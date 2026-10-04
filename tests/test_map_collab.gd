extends TestCase
## Session de l'éditeur collaboratif (MapCollab, docs/MAP_COLLAB.md § 3, 5.1,
## 8) : un hôte et un invité dans le même processus, sur 127.0.0.1. Cartes
## identiques après des changements croisés sur le même élément, code faux
## refusé, message invalide = déconnexion, rattrapage, annulation par auteur.
## Ports 17790+ (décalés par AUTOTEST_PORT_OFFSET).

const BASE := 17790


func _port(i: int) -> int:
	return BASE + i + OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()


func _map() -> EditorMap:
	var m := EditorMap.blank("essai", "ESSAI", "TEST")
	m.pieces = [{"id": "p1", "etage": 0, "nom": "Hall", "zone": "z1", "contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}]
	m.zones = [{"id": "z1", "nom": {"fr": "Hall", "en": "Hall"}}]
	m.depart = "z1"
	return m


func _until(cond: Callable, limit := 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > limit * 1000.0:
			return false
		await host.get_tree().process_frame
	return true


func _put(id: String, v: float) -> Array:
	return [{"op": "put", "coll": "objets", "el": {"id": id, "type": "caisse", "etage": 0, "position": [v, 4.0]}}]


## Hôte (Alice) et invité (Bob) connectés : [hôte, invité].
func _pair(i: int) -> Array:
	var h := MapCollab.new(_map())
	host.add_child(h)
	assert_eq(h.host(_port(i), "Alice"), OK, "hôte à l'écoute")
	var g := MapCollab.new(EditorMap.blank())
	host.add_child(g)
	g.join("127.0.0.1", _port(i), h.session_code.to_lower(), "Bob")
	var ok: bool = await _until(func(): return g.role == MapCollab.Role.GUEST and not g._joining)
	assert_true(ok, "invité accueilli")
	return [h, g]


func _settled(h: MapCollab, g: MapCollab) -> bool:
	return g.pending.is_empty() and g.seq == h.seq


func _end(list: Array) -> void:
	for n in list:
		n.leave()
		n.queue_free()
	await host.get_tree().process_frame


func test_guest_gets_the_map_and_peers() -> void:
	var p := await _pair(0)
	var h: MapCollab = p[0]
	var g: MapCollab = p[1]
	assert_eq(g.my_id, "2", "invité : id 2")
	assert_eq(MapOps.hash_of(g.doc), MapOps.hash_of(h.doc), "carte de l'hôte reçue")
	assert_eq(g.peers.size(), 2, "deux participants chez l'invité")
	assert_eq(h.peer_name("2"), "Bob", "pseudo connu de l'hôte")
	# Présence : curseur de Bob chez Alice.
	g.set_presence({"cursor": [3.5, 4.0], "floor": 0, "selection": ["p1"], "tool": "select"})
	assert_true(await _until(func(): return (h.peers["2"].presence as Dictionary).has("cursor")), "curseur de l'invité reçu")
	assert_eq(h.peers["2"].presence.cursor, [3.5, 4.0])
	await _end(p)


func test_simultaneous_changes_converge() -> void:
	var p := await _pair(1)
	var h: MapCollab = p[0]
	var g: MapCollab = p[1]
	# Même élément modifié des deux côtés dans la même image, plus des
	# changements d'éléments différents.
	h.submit_ops(_put("c1", 3.0), "hôte")
	g.submit_ops(_put("c1", 7.0), "invité")
	g.submit_ops(_put("c2", 5.0), "invité 2")
	h.submit_ops(_put("c3", 6.0), "hôte 2")
	var gb := g.doc.snapshot()
	g.doc.pieces[0]["nom"] = "Hall de Bob"
	g.submit_local(MapOps.diff(gb, g.doc), "nom", gb)
	assert_true(await _until(func(): return _settled(h, g)), "tout est confirmé")
	assert_eq(MapOps.hash_of(g.doc), MapOps.hash_of(h.doc), "cartes identiques (même empreinte)")
	assert_eq(float(h.doc.find("c1").position[0]), 7.0, "dernier arrivé chez l'hôte gagne (invité)")
	assert_eq(String(h.doc.pieces[0].nom), "Hall de Bob", "changement local de l'invité")
	assert_eq(h.history.entries.size(), g.history.entries.size(), "même historique")
	await _end(p)


func test_undo_by_author_across_editors() -> void:
	var p := await _pair(2)
	var h: MapCollab = p[0]
	var g: MapCollab = p[1]
	g.submit_ops(_put("a", 1.0) + _put("b", 1.0), "Bob pose")
	assert_true(await _until(func(): return _settled(h, g)))
	h.submit_ops(_put("a", 9.0), "Alice déplace")
	assert_true(await _until(func(): return _settled(h, g)))
	assert_true(h.request_undo().is_empty() == false, "Alice annule la sienne")
	h.submit_ops(_put("a", 9.0), "Alice redéplace")
	assert_true(await _until(func(): return _settled(h, g)))
	var u := g.request_undo()
	assert_eq(int(u.get("skipped", -1)), 1, "conflit : a modifié par Alice")
	assert_true(await _until(func(): return _settled(h, g)))
	assert_true(h.doc.find("b").is_empty() and g.doc.find("b").is_empty(), "b annulé des deux côtés")
	assert_eq(float(h.doc.find("a").position[0]), 9.0, "a gardé (Alice)")
	assert_eq(MapOps.hash_of(g.doc), MapOps.hash_of(h.doc), "cartes identiques")
	g.request_redo()
	assert_true(await _until(func(): return _settled(h, g)))
	assert_false(h.doc.find("b").is_empty(), "rétabli chez l'hôte")
	await _end(p)


func test_wrong_code_is_refused() -> void:
	var h := MapCollab.new(_map())
	host.add_child(h)
	h.host(_port(3), "Alice")
	var g := MapCollab.new(EditorMap.blank())
	host.add_child(g)
	var msgs := []
	g.message.connect(func(t, err): msgs.append([t, err]))
	for i in MapCollab.MAX_BAD_CODES:
		g.join("127.0.0.1", _port(3), "FAUX00", "Eve")
		assert_true(await _until(func(): return g.role == MapCollab.Role.SOLO), "code faux : refusé")
	assert_true(not msgs.is_empty() and msgs[-1][1], "message d'erreur")
	g.join("127.0.0.1", _port(3), h.session_code, "Eve")
	assert_true(await _until(func(): return g.role == MapCollab.Role.SOLO), "après 5 essais : refusé même avec le bon code")
	assert_eq(h.peers.size(), 1, "personne n'est entré")
	await _end([h, g])


func test_invalid_message_disconnects() -> void:
	var h := MapCollab.new(_map())
	host.add_child(h)
	h.host(_port(4), "Alice")
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", _port(4))
	assert_true(await _until(func(): tcp.poll(); return tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED), "connecté")
	tcp.put_data((JSON.stringify({"t": "hello", "proto": MapCollab.PROTO, "name": "Mallory", "code": h.session_code}) + "\n").to_utf8_buffer())
	assert_true(await _until(func(): return h.peers.size() == 2), "accueilli")
	# Changement avec un objet Godot sérialisé en texte et un id vide : invalide.
	tcp.put_data((JSON.stringify({"t": "change", "cid": "x", "ops": [{"op": "put", "coll": "objets", "el": {"id": ""}}]}) + "\n").to_utf8_buffer())
	assert_true(await _until(func(): return h.peers.size() == 1), "pair déconnecté")
	assert_true(h.doc.objets.is_empty(), "rien appliqué")
	# JSON illisible : aussi déconnecté.
	var t2 := StreamPeerTCP.new()
	t2.connect_to_host("127.0.0.1", _port(4))
	assert_true(await _until(func(): t2.poll(); return t2.get_status() == StreamPeerTCP.STATUS_CONNECTED))
	t2.put_data((JSON.stringify({"t": "hello", "proto": MapCollab.PROTO, "name": "M2", "code": h.session_code}) + "\n{pas du json\n").to_utf8_buffer())
	assert_true(await _until(func(): t2.poll(); return h._conns.is_empty() and h.peers.size() == 1), "JSON illisible : déconnecté")
	tcp.disconnect_from_host()
	t2.disconnect_from_host()
	await _end([h])


func test_checksum_triggers_resync() -> void:
	var p := await _pair(5)
	var h: MapCollab = p[0]
	var g: MapCollab = p[1]
	# Carte de l'invité abîmée en douce : l'empreinte de l'hôte la fait rattraper.
	g.doc.pieces[0]["nom"] = "Abîmé"
	var replaced := [0]
	g.map_replaced.connect(func(): replaced[0] += 1)
	h._sum_t = MapCollab.SUM_EVERY
	assert_true(await _until(func(): return replaced[0] > 0), "carte entière renvoyée")
	assert_eq(MapOps.hash_of(g.doc), MapOps.hash_of(h.doc), "cartes de nouveau identiques")
	# L'hôte quitte : l'invité repasse seul, la carte reste.
	h.leave()
	assert_true(await _until(func(): return g.role == MapCollab.Role.SOLO), "session terminée chez l'invité")
	assert_eq(String(g.doc.pieces[0].nom), "Hall", "la carte reste")
	await _end(p)


func test_editor_shares_its_changes() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	assert_true(ed.agent_link != null and MapEditor.mcp_server().editor() == ed.agent_link, "liaison de l'éditeur inscrite auprès du serveur MCP du jeu")
	assert_false(MapEditor.mcp_server().is_running(), "sans affichage : le serveur MCP du jeu n'écoute pas")
	assert_eq(ed.collab.host(_port(6), "Alice"), OK)
	var g := MapCollab.new(EditorMap.blank())
	host.add_child(g)
	g.join("127.0.0.1", _port(6), ed.collab.session_code, "Bob")
	assert_true(await _until(func(): return g.role == MapCollab.Role.GUEST and not g._joining), "invité accueilli")
	# Pose dans l'éditeur de l'hôte (push_undo + changed) : diffusée.
	var room := ed.add_object({"contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}, 0)
	assert_true(await _until(func(): return g.seq == ed.collab.seq), "changement reçu")
	assert_false(g.doc.find(String(room.id)).is_empty(), "pièce de l'hôte chez l'invité")
	# Changement de l'invité : visible dans l'éditeur de l'hôte.
	g.submit_ops([{"op": "put", "coll": "objets", "el": {"id": "c9", "type": "caisse", "etage": 0, "position": [4.0, 4.0]}}], "caisse")
	assert_true(await _until(func(): return not ed.doc.find("c9").is_empty()), "caisse de l'invité dans l'éditeur")
	assert_true(ed.status.text.contains("Bob"), "barre d'état : auteur du changement (%s)" % ed.status.text)
	# Ctrl+Z de l'hôte : sa pièce, pas la caisse de Bob.
	ed.undo()
	assert_true(ed.doc.find(String(room.id)).is_empty() and not ed.doc.find("c9").is_empty(), "Ctrl+Z : seulement l'action de l'hôte")
	assert_true(await _until(func(): return _settled(ed.collab, g)))
	assert_eq(MapOps.hash_of(g.doc), MapOps.hash_of(ed.doc), "cartes identiques")
	await _end([g])
	ed.queue_free()
	await wait_frames(1)


## TESTER à plusieurs (§ 5.3) : invitation de l'hôte (port contrôlé), refus
## d'un invité (motif nettoyé), annulation ; port invalide = session quittée.
func test_playtest_messages() -> void:
	var p := await _pair(7)
	var h: MapCollab = p[0]
	var g: MapCollab = p[1]
	var got_g := []
	var got_h := []
	g.playtest_message.connect(func(m): got_g.append(m))
	h.playtest_message.connect(func(m): got_h.append(m))
	assert_eq(g.host_address(), "127.0.0.1", "adresse de l'hôte connue de l'invité")
	assert_eq(h.human_guests(), ["2"], "un invité humain chez l'hôte")
	h.send_playtest(17800)
	assert_true(await _until(func(): return got_g.size() == 1), "invitation reçue")
	assert_eq(got_g[0], {"t": "playtest", "port": 17800})
	g.send_playtest_status(false, "déjà" + char(0x202E) + " dans une partie", "already in a game\n")
	assert_true(await _until(func(): return got_h.size() == 1), "refus de l'invité reçu")
	assert_eq(got_h[0].peer, "2")
	assert_false(got_h[0].ok)
	assert_eq(got_h[0].reason_fr, "déjà dans une partie", "motif sans caractère de contrôle")
	assert_eq(got_h[0].reason_en, "already in a game")
	h.send_playtest_cancel()
	assert_true(await _until(func(): return got_g.size() == 2), "annulation reçue")
	assert_eq(got_g[1].t, "playtest_cancel")
	assert_eq(g.role, MapCollab.Role.GUEST, "toujours dans la session")
	# Port hors 1024-65535 : message invalide, l'invité quitte la session.
	h._broadcast({"t": "playtest", "port": 80})
	assert_true(await _until(func(): return g.role == MapCollab.Role.SOLO), "port invalide : session quittée")
	assert_eq(got_g.size(), 2, "rien transmis à l'éditeur")
	await _end(p)


## Une session qui change de parent avec keep_alive (partie de TESTER) reste
## ouverte ; sans, sortir de l'arbre la quitte.
func test_keep_alive_survives_reparent() -> void:
	var p := await _pair(8)
	var h: MapCollab = p[0]
	var g: MapCollab = p[1]
	var holder := Node.new()
	host.add_child(holder)
	g.keep_alive = true
	g.reparent(holder, false)
	g.keep_alive = false
	await wait_frames(2)
	assert_eq(g.role, MapCollab.Role.GUEST, "invité toujours dans la session")
	h.submit_ops(_put("k1", 3.0), "caisse")
	assert_true(await _until(func(): return not g.doc.find("k1").is_empty()), "changement reçu après le changement de parent")
	host.remove_child(h)
	assert_eq(h.role, MapCollab.Role.SOLO, "sortie de l'arbre sans keep_alive : session fermée")
	h.free()
	assert_true(await _until(func(): return g.role == MapCollab.Role.SOLO), "l'invité est prévenu")
	await _end([g])
	holder.queue_free()


## Retour d'un TESTER à plusieurs : l'éditeur qui revient reprend la session
## tenue pendant la partie (même nœud, même carte, même historique), avec
## son dossier, sa sélection et sa vue.
func test_editor_takes_the_session_back() -> void:
	var m := _map()
	var c := MapCollab.new(m)
	c.name = "Collab"
	c.submit_ops(_put("t1", 4.0), "caisse")
	var pt := CollabPlaytest.new()
	pt.collab = c
	pt.phase = CollabPlaytest.Phase.PLAYING
	pt.editor_state = {"map_dir": "user://maps/essai", "example": false, "dirty": true, "floor_k": 0, "selected": "t1",
		"zoom": 31.0, "origin": Vector2(12, 34)}
	host.add_child(pt)
	pt.add_child(c)
	CollabPlaytest.current = pt
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	assert_true(ed.collab == c and c.get_parent() == ed, "session reprise par l'éditeur")
	assert_true(CollabPlaytest.current == null, "test terminé")
	assert_true(ed.doc == m and not ed.doc.find("t1").is_empty(), "même carte")
	assert_eq(c.history.undo_count(c.my_id), 1, "historique gardé")
	assert_eq(ed.map_dir, "user://maps/essai")
	assert_true(ed.dirty, "modifications non enregistrées gardées")
	assert_eq(ed.selected, "t1", "sélection gardée")
	assert_eq(ed.canvas.zoom, 31.0, "vue gardée")
	assert_true(ed.status.text.contains("Retour du test") or ed.status.text.contains("Back from the play test"), "barre d'état : %s" % ed.status.text)
	await wait_frames(1)
	assert_false(is_instance_valid(pt), "nœud du test libéré")
	ed.queue_free()
	await wait_frames(1)
