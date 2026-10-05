extends TestCase
## Points ajoutés ou retirés d'un contour libre dans l'éditeur de cartes
## (MapVertex, docs/MAP_AUTHORING.md § 2) : poignée « + » glissée au milieu
## d'un côté, double-clic sur un côté, Suppr sur un sommet survolé ou saisi,
## menu du clic droit ; pièce rectangle qui devient un polygone ; jamais moins
## de 3 sommets ; refus d'un contour invalide ; une étape d'annulation par
## geste ; barrière invisible (« sommets »).

const TMP := "res://tests/_out/test_map_vertex_edit"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	ed.canvas.set_snap_mode("grille")
	ed.canvas.zoom = 18.0
	ed.canvas.origin = Vector2(40, 40)
	return ed


func _room(ed: MapEditor, pts: Array) -> String:
	ed.add_object({"contour": pts}, 0)
	return ed.selected


func _key(ed: MapEditor, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	ed._input(e)


## Glisse la souris de `a` à `b` (m) dans la vue Dessus.
func _drag(cv: MapCanvas, a: Vector2, b: Vector2) -> void:
	cv.mouse_inside = true
	cv.mouse_m = a
	cv._press(false)
	cv.mouse_m = b
	cv._drag_update()
	cv._release()


func _poly(ed: MapEditor, eid: String) -> PackedVector2Array:
	return MapVertex.poly_of(ed.doc.find(eid))


# ------------------------------------------------------------------ fonctions pures

func test_pure_helpers() -> void:
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	assert_eq(MapVertex.inserted(sq, 1, Vector2(4, 2)), PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 2), Vector2(4, 4), Vector2(0, 4)]), "point inséré après le sommet 1")
	assert_eq(MapVertex.removed(sq, 0).size(), 3, "sommet retiré")
	var hit := MapVertex.edge_at(sq, Vector2(2, 0.1), 0.2)
	assert_eq(int(hit.get("edge", -1)), 0, "côté nord touché")
	assert_true(MapVertex.edge_at(sq, Vector2(2, 2), 0.2).is_empty(), "milieu : aucun côté")
	var diag := PackedVector2Array([Vector2(0, 0), Vector2(3, 3), Vector2(0, 3)])
	var p := MapVertex.point_on_edge(diag, 0, Vector2(1.3, 1.1), Vector2(1, 1))
	assert_eq(p, Vector2(1, 1), "point aimanté gardé s'il est sur le côté")
	p = MapVertex.point_on_edge(diag, 0, Vector2(1.3, 1.1), Vector2(1.5, 1.0))
	assert_near(MapGeom.dist_to_segment(p, diag[0], diag[1]), 0.0, 0.01, "sinon projeté sur le côté en biais")
	var rect := {"contour": MapGeom.poly_arr(sq)}
	assert_eq(MapVertex.plus_handles(rect).size(), 8, "rectangle : deux « + » par côté (quart, trois quarts)")
	var tri := {"contour": MapGeom.poly_arr(diag)}
	assert_eq(MapVertex.plus_handles(tri).size(), 3, "polygone : un « + » au milieu de chaque côté")
	assert_eq(Vector2(MapVertex.plus_handles(tri)[0].p), Vector2(1.5, 1.5), "milieu du côté")


# ------------------------------------------------------------------ pièces

