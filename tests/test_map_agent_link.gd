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


## Vues multiples (docs/EDITOR_VIEWS.md § 6.4) : get_elements rend les
## hauteurs (boîte, altitude de pose, type de glissement) ; une vue inconnue
## est refusée pour la capture.
func test_elements_with_heights_and_views() -> void:
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m.objets.append({"id": "fx1", "type": "effet", "effet": "torche", "etage": 0, "position": [9.5, 4.5], "mur": "n", "hauteur": 2.4})
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var r := link.cmd_get_elements({"ids": ["p3", "p5", "fx1", "o5", "zz"]})
	assert_near(float(r.elements.p3.z_max), 6.8, 0.001, "entrepôt en double hauteur : jusqu'à 6,80 m")
	assert_near(float(r.elements.p5.z_monde), 3.5, 0.001, "passerelle : sol de l'étage 1")
	assert_eq(String(r.elements.p5.glissement_vertical), "niveau")
	assert_near(float(r.elements.fx1.hauteur_pose), 2.4, 0.001, "torche : hauteur de pose")
	assert_near(float(r.elements.fx1.z_monde), 2.4, 0.001)
	assert_eq(String(r.elements.o5.glissement_vertical), "fixe")
	assert_near(float(r.elements.o5.z_min), MapValidator.SILL, 0.001, "fenêtre : de l'allège")
	assert_eq(r.absents, ["zz"])
	var s: Dictionary = await link.cmd_screenshot({"view": "biais"})
	assert_true(s.has("error") and String(s.error).contains("biais"), "vue inconnue refusée : %s" % s)
	link.queue_free()
	collab.queue_free()


## Format 14 (docs/EDITOR_SCALE_ROTATE.md § 6) : dimensions et possibilités
## d'échelle des éléments, « put » d'une échelle (arrondie au pas), refus qui
## nomme l'objet de jeu d'un prefab bloqué, catalogue.
func test_scale_through_the_agent_link() -> void:
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m.objets.append({"id": "d90", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [12.0, 7.5]})
	m.prefabs["coin_pap"] = preload("res://tests/test_map_scale.gd").PAP_DEF.duplicate(true)
	m.objets.append({"id": "d93", "type": "prefab", "prefab": "map:coin_pap", "etage": 0, "position": [5.0, 26.0]})
	m.activate_prefabs()
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var r := link.cmd_get_elements({"ids": ["d90", "d93", "b1"]})
	assert_eq(r.elements.d90.dimensions, [2.5, 2.0, 1.5], "dimensions finales")
	assert_true(bool(r.elements.d90.echelle_possible) and bool(r.elements.d90.inclinaison_possible), "décor : échelle et inclinaison")
	assert_false(bool(r.elements.d93.echelle_possible), "prefab avec un Pack-a-Punch : bloqué")
	assert_true(String(r.elements.d93.get("raison", "")).contains("Pack-a-Punch"), "raison qui nomme l'objet : %s" % r.elements.d93.get("raison", ""))
	var el: Dictionary = m.find("d90").duplicate(true)
	el["echelle"] = [1.234, 1.234, 1.234]
	var a := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": el}], "label": "Pile agrandie", "animate": false})
	assert_false(a.has("error"), str(a))
	assert_true(MapScale.scale_of(collab.doc.find("d90")).is_equal_approx(Vector3.ONE * 1.23), "arrondie au pas de 0,01 (%s)" % str(collab.doc.find("d90").get("echelle")))
	var k: Dictionary = m.find("d93").duplicate(true)
	k["echelle"] = [2, 2, 2]
	var b := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": k}], "label": "Coin agrandi", "animate": false})
	assert_true((b.invalid as Dictionary).has("d93") and String(b.invalid.d93).contains("Pack-a-Punch"), "refus nommé : %s" % str(b.invalid))
	assert_false(collab.doc.find("d93").has("echelle"), "prefab bloqué : inchangé")
	var cat := MapAgentLink.catalog()
	var pap: Array = (cat.items as Array).filter(func(it): return String(it.id) == "pap")
	assert_true(not pap.is_empty() and pap[0].get("echelle", true) == false, "catalogue : le Pack-a-Punch garde sa taille")
	assert_true(bool(cat.prefabs.poutre.inclinaison) and not bool(cat.prefabs.torche_murale.inclinaison), "catalogue : inclinaison au sol seulement")
	link.queue_free()
	collab.queue_free()


## Nombre de marches d'un escalier : plus réglable. Claude (editor_apply) qui
## en écrit un est refusé avec un message clair ; le schéma d'écriture
## (catalogue) ne le propose plus ; la LECTURE des cartes d'avant l'admet.
func test_stair_steps_refused_through_the_agent_link() -> void:
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var st := {"id": "e70", "type": "escalier", "etage": 0, "rect": [4.0, 4.0, 6.0, 8.0], "monte": "n", "marches": 12}
	var a := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": st}], "label": "Escalier", "animate": false})
	assert_true((a.invalid as Dictionary).has("e70") and String(a.invalid.e70).contains("marches"), "refus nommé : %s" % str(a))
	assert_true(collab.doc.find("e70").is_empty(), "escalier non appliqué")
	var cat := MapAgentLink.catalog()
	assert_false((cat.kinds.escalier.keys as Dictionary).has("marches"), "schéma d'écriture : plus de « marches »")
	assert_true((MapCatalog.allowed_kinds().escalier.keys as Dictionary).has("marches"), "lecture des cartes d'avant : admis")
	link.queue_free()
	collab.queue_free()


## Revue : Claude (MCP) passe par les mêmes règles que l'éditeur (plafond,
## décor posé dessus).
func test_mcp_scale_follows_editor_rules() -> void:
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m.objets.append({"id": "d80", "type": "prefab", "prefab": "etagere", "etage": 0, "position": [20.0, 9.0]})
	m.objets.append({"id": "d81", "type": "prefab", "prefab": "sacs_sable", "etage": 0, "position": [19.0, 14.5]})
	m.objets.append({"id": "d82", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [19.0, 14.5], "z": 0.9})
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var tall: Dictionary = m.find("d80").duplicate(true)
	tall["echelle"] = [4, 4, 4]
	var a := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": tall}], "label": "Étagère géante", "animate": false})
	assert_true((a.invalid as Dictionary).has("d80"), "étagère × 4 sous le plafond : refusée (%s)" % str(a))
	assert_false(collab.doc.find("d80").has("echelle"), "carte inchangée")
	var tilt: Dictionary = m.find("d81").duplicate(true)
	tilt["incl"] = [0, 20]
	var b := link.cmd_apply({"ops": [{"op": "put", "coll": "objets", "el": tilt}], "label": "Sacs inclinés", "animate": false})
	assert_true((b.invalid as Dictionary).has("d81") and String(b.invalid.d81).contains("posé dessus"), "porteur incliné : refusé (%s)" % str(b))
	link.queue_free()
	collab.queue_free()
