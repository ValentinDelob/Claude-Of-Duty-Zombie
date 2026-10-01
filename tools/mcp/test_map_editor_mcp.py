"""Tests du pont MCP de l'éditeur de cartes (unittest, bibliothèque standard).

Un FAUX ÉDITEUR (serveur TCP dans un thread) implémente le protocole agent ↔
éditeur (§ 5.2 de la spécification) sur une petite carte en mémoire ; le
serveur MCP tourne en sous-processus et on lui parle en JSON-RPC sur stdio,
comme Claude Code.

Lancer : py -m unittest tools/mcp/test_map_editor_mcp.py
"""

from __future__ import annotations

import base64
import copy
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "map_editor_mcp.py")
sys.path.insert(0, HERE)
import map_editor_mcp  # noqa: E402
import map_geom  # noqa: E402

TOKEN = "jeton-de-test-123"

SMALL_MAP = {
    "carte": {"format": 8, "id": "essai", "nom": {"fr": "ESSAI", "en": "TEST"},
              "etages": [{"sol": 0, "hauteur": 3.2}]},
    "pieces": [
        {"id": "p1", "nom": "Entrée", "etage": 0, "zone": "z1", "contour": [[0, 0], [10, 0], [10, 8], [0, 8]]},
        {"id": "p2", "nom": "Atelier", "etage": 0, "zone": "z2", "contour": [[10, 0], [18, 0], [18, 8], [10, 8]]},
        {"id": "p3", "nom": "Cave", "etage": 0, "zone": "z3", "contour": [[24, 1], [32, 1], [32, 9], [24, 9]]},
    ],
    "ouvertures": [
        {"id": "o1", "type": "porte", "etage": 0, "position": [10, 4], "largeur": 2, "prix": 750},
        {"id": "o2", "type": "fenetre", "etage": 0, "position": [5, 0]},
    ],
    "objets": [
        {"id": "s1", "type": "depart", "etage": 0, "position": [5, 4]},
        {"id": "a1", "type": "atout", "atout": "lazarus", "etage": 0, "position": [2, 8], "mur": "s"},
    ],
    "zones": [
        {"id": "z1", "nom": {"fr": "Entrée", "en": "Entrance"}},
        {"id": "z2", "nom": {"fr": "Atelier", "en": "Workshop"}},
        {"id": "z3", "nom": {"fr": "Cave", "en": "Cellar"}},
    ],
    "depart": "z1",
}


def tiny_png() -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\x80\x40\xc0")) + chunk(b"IEND", b""))