func test_plus_handle_turns_rectangle_into_polygon_and_undo() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var rid := _room(ed, [[4, 4], [12, 4], [12, 10], [4, 10]])
	assert_eq(cv.handles().size(), 8, "rectangle : 8 poignées de redimensionnement")
	var plus := cv.plus_handles()
	assert_eq(plus.size(), 8, "8 poignées « + »")
	# Simple clic sur un « + » sans le tirer : rien n'est ajouté.
	var top: Dictionary = plus.filter(func(ph): return absf(Vector2(ph.p).y - 4.0) < 0.01)[0]
	_drag(cv, top.p, top.p)
	assert_eq(_poly(ed, rid).size(), 4, "clic sans glisser : rien d'ajouté")
	# Glissé vers le nord : un sommet de plus à cet endroit.
	_drag(cv, top.p, Vector2(top.p.x, 2.0))
	var poly := _poly(ed, rid)
	assert_eq(poly.size(), 5, "point ajouté : 5 sommets (%s)" % ed.status.text)
	assert_true(poly.has(Vector2(top.p.x, 2.0)), "sommet là où la souris l'a lâché")
	assert_false(ed.doc.find(rid).has("forme"), "plus de forme de base")
	assert_eq(cv.handles().size(), 5, "polygone : une poignée par sommet")
	assert_eq(cv.plus_handles().size(), 5, "un « + » par côté")
	assert_true(ed.status.text.contains("5"), "barre d'état : %s" % ed.status.text)
	# Une seule étape d'annulation.
	ed.undo()
	assert_eq(_poly(ed, rid).size(), 4, "Ctrl+Z : le rectangle revient")
	ed.select(rid)
	assert_eq(cv.handles().size(), 8, "et ses 8 poignées")
	ed.queue_free()
	await wait_frames(1)


func test_double_click_adds_point_on_side() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var rid := _room(ed, [[4, 4], [12, 4], [12, 10], [4, 10]])
	cv.mouse_inside = true
	# Double-clic sur le côté est (premier clic : la pièce choisie se désélectionne).
	cv.mouse_m = Vector2(12.05, 6.1)
	cv._press(false)
	cv._release()
	cv._press(true)
	cv._release()
	var poly := _poly(ed, rid)
	assert_eq(poly.size(), 5, "double-clic : point ajouté (%s)" % ed.status.text)
	assert_true(poly.has(Vector2(12, 6)), "aimanté sur la grille, sur le côté (%s)" % str(poly))
	assert_eq(ed.selected, rid, "la pièce reste choisie")
	# Double-clic au milieu de la pièce : pas de point.
	cv.mouse_m = Vector2(8, 7)
	cv._press(false)
	cv._release()
	cv._press(true)
	cv._release()
	assert_eq(_poly(ed, rid).size(), 5, "loin d'un côté : rien")
	ed.undo()
	assert_eq(_poly(ed, rid).size(), 4, "Ctrl+Z : une étape")
	ed.queue_free()
	await wait_frames(1)


func test_delete_key_on_hovered_or_held_vertex_only() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var rid := _room(ed, [[4, 4], [12, 4], [12, 10], [8, 12], [4, 10]])
	ed.select(rid)
	# Suppr sur un sommet survolé : ce point seul.
	cv.mouse_inside = true
	cv.mouse_m = Vector2(8, 12)
	assert_eq(cv.vertex_at(cv.mouse_m), 3, "sommet survolé")
	_key(ed, KEY_DELETE)
	assert_false(ed.doc.find(rid).is_empty(), "la pièce reste")
	assert_eq(_poly(ed, rid).size(), 4, "point supprimé")
	assert_false(_poly(ed, rid).has(Vector2(8, 12)))
	ed.undo()
	assert_eq(_poly(ed, rid).size(), 5, "Ctrl+Z : le point revient")
	# Suppr pendant qu'un sommet est saisi (glissement en cours).
	ed.select(rid)
	cv.mouse_m = Vector2(8, 12)
	cv._press(false)
	assert_eq(String(cv.drag.get("kind", "")), "handle", "sommet saisi")
	cv.mouse_m = Vector2(8, 13)
	cv._drag_update()
	_key(ed, KEY_DELETE)
	assert_true(cv.drag.is_empty(), "glissement terminé")
	assert_eq(_poly(ed, rid).size(), 4, "sommet saisi supprimé")
	assert_false(_poly(ed, rid).has(Vector2(8, 13)), "pas de reste du glissement")
	ed.undo()
	assert_eq(_poly(ed, rid).size(), 5, "Ctrl+Z")
	assert_true(_poly(ed, rid).has(Vector2(8, 12)), "à sa place d'avant le glissement")
	# Souris ailleurs : Suppr supprime l'élément choisi, comme avant.
	ed.select(rid)
	cv.mouse_m = Vector2(7, 7)
	_key(ed, KEY_DELETE)
	assert_true(ed.doc.find(rid).is_empty(), "souris hors d'un sommet : la pièce est supprimée")
	ed.undo()
	# Souris hors de la vue : idem, même placée sur un sommet.
	ed.select(rid)
	cv.mouse_inside = false
	cv.mouse_m = Vector2(8, 12)
	_key(ed, KEY_DELETE)
	assert_true(ed.doc.find(rid).is_empty(), "souris hors de la vue : la pièce est supprimée")
	ed.queue_free()
	await wait_frames(1)


