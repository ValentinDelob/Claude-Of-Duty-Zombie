extends TestCase
## Formes libres dans l'éditeur de cartes (docs/MAP_AUTHORING.md, « Formes
## libres ») : modes d'aimantation (grille, grille fine, libre, inversion
## Maj), saisie au clavier de la longueur et de l'angle, formes de base
## (cercle, ellipse, polygone, triangle, L, mur courbe), nombre de points d'une
## forme posée, rotation libre d'une pièce avec son contenu et d'un objet,
## mur mitoyen hors de la grille avec tolérance, porte sur un côté quelconque,
## collisions et navigation autour d'un cercle et d'un pilier tourné,
## escalier et piège tournés, format 4 relu à l'identique, formats 1 à 3 lus
## (DRAFT ARENA construite à l'identique), contrôle des cartes reçues.

const TMP := "res://tests/_out/test_map_editor_freeform"
## Empreinte SHA-256 de la description en maillage de DRAFT ARENA (JSON trié,
## noms en français) : la même qu'avant les formes libres (format 3), sauf le
## plafond de l'entrepôt sous la passerelle (toujours dessiné sous la dalle de
## l'étage du dessus, MapLayoutExport.under_slab), les objets supprimés au
## lot C (atouts, armes murales, une seule caisse) et, format 18, sa porte
## d'évacuation (marqueur « evac », regard de départ).
const DRAFT_LAYOUT_SHA := "887b82bf034a45305d6a756f10a8e9c712581570fe88f62cc435018465254073"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


# ------------------------------------------------------------------ carte d'essai

## Sommets est du cercle (côté à plat à l'est) : [haut, bas].
static func east_edge(poly: PackedVector2Array) -> Array:
	var best := -1
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if absf(a.x - b.x) < 0.001 and (best < 0 or a.x > poly[best].x):
			best = i
	var p := poly[best]
	var q := poly[(best + 1) % poly.size()]
	return [p, q] if p.y < q.y else [q, p]


## Salle ronde de 32 points (rayon 13 m, départ), annexe tracée sans grille
## collée à son côté est (une porte), mur courbe et pilier tourné à 30° dans
## la salle ronde, une fenêtre chacune, boîte dans l'annexe.
static func round_map() -> EditorMap:
	var doc := EditorMap.blank("ronde", "SALLE RONDE", "ROUND ROOM")
	var za := doc.add_zone("Salle ronde", "Round room")
	var zb := doc.add_zone("Annexe", "Annex")
	var forme := {"type": "cercle", "centre": [16.0, 16.0], "rx": 13.0, "points": 32, "angle": 0}
	var circle := MapShapes.outline(forme)
	doc.pieces.append({"id": "p1", "nom": "Salle ronde", "altitude": 0, "zone": za.id, "contour": MapGeom.poly_arr(circle), "forme": forme})
	var e := east_edge(circle)
	var top: Vector2 = e[0]
	var bottom: Vector2 = e[1]
	var annex := PackedVector2Array([top, MapGeom.round_cm(top + Vector2(8, 0)), MapGeom.round_cm(bottom + Vector2(8, 0)), bottom])
	doc.pieces.append({"id": "p2", "nom": "Annexe", "altitude": 0, "zone": zb.id, "contour": MapGeom.poly_arr(annex), "surface_murs": "brick"})
	doc.depart = String(za.id)
	var r := MapRules.place_opening(doc, 0, "porte", (top + bottom) * 0.5, 1.5)
	doc.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": r.position, "largeur": 1.5, "prix": 750})
	for pt in [Vector2(6.6, 6.6), (top + bottom) * 0.5 + Vector2(8.3, 0)]:
		var w := MapRules.place_opening(doc, 0, "fenetre", pt, 1.0)
		doc.ouvertures.append({"id": doc.new_id("o"), "type": "fenetre", "altitude": 0, "position": w.position})
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": [18.0, 18.0]})
	doc.objets.append({"id": "x1", "type": "pilier", "altitude": 0, "rect": [9.0, 17.0, 11.0, 19.0], "rot": 30})
	doc.objets.append({"id": "m1", "type": "mur_courbe", "altitude": 0, "centre": [16.0, 16.0], "rayon": 7.0, "debut": 290.0, "ouverture": 100.0,
		"segments": 8, "epaisseur": 0.5})
	var box := {"type": "boite", "depart": false}
	var res := MapRules.place_wall_item(doc, 0, box, (top + bottom) * 0.5 + Vector2(4.0, -0.9))
	box["id"] = "b1"
	box["altitude"] = 0.0
	box["position"] = res.position
	MapRules.apply_wall(box, res)
	doc.objets.append(box)
	return MapTestKit.add_evac(doc)


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


func test_round_map_is_playable() -> void:
	var doc := round_map()
	var v := _check(doc)
	assert_true(v.ok(), "salle ronde jouable :\n" + _errs(v))
	assert_eq(v.doors.size(), 1, "porte entre la salle ronde et l'annexe")
	if not v.doors.is_empty():
		assert_true(v.doors[0].has("oblique"), "porte sur un côté hors de la grille : vrai mur oblique")
	assert_eq(v.windows.size(), 2)


# ------------------------------------------------------------------ outils de l'éditeur

func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	ed.canvas.fine_step = 0.5
	ed.canvas.set_snap_mode("grille")
	ed.canvas.invert_snap = false
	return ed


