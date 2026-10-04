extends Node
## McpServer — serveur MCP du jeu (docs/MCP.md) : une IA (Claude Code ou
## tout client MCP « Streamable HTTP ») pilote l'éditeur de cartes ouvert,
## sans le dépôt ni Python : le jeu seul suffit.
##
## - Écoute 127.0.0.1 SEULEMENT, port 7791 (sinon le suivant libre jusqu'à
##   7799), chemin /mcp, tant que le jeu tourne (menu compris), si le réglage
##   Settings.mcp_enabled est vrai (défaut ; Collaboration > Autoriser Claude
##   ou Connecter une IA). Jamais en --headless ni en autotest : un test
##   démarre lui-même un serveur (start) sur sa plage de ports.
## - HTTP/1.1 maison sur TCPServer, sondé à chaque image sans bloquer le jeu :
##   Content-Length (pas de chunked), keep-alive, 8 clients, corps ≤ 64 Mio,
##   en-têtes ≤ 16 Kio, requête incomplète coupée après 10 s, connexion
##   inactive après 120 s, envoi non bloquant.
## - Sécurité : « Authorization: Bearer <jeton> » obligatoire (32 hex, stable,
##   user://mcp/token, régénérable) ; Host = 127.0.0.1 ou localhost avec ce
##   port (sinon 403) ; Origin présent et non local -> 403 (DNS rebinding,
##   pages web) ; POST en application/json seulement ; aucun CORS ; 401 sans
##   WWW-Authenticate et /.well-known/* -> 404 (le client ne tente pas OAuth).
## - MCP (2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05) : POST JSON-RPC
##   (objet ou lot) -> application/json ; notifications seules -> 202 ;
##   initialize rend Mcp-Session-Id (sessions suivies, 32 au plus) ; GET -> 405 ;
##   DELETE ferme la session. Outils : McpTools ; documents : McpDocs (les
##   règles de conception sont jointes au premier tools/call de chaque session).
## - L'éditeur de cartes ouvert s'enregistre (attach_editor : MapAgentLink,
##   méthode async handle(cmd, args) -> Dictionary) et pousse ses événements
##   (push_event, 100 gardés).

signal state_changed

const HOST := "127.0.0.1"
const FIRST_PORT := 7791
const LAST_PORT := 7799
const PATH := "/mcp"
const MAX_CLIENTS := 8
const MAX_BODY := 64 * 1024 * 1024
const MAX_HEAD := 16 * 1024
## Requête commencée mais incomplète.
const REQUEST_SEC := 10.0
## Connexion gardée ouverte sans requête.
const IDLE_SEC := 120.0
## Traitement d'une requête (outil de l'éditeur) au plus.
const WORK_SEC := 120.0
const MAX_SESSIONS := 32
## Une session sans requête depuis plus longtemps ne compte plus comme
## « Claude présent » dans l'éditeur (pastille).
const AGENT_IDLE_SEC := 1800.0
const MAX_EVENTS := 100
const PROTOCOLS := ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
const SERVER_NAME := "map-editor"

## Dossier du jeton (tests : un dossier à eux, jamais celui du joueur).
var dir := "user://mcp"
## Faux : ne démarre pas tout seul (_ready) ; tests.
var autostart := true
## Délais (s) ; les tests les raccourcissent.
var request_sec := REQUEST_SEC
var idle_sec := IDLE_SEC
var work_sec := WORK_SEC
var port := 0
var token := ""
## Dernier échec d'écoute ("" si aucun).
var error := ""
var tools: McpTools
## Événements poussés par l'éditeur ({time, event, …}), du plus ancien au plus récent.
var events: Array = []
## Mcp-Session-Id -> {t (dernière requête, s), rules (règles livrées), version, ready}
var sessions := {}
var _server: TCPServer
var _clients: Array = []
var _editor: Object
var _clock := 0.0