func test_minimum_three_and_invalid_outline_refused() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var tri := _room(ed, [[4, 4], [10, 4], [4, 10]])
	var res := ed.remove_vertex(tri, 1)
	assert_false(res.ok, "triangle : pas moins de 3 sommets")
	assert_eq(_poly(ed, tri).size(), 3)
	assert_true(ed.status.text.contains("3"), "refus expliqué : %s" % ed.status.text)
	# Pièce voisine : le point tiré dedans est refusé, le contour ne change pas.
	var a := _room(ed, [[12, 4], [18, 4], [18, 10], [12, 10]])
	var _b := _room(ed, [[18, 4], [24, 4], [24, 10], [18, 10]])
	ed.select(a)
	var before := ed.doc.find(a).duplicate(true)
	var east: Dictionary = cv.plus_handles().filter(func(ph): return absf(Vector2(ph.p).x - 18.0) < 0.01)[0]
	_drag(cv, east.p, Vector2(20, Vector2(east.p).y))
	assert_eq(ed.doc.find(a).contour, before.contour, "chevauchement : refusé")
	assert_true(cv.refusal != "", "refus montré : %s" % cv.refusal)
	# Côtés qui se croisent : refusé aussi.
	ed.select(a)
	var north: Dictionary = cv.plus_handles().filter(func(ph): return absf(Vector2(ph.p).y - 4.0) < 0.01)[0]
	_drag(cv, north.p, Vector2(Vector2(north.p).x, 12.0))
	assert_eq(ed.doc.find(a).contour, before.contour, "contour croisé : refusé")
	# Suppression qui rendrait la pièce trop petite : refusée.
	var thin := _room(ed, [[4, 14], [10, 14], [10, 15.6], [7, 15.6], [4, 15.6]])
	assert_true(ed.remove_vertex(thin, 1).ok, "sommet utile retiré")
	assert_false(ed.remove_vertex(thin, 0).ok, "triangle trop petit : refusé (%s)" % ed.status.text)
	ed.queue_free()
	await wait_frames(1)


