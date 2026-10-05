extends TestCase
## Édition dans les élévations de l'éditeur de cartes (docs/EDITOR_VIEWS.md
## § 6 ; format 12 § 7) : chaque type dans chaque vue (bouge, ne bouge pas,
## refus), changement d'étage d'une pièce avec son contenu, poignées
## (plafond, largeur, hauteur de barrière, sol d'un étage), verrouillage
## d'axe, saisie d'une valeur, une action = une annulation, aller-retour du
## format 12 (z, descente, hauteur au sol), carte au format 11 lue telle
## quelle, carte reçue avec une hauteur hors bornes refusée, décor surélevé
## (posé sur un autre), export en jeu à la bonne hauteur.

const TMP := "res://tests/_out/test_map_views_edit"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


static func _arena() -> EditorMap:
	var doc := EditorMap.load_dir("res://assets/maps/draft_arena/")
	doc.objets.append({"id": "fx1", "type": "effet", "effet": "torche", "altitude": 0, "position": [9.5, 4.5], "mur": "n", "hauteur": 1.8})
	doc.objets.append({"id": "lu1", "type": "luminaire", "luminaire": "suspension", "altitude": 0, "position": [10.0, 26.0], "rot": 0})
	doc.objets.append({"id": "d1", "type": "prefab", "prefab": "caisses", "altitude": 0, "position": [8.0, 28.0], "rot": 0})
	doc.objets.append({"id": "d2", "type": "prefab", "prefab": "bureau", "altitude": 0, "position": [13.75, 28.0], "rot": 0})
	return doc


func _editor(doc: EditorMap) -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed._reset(doc)
	await wait_frames(2)
	return ed


## Fenêtre du bas (Avant par défaut) au plan `pl`, cadrée.
func _view(ed: MapEditor, pl := "avant") -> MapElevation:
	var pn: MapViewPane = ed.views.panes[1]
	ed.views.set_pane_plane(pn, pl)
	var ev: MapElevation = pn.view
	ev.zoom = 20.0
	ev.origin = Vector2(40, 300)
	return ev


func _mouse(ev: MapElevation, m: Vector2, button := -1, pressed := false) -> void:
	if button < 0:
		var mm := InputEventMouseMotion.new()
		mm.position = ev.to_px(m)
		ev._gui_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.position = ev.to_px(m)
	mb.button_index = button
	mb.pressed = pressed
	ev._gui_input(mb)


## Glisse de `a` à `b` (uv, m) dans la vue.
func _drag(ev: MapElevation, a: Vector2, b: Vector2) -> void:
	_mouse(ev, a)
	_mouse(ev, a, MOUSE_BUTTON_LEFT, true)
	for i in 4:
		_mouse(ev, a.lerp(b, (i + 1) / 4.0))
	_mouse(ev, b, MOUSE_BUTTON_LEFT, false)


func test_pose_kinds() -> void:
	assert_eq(MapVertical.pose_kind({"type": "effet"}), "pose")
	assert_eq(MapVertical.pose_kind({"type": "prefab"}), "pose")
	assert_eq(MapVertical.pose_kind({"type": "luminaire"}), "pose")
	assert_eq(MapVertical.pose_kind({"type": "porte"}), "fixe")
	assert_eq(MapVertical.pose_kind({"type": "fenetre"}), "fixe")
	assert_eq(MapVertical.pose_kind({"id": "p1", "contour": []}), "niveau")
	for t in ["escalier", "pilier", "mur", "piege", "atout", "depart", "apparition", "teleporteur"]:
		assert_eq(MapVertical.pose_kind({"type": t}), "niveau", t)


