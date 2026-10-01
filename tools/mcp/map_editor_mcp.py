#!/usr/bin/env python3
"""Serveur MCP (stdio) qui relie Claude Code à l'éditeur de cartes du jeu
« Claude of Duty Zombie », en direct.

Bibliothèque standard uniquement (Python 3.13, rien à installer). Protocole :
JSON-RPC 2.0 MCP sur stdin/stdout, une ligne JSON par message ; logs sur
stderr seulement (stdout est réservé au protocole).

Côté éditeur (spécification « Éditeur de cartes collaboratif », § 5.2) :
l'éditeur ouvert écoute sur 127.0.0.1 (port 7791 à 7799) et écrit le port et un
jeton dans user://editor_collab/agent.json ; on s'y connecte en TCP, une ligne
JSON par message, requêtes {id, cmd, args}, réponses {id, ok, result | error},
événements poussés {event: ...}. Première requête : hello avec le jeton.
"""

from __future__ import annotations

import base64
import collections
import itertools
import json
import math
import os
import socket
import sys
import threading
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import map_geom  # noqa: E402

SERVER_NAME = "map-editor"
SERVER_VERSION = "1.0.0"
SUPPORTED_PROTOCOLS = ["2025-06-18", "2025-03-26", "2024-11-05", "2024-10-07"]
LATEST_PROTOCOL = SUPPORTED_PROTOCOLS[0]

MAX_LINE = 2 * 1024 * 1024 + 1024  # messages ≤ 2 Mo (§ 5)
MAX_OPS = 5000
MAX_DEPTH = 8
MAX_ID_LEN = 64
COLLS = ("pieces", "ouvertures", "objets", "zones")
CONNECT_TIMEOUT = 3.0
REQUEST_TIMEOUT = float(os.environ.get("CLAUDE_MAP_EDITOR_TIMEOUT", "30"))
# Commandes sans effet sur la carte : on peut les renvoyer après une reconnexion.
SAFE_CMDS = {"hello", "status", "get_map", "get_selection", "validate", "screenshot", "catalog", "highlight"}

OPEN_EDITOR_FR = "Ouvre l'éditeur de cartes du jeu (Collaboration > Autoriser Claude coché)"

INSTRUCTIONS = """Pilote en direct l'éditeur de cartes de Claude of Duty Zombie (clone de BO1 Zombies).
- Commence toujours par editor_status puis editor_get_map (résumé) et editor_get_selection : ce que l'utilisateur a sélectionné est souvent l'objet de sa demande. editor_get_element donne les éléments complets avant de les modifier.
- Unités en mètres, x vers l'est, y vers le sud ; « etage » = indice d'étage (0 = rez-de-chaussée). Format des éléments : docs/MAP_AUTHORING.md (§ Format des fichiers).
- editor_apply : un lot d'opérations (put / del / carte / depart / add). Pour créer, utilise « add » sans id ou avec un id provisoire "$1", "$2"… réutilisable dans le même lot (ex. zone d'une pièce) ; pour modifier, « put » de l'élément complet relu avant. Un appel editor_apply = UNE étape d'annulation (un Ctrl+Z) pour l'utilisateur : regroupe ce qui va ensemble, sépare ce qui est indépendant. Donne toujours un « label » clair en français (« Couloir entre l'entrée et l'atelier »).
- Après chaque modification : editor_validate (erreurs bloquantes à corriger) et editor_screenshot pour voir le résultat ; editor_highlight pour montrer à l'utilisateur ce dont tu parles. editor_undo_last annule ta dernière action.
- Respecte docs/MAP_DESIGN_RULES.md (surface vide < 15 m², couloirs 2-3 m et 12 m max en ligne droite, boucles, fenêtres, prix des portes, décor) et l'esprit de BO1 Zombies.
- L'utilisateur (et d'autres participants) éditent en même temps : relis la carte avant de modifier un élément, ne refais pas ce qu'il vient de défaire."""