class Client:
	var tcp: StreamPeerTCP
	var buf := PackedByteArray()
	var out := PackedByteArray()
	## En-tête de la requête en cours (corps attendu) ; {} sinon.
	var head := {}
	var need := 0
	var scan := 0
	var idle := 0.0
	var wait := 0.0
	var busy := false
	var busy_t := 0.0
	## Numéro de la requête en cours (une réponse en retard est jetée).
	var serial := 0
	var closing := false
	var gone := false


func _init() -> void:
	tools = McpTools.new(self)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if autostart and may_autostart() and Settings.mcp_enabled:
		start()


## Démarrage automatique permis : jamais sans affichage ni en autotest (le
## port 7791 reste au jeu du joueur).
static func may_autostart() -> bool:
	return DisplayServer.get_name() != "headless" and not AutotestMode.is_running()


func _exit_tree() -> void:
	stop()


func is_running() -> bool:
	return _server != null


func url() -> String:
	return "http://%s:%d%s" % [HOST, port if is_running() else FIRST_PORT, PATH]


## Commande Claude Code qui déclare ce serveur (portée utilisateur).
func claude_command() -> String:
	return "claude mcp add --transport http --scope user %s %s --header \"Authorization: Bearer %s\"" % [SERVER_NAME, url(), get_token()]


## Configuration générique d'un client MCP HTTP.
func json_config() -> String:
	return JSON.stringify({"type": "http", "url": url(), "headers": {"Authorization": "Bearer " + get_token()}}, "  ", false)


## Réglage persistant (Settings.mcp_enabled) : démarre ou arrête l'écoute.
func set_enabled(on: bool) -> void:
	if Settings.mcp_enabled != on:
		Settings.mcp_enabled = on
		Settings.save_settings()
	if on and not is_running():
		start()
	elif not on and is_running():
		stop()
	state_changed.emit()


## Écoute sur le premier port libre de `first` à `last`. OK ou l'erreur.
func start(first := FIRST_PORT, last := LAST_PORT) -> Error:
	stop()
	get_token()
	var err := ERR_CANT_OPEN
	for p in range(first, last + 1):
		var srv := TCPServer.new()
		err = srv.listen(p, HOST)
		if err == OK:
			_server = srv
			port = p
			break
	if err != OK:
		error = Lang.t("aucun port libre de %d à %d", "no free port from %d to %d") % [first, last]
		push_warning("[McpServer] " + error)
	else:
		error = ""
	state_changed.emit()
	return err


func stop() -> void:
	for c: Client in _clients:
		c.gone = true
		c.tcp.disconnect_from_host()
	_clients.clear()
	sessions.clear()
	if _server != null:
		_server.stop()
		_server = null
		state_changed.emit()


# ------------------------------------------------------------------ jeton

func _token_path() -> String:
	return dir.path_join("token")


## Jeton stable (32 hex) : lu dans user://mcp/token, créé au besoin.
func get_token() -> String:
	if token != "":
		return token
	var t := ""
	if FileAccess.file_exists(_token_path()):
		t = FileAccess.get_file_as_string(_token_path()).strip_edges()
	if t.length() == 32 and t.is_valid_hex_number():
		token = t.to_lower()
	else:
		regenerate_token()
	return token


## Nouveau jeton (l'ancien ne marche plus ; sessions fermées).
func regenerate_token() -> void:
	token = Crypto.new().generate_random_bytes(16).hex_encode()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_token_path(), FileAccess.WRITE)
	if f == null:
		push_warning("[McpServer] jeton non enregistré (%s)" % error_string(FileAccess.get_open_error()))
	else:
		f.store_string(token)
		f.close()
	sessions.clear()
	state_changed.emit()


## Comparaison de jetons sans sortie anticipée.
static func same(a: String, b: String) -> bool:
	if a.length() != b.length() or b.is_empty():
		return false
	var d := 0
	for i in a.length():
		d |= a.unicode_at(i) ^ b.unicode_at(i)
	return d == 0


# ------------------------------------------------------------------ éditeur

## L'éditeur ouvert (MapAgentLink : handle(cmd, args) async).
func attach_editor(link: Object) -> void:
	_editor = link
	state_changed.emit()