func test_torch_moves_up_in_front_view_as_one_undo() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.canvas.fine_step = 0.1
	ed.canvas.set_snap_mode("fine")
	ev.zoom = 40.0
	ed.select("fx1")
	await wait_frames(1)
	var e := ev.projected_of("fx1")
	var o := ev.tools.anchor_px(e)
	# Flèche Z : un seul axe, de 1,80 à 2,10 m (loin des aimants).
	var at := ev.to_m(o + Vector2(0, -EditorUi.px(35)))
	_drag(ev, at, at + Vector2(0.4, -0.3))
	var t := ed.doc.find("fx1")
	assert_near(MapCatalog.effect_height(t), 2.1, 0.001, "torche à 2,10 m")
	assert_near(float(t.position[0]), 9.5, 0.001, "Z verrouillé : x inchangé")
	assert_eq(ed.collab.history.undo_count(ed.collab.my_id), 1, "un glissement = une annulation")
	ed.undo()
	assert_near(MapCatalog.effect_height(ed.doc.find("fx1")), 1.8, 0.001, "Ctrl+Z : de retour à 1,80 m")
	ed.queue_free()
	await wait_frames(1)


func test_horizontal_move_in_front_view_keeps_depth() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.canvas.set_snap_mode("libre")
	ed.select("d1")
	await wait_frames(1)
	var y0 := float(ed.doc.find("d1").position[1])
	var e := ev.projected_of("d1")
	var c := Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	_drag(ev, c, c + Vector2(2.0, 0.0))
	var d := ed.doc.find("d1")
	assert_near(float(d.position[0]), 10.0, 0.001, "x + 2 m")
	assert_near(float(d.position[1]), y0, 0.001, "profondeur (y) inchangée")
	# Vue Droite : l'axe de l'écran est −Y.
	ev = _view(ed, "droite")
	ed.select("d1")
	e = ev.projected_of("d1")
	c = Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	_drag(ev, c, c + Vector2(1.0, 0.0))
	d = ed.doc.find("d1")
	assert_near(float(d.position[1]), y0 - 1.0, 0.001, "Droite : vers la droite = y décroissant")
	assert_near(float(d.position[0]), 10.0, 0.001)
	ed.queue_free()
	await wait_frames(1)


func test_room_changes_floor_with_its_content() -> void:
	var doc := _arena()
	# Un niveau vide (7 m) au-dessus de la passerelle.
	doc.view_levels.append(7.0)
	var ed := await _editor(doc)
	var ev := _view(ed)
	ed.select("p5")
	var b3 := ed.doc.find("b3")
	assert_eq(ed.doc.level_of(b3), 1)
	var e := ev.projected_of("p5")
	var c := Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	_drag(ev, c, c + Vector2(0.0, -3.5))
	assert_eq(ed.doc.level_of(ed.doc.find("p5")), 2, "passerelle montée à l'étage 2")
	assert_eq(ed.doc.level_of(ed.doc.find("b3")), 2, "sa boîte avec elle")
	assert_eq(ed.doc.level_of(ed.doc.find("c1")), 2, "son interrupteur avec elle")
	ed.undo()
	assert_eq(ed.doc.level_of(ed.doc.find("p5")), 1)
	assert_eq(ed.doc.level_of(ed.doc.find("b3")), 1)
	ed.queue_free()
	await wait_frames(1)


func test_openings_do_not_move_vertically() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.select("o6")
	var p0: Array = ed.doc.find("o6").position.duplicate()
	var e := ev.projected_of("o6")
	assert_false(ev.tools.can_v(e), "fenêtre : pas de flèche Z")
	assert_true(ev.tools.can_h(e), "fenêtre du mur nord vue de face : glisse le long du mur")
	var c := Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	_drag(ev, c, c + Vector2(0.0, -2.0))
	assert_eq(ed.doc.find("o6").position, p0, "aucun déplacement vertical")
	# Porte du mur est (o2 : x = 17) vue en Avant : de profil, axe horizontal verrouillé.
	ed.select("o2")
	assert_false(ev.tools.can_h(ev.projected_of("o2")), "porte de profil : pas de glissement horizontal")
	ed.queue_free()
	await wait_frames(1)


