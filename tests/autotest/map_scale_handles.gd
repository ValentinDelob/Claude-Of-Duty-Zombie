extends AutotestScenario
## Poignées d'échelle (format 14, docs/EDITOR_SCALE_ROTATE.md § 2.4) dans
## le vrai éditeur : en vue Dessus, coin sud-est de la pile de caisses tiré
## (×1,50 uniforme, coin nord-ouest fixe, aimanté au pas de 0,25 en grille
## 1 m), face est (X seul, côté ouest fixe), valeur tapée (« 2 » + Entrée) ;
## en vue Avant, losange du haut (Z seul, base au sol) ; prefab qui contient
## un Pack-a-Punch : cadenas aux coins, refus nommé ; Échap annule ; un geste
## = une annulation.

const Free := preload("res://tests/test_map_decor_free.gd")
const Scale := preload("res://tests/test_map_scale.gd")

var ed: MapEditor


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	var doc := Free.two_rooms()
	doc.prefabs["coin_pap"] = Scale.PAP_DEF.duplicate(true)
	doc.objets.append({"id": "c1", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [4.0, 4.0]})
	doc.objets.append({"id": "k1", "type": "prefab", "prefab": "map:coin_pap", "altitude": 0, "position": [19.0, 4.0]})
	for o in doc.objets:
		if String(o.type) == "depart":
			o["position"] = [11.0, 8.0]
	ed._reset(doc)
	ed.doc.activate_prefabs()
	var cv := ed.canvas
	cv.zoom = 40.0
	cv.origin = Vector2(60, 60)
	cv.set_snap_mode("grille")
	await frames(3)
	# Prefab avec un Pack-a-Punch d'abord (sa définition, qui ne passerait pas
	# le contrôle de prefab.json, ne survit pas à une carte remise : doc.restore).
	ed.select("k1")
	await frames(2)
	var kh := cv.gizmo.handles_of(ed.doc.find("k1"))
	at.check(kh.size() == 4 and kh.all(func(h): return h.lock), "quatre cadenas, pas de face")
	if not kh.is_empty():
		var lp: Vector2 = kh[1].m
		_mouse(cv, lp, -1)
		_mouse(cv, lp, 1)
		_mouse(cv, lp, 0)
		await frames(1)
		at.check(ed.status.text == "Échelle impossible : « Coin Pack-a-Punch » contient un Pack-a-Punch (objet de jeu à taille fixe)", "barre d'état : %s" % ed.status.text)
		at.check(cv.cursor_at(cv.to_px(lp)) == Control.CURSOR_FORBIDDEN, "curseur interdit sur un cadenas")
	at.check(not ed.doc.find("k1").has("echelle"), "prefab bloqué : pas d'échelle")

	var undo0 := ed.collab.history.undo_count(ed.collab.my_id)
	ed.select("c1")
	await frames(2)

	# Coin sud-est (5,25 ; 5) tiré vers (6,5 ; 6) : ×1,5 ; coin nord-ouest (2,75 ; 3) fixe.
	var hs := cv.gizmo.handles_of(ed.doc.find("c1"))
	at.check(hs.size() == 8, "4 coins et 4 faces (%d)" % hs.size())
	await _drag(cv, Vector2(5.25, 5.0), Vector2(6.5, 6.0))
	var c1 := ed.doc.find("c1")
	at.check(MapScale.scale_of(c1).is_equal_approx(Vector3.ONE * 1.5), "coin : ×1,50 uniforme (%s)" % str(MapScale.scale_of(c1)))
	var nw: Vector2 = MapGizmo.frame(c1).c - Vector2(MapScale.dims(c1).x, MapScale.dims(c1).y) * 0.5
	at.check(nw.distance_to(Vector2(2.75, 3.0)) < 0.011, "coin nord-ouest fixe (%s)" % str(nw))
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == undo0 + 1, "un geste = une annulation")
	at.check(ed.status.text.contains("×1,00 → ×1,50") and ed.status.text.contains("3,75 × 3,00 × 2,25 m"), "barre d'état : %s" % ed.status.text)

	# Face est : X seul, côté ouest fixe ; valeur tapée « 2 » puis Entrée.
	c1 = ed.doc.find("c1")
	var east: Vector2 = MapGizmo.frame(c1).c + Vector2(MapScale.dims(c1).x * 0.5, 0)
	var west0: float = MapGizmo.frame(c1).c.x - MapScale.dims(c1).x * 0.5
	_mouse(cv, east, -1)
	_mouse(cv, east, 1)
	_mouse(cv, east + Vector2(0.3, 0), -1)
	await frames(1)
	for ch in ["2"]:
		var k := InputEventKey.new()
		k.pressed = true
		k.keycode = KEY_2
		k.unicode = ch.unicode_at(0)
		cv.handle_key(k)
	var ke := InputEventKey.new()
	ke.pressed = true
	ke.keycode = KEY_ENTER
	cv.handle_key(ke)
	await frames(2)
	c1 = ed.doc.find("c1")
	at.check(MapScale.scale_of(c1).is_equal_approx(Vector3(2, 1.5, 1.5)), "face est, valeur tapée : X ×2 (%s ; refus : %s ; geste : %s)" % [str(MapScale.scale_of(c1)), cv.refusal, str(cv.drag.get("h", {}))])
	at.check(absf(MapGizmo.frame(c1).c.x - MapScale.dims(c1).x * 0.5 - west0) < 0.011, "côté ouest fixe")
	_mouse(cv, east, 0)
	# Échap pendant un geste : rien ne change.
	var s_before := MapScale.scale_of(ed.doc.find("c1"))
	var se: Vector2 = MapGizmo.frame(ed.doc.find("c1")).c + Vector2(MapScale.dims(ed.doc.find("c1")).x, MapScale.dims(ed.doc.find("c1")).y) * 0.5
	_mouse(cv, se, -1)
	_mouse(cv, se, 1)
	_mouse(cv, se + Vector2(1, 1), -1)
	await frames(1)
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	cv.handle_key(esc)
	await frames(1)
	at.check(MapScale.scale_of(ed.doc.find("c1")).is_equal_approx(s_before) and cv.drag.is_empty(), "Échap : geste annulé")

	# Vue Avant : losange du haut, Z seul, base au sol.
	var av: MapElevation = ed.views.panes[1].view if ed.views.panes.size() > 1 else null
	if av != null and av.plane == "avant":
		av.zoom = 40.0
		av.origin = Vector2(40, av.size.y - 60)
		await frames(2)
		var e := av.projected_of("c1")
		var top := av.tools.gizmo.handles_of(e).filter(func(h): return h.kind == "top")
		at.check(top.size() == 1, "losange de la hauteur")
		if top.size() == 1:
			var p: Vector2 = top[0].p
			await _drag_px(av, p, p + Vector2(0, -0.75 * av.zoom))
			c1 = ed.doc.find("c1")
			at.check(is_equal_approx(MapScale.scale_of(c1).z, 2.0) and MapVertical.decor_z(c1) == 0.0, "Z ×2, base au sol (%s)" % str(MapScale.scale_of(c1)))
			# Revue : « - » puis Entrée en élévation : rien ne change, jamais de NaN.
			e = av.projected_of("c1")
			top = av.tools.gizmo.handles_of(e).filter(func(h): return h.kind == "top")
			var s1 := MapScale.scale_of(ed.doc.find("c1"))
			var tp: Vector2 = top[0].p
			_mouse(av, av.to_m(tp), -1)
			_mouse(av, av.to_m(tp), 1)
			for kc in [KEY_MINUS, KEY_ENTER]:
				var k := InputEventKey.new()
				k.pressed = true
				k.keycode = kc
				k.unicode = "-".unicode_at(0) if kc == KEY_MINUS else 0
				av.tools.handle_key(k)
			_mouse(av, av.to_m(tp), 0)
			await frames(1)
			var c2 := ed.doc.find("c1")
			at.check(MapScale.scale_of(c2).is_equal_approx(s1) and (c2.get("echelle", []) as Array).all(func(x): return is_finite(float(x))), "élévation, « - » : échelle inchangée (%s)" % str(c2.get("echelle", "—")))
	else:
		at.fail("vue Avant absente")

	# Revue : saisie illisible (« m », « . », « 1,5, ») puis Entrée : jamais de NaN.
	for typed in [[KEY_M], [KEY_PERIOD], [KEY_1, KEY_COMMA, KEY_5, KEY_COMMA]]:
		var s0 := MapScale.scale_of(ed.doc.find("c1"))
		var se2: Vector2 = MapGizmo.frame(ed.doc.find("c1")).c + Vector2(MapScale.dims(ed.doc.find("c1")).x, MapScale.dims(ed.doc.find("c1")).y) * 0.5
		_mouse(cv, se2, -1)
		_mouse(cv, se2, 1)
		await frames(1)
		for kc in typed:
			_key(cv, kc)
		_key(cv, KEY_ENTER)
		_mouse(cv, se2, 0)
		await frames(1)
		var cc := ed.doc.find("c1")
		var ok := (cc.get("echelle", [1, 1, 1]) as Array).all(func(x): return is_finite(float(x)))
		# « 1,5, » : la dernière valeur lisible (1,5) reste ; « m », « . » : rien ne change.
		var want := s0 if typed.size() == 1 else Vector3.ONE * 1.5 * (s0 / s0.x)
		at.check(ok and MapScale.scale_of(cc).distance_to(want) < 0.011, "saisie illisible %s : jamais de NaN (%s)" % [str(typed), str(cc.get("echelle", "—"))])
	at.check(not String(ed.doc.file_texts()["objets.json"]).contains("nan"), "aucun NaN dans le fichier")

func _key(cv: MapCanvas, kc: int) -> void:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = kc
	var chars := {KEY_PERIOD: ".", KEY_COMMA: ",", KEY_1: "1", KEY_5: "5", KEY_M: "m"}
	if chars.has(kc):
		k.unicode = String(chars[kc]).unicode_at(0)
	cv.handle_key(k)


func _drag(cv: MapView, a: Vector2, b: Vector2) -> void:
	_mouse(cv, a, -1)
	_mouse(cv, a, 1)
	for i in 6:
		_mouse(cv, a.lerp(b, (i + 1) / 6.0), -1)
		await frames(1)
	_mouse(cv, b, 0)
	await frames(1)


func _mouse(v: MapView, m: Vector2, press: int) -> void:
	if press < 0:
		var mm := InputEventMouseMotion.new()
		mm.position = v.to_px(m)
		v._gui_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.position = v.to_px(m)
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = press == 1
	v._gui_input(mb)


func _drag_px(v: MapElevation, a: Vector2, b: Vector2) -> void:
	await _drag(v, v.to_m(a), v.to_m(b))
