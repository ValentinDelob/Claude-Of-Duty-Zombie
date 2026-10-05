extends TestCase
## Interface complète des niveaux de l'éditeur (docs/LEVELS_PLAN.md, étape 5) :
## barre des niveaux (menu du plus haut au plus bas, « Autre altitude… »),
## Page préc. / suiv., Maj+Page (la sélection change de niveau), niveau vide,
## altitude d'une pièce avec son contenu en une étape d'annulation (escalier
## qui y arrive : seule son arrivée suit ; qui en part : seul son pied), refus
## qui laisse la carte intacte, duplication d'un niveau, actions de l'onglet
## Niveaux, Alt + clic (pièce empilée suivante), clic dans une élévation,
## glissement vertical d'une pièce en élévation avec aimants (pas 0,25),
## fantôme et vides hachurés du plan, bornes de 30 m retirées, textes FR / EN.

const Free := preload("res://tests/test_levels_free.gd")
const TMP := "res://tests/_out/test_map_levels_ui"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


func _editor(doc: EditorMap) -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed._reset(doc)
	await wait_frames(2)
	return ed


func _done(ed: MapEditor) -> void:
	ed.queue_free()
	await wait_frames(1)


## Salle A (0 m), salle B (0 m) et salle C posée sur B à 3,5 m ; A a un départ,
## la boîte et une fenêtre.
static func _stack() -> EditorMap:
	var doc := Free._map("pile", [
		{"id": "A", "nom": "Salle A", "altitude": 0, "contour": Free.rect(0, 0, 10, 10)},
		{"id": "B", "nom": "Salle B", "altitude": 0, "contour": Free.rect(14, 0, 24, 10)},
		{"id": "C", "nom": "Salle C", "altitude": 3.5, "contour": Free.rect(14, 0, 24, 10)}],
		[3.0, 7.0], [3.25, 0.0], [3.25, 10.0])
	return doc


func _undos(ed: MapEditor) -> int:
	return ed.collab.history.undo_count(ed.collab.my_id)