func test_room_ceiling_handle_and_double_height_lock() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.canvas.fine_step = 0.1
	ed.canvas.set_snap_mode("fine")
	ed.select("p1")
	var e := ev.projected_of("p1")
	var hs: Array = ev.tools.handles(e)
	var top: Array = hs.filter(func(h): return h.id == "top")
	assert_eq(top.size(), 1, "losange du plafond")
	var px: Vector2 = top[0].p
	_drag(ev, ev.to_m(px), ev.to_m(px) + Vector2(0, -1.0))
	assert_near(float(ed.doc.find("p1").get("plafond", 3.2)), 4.2, 0.001, "plafond 3,20 → 4,20 m")
	assert_eq(ed.collab.history.undo_count(ed.collab.my_id), 1)
	# Entrepôt haut (format 17 : plus de double hauteur) : son plafond se règle aussi.
	ed.select("p3")
	var top_h: Array = ev.tools.handles(ev.projected_of("p3")).filter(func(h): return h.id == "top")
	assert_false(top_h.is_empty() or bool(top_h[0].get("lock", false)), "pièce haute : poignée du plafond, sans cadenas")
	ed.queue_free()
	await wait_frames(1)


func test_opening_width_handle() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.canvas.set_snap_mode("libre")
	ed.select("o4")
	var e := ev.projected_of("o4")
	var r: Array = ev.tools.handles(e).filter(func(h): return h.id == "side_r")
	assert_eq(r.size(), 1, "passage vu de face : poignées de largeur")
	var px: Vector2 = r[0].p
	_drag(ev, ev.to_m(px), ev.to_m(px) + Vector2(-1.0, 0))
	assert_near(MapRules.opening_width(ed.doc.find("o4")), 2.0, 0.001, "largeur 4 → 2 m")
	ed.queue_free()
	await wait_frames(1)


func test_level_tag_moves_a_floor() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	var y := ev.to_px(Vector2(0, -3.5)).y
	var at := ev.to_m(Vector2(ev._ruler() + EditorUi.px(20), y))
	_drag(ev, at, at + Vector2(0, -0.5))
	assert_near(ed.doc.floor_sol(1), 4.0, 0.001, "sol de l'étage 1 : 3,50 → 4,00 m")
	# Jamais à moins de 3,1 m de l'étage du dessous.
	y = ev.to_px(Vector2(0, -4.0)).y
	at = ev.to_m(Vector2(ev._ruler() + EditorUi.px(20), y))
	_drag(ev, at, at + Vector2(0, 2.0))
	assert_near(ed.doc.floor_sol(1), 3.1, 0.001, "borné à 3,10 m")
	ed.queue_free()
	await wait_frames(1)


func test_axis_lock_and_typed_value() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.select("lu1")
	var e := ev.projected_of("lu1")
	var o := ev.tools.anchor_px(e)
	var a := ev.to_m(o + Vector2(EditorUi.px(17), -EditorUi.px(21)))
	_mouse(ev, a)
	_mouse(ev, a, MOUSE_BUTTON_LEFT, true)
	_mouse(ev, a + Vector2(1.0, -0.3))
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_Z
	assert_true(ev.tools.handle_key(k), "Z : verrouille")
	assert_eq(ev.tools.drag.lock, "v")
	for ch in ["-", "0", ".", "5"]:
		var kk := InputEventKey.new()
		kk.pressed = true
		kk.unicode = ch.unicode_at(0)
		kk.keycode = KEY_MINUS if ch == "-" else (KEY_PERIOD if ch == "." else KEY_0 + int(ch))
		ev.tools.handle_key(kk)
	var ent := InputEventKey.new()
	ent.pressed = true
	ent.keycode = KEY_ENTER
	ev.tools.handle_key(ent)
	var l := ed.doc.find("lu1")
	assert_near(MapVertical.descente(l), 0.7 + 0.5, 0.001, "suspension descendue de 0,5 m (descente 1,2)")
	assert_near(float(l.position[0]), 10.0, 0.001, "x inchangé (Z verrouillé)")
	ed.queue_free()
	await wait_frames(1)


