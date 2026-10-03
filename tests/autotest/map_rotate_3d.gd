extends AutotestScenario
## @rendu : gizmo de rotation de la vue 3D (format 14,
## docs/EDITOR_SCALE_ROTATE.md § 3.2, maquette écran 2) dans le vrai
## éditeur : trois anneaux autour de la poutre choisie (X et Y : elle
## s'incline ; aucun pour un décor mural), anneau Y glissé de 30° (crans de
## 15°), seuls les nœuds de la poutre bougent dans l'aperçu pendant le geste,
## une annulation au relâché ; mesure : moins de 2 ms par mouvement de
## souris sur une carte de 50 pièces et 2000 objets (captures : map_scale_look).

const Objects := preload("res://tests/test_map_objects.gd")

var ed: MapEditor


func run() -> void:
	timeout_sec = 150
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	var doc := Objects.objects_map()
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	doc.pieces[0]["plafond"] = 6.8
	doc.find("s1")["position"] = [6.0, 8.5]
	doc.objets.append({"id": "d91", "type": "prefab", "prefab": "poutre", "etage": 0, "position": [5.0, 3.5]})
	doc.objets.append({"id": "d94", "type": "prefab", "prefab": "torche_murale", "etage": 0, "position": [2.0, 10.0], "mur": "s"})
	ed._reset(doc)
	ed.views.setup("3b", ["3d", "dessus", "avant"])
	await frames(5)
	var pv := ed.preview
	if pv == null or pv.gizmo == null:
		at.fail("aperçu 3D ou gizmo absent")
		return
	pv.world.rebuild_now()
	ed.select("d91")
	pv.center_on_selection()
	await frames(10)
	var gz := pv.gizmo
	at.check(MapGizmo3D.axes_of(ed.doc.find("d91")) == [0, 1, 2], "poutre : anneaux X, Y, Z")
	var c := gz.center3(ed.doc.find("d91"))
	var r := gz.radius_m(c)
	var pts := gz.ring_px(c, r, 1)
	at.check(pts.size() > 10, "anneau Y projeté à l'écran")
	if pts.size() <= 10:
		return
	var undo0 := ed.collab.history.undo_count(ed.collab.my_id)
	var nodes := gz._nodes_of("d91")
	at.check(not nodes.is_empty(), "nœuds de la poutre dans l'aperçu (%d)" % nodes.size())
	var t0: Transform3D = (nodes.keys()[0] as Node3D).global_transform if not nodes.is_empty() else Transform3D()
	_mouse(pv, pts[0], -1)
	_mouse(pv, pts[0], 1)
	at.check(not gz.drag.is_empty() and int(gz.drag.axis) == 1, "anneau Y attrapé")
	for i in range(1, 7):
		_mouse(pv, pts[i], -1)
		await frames(1)
	await frames(3)
	var moved := not nodes.is_empty() and not (nodes.keys()[0] as Node3D).global_transform.is_equal_approx(t0)
	at.check(moved, "pendant le geste, la poutre tourne dans l'aperçu (nœuds déplacés)")
	_mouse(pv, pts[6], 0)
	await frames(2)
	var b := ed.doc.find("d91")
	at.check(MapScale.incl_of(b).is_equal_approx(Vector2(0, 30)), "Y +30° (%s)" % str(MapScale.incl_of(b)))
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == undo0 + 1, "une annulation au relâché")
	await until(func(): return pv.world.idle() and not pv.world.is_stale(), 15.0, "aperçu reconstruit")
	await frames(5)
	# Revue : angle tapé puis Entrée sans bouger la souris.
	await until(func(): return pv.world.idle() and not pv.world.is_stale(), 15.0, "aperçu reconstruit")
	c = gz.center3(ed.doc.find("d91"))
	pts = gz.ring_px(c, gz.radius_m(c), 2)
	# Prise à 45° sur l'anneau Z (à 0° et 90° il croise les anneaux X et Y).
	_mouse(pv, pts[9], -1)
	_mouse(pv, pts[9], 1)
	for kc in [KEY_4, KEY_5, KEY_ENTER]:
		_key(pv, kc)
	await frames(2)
	at.check(MapGeom.rot_of(ed.doc.find("d91")) == 45 and gz.drag.is_empty(), "Z tapé « 45 » + Entrée sans bouger : 45° (%d)" % MapGeom.rot_of(ed.doc.find("d91")))
	_mouse(pv, pts[9], 0)
	# Revue : changement d'un autre (Claude) pendant le geste : gardé après Échap,
	# le geste n'est pas compté avec lui.
	c = gz.center3(ed.doc.find("d91"))
	pts = gz.ring_px(c, gz.radius_m(c), 1)
	var undo1 := ed.collab.history.undo_count(ed.collab.my_id)
	_mouse(pv, pts[6], -1)
	_mouse(pv, pts[6], 1)
	for i in range(7, 11):
		_mouse(pv, pts[i], -1)
		await frames(1)
	ed.collab.submit_ops([{"op": "put", "coll": "objets", "el": {"id": "d96", "type": "caisse", "etage": 0, "position": [10.0, 8.0]}}], "caisse de Claude", ed.collab.my_id + ":claude")
	await frames(1)
	_key(pv, KEY_ESCAPE)
	await frames(2)
	at.check(not ed.doc.find("d96").is_empty(), "changement de Claude gardé après Échap")
	at.check(MapScale.incl_of(ed.doc.find("d91")).is_equal_approx(Vector2(0, 30)), "geste annulé : inclinaison d'avant")
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == undo1 + 1 and String(ed.collab.history.entries[-1].label).contains("caisse de Claude"),
		"historique : le seul changement de Claude (le geste annulé n'y est pas)")
	# Revue : disposition changée pendant le geste : geste annulé, aperçu jamais figé.
	_mouse(pv, pts[6], -1)
	_mouse(pv, pts[6], 1)
	_mouse(pv, pts[9], -1)
	await frames(1)
	ed.views.set_layout("2v")
	await frames(3)
	at.check(gz.drag.is_empty() and pv.world.auto, "disposition changée : geste annulé, aperçu repart")
	at.check(MapScale.incl_of(ed.doc.find("d91")).is_equal_approx(Vector2(0, 30)), "rien d'écrit")
	ed.views.set_layout("3b")
	await frames(5)
	ed.select("d94")
	await frames(2)
	at.check(gz.target().is_empty(), "décor mural : pas d'anneau en 3D")

	# Mesure : carte de 50 pièces et 2000 objets.
	var big := EditorMap.blank("grande", "GRANDE", "BIG")
	for row in 2:
		for col in 25:
			var x0 := 2.0 + col * 6.0
			var y0 := 4.0 + row * 6.0
			var z := big.add_zone("S", "R")
			big.pieces.append({"id": big.new_id("p"), "nom": "S", "etage": 0, "zone": String(z.id), "plafond": 6.8,
				"contour": [[x0, y0], [x0 + 6, y0], [x0 + 6, y0 + 6], [x0, y0 + 6]]})
	for i in 2000:
		@warning_ignore("integer_division")
		big.objets.append({"id": big.new_id("q"), "type": "apparition", "etage": 0, "position": [3.0 + (i % 148), 11.0 + (i / 148) * 0.05]})
	big.objets.append({"id": "d95", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [6.0, 6.5]})
	ed._reset(big)
	await frames(3)
	pv.world.rebuild_now()
	ed.select("d95")
	pv.center_on_selection()
	await frames(10)
	var c2 := gz.center3(ed.doc.find("d95"))
	var p2 := gz.ring_px(c2, gz.radius_m(c2), 2)
	if p2.size() <= 10:
		at.fail("anneau Z de la grande carte absent")
		return
	_mouse(pv, p2[0], -1)
	_mouse(pv, p2[0], 1)
	var worst := 0
	var total := 0
	var n := 0
	for i in range(1, 40):
		var t1 := Time.get_ticks_usec()
		_mouse(pv, p2[i % p2.size()], -1)
		var dt := Time.get_ticks_usec() - t1
		total += dt
		worst = maxi(worst, dt)
		n += 1
		await frames(1)
	_mouse(pv, p2[39 % p2.size()], 0)
	print("    gizmo 3D, 2000 objets : %.2f ms par mouvement en moyenne (pire %.2f ms)" % [total / 1000.0 / n, worst / 1000.0])
	at.check(total / 1000.0 / n < 2.0, "moins de 2 ms par mouvement de souris (%.2f ms en moyenne)" % (total / 1000.0 / n))


func _key(pv: MapPreviewPanel, kc: int) -> void:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = kc
	if kc in [KEY_4, KEY_5]:
		k.unicode = ("4" if kc == KEY_4 else "5").unicode_at(0)
	pv._view_key(k)


## Souris dans l'aperçu (px de la vue) : `press` -1 mouvement, 1 appui, 0 relâché.
func _mouse(pv: MapPreviewPanel, px: Vector2, press: int) -> void:
	if press < 0:
		var mm := InputEventMouseMotion.new()
		mm.position = px
		pv._view_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.position = px
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = press == 1
	pv._view_input(mb)