func _key(ed: MapEditor, code: Key, shift := false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = true
	k.shift_pressed = shift
	ed._input(k)


# ------------------------------------------------------------------ barre des niveaux

func test_level_menu_lists_levels_from_top_and_other_altitude() -> void:
	var ed := await _editor(Free.high_hall())
	var lines := ed.level_menu_lines()
	assert_eq(lines.map(func(l): return int(l.k)), [2, 1, 0], "du plus haut au plus bas")
	assert_true(String(lines[0].text).contains(EditorMap.alt_text(7.0, not Lang.is_en())), "altitude : %s" % lines[0].text)
	assert_true(String(lines[2].text).contains(Lang.t("1 pièce(s)", "1 room(s)")), "nombre de pièces : %s" % lines[2].text)
	ed.fill_level_menu()
	var pm := ed.floor_label.get_popup()
	assert_eq(pm.item_count, 5, "3 niveaux, séparateur, « Autre altitude… »")
	assert_eq(pm.get_item_text(pm.get_item_index(MapEditor.LEVEL_MENU_OTHER)), Lang.t("Autre altitude…", "Other altitude…"))
	assert_true(pm.is_item_checked(pm.get_item_index(0)), "le niveau affiché est coché")
	ed._on_level_menu(2)
	assert_near(ed.view_alt(), 7.0, 0.001, "menu : niveau 7 m affiché")
	assert_true(ed.floor_label.text.begins_with(EditorMap.level_name(7.0)), "barre : %s" % ed.floor_label.text)
	# Autre altitude… : un niveau qui n'existe pas est créé vide (même négatif).
	var d := ed.altitude_dialog()
	# Valeur tapée (virgule décimale), pas encore appliquée au champ.
	(d.find_child("Alt", true, false) as SpinBox).get_line_edit().text = "-3,5"
	d.confirmed.emit()
	assert_near(ed.view_alt(), -3.5, 0.001, "niveau -3,5 m affiché")
	assert_eq(ed.floor_k, 0, "le plus bas")
	assert_eq(ed.doc.level_count(), 4)
	assert_false(ed.doc.file_texts()["pieces.json"].contains("-3.5"), "niveau vide jamais enregistré")
	await _done(ed)


func test_page_keys_and_empty_level() -> void:
	var ed := await _editor(Free.high_hall())
	_key(ed, KEY_PAGEDOWN)
	assert_near(ed.view_alt(), 3.5, 0.001, "Page suiv. : niveau du dessus")
	_key(ed, KEY_PAGEDOWN)
	assert_near(ed.view_alt(), 7.0, 0.001)
	_key(ed, KEY_PAGEDOWN)
	assert_near(ed.view_alt(), 7.0, 0.001, "pas au-delà du plus haut")
	_key(ed, KEY_PAGEUP)
	assert_near(ed.view_alt(), 3.5, 0.001, "Page préc. : niveau du dessous")
	ed.add_floor()
	assert_near(ed.view_alt(), 10.5, 0.001, "nouveau niveau vide 3,5 m au-dessus du plus haut")
	assert_true(ed.doc.rooms_on(ed.floor_k).is_empty())
	var r := ed.add_level_at(12.25)
	assert_true(r.ok and absf(ed.view_alt() - 12.25) < 0.001, "nouveau niveau vide à 12,25 m")
	ed.remove_top_floor()
	assert_eq(ed.doc.level_index(12.25), -1, "niveau vide du haut retiré")
	await _done(ed)


# ------------------------------------------------------------------ altitude d'une pièce

func test_room_altitude_moves_content_and_stair_arrival_in_one_undo() -> void:
	var ed := await _editor(Free.high_hall())
	var n0 := _undos(ed)
	var r := ed.panels.set_room_altitude("m1", 4.0)
	assert_true(r.ok, "mezzanine montée à 4 m (%s)" % MapRules.why(r))
	assert_near(EditorMap.alt_of(ed.doc.find("m1")), 4.0, 0.0001)
	var s1 := ed.doc.find("s1e")
	assert_near(EditorMap.alt_of(s1), 0.0, 0.0001, "escalier qui y arrive : son pied reste")
	assert_near(float(s1.altitude_haut), 4.0, 0.0001, "… son arrivée suit")
	assert_near(float(ed.doc.find("s2e").altitude_haut), 7.0, 0.0001, "l'autre escalier ne bouge pas")
	assert_eq(_undos(ed), n0 + 1, "une étape d'annulation")
	ed.undo()
	assert_near(EditorMap.alt_of(ed.doc.find("m1")), 3.5, 0.0001, "Ctrl+Z : mezzanine revenue")
	assert_near(float(ed.doc.find("s1e").altitude_haut), 3.5, 0.0001, "Ctrl+Z : arrivée revenue")
	await _done(ed)


func test_room_carries_the_foot_of_its_stairs() -> void:
	var ed := await _editor(Free.half_level())
	var plan := MapTransform.vertical_plan(ed.doc, ["pa"])
	assert_eq(plan.foot, ["r1"], "la rampe part de la salle : son pied")
	var plan2 := MapTransform.vertical_plan(ed.doc, ["pp"])
	assert_eq(plan2.top, ["r1"], "elle arrive au palier : son arrivée")
	var plan3 := MapTransform.vertical_plan(ed.doc, ["pa", "pp"])
	assert_true(plan3.both.has("r1") and plan3.foot.is_empty() and plan3.top.is_empty(), "les deux pièces : tout l'escalier (%s)" % [plan3])
	# Le palier monte de 0,25 m : la rampe arrive 0,25 m plus haut, son pied reste.
	var r := ed.panels.set_room_altitude("pp", 1.75)
	assert_true(r.ok, "palier à 1,75 m (%s)" % MapRules.why(r))
	assert_near(float(ed.doc.find("r1").altitude_haut), 1.75, 0.0001)
	assert_near(EditorMap.alt_of(ed.doc.find("r1")), 0.0, 0.0001)
	await _done(ed)


func test_refused_altitude_leaves_the_map_intact() -> void:
	var ed := await _editor(Free.high_hall())
	var before := ed.doc.snapshot()
	var n0 := _undos(ed)
	var r := ed.panels.set_room_altitude("m1", 2.0)
	assert_false(r.ok, "à 2 m de la halle qu'elle recouvre : refusé")
	assert_true(MapRules.why(r).contains("3,1") or MapRules.why(r).contains("3.1"), "refus nommé : %s" % MapRules.why(r))
	assert_eq(ed.doc.snapshot(), before, "carte intacte")
	assert_eq(_undos(ed), n0, "aucune étape d'annulation")
	# Escalier qui n'arriverait plus au-dessus de son pied : refusé aussi.
	r = ed.panels.set_room_altitude("m1", -0.5)
	assert_false(r.ok, "mezzanine sous le pied de son escalier : refusée")
	assert_eq(ed.doc.snapshot(), before, "carte intacte")
	await _done(ed)


func test_shift_page_moves_the_selection_to_the_next_level() -> void:
	var ed := await _editor(_stack())
	ed.select("A")
	var n0 := _undos(ed)
	_key(ed, KEY_PAGEDOWN, true)
	var a := ed.doc.find("A")
	assert_near(EditorMap.alt_of(a), 3.5, 0.0001, "Maj+Page suiv. : salle A au niveau du dessus")
	assert_near(EditorMap.alt_of(ed.doc.find("s1")), 3.5, 0.0001, "son départ avec elle")
	assert_near(EditorMap.alt_of(ed.doc.find("w1")), 3.5, 0.0001, "sa fenêtre avec elle")
	assert_near(ed.view_alt(), 3.5, 0.001, "la vue la suit")
	assert_eq(ed.selected, "A")
	assert_eq(_undos(ed), n0 + 1, "une étape d'annulation")
	_key(ed, KEY_PAGEUP, true)
	assert_near(EditorMap.alt_of(ed.doc.find("A")), 0.0, 0.0001, "Maj+Page préc. : revenue")
	# Refus : B ne peut pas monter dans C (pièces de même altitude qui se recouvrent).
	ed.select("B")
	var before := ed.doc.snapshot()
	var r := ed.move_selection_level(1)
	assert_false(r.ok, "B sur C : refusé")
	assert_eq(ed.doc.snapshot(), before, "carte intacte")
	# Menu du clic droit : les deux entrées, grisées sans sélection.
	ed.select("")
	ed.open_context_menu(Vector2(100, 100), Vector2(5, 5), "")
	assert_true(String(ed.context_menu.states()[MapContextMenu.LEVEL_UP]) != "", "grisée sans sélection")
	ed.context_menu.hide()
	ed.open_context_menu(Vector2(100, 100), Vector2(5, 5), "A")
	assert_eq(String(ed.context_menu.states()[MapContextMenu.LEVEL_UP]), "")
	ed.context_menu._on_id(MapContextMenu.LEVEL_UP)
	assert_near(EditorMap.alt_of(ed.doc.find("A")), 3.5, 0.0001, "menu : Monter d'un niveau")
	ed.context_menu.hide()
	await _done(ed)


func test_group_moves_vertically_by_altitude() -> void:
	var ed := await _editor(_stack())
	var snap := ed.doc.snapshot()
	var r := MapGroup.move(ed, MapGroup.movers(ed.doc, ["A"]), Vector2.ZERO, 1.25, snap, NAN, {}, ["A"])
	assert_true(r.ok, "groupe monté de 1,25 m (%s)" % MapRules.why(r))
	assert_near(EditorMap.alt_of(ed.doc.find("A")), 1.25, 0.0001)
	assert_near(EditorMap.alt_of(ed.doc.find("b1")), 1.25, 0.0001, "sa boîte avec elle")
	r = MapGroup.move(ed, MapGroup.movers(ed.doc, ["B"]), Vector2.ZERO, 1.0, ed.doc.snapshot(), NAN, {}, ["B"])
	assert_false(r.ok, "B à 1 m de C : refusé")
	await _done(ed)


# ------------------------------------------------------------------ onglet Niveaux

func test_duplicate_level_above_with_new_ids_and_zones() -> void:
	var ed := await _editor(EditorMap.load_dir("res://assets/maps/draft_arena/"))
	var k := ed.doc.level_index(3.5)
	var n_rooms := ed.doc.pieces.size()
	var ids0 := ed.doc.pieces.map(func(p): return String(p.id)) + ed.doc.objets.map(func(o): return String(o.id))
	var zones0 := ed.doc.zones.size()
	var n0 := _undos(ed)
	assert_near(ed.level_copy_gap(k), 3.6, 0.001, "écart : plafond 3,3 m + dalle")
	var r := ed.duplicate_level(k)
	assert_true(r.ok, "passerelle dupliquée (%s)" % MapRules.why(r))
	assert_eq(ed.doc.pieces.size(), n_rooms + 1)
	var copy := ed.doc.rooms_on(ed.doc.level_index(7.1))
	assert_eq(copy.size(), 1, "copie au niveau 7,1 m")
	assert_false(String(copy[0].id) in ids0, "nouvel identifiant")
	assert_true(String(copy[0].zone) != "z5", "nouvelle zone")
	assert_eq(ed.doc.zones.size(), zones0 + 1)
	assert_true((r.ids as Array).all(func(i): return not ids0.has(i)), "tous les identifiants sont neufs")
	assert_true(ed.doc.objects_on(ed.doc.level_index(7.1)).size() > 0, "son contenu copié")
	assert_near(ed.view_alt(), 7.1, 0.001, "la vue va à la copie")
	assert_eq(_undos(ed), n0 + 1, "une étape d'annulation")
	ed.undo()
	assert_eq(ed.doc.pieces.size(), n_rooms, "Ctrl+Z : copie retirée")
	# Niveau 0 : les escaliers ne sont pas copiés.
	r = ed.duplicate_level(0)
	assert_true(r.ok, "rez-de-chaussée dupliqué (%s)" % MapRules.why(r))
	assert_true(ed.status.text.contains(Lang.t("escalier", "stair")), "escaliers non copiés signalés : %s" % ed.status.text)
	await _done(ed)


func test_levels_tab_actions() -> void:
	var ed := await _editor(EditorMap.load_dir("res://assets/maps/draft_arena/"))
	ed.set_floor(ed.doc.level_index(3.5))
	ed.panels.show_tab("floors")
	ed.panels.refresh_now()
	var tab := ed.panels
	var list := tab.find_child("LevelList", true, false) as ItemList
	assert_eq(list.item_count, 2, "deux niveaux")
	assert_true(list.get_item_text(0).contains(EditorMap.alt_text(3.5, not Lang.is_en())), "le plus haut en tête : %s" % list.get_item_text(0))
	# Déplacer le niveau de 0,5 m : tout ce qui y est posé suit, l'arrivée de l'escalier aussi.
	(tab.find_child("LevelMoveBy", true, false) as SpinBox).get_line_edit().text = "0,5"
	(tab.find_child("LevelMoveGo", true, false) as Button).pressed.emit()
	assert_near(EditorMap.alt_of(ed.doc.find("p5")), 4.0, 0.0001, "passerelle à 4 m")
	assert_near(float(ed.doc.find("x2").altitude_haut), 4.0, 0.0001, "escalier : arrivée à 4 m")
	assert_near(ed.view_alt(), 4.0, 0.001, "la vue suit le niveau")
	ed.undo()
	assert_near(EditorMap.alt_of(ed.doc.find("p5")), 3.5, 0.0001, "Ctrl+Z")
	# Déplacer trop bas : refus nommé, rien ne bouge.
	ed.panels.refresh_now()
	(tab.find_child("LevelMoveBy", true, false) as SpinBox).get_line_edit().text = "-2"
	var before := ed.doc.snapshot()
	(tab.find_child("LevelMoveGo", true, false) as Button).pressed.emit()
	assert_eq(ed.doc.snapshot(), before, "à 1,5 m de l'entrepôt : refusé, carte intacte")
	# Nouveau niveau vide à … m.
	ed.panels.refresh_now()
	(tab.find_child("LevelNewAlt", true, false) as SpinBox).get_line_edit().text = "9 m"
	(tab.find_child("LevelNewGo", true, false) as Button).pressed.emit()
	assert_near(ed.view_alt(), 9.0, 0.001, "niveau vide à 9 m affiché")
	# Choisir un niveau dans la liste, puis Voir.
	ed.panels.refresh_now()
	list = tab.find_child("LevelList", true, false) as ItemList
	var i35 := -1
	for i in list.item_count:
		if int(list.get_item_metadata(i)) == ed.doc.level_index(3.5):
			i35 = i
	list.select(i35)
	list.item_selected.emit(i35)
	ed.panels.refresh_now()
	assert_near(ed.view_alt(), 9.0, 0.001, "un clic choisit le niveau sans l'afficher")
	(tab.find_child("LevelSee", true, false) as Button).pressed.emit()
	assert_near(ed.view_alt(), 3.5, 0.001, "Voir : niveau 3,5 m affiché")
	# Supprimer le niveau : confirmation, puis tout ce qui y est posé disparaît.
	ed.panels.refresh_now()
	(tab.find_child("LevelDelete", true, false) as Button).pressed.emit()
	var dlg := ed.find_child("DeleteLevelDialog", true, false) as ConfirmationDialog
	assert_true(dlg != null, "boîte de confirmation")
	assert_true(dlg.dialog_text.contains(Lang.t("escalier", "stair")), "elle cite l'escalier qui y arrive : %s" % dlg.dialog_text)
	assert_false(ed.doc.find("p5").is_empty(), "rien de supprimé avant la confirmation")
	dlg.confirmed.emit()
	assert_true(ed.doc.find("p5").is_empty(), "passerelle supprimée")
	assert_true(ed.doc.find("x2").is_empty(), "escalier qui y arrivait supprimé")
	assert_eq(ed.doc.level_index(3.5), -1, "plus de niveau 3,5 m")
	ed.undo()
	assert_false(ed.doc.find("p5").is_empty() or ed.doc.find("x2").is_empty(), "Ctrl+Z : niveau rétabli")
	# Ciel de la carte trouvable dans l'onglet.
	ed.panels.refresh_now()
	var sky := false
	for c in tab.find_children("*", "OptionButton", true, false):
		if (c as OptionButton).get_item_text(0) == Lang.t("Sans fond (noir)", "None (black)"):
			sky = true
	assert_true(sky, "réglage du ciel dans l'onglet Niveaux")
	await _done(ed)


# ------------------------------------------------------------------ plan et élévations

func test_alt_click_picks_the_next_stacked_room() -> void:
	var ed := await _editor(Free.high_hall())
	var cv := ed.canvas
	var m := Vector2(3.0, 8.0)
	var st := ed.stacked_rooms(m)
	assert_eq(st.map(func(p): return String(p.id)), ["m1", "ph"], "mezzanine puis halle, du haut vers le bas")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = cv.to_px(m)
	mb.alt_pressed = true
	mb.pressed = true
	cv._gui_input(mb)
	var up := mb.duplicate()
	up.pressed = false
	cv._gui_input(up)
	assert_eq(ed.selected, "m1", "Alt + clic depuis 0 m : la mezzanine (autre niveau)")
	assert_near(ed.view_alt(), 3.5, 0.001, "la vue va à son niveau")
	mb.position = cv.to_px(m)
	cv._gui_input(mb)
	cv._gui_input(up)
	assert_eq(ed.selected, "ph", "Alt + clic suivant : la halle")
	assert_near(ed.view_alt(), 0.0, 0.001)
	# Sans pièce empilée : un clic ordinaire.
	assert_false(ed.stack_pick(Vector2(12.0, 8.0)), "une seule pièce sous le point")
	await _done(ed)


func test_click_in_elevation_goes_to_the_room_level() -> void:
	var ed := await _editor(Free.high_hall())
	var pn: MapViewPane = ed.views.panes[1]
	ed.views.set_pane_plane(pn, "avant")
	var ev: MapElevation = pn.view
	ev.zoom = 20.0
	ev.origin = Vector2(40, 300)
	await wait_frames(1)
	var e := ev.projected_of("m2")
	var c := Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = ev.to_px(c)
	mb.pressed = true
	ev._gui_input(mb)
	var up := mb.duplicate()
	up.pressed = false
	ev._gui_input(up)
	assert_eq(ed.selected, "m2", "clic sur la mezzanine du haut")
	assert_near(ed.view_alt(), 7.0, 0.001, "la vue Dessus va à son niveau")
	await _done(ed)


func _elev(ed: MapEditor) -> MapElevation:
	var pn: MapViewPane = ed.views.panes[1]
	ed.views.set_pane_plane(pn, "avant")
	var ev: MapElevation = pn.view
	ev.zoom = 20.0
	ev.origin = Vector2(40, 300)
	return ev


func _drag(ev: MapElevation, a: Vector2, b: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = ev.to_px(a)
	ev._gui_input(mm)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = ev.to_px(a)
	mb.pressed = true
	ev._gui_input(mb)
	for i in 4:
		var m2 := InputEventMouseMotion.new()
		m2.position = ev.to_px(a.lerp(b, (i + 1) / 4.0))
		ev._gui_input(m2)
	var up := mb.duplicate()
	up.position = ev.to_px(b)
	up.pressed = false
	ev._gui_input(up)


func test_room_drag_in_elevation_with_magnets() -> void:
	var ed := await _editor(_stack())
	var ev := _elev(ed)
	ed.canvas.set_snap_mode("grille")
	ed.select("A")
	await wait_frames(1)
	var e := ev.projected_of("A")
	var c := Vector2((float(e.u0) + float(e.u1)) * 0.5 + 3.0, (float(e.v0) + float(e.v1)) * 0.5)
	var n0 := _undos(ed)
	# 1,1 m plus haut : pas de 0,25 m -> 1 m.
	_drag(ev, c, c + Vector2(0, -1.1))
	assert_near(EditorMap.alt_of(ed.doc.find("A")), 1.0, 0.0001, "pièce montée de 1 m (pas de 0,25)")
	assert_near(EditorMap.alt_of(ed.doc.find("s1")), 1.0, 0.0001, "son contenu avec elle")
	assert_eq(_undos(ed), n0 + 1, "un glissement = une annulation")
	assert_near(ed.view_alt(), 1.0, 0.001, "la vue suit la pièce")
	# Près du niveau 3,5 m (celui de C) : aimantée dessus.
	e = ev.projected_of("A")
	c = Vector2((float(e.u0) + float(e.u1)) * 0.5 + 3.0, (float(e.v0) + float(e.v1)) * 0.5)
	_drag(ev, c, c + Vector2(0, -2.4))
	assert_near(EditorMap.alt_of(ed.doc.find("A")), 3.5, 0.0001, "aimant : sol du niveau 3,5 m")
	# Aimants d'une pièce empilée : au-dessus / au-dessous de celle qu'elle recouvre.
	var mags := MapVertical.room_alt_magnets(ed.doc, ed.doc.find("C"))
	var zs := mags.map(func(m): return snappedf(float(m.z), 0.01))
	assert_true(zs.has(3.5), "au-dessus de B : 3,2 + 0,3 = 3,5 (%s)" % [zs])
	assert_true(zs.has(-3.1), "sous B : -3,1 m")
	ed.undo()
	ed.undo()
	assert_near(EditorMap.alt_of(ed.doc.find("A")), 0.0, 0.0001, "deux Ctrl+Z : revenue")
	await _done(ed)


func test_level_tag_drag_is_free_and_refuses_stacking() -> void:
	var ed := await _editor(_stack())
	var ev := _elev(ed)
	ed.canvas.set_snap_mode("grille")
	await wait_frames(1)
	# Niveau 3,5 m (C sur B) : monté à 4,25 m, librement.
	var r := ed.shift_level_to(1, 4.25)
	assert_true(r.ok)
	assert_near(EditorMap.alt_of(ed.doc.find("C")), 4.25, 0.0001)
	r = ed.shift_level_to(1, 2.0)
	assert_false(r.ok, "à 2 m de B qu'il recouvre : refusé")
	assert_near(EditorMap.alt_of(ed.doc.find("C")), 4.25, 0.0001, "dernière place gardée")
	r = ed.shift_level_to(1, 0.0)
	assert_false(r.ok, "rejoindre le niveau de B qu'il recouvre : refusé")
	await _done(ed)


func test_plan_ghost_hatched_voids_and_dashed_rooms_above() -> void:
	var ed := await _editor(Free.high_hall())
	ed.set_floor(1)
	var voids := ed.canvas.high_void_polys(1)
	assert_eq(voids.size(), 1, "la halle traverse le niveau 3,5 m")
	assert_eq(String(voids[0].id), "ph")
	assert_eq((voids[0].holes as Array).size(), 1, "la mezzanine n'est pas hachurée")
	assert_eq(ed.canvas.high_void_polys(0).size(), 0, "rien au niveau de la halle")
	assert_eq(ed.canvas.ghost_k(), 0, "fantôme : le niveau du dessous")
	var mg := MapSnap.magnet(ed.doc, 1, Vector2(23.9, 0.1), 0.5, "", ed.canvas.ghost_k())
	assert_eq(String(mg.get("kind", "")), "fantome", "sommet du fantôme aimanté")
	assert_eq(Vector2(mg.p), Vector2(24, 0))
	ed.ghost_below = false
	assert_eq(ed.canvas.ghost_k(), -1, "fantôme masqué : pas d'aimant")
	ed.ghost_below = true
	ed.dashed_above = true
	ed.canvas.queue_redraw()
	await wait_frames(2)
	await _done(ed)


# ------------------------------------------------------------------ bornes et textes

func test_design_bounds_of_30_m_are_gone() -> void:
	assert_true(MapVertical.DECOR_Z[1] > 1000.0 and MapCatalog.WALL_LIGHT_HEIGHT[1] > 1000.0 and MapCatalog.CLIP_HEIGHT[1] > 1000.0, "plus de 30 m")
	assert_near(MapVertical.decor_z({"z": 45.0}), 45.0, 0.001, "décor à 45 m (sous un plafond réel assez haut)")
	assert_true(MapRules.check_arc({"type": "mur_courbe", "centre": [0, 0], "rayon": 200.0, "ouverture": 90.0, "segments": 8}).ok, "mur courbe de 200 m de rayon")
	assert_false(MapRules.check_arc({"type": "mur_courbe", "centre": [0, 0], "rayon": 9000.0, "ouverture": 90.0, "segments": 8}).ok, "trop grand pour la mémoire du validateur")
	var doc := _stack()
	doc.objets.append({"id": "i9", "type": "bloc_invisible", "altitude": 0, "rect": [1, 1, 2, 2], "hauteur": 100.0})
	assert_eq(CustomMapGuard.check_texts(doc.file_texts()).reasons, [], "barrière de 100 m : acceptée")


func test_texts_fr_and_en() -> void:
	var saved := Settings.language
	for lang in ["fr", "en"]:
		Settings.language = lang
		var ed := await _editor(Free.high_hall())
		ed.set_floor(1)
		var fr: bool = lang == "fr"
		assert_true(ed.floor_label.text.begins_with("Niveau 3,5 m" if fr else "Level 3.5 m"), "barre (%s) : %s" % [lang, ed.floor_label.text])
		ed.fill_level_menu()
		var pm := ed.floor_label.get_popup()
		assert_eq(pm.get_item_text(pm.get_item_index(MapEditor.LEVEL_MENU_OTHER)), "Autre altitude…" if fr else "Other altitude…")
		assert_true(pm.get_item_text(0).contains("pièce(s)" if fr else "room(s)"), pm.get_item_text(0))
		ed.open_context_menu(Vector2(100, 100), Vector2(3, 8), "m1")
		var labels := ed.context_menu.aligned_labels()
		assert_true(String(labels[MapContextMenu.LEVEL_UP]).begins_with("Monter d'un niveau" if fr else "Up one level"), String(labels[MapContextMenu.LEVEL_UP]))
		assert_true(String(labels[MapContextMenu.LEVEL_DOWN]).contains("Maj+Page préc." if fr else "Shift+Page Up"), String(labels[MapContextMenu.LEVEL_DOWN]))
		ed.context_menu.hide()
		assert_eq(ed.canvas.header_sub(), "Niveau 3,5 m" if fr else "Level 3.5 m")
		ed.panels.show_tab("floors")
		ed.panels.refresh_now()
		var see := ed.panels.find_child("LevelDuplicate", true, false) as Button
		assert_true(see.text.begins_with("Dupliquer au-dessus" if fr else "Duplicate above"), see.text)
		await _done(ed)
	Settings.language = saved