func test_decor_stacked_on_another() -> void:
	var doc := _arena()
	var ed := await _editor(doc)
	var v := ed.raster().v
	var crate := ed.doc.find("d1")
	# Bureau (support 0,78) posé sur la pile de caisses (h 1,5) : il doit reposer dessus.
	var desk := ed.doc.find("d2").duplicate(true)
	desk["position"] = crate.position.duplicate()
	desk["z"] = 0.7
	var bad := desk.duplicate(true)
	ed.doc.find("d2").merge(bad, true)
	assert_false(MapVertical.check_pose(ed.doc, v, ed.doc.find("d2")).ok, "décor bloquant en l'air : refusé")
	ed.doc.find("d2")["z"] = 1.5
	assert_true(MapVertical.check_pose(ed.doc, v, ed.doc.find("d2")).ok, "posé sur le dessus de la pile de caisses")
	# Sans collision, il peut flotter.
	var debris := {"id": "d3", "type": "prefab", "prefab": "debris_epars", "altitude": 0, "position": [10.0, 25.0], "rot": 0, "z": 1.0}
	ed.doc.objets.append(debris)
	assert_true(MapVertical.check_pose(ed.doc, v, debris).ok, "décor sans collision : libre")
	ed.queue_free()
	await wait_frames(1)


func test_format_12_round_trip_and_older_maps() -> void:
	var doc := _arena()
	doc.find("d2")["z"] = 1.5
	doc.find("d2")["position"] = [8.0, 28.0]
	doc.find("lu1")["descente"] = 1.2
	doc.objets.append({"id": "lu2", "type": "luminaire", "luminaire": "lampe_bureau", "altitude": 0, "position": [12.0, 24.0], "rot": 0, "hauteur": 1.0})
	doc.objets.append({"id": "fx2", "type": "effet", "effet": "cable_nu", "altitude": 0, "position": [12.0, 30.0], "descente": 0.4})
	var dir := ProjectSettings.globalize_path(TMP + "/f12")
	assert_eq(doc.save_dir(dir), OK)
	var carte: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json")))
	assert_eq(int(carte.format), EditorMap.FORMAT, "carte enregistrée au format courant (12 et plus)")
	var back := EditorMap.load_dir(dir)
	assert_true(back.same_as(EditorMap.from_texts(doc.file_texts())), "relue à l'identique")
	assert_near(float(back.find("d2").z), 1.5, 0.001)
	assert_near(float(back.find("lu1").descente), 1.2, 0.001)
	assert_near(float(back.find("lu2").hauteur), 1.0, 0.001, "luminaire au sol : hauteur gardée")
	assert_near(float(back.find("fx2").descente), 0.4, 0.001)
	# Valeur par défaut, illisible, hors du type : retirée.
	var t := {"carte.json": FileAccess.get_file_as_string(dir.path_join("carte.json"))}
	for f in EditorMap.FILES:
		t[f] = FileAccess.get_file_as_string(dir.path_join(f))
	var objs: Dictionary = JSON.parse_string(t["objets.json"])
	for o in objs.objets:
		if o.id == "d1":
			o["z"] = 0.0
		if o.id == "fx1":
			o["descente"] = 1.0
	t["objets.json"] = JSON.stringify(objs)
	var m := EditorMap.from_texts(t)
	assert_false(m.find("d1").has("z"), "z = 0 : retirée")
	assert_false(m.find("fx1").has("descente"), "descente sur un effet mural : retirée")
	# Carte au format 11 (DRAFT ARENA, format 1) : lue telle quelle, sans clé ajoutée.
	var old := EditorMap.load_dir("res://assets/maps/draft_arena/")
	for o in old.objets:
		assert_false(o.has("z") or o.has("descente"), "aucune clé du format 12 ajoutée")