func test_context_menu_point_entries() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var rid := _room(ed, [[4, 4], [12, 4], [12, 10], [8, 12], [4, 10]])
	ed.select(rid)
	cv.mouse_inside = true
	# Clic droit sur un sommet.
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = true
	mb.position = cv.to_px(Vector2(8, 12))
	cv._gui_input(mb)
	var m := ed.context_menu
	assert_true(m != null and m.visible, "menu ouvert")
	assert_true(m.get_item_text(0).begins_with(Lang.t("Supprimer ce point", "Delete this point")), "« Supprimer ce point » en tête : %s" % m.get_item_text(0))
	assert_eq(m.item_count, MapContextMenu.ENTRIES.size() + 2, "entrée du point et séparateur en plus")
	m._on_id(MapContextMenu.DELETE_POINT)
	m.hide()
	assert_eq(_poly(ed, rid).size(), 4, "point supprimé par le menu")
	# Clic droit sur un côté : « Ajouter un point ici ».
	mb.position = cv.to_px(Vector2(4, 6))
	cv._gui_input(mb)
	assert_true(m.get_item_text(0).begins_with(Lang.t("Ajouter un point ici", "Add a point here")), "« Ajouter un point ici » : %s" % m.get_item_text(0))
	m._on_id(MapContextMenu.ADD_POINT)
	m.hide()
	assert_true(_poly(ed, rid).has(Vector2(4, 6)), "point ajouté sur le côté ouest (%s)" % str(_poly(ed, rid)))
	# Ailleurs : le menu habituel.
	mb.position = cv.to_px(Vector2(7, 7))
	cv._gui_input(mb)
	assert_eq(m.item_count, MapContextMenu.ENTRIES.size(), "menu habituel")
	m.hide()
	# Triangle : « Supprimer ce point » grisé.
	var tri := _room(ed, [[20, 4], [26, 4], [20, 10]])
	ed.select(tri)
	mb.position = cv.to_px(Vector2(26, 4))
	cv._gui_input(mb)
	assert_true(m.is_item_disabled(0), "triangle : entrée grisée (%s)" % m.get_item_tooltip(0))
	m.hide()
	ed.queue_free()
	await wait_frames(1)


func test_wall_items_stay_valid_after_point_added() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	var rid := _room(ed, [[4, 4], [16, 4], [16, 12], [4, 12]])
	var perk := {"type": "atout", "atout": "titan"}
	var r := MapRules.place_wall_item(ed.doc, 0, perk, Vector2(10, 4.6))
	assert_true(r.ok, "atout posé : %s" % str(r))
	perk.merge({"altitude": 0, "position": r.get("position", [0, 0])})
	MapRules.apply_wall(perk, r)
	ed.add_object(perk, 0)
	var pid := ed.selected
	ed.select(rid)
	var south: Dictionary = cv.plus_handles().filter(func(ph): return absf(Vector2(ph.p).y - 12.0) < 0.01)[0]
	_drag(cv, south.p, Vector2(Vector2(south.p).x, 14.0))
	assert_eq(_poly(ed, rid).size(), 5, "point ajouté au sud")
	assert_true(MapRules.check_existing(ed.doc, ed.doc.find(pid)).ok, "l'atout du mur nord reste valide")
	assert_true(MapRules.check_existing(ed.doc, ed.doc.find(rid)).ok, "la pièce aussi")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ barrière invisible

func test_invisible_barrier_points() -> void:
	var ed: MapEditor = await _editor()
	var cv := ed.canvas
	ed.add_object({"type": "bloc_invisible", "sommets": [[4, 4], [8, 4], [8, 8], [4, 8]]}, 0)
	var bid := ed.selected
	assert_eq(cv.handles().size(), 4, "une poignée par sommet")
	assert_eq(cv.plus_handles().size(), 4, "un « + » par côté (pas de redimensionnement rectangle)")
	var east: Dictionary = cv.plus_handles().filter(func(ph): return absf(Vector2(ph.p).x - 8.0) < 0.01)[0]
	_drag(cv, east.p, Vector2(10, 6))
	assert_eq(_poly(ed, bid).size(), 5, "point ajouté")
	assert_true(_poly(ed, bid).has(Vector2(10, 6)))
	ed.select(bid)
	cv.mouse_inside = true
	cv.mouse_m = Vector2(10, 6)
	_key(ed, KEY_DELETE)
	assert_eq(_poly(ed, bid).size(), 4, "Suppr : point supprimé")
	assert_false(ed.doc.find(bid).is_empty(), "la barrière reste")
	assert_true(ed.remove_vertex(bid, 0).ok, "triangle")
	assert_false(ed.remove_vertex(bid, 0).ok, "pas moins de 3 sommets")
	ed.undo()
	assert_eq(_poly(ed, bid).size(), 4, "Ctrl+Z")
	ed.queue_free()
	await wait_frames(1)
