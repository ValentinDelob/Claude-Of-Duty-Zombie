extends AutotestScenario
## Anneaux de rotation des vues planes (format 14, docs/EDITOR_SCALE_ROTATE.md
## § 3.2) dans le vrai éditeur : anneau Z en vue Dessus (crans de 15°, à la
## place de la poignée ronde), anneau Y en vue Avant (poutre inclinée de
## +30°, posée au sol, bout est en bas), valeur tapée (« 45 » + Entrée),
## anneau X en vue Droite (sens : le bout nord descend), refus (trop haut
## pour le plafond), Échap ; un geste = une annulation.

const Free := preload("res://tests/test_map_decor_free.gd")

var ed: MapEditor


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var rest0: Variant = MapEditor.pref(MapPanelsScale.PREF_REST, true)
	MapEditor.set_pref(MapPanelsScale.PREF_REST, true)
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	var doc := Free.two_rooms()
	doc.pieces[1]["plafond"] = 6.8
	doc.objets.append({"id": "d71", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [4.0, 4.0]})
	doc.objets.append({"id": "d72", "type": "prefab", "prefab": "poutre", "etage": 0, "position": [19.0, 5.5]})
	doc.objets.append({"id": "d73", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [10.0, 4.0]})
	ed._reset(doc)
	ed.views.setup("2v", ["dessus", "avant"])
	var cv := ed.canvas
	cv.zoom = 30.0
	cv.origin = Vector2(40, 40)
	await frames(3)
	var undo0 := ed.collab.history.undo_count(ed.collab.my_id)

	# Anneau Z : la prise au nord, tournée de 37° -> 30° (cran de 15°).
	ed.select("d71")
	await frames(2)
	at.check(cv.rot_handle().is_empty(), "pas de poignée ronde pour le décor : l'anneau Z")
	var rg := cv.gizmo.ring_of(ed.doc.find("d71"))
	at.check(not rg.is_empty() and float(rg.r) >= MapGizmo.RING_MIN * EditorUi.factor() - 0.01, "anneau Z (rayon %.0f px)" % float(rg.get("r", 0)))
	var c: Vector2 = rg.c
	var g := c + Vector2(0, -float(rg.r))
	await _drag_px(cv, g, c + (g - c).rotated(deg_to_rad(37.0)))
	at.check(MapGeom.rot_of(ed.doc.find("d71")) == 30, "Z : 30° (%d)" % MapGeom.rot_of(ed.doc.find("d71")))
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == undo0 + 1, "un geste = une annulation")

	# Anneau Y (vue Avant) : poutre, +30° ; le bout est descend, posée au sol.
	ed.select("d72")
	var av: MapElevation = ed.views.panes[1].view
	av.zoom = 30.0
	av.origin = Vector2(av.size.x * 0.5 - 19.0 * 30.0, av.size.y - 40.0)
	await frames(3)
	var e := av.projected_of("d72")
	var ry := av.tools.gizmo.ring_of(e)
	at.check(not ry.is_empty() and int(ry.axis) == 1, "anneau Y en vue Avant")
	if not ry.is_empty():
		var c2: Vector2 = ry.c
		var g2 := c2 + Vector2(0, -float(ry.r))
		await _drag_px(av, g2, c2 + (g2 - c2).rotated(deg_to_rad(32.0)))
		var b := ed.doc.find("d72")
		at.check(MapScale.incl_of(b).is_equal_approx(Vector2(0, 30)) and MapVertical.decor_z(b) == 0.0, "Y +30°, posée au sol (%s)" % str(MapScale.incl_of(b)))
		var ze := _side_z(b, 0, 1.0)
		var zw := _side_z(b, 0, -1.0)
		at.check(ze < zw, "sens : le bout est descend (est %.2f, ouest %.2f)" % [ze, zw])
		# Valeur tapée : 15 puis Entrée (de plus que les 30° : 45°).
		e = av.projected_of("d72")
		ry = av.tools.gizmo.ring_of(e)
		c2 = ry.c
		g2 = c2 + Vector2(0, -float(ry.r))
		_mouse(av, g2, -1)
		_mouse(av, g2, 1)
		_mouse(av, g2 + Vector2(3, 0), -1)
		for ch in ["1", "5"]:
			var k := InputEventKey.new()
			k.pressed = true
			k.keycode = KEY_1 if ch == "1" else KEY_5
			k.unicode = ch.unicode_at(0)
			av.tools.handle_key(k)
		var ke := InputEventKey.new()
		ke.pressed = true
		ke.keycode = KEY_ENTER
		av.tools.handle_key(ke)
		_mouse(av, g2 + Vector2(3, 0), 0)
		await frames(2)
		at.check(is_equal_approx(MapScale.incl_of(ed.doc.find("d72")).y, 45.0), "valeur tapée 15 : Y 45° (%s ; %s)" % [str(MapScale.incl_of(ed.doc.find("d72"))), ed.status.text])
		# Échap : rien ne change.
		var before := ed.doc.find("d72").duplicate(true)
		e = av.projected_of("d72")
		ry = av.tools.gizmo.ring_of(e)
		c2 = ry.c
		g2 = c2 + Vector2(0, -float(ry.r))
		_mouse(av, g2, -1)
		_mouse(av, g2, 1)
		_mouse(av, c2 + (g2 - c2).rotated(deg_to_rad(-40.0)), -1)
		var esc := InputEventKey.new()
		esc.pressed = true
		esc.keycode = KEY_ESCAPE
		av.tools.handle_key(esc)
		await frames(1)
		at.check(ed.doc.find("d72") == before, "Échap : geste annulé")

	# Vue Droite : anneau X ; sens (le bout nord descend).
	ed.views.set_pane_plane(ed.views.panes[1], "droite")
	await frames(3)
	var dv: MapElevation = ed.views.panes[1].view
	ed.select("d73")
	await frames(2)
	var ed71 := dv.projected_of("d73")
	var rx := dv.tools.gizmo.ring_of(ed71) if not ed71.is_empty() else {}
	at.check(not rx.is_empty() and int(rx.axis) == 0, "anneau X en vue Droite")
	if not rx.is_empty():
		var c3: Vector2 = rx.c
		var g3 := c3 + Vector2(0, -float(rx.r))
		await _drag_px(dv, g3, c3 + (g3 - c3).rotated(deg_to_rad(15.0)))
		var cr := ed.doc.find("d73")
		at.check(is_equal_approx(MapScale.incl_of(cr).x, 15.0), "X +15° (%s)" % str(MapScale.incl_of(cr)))
		var zn := _side_z(cr, 1, -1.0)
		var zs := _side_z(cr, 1, 1.0)
		at.check(zn < zs, "sens : le bout nord descend (nord %.2f, sud %.2f)" % [zn, zs])
	MapEditor.set_pref(MapPanelsScale.PREF_REST, rest0)


## Hauteur moyenne des coins d'un côté de la boîte (axe 0 : x, 1 : y ; `sgn` : côté).
func _side_z(o: Dictionary, axis: int, sgn: float) -> float:
	var c := MapGeom.v2(o.position)
	var sum := 0.0
	var n := 0
	for q in MapScale.corners(o):
		var v3 := q as Vector3
		if (v3[axis] - c[axis]) * sgn > 0.0:
			sum += v3.z
			n += 1
	return sum / maxf(n, 1)


func _drag_px(v: MapView, a: Vector2, b: Vector2) -> void:
	_mouse(v, a, -1)
	_mouse(v, a, 1)
	for i in 6:
		_mouse(v, a.lerp(b, (i + 1) / 6.0), -1)
		await frames(1)
	_mouse(v, b, 0)
	await frames(1)


## Souris dans la vue (px) : `press` -1 mouvement, 1 appui, 0 relâché.
func _mouse(v: MapView, px: Vector2, press: int) -> void:
	if press < 0:
		var mm := InputEventMouseMotion.new()
		mm.position = px
		v._gui_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.position = px
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = press == 1
	v._gui_input(mb)