func test_received_map_with_out_of_bounds_height_is_refused() -> void:
	var doc := _arena()
	doc.find("d1")["z"] = 31.0
	var texts := doc.file_texts()
	var r := CustomMapGuard.check_texts(texts)
	assert_false(r.ok, "z hors bornes : refusée")
	doc.find("d1")["z"] = 1.0
	doc.find("lu1")["descente"] = 4.0
	r = CustomMapGuard.check_texts(doc.file_texts())
	assert_false(r.ok, "descente hors bornes : refusée")
	doc.find("lu1")["descente"] = 1.0
	doc.pieces[0]["plafond"] = 2.5
	r = CustomMapGuard.check_texts(doc.file_texts())
	assert_false(r.ok, "plafond de pièce sous 2,8 m : refusé (bornes unifiées)")
	doc.pieces[0]["plafond"] = 12.0
	r = CustomMapGuard.check_texts(doc.file_texts())
	assert_true(r.ok, "format 17 : plafond sans maximum (%s)" % [r.get("reasons", [])])
	doc.pieces[0]["plafond"] = 4.0
	r = CustomMapGuard.check_texts(doc.file_texts())
	assert_true(r.ok, "bornes respectées : acceptée (%s)" % [r.get("reasons", [])])


func test_export_heights_in_game() -> void:
	var doc := _arena()
	doc.find("d2")["position"] = [8.0, 28.0]
	doc.find("d2")["z"] = 1.5
	doc.find("lu1")["descente"] = 1.2
	var v := MapRaster.build(doc).v
	v.analyze()
	var lay := MapLayoutExport.build(v)
	var desk: Array = lay.props.filter(func(p): return String(p.id) == "d2")
	assert_eq(desk.size(), 1)
	assert_near(float(desk[0].p[1]), 1.5, 0.001, "bureau posé à 1,5 m en jeu")
	var lamp: Array = (lay.markers.lamps as Array).filter(func(l): return String(l.get("fixture", "")) == "suspension")
	assert_eq(lamp.size(), 1)
	assert_near(float(lamp[0].p[1]), 3.2 - 1.2, 0.001, "lumière 1,2 m sous le plafond")


func test_stack_decor_by_dragging_in_front_view() -> void:
	var doc := EditorMap.blank("pile", "PILE", "STACK")
	var z := String(doc.add_zone("A", "A").id)
	doc.pieces.append({"id": "p1", "nom": "A", "altitude": 0, "zone": z, "contour": [[0, 0], [14, 0], [14, 10], [0, 10]]})
	doc.objets.append({"id": "d1", "type": "prefab", "prefab": "sacs_sable", "altitude": 0, "position": [5.0, 4.0], "rot": 0})
	doc.objets.append({"id": "d2", "type": "prefab", "prefab": "sacs_sable", "altitude": 0, "position": [8.0, 4.0], "rot": 0})
	var ed := await _editor(doc)
	var ev := _view(ed)
	ev.zoom = 40.0
	ed.canvas.set_snap_mode("libre")
	ed.select("d2")
	var e := ev.projected_of("d2")
	var a := Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	_mouse(ev, a)
	_mouse(ev, a, MOUSE_BUTTON_LEFT, true)
	for i in 6:
		_mouse(ev, a.lerp(a + Vector2(-3.0, -0.92), (i + 1) / 6.0))
	var refusal := ev.tools.refusal
	_mouse(ev, a + Vector2(-3.0, -0.92), MOUSE_BUTTON_LEFT, false)
	var d2 := ed.doc.find("d2")
	assert_near(float(d2.position[0]), 5.0, 0.02, "posé au-dessus de d1 (%s)" % refusal)
	assert_near(MapVertical.decor_z(d2), 0.9, 0.005, "aimanté sur le dessus des sacs (%s)" % refusal)
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ correctifs de relecture

## Glissement « déplacer » commencé sur `id` dans la vue (outils de la vue).
func _begin_move(ed: MapEditor, ev: MapElevation, id: String, lock := "") -> void:
	ed.select(id)
	var e := ev.projected_of(id)
	ev.mouse_m = Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	ev.tools._begin("move", e, {"lock": lock})


## Souris amenée à `dm` (m, uv) du début du glissement.
func _move_to(ev: MapElevation, dm: Vector2) -> void:
	ev.mouse_m = Vector2(ev.tools.drag.start_m) + dm
	ev.tools.update()