func detach_editor(link: Object) -> void:
	if _editor == link:
		_editor = null
		state_changed.emit()


func editor() -> Object:
	if _editor != null and is_instance_valid(_editor):
		return _editor
	return null


## Événement de l'éditeur (change, selection, peers) : gardé pour editor_events.
func push_event(ev: Dictionary) -> void:
	var e := {"time": Time.get_time_string_from_system()}
	e.merge(ev)
	events.append(e)
	if events.size() > MAX_EVENTS:
		events = events.slice(events.size() - MAX_EVENTS)


## Une IA est connectée (session MCP active récemment).
func has_agent() -> bool:
	for s in sessions.values():
		if _clock - float(s.t) < AGENT_IDLE_SEC:
			return true
	return false


# ------------------------------------------------------------------ HTTP

func _process(delta: float) -> void:
	_clock += delta
	if _server == null:
		return
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		if _clients.size() >= MAX_CLIENTS:
			tcp.put_data(_response(503, {}, "Too many connections".to_utf8_buffer(), false))
			tcp.disconnect_from_host()
			continue
		var c := Client.new()
		c.tcp = tcp
		_clients.append(c)
	for c: Client in _clients.duplicate():
		_step(c, delta)


func _step(c: Client, delta: float) -> void:
	c.tcp.poll()
	if c.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_drop(c)
		return
	_flush(c)
	if c.gone:
		return
	if c.closing:
		if c.out.is_empty():
			_drop(c)
		return
	if c.busy:
		c.busy_t += delta
		if c.busy_t > work_sec:
			c.serial += 1
			c.busy = false
			_send(c, 504, {}, "Gateway Timeout: the editor did not answer", true)
		return
	var n := c.tcp.get_available_bytes()
	if n > 0:
		var r: Array = c.tcp.get_partial_data(n)
		if r[0] == OK:
			if c.buf.is_empty() and c.head.is_empty():
				c.wait = 0.0
			c.buf.append_array(r[1])
			c.idle = 0.0
	if c.buf.is_empty() and c.head.is_empty():
		c.idle += delta
		if c.idle > idle_sec and c.out.is_empty():
			_drop(c)
		return
	c.wait += delta
	if c.wait > request_sec:
		_send(c, 408, {}, "Request Timeout", true)
		return
	_parse(c)


func _drop(c: Client) -> void:
	c.gone = true
	c.tcp.disconnect_from_host()
	_clients.erase(c)


func _flush(c: Client) -> void:
	while not c.out.is_empty():
		var r: Array = c.tcp.put_partial_data(c.out)
		if r[0] != OK:
			_drop(c)
			return
		var sent: int = r[1]
		if sent <= 0:
			return
		c.out = c.out.slice(sent)