## Touche envoyée à l'éditeur (`text` : caractère tapé, pour la saisie au clavier).
func _key(ed: MapEditor, code: Key, text := "", shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.shift_pressed = shift
	if text != "":
		e.unicode = text.unicode_at(0)
	ed._input(e)


func _type(ed: MapEditor, s: String) -> void:
	for ch in s:
		var code: Key = KEY_PERIOD if ch == "," or ch == "." else (KEY_MINUS if ch == "-" else KEY_0 + int(ch))
		_key(ed, code, ch)


## Clic (appui et relâchement sans bouger) au point `m` de la vue.
func _click(ed: MapEditor, m: Vector2) -> void:
	ed.canvas.mouse_m = m
	ed.canvas._press(false)
	ed.canvas._release()


func test_snap_modes() -> void:
	assert_eq(MapSnap.effective("grille", false, "grille"), "grille")
	assert_eq(MapSnap.effective("grille", true, "grille"), "libre", "Maj : la grille devient libre")
	assert_eq(MapSnap.effective("fine", true, "fine"), "libre", "Maj : la grille fine devient libre")
	assert_eq(MapSnap.effective("libre", true, "fine"), "fine", "Maj en libre : la dernière grille")
	var m := Vector2(3.337, 7.861)
	assert_eq(MapSnap.on_step(m, "grille", 0.5), Vector2(3, 8), "grille 1 m")
	assert_true(MapSnap.on_step(m, "fine", 0.25).is_equal_approx(Vector2(3.25, 7.75)), "grille fine 0,25 m")
	assert_true(MapSnap.on_step(m, "fine", 0.1).is_equal_approx(Vector2(3.3, 7.9)), "grille fine 0,1 m")
	assert_true(MapSnap.on_step(m, "libre", 0.5).is_equal_approx(Vector2(3.34, 7.86)), "libre : au centimètre")
	assert_eq(MapSnap.next_mode("grille"), "fine")
	assert_eq(MapSnap.next_mode("fine"), "libre")
	assert_eq(MapSnap.next_mode("libre"), "grille")
	assert_near(MapSnap.next_fine(0.5), 0.25, 0.0001)
	assert_near(MapSnap.next_fine(0.25), 0.1, 0.0001)
	assert_near(MapSnap.next_fine(0.1), 0.5, 0.0001)
	# Aimants de la carte (mode libre) : sommet d'abord, sinon un point du côté.
	var doc := EditorMap.blank()
	doc.pieces.append({"id": "p1", "altitude": 0, "zone": "z1", "contour": [[2, 2], [10, 2], [10, 8], [2, 8]]})
	var mg := MapSnap.magnet(doc, 0, Vector2(10.1, 8.05), 0.3)
	assert_true(not mg.is_empty() and mg.kind == "sommet" and Vector2(mg.p) == Vector2(10, 8), "aimant : sommet %s" % str(mg))
	mg = MapSnap.magnet(doc, 0, Vector2(6.07, 8.12), 0.3)
	assert_true(not mg.is_empty() and mg.kind == "cote" and Vector2(mg.p).is_equal_approx(Vector2(6.07, 8)), "aimant : côté %s" % str(mg))
	assert_true(MapSnap.magnet(doc, 0, Vector2(6, 5), 0.3).is_empty(), "loin des côtés : pas d'aimant")
	assert_true(MapSnap.magnet(doc, 0, Vector2(10.1, 8.05), 0.3, "p1").is_empty(), "la pièce déplacée n'aimante pas")
	# Tracé sans grille : côtés à 15° près, Alt libre, longueur au centimètre.
	assert_true(MapSnap.trace_free(doc, 0, Vector2(2, 12), Vector2(5.1, 12.2), 0.3, false).is_equal_approx(Vector2(5.1, 12)), "presque horizontal -> 0°")
	var p30 := MapSnap.trace_free(doc, 0, Vector2(2, 12), Vector2(5.5, 10.1), 0.3, false)
	assert_near(MapGeom.dir_angle(p30 - Vector2(2, 12)), 30.0, 0.3, "à 15° près : 30° (%s)" % p30)
	assert_true(MapSnap.trace_free(doc, 0, Vector2(2, 12), Vector2(5.123, 10.456), 0.3, true).is_equal_approx(Vector2(5.12, 10.46)), "Alt : angle libre, centimètre")
	# Tracé vers un côté : le trait à 15° s'arrête sur le côté aimanté.
	var hit := MapSnap.trace_free(doc, 0, Vector2(6, 14), Vector2(6.05, 8.1), 0.3, false)
	assert_true(hit.is_equal_approx(Vector2(6, 8)), "trait vertical arrêté sur le côté : %s" % hit)
	# Dans l'éditeur : G change de mode (mémorisé), Maj l'inverse.
	var ed := await _editor()
	var cv := ed.canvas
	assert_eq(cv.snap(Vector2(3.4, 3.6)), Vector2(3, 4), "grille 1 m par défaut")
	_key(ed, KEY_G)
	assert_eq(cv.snap_mode, "fine", "G : grille fine")
	assert_true(cv.snap(Vector2(3.4, 3.6)).is_equal_approx(Vector2(3.5, 3.5)), "grille fine 0,5 m")
	_key(ed, KEY_G, "", true)
	assert_near(cv.fine_step, 0.25, 0.0001, "Maj+G : pas fin 0,25 m")
	_key(ed, KEY_G)
	assert_eq(cv.snap_mode, "libre", "G : libre")
	assert_true(cv.snap(Vector2(3.437, 3.612)).is_equal_approx(Vector2(3.44, 3.61)), "libre : au centimètre")
	cv.invert_snap = true
	assert_eq(cv.mode_now(), "fine", "Maj en libre : la grille fine")
	assert_true(cv.snap(Vector2(3.437, 3.612)).is_equal_approx(Vector2(3.5, 3.5)), "Maj : grille fine 0,25 m")
	cv.invert_snap = false
	assert_eq(String(MapEditor.pref("aimantation", "")), "libre", "mode mémorisé")
	assert_near(float(MapEditor.pref("pas_fin", 0.0)), 0.25, 0.0001, "pas fin mémorisé")
	assert_true(ed.snap_button.text.contains(Lang.t("libre", "free")), "bouton de la barre du haut : %s" % ed.snap_button.text)
	cv.set_snap_mode("grille")
	ed.queue_free()
	await wait_frames(1)


func test_keyboard_entry_length_and_angle() -> void:
	var ed := await _editor()
	var cv := ed.canvas
	cv.zoom = 20.0
	# Pièce polygone : premier point, puis « 4 Tab 30 Entrée » : 4 m à 30°.
	ed.select_slot(2)
	assert_eq(ed.current_item().id, "piece_poly")
	_click(ed, Vector2(2, 6))
	_type(ed, "4")
	assert_eq(cv.entry.get("values", []), ["4", ""], "longueur tapée")
	_key(ed, KEY_TAB)
	assert_eq(int(cv.entry.get("i", -1)), 1, "Tab : champ de l'angle")
	_type(ed, "30")
	_key(ed, KEY_ENTER)
	assert_eq(cv.poly_pts.size(), 2, "côté posé au clavier")
	var want := MapGeom.round_mm(MapGeom.polar(Vector2(2, 6), 4.0, 30.0))
	if cv.poly_pts.size() == 2:
		assert_true(cv.poly_pts[1].is_equal_approx(want), "4 m à 30° : %s (attendu %s)" % [cv.poly_pts[1], want])
		assert_near(cv.poly_pts[0].distance_to(cv.poly_pts[1]), 4.0, 0.01, "longueur exacte")
		# Seulement l'angle (Tab d'abord) : la longueur suit le curseur.
		cv.mouse_m = cv.poly_pts[1] + Vector2(0, 3)
		_key(ed, KEY_TAB)
		_type(ed, "-90")
		assert_near(cv.trace_end().distance_to(cv.poly_pts[1]), 3.0, 0.02, "longueur du curseur")
		assert_near(MapGeom.dir_angle(cv.trace_end() - cv.poly_pts[1]), 270.0, 0.1, "-90° : vers le sud")
		_key(ed, KEY_ESCAPE)
		assert_true(cv.entry.is_empty() and cv.poly_pts.size() == 2, "Échap : saisie annulée, tracé gardé")
	# Mur : un clic (sans glisser) puis « 5 Tab 90 Entrée » : 5 m vers le nord.
	ed.select_slot(3)
	_click(ed, Vector2(3, 18))
	assert_true(cv.drag.get("sticky", false), "simple clic : le tracé suit le curseur")
	_type(ed, "5")
	_key(ed, KEY_TAB)
	_type(ed, "90")
	_key(ed, KEY_ENTER)
	var walls := ed.doc.objets.filter(func(o): return o.type == "mur")
	assert_eq(walls.size(), 1, "mur posé au clavier")
	if not walls.is_empty():
		assert_true(MapGeom.v2(walls[0].b).is_equal_approx(Vector2(3, 13)), "5 m à 90° (nord) : %s" % str(walls[0].b))
	# Rectangle : « 6 Tab 4,5 Entrée ».
	ed.select_slot(1)
	_click(ed, Vector2(12, 2))
	_type(ed, "6")
	_key(ed, KEY_TAB)
	_type(ed, "4,5")
	_key(ed, KEY_ENTER)
	assert_eq(ed.doc.pieces.size(), 1, "rectangle posé au clavier")
	if not ed.doc.pieces.is_empty():
		assert_eq(MapGeom.bbox(ed.doc.room_poly(ed.doc.pieces[0])), Rect2(12, 2, 6, 4.5), "6 × 4,5 m")
	# Cercle : « 3 Tab 12 Entrée » : rayon 3 m, 12 points.
	ed.set_hotbar(4, "piece_cercle")
	_click(ed, Vector2(26, 12))
	_type(ed, "3")
	_key(ed, KEY_TAB)
	_type(ed, "12")
	_key(ed, KEY_ENTER)
	var circles := ed.doc.pieces.filter(func(p): return p.has("forme"))
	assert_eq(circles.size(), 1, "cercle posé au clavier")
	if not circles.is_empty():
		assert_eq(int(circles[0].forme.points), 12, "12 points")
		assert_near(float(circles[0].forme.rx), 3.0, 0.001, "rayon 3 m")
		assert_eq(circles[0].contour.size(), 12)
	# + / - et molette pendant le tracé : nombre de points.
	_click(ed, Vector2(40, 12))
	var n0 := cv.shape_points
	_key(ed, KEY_PLUS, "+")
	_key(ed, KEY_PLUS, "+")
	_key(ed, KEY_MINUS, "-")
	assert_eq(cv.shape_points, n0 + 1, "+ + - : un point de plus")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = cv.to_px(cv.mouse_m)
	cv._gui_input(wheel)
	assert_eq(cv.shape_points, n0 + 2, "molette : un point de plus")
	cv.cancel()
	# Mur courbe : « 4 Tab 180 Entrée » : rayon 4 m, demi-cercle.
	ed.set_hotbar(5, "mur_courbe")
	_click(ed, Vector2(30, 30))
	_type(ed, "4")
	_key(ed, KEY_TAB)
	_type(ed, "180")
	_key(ed, KEY_ENTER)
	var arcs := ed.doc.objets.filter(func(o): return o.type == "mur_courbe")
	assert_true(arcs.size() == 1 and absf(float(arcs[0].rayon) - 4.0) < 0.001 and absf(float(arcs[0].ouverture) - 180.0) < 0.01,
		"mur courbe posé au clavier : %s" % str(arcs))
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ formes de base

func test_shape_generation() -> void:
	var c := Vector2(20, 20)
	for n in [3, 5, 12, 32, 64]:
		var p := MapShapes.regular(c, 4.0, 4.0, n)
		assert_eq(p.size(), n, "%d points" % n)
		var exact := true
		for v in p:
			exact = exact and absf(v.distance_to(c) - 4.0) < 1e-4
		assert_true(exact, "rayon exact (%d points)" % n)
		assert_near(p[0].y, p[n - 1].y, 1e-4, "côté à plat au sud (%d points)" % n)
		assert_true(p[0].y > c.y and MapGeom.is_simple(p), "contour simple")
	assert_eq(MapShapes.regular(c, 4, 4, 2).size(), 3, "3 points au moins")
	assert_eq(MapShapes.regular(c, 4, 4, 100).size(), 64, "64 points au plus")
	var e := east_edge(MapShapes.regular(c, 4, 4, 32))
	assert_true(absf(Vector2(e[0]).x - Vector2(e[1]).x) < 1e-4, "32 points : côté est droit (une pièce s'y colle)")
	assert_true(MapGeom.is_axis_rect(MapShapes.outline({"type": "cercle", "centre": [20, 20], "rx": 4, "points": 4})), "4 points : un carré droit")
	assert_false(MapGeom.is_axis_rect(MapShapes.regular(c, 4, 4, 4, 45)), "tourné de 45° : un losange")
	# Ellipse : chaque sommet sur l'ellipse.
	var el := MapShapes.outline(MapShapes.from_drag("ellipse", Vector2(4, 4), Vector2(16, 10), 24))
	assert_eq(el.size(), 24)
	var on := true
	for v in el:
		on = on and absf(pow((v.x - 10.0) / 6.0, 2) + pow((v.y - 7.0) / 3.0, 2) - 1.0) < 0.002
	assert_true(on, "sommets sur l'ellipse de 12 × 6 m")
	# Triangle et L : surfaces.
	var tri := MapShapes.outline(MapShapes.from_drag("triangle", Vector2(2, 2), Vector2(8, 6), 0))
	assert_near(MapGeom.area(tri), 12.0, 0.01, "triangle 6 × 4 m : 12 m²")
	assert_true(MapGeom.bbox(tri).is_equal_approx(Rect2(2, 2, 6, 4)), "triangle dans son rectangle")
	var l := MapShapes.outline(MapShapes.from_drag("l", Vector2(0, 0), Vector2(10, 8), 0))
	assert_eq(l.size(), 6, "L : 6 sommets")
	assert_near(MapGeom.area(l), 60.0, 0.01, "L à branches de 50 % : 3/4 de 10 × 8 m")
	# Cercle au glisser : du centre au bord.
	var ci := MapShapes.from_drag("cercle", Vector2(10, 10), Vector2(13, 14), 16)
	assert_near(float(ci.rx), 5.0, 0.001, "rayon 5 m")
	assert_eq(MapShapes.outline(ci).size(), 16)
	# Mur courbe : segments + 1 points, rayon exact, du nord vers l'est.
	var arc := MapShapes.arc_points(Vector2(10, 10), 5.0, 0.0, 90.0, 6)
	assert_eq(arc.size(), 7, "6 segments : 7 points")
	assert_true(arc[0].is_equal_approx(Vector2(10, 5)) and arc[6].is_equal_approx(Vector2(15, 10)), "du nord à l'est : %s … %s" % [arc[0], arc[6]])
	var ok := true
	for v in arc:
		ok = ok and absf(v.distance_to(Vector2(10, 10)) - 5.0) < 0.002
	assert_true(ok, "arc : rayon exact")
	var o := MapShapes.arc_from_drag({"type": "mur_courbe", "epaisseur": 0.5}, Vector2(10, 10), Vector2(13, 10), 8, 120.0)
	assert_true(absf(float(o.rayon) - 3.0) < 0.001 and absf(float(o.debut) - 90.0) < 0.01 and int(o.segments) == 8, "mur courbe au glisser : %s" % str(o))
	assert_true(MapRules.check_arc(o).ok, "mur courbe valide")
	assert_false(MapRules.check_arc(o.merged({"rayon": 0.4}, true)).ok, "rayon trop petit refusé")


func test_change_points_of_placed_shape() -> void:
	var doc := EditorMap.blank()
	var z := doc.add_zone("Rond", "Round")
	var forme := {"type": "cercle", "centre": [12.0, 12.0], "rx": 8.0, "points": 24, "angle": 0}
	doc.pieces.append({"id": "p1", "nom": "Rond", "altitude": 0, "zone": z.id, "contour": MapGeom.poly_arr(MapShapes.outline(forme)), "forme": forme})
	var w := MapRules.place_opening(doc, 0, "fenetre", Vector2(12, 20.4), 1.0)
	assert_true(w.ok, "fenêtre sur le côté sud : %s" % str(w))
	doc.ouvertures.append({"id": "o1", "type": "fenetre", "altitude": 0, "position": w.get("position", [0, 0])})
	var room := doc.find("p1")
	var f: Dictionary = room.forme.duplicate(true)
	f["points"] = 12
	var res := MapTransform.regenerate(doc, room, f)
	assert_true(res.ok, "12 points : %s" % str(res))
	assert_eq(doc.find("p1").contour.size(), 12, "contour régénéré")
	assert_eq(int(doc.find("p1").forme.points), 12, "paramètre gardé")
	var round_ok := true
	for v in doc.room_poly(doc.find("p1")):
		round_ok = round_ok and absf(v.distance_to(Vector2(12, 12)) - 8.0) < 0.002
	assert_true(round_ok, "rayon gardé")
	assert_true(MapRules.check_existing(doc, doc.find("o1")).ok, "la fenêtre reste sur son mur (%s)" % str(doc.find("o1").position))
	# Refus : la forme agrandie chevaucherait une autre pièce ; rien ne change.
	doc.pieces.append({"id": "p2", "nom": "Voisine", "altitude": 0, "zone": z.id, "contour": [[21, 4], [26, 4], [26, 20], [21, 20]]})
	var before := doc.file_texts()
	f["rx"] = 12.0
	assert_false(MapTransform.regenerate(doc, doc.find("p1"), f).ok, "agrandie sur la pièce voisine : refusée")
	assert_true(doc.file_texts() == before, "carte inchangée après un refus")
	# Sommet déplacé à la main : ce n'est plus une forme régénérable.
	var ed := await _editor()
	ed.doc = doc.duplicate_map()
	ed.changed()
	var orig: Dictionary = ed.doc.find("p1").duplicate(true)
	var r := ed.try_handle(orig, 0, MapGeom.v2(orig.contour[0]) + Vector2(0, 0.5), ed.doc.snapshot())
	assert_true(r.ok and not ed.doc.find("p1").has("forme"), "sommet déplacé : polygone libre")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ rotations libres

func _room_with_content() -> EditorMap:
	var doc := EditorMap.blank()
	var z := doc.add_zone("A", "A")
	doc.pieces.append({"id": "p1", "nom": "A", "altitude": 0, "zone": z.id, "contour": [[4, 4], [16, 4], [16, 12], [4, 12]]})
	var perk := {"type": "poste_central"}
	var r := MapRules.place_wall_item(doc, 0, perk, Vector2(10, 4.6))
	perk.merge({"id": "a1", "altitude": 0, "position": r.get("position", [0, 0])})
	MapRules.apply_wall(perk, r)
	doc.objets.append(perk)
	doc.objets.append({"id": "d1", "type": "prefab", "prefab": "bureau", "altitude": 0, "position": [8.0, 8.0], "rot": 0})
	doc.objets.append({"id": "x1", "type": "pilier", "altitude": 0, "rect": [12.0, 7.0, 13.0, 9.0]})
	var w := MapRules.place_opening(doc, 0, "fenetre", Vector2(10, 12.3), 1.0)
	doc.ouvertures.append({"id": "o1", "type": "fenetre", "altitude": 0, "position": w.get("position", [0, 0])})
	return doc


func test_free_rotation_of_a_room_with_its_content() -> void:
	var doc := _room_with_content()
	var room := doc.find("p1")
	var c := MapTransform.pivot(doc, room)
	assert_eq(c, Vector2(10, 8), "centre du rectangle englobant")
	var att := MapTransform.attached(doc, room)
	assert_eq(att.size(), 4, "poste central, bureau, pilier et fenêtre rattachés : %s" % str(att))
	var res := MapTransform.apply(doc, room.duplicate(true), att, c, 30.0, doc.snapshot())
	assert_true(res.ok, "pièce tournée de 30° : %s" % str(res))
	var p := doc.room_poly(doc.find("p1"))
	assert_true(p[0].distance_to(MapGeom.rotate_about(Vector2(4, 4), c, 30)) < 0.002, "sommets tournés")
	var perk := doc.find("a1")
	assert_near(float(perk.get("angle", -1.0)), 30.0, 0.01, "poste central : face au mur tourné (30°)")
	assert_true(MapRules.check_existing(doc, perk).ok, "poste central toujours collé à son mur : %s" % MapRules.why(MapRules.check_existing(doc, perk)))
	assert_eq(int(doc.find("d1").rot), 30, "bureau tourné de 30°")
	assert_true(MapGeom.v2(doc.find("d1").position).distance_to(MapGeom.rotate_about(Vector2(8, 8), c, 30)) < 0.002, "bureau déplacé avec la pièce")
	assert_eq(int(doc.find("x1").get("rot", 0)), 30, "pilier tourné de 30°")
	assert_true(MapRules.check_existing(doc, doc.find("o1")).ok, "fenêtre toujours sur son mur")
	for id in ["d1", "x1"]:
		assert_true(MapRules.check_existing(doc, doc.find(id)).ok, "%s toujours valide : %s" % [id, MapRules.why(MapRules.check_existing(doc, doc.find(id)))])
	# Tournée encore de 60° : 90° en tout, le poste central de nouveau contre un mur droit.
	res = MapTransform.apply(doc, doc.find("p1").duplicate(true), MapTransform.attached(doc, doc.find("p1")), c, 60.0, doc.snapshot())
	assert_true(res.ok, "90° en tout : %s" % str(res))
	assert_true(MapGeom.is_axis_rect(doc.room_poly(doc.find("p1"))), "rectangle de nouveau droit")
	assert_false(doc.find("a1").has("angle"), "poste central contre un mur droit : sans angle (%s)" % str(doc.find("a1")))
	assert_eq(String(doc.find("a1").mur), "e", "mur à l'est")
	# R (90°) : comme avant, la grille reste la grille.
	var q := MapTransform.rotated({"type": "escalier", "rect": [2, 2, 4, 7], "monte": "n"}, Vector2(3, 4.5), 90)
	assert_true(q.monte == "e" and not q.has("rot") and MapGeom.rect_of(q.rect).size == Vector2(5, 2), "quart de tour : rectangle droit, monte à l'est (%s)" % str(q))


func test_free_rotation_of_objects() -> void:
	var doc := _room_with_content()
	var desk := doc.find("d1")
	var res := MapTransform.apply(doc, desk.duplicate(true), [], MapTransform.pivot(doc, desk), 37.0, doc.snapshot())
	assert_true(res.ok, "bureau tourné de 37° : %s" % str(res))
	desk = doc.find("d1")
	assert_eq(int(desk.rot), 37, "au degré près")
	var poly := MapRaster.floor_poly(desk)
	assert_near(MapGeom.area(poly), 1.5, 0.001, "emprise 1,5 × 1 m")
	assert_near(rad_to_deg((poly[1] - poly[0]).angle()), 37.0, 0.01, "emprise tournée de 37°")
	var cells := MapRaster.floor_cells(desk)
	assert_true(cells.size() >= 3 and cells.all(func(cc): return MapGeom.contains(poly, MapGeom.cell_center(cc))), "cases du décor dans l'emprise tournée (%s)" % str(cells))
	assert_true(MapRules.hit(doc, desk, MapGeom.centroid(poly)), "clic sur le décor tourné")
	# Pilier tourné : vrai pavé oblique, pas de cases de la grille en escalier.
	var pil := doc.find("x1")
	res = MapTransform.apply(doc, pil.duplicate(true), [], MapTransform.pivot(doc, pil), 30.0, doc.snapshot())
	assert_true(res.ok, "pilier tourné de 30° : %s" % str(res))
	var v := MapRaster.build(doc).v
	var boxes: Array = v.oblique_walls[0].filter(func(w): return w.kind == "pilier")
	assert_eq(boxes.size(), 1, "un pavé oblique pour le pilier")
	if not boxes.is_empty():
		assert_near(Vector2(boxes[0].t).angle(), deg_to_rad(30.0), 0.001, "pavé tourné de 30°")
		assert_near(float(boxes[0].half), 1.25, 0.001, "contour sur le trait : 2 m + 0,5 m de mur")
	# Rotation refusée (le pilier sortirait de la pièce) : rien ne change.
	var big := {"id": "x2", "type": "pilier", "altitude": 0, "rect": [4.5, 5.0, 15.5, 6.0]}
	doc.objets.append(big)
	var before := doc.file_texts()
	res = MapTransform.apply(doc, big.duplicate(true), [], MapTransform.pivot(doc, big), 45.0, doc.snapshot())
	assert_false(res.ok, "pilier de 11 m tourné de 45° : il déborde, refusé")
	assert_true(doc.file_texts() == before, "carte inchangée")


func test_rotation_handle_in_the_editor() -> void:
	var ed := await _editor()
	var cv := ed.canvas
	ed.doc = _room_with_content()
	ed.changed()
	ed.select_mouse()
	ed.select("d1")
	# Format 14 : l'anneau Z (prise au nord) remplace la poignée ronde du décor.
	assert_true(cv.rot_handle().is_empty(), "pas de poignée ronde : l'anneau Z")
	var rh := _ring_grip(cv, ed.doc.find("d1"))
	assert_false(rh.is_empty(), "anneau Z sur le décor choisi")
	if rh.is_empty():
		ed.queue_free()
		return
	var c: Vector2 = rh.c
	cv.mouse_m = rh.p
	cv._press(false)
	assert_eq(String(cv.drag.get("kind", "")), "ring", "anneau attrapé")
	# Déplacée de 32° autour du centre : pas de 15° -> 30°.
	cv.mouse_m = c + (Vector2(rh.p) - c).rotated(deg_to_rad(32.0))
	cv._drag_update()
	cv._release()
	assert_eq(int(ed.doc.find("d1").rot), 30, "rotation aimantée à 15° : 30°")
	# Alt : au degré près.
	rh = _ring_grip(cv, ed.doc.find("d1"))
	cv.mouse_m = rh.p
	cv._press(false)
	cv.free_angle = true
	cv.mouse_m = Vector2(rh.c) + (Vector2(rh.p) - Vector2(rh.c)).rotated(deg_to_rad(7.2))
	cv._drag_update()
	cv._release()
	cv.free_angle = false
	assert_eq(int(ed.doc.find("d1").rot), 37, "Alt : 30 + 7 = 37°")
	ed.undo()
	assert_eq(int(ed.doc.find("d1").rot), 30, "Ctrl+Z : rotation annulée")
	# Objet mural : pas de poignée (il suit son mur).
	ed.select("a1")
	assert_true(cv.rot_handle().is_empty() and cv.gizmo.ring_of(ed.doc.find("a1")).is_empty(), "poste central : ni poignée ni anneau")
	ed.queue_free()
	await wait_frames(1)


## Prise de l'anneau Z d'un élément (m) : {p (prise au nord), c (centre)} ; {} sans anneau.
static func _ring_grip(cv: MapCanvas, e: Dictionary) -> Dictionary:
	var rg := cv.gizmo.ring_of(e)
	if rg.is_empty():
		return {}
	return {"p": cv.to_m(Vector2(rg.c) + Vector2(0, -float(rg.r))), "c": cv.to_m(Vector2(rg.c))}


# ------------------------------------------------------------------ murs mitoyens hors de la grille

func test_shared_wall_off_grid_with_tolerance() -> void:
	var doc := EditorMap.blank()
	var za := doc.add_zone("A", "A")
	var zb := doc.add_zone("B", "B")
	# Deux pièces tracées sans grille, collées par un côté en biais à 3 mm près.
	var a := PackedVector2Array([Vector2(2.13, 3.07), Vector2(9.41, 2.52), Vector2(10.33, 9.18), Vector2(3.02, 9.9)])
	var b := PackedVector2Array([Vector2(9.412, 2.523), Vector2(16.2, 3.1), Vector2(15.8, 9.4), Vector2(10.332, 9.177)])
	doc.pieces.append({"id": "p1", "nom": "A", "altitude": 0, "zone": za.id, "contour": MapGeom.poly_arr(a)})
	assert_false(MapGeom.overlap(a, b), "collées à 3 mm près : pas de chevauchement")
	assert_true(MapRules.check_room(doc, 0, b).ok, "pièce B acceptée contre A")
	doc.pieces.append({"id": "p2", "nom": "B", "altitude": 0, "zone": zb.id, "contour": MapGeom.poly_arr(b)})
	assert_eq(MapGeom.common_segments(a, b).size(), 1, "un bord commun malgré l'écart")
	var v := MapRaster.build(doc).v
	var common: Array = v.oblique_walls[0].filter(func(w): return w.kind == "piece" and w.pos != "" and w.neg != "")
	assert_eq(common.size(), 1, "un seul mur mitoyen")
	var r := MapRules.place_opening(doc, 0, "porte", Vector2(9.9, 6.0), 2.0)
	assert_true(r.ok and r.rooms == ["p1", "p2"], "porte sur le bord commun : %s" % str(r))
	# Une pièce sans grille collée au côté d'une pièce de la grille : ce côté
	# reste un mur de la grille, sans second mur oblique par-dessus.
	var d2 := EditorMap.blank()
	var zg := d2.add_zone("G", "G")
	var zf := d2.add_zone("F", "F")
	d2.pieces.append({"id": "g1", "nom": "G", "altitude": 0, "zone": zg.id, "contour": [[0, 0], [10, 0], [10, 10], [0, 10]]})
	d2.pieces.append({"id": "f1", "nom": "F", "altitude": 0, "zone": zf.id, "contour": [[10, 3.37], [15.23, 3.37], [15.23, 7.81], [10, 7.81]]})
	var v2 := MapRaster.build(d2).v
	var along: Array = v2.oblique_walls[0].filter(func(w): return absf(Vector2(w.a).x - 10.0) < 0.05 and absf(Vector2(w.b).x - 10.0) < 0.05)
	assert_eq(along.size(), 0, "pas de mur oblique en double sur le mur de la grille")
	var r2 := MapRules.place_opening(d2, 0, "porte", Vector2(10.1, 5.6), 2.0)
	assert_true(r2.ok and not r2.has("dir") and absf(float(r2.get("position", [0, 0])[0]) - 10.0) < 0.001, "porte dans le mur de la grille : %s" % str(r2))
	d2.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": r2.get("position", [10, 5.5]), "largeur": 2.0, "prix": 750})
	var f2: MapValidator.Floor = MapRaster.build(d2).v.floors[0]
	var cell := MapGeom.cell_of(MapGeom.v2(d2.ouvertures[0].position))
	assert_eq(f2.at(cell), MapValidator.K.PORTE, "porte dans les cases du mur de la grille")
	assert_eq(f2.at(cell + Vector2i(1, 0)), MapValidator.K.SOL, "sol de la pièce sans grille derrière la porte")


## Deux pièces collées par un côté à 17° de la verticale (ni droit ni à 45°) :
## porte, fenêtres, départ, boîte.
static func slanted_map() -> EditorMap:
	var doc := EditorMap.blank("pente", "PENTE", "SLANT")
	var za := doc.add_zone("Ouest", "West")
	var zb := doc.add_zone("Est", "East")
	var p := Vector2(12, 3)
	var q := MapGeom.round_cm(MapGeom.polar(p, 12.0, -73.0))
	doc.pieces.append({"id": "p1", "nom": "Ouest", "altitude": 0, "zone": za.id, "contour": MapGeom.poly_arr(PackedVector2Array([Vector2(2, 3), p, q, Vector2(2, q.y)]))})
	doc.pieces.append({"id": "p2", "nom": "Est", "altitude": 0, "zone": zb.id, "contour": MapGeom.poly_arr(PackedVector2Array([p, Vector2(24, 3), Vector2(24, q.y), q]))})
	doc.depart = String(za.id)
	var r := MapRules.place_opening(doc, 0, "porte", (p + q) * 0.5, 2.0)
	doc.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": r.get("position", [0, 0]), "largeur": 2.0, "prix": 750})
	for pt in [Vector2(4, 2.7), Vector2(20, 2.7)]:
		var w := MapRules.place_opening(doc, 0, "fenetre", pt, 1.0)
		doc.ouvertures.append({"id": doc.new_id("o"), "type": "fenetre", "altitude": 0, "position": w.get("position", [0, 0])})
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": [5.0, 11.0]})
	var box := {"type": "boite", "depart": false}
	var res := MapRules.place_wall_item(doc, 0, box, Vector2(18, q.y - 0.6))
	box.merge({"id": "b1", "altitude": 0, "position": res.get("position", [0, 0])})
	MapRules.apply_wall(box, res)
	doc.objets.append(box)
	return MapTestKit.add_evac(doc)


func test_door_on_any_side() -> void:
	var doc := slanted_map()
	var door: Dictionary = doc.find("o1")
	assert_true(MapRules.check_existing(doc, door).ok, "porte sur le côté à 17°")
	var v := _check(doc)
	assert_true(v.ok(), "carte à côté de 17° jouable :\n" + _errs(v))
	assert_eq(v.doors.size(), 1)
	if not v.ok():
		return
	var L := MapLayoutExport.build(v)
	var d: Dictionary = L.markers.doors[0]
	var t := (MapGeom.polar(Vector2(12, 3), 12.0, -73.0) - Vector2(12, 3)).normalized()
	assert_near(absf(sin(float(d.yaw) - atan2(-t.y, t.x))), 0.0, 0.01, "porte tournée comme le mur (%.3f rad)" % float(d.yaw))
	var cut: Array = L.obliques.filter(func(o): return o.openings.any(func(cc): return absf(float(cc.w) - 2.0) < 0.01))
	assert_eq(cut.size(), 1, "porte découpée dans le mur oblique")


# ------------------------------------------------------------------ jeu : salle ronde

func test_round_room_geometry_and_collisions() -> void:
	var v := _check(round_map())
	assert_true(v.ok(), _errs(v))
	var L := MapLayoutExport.build(v)
	var arch := MeshMapGeometry.build(L)
	var world := Node3D.new()
	host.add_child(world)
	world.add_child(arch)
	# Rendu : les murs obliques sont fusionnés par matériau (un maillage chacun).
	var biais := arch.find_children("*__biais", "MeshInstance3D", false, false)
	assert_true(biais.size() >= 1 and biais.size() <= 4, "murs obliques fusionnés : %d maillage(s)" % biais.size())
	var boxes := arch.find_children("Biais_*", "CollisionBox", false, false)
	assert_true(boxes.size() >= 40, "collisions en CollisionBox tournées (%d)" % boxes.size())
	for bx in boxes:
		assert_false(bx.get_children().any(func(n): return n is MeshInstance3D), "collision sans maillage")
	# Sol : suit le vrai contour (jusqu'au pied du mur, sans trou).
	var floors := []
	for r in L.rooms:
		if String(r.id).begins_with("dehors"):
			continue
		var p := PackedVector2Array()
		for q in r.outline:
			p.append(Vector2(q[0], q[1]) - Vector2.ONE * MapGeom.WORLD_OFFSET)
		floors.append(p)
	var circle := MapShapes.outline(round_map().pieces[0].forme)
	var holes := []
	for i in 64:
		var dir := Vector2.from_angle(TAU * (i + 0.5) / 64.0)
		var q := Vector2(16, 16) + dir * (12.937 - MapGeom.WALL_HALF - 0.1)
		if MapGeom.contains(circle, q) and not floors.any(func(fp): return MapGeom.contains(fp, q) or MapGeom.on_boundary(fp, q, 0.002)):
			holes.append(q)
	assert_eq(holes.size(), 0, "sol continu jusqu'au pied du mur rond : %s" % str(holes))
	await wait_frames(2)
	await host.get_tree().physics_frame
	var off := MapGeom.WORLD_OFFSET
	var space := world.get_world_3d().direct_space_state
	# Rayon vers le sud : arrêté sur la face intérieure du côté sud (à plat).
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off + 16, 1.2, off + 16), Vector3(off + 16, 1.2, off + 32), 1))
	assert_true(not hit.is_empty() and hit.collider is CollisionBox, "mur rond : CollisionBox")
	if not hit.is_empty():
		assert_near(hit.position.z - off, 16.0 + 13.0 * cos(PI / 32.0) - MapGeom.WALL_HALF, 0.03, "sur la face du côté sud")
	# Vers le nord : le mur courbe (rayon 7 m) l'arrête d'abord.
	var hn := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off + 16, 1.2, off + 16), Vector3(off + 16, 1.2, off + 0.5), 1))
	assert_true(not hn.is_empty() and hn.position.z - off > 16.0 - 7.0 - 0.05 and hn.position.z - off < 16.0 - 6.5,
		"mur courbe : %s" % str(hn.get("position", "rien")))
	# Vers l'ouest à hauteur du pilier tourné de 30° : arrêté sur sa face.
	var hp := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off + 14, 1.2, off + 18), Vector3(off + 6, 1.2, off + 18), 1))
	assert_true(not hp.is_empty() and hp.collider is CollisionBox and absf(hp.position.x - off - (10.0 + 1.25 / cos(deg_to_rad(30.0)))) < 0.05,
		"pilier tourné : %s" % str(hp.get("position", "rien")))
	# Un corps poussé contre le mur rond reste dedans.
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.95
	body.add_child(cs)
	world.add_child(body)
	body.global_position = Vector3(off + 16, 0.05, off + 24)
	await host.get_tree().physics_frame
	for i in 80:
		body.move_and_collide(Vector3(-0.35, 0, 1).normalized() * 0.1)
	var e := Vector2(body.global_position.x, body.global_position.z) - Vector2.ONE * off
	assert_true(e.distance_to(Vector2(16, 16)) < 13.0 - MapGeom.WALL_HALF - 0.3, "le corps bute sur le mur rond (%.2f m du centre)" % e.distance_to(Vector2(16, 16)))
	world.queue_free()
	await wait_frames(1)