class FakeEditor:
    """Éditeur factice : écoute agent locale, jeton, commandes § 5.2."""

    PREFIX = {"atout": "a", "arme": "w", "boite": "b", "depart": "s", "escalier": "e", "pilier": "x", "mur": "m",
              "piege": "t", "levier": "l", "prefab": "d", "luminaire": "lu", "bloc_invisible": "i"}

    def __init__(self, tmpdir: str) -> None:
        self.doc = copy.deepcopy(SMALL_MAP)
        self.history: list[tuple[str, dict]] = []
        self.hellos = 0
        self.commands: list[str] = []
        self.clients: list[socket.socket] = []
        self.lock = threading.Lock()
        self.srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.srv.bind(("127.0.0.1", 0))
        self.srv.listen()
        self.port = self.srv.getsockname()[1]
        self.agent_json = os.path.join(tmpdir, "agent.json")
        self.write_agent_json(TOKEN)
        threading.Thread(target=self._accept, daemon=True).start()

    def write_agent_json(self, token: str, port: int | None = None) -> None:
        with open(self.agent_json, "w", encoding="utf-8") as f:
            json.dump({"port": port or self.port, "token": token, "pid": os.getpid(), "map_id": "essai"}, f)

    def stop(self) -> None:
        self.drop_clients()
        self.srv.close()

    def drop_clients(self) -> None:
        with self.lock:
            for c in self.clients:
                try:
                    c.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                c.close()
            self.clients.clear()

    def _accept(self) -> None:
        while True:
            try:
                c, _ = self.srv.accept()
            except OSError:
                return
            with self.lock:
                self.clients.append(c)
            threading.Thread(target=self._serve, args=(c,), daemon=True).start()

    def _send(self, c: socket.socket, msg: dict) -> None:
        try:
            c.sendall((json.dumps(msg) + "\n").encode("utf-8"))
        except OSError:
            pass

    def _serve(self, c: socket.socket) -> None:
        f = c.makefile("rb")
        authed = False
        try:
            for line in f:
                req = json.loads(line)
                rid, cmd, args = req.get("id"), req.get("cmd"), req.get("args") or {}
                self.commands.append(cmd)
                if not authed:
                    if cmd != "hello" or args.get("token") != TOKEN:
                        self._send(c, {"id": rid, "ok": False, "error": "jeton invalide"})
                        break
                    authed = True
                    self.hellos += 1
                try:
                    res = self.run(cmd, args)
                    self._send(c, {"id": rid, "ok": True, "result": res})
                    if cmd == "apply":
                        self._send(c, {"event": "change", "author": "1:claude", "label": args.get("label")})
                except ValueError as e:
                    self._send(c, {"id": rid, "ok": False, "error": str(e)})
        except (OSError, ValueError):
            pass
        finally:
            f.close()
            try:
                c.close()
            except OSError:
                pass

    def info(self) -> dict:
        return {"map_id": "essai", "map_name": "ESSAI", "role": "solo", "peers": [], "editor_version": "test"}

    def run(self, cmd: str, args: dict):
        if cmd == "hello":
            return self.info()
        if cmd == "status":
            return {**self.info(), "floor": 0, "selection": ["p2"], "dirty": bool(self.history)}
        if cmd == "get_map":
            return copy.deepcopy(self.doc)
        if cmd == "get_selection":
            return {"ids": ["p2"], "elements": [self.doc["pieces"][1]], "floor": 0, "cursor": [14.0, 4.0]}
        if cmd == "apply":
            return self.apply(args)
        if cmd == "undo":
            if not self.history:
                raise ValueError("rien à annuler")
            label, before = self.history.pop()
            self.doc = before
            return {"undone": label}
        if cmd == "validate":
            return {"text": "1 avertissement", "problems": [{"level": "warning", "fr": "impasse", "pos": [5, 4]}]}
        if cmd == "screenshot":
            return {"png_base64": base64.b64encode(tiny_png()).decode(), "width": 1, "height": 1,
                    "bounds": [0, 0, 32, 9], "floor": args.get("floor", 0)}
        if cmd == "highlight":
            return {"shown": args.get("ids"), "message": args.get("message")}
        if cmd == "catalog":
            return {"types": ["porte", "fenetre", "atout"], "atouts": ["lazarus", "titan"]}
        raise ValueError("commande inconnue : %s" % cmd)

    def new_id(self, prefix: str, used: set) -> str:
        n = 1
        while "%s%d" % (prefix, n) in used:
            n += 1
        used.add("%s%d" % (prefix, n))
        return "%s%d" % (prefix, n)

    def apply(self, args: dict) -> dict:
        ops = copy.deepcopy(args.get("ops"))
        used = {e["id"] for coll in map_editor_mcp.COLLS for e in self.doc[coll]}
        ids: dict[str, str] = {}
        for op in ops:
            if op.get("op") == "add":
                el = op["el"]
                coll = op["coll"]
                prefix = {"pieces": "p", "ouvertures": "o", "zones": "z"}.get(coll) or self.PREFIX.get(el.get("type"), "x")
                real = self.new_id(prefix, used)
                if isinstance(el.get("id"), str) and el["id"].startswith("$"):
                    ids[el["id"]] = real
                else:
                    ids["$auto%d" % len(ids)] = real
                el["id"] = real
                op["op"] = "put"

        def subst(v):
            if isinstance(v, str) and v in ids:
                return ids[v]
            if isinstance(v, dict):
                return {k: subst(x) for k, x in v.items()}
            if isinstance(v, list):
                return [subst(x) for x in v]
            return v
        ops = subst(ops)
        before = copy.deepcopy(self.doc)
        for op in ops:
            if op["op"] == "put":
                lst = self.doc[op["coll"]]
                for i, e in enumerate(lst):
                    if e["id"] == op["el"]["id"]:
                        lst[i] = op["el"]
                        break
                else:
                    lst.append(op["el"])
            elif op["op"] == "del":
                self.doc[op["coll"]] = [e for e in self.doc[op["coll"]] if e["id"] != op["id"]]
            elif op["op"] == "carte":
                self.doc["carte"] = op["carte"]
            elif op["op"] == "depart":
                self.doc["depart"] = op["id"]
        self.history.append((args.get("label"), before))
        return {"cid": "1-%d" % len(self.history), "ids": {k: v for k, v in ids.items() if not k.startswith("$auto")},
                "invalid": {}}