## Fin des en-têtes (\r\n\r\n) dans le tampon : indice ou -1.
static func head_end(buf: PackedByteArray, from := 0) -> int:
	for i in range(maxi(0, from - 3), buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


## Ligne de requête et en-têtes : {method, path, version, headers, keep} ou
## {error}. Noms d'en-têtes en minuscules ; doublon d'un en-tête sensible =
## erreur.
static func parse_head(text: String) -> Dictionary:
	var lines := text.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() != 3 or not first[2].begins_with("HTTP/1.") or first[0].is_empty() or not first[1].begins_with("/"):
		return {"error": "bad request line"}
	var headers := {}
	for i in range(1, lines.size()):
		var l := lines[i]
		var k := l.find(":")
		if k <= 0:
			return {"error": "bad header"}
		var name := l.left(k).strip_edges().to_lower()
		if name.contains(" "):
			return {"error": "bad header"}
		var value := l.substr(k + 1).strip_edges()
		if headers.has(name):
			if name in ["host", "authorization", "content-length", "content-type", "origin", "mcp-session-id", "transfer-encoding"]:
				return {"error": "duplicate header " + name}
			headers[name] = String(headers[name]) + ", " + value
		else:
			headers[name] = value
	var conn := String(headers.get("connection", "")).to_lower()
	var keep := conn != "close" if first[2] == "HTTP/1.1" else conn == "keep-alive"
	return {"method": first[0], "path": first[1], "version": first[2], "headers": headers, "keep": keep}


func _parse(c: Client) -> void:
	if c.head.is_empty():
		var end := head_end(c.buf, c.scan)
		if end < 0:
			c.scan = c.buf.size()
			if c.buf.size() > MAX_HEAD:
				_send(c, 431, {}, "Request Header Fields Too Large", true)
			return
		c.scan = 0
		if end > MAX_HEAD:
			_send(c, 431, {}, "Request Header Fields Too Large", true)
			return
		var head := parse_head(c.buf.slice(0, end).get_string_from_utf8())
		c.buf = c.buf.slice(end + 4)
		if head.has("error"):
			_send(c, 400, {}, "Bad Request: " + String(head.error), true)
			return
		var h: Dictionary = head.headers
		if h.has("transfer-encoding"):
			_send(c, 501, {}, "Not Implemented: use Content-Length", true)
			return
		var cl := String(h.get("content-length", "0"))
		if not cl.is_valid_int() or cl.begins_with("-") or cl.begins_with("+") or cl.length() > 10:
			_send(c, 400, {}, "Bad Request: Content-Length", true)
			return
		if cl.to_int() > MAX_BODY:
			_send(c, 413, {}, "Content Too Large", true)
			return
		c.head = head
		c.need = cl.to_int()
	if c.buf.size() < c.need:
		return
	var body := c.buf.slice(0, c.need)
	c.buf = c.buf.slice(c.need)
	var req := c.head
	c.head = {}
	c.need = 0
	c.wait = 0.0
	_serve(c, req, body)


## Traite une requête complète (coroutine : les outils attendent l'éditeur).
func _serve(c: Client, head: Dictionary, body: PackedByteArray) -> void:
	c.busy = true
	c.busy_t = 0.0
	c.serial += 1
	var serial := c.serial
	var r: Dictionary = await route(head, body)
	if c.gone or c.serial != serial:
		return
	c.busy = false
	_send(c, int(r.status), r.get("headers", {}), r.get("body", PackedByteArray()), not bool(head.keep))


func _send(c: Client, status: int, headers: Dictionary, body: Variant, close: bool) -> void:
	var b: PackedByteArray = body if body is PackedByteArray else String(body).to_utf8_buffer()
	if not headers.has("Content-Type") and not b.is_empty():
		headers["Content-Type"] = "text/plain; charset=utf-8"
	c.out.append_array(_response(status, headers, b, not close))
	if close:
		c.closing = true
	_flush(c)


const REASONS := {200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
	405: "Method Not Allowed", 408: "Request Timeout", 413: "Content Too Large", 415: "Unsupported Media Type", 431: "Request Header Fields Too Large",
	500: "Internal Server Error", 501: "Not Implemented", 503: "Service Unavailable", 504: "Gateway Timeout"}


static func _response(status: int, headers: Dictionary, body: PackedByteArray, keep: bool) -> PackedByteArray:
	var lines := ["HTTP/1.1 %d %s" % [status, REASONS.get(status, "Status")]]
	for k in headers:
		lines.append("%s: %s" % [k, headers[k]])
	lines.append("Content-Length: %d" % body.size())
	lines.append("Cache-Control: no-store")
	lines.append("X-Content-Type-Options: nosniff")
	lines.append("Connection: " + ("keep-alive" if keep else "close"))
	var out := ("\r\n".join(lines) + "\r\n\r\n").to_utf8_buffer()
	out.append_array(body)
	return out


func _host_ok(h: String) -> bool:
	h = h.to_lower()
	return h == "%s:%d" % [HOST, port] or h == "localhost:%d" % port


static func origin_ok(o: String) -> bool:
	var re := RegEx.create_from_string("^https?://(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?$")
	return re.search(o.to_lower()) != null


func _auth_ok(a: String) -> bool:
	var parts := a.strip_edges().split(" ", false)
	return parts.size() == 2 and parts[0].to_lower() == "bearer" and same(parts[1], get_token())


static func _plain(status: int, text: String, headers := {}) -> Dictionary:
	return {"status": status, "headers": headers, "body": text.to_utf8_buffer()}


static func _json(status: int, data: Variant, headers := {}) -> Dictionary:
	var h: Dictionary = headers.duplicate()
	h["Content-Type"] = "application/json"
	return {"status": status, "headers": h, "body": JSON.stringify(data, "", false).to_utf8_buffer()}


## Réponse HTTP à une requête : {status, headers, body}.
func route(head: Dictionary, body: PackedByteArray) -> Dictionary:
	var h: Dictionary = head.headers
	if not _host_ok(String(h.get("host", ""))):
		return _plain(403, "Forbidden: Host must be 127.0.0.1:%d or localhost:%d" % [port, port])
	if h.has("origin") and not origin_ok(String(h.origin)):
		return _plain(403, "Forbidden: Origin")
	var path := String(head.path).split("?")[0]
	if path != PATH:
		return _plain(404, "Not Found")
	if not _auth_ok(String(h.get("authorization", ""))):
		return _plain(401, "Unauthorized: Authorization: Bearer <token> (see the game: map editor > Collaboration > Connect an AI)")
	match String(head.method):
		"POST":
			return await _post(h, body)
		"DELETE":
			var sid := String(h.get("mcp-session-id", ""))
			if sid == "" or not sessions.has(sid):
				return _plain(404, "Not Found: unknown session")
			sessions.erase(sid)
			return {"status": 200, "headers": {}, "body": PackedByteArray()}
	return _plain(405, "Method Not Allowed", {"Allow": "POST, DELETE"})


func _post(h: Dictionary, body: PackedByteArray) -> Dictionary:
	if String(h.get("content-type", "")).split(";")[0].strip_edges().to_lower() != "application/json":
		return _plain(415, "Unsupported Media Type: application/json")
	var pv := String(h.get("mcp-protocol-version", ""))
	if pv != "" and not pv in PROTOCOLS:
		return _plain(400, "Bad Request: unsupported MCP-Protocol-Version %s (%s)" % [pv.left(20), ", ".join(PROTOCOLS)])
	var j := JSON.new()
	if j.parse(body.get_string_from_utf8()) != OK:
		return _json(400, rpc_error(null, -32700, "Parse error"))
	var data: Variant = j.data
	var batch := data is Array
	var msgs: Array = data if batch else [data]
	if msgs.is_empty():
		return _json(400, rpc_error(null, -32600, "Invalid Request: empty batch"))
	var init := msgs.any(func(m): return m is Dictionary and m.get("method") is String and m.method == "initialize" and m.has("id"))
	var headers := {}
	var session: Dictionary
	if init:
		var sid := _new_session()
		session = sessions[sid]
		headers["Mcp-Session-Id"] = sid
	else:
		var sid := String(h.get("mcp-session-id", ""))
		if sid == "":
			return _plain(400, "Bad Request: Mcp-Session-Id header required (initialize first)")
		if not sessions.has(sid):
			return _plain(404, "Not Found: unknown or closed session (initialize again)")
		session = sessions[sid]
	session.t = _clock
	var replies := []
	for m in msgs:
		var r: Variant = await handle_message(m, session)
		if r != null:
			replies.append(r)
	if replies.is_empty():
		return {"status": 202, "headers": headers, "body": PackedByteArray()}
	return _json(200, replies if batch else replies[0], headers)


func _new_session() -> String:
	if sessions.size() >= MAX_SESSIONS:
		var old := ""
		for k in sessions:
			if old == "" or float(sessions[k].t) < float(sessions[old].t):
				old = k
		sessions.erase(old)
	var sid := Crypto.new().generate_random_bytes(16).hex_encode()
	sessions[sid] = {"t": _clock, "rules": false, "version": PROTOCOLS[1], "ready": false}
	return sid


# ------------------------------------------------------------------ JSON-RPC / MCP

static func rpc_error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}