## Point (uv, m) de la vue Dessous au-dessus du point `p` du plan.
static func _below_uv(p: Vector2) -> Vector2:
	return MapView.uv_of("dessous", Vector3(p.x, p.y, 0.0))


func test_collab_change_during_elevation_drag_is_kept() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.canvas.set_snap_mode("grille")
	_begin_move(ed, ev, "d1", "h")
	_move_to(ev, Vector2(2.0, 0.0))
	assert_near(float(ed.doc.find("d1").position[0]), 10.0, 0.001, "d1 glissé de 2 m")
	# Un invité déplace le bureau pendant le glissement.
	var desk := ed.doc.find("d2").duplicate(true)
	desk["position"] = [14.75, 30.0]
	var ops := [{"op": "put", "coll": "objets", "el": desk}]
	MapOps.apply(ed.doc, ops)
	ed._on_collab_applied(ops, "invite", "bureau", false)
	_move_to(ev, Vector2(3.0, 0.0))
	assert_eq(ed.doc.find("d2").position, [14.75, 30.0], "le changement reçu n'est pas effacé par le glissement")
	ev.tools.release()
	ed.undo()
	assert_near(float(ed.doc.find("d1").position[0]), 8.0, 0.001, "Ctrl+Z : d1 revient")
	assert_eq(ed.doc.find("d2").position, [14.75, 30.0], "Ctrl+Z ne défait pas le changement de l'invité")
	ed.queue_free()
	await wait_frames(1)


func test_undo_and_map_replaced_during_elevation_drag() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.canvas.set_snap_mode("grille")
	ed.select("d1")
	ed.rotate_selected()
	var n := ed.collab.history.undo_count(ed.collab.my_id)
	_begin_move(ed, ev, "d1", "h")
	_move_to(ev, Vector2(2.0, 0.0))
	# Ctrl+Z pendant le glissement : le glissement est annulé d'abord.
	ed.undo()
	assert_false(ev.tools.dragging(), "Ctrl+Z annule le glissement")
	assert_near(float(ed.doc.find("d1").position[0]), 8.0, 0.001)
	assert_eq(ed.collab.history.undo_count(ed.collab.my_id), n - 1, "puis défait la rotation")
	# Carte entière remplacée : glissement abandonné sans remettre l'ancienne carte.
	_begin_move(ed, ev, "d1", "h")
	_move_to(ev, Vector2(2.0, 0.0))
	var fresh := _arena()
	fresh.find("d1")["position"] = [6.0, 30.0]
	ed.doc.restore(fresh.snapshot())
	ed._on_map_replaced()
	assert_false(ev.tools.dragging(), "glissement abandonné")
	ev.tools.release()
	ev.tools.cancel()
	assert_eq(ed.doc.find("d1").position, [6.0, 30.0], "la carte reçue reste")
	ed.queue_free()
	await wait_frames(1)


func test_object_under_double_height_ceiling_keeps_its_floor() -> void:
	var doc := _arena()
	# Lampe de bureau dans l'entrepôt (double hauteur), loin de la passerelle.
	doc.objets.append({"id": "lb", "type": "luminaire", "luminaire": "lampe_bureau", "altitude": 0, "position": [14.0, 14.0], "rot": 0})
	var ed := await _editor(doc)
	var ev := _view(ed)
	ed.canvas.set_snap_mode("grille")
	_begin_move(ed, ev, "lb", "v")
	_move_to(ev, Vector2(0.0, -4.0))
	ev.tools.release()
	var lb := ed.doc.find("lb")
	assert_eq(ed.doc.level_of(lb), 0, "sous le plafond réel de l'entrepôt : reste à l'étage 0")
	var z := MapVertical.pose_z(ed.doc, ed.raster().v, lb)
	assert_true(z > ed.doc.floor_sol(1) and z < ed.doc.floor_sol(1) + 3.0, "posée au-dessus du sol de l'étage 1 (%s m)" % z)
	ed.queue_free()
	await wait_frames(1)