func test_round_room_navigation() -> void:
	var doc := round_map()
	var v := _check(doc)
	var L := MapLayoutExport.build(v)
	var world := Node3D.new()
	host.add_child(world)
	world.add_child(MeshMapGeometry.build(L))
	await host.get_tree().physics_frame
	var nav := MeshNav.new()
	nav.setup(world)
	nav.bake()
	for i in 20:
		await host.get_tree().process_frame
	NavigationServer3D.map_force_update(nav.map)
	var off := MapGeom.WORLD_OFFSET
	var pillar := MapRaster.rect_poly(doc.find("x1"))
	var arc := MapShapes.arc_segments(doc.find("m1"))
	var circle := doc.room_poly(doc.find("p1"))
	var crossings := []
	var check_path := func(path: PackedVector3Array) -> void:
		for i in path.size() - 1:
			var a := Vector2(path[i].x, path[i].z) - Vector2.ONE * off
			var b := Vector2(path[i + 1].x, path[i + 1].z) - Vector2.ONE * off
			for j in 4:
				if Geometry2D.segment_intersects_segment(a, b, pillar[j], pillar[(j + 1) % 4]) != null:
					crossings.append(["pilier", a, b])
			for s in arc:
				if Geometry2D.segment_intersects_segment(a, b, s[0], s[1]) != null:
					crossings.append(["mur courbe", a, b])
	# D'un côté du pilier tourné à l'autre : le chemin le contourne.
	var p1 := nav.find_path(Vector3(off + 13, 0, off + 18), Vector3(off + 7, 0, off + 18))
	assert_true(p1.size() >= 3, "chemin autour du pilier (%d points)" % p1.size())
	check_path.call(p1)
	# Du dedans du mur courbe au dehors : le chemin passe par un bout de l'arc.
	var p2 := nav.find_path(Vector3(off + 16, 0, off + 12), Vector3(off + 16, 0, off + 5))
	assert_true(p2.size() >= 3, "chemin autour du mur courbe (%d points)" % p2.size())
	check_path.call(p2)
	assert_eq(crossings, [], "aucun chemin ne traverse le pilier ni le mur courbe")
	var outside := Array(p1 + p2).filter(func(q): return not MapGeom.contains(circle, Vector2(q.x, q.z) - Vector2.ONE * off))
	assert_eq(outside.size(), 0, "chemins dans la salle ronde")
	# De la cour de la fenêtre à l'annexe : par la fenêtre, puis la porte.
	var wins: Array = L.markers.windows.filter(func(w): return w.zone == "a")
	if not wins.is_empty():
		var win: Dictionary = wins[0]
		var from := Vector3(win.p[0], win.p[1], win.p[2]) + Vector3(win["in"][0], 0, win["in"][2]) * 1.2
		var p3 := nav.find_path(from, Vector3(off + 32, 0, off + 16))
		assert_false(p3.is_empty(), "l'annexe est atteinte par la porte")
	assert_false(nav.world_line_clear(Vector3(off + 13, 0, off + 18), Vector3(off + 7, 0, off + 18)), "pas de ligne de vue à travers le pilier")
	nav.region.queue_free()
	world.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ escalier et piège tournés