def log(*args) -> None:
    print("[map-editor-mcp]", *args, file=sys.stderr, flush=True)


class EditorError(Exception):
    """Erreur montrée telle quelle à Claude (résultat d'outil isError)."""


# ------------------------------------------------------------------ lien avec l'éditeur

def agent_json_path() -> str:
    forced = os.environ.get("CLAUDE_MAP_EDITOR_AGENT_JSON")
    if forced:
        return forced
    appdata = os.environ.get("APPDATA")
    if appdata:
        base = os.path.join(appdata, "Godot", "app_userdata")
    else:  # Linux / macOS (Godot : ~/.local/share/godot)
        base = os.path.join(os.path.expanduser("~"), ".local", "share", "godot", "app_userdata")
    return os.path.join(base, "Call of Claude Zombie", "editor_collab", "agent.json")


class EditorLink:
    """Connexion TCP à l'éditeur local, rouverte à la demande."""

    def __init__(self) -> None:
        self.sock: socket.socket | None = None
        self.reader: threading.Thread | None = None
        self.lock = threading.Lock()          # envoi + table des requêtes
        self.pending: dict[int, dict] = {}    # id -> {"event": Event, "msg": dict | None}
        self.ids = itertools.count(1)
        self.events: collections.deque = collections.deque(maxlen=100)
        self.info: dict = {}
        self.alive = False
        self.connections = 0

    # --- connexion

    def _read_agent_json(self) -> dict:
        path = agent_json_path()
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except FileNotFoundError:
            raise EditorError("Éditeur de cartes introuvable : %s. (fichier absent : %s)" % (OPEN_EDITOR_FR, path))
        except (OSError, ValueError) as e:
            raise EditorError("agent.json illisible (%s) : %s. %s" % (path, e, OPEN_EDITOR_FR))
        if not isinstance(data, dict) or not isinstance(data.get("port"), int) or not data.get("token"):
            raise EditorError("agent.json incomplet (port / token manquants) : %s. %s" % (path, OPEN_EDITOR_FR))
        return data

    def _connect(self) -> None:
        self.close()
        data = self._read_agent_json()
        port = int(data["port"])
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=CONNECT_TIMEOUT)
        except OSError as e:
            raise EditorError("Impossible de joindre l'éditeur sur 127.0.0.1:%d (%s). %s. "
                              "(agent.json est peut-être resté d'une session fermée.)" % (port, e, OPEN_EDITOR_FR))
        sock.settimeout(None)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.sock = sock
        self.alive = True
        self.connections += 1
        self.reader = threading.Thread(target=self._read_loop, args=(sock,), daemon=True)
        self.reader.start()
        try:
            info = self._request_raw("hello", {"token": str(data["token"]), "client": "claude-mcp"}, CONNECT_TIMEOUT + 2)
        except EditorError as e:
            self.close()
            raise EditorError("L'éditeur a refusé la connexion : %s. (Jeton périmé ? Rouvre l'éditeur, puis réessaie.)" % e)
        except ConnectionError as e:
            self.close()
            raise EditorError("L'éditeur a fermé la connexion pendant la poignée de main (%s). %s" % (e, OPEN_EDITOR_FR))
        self.info = info if isinstance(info, dict) else {}
        self.info["agent_json"] = {"port": port, "map_id": data.get("map_id"), "pid": data.get("pid")}
        log("connecté à l'éditeur, port", port)

    def close(self) -> None:
        sock, self.sock = self.sock, None
        self.alive = False
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                sock.close()
            except OSError:
                pass
        self._fail_pending("connexion fermée")

    def _fail_pending(self, why: str) -> None:
        with self.lock:
            for p in self.pending.values():
                if p["msg"] is None:
                    p["msg"] = {"ok": False, "error": why, "_lost": True}
                    p["event"].set()

    def _read_loop(self, sock: socket.socket) -> None:
        buf = b""
        try:
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    self._on_line(line)
                if len(buf) > MAX_LINE:
                    log("message trop long de l'éditeur : déconnexion")
                    break
        except OSError:
            pass
        finally:
            if self.sock is sock:
                self.alive = False
                self._fail_pending("connexion perdue avec l'éditeur")
            log("connexion à l'éditeur fermée")

    def _on_line(self, line: bytes) -> None:
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            log("ligne illisible de l'éditeur ignorée")
            return
        if not isinstance(msg, dict):
            return
        if "event" in msg and "id" not in msg:
            self.events.append({"time": time.strftime("%H:%M:%S"), **msg})
            return
        with self.lock:
            p = self.pending.get(msg.get("id"))
            if p is not None and p["msg"] is None:
                p["msg"] = msg
                p["event"].set()

    # --- requêtes

    def _request_raw(self, cmd: str, args: dict, timeout: float):
        sock = self.sock
        if sock is None or not self.alive:
            raise EditorError("connexion perdue avec l'éditeur")
        rid = next(self.ids)
        entry = {"event": threading.Event(), "msg": None}
        data = (json.dumps({"id": rid, "cmd": cmd, "args": args}, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")
        with self.lock:
            self.pending[rid] = entry
        try:
            try:
                sock.sendall(data)
            except OSError as e:
                self.alive = False
                raise ConnectionError(str(e))
            if not entry["event"].wait(timeout):
                raise EditorError("l'éditeur n'a pas répondu à « %s » en %.0f s" % (cmd, timeout))
        finally:
            with self.lock:
                self.pending.pop(rid, None)
        msg = entry["msg"]
        if msg.get("_lost"):
            raise ConnectionError(str(msg.get("error")))
        if msg.get("ok") is True:
            return msg.get("result")
        err = msg.get("error")
        if isinstance(err, dict):
            err = err.get("fr") or err.get("message") or json.dumps(err, ensure_ascii=False)
        raise EditorError(str(err or "erreur inconnue de l'éditeur"))

    def request(self, cmd: str, args: dict | None = None, timeout: float = REQUEST_TIMEOUT):
        """Requête à l'éditeur ; (re)connexion automatique. Une commande qui
        modifie la carte n'est jamais renvoyée en double après une coupure."""
        args = args or {}
        if self.sock is None or not self.alive:
            self._connect()
        try:
            return self._request_raw(cmd, args, timeout)
        except ConnectionError as e:
            self.close()
            if cmd not in SAFE_CMDS:
                raise EditorError("connexion perdue avec l'éditeur pendant « %s » (%s) : vérifie avec editor_get_map "
                                  "si la modification a été faite avant de recommencer." % (cmd, e))
            self._connect()
            try:
                return self._request_raw(cmd, args, timeout)
            except ConnectionError as e2:
                self.close()
                raise EditorError("connexion perdue avec l'éditeur (%s). %s" % (e2, OPEN_EDITOR_FR))


# ------------------------------------------------------------------ contrôle des opérations (§ 2)

def _depth(v, d: int = 1) -> int:
    if isinstance(v, dict):
        return max([d] + [_depth(x, d + 1) for x in v.values()])
    if isinstance(v, list):
        return max([d] + [_depth(x, d + 1) for x in v])
    return d


def _finite(v) -> bool:
    if isinstance(v, float):
        return math.isfinite(v)
    if isinstance(v, dict):
        return all(_finite(x) for x in v.values())
    if isinstance(v, list):
        return all(_finite(x) for x in v)
    return True


def check_ops(ops) -> str:
    """Contrôle local d'un lot (avant envoi) ; "" si valide. Reprend
    MapOps.validate (§ 2) pour donner une erreur claire sans aller-retour."""
    if not isinstance(ops, list) or not ops:
        return "ops doit être une liste non vide d'opérations"
    if len(ops) > MAX_OPS:
        return "trop d'opérations (%d, %d au plus par lot)" % (len(ops), MAX_OPS)
    for i, op in enumerate(ops):
        where = "ops[%d]" % i
        if not isinstance(op, dict):
            return "%s : une opération est un objet JSON" % where
        kind = op.get("op")
        if kind in ("put", "add", "del") and op.get("coll") not in COLLS:
            return "%s : coll doit être l'une de %s" % (where, ", ".join(COLLS))
        if kind == "put":
            el = op.get("el")
            if not isinstance(el, dict):
                return "%s : put demande « el » (l'élément complet)" % where
            eid = el.get("id")
            if not isinstance(eid, str) or not eid or len(eid) > MAX_ID_LEN:
                return "%s : put demande un el.id texte de 1 à %d caractères (pour créer, utilise « add »)" % (where, MAX_ID_LEN)
        elif kind == "add":
            el = op.get("el")
            if not isinstance(el, dict):
                return "%s : add demande « el »" % where
            eid = el.get("id")
            if eid is not None and not (isinstance(eid, str) and eid.startswith("$") and eid[1:].isdigit()):
                return "%s : add : el.id absent ou provisoire (\"$1\", \"$2\"…), l'éditeur attribue le vrai id" % where
        elif kind == "del":
            if not isinstance(op.get("id"), str) or not op.get("id"):
                return "%s : del demande « id »" % where
        elif kind == "carte":
            if not isinstance(op.get("carte"), dict):
                return "%s : carte demande « carte » (le dictionnaire carte complet)" % where
        elif kind == "depart":
            if not isinstance(op.get("id"), str):
                return "%s : depart demande « id » (id de zone)" % where
        else:
            return "%s : op inconnue %r (put, add, del, carte, depart)" % (where, kind)
        if _depth(op) > MAX_DEPTH:
            return "%s : trop profond (%d niveaux au plus)" % (where, MAX_DEPTH)
        if not _finite(op):
            return "%s : nombre non fini (NaN ou infini)" % where
    try:
        size = len(json.dumps(ops, ensure_ascii=False, allow_nan=False).encode("utf-8"))
    except ValueError:
        return "nombre non fini dans les ops"
    if size > 2 * 1024 * 1024 - 4096:
        return "lot trop gros (%d octets, 2 Mo au plus par message)" % size
    return ""


# ------------------------------------------------------------------ outils MCP

def _ids_schema(desc: str) -> dict:
    return {"type": "array", "items": {"type": "string"}, "description": desc}


TOOLS = [
    {
        "name": "editor_status",
        "description": "État de l'éditeur de cartes ouvert : carte (id, nom), rôle (solo / hôte / invité), participants, "
                       "étage affiché, sélection, modifications non enregistrées. À appeler en premier.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "editor_get_map",
        "description": "Lit la carte ouverte. format \"summary\" (défaut) : résumé calculé pour raisonner — par étage, pièces "
                       "(id, nom, zone, bbox [x0,y0,x1,y1] en m, surface m², contour si non rectangulaire, voisines par mur "
                       "commun avec le bord partagé, pièces proches non collées avec les points les plus proches), "
                       "ouvertures (type, position, largeur, prix, pièces reliées), objets regroupés par type (id, position "
                       "ou rect, atout/arme/prefab, mur), zones et zone de départ, totaux. format \"full\" : la carte "
                       "complète {carte, pieces, ouvertures, objets, zones, depart} (format docs/MAP_AUTHORING.md).",
        "inputSchema": {"type": "object", "properties": {
            "format": {"type": "string", "enum": ["summary", "full"], "default": "summary"},
            "floor": {"type": "integer", "minimum": 0, "description": "Résumé d'un seul étage (facultatif)."},
        }, "additionalProperties": False},
    },
    {
        "name": "editor_get_element",
        "description": "Éléments complets (toutes leurs clés) d'après leurs ids, avec leur collection (pieces, ouvertures, "
                       "objets, zones). À relire avant un « put » qui modifie un élément.",
        "inputSchema": {"type": "object", "properties": {"ids": _ids_schema("Ids des éléments (p3, o1, a2, z1…).")},
                        "required": ["ids"], "additionalProperties": False},
    },
    {
        "name": "editor_get_selection",
        "description": "Ce que l'utilisateur a sélectionné dans l'éditeur : ids, éléments complets, étage affiché et position "
                       "de la souris sur le plan (m). « ça », « cette pièce », « ici » désignent souvent la sélection ou le curseur.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "editor_apply",
        "description": "Applique un lot d'opérations à la carte, en direct chez tous les participants. UN appel = UNE étape "
                       "d'annulation (Ctrl+Z) pour l'utilisateur. Opérations : "
                       "{\"op\":\"add\",\"coll\":C,\"el\":{…}} crée (sans id, ou id provisoire \"$1\", \"$2\"… que l'on peut "
                       "citer ailleurs dans le même lot, ex. \"zone\":\"$1\" ; l'éditeur attribue les vrais ids, rendus dans "
                       "« ids ») ; {\"op\":\"put\",\"coll\":C,\"el\":{\"id\":…,…}} remplace l'élément entier de même id ; "
                       "{\"op\":\"del\",\"coll\":C,\"id\":…} supprime ; {\"op\":\"carte\",\"carte\":{…}} remplace carte "
                       "(étages, noms) ; {\"op\":\"depart\",\"id\":zone} zone de départ. C ∈ pieces, ouvertures, objets, zones. "
                       "Chaque élément porte « etage ». Résultat : cid, ids attribués, éléments refusés (invalid).",
        "inputSchema": {"type": "object", "properties": {
            "label": {"type": "string", "minLength": 1, "maxLength": 120,
                      "description": "Libellé court en français affiché à l'utilisateur et dans l'historique (« Couloir entrée → atelier »)."},
            "ops": {"type": "array", "minItems": 1, "maxItems": MAX_OPS, "items": {"type": "object", "properties": {
                "op": {"type": "string", "enum": ["add", "put", "del", "carte", "depart"]},
                "coll": {"type": "string", "enum": list(COLLS)},
                "el": {"type": "object"}, "id": {"type": "string"}, "carte": {"type": "object"},
            }, "required": ["op"]}},
            "animate": {"type": "boolean", "default": True,
                        "description": "Faire apparaître les éléments un par un chez l'utilisateur (défaut true)."},
        }, "required": ["label", "ops"], "additionalProperties": False},
    },
    {
        "name": "editor_undo_last",
        "description": "Annule la dernière modification de Claude encore active (comme un Ctrl+Z limité à Claude ; les "
                       "éléments retouchés entre-temps par quelqu'un d'autre ne sont pas annulés).",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "editor_validate",
        "description": "Lance le validateur de l'éditeur (MapValidator) : erreurs bloquantes (carte refusée par TESTER) et "
                       "avertissements de conception BO1, avec positions en mètres. À appeler après chaque modification.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "editor_screenshot",
        "description": "Image PNG du plan de l'éditeur (un étage, éventuellement cadré sur des éléments) pour voir le résultat ; "
                       "le texte joint donne les bornes en mètres [x0,y0,x1,y1] de l'image.",
        "inputSchema": {"type": "object", "properties": {
            "floor": {"type": "integer", "minimum": 0, "description": "Étage (défaut : celui affiché)."},
            "ids": _ids_schema("Cadrer sur ces éléments (facultatif)."),
        }, "additionalProperties": False},
    },
    {
        "name": "editor_highlight",
        "description": "Montre des éléments à l'utilisateur dans l'éditeur (contour pulsé + bulle avec le message). "
                       "Pour désigner ce dont tu parles ou poser une question sur un endroit précis.",
        "inputSchema": {"type": "object", "properties": {
            "ids": _ids_schema("Éléments à montrer."),
            "message": {"type": "string", "maxLength": 200, "description": "Bulle affichée (français)."},
        }, "required": ["ids"], "additionalProperties": False},
    },
    {
        "name": "editor_catalog",
        "description": "Catalogue de l'éditeur : types d'objets et d'ouvertures admis avec leurs clés (MapCatalog), décors "
                       "(prefabs), luminaires, armes, atouts, textures. À lire avant de créer un type d'objet inconnu.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "editor_events",
        "description": "Derniers événements poussés par l'éditeur (changements faits par l'utilisateur ou d'autres "
                       "participants, sélection, participants), du plus ancien au plus récent ; 100 gardés au plus.",
        "inputSchema": {"type": "object", "properties": {
            "limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 20},
        }, "additionalProperties": False},
    },
    {
        "name": "editor_plan_corridor",
        "description": "PROPOSE (sans rien appliquer) les ops d'un couloir entre deux pièces du même étage : couloir droit "
                       "si leurs murs se font face, en L sinon ; une simple porte si elles ont déjà un mur commun. Le couloir "
                       "va dans la zone de room_a (passage libre côté A), porte payante côté B si B est d'une autre zone. "
                       "Contrôle chevauchements et ouvertures existantes, signale les écarts aux règles (§ 3.2). "
                       "Relire puis passer les ops à editor_apply avec le label proposé.",
        "inputSchema": {"type": "object", "properties": {
            "room_a": {"type": "string", "description": "Pièce de départ : id (p1…) ou nom (casse et accents ignorés)."},
            "room_b": {"type": "string", "description": "Pièce d'arrivée : id ou nom."},
            "width": {"type": "number", "minimum": 1, "maximum": 6, "default": 2.5,
                      "description": "Largeur en m (multiple de 0,5 ; couloir principal 2 à 3 m)."},
            "price": {"type": "integer", "minimum": 0, "description": "Prix de la porte côté B (défaut : 750/1000/1250 selon les portes déjà posées)."},
        }, "required": ["room_a", "room_b"], "additionalProperties": False},
    },
]


def text(obj) -> dict:
    if isinstance(obj, str):
        return {"type": "text", "text": obj}
    return {"type": "text", "text": json.dumps(obj, ensure_ascii=False, separators=(",", ":"))}


class Tools:
    def __init__(self, link: EditorLink) -> None:
        self.link = link

    def call(self, name: str, args: dict) -> dict:
        fn = getattr(self, "t_" + name.removeprefix("editor_"), None) if name.startswith("editor_") else None
        if fn is None or not any(t["name"] == name for t in TOOLS):
            return {"content": [text("Outil inconnu : %s" % name)], "isError": True}
        if not isinstance(args, dict):
            return {"content": [text("Arguments invalides (objet JSON attendu).")], "isError": True}
        try:
            content = fn(args)
            return {"content": content, "isError": False}
        except EditorError as e:
            return {"content": [text(str(e))], "isError": True}
        except Exception as e:  # jamais planter : erreur rendue à Claude
            log("erreur dans", name, ":", traceback.format_exc())
            return {"content": [text("Erreur interne du pont MCP (%s) : %s" % (type(e).__name__, e))], "isError": True}

    def _ids(self, args: dict, required: bool = True) -> list[str]:
        ids = args.get("ids")
        if ids is None and not required:
            return []
        if not isinstance(ids, list) or not all(isinstance(i, str) and i for i in ids) or (required and not ids):
            raise EditorError("« ids » doit être une liste d'identifiants texte (ex. [\"p3\", \"o1\"]).")
        return ids

    def _map(self) -> dict:
        doc = self.link.request("get_map")
        if not isinstance(doc, dict):
            raise EditorError("réponse get_map inattendue de l'éditeur")
        return doc

    def t_status(self, args):
        return [text(self.link.request("status"))]

    def t_get_map(self, args):
        fmt = args.get("format", "summary")
        if fmt not in ("summary", "full"):
            raise EditorError("format : \"summary\" ou \"full\"")
        doc = self._map()
        if fmt == "full":
            return [text(doc)]
        floor = args.get("floor")
        if floor is not None and (not isinstance(floor, int) or isinstance(floor, bool) or floor < 0):
            raise EditorError("floor : entier ≥ 0")
        return [text(map_geom.summarize(doc, floor))]

    def t_get_element(self, args):
        return [text(map_geom.find_elements(self._map(), self._ids(args)))]

    def t_get_selection(self, args):
        return [text(self.link.request("get_selection"))]

    def t_apply(self, args):
        label = args.get("label")
        if not isinstance(label, str) or not label.strip():
            raise EditorError("« label » obligatoire : un libellé court en français (affiché à l'utilisateur).")
        ops = args.get("ops")
        err = check_ops(ops)
        if err:
            raise EditorError("Lot refusé avant envoi : " + err)
        animate = args.get("animate", True)
        if not isinstance(animate, bool):
            raise EditorError("animate : true ou false")
        res = self.link.request("apply", {"label": label.strip()[:120], "ops": ops, "animate": animate})
        out = [text(res)]
        if isinstance(res, dict) and res.get("invalid"):
            out.append(text("Attention : %d élément(s) refusé(s) par l'éditeur (voir « invalid ») ; le reste du lot est appliqué."
                            % len(res["invalid"])))
        return out

    def t_undo_last(self, args):
        return [text(self.link.request("undo"))]

    def t_validate(self, args):
        res = self.link.request("validate")
        return [text(res)]

    def t_screenshot(self, args):
        a = {}
        if "floor" in args:
            f = args["floor"]
            if not isinstance(f, int) or isinstance(f, bool) or f < 0:
                raise EditorError("floor : entier ≥ 0")
            a["floor"] = f
        ids = self._ids(args, required=False)
        if ids:
            a["ids"] = ids
        res = self.link.request("screenshot", a, timeout=max(REQUEST_TIMEOUT, 30))
        if not isinstance(res, dict) or not isinstance(res.get("png_base64"), str):
            raise EditorError("réponse screenshot inattendue de l'éditeur")
        data = res["png_base64"]
        try:
            raw = base64.b64decode(data, validate=True)
        except ValueError:
            raise EditorError("image illisible renvoyée par l'éditeur")
        if not raw.startswith(b"\x89PNG"):
            raise EditorError("l'éditeur n'a pas renvoyé un PNG")
        info = {k: v for k, v in res.items() if k != "png_base64"}
        info["unites"] = "bounds = [x0, y0, x1, y1] en mètres (x vers l'est, y vers le sud)"
        return [{"type": "image", "data": data, "mimeType": "image/png"}, text(info)]

    def t_highlight(self, args):
        ids = self._ids(args)
        msg = args.get("message", "")
        if not isinstance(msg, str):
            raise EditorError("message : texte")
        return [text(self.link.request("highlight", {"ids": ids, "message": msg[:200]}))]

    def t_catalog(self, args):
        return [text(self.link.request("catalog"))]

    def t_events(self, args):
        limit = args.get("limit", 20)
        if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 100:
            raise EditorError("limit : entier de 1 à 100")
        evs = list(self.link.events)[-limit:]
        if not evs:
            return [text("Aucun événement reçu de l'éditeur depuis le lancement du pont." +
                         ("" if self.link.alive else " (pas connecté pour l'instant : appelle editor_status)"))]
        return [text({"events": evs, "connecte": self.link.alive})]

    def t_plan_corridor(self, args):
        a, b = args.get("room_a"), args.get("room_b")
        if not isinstance(a, str) or not isinstance(b, str):
            raise EditorError("room_a et room_b : id ou nom de pièce (texte)")
        width = args.get("width", args.get("largeur", 2.5))
        if isinstance(width, bool) or not isinstance(width, (int, float)):
            raise EditorError("width : nombre (m)")
        price = args.get("price")
        if price is not None and (isinstance(price, bool) or not isinstance(price, int) or price < 0):
            raise EditorError("price : entier ≥ 0")
        try:
            plan = map_geom.plan_corridor(self._map(), a, b, float(width), price)
        except map_geom.PlanError as e:
            raise EditorError("Pas de proposition : %s" % e)
        return [text(plan)]


# ------------------------------------------------------------------ JSON-RPC / MCP

class Server:
    def __init__(self, out=None) -> None:
        self.link = EditorLink()
        self.tools = Tools(self.link)
        self.out = out or sys.stdout.buffer
        self.out_lock = threading.Lock()
        self.initialized = False

    def send(self, msg: dict) -> None:
        data = (json.dumps(msg, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        with self.out_lock:
            self.out.write(data)
            self.out.flush()

    @staticmethod
    def error(rid, code: int, message: str) -> dict:
        return {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}}

    def handle(self, msg) -> dict | None:
        if not isinstance(msg, dict) or msg.get("jsonrpc") != "2.0" or not isinstance(msg.get("method", ""), str):
            if isinstance(msg, dict) and "method" not in msg and ("result" in msg or "error" in msg):
                return None  # réponse du client à une requête que nous n'envoyons jamais
            return self.error(msg.get("id") if isinstance(msg, dict) else None, -32600, "Invalid Request")
        method = msg.get("method")
        rid = msg.get("id")
        is_notification = "id" not in msg
        params = msg.get("params") or {}
        if is_notification:
            if method == "notifications/initialized":
                self.initialized = True
            return None
        try:
            if method == "initialize":
                asked = params.get("protocolVersion") if isinstance(params, dict) else None
                version = asked if asked in SUPPORTED_PROTOCOLS else LATEST_PROTOCOL
                return {"jsonrpc": "2.0", "id": rid, "result": {
                    "protocolVersion": version,
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": SERVER_NAME, "title": "Éditeur de cartes (Claude of Duty Zombie)", "version": SERVER_VERSION},
                    "instructions": INSTRUCTIONS,
                }}
            if method == "ping":
                return {"jsonrpc": "2.0", "id": rid, "result": {}}
            if method == "tools/list":
                return {"jsonrpc": "2.0", "id": rid, "result": {"tools": TOOLS}}
            if method == "tools/call":
                if not isinstance(params, dict) or not isinstance(params.get("name"), str):
                    return self.error(rid, -32602, "Invalid params: name requis")
                return {"jsonrpc": "2.0", "id": rid, "result": self.tools.call(params["name"], params.get("arguments") or {})}
            if method in ("resources/list", "prompts/list"):
                key = "resources" if method.startswith("resources") else "prompts"
                return {"jsonrpc": "2.0", "id": rid, "result": {key: []}}
            return self.error(rid, -32601, "Method not found: %s" % method)
        except Exception as e:
            log("erreur interne :", traceback.format_exc())
            return self.error(rid, -32603, "Internal error: %s" % e)

    def handle_line(self, line: bytes) -> None:
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            self.send(self.error(None, -32700, "Parse error"))
            return
        if isinstance(msg, list):  # lots JSON-RPC (anciennes versions du protocole)
            replies = [r for r in (self.handle(m) for m in msg) if r is not None]
            if replies:
                with self.out_lock:
                    self.out.write((json.dumps(replies, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
                    self.out.flush()
            return
        reply = self.handle(msg)
        if reply is not None:
            self.send(reply)

    def run(self, inp=None) -> None:
        inp = inp or sys.stdin.buffer
        log("démarré (agent.json : %s)" % agent_json_path())
        for line in inp:
            try:
                self.handle_line(line)
            except Exception:
                log("erreur :", traceback.format_exc())
        self.link.close()
        log("arrêt (stdin fermé)")


def main() -> None:
    # Logs en UTF-8 sans jamais lever d'erreur d'encodage (console Windows cp1252).
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    Server().run()


if __name__ == "__main__":
    main()