func test_refused_move_keeps_last_valid_place() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ed.canvas.set_snap_mode("grille")
	_begin_move(ed, ev, "d1", "h")
	_move_to(ev, Vector2(2.0, 0.0))
	assert_near(float(ed.doc.find("d1").position[0]), 10.0, 0.001)
	_move_to(ev, Vector2(30.0, 0.0))
	assert_true(ev.tools.refusal != "", "hors de la carte : refusé")
	assert_near(float(ed.doc.find("d1").position[0]), 10.0, 0.001, "reste à sa dernière place valide (§ 6.1)")
	ev.tools.release()
	assert_near(float(ed.doc.find("d1").position[0]), 10.0, 0.001)
	ed.queue_free()
	await wait_frames(1)


func test_axis_locks_follow_allowed_axes() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	# Porte du mur est vue en Avant : ni horizontal ni vertical, immobile.
	var p0: Array = ed.doc.find("o2").position.duplicate()
	_begin_move(ed, ev, "o2")
	assert_eq(ev.tools.drag.lock, "both", "aucun axe permis")
	_move_to(ev, Vector2(1.0, -1.0))
	ev.tools.release()
	assert_eq(ed.doc.find("o2").position, p0, "la porte ne glisse pas hors de son mur")
	# Torche du mur nord vue de Droite : seulement Z ; la touche de l'axe
	# horizontal (Y) ne libère pas cet axe.
	ev = _view(ed, "droite")
	_begin_move(ed, ev, "fx1")
	assert_eq(ev.tools.drag.lock, "v")
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_Y
	ev.tools.handle_key(k)
	assert_eq(ev.tools.drag.lock, "v", "Y refusé : la torche ne quitte pas son mur")
	k.keycode = KEY_Z
	ev.tools.handle_key(k)
	assert_eq(ev.tools.drag.lock, "v", "Z : reste verrouillé sur Z (seul axe permis)")
	var x0: Array = ed.doc.find("fx1").position.duplicate()
	_move_to(ev, Vector2(2.0, 0.0))
	ev.tools.cancel()
	assert_eq(ed.doc.find("fx1").position, x0)
	ed.queue_free()
	await wait_frames(1)


func test_room_floor_change_checks_its_content() -> void:
	var doc := _arena()
	# Escalier dans la passerelle (étage 1 : l'étage 2 existe au-dessus).
	doc.view_levels.append(7.0)
	doc.objets.append({"id": "st", "type": "escalier", "altitude": 1 * EditorMap.FLOOR_STEP, "rect": [3.0, 5.0, 5.0, 9.0], "rot": 0})
	var ed := await _editor(doc)
	var p5 := ed.doc.find("p5")
	var att := ed.attached_to(p5)
	assert_true("st" in att, "l'escalier part avec la passerelle")
	var snap := ed.doc.snapshot()
	var res := ed.try_move_3d(p5.duplicate(true), att, Vector2.ZERO, 2, NAN, snap)
	assert_false(res.ok, "escalier sur le dernier étage : refusé")
	assert_eq(ed.doc.level_of(ed.doc.find("p5")), 1, "la passerelle reste à l'étage 1")
	assert_eq(ed.doc.level_of(ed.doc.find("st")), 1)
	ed.queue_free()
	await wait_frames(1)