static func stairs_map() -> EditorMap:
	var doc := EditorMap.blank("escalier", "ESCALIER", "STAIRS")
	var za := doc.add_zone("Bas", "Down")
	var zb := doc.add_zone("Haut", "Up")
	doc.pieces.append({"id": "p1", "nom": "Bas", "altitude": 0, "zone": za.id, "contour": [[0, 0], [20, 0], [20, 16], [0, 16]]})
	doc.pieces.append({"id": "p2", "nom": "Haut", "altitude": 1 * EditorMap.FLOOR_STEP, "zone": zb.id, "contour": [[0, 0], [20, 0], [20, 16], [0, 16]]})
	doc.depart = String(za.id)
	doc.objets.append({"id": "e1", "type": "escalier", "altitude": 0, "rect": [6.75, 4.5, 9.25, 11.5], "monte": "n", "rot": 30})
	for k in 2:
		for x in [3.0, 17.0]:
			var w := MapRules.place_opening(doc, k, "fenetre", Vector2(x, -0.3), 1.0)
			doc.ouvertures.append({"id": doc.new_id("o"), "type": "fenetre", "altitude": k * EditorMap.FLOOR_STEP, "position": w.get("position", [0, 0])})
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": [15.0, 13.0]})
	var box := {"type": "boite", "depart": false}
	var r := MapRules.place_wall_item(doc, 0, box, Vector2(14, 15.4))
	box.merge({"id": "b1", "altitude": 0, "position": r.get("position", [0, 0])})
	MapRules.apply_wall(box, r)
	doc.objets.append(box)
	doc.objets.append({"id": "t1", "type": "piege", "altitude": 0, "rect": [13.0, 5.0, 16.0, 9.0], "rot": 20})
	var lv := {"type": "levier"}
	var rl := MapRules.place_wall_item(doc, 0, lv, Vector2(19.4, 7.0))
	lv.merge({"id": "l1", "altitude": 0, "position": rl.get("position", [0, 0])})
	MapRules.apply_wall(lv, rl)
	doc.objets.append(lv)
	return MapTestKit.add_evac(doc)


