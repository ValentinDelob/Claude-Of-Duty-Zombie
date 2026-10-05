extends TestCase
## Serveur MCP du jeu (autoload McpServer, docs/MCP.md) : un serveur de test
## démarré sur les ports 17941+ (décalés par AUTOTEST_PORT_OFFSET), appelé en
## HTTP brut (StreamPeerTCP) comme le ferait Claude Code. Analyse HTTP,
## jeton / Host / Origin / Content-Type, sessions MCP, outils transmis à un
## faux éditeur, règles de conception jointes au premier appel seulement,
## editor_guide, ressources, prompt, erreurs JSON-RPC. Jeton écrit dans
## tests/_out, jamais chez le joueur.

const SERVER := preload("res://scripts/autoload/mcp_server.gd")
const BASE := 17941


## Faux éditeur : rend des réponses fixes et note les commandes reçues.
class FakeLink extends Node:
	var calls: Array = []

	func handle(cmd: String, args: Dictionary) -> Dictionary:
		calls.append([cmd, args])
		await get_tree().process_frame
		match cmd:
			"status":
				return {"map_id": "essai", "role": "solo"}
			"get_map":
				return {"carte": {}, "pieces": [{"id": "p1"}], "ouvertures": [], "objets": [], "zones": [], "depart": ""}
			"apply":
				return {"cid": "c1", "ids": {"$1": "p2"}, "invalid": {"o9": "type inconnu"}}
			"screenshot":
				var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
				return {"png_base64": Marshalls.raw_to_base64(img.save_png_to_buffer()), "width": 4, "height": 4, "floor": 0, "bounds": [0, 0, 1, 1]}
			"get_elements":
				return {"error": "commande inconnue : get_elements"}
		return {"error": "commande inconnue : %s" % cmd}


var _srv: Node
var _tcp: StreamPeerTCP
var _sid := ""
var _n := 0


func _off() -> int:
	return OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()