func test_support_of_a_stacked_decor_cannot_go_alone() -> void:
	var doc := _arena()
	doc.find("d2")["position"] = [8.0, 28.0]
	doc.find("d2")["z"] = 1.5
	var ed := await _editor(doc)
	assert_eq(MapVertical.resting_on(ed.doc, ed.doc.find("d1")), ["d2"], "le bureau repose sur les caisses")
	# Dessus : déplacer ou supprimer les caisses seules est refusé.
	var snap := ed.doc.snapshot()
	var res := ed.try_move(ed.doc.find("d1").duplicate(true), [], Vector2(-3.0, 0.0), snap)
	assert_false(res.ok, "déplacer le support : refusé")
	assert_eq(ed.doc.find("d1").position, [8.0, 28.0])
	ed.delete_element("d1")
	assert_false(ed.doc.find("d1").is_empty(), "supprimer le support : refusé")
	# Élévation : pareil.
	var ev := _view(ed)
	ed.canvas.set_snap_mode("grille")
	_begin_move(ed, ev, "d1", "h")
	_move_to(ev, Vector2(-3.0, 0.0))
	ev.tools.release()
	assert_eq(ed.doc.find("d1").position, [8.0, 28.0], "élévation : refusé aussi")
	# Validateur (et donc cartes reçues) : un décor bloquant en l'air est une erreur.
	ed.doc.find("d2")["z"] = 0.7
	var v := MapRaster.build(ed.doc).v
	v.analyze()
	assert_true(v.errors().any(func(e): return String(e.fr).contains("en l'air")), "validateur : décor en l'air")
	assert_false(CustomMapGuard.check_playable(ed.doc).is_empty(), "carte reçue : injouable")
	ed.queue_free()
	await wait_frames(1)


func test_cut_lines_keep_a_minimal_gap() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed)
	ev.set_cut([5.0, 5.04], "perso")
	assert_eq(ev.coupe.size(), 2, "coupe gardée")
	assert_near(float(ev.coupe[1]) - float(ev.coupe[0]), MapElevation.CUT_MIN, 0.001)
	ev.set_cut([10.0, 14.0], "perso")
	# Trait avant tiré au-delà de l'autre (vue Avant : coupe sur Y).
	ed.canvas.drag = {"kind": "cut", "ev": ev, "i": 0}
	ed.canvas.mouse_m = Vector2(0.0, 20.0)
	ed.canvas._drag_cut()
	assert_eq(ev.coupe.size(), 2, "la coupe ne disparaît pas")
	assert_near(float(ev.coupe[0]), 14.0 - MapElevation.CUT_MIN, 0.011)
	assert_near(float(ev.coupe[1]), 14.0, 0.001)
	ed.canvas.drag = {}
	ed.queue_free()
	await wait_frames(1)


func test_below_view_picks_only_the_current_floor() -> void:
	var ed := await _editor(_arena())
	var ev := _view(ed, "dessous")
	ed.floor_k = 0
	var e := ev.element_at(_below_uv(Vector2(5.0, 7.0)))
	assert_eq(String(e.get("id", "")), "p3", "étage 0 : l'entrepôt, pas la passerelle de l'étage 1")
	ed.floor_k = 1
	e = ev.element_at(_below_uv(Vector2(5.0, 7.0)))
	assert_eq(String(e.get("id", "")), "p5", "étage 1 : la passerelle")
	ed.queue_free()
	await wait_frames(1)


func test_numpad_and_layout_change_during_a_drag() -> void:
	var ed := await _editor(_arena())
	var lay := ed.views
	# Tracé en cours : le pavé numérique ne change pas de plan.
	ed.pick_item("piece_poly")
	ed.canvas.poly_pts.append(Vector2(2, 6))
	assert_true(lay.busy(), "tracé : vues occupées")
	var planes := lay.panes.map(func(p): return p.plane())
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_KP_3
	ed._input(k)
	assert_eq(lay.panes.map(func(p): return p.plane()), planes, "pavé 3 pendant le tracé : aucun plan changé")
	ed.canvas.cancel()
	ed.pick_item("select")
	# Glissement en élévation puis changement de disposition : annulé, sans
	# carte modifiée ni étape d'annulation.
	var ev := _view(ed)
	ed.canvas.set_snap_mode("grille")
	var n := ed.collab.history.undo_count(ed.collab.my_id)
	_begin_move(ed, ev, "d1", "h")
	_move_to(ev, Vector2(2.0, 0.0))
	assert_true(lay.busy())
	lay.set_layout("4")
	assert_false(lay.elevation_dragging(), "glissement annulé")
	assert_near(float(ed.doc.find("d1").position[0]), 8.0, 0.001, "la carte d'avant revient")
	assert_eq(ed.collab.history.undo_count(ed.collab.my_id), n, "aucune étape d'annulation")
	ed.queue_free()
	await wait_frames(1)