func test_rotated_stairs_and_trap() -> void:
	var doc := stairs_map()
	assert_true(MapRules.check_existing(doc, doc.find("e1")).ok, "escalier tourné dans la pièce")
	var v := _check(doc)
	assert_true(v.ok(), "escalier tourné de 30° : jouable :\n" + _errs(v))
	assert_eq(v.stairs.size(), 1)
	if v.stairs.is_empty() or not v.ok():
		return
	var st: Dictionary = v.stairs[0]
	assert_true(st.has("diag") and st.lower == "a" and st.upper == "b", "escalier tourné du bas vers le haut : %s → %s" % [st.lower, st.upper])
	assert_true(v.zone_edges.any(func(e): return e.kind == "escalier"), "zones reliées par l'escalier")
	var L := MapLayoutExport.build(v)
	var s: Dictionary = L.stairs[0]
	var run := Vector2(float(s.b[0]) - float(s.a[0]), float(s.b[2]) - float(s.a[2]))
	var up := Vector2(0, -1).rotated(deg_to_rad(30.0))
	assert_near(run.normalized().dot(up), 1.0, 0.001, "monte dans le sens de l'escalier tourné")
	assert_near(run.length(), 6.5, 0.01, "longueur des marches (7 m - 2 × 0,25)")
	assert_near(float(s.w), 2.0, 0.01, "largeur des marches")
	assert_near(float(s.b[1]), 3.5, 0.001, "haut à l'étage du dessus")
	# Piège tourné : zone électrifiée tournée de 20°.
	var trap_marker: Dictionary = L.markers.traps[0]
	assert_true(trap_marker.has("yaw") and absf(float(trap_marker.yaw) + deg_to_rad(20.0)) < 0.001, "piège tourné : %s" % str(trap_marker.get("yaw", "?")))
	var trap := ElectricTrap.new()
	var m := MapMarker.new()
	m.id = "t"
	m.wall = Vector3(1, 0, 0)
	m.data = {"area": MeshMapLayout.box(trap_marker.area), "yaw": float(trap_marker.get("yaw", 0.0))}
	trap.setup_marker(m)
	var off := MapGeom.WORLD_OFFSET
	var cen := Vector3(off + 14.5, 0, off + 7)
	assert_true(trap.contains(cen + Basis(Vector3.UP, float(trap_marker.yaw)) * Vector3(1.2, 0, 1.7)), "coin de la zone tournée : électrifié")
	assert_false(trap.contains(cen + Basis(Vector3.UP, float(trap_marker.yaw)) * Vector3(1.2, 0, -1.9)), "hors de la zone tournée")
	assert_false(trap.contains(cen + Vector3(1.2, 0, -1.7)), "coin de la zone avant rotation : hors de la zone")
	trap.free()
	# Refus : escalier tourné trop étroit.
	var bad := stairs_map()
	bad.find("e1")["rect"] = [7.25, 4.5, 8.75, 11.5]
	assert_true(_errs(_check(bad)).contains("trop étroit"), "escalier tourné trop étroit refusé")