static func _ok(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


## Id JSON-RPC : entier rendu entier (les nombres JSON arrivent en float).
static func norm_id(id: Variant) -> Variant:
	if id is float and is_finite(id) and id == floorf(id) and absf(id) < 9.0e15:
		return int(id)
	return id


## Un message JSON-RPC : la réponse, ou null (notification, réponse du client).
func handle_message(m: Variant, session: Dictionary) -> Variant:
	if not m is Dictionary:
		return rpc_error(null, -32600, "Invalid Request")
	var msg: Dictionary = m
	if not msg.has("method"):
		if msg.has("result") or msg.has("error"):
			return null  # réponse du client à une requête que nous n'envoyons jamais
		return rpc_error(norm_id(msg.get("id")), -32600, "Invalid Request")
	if not (msg.get("jsonrpc") is String and msg.jsonrpc == "2.0") or not msg.method is String:
		return rpc_error(norm_id(msg.get("id")), -32600, "Invalid Request")
	var method := String(msg.method)
	if not msg.has("id"):
		if method == "notifications/initialized":
			session.ready = true
		return null
	var id: Variant = norm_id(msg.id)
	if not (id is String or id is int or id is float):
		return rpc_error(null, -32600, "Invalid Request: id")
	var params: Variant = msg.get("params", {})
	if params == null:
		params = {}
	if not params is Dictionary:
		return rpc_error(id, -32602, "Invalid params")
	match method:
		"initialize":
			var asked: Variant = params.get("protocolVersion")
			var version: String = String(asked) if asked is String and String(asked) in PROTOCOLS else PROTOCOLS[0]
			session.version = version
			return _ok(id, {
				"protocolVersion": version,
				"capabilities": {"tools": {"listChanged": false}, "resources": {"listChanged": false, "subscribe": false}, "prompts": {"listChanged": false}},
				"serverInfo": {"name": SERVER_NAME, "title": "Éditeur de cartes (Claude of Duty Zombie)", "version": String(ProjectSettings.get_setting("application/config/version", "1.0.0"))},
				"instructions": McpDocs.INSTRUCTIONS,
			})
		"ping":
			return _ok(id, {})
		"tools/list":
			return _ok(id, {"tools": tools.list()})
		"tools/call":
			if not params.get("name") is String:
				return rpc_error(id, -32602, "Invalid params: name requis")
			var args: Variant = params.get("arguments")
			if args == null:
				args = {}
			var res: Variant = await tools.call_tool(String(params.name), args)
			if not res is Dictionary:
				return rpc_error(id, -32603, "Internal error")
			if not bool(session.rules):
				# Premier appel d'outil de la session : règles de conception en tête.
				session.rules = true
				var asked_rules: bool = String(params.name) == "editor_guide" and args is Dictionary and args.get("topic") is String \
					and args.topic == "regles" and not (args.get("section") is String and String(args.section).strip_edges() != "")
				if not asked_rules:
					(res.content as Array).push_front(McpTools.text(McpDocs.rules_intro()))
			return _ok(id, res)
		"resources/list":
			return _ok(id, {"resources": McpDocs.resources()})
		"resources/templates/list":
			return _ok(id, {"resourceTemplates": []})
		"resources/read":
			var uri: Variant = params.get("uri")
			var r := McpDocs.read_resource(String(uri)) if uri is String else {}
			if r.is_empty():
				return rpc_error(id, -32002, "Resource not found: %s" % str(uri).left(120))
			return _ok(id, {"contents": [r]})
		"prompts/list":
			return _ok(id, {"prompts": McpDocs.prompts()})
		"prompts/get":
			var p := McpDocs.get_prompt(params.get("name"), params.get("arguments", {}))
			if p.has("error"):
				return rpc_error(id, -32602, String(p.error))
			return _ok(id, p)
	return rpc_error(id, -32601, "Method not found: %s" % method.left(80))