class McpProcess:
    """Le serveur MCP en sous-processus, piloté en JSON-RPC sur stdio."""

    def __init__(self, agent_json: str) -> None:
        env = dict(os.environ, CLAUDE_MAP_EDITOR_AGENT_JSON=agent_json, CLAUDE_MAP_EDITOR_TIMEOUT="5",
                   PYTHONIOENCODING="utf-8")
        self.p = subprocess.Popen([sys.executable, SERVER], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, env=env,
                                  creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        self.n = 0
        # stderr lu en continu (jamais de blocage sur un tube plein).
        self.stderr: list[bytes] = []
        self.err_thread = threading.Thread(target=lambda: self.stderr.extend(self.p.stderr), daemon=True)
        self.err_thread.start()

    def send(self, msg: dict) -> None:
        self.p.stdin.write((json.dumps(msg) + "\n").encode("utf-8"))
        self.p.stdin.flush()

    def rpc(self, method: str, params: dict | None = None) -> dict:
        self.n += 1
        self.send({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}})
        line = self.p.stdout.readline()
        if not line:
            raise AssertionError("le serveur MCP s'est arrêté : " + b"".join(self.stderr).decode("utf-8", "replace"))
        msg = json.loads(line)
        assert msg.get("id") == self.n, msg
        return msg

    def init(self, version: str = "2025-06-18") -> dict:
        r = self.rpc("initialize", {"protocolVersion": version, "capabilities": {},
                                    "clientInfo": {"name": "test", "version": "0"}})
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return r

    def call(self, name: str, args: dict | None = None) -> dict:
        return self.rpc("tools/call", {"name": name, "arguments": args or {}})["result"]

    def close(self) -> None:
        try:
            self.p.stdin.close()
            self.p.wait(5)
        except (OSError, subprocess.TimeoutExpired):
            self.p.kill()
        self.p.stdout.close()
        self.err_thread.join(2)
        self.p.stderr.close()


def body(result: dict):
    """Premier contenu texte d'un résultat d'outil, décodé si c'est du JSON."""
    t = next(c["text"] for c in result["content"] if c["type"] == "text")
    try:
        return json.loads(t)
    except ValueError:
        return t


class BaseCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.editor = FakeEditor(self.tmp.name)
        self.mcp = McpProcess(self.editor.agent_json)

    def tearDown(self) -> None:
        self.mcp.close()
        self.editor.stop()
        self.tmp.cleanup()