# ------------------------------------------------------------------ format 4

func test_format_4_round_trip_and_older_formats() -> void:
	var doc := round_map()
	doc.objets.append({"id": "d9", "type": "prefab", "prefab": "chaise", "altitude": 0, "position": [20.0, 21.0], "rot": 37})
	var t := doc.file_texts()
	# Format 5 (variantes, barrière) : les clés du format 4 sont écrites telles quelles.
	assert_true(EditorMap.FORMAT >= 4 and String(t["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT), "format courant (%d), au moins 4" % EditorMap.FORMAT)
	assert_true(String(t["pieces.json"]).contains("\"forme\":{") and String(t["pieces.json"]).contains("\"points\":32"), "forme de base enregistrée")
	assert_true(String(t["objets.json"]).contains("\"type\":\"mur_courbe\"") and String(t["objets.json"]).contains("\"rot\":30")
		and String(t["objets.json"]).contains("\"rot\":37"), "mur courbe et rotations enregistrés")
	var dir := ProjectSettings.globalize_path(TMP + "/ronde")
	assert_eq(doc.save_dir(dir), OK)
	var back := EditorMap.load_dir(dir)
	assert_true(back.load_errors.is_empty() and back.same_as(doc), "format 4 relu à l'identique")
	assert_true(_check(back).ok(), "toujours jouable")
	# Formats 1 à 3 lus tels quels.
	var diag: EditorMap = load("res://tests/test_map_editor_diagonal.gd").diag_map()
	for fmt in [2, 3]:
		var m := _with_format(diag, fmt)
		assert_true(m.load_errors.is_empty() and m.format_read == fmt and _check(m).ok(), "format %d lu et jouable" % fmt)
	var draft := EditorMap.load_dir("res://tests/fixtures/maps/legacy_draft_arena/")
	assert_eq(draft.format_read, 1, "DRAFT ARENA : format 1")
	var lang := Settings.language
	Settings.language = "fr"
	var vd := _check(draft)
	var sha := JSON.stringify(MapLayoutExport.build(vd), "", true).sha256_text()
	Settings.language = lang
	assert_true(vd.ok(), _errs(vd))
	assert_eq(sha, DRAFT_LAYOUT_SHA, "DRAFT ARENA construite octet pour octet comme avant")
	# Fichier écrit à la main : forme illisible ignorée, rotation arrondie au degré.
	var tx := doc.file_texts()
	tx["pieces.json"] = String(tx["pieces.json"]).replace("\"type\":\"cercle\"", "\"type\":\"etoile\"")
	tx["objets.json"] = String(tx["objets.json"]).replace("\"rot\":37", "\"rot\":37.6")
	var mx := EditorMap.from_texts(tx)
	assert_false(mx.find("p1").has("forme"), "forme inconnue retirée (la pièce reste un polygone)")
	assert_eq(int(mx.find("d9").rot), 38, "rotation au degré près")


func _with_format(m: EditorMap, fmt: int) -> EditorMap:
	var t := m.file_texts()
	t["carte.json"] = String(t["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": %d" % fmt)
	return EditorMap.from_texts(t)


# ------------------------------------------------------------------ contrôle des cartes reçues

func _refused(texts: Dictionary, what: String) -> void:
	var r := CustomMapGuard.check_texts(texts)
	assert_false(r.ok, "refus attendu : " + what)
	var reasons: Array = r.get("reasons", [])
	assert_true(not reasons.is_empty() and String(reasons[0][0]) != "" and String(reasons[0][1]) != "", "raison FR/EN : %s -> %s" % [what, str(reasons)])


func test_guard_free_shapes() -> void:
	CustomMapGuard.reset_schema()
	var m := round_map()
	var pk := CustomMapGuard.package_of(m)
	var chk := CustomMapGuard.check_package(pk.bytes, pk.sha)
	assert_true(chk.ok, "carte à formes libres acceptée : " + str(chk.get("reasons")))
	if chk.ok:
		assert_eq(CustomMapGuard.package_of(chk.map).sha, pk.sha, "même empreinte chez l'invité")
	var kinds := MapCatalog.allowed_kinds()
	assert_true(kinds.has("mur_courbe") and kinds.pilier.keys.has("rot") and kinds.escalier.keys.has("rot") and kinds.piege.keys.has("rot"), "types du format 4 admis")
	assert_eq(String(MapCatalog.room_keys().forme.t), "shape", "forme d'une pièce admise")
	var t := m.file_texts()
	var subs := [
		["\"points\":32", "\"points\":65", "65 points"], ["\"points\":32", "\"points\":2", "2 points"], ["\"points\":32", "\"points\":\"x\"", "points en texte"],
		["\"points\":32", "\"points\":32.5", "points non entiers"], ["\"type\":\"cercle\"", "\"type\":\"script\"", "type de forme inconnu"],
		["\"rx\":13", "\"rx\":1e999", "rayon infini"], ["\"rx\":13", "\"rx\":-3", "rayon négatif"], ["\"rx\":13", "\"rx\":13,\"code\":1", "clé inconnue dans la forme"],
		["\"angle\":0", "\"angle\":400", "angle 400"],
	]
	for s in subs:
		var tt := t.duplicate()
		tt["pieces.json"] = String(tt["pieces.json"]).replace(s[0], s[1])
		assert_true(String(tt["pieces.json"]).contains(s[1]), "remplacement %s" % s[2])
		_refused(tt, s[2])
	for bad in ["400", "-1", "45.5", "\"x\"", "1e999"]:
		var tt := t.duplicate()
		tt["objets.json"] = String(tt["objets.json"]).replace("\"rot\":30", "\"rot\":" + bad)
		assert_true(String(tt["objets.json"]).contains("\"rot\":" + bad), "remplacement rot %s" % bad)
		_refused(tt, "rotation %s" % bad)
	for s in [["\"segments\":8", "\"segments\":0"], ["\"segments\":8", "\"segments\":65"], ["\"ouverture\":100", "\"ouverture\":500"],
			["\"rayon\":7", "\"rayon\":1e999"]]:
		var tt := t.duplicate()
		tt["objets.json"] = String(tt["objets.json"]).replace(s[0], s[1])
		assert_true(String(tt["objets.json"]).contains(s[1]), "remplacement %s" % s[1])
		_refused(tt, "mur courbe %s" % s[1])
	# Format 17 : un arc qui passe en coordonnées négatives est admis.
	var neg := t.duplicate()
	neg["objets.json"] = String(neg["objets.json"]).replace("\"centre\":[16,16]", "\"centre\":[1,1]")
	assert_true(CustomMapGuard.check_texts(neg).ok, "mur courbe en partie en négatif accepté")
	# 64 points par pièce : accepté (la limite par pièce le permet).
	var big := round_map()
	var f64 := {"type": "cercle", "centre": [16.0, 16.0], "rx": 13.0, "points": 64, "angle": 0}
	big.pieces[0]["forme"] = f64
	big.pieces[0]["contour"] = MapGeom.poly_arr(MapShapes.outline(f64))
	var r64 := CustomMapGuard.check_texts(big.file_texts())
	assert_true(r64.ok, "cercle de 64 points accepté : %s" % str(r64.get("reasons")))
	assert_true(CustomMapGuard.MAX_VERTICES >= 64 and CustomMapGuard.MAX_TOTAL_VERTICES == 4096, "limites de sommets")