func _until(cond: Callable, limit := 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > limit * 1000.0:
			return false
		await host.get_tree().process_frame
	return true


func _start() -> Node:
	var s: Node = SERVER.new()
	s.autostart = false
	s.dir = ProjectSettings.globalize_path("res://tests/_out/mcp_test")
	host.add_child(s)
	assert_eq(s.start(BASE + _off(), BASE + 8 + _off()), OK, "écoute de test")
	_srv = s
	return s


func _stop() -> void:
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null
	if _srv != null:
		_srv.stop()
		_srv.queue_free()
		_srv = null
	_sid = ""
	await host.get_tree().process_frame


func _connect() -> StreamPeerTCP:
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", _srv.port)
	await _until(func(): tcp.poll(); return tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED)
	return tcp


## Envoie des octets bruts et lit UNE réponse HTTP : {status, headers, body,
## raw} ({closed: true} si la connexion se ferme sans réponse).
func _raw(tcp: StreamPeerTCP, data: PackedByteArray, limit := 5.0) -> Dictionary:
	if not data.is_empty():
		tcp.put_data(data)
	var buf := PackedByteArray()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit * 1000.0:
		tcp.poll()
		var n := tcp.get_available_bytes()
		if n > 0:
			buf.append_array(tcp.get_partial_data(n)[1])
		var end := SERVER.head_end(buf)
		if end >= 0:
			var head := buf.slice(0, end).get_string_from_utf8().split("\r\n")
			var headers := {}
			for i in range(1, head.size()):
				var k := head[i].find(":")
				headers[head[i].left(k).to_lower()] = head[i].substr(k + 1).strip_edges()
			var cl := int(String(headers.get("content-length", "0")))
			if buf.size() >= end + 4 + cl:
				var body := buf.slice(end + 4, end + 4 + cl).get_string_from_utf8()
				return {"status": head[0].split(" ")[1].to_int(), "headers": headers, "body": body, "json": JSON.parse_string(body) if String(headers.get("content-type", "")).begins_with("application/json") else null}
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED and n == 0:
			return {"closed": true, "status": 0}
		await host.get_tree().process_frame
	return {"status": -1}


func _request(method: String, path: String, headers: Dictionary, body := "") -> PackedByteArray:
	var lines := ["%s %s HTTP/1.1" % [method, path]]
	for k in headers:
		lines.append("%s: %s" % [k, headers[k]])
	var b := body.to_utf8_buffer()
	if method == "POST":
		lines.append("Content-Length: %d" % b.size())
	var out := ("\r\n".join(lines) + "\r\n\r\n").to_utf8_buffer()
	out.append_array(b)
	return out


func _std_headers(extra := {}) -> Dictionary:
	var h := {"Host": "127.0.0.1:%d" % _srv.port, "Authorization": "Bearer " + _srv.get_token(), "Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
	if _sid != "":
		h["Mcp-Session-Id"] = _sid
	h.merge(extra, true)
	return h


## POST JSON-RPC sur la connexion gardée (keep-alive).
func _post(payload: Variant, extra := {}) -> Dictionary:
	if _tcp == null or _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_tcp = await _connect()
	return await _raw(_tcp, _request("POST", "/mcp", _std_headers(extra), JSON.stringify(payload)))


func _call(method: String, params := {}) -> Dictionary:
	_n += 1
	var r := await _post({"jsonrpc": "2.0", "id": _n, "method": method, "params": params})
	return r.get("json", {}) if r.get("json") is Dictionary else {}


func _init_session(version := "2025-06-18") -> Dictionary:
	_sid = ""
	var r := await _post({"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": version, "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}})
	_sid = String(r.headers.get("mcp-session-id", "")) if r.has("headers") else ""
	return r


func _tool(name: String, args := {}) -> Dictionary:
	var r := await _call("tools/call", {"name": name, "arguments": args})
	return r.get("result", {})


static func _texts(res: Dictionary) -> String:
	var out := []
	for c in res.get("content", []):
		if String(c.get("type", "")) == "text":
			out.append(String(c.text))
	return "\n".join(out)


# ------------------------------------------------------------------ tests

func test_http_head_parsing() -> void:
	var h: Dictionary = SERVER.parse_head("POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1:7791\r\nContent-Type: application/json\r\nX-A: 1\r\nx-a: 2")
	assert_eq(String(h.method), "POST")
	assert_eq(String(h.path), "/mcp?x=1")
	assert_eq(String(h.headers.host), "127.0.0.1:7791", "noms en minuscules")
	assert_eq(String(h.headers["x-a"]), "1, 2", "doublon ordinaire : valeurs jointes")
	assert_true(bool(h.keep), "HTTP/1.1 : keep-alive par défaut")
	assert_false(bool(SERVER.parse_head("GET / HTTP/1.0").keep), "HTTP/1.0 : fermée par défaut")
	assert_false(bool(SERVER.parse_head("GET / HTTP/1.1\r\nConnection: close").keep))
	assert_true(SERVER.parse_head("GET / HTTP/1.1\r\nHost: a\r\nHost: b").has("error"), "Host en double refusé")
	assert_true(SERVER.parse_head("GARBAGE").has("error"))
	assert_true(SERVER.parse_head("GET / HTTP/1.1\r\nsans deux-points").has("error"))
	assert_eq(SERVER.head_end("ab\r\n\r\ncd".to_utf8_buffer()), 2)
	assert_eq(SERVER.head_end("ab\r\n\r".to_utf8_buffer()), -1)
	assert_true(SERVER.origin_ok("http://localhost:5173") and SERVER.origin_ok("http://127.0.0.1") and SERVER.origin_ok("https://LOCALHOST:1"))
	assert_false(SERVER.origin_ok("https://evil.example") or SERVER.origin_ok("null") or SERVER.origin_ok("http://127.0.0.1.evil.com"))
	assert_eq(SERVER.norm_id(3.0), 3, "id entier rendu entier")
	assert_true(SERVER.same("abc", "abc") and not SERVER.same("abc", "abd") and not SERVER.same("", ""))


func test_token_is_stable_and_regenerable() -> void:
	var d := ProjectSettings.globalize_path("res://tests/_out/mcp_token_test")
	DirAccess.remove_absolute(d.path_join("token"))
	var a: Node = SERVER.new()
	a.autostart = false
	a.dir = d
	var t := String(a.get_token())
	assert_true(t.length() == 32 and t.is_valid_hex_number(), "32 hex")
	var b: Node = SERVER.new()
	b.autostart = false
	b.dir = d
	assert_eq(String(b.get_token()), t, "jeton stable (relu dans le fichier)")
	b.regenerate_token()
	assert_true(String(b.get_token()) != t and FileAccess.get_file_as_string(d.path_join("token")) == b.token, "nouveau jeton enregistré")
	assert_true(String(b.claude_command()).begins_with("claude mcp add --transport http --scope user map-editor http://127.0.0.1:7791/mcp --header \"Authorization: Bearer "), b.claude_command())
	var cfg: Variant = JSON.parse_string(b.json_config())
	assert_true(cfg is Dictionary and cfg.type == "http" and String(cfg.headers.Authorization) == "Bearer " + b.token, "config JSON générique")
	a.free()
	b.free()


func test_http_security() -> void:
	var s := _start()
	var tcp := await _connect()
	var ok_host := "127.0.0.1:%d" % s.port
	var body := JSON.stringify({"jsonrpc": "2.0", "id": 1, "method": "ping"})
	# Sans jeton : 401, sans WWW-Authenticate (le client ne tente pas OAuth).
	var r := await _raw(tcp, _request("POST", "/mcp", {"Host": ok_host, "Content-Type": "application/json"}, body))
	assert_eq(int(r.status), 401, "sans jeton")
	assert_false((r.headers as Dictionary).has("www-authenticate"), "pas de WWW-Authenticate")
	r = await _raw(tcp, _request("POST", "/mcp", {"Host": ok_host, "Content-Type": "application/json", "Authorization": "Bearer " + "0".repeat(32)}, body))
	assert_eq(int(r.status), 401, "mauvais jeton")
	r = await _raw(tcp, _request("GET", "/.well-known/oauth-protected-resource", {"Host": ok_host}))
	assert_eq(int(r.status), 404, "/.well-known : 404")
	r = await _raw(tcp, _request("POST", "/mcp", {"Host": "evil.example:%d" % s.port, "Content-Type": "application/json", "Authorization": "Bearer " + s.get_token()}, body))
	assert_eq(int(r.status), 403, "Host étranger (DNS rebinding)")
	r = await _raw(tcp, _request("POST", "/mcp", {"Host": ok_host, "Origin": "https://evil.example", "Content-Type": "application/json", "Authorization": "Bearer " + s.get_token()}, body))
	assert_eq(int(r.status), 403, "Origin étranger")
	assert_false((r.headers as Dictionary).has("access-control-allow-origin"), "pas de CORS")
	r = await _raw(tcp, _request("POST", "/mcp", {"Host": ok_host, "Content-Type": "text/plain", "Authorization": "Bearer " + s.get_token()}, body))
	assert_eq(int(r.status), 415, "POST sans application/json")
	r = await _raw(tcp, _request("GET", "/mcp", {"Host": ok_host, "Authorization": "Bearer " + s.get_token()}))
	assert_eq(int(r.status), 405, "GET /mcp : pas de flux SSE")
	r = await _raw(tcp, _request("POST", "/autre", {"Host": "localhost:%d" % s.port, "Content-Type": "application/json", "Authorization": "Bearer " + s.get_token()}, body))
	assert_eq(int(r.status), 404, "autre chemin")
	# Origin locale admise ; sans session : 400.
	r = await _raw(tcp, _request("POST", "/mcp", {"Host": "localhost:%d" % s.port, "Origin": "http://localhost:3000", "Content-Type": "application/json; charset=utf-8", "Authorization": "bearer " + s.get_token()}, body))
	assert_eq(int(r.status), 400, "authentifié, mais sans Mcp-Session-Id : 400 (%s)" % str(r.get("body", "")))
	# Corps trop gros : 413 avant lecture, connexion fermée.
	r = await _raw(tcp, ("POST /mcp HTTP/1.1\r\nHost: %s\r\nContent-Length: %d\r\n\r\n" % [ok_host, SERVER.MAX_BODY + 1]).to_utf8_buffer())
	assert_eq(int(r.status), 413, "corps de plus de 64 Mio")
	tcp.disconnect_from_host()
	# En-têtes trop longs : 431.
	tcp = await _connect()
	r = await _raw(tcp, ("GET /mcp HTTP/1.1\r\nX-Pad: %s\r\n" % "a".repeat(SERVER.MAX_HEAD + 10)).to_utf8_buffer())
	assert_eq(int(r.status), 431, "en-têtes de plus de 16 Kio")
	tcp.disconnect_from_host()
	# Chunked refusé ; requête incomplète coupée (délai raccourci).
	tcp = await _connect()
	r = await _raw(tcp, ("POST /mcp HTTP/1.1\r\nHost: %s\r\nTransfer-Encoding: chunked\r\n\r\n" % ok_host).to_utf8_buffer())
	assert_eq(int(r.status), 501, "chunked")
	tcp.disconnect_from_host()
	s.request_sec = 0.3
	tcp = await _connect()
	r = await _raw(tcp, ("POST /mcp HTTP/1.1\r\nHost: %s\r\nContent-Length: 50\r\n\r\n{" % ok_host).to_utf8_buffer())
	assert_eq(int(r.status), 408, "requête incomplète coupée")
	tcp.disconnect_from_host()
	await _stop()


func test_mcp_session_and_tools() -> void:
	var s := _start()
	var r := await _init_session("2025-06-18")
	assert_eq(int(r.status), 200, "initialize")
	assert_eq(_sid.length(), 32, "Mcp-Session-Id rendu")
	var res: Dictionary = r.json.result
	assert_eq(String(res.protocolVersion), "2025-06-18", "version demandée gardée")
	assert_true(res.capabilities.has("tools") and res.capabilities.has("resources") and res.capabilities.has("prompts"), "capacités")
	assert_eq(String(res.serverInfo.name), "map-editor")
	var ins := String(res.instructions)
	assert_true(ins.length() < 1800, "instructions courtes (%d caractères)" % ins.length())
	assert_false(ins.contains("docs/"), "aucun chemin docs/ dans les instructions")
	assert_true(ins.contains("OBLIGATOIRES") and ins.contains("editor_guide"), "règles obligatoires et guide cités")
	assert_true(String(r.body).contains("\"id\":0"), "id entier rendu entier : %s" % String(r.body).left(40))
	var r2 := await _post({"jsonrpc": "2.0", "method": "notifications/initialized"})
	assert_eq(int(r2.status), 202, "notification : 202")
	assert_eq(String(r2.body), "", "sans corps")
	assert_true(bool(s.sessions[_sid].ready))
	assert_true(s.has_agent(), "une IA est connectée")
	# Session inconnue, version de protocole inconnue.
	r2 = await _post({"jsonrpc": "2.0", "id": 5, "method": "ping"}, {"Mcp-Session-Id": "f".repeat(32)})
	assert_eq(int(r2.status), 404, "session inconnue : 404")
	r2 = await _post({"jsonrpc": "2.0", "id": 5, "method": "ping"}, {"MCP-Protocol-Version": "1999-01-01"})
	assert_eq(int(r2.status), 400, "version de protocole inconnue : 400")
	var p := await _call("ping")
	assert_true(p.has("result"), "ping")
	# tools/list : tous les outils du pont d'origine + editor_guide, sans cmd ni fn.
	var lst: Array = (await _call("tools/list")).result.tools
	var names := lst.map(func(t): return String(t.name))
	for n in ["editor_guide", "editor_status", "editor_get_map", "editor_get_element", "editor_get_selection", "editor_apply", "editor_undo_last",
			"editor_validate", "editor_screenshot", "editor_highlight", "editor_catalog", "editor_events", "editor_plan_corridor",
			"editor_prefab_list", "editor_prefab_sources", "editor_prefab_create", "editor_prefab_import_model", "editor_prefab_import",
			"editor_prefab_update", "editor_prefab_delete", "editor_texture_list", "editor_texture_import", "editor_texture_update",
			"editor_texture_delete", "editor_texture_import_from_map"]:
		assert_true(n in names, "outil %s" % n)
	assert_false(lst.any(func(t): return t.has("cmd") or t.has("fn")), "définitions internes cachées")
	assert_false(JSON.stringify(lst).contains("docs/"), "aucun chemin docs/ dans les descriptions")
	# Premier appel (éditeur fermé) : règles en tête, puis l'erreur claire.
	var t1 := await _tool("editor_status")
	assert_true(bool(t1.isError), "éditeur fermé : erreur d'outil")
	var c0 := String(t1.content[0].text)
	assert_true(c0.begins_with("RÈGLES DE CONCEPTION OBLIGATOIRES") and c0.contains("Grille de contrôle"), "règles complètes au premier appel")
	assert_true(String(t1.content[1].text).contains("Ouvre l'éditeur de cartes du jeu") or String(t1.content[1].text).contains("ouvre l'éditeur de cartes du jeu"), _texts(t1).right(200))
	var t2 := await _tool("editor_status")
	assert_false(_texts(t2).contains("RÈGLES DE CONCEPTION"), "règles jointes une seule fois par session")
	# Faux éditeur : les outils « cmd » lui sont transmis tels quels.
	var fake := FakeLink.new()
	host.add_child(fake)
	s.attach_editor(fake)
	t2 = await _tool("editor_status")
	assert_false(bool(t2.isError), _texts(t2))
	assert_eq(JSON.parse_string(_texts(t2)), {"map_id": "essai", "role": "solo"}, "résultat de handle en JSON")
	assert_eq(String(fake.calls[-1][0]), "status")
	# editor_apply : contrôles locaux, puis envoi.
	var bad := await _tool("editor_apply", {"label": "x", "ops": [{"op": "put", "coll": "pieces", "el": {}}]})
	assert_true(bool(bad.isError) and _texts(bad).begins_with("Lot refusé avant envoi : ops[0] : put demande un el.id"), _texts(bad))
	bad = await _tool("editor_apply", {"ops": [{"op": "del", "coll": "pieces", "id": "p1"}]})
	assert_true(bool(bad.isError) and _texts(bad).contains("« label » obligatoire"), _texts(bad))
	bad = await _tool("editor_apply", {"label": "x", "ops": [{"op": "frob"}]})
	assert_true(_texts(bad).contains("op inconnue 'frob'"), _texts(bad))
	var n0: int = fake.calls.size()
	var good := await _tool("editor_apply", {"label": "  Hall  ", "ops": [{"op": "add", "coll": "pieces", "el": {"id": "$1", "contour": [[0, 0], [4, 0], [4, 4], [0, 4]]}}]})
	assert_false(bool(good.isError), _texts(good))
	assert_eq(fake.calls.size(), n0 + 1, "un seul appel à l'éditeur")
	assert_eq(String(fake.calls[-1][1].label), "Hall", "libellé nettoyé")
	assert_true(bool(fake.calls[-1][1].animate), "animate par défaut")
	assert_true(_texts(good).contains("Attention : 1 élément(s) refusé(s)"), "avertissement invalid")
	# Capture : image PNG + bornes.
	var shot := await _tool("editor_screenshot", {"floor": 0})
	assert_eq(String(shot.content[0].type), "image", "contenu image")
	assert_eq(String(shot.content[0].mimeType), "image/png")
	assert_true(_texts(shot).contains("unites"), "bornes expliquées")
	assert_true(int(fake.calls[-1][1].floor) == 0 and fake.calls[-1][1].floor is int, "étage entier transmis")
	var v := await _tool("editor_screenshot", {"view": "biais"})
	assert_true(bool(v.isError) and _texts(v).begins_with("view : dessus"), _texts(v))
	# get_element : éditeur sans get_elements -> repli sur MapSummary.find_elements.
	var ge := await _tool("editor_get_element", {"ids": ["p1"]})
	assert_false(bool(ge.isError), _texts(ge))
	assert_true(_texts(ge).contains("p1"), _texts(ge))
	ge = await _tool("editor_get_element", {"ids": []})
	assert_true(_texts(ge).contains("« ids » doit être une liste"), _texts(ge))
	# get_map : complet transmis ; floor contrôlé.
	var gm := await _tool("editor_get_map", {"format": "full"})
	assert_true(JSON.parse_string(_texts(gm)).has("pieces"), "carte complète")
	gm = await _tool("editor_get_map", {"floor": -1})
	assert_eq(_texts(gm), "floor : entier ≥ 0")
	# Résumé calculé (MapSummary) par défaut.
	gm = await _tool("editor_get_map", {})
	assert_false(bool(gm.isError), _texts(gm))
	assert_true(JSON.parse_string(_texts(gm)) is Dictionary, "résumé en JSON")
	var pc := await _tool("editor_plan_corridor", {"room_a": "p1", "room_b": "p9"})
	assert_true(bool(pc.isError) and _texts(pc).begins_with("Pas de proposition"), _texts(pc))
	# Événements gardés par le serveur.
	var ev := await _tool("editor_events")
	assert_true(_texts(ev).begins_with("Aucun événement"), _texts(ev))
	for i in 105:
		s.push_event({"event": "selection", "ids": ["p%d" % i]})
	ev = await _tool("editor_events", {"limit": 3})
	var evs: Array = JSON.parse_string(_texts(ev)).events
	assert_eq(evs.size(), 3)
	assert_eq(evs[-1].ids, ["p104"], "les plus récents")
	assert_true(evs[0].has("time"), "heure notée")
	assert_eq(s.events.size(), 100, "100 gardés au plus")
	ev = await _tool("editor_events", {"limit": 0})
	assert_eq(_texts(ev), "limit : entier de 1 à 100")
	# Outil inconnu, arguments invalides, outil ajouté au registre.
	var unk := await _tool("editor_frob")
	assert_true(bool(unk.isError) and _texts(unk) == "Outil inconnu : editor_frob")
	var badargs := await _call("tools/call", {"name": "editor_status", "arguments": [1]})
	assert_eq(_texts(badargs.result), "Arguments invalides (objet JSON attendu).")
	assert_eq(s.tools.add_tool({"name": "editor_prefab_test", "description": "essai", "inputSchema": {"type": "object"}, "cmd": "prefab_test"}), "")
	var pf := await _tool("editor_prefab_test", {"a": 1})
	assert_eq(String(fake.calls[-1][0]), "prefab_test", "outil ajouté : commande transmise telle quelle")
	assert_eq(int(fake.calls[-1][1].a), 1)
	assert_true(bool(pf.isError) and _texts(pf).contains("commande inconnue"), "erreur de handle = erreur d'outil")
	s.detach_editor(fake)
	fake.queue_free()
	await _stop()


func test_rules_once_per_session_and_guide() -> void:
	var s := _start()
	await _init_session("2024-11-05")
	# Premier appel = le guide des règles : pas de doublon.
	var g := await _tool("editor_guide", {"topic": "regles"})
	assert_eq(_texts(g).count("Grille de contrôle"), McpDocs.text_of("regles").count("Grille de contrôle"), "règles une seule fois")
	assert_eq(_texts(g), McpDocs.text_of("regles"), "MAP_DESIGN_RULES.md complet")
	g = await _tool("editor_guide", {"topic": "format"})
	assert_true(_texts(g).contains("Sections") and _texts(g).contains("Format des fichiers"), "gros sujet : liste des sections")
	g = await _tool("editor_guide", {"topic": "format", "section": "format des fichiers"})
	assert_true(_texts(g).begins_with("### Format des fichiers"), _texts(g).left(80))
	g = await _tool("editor_guide", {"topic": "objets", "section": "4"})
	assert_true(_texts(g).begins_with("## 4. Escaliers"), _texts(g).left(80))
	g = await _tool("editor_guide", {"topic": "vues", "section": "6.4"})
	assert_true(_texts(g).begins_with("### 6.4 Collaboration"), "6.4 et non 6.4 bis : %s" % _texts(g).left(60))
	g = await _tool("editor_guide", {"topic": "consignes"})
	assert_true(_texts(g).contains("Escaliers") and not _texts(g).contains("docs/"), "consignes sans chemin docs/")
	g = await _tool("editor_guide", {"topic": "echelle"})
	assert_eq(_texts(g), McpDocs.text_of("echelle"), "sujet moyen : en entier")
	g = await _tool("editor_guide", {"topic": "frob"})
	assert_true(bool(g.isError))
	g = await _tool("editor_guide", {"topic": "regles", "section": "zzz introuvable"})
	assert_true(bool(g.isError) and _texts(g).contains("introuvable"))
	# Nouvelle session : règles de nouveau jointes au premier appel.
	await _init_session()
	g = await _tool("editor_guide", {"topic": "consignes"})
	assert_true(String(g.content[0].text).begins_with("RÈGLES DE CONCEPTION OBLIGATOIRES"), "nouvelle session : règles jointes")
	assert_true(String(g.content[1].text).begins_with("# Consignes"), "puis le résultat de l'outil")
	# Ressources et prompt.
	var rl: Array = (await _call("resources/list")).result.resources
	assert_eq(rl.size(), McpDocs.TOPICS.size(), "une ressource par sujet")
	var rr := await _call("resources/read", {"uri": "zombie://docs/MAP_DESIGN_RULES.md"})
	assert_eq(String(rr.result.contents[0].text), McpDocs.text_of("regles"))
	rr = await _call("resources/read", {"uri": "zombie://docs/../project.godot"})
	assert_eq(int(rr.error.code), -32002, "ressource inconnue")
	var pl: Array = (await _call("prompts/list")).result.prompts
	assert_eq(String(pl[0].name), "concevoir_carte")
	var pg := await _call("prompts/get", {"name": "concevoir_carte", "arguments": {"demande": "une usine"}})
	var msgs: Array = pg.result.messages
	assert_true(String(msgs[0].content.text).contains("une usine"), "demande reprise")
	assert_eq(String(msgs[1].content.resource.text), McpDocs.text_of("regles"), "règles jointes au prompt")
	pg = await _call("prompts/get", {"name": "autre"})
	assert_eq(int(pg.error.code), -32602)
	# Erreurs JSON-RPC, lot, fermeture de session.
	var m := await _call("frob/bar")
	assert_eq(int(m.error.code), -32601, "méthode inconnue")
	var pe := await _raw(_tcp, _request("POST", "/mcp", _std_headers(), "{pas du json"))
	assert_eq(int(pe.status), 400)
	assert_eq(int(pe.json.error.code), -32700, "erreur d'analyse")
	var bt := await _post([{"jsonrpc": "2.0", "id": "a", "method": "ping"}, {"jsonrpc": "2.0", "method": "notifications/x"}, {"jsonrpc": "2.0", "id": 7, "method": "nope"}, {"id": 8}])
	assert_true(bt.json is Array and (bt.json as Array).size() == 3, "lot : une réponse par requête (%s)" % bt.get("body", ""))
	assert_eq(String(bt.json[0].id), "a")
	assert_eq(int(bt.json[1].error.code), -32601)
	assert_eq(int(bt.json[2].error.code), -32600, "message sans method")
	var only := await _post({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {}})
	assert_eq(int(only.status), 202)
	var del := await _raw(_tcp, _request("DELETE", "/mcp", _std_headers()))
	assert_eq(int(del.status), 200, "DELETE : session fermée")
	var after := await _post({"jsonrpc": "2.0", "id": 9, "method": "ping"})
	assert_eq(int(after.status), 404, "session fermée : 404")
	assert_false(s.sessions.has(_sid), "session oubliée")
	await _stop()


## Vraie liaison d'éditeur (MapAgentLink sur une session) derrière le serveur :
## lot appliqué et annulable, événement « change » gardé.
func test_end_to_end_with_agent_link() -> void:
	var s := _start()
	var m := EditorMap.blank("essai", "ESSAI", "TEST")
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	s.attach_editor(link)
	await _init_session()
	var r := await _tool("editor_apply", {"label": "Hall", "animate": false, "ops": [
		{"op": "add", "coll": "pieces", "el": {"id": "$1", "nom": "Hall", "contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}}]})
	assert_false(bool(r.isError), _texts(r))
	assert_eq(m.pieces.size(), 1, "pièce posée")
	assert_eq(String(collab.history.entries[0].author), "1:claude", "auteur : le Claude de l'éditeur")
	var st := await _tool("editor_status")
	assert_eq(String(JSON.parse_string(_texts(st)).role), "solo")
	var u := await _tool("editor_undo_last")
	assert_false(bool(u.isError), _texts(u))
	assert_true(m.pieces.is_empty(), "annulé")
	var shot := await _tool("editor_screenshot")
	assert_true(bool(shot.isError) and _texts(shot).contains("headless"), "capture refusée sans affichage")
	s.detach_editor(link)
	link.queue_free()
	collab.queue_free()
	await _stop()


func test_server_limits_clients() -> void:
	var s := _start()
	var socks := []
	for i in SERVER.MAX_CLIENTS:
		socks.append(await _connect())
	await _until(func(): return s._clients.size() == SERVER.MAX_CLIENTS)
	var extra := await _connect()
	var r := await _raw(extra, PackedByteArray())
	assert_eq(int(r.status), 503, "9e client refusé")
	for t in socks:
		t.disconnect_from_host()
	extra.disconnect_from_host()
	await _until(func(): return s._clients.is_empty())
	assert_true(s._clients.is_empty(), "clients partis")
	await _stop()


## Fenêtre Collaboration > Connecter une IA (MCP)… : état, adresse, jeton
## masqué ; avertissement quand le port n'est pas 7791. Le serveur du jeu
## (autoload) garde son jeton dans tests/_out le temps du test.
func test_connect_dialog() -> void:
	var auto := MapEditor.mcp_server()
	var old_dir: String = auto.dir
	var old_token: String = auto.token
	auto.dir = ProjectSettings.globalize_path("res://tests/_out/mcp_dialog_test")
	auto.token = ""
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	assert_true(auto.editor() == ed.agent_link, "éditeur inscrit")
	var rec: Node = ed.get_node_or_null("RecoveryDialog")
	if rec is Window:
		(rec as Window).hide()  # carte de secours de ce poste : sans rapport
	var d := McpDialog.open(ed)
	assert_true(d != null and d.visible, "fenêtre ouverte")
	assert_true(String(d._state.text).contains("désactivé") or String(d._state.text).contains("disabled") or String(d._state.text).contains("arrêté") or String(d._state.text).contains("stopped"), d._state.text)
	assert_eq(String(d._url.text), "http://127.0.0.1:7791/mcp")
	assert_true(d._token.secret and String(d._token.text).length() == 32, "jeton masqué")
	d._show.button_pressed = true
	assert_false(d._token.secret, "« Afficher » montre le jeton")
	assert_false(d._warn.visible, "pas d'avertissement de port")
	# Port de secours : prévenu.
	auto.port = 7795
	auto._server = TCPServer.new()
	d.refresh()
	assert_true(d._warn.visible and String(d._warn.text).contains("7795"), "port différent de 7791 signalé")
	assert_eq(String(d._url.text), "http://127.0.0.1:7795/mcp")
	auto._server = null
	auto.port = 0
	d.queue_free()
	ed.queue_free()
	await wait_frames(2)
	assert_true(auto.editor() == null, "éditeur retiré en sortant")
	auto.dir = old_dir
	auto.token = old_token


func test_checks_ported_from_main() -> void:
	# Nombre de marches automatique : « marches » refusé avant envoi (put ou add).
	var st := {"type": "escalier", "altitude": 0, "rect": [2, 2, 4, 6], "monte": "n"}
	var put_el := st.duplicate()
	put_el["id"] = "e1"
	put_el["marches"] = 12
	var add_el := st.duplicate()
	add_el["marches"] = 12
	assert_true(McpTools.check_ops([{"op": "put", "coll": "objets", "el": put_el}]).contains("n'est plus réglable"))
	assert_true(McpTools.check_ops([{"op": "add", "coll": "objets", "el": add_el}]).contains("n'est plus réglable"))
	var ok_el := st.duplicate()
	ok_el["id"] = "e1"
	assert_eq(McpTools.check_ops([{"op": "put", "coll": "objets", "el": ok_el}]), "")
	# Sélection pendant un geste : « busy » décrit ; boîte au sol dans les consignes.
	assert_true(String(McpTools.new().find("editor_highlight").description).contains("busy"))
	assert_true(McpDocs.CONSIGNES.contains("Boîte mystère (format 15") and McpDocs.CONSIGNES.contains("jamais de « marches »"))