class TestProtocol(BaseCase):
    def test_handshake_versions_ping_list(self):
        r = self.mcp.init("2025-06-18")["result"]
        self.assertEqual(r["protocolVersion"], "2025-06-18")
        self.assertIn("tools", r["capabilities"])
        self.assertEqual(r["serverInfo"]["name"], "map-editor")
        self.assertIn("editor_apply", r["instructions"])
        self.assertIn("MAP_DESIGN_RULES", r["instructions"])
        self.assertEqual(self.mcp.rpc("initialize", {"protocolVersion": "2024-11-05"})["result"]["protocolVersion"], "2024-11-05")
        self.assertEqual(self.mcp.rpc("initialize", {"protocolVersion": "2099-01-01"})["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual(self.mcp.rpc("ping")["result"], {})
        tools = self.mcp.rpc("tools/list")["result"]["tools"]
        names = {t["name"] for t in tools}
        self.assertEqual(names, {"editor_status", "editor_get_map", "editor_get_element", "editor_get_selection",
                                 "editor_apply", "editor_undo_last", "editor_validate", "editor_screenshot",
                                 "editor_highlight", "editor_catalog", "editor_events", "editor_plan_corridor"})
        for t in tools:
            self.assertEqual(t["inputSchema"]["type"], "object")
            self.assertTrue(t["description"])
        self.assertEqual(self.mcp.rpc("nope/nope")["error"]["code"], -32601)
        # Ligne illisible : erreur JSON-RPC, le serveur continue.
        self.mcp.p.stdin.write(b"{pas du json\n")
        self.mcp.p.stdin.flush()
        self.assertEqual(json.loads(self.mcp.p.stdout.readline())["error"]["code"], -32700)
        self.assertEqual(self.mcp.rpc("ping")["result"], {})

    def test_unknown_tool_is_error(self):
        self.mcp.init()
        r = self.mcp.call("editor_nope")
        self.assertTrue(r["isError"])


class TestTools(BaseCase):
    def setUp(self) -> None:
        super().setUp()
        self.mcp.init()

    def test_status_selection_catalog_validate_highlight(self):
        st = self.mcp.call("editor_status")
        self.assertFalse(st["isError"], st)
        self.assertEqual(body(st)["role"], "solo")
        sel = body(self.mcp.call("editor_get_selection"))
        self.assertEqual(sel["ids"], ["p2"])
        self.assertIn("lazarus", body(self.mcp.call("editor_catalog"))["atouts"])
        self.assertEqual(body(self.mcp.call("editor_validate"))["problems"][0]["level"], "warning")
        h = body(self.mcp.call("editor_highlight", {"ids": ["p1"], "message": "Ici ?"}))
        self.assertEqual(h["shown"], ["p1"])
        self.assertTrue(self.mcp.call("editor_highlight", {"ids": "p1"})["isError"])
        self.assertEqual(self.editor.hellos, 1)  # une seule connexion pour tous les appels

    def test_get_map_summary_full_element(self):
        s = body(self.mcp.call("editor_get_map"))
        f0 = s["etages"][0]
        p1 = next(p for p in f0["pieces"] if p["id"] == "p1")
        self.assertEqual(p1["bbox"], [0, 0, 10, 8])
        self.assertEqual(p1["surface"], 80)
        self.assertEqual(p1["voisins"][0]["id"], "p2")
        p2 = next(p for p in f0["pieces"] if p["id"] == "p2")
        self.assertEqual(p2["proches"][0]["id"], "p3")
        self.assertEqual(p2["proches"][0]["distance"], 6)
        o1 = next(o for o in f0["ouvertures"] if o["id"] == "o1")
        self.assertEqual(sorted(o1["pieces"]), ["p1", "p2"])
        self.assertEqual(o1["prix"], 750)
        self.assertEqual(f0["objets"]["atout"][0]["atout"], "lazarus")
        self.assertTrue(next(z for z in s["zones"] if z["id"] == "z1")["depart"])
        full = body(self.mcp.call("editor_get_map", {"format": "full"}))
        self.assertEqual(full, SMALL_MAP)
        el = body(self.mcp.call("editor_get_element", {"ids": ["o1", "zz"]}))
        self.assertEqual(el["elements"]["o1"]["coll"], "ouvertures")
        self.assertEqual(el["absents"], ["zz"])
        self.assertTrue(self.mcp.call("editor_get_map", {"format": "xml"})["isError"])

    def test_apply_events_undo(self):
        r = self.mcp.call("editor_apply", {"label": "Claude : cave", "ops": [
            {"op": "add", "coll": "zones", "el": {"id": "$1", "nom": {"fr": "Réserve", "en": "Storage"}}},
            {"op": "add", "coll": "pieces", "el": {"id": "$2", "nom": "Réserve", "etage": 0, "zone": "$1",
                                                    "contour": [[0, 8], [10, 8], [10, 14], [0, 14]]}},
            {"op": "add", "coll": "ouvertures", "el": {"type": "passage", "etage": 0, "position": [5, 8], "largeur": 2}},
        ]})
        self.assertFalse(r["isError"], r)
        res = body(r)
        self.assertEqual(res["ids"], {"$1": "z4", "$2": "p4"})
        self.assertEqual(self.editor.doc["pieces"][-1]["zone"], "z4")
        self.assertEqual(self.editor.doc["ouvertures"][-1]["id"], "o3")
        # L'événement poussé par l'éditeur est gardé.
        deadline = time.time() + 2
        evs = {}
        while time.time() < deadline:
            evs = body(self.mcp.call("editor_events"))
            if isinstance(evs, dict):
                break
            time.sleep(0.02)
        self.assertEqual(evs["events"][-1]["label"], "Claude : cave")
        u = self.mcp.call("editor_undo_last")
        self.assertFalse(u["isError"])
        self.assertEqual(len(self.editor.doc["pieces"]), 3)
        self.assertTrue(self.mcp.call("editor_undo_last")["isError"])  # erreur de l'éditeur relayée

    def test_apply_rejected_locally(self):
        for ops, needle in (([{"op": "put", "coll": "pieces", "el": {"nom": "x"}}], "add"),
                            ([{"op": "add", "coll": "trucs", "el": {}}], "coll"),
                            ([{"op": "add", "coll": "pieces", "el": {"id": "p9"}}], "provisoire"),
                            ([{"op": "boum"}], "inconnue"),
                            ([], "non vide")):
            r = self.mcp.call("editor_apply", {"label": "x", "ops": ops})
            self.assertTrue(r["isError"], ops)
            self.assertIn(needle, body(r))
        self.assertTrue(self.mcp.call("editor_apply", {"label": " ", "ops": [{"op": "depart", "id": "z1"}]})["isError"])
        self.assertNotIn("apply", self.editor.commands)

    def test_screenshot(self):
        r = self.mcp.call("editor_screenshot", {"floor": 0, "ids": ["p1"]})
        self.assertFalse(r["isError"], r)
        img = next(c for c in r["content"] if c["type"] == "image")
        self.assertEqual(img["mimeType"], "image/png")
        self.assertTrue(base64.b64decode(img["data"]).startswith(b"\x89PNG"))
        self.assertEqual(body(r)["bounds"], [0, 0, 32, 9])

    def test_plan_corridor(self):
        r = body(self.mcp.call("editor_plan_corridor", {"room_a": "p2", "room_b": "p3", "width": 2.5}))
        self.assertEqual(r["type"], "droit")
        room = r["ops"][0]["el"]
        self.assertEqual(room["zone"], "z2")
        x0, y0, x1, y1 = map_geom.bbox(map_geom.pts(room["contour"]))
        self.assertEqual((x0, x1), (18, 24))
        self.assertAlmostEqual(y1 - y0, 2.5)
        self.assertEqual(r["ops"][2]["el"]["type"], "porte")
        # Rien n'a été appliqué.
        self.assertNotIn("apply", self.editor.commands)
        # Les ops proposées passent telles quelles.
        self.assertFalse(self.mcp.call("editor_apply", {"label": r["label"], "ops": r["ops"]})["isError"])
        e = self.mcp.call("editor_plan_corridor", {"room_a": "p1", "room_b": "p2"})
        self.assertTrue(e["isError"])
        self.assertIn("déjà reliées", body(e))

    def test_plan_corridor_by_name(self):
        # Nom de pièce au lieu de l'id : casse et accents ignorés.
        by_id = body(self.mcp.call("editor_plan_corridor", {"room_a": "p2", "room_b": "p3"}))
        by_name = body(self.mcp.call("editor_plan_corridor", {"room_a": "atelier", "room_b": "CAVE"}))
        self.assertEqual(by_name["ops"], by_id["ops"])
        e = self.mcp.call("editor_plan_corridor", {"room_a": "entree", "room_b": "Atelier"})
        self.assertTrue(e["isError"])
        self.assertIn("déjà reliées", body(e))
        e = self.mcp.call("editor_plan_corridor", {"room_a": "Grenier", "room_b": "p3"})
        self.assertTrue(e["isError"])
        self.assertIn("inconnue", body(e))


class TestConnection(BaseCase):
    def test_editor_absent(self):
        self.mcp.close()
        self.mcp = McpProcess(os.path.join(self.tmp.name, "absent", "agent.json"))
        self.mcp.init()
        r = self.mcp.call("editor_status")
        self.assertTrue(r["isError"])
        self.assertIn("Ouvre l'éditeur de cartes du jeu", body(r))
        # agent.json resté d'une session fermée : port fermé.
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        dead = s.getsockname()[1]
        s.close()
        self.editor.write_agent_json(TOKEN, port=dead)
        self.mcp.close()
        self.mcp = McpProcess(self.editor.agent_json)
        self.mcp.init()
        r = self.mcp.call("editor_get_map")
        self.assertTrue(r["isError"])
        self.assertIn("Ouvre l'éditeur", body(r))
        # L'éditeur s'ouvre ensuite : l'appel suivant se connecte.
        self.editor.write_agent_json(TOKEN)
        self.assertFalse(self.mcp.call("editor_status")["isError"])

    def test_bad_token(self):
        self.editor.write_agent_json("mauvais")
        self.mcp.init()
        r = self.mcp.call("editor_status")
        self.assertTrue(r["isError"])
        self.assertIn("refusé", body(r))
        self.assertEqual(self.editor.hellos, 0)

    def test_reconnect(self):
        self.mcp.init()
        self.assertFalse(self.mcp.call("editor_status")["isError"])
        self.editor.drop_clients()
        time.sleep(0.2)
        r = self.mcp.call("editor_status")
        self.assertFalse(r["isError"], r)
        self.assertEqual(self.editor.hellos, 2)
        # Coupure juste avant une modification : nouvelle connexion, appliquée une fois.
        self.editor.drop_clients()
        time.sleep(0.2)
        r = self.mcp.call("editor_apply", {"label": "x", "ops": [{"op": "depart", "id": "z2"}]})
        self.assertFalse(r["isError"], r)
        self.assertEqual(self.editor.doc["depart"], "z2")
        self.assertEqual(self.editor.commands.count("apply"), 1)


class TestPure(unittest.TestCase):
    def test_geometry(self):
        a = map_geom.pts([[0, 0], [10, 0], [10, 8], [0, 8]])
        b = map_geom.pts([[10, 2], [14, 2], [14, 6], [10, 6]])
        c = map_geom.pts([[13, 0], [20, 0], [20, 3], [13, 3]])
        self.assertEqual(map_geom.bbox(a), [0, 0, 10, 8])
        self.assertEqual(map_geom.area(a), 80)
        self.assertTrue(map_geom.is_axis_rect(a))
        self.assertEqual(map_geom.common_segments(a, b), [[(10.0, 2.0), (10.0, 6.0)]])
        self.assertFalse(map_geom.polys_overlap(a, b))
        self.assertTrue(map_geom.polys_overlap(b, c))
        self.assertTrue(map_geom.polys_overlap(a, a))
        d, pa, pb = map_geom.closest_points(a, map_geom.pts([[15, 10], [18, 10], [18, 12], [15, 12]]))
        self.assertAlmostEqual(d, ((15 - 10) ** 2 + (10 - 8) ** 2) ** 0.5)
        self.assertEqual((pa, pb), ((10.0, 8.0), (15.0, 10.0)))
        self.assertEqual(map_geom.nearest_edge_point(a, b), (10.0, 2.0))

    def test_l_corridor(self):
        doc = {"pieces": [
            {"id": "p1", "etage": 0, "zone": "z1", "contour": [[0, 0], [8, 0], [8, 8], [0, 8]]},
            {"id": "p2", "etage": 0, "zone": "z2", "contour": [[16, 14], [24, 14], [24, 22], [16, 22]]},
        ], "ouvertures": [], "objets": []}
        plan = map_geom.plan_corridor(doc, "p1", "p2", 2)
        self.assertEqual(plan["type"], "en_L")
        poly = map_geom.pts(plan["ops"][0]["el"]["contour"])
        self.assertEqual(len(poly), 6)
        self.assertAlmostEqual(map_geom.area(poly), sum(plan["longueurs"]) * 2 - 4, places=3)
        self.assertEqual(plan["ops"][2]["el"]["prix"], 750)
        doc["pieces"][1]["etage"] = 1
        with self.assertRaises(map_geom.PlanError):
            map_geom.plan_corridor(doc, "p1", "p2")

    def test_resolve_room(self):
        doc = {"pieces": [
            {"id": "p1", "nom": "Salle Électrique", "contour": []},
            {"id": "p2", "nom": {"fr": "Théâtre", "en": "Theater"}, "contour": []},
            {"id": "p3", "nom": "Cave", "contour": []},
            {"id": "p4", "nom": "cave", "contour": []},
        ]}
        self.assertEqual(map_geom.resolve_room(doc, "p3"), "p3")
        self.assertEqual(map_geom.resolve_room(doc, "salle  electrique"), "p1")
        self.assertEqual(map_geom.resolve_room(doc, "THEATRE"), "p2")
        self.assertEqual(map_geom.resolve_room(doc, "theater"), "p2")
        with self.assertRaises(map_geom.PlanError):
            map_geom.resolve_room(doc, "Cave")  # ambigu
        with self.assertRaises(map_geom.PlanError):
            map_geom.resolve_room(doc, "")

    def test_check_ops(self):
        self.assertEqual(map_editor_mcp.check_ops([{"op": "del", "coll": "objets", "id": "a1"}]), "")
        self.assertIn("non fini", map_editor_mcp.check_ops([{"op": "put", "coll": "objets",
                                                              "el": {"id": "a", "position": [float("nan"), 0]}}]))
        deep = {"id": "a"}
        cur = deep
        for _ in range(10):
            cur["k"] = {}
            cur = cur["k"]
        self.assertIn("profond", map_editor_mcp.check_ops([{"op": "put", "coll": "objets", "el": deep}]))


if __name__ == "__main__":
    unittest.main()
