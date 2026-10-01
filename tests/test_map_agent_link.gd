extends TestCase
## Liaison agent de l'éditeur (MapAgentLink, docs/MAP_COLLAB.md § 5.2) : un
## client TCP de test fait ce que fera le pont MCP. Jeton bon et mauvais,
## get_map, apply avec ids provisoires « $1 », undo, validate, capture
## refusée sans affichage. agent.json écrit dans tests/_out, jamais chez le
## joueur. Ports 17891+ (décalés par AUTOTEST_PORT_OFFSET).

const BASE := 17891

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


func _connect(port: int) -> StreamPeerTCP:
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", port)
	await _until(func(): tcp.poll(); return tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED)
	return tcp


## Envoie une requête et attend SA réponse (les événements poussés sont passés).
func _req(tcp: StreamPeerTCP, cmd: String, args := {}) -> Dictionary:
	_n += 1
	tcp.put_data((JSON.stringify({"id": _n, "cmd": cmd, "args": args}) + "\n").to_utf8_buffer())
	var buf := PackedByteArray()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		tcp.poll()
		var n := tcp.get_available_bytes()
		if n > 0:
			buf.append_array(tcp.get_partial_data(n)[1])
		var i := buf.find(10)
		while i >= 0:
			var msg: Variant = JSON.parse_string(buf.slice(0, i).get_string_from_utf8())
			buf = buf.slice(i + 1)
			if msg is Dictionary and int(msg.get("id", -1)) == _n:
				return msg
			i = buf.find(10)
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return {"closed": true}
		await host.get_tree().process_frame
	return {}


func test_agent_link_commands() -> void:
	MapAgentLink.dir_override = ProjectSettings.globalize_path("res://tests/_out/agent_link_test")
	var m := EditorMap.blank("essai", "ESSAI", "TEST")
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	assert_eq(link.start(BASE + _off(), BASE + 8 + _off()), OK, "écoute locale")
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(MapAgentLink.file_path()))
	assert_true(info is Dictionary and int(info.port) == link.port and String(info.token).length() == 32, "agent.json : port et jeton")
	# Mauvais jeton : refusé et coupé.
	var bad := await _connect(link.port)
	var r := await _req(bad, "hello", {"token": "0".repeat(32), "client": "claude-mcp"})
	assert_false(bool(r.get("ok", true)), "mauvais jeton refusé")
	var bad2 := await _connect(link.port)
	r = await _req(bad2, "get_map")
	assert_false(bool(r.get("ok", true)), "commande avant hello refusée")
	# Bon jeton.
	var tcp := await _connect(link.port)
	r = await _req(tcp, "hello", {"token": String(info.token), "client": "claude-mcp"})
	assert_true(bool(r.get("ok", false)), "hello accepté : %s" % str(r))
	assert_eq(String(r.result.role), "solo")
	assert_true(await _until(func(): return collab.peers.has("1:claude")), "Claude dans les participants")
	r = await _req(tcp, "get_map")
	assert_true((r.result as Dictionary).has("pieces"), "get_map : carte complète")
	# apply : pièce + porte + arme avec ids provisoires, et un élément refusé.
	r = await _req(tcp, "apply", {"label": "deux pièces", "ops": [
		{"op": "add", "coll": "pieces", "el": {"id": "$1", "nom": "Hall", "contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}},
		{"op": "add", "coll": "pieces", "el": {"id": "$2", "contour": [[10, 2], [16, 2], [16, 8], [10, 8]]}},
		{"op": "add", "coll": "ouvertures", "el": {"id": "$3", "type": "porte", "position": [10, 5], "largeur": 2}},
		{"op": "add", "coll": "objets", "el": {"id": "$4", "type": "fusee", "position": [4, 4]}},
	]})
	assert_true(bool(r.get("ok", false)), "apply accepté : %s" % str(r))
	var res: Dictionary = r.get("result", {})
	assert_eq(res.get("ids", {}).get("$1", ""), "p1", "$1 -> p1")
	assert_true((res.get("invalid", {}) as Dictionary).has(String(res.ids.get("$4", ""))), "type inconnu listé dans invalid")
	assert_eq(m.pieces.size(), 2, "deux pièces posées")
	assert_eq(m.zones.size(), 2, "une zone par pièce")
	assert_eq(collab.history.entries.size(), 1, "un lot = une entrée d'historique")
	assert_eq(String(collab.history.entries[0].author), "1:claude", "auteur : le Claude de l'éditeur")
	r = await _req(tcp, "validate")
	assert_true(bool(r.get("ok", false)) and (r.result as Dictionary).has("text"), "validate : rapport")
	r = await _req(tcp, "screenshot", {"floor": 0})
	assert_false(bool(r.get("ok", true)), "capture refusée sans affichage")
	r = await _req(tcp, "catalog")
	assert_true(bool(r.get("ok", false)) and (r.result.kinds as Dictionary).has("porte"), "catalogue")
	# undo : le lot de Claude entier.
	r = await _req(tcp, "undo")
	assert_true(bool(r.get("ok", false)), "undo accepté : %s" % str(r))
	assert_true(m.pieces.is_empty() and m.ouvertures.is_empty() and m.zones.is_empty(), "lot annulé d'un coup")
	r = await _req(tcp, "undo")
	assert_false(bool(r.get("ok", true)), "plus rien à annuler")
	r = await _req(tcp, "frobnicate")
	assert_false(bool(r.get("ok", true)), "commande inconnue")
	link.stop()
	assert_false(FileAccess.file_exists(MapAgentLink.file_path()), "agent.json supprimé à l'arrêt")
	for t in [bad, bad2, tcp]:
		t.disconnect_from_host()
	link.queue_free()
	collab.queue_free()
	MapAgentLink.dir_override = ""
	await host.get_tree().process_frame
