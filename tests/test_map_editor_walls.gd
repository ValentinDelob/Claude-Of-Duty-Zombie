extends TestCase
## Murs libres et déplacements le long des murs dans l'éditeur de cartes
## (docs/MAP_AUTHORING.md, « Règles imposées à la pose ») : armes, atouts,
## appliques... posés sur un MUR LIBRE (outil Mur, droit ou en biais, épais, et
## mur courbe), des deux côtés, face vers le curseur, refusés sur un mur trop
## court, en chevauchement ou contre un mur de la pièce ; acceptés par la
## vérification et construits en jeu contre la bonne face ; accrochés au mur
## qui bouge. Fenêtres, portes et objets muraux posés puis déplacés le long de
## leur mur (droit, en biais, côté de cercle) et vers un autre mur, en grille
## 1 m, grille fine (0,5 / 0,25 / 0,1 m) et sans grille.

const TMP := "res://tests/_out/test_map_editor_walls"
const MODES := [["grille", 0.5], ["fine", 0.5], ["fine", 0.25], ["fine", 0.1], ["libre", 0.5]]


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


# ------------------------------------------------------------------ carte d'essai

## Une pièce de 20 × 14 m (départ, deux fenêtres, boîte) et des murs libres :
## m1 droit sur la grille, m2 en biais à 45°, m3 courbe (4 segments sur 180°),
## m4 droit de 1,5 m d'épaisseur, m5 collé au mur nord de la pièce.
static func free_walls_map() -> EditorMap:
	var doc := EditorMap.blank("murs_libres", "MURS LIBRES", "FREE WALLS")
	var z := doc.add_zone("Salle", "Hall")
	doc.pieces.append({"id": "p1", "nom": "Salle", "etage": 0, "zone": z.id, "contour": [[4, 4], [24, 4], [24, 18], [4, 18]]})
	doc.depart = String(z.id)
	for pt in [Vector2(9, 3.8), Vector2(21, 3.8)]:
		var w := MapRules.place_opening(doc, 0, "fenetre", pt, 1.0)
		doc.ouvertures.append({"id": doc.new_id("o"), "type": "fenetre", "etage": 0, "position": w.position})
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [15.0, 15.0]})
	doc.objets.append({"id": "m1", "type": "mur", "etage": 0, "a": [12, 6], "b": [12, 12], "epaisseur": 0.5})
	doc.objets.append({"id": "m2", "type": "mur", "etage": 0, "a": [16, 6], "b": [20, 10], "epaisseur": 0.5})
	doc.objets.append({"id": "m3", "type": "mur_courbe", "etage": 0, "centre": [8.0, 12.0], "rayon": 2.5, "debut": 0.0, "ouverture": 180.0,
		"segments": 4, "epaisseur": 0.5})
	doc.objets.append({"id": "m4", "type": "mur", "etage": 0, "a": [21, 11], "b": [21, 16], "epaisseur": 1.5})
	doc.objets.append({"id": "m5", "type": "mur", "etage": 0, "a": [6, 4], "b": [6, 8], "epaisseur": 0.5})
	var box := {"type": "boite", "depart": true}
	var r := MapRules.place_wall_item(doc, 0, box, Vector2(15, 17.4))
	box.merge({"id": "b1", "etage": 0, "position": r.position}, true)
	MapRules.apply_wall(box, r)
	doc.objets.append(box)
	return doc


const WEAPON := {"type": "arme", "arme": "m14"}
const PERK := {"type": "atout", "atout": "titan"}
const SCONCE := {"type": "luminaire", "luminaire": "applique", "couleur": "#ffc88a", "intensite": 1.4, "portee": 7, "courant": true, "vacille": false}


## Pose (règles de l'éditeur) puis ajoute l'objet à la carte ; sinon la raison du refus.
static func put(doc: EditorMap, tmpl: Dictionary, mouse: Vector2) -> Dictionary:
	var r := MapRules.place_wall_item(doc, 0, tmpl, mouse)
	if not r.ok:
		return r
	var o := tmpl.duplicate(true)
	o.merge({"id": doc.new_id("w"), "etage": 0, "position": r.position}, true)
	MapRules.apply_wall(o, r)
	doc.objets.append(o)
	return o


static func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


## Face (m, éditeur) de l'objet mural : 0,25 m devant son trait.
static func face_of(o: Dictionary) -> Vector2:
	return MapGeom.v2(o.position) - MapGeom.item_wall_dir(o) * MapGeom.WALL_HALF


# ------------------------------------------------------------------ pose sur un mur libre

func test_wall_items_on_a_straight_free_wall() -> void:
	var doc := free_walls_map()
	# Mur m1 (x = 12, de y = 6 à 12) : une arme de chaque côté, face vers le curseur.
	var west := put(doc, WEAPON, Vector2(11.4, 8.1))
	assert_true(west.has("id"), "arme à l'ouest du mur libre : %s" % str(west))
	if west.has("id"):
		assert_eq(String(west.mur), "e", "le mur est à l'est de l'arme")
		assert_false(west.has("angle"), "mur de la grille : pas d'angle")
		assert_near(MapGeom.v2(west.position).x, 12.0, 0.001, "sur le trait du mur")
		assert_near(MapGeom.v2(west.position).y, 8.25, 0.001, "aimantée sur la grille")
	var east := put(doc, WEAPON, Vector2(12.6, 8.1))
	assert_true(east.has("id"), "arme à l'est, dos à dos : %s" % str(east))
	if east.has("id"):
		assert_eq(String(east.mur), "o", "le mur est à l'ouest de l'arme")
	# Atout et applique, plus loin.
	var perk := put(doc, PERK, Vector2(12.9, 10.4))
	assert_true(perk.has("id") and String(perk.get("mur", "")) == "o", "atout contre le mur libre : %s" % str(perk))
	var sconce := put(doc, SCONCE, Vector2(11.7, 10.8))
	assert_true(sconce.has("id") and String(sconce.get("mur", "")) == "e", "applique contre le mur libre : %s" % str(sconce))
	# Au bout du mur : l'arme reste sur le mur (ses cases débordent de 0,25 m).
	var end_r := MapRules.place_wall_item(doc, 0, WEAPON, Vector2(11.5, 12.9))
	assert_true(end_r.ok and MapGeom.v2(end_r.position).y <= 11.75 + 0.001, "au bout : ramenée sur le mur (%s)" % str(end_r))
	# Chevauchement : même place qu'une arme posée.
	var again := MapRules.place_wall_item(doc, 0, WEAPON, Vector2(11.4, 8.1))
	assert_false(again.ok, "deux armes au même endroit refusées")
	assert_true(String(again.get("fr", "")).contains("chevauche"), "raison : %s" % again.get("fr", ""))
	# Mur trop court pour une boîte (0,5 m de trait, 1 m de cases).
	doc.objets.append({"id": "m6", "type": "mur", "etage": 0, "a": [15, 13], "b": [15, 13.5], "epaisseur": 0.5})
	var short := MapRules.place_wall_item(doc, 0, {"type": "boite", "depart": false}, Vector2(14.4, 13.2))
	assert_false(short.ok, "boîte sur un mur de 1 m : refusée")
	assert_true(String(short.get("fr", "")).contains("trop court"), "raison : %s" % short.get("fr", ""))
	var fits := MapRules.place_wall_item(doc, 0, WEAPON, Vector2(14.4, 13.2))
	assert_true(fits.ok, "arme de 1 m sur ce mur de 1 m : acceptée (%s)" % fits.get("fr", ""))


func test_wall_items_on_oblique_thick_and_curved_free_walls() -> void:
	var doc := free_walls_map()
	# Mur en biais m2 (45°) : des deux côtés, orientées selon le mur.
	var t := Vector2(1, 1).normalized()
	var n := Vector2(-t.y, t.x)
	var mid := Vector2(18, 8)
	for side in [1.0, -1.0]:
		var o := put(doc, WEAPON, mid + n * 0.7 * side)
		assert_true(o.has("id"), "arme de chaque côté du mur en biais (%s) : %s" % [side, str(o)])
		if o.has("id"):
			assert_true(MapGeom.item_oblique(o), "vrai mur oblique : angle %s" % str(o.get("angle")))
			assert_true(MapGeom.item_wall_dir(o).distance_to(-n * side) < 0.001, "face vers le curseur : %s" % MapGeom.item_wall_dir(o))
			assert_true(MapGeom.dist_to_segment(MapGeom.v2(o.position), Vector2(16, 6), Vector2(20, 10)) < 0.01, "sur le trait du mur en biais")
	var perk := put(doc, PERK, Vector2(16.4, 6.4) + n * 0.8)
	assert_true(perk.has("id"), "atout contre le mur en biais : %s" % str(perk))
	# Mur en biais trop court pour une arme.
	doc.objets.append({"id": "m7", "type": "mur", "etage": 0, "a": [18, 15], "b": [18.6, 15.6], "epaisseur": 0.5})
	var short := MapRules.place_wall_item(doc, 0, WEAPON, Vector2(18.3, 15.3) + n * 0.6)
	assert_false(short.ok, "mur en biais de 0,85 m : arme refusée")
	# Mur épais m4 (1,5 m, x = 21) : le trait est à 0,25 m derrière la face.
	var thick_w := put(doc, WEAPON, Vector2(19.8, 13.1))
	var thick_e := put(doc, WEAPON, Vector2(22.2, 13.1))
	assert_true(thick_w.has("id") and thick_e.has("id"), "armes des deux côtés du mur épais : %s / %s" % [str(thick_w), str(thick_e)])
	if thick_w.has("id") and thick_e.has("id"):
		assert_near(face_of(thick_w).x, 20.25, 0.001, "face ouest du mur de 1,5 m")
		assert_near(face_of(thick_e).x, 21.75, 0.001, "face est du mur de 1,5 m")
	# Mur courbe m3 : côté bombé (dehors) et côté creux (dedans).
	var c := Vector2(8, 12)
	var dir := MapGeom.deg_dir(67.5)
	var on_seg := c + dir * 2.5 * cos(deg_to_rad(22.5))
	var outside := put(doc, WEAPON, on_seg + dir * 0.6)
	assert_true(outside.has("id"), "arme sur le côté bombé du mur courbe : %s" % str(outside))
	var inside := put(doc, WEAPON, on_seg - dir * 0.6)
	assert_true(inside.has("id"), "arme dans le creux du mur courbe : %s" % str(inside))
	if outside.has("id") and inside.has("id"):
		assert_true(MapGeom.item_wall_dir(outside).dot(dir) < -0.99, "dehors : le mur est vers le centre")
		assert_true(MapGeom.item_wall_dir(inside).dot(dir) > 0.99, "dedans : le mur est vers l'extérieur")
	# Dans le creux : un atout de 1,5 m tient sur un segment de 1,9 m, une boîte de 2 m non.
	var perk_in := put(doc, {"type": "atout", "atout": "lazarus"}, c + MapGeom.deg_dir(112.5) * 1.7)
	assert_true(perk_in.has("id"), "atout dans le creux du mur courbe : %s" % str(perk_in))
	var box_in := MapRules.place_wall_item(doc, 0, {"type": "boite", "depart": false}, c + MapGeom.deg_dir(157.5) * 1.7)
	assert_false(box_in.ok, "boîte plus large que le segment : refusée")
	assert_true(String(box_in.get("fr", "")).contains("trop court"), "raison : %s" % box_in.get("fr", ""))
	# Mur collé au mur nord de la pièce (m5) : l'arme glisse hors du mur de la pièce.
	var corner := put(doc, WEAPON, Vector2(5.9, 4.4))
	assert_true(corner.has("id"), "arme près du raccord avec le mur de la pièce : %s" % str(corner))
	if corner.has("id"):
		assert_true(MapGeom.v2(corner.position).y >= 4.75 - 0.001, "à 0,25 m au moins de la face du mur nord : %s" % str(corner.position))
	# Applique contre ce mur, tout près du mur nord : elle reste valide sur sa face.
	var low := put(doc, SCONCE, Vector2(5.9, 4.3))
	assert_true(low.has("id") and String(low.get("mur", "")) == "e", "applique au raccord des deux murs : %s" % str(low))
	# Tout est accepté par la vérification.
	var v := MapRaster.build(doc).v
	v.analyze()
	assert_true(v.ok(), "carte avec des objets sur des murs libres :\n" + _errs(v))
	for o in doc.objets:
		if MapCatalog.tool_of(o) == "wall_item":
			assert_true(MapRules.check_existing(doc, o).ok, "%s toujours valide : %s" % [o.id, MapRules.check_existing(doc, o).get("fr", "")])


func test_free_wall_items_are_built_in_game() -> void:
	var doc := free_walls_map()
	var n := Vector2(-1, 1).normalized()
	var items := [put(doc, WEAPON, Vector2(11.4, 8.1)), put(doc, {"type": "arme", "arme": "mp5k"}, Vector2(12.6, 8.1)),
		put(doc, {"type": "arme", "arme": "olympia"}, Vector2(18, 8) + n * 0.7),
		put(doc, {"type": "arme", "arme": "stakeout"}, Vector2(18, 8) - n * 0.7),
		put(doc, PERK, Vector2(22.2, 13.1))]
	for o in items:
		assert_true(o.has("id"), "posé : %s" % str(o))
	var def := EditorMapDef.from_map(doc, "perso:murs")
	assert_true(def.is_valid(), "carte convertie :\n" + _errs(def.validator))
	var layout := def.create_layout()
	var markers := layout.wall_buys() + layout.perks()
	assert_eq(markers.size(), items.size(), "armes et atout construits")
	var off := MapGeom.WORLD_OFFSET
	for o in items:
		if not o.has("id"):
			continue
		var f := face_of(o)
		var dv := MapGeom.item_wall_dir(o)
		var found := false
		for mk: MapMarker in markers:
			var p := mk.on_wall(0.0, 0.0)
			if Vector2(p.x - off, p.z - off).distance_to(f) < 0.05:
				found = true
				assert_true(Vector2(mk.wall.x, mk.wall.z).distance_to(dv) < 0.01, "%s tourné vers la bonne face (mur %s, voulu %s)" % [o.id, mk.wall, dv])
				# Le joueur achète devant la face, du côté où l'objet a été posé.
				var front := Vector2(mk.pos.x - off, mk.pos.z - off)
				assert_true((front - f).dot(-dv) > 0.3, "%s : on l'achète du bon côté du mur" % o.id)
		assert_true(found, "%s construit contre sa face en %s" % [o.id, f])


func test_items_follow_their_free_wall() -> void:
	var ed := await _editor()
	ed.doc = free_walls_map()
	var west := put(ed.doc, WEAPON, Vector2(11.4, 8.1))
	var east := put(ed.doc, WEAPON, Vector2(12.6, 9.6))
	ed.changed()
	var att := ed.attached_to(ed.doc.find("m1"))
	assert_true(att.has(String(west.id)) and att.has(String(east.id)), "armes accrochées au mur libre : %s" % str(att))
	assert_false(att.has("b1"), "la boîte du mur de la pièce n'en fait pas partie")
	# Glisser le mur de 2 m vers l'est : les armes suivent, toujours valides.
	var cv := ed.canvas
	ed.select_slot(0)
	_drag(ed, Vector2(12, 11.2), Vector2(14, 11.2))
	assert_eq(MapGeom.v2(ed.doc.find("m1").a), Vector2(14, 6), "mur déplacé")
	assert_near(MapGeom.v2(ed.doc.find(String(west.id)).position).x, 14.0, 0.001, "l'arme suit son mur")
	assert_near(MapGeom.v2(ed.doc.find(String(east.id)).position).x, 14.0, 0.001, "l'arme de l'autre face aussi")
	# Sans grille : mur déplacé hors de la grille, armes raccrochées à sa face.
	cv.set_snap_mode("libre")
	_drag(ed, Vector2(14, 11.2), Vector2(14.37, 11.4))
	var mx := MapGeom.v2(ed.doc.find("m1").a).x
	assert_true(absf(mx - 14.37) < 0.02, "mur déplacé sans grille (%s)" % mx)
	for id in [String(west.id), String(east.id)]:
		var o := ed.doc.find(id)
		assert_near(MapGeom.v2(o.position).x, mx, 0.002, "%s sur la face du mur déplacé sans grille" % id)
		assert_true(MapRules.check_existing(ed.doc, o).ok, "%s toujours valide : %s" % [id, MapRules.check_existing(ed.doc, o).get("fr", "")])
	cv.set_snap_mode("grille")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ déplacements le long des murs

func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	ed.canvas.fine_step = 0.5
	ed.canvas.set_snap_mode("grille")
	ed.canvas.invert_snap = false
	ed.canvas.zoom = 22.0
	ed.canvas.origin = Vector2(50, 40)
	return ed


## Glisser à la souris (appui, mouvements, relâchement) de `from` à `to`.
func _drag(ed: MapEditor, from: Vector2, to: Vector2, steps := 10) -> void:
	for ev in _mouse_events(ed.canvas, from, to, steps):
		ed.canvas._gui_input(ev)


static func _mouse_events(cv: MapCanvas, from: Vector2, to: Vector2, steps: int) -> Array:
	var out := []
	var mv := InputEventMouseMotion.new()
	mv.position = cv.to_px(from)
	out.append(mv)
	var down := InputEventMouseButton.new()
	down.position = cv.to_px(from)
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	out.append(down)
	for i in steps:
		var m := InputEventMouseMotion.new()
		# Main pas tout à fait droite : le curseur s'écarte un peu du mur.
		var wobble := Vector2(0.03, -0.04) * sin(i * 1.7) if i < steps - 1 else Vector2.ZERO
		m.position = cv.to_px(from.lerp(to, (i + 1.0) / steps) + wobble)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		out.append(m)
	var up := InputEventMouseButton.new()
	up.position = cv.to_px(to)
	up.button_index = MOUSE_BUTTON_LEFT
	out.append(up)
	return out


## Pièces d'essai : [nom, carte, [points de pose des fenêtres]].
static func _maps() -> Array:
	var out := []
	var d1 := EditorMap.blank()
	d1.pieces.append({"id": "p1", "nom": "A", "etage": 0, "zone": "z1", "contour": [[2, 2], [12, 2], [12, 10], [2, 10]]})
	d1.pieces.append({"id": "p2", "nom": "B", "etage": 0, "zone": "z2", "contour": [[12, 4], [18, 4], [18, 8], [12, 8]]})
	out.append(["grille", d1, [Vector2(5, 1.8), Vector2(1.8, 6)]])
	var d2 := EditorMap.blank()
	d2.pieces.append({"id": "p1", "nom": "A", "etage": 0, "zone": "z1", "contour": [[2.25, 2.25], [8.25, 2.25], [8.25, 8.25], [2.25, 8.25]]})
	d2.pieces.append({"id": "p2", "nom": "B", "etage": 0, "zone": "z2", "contour": [[8.25, 2.25], [14.25, 2.25], [14.25, 8.25], [8.25, 8.25]]})
	out.append(["fine 0,25", d2, [Vector2(5, 2), Vector2(11, 8.5)]])
	var d3 := EditorMap.blank()
	d3.pieces.append({"id": "p1", "nom": "A", "etage": 0, "zone": "z1", "contour": [[2.37, 2.11], [12.84, 2.11], [12.84, 9.73], [2.37, 9.73]]})
	d3.pieces.append({"id": "p2", "nom": "B", "etage": 0, "zone": "z2", "contour": [[12.84, 3.52], [17.2, 3.52], [17.2, 7.9], [12.84, 7.9]]})
	out.append(["libre", d3, [Vector2(5, 2), Vector2(2.2, 6)]])
	var d4 := EditorMap.blank()
	d4.pieces.append({"id": "p1", "nom": "A", "etage": 0, "zone": "z1", "contour": [[2, 2], [12, 2], [12, 6], [8, 10], [2, 10]]})
	out.append(["biais", d4, [Vector2(10.5, 7.5), Vector2(5, 10.2)]])
	var d5 := EditorMap.blank()
	d5.pieces.append({"id": "p1", "nom": "A", "etage": 0, "zone": "z1", "contour": MapGeom.poly_arr(MapShapes.outline({"type": "cercle", "centre": [16.0, 16.0], "rx": 13.0, "points": 32, "angle": 0}))})
	out.append(["cercle", d5, [Vector2(16, 2.8), Vector2(6.6, 6.6)]])
	return out


## Direction du mur sous une ouverture posée (résultat de place_opening).
static func _along(r: Dictionary) -> Vector2:
	if r.has("dir"):
		return Vector2(r.dir[0], r.dir[1])
	return Vector2(1, 0) if r.horizontal else Vector2(0, 1)


func test_windows_move_along_their_wall_in_every_snap_mode() -> void:
	var ed := await _editor()
	var cv := ed.canvas
	for mp in _maps():
		var base: EditorMap = mp[1]
		for at in mp[2]:
			var r := MapRules.place_opening(base, 0, "fenetre", at, 1.0)
			assert_true(r.ok, "%s : fenêtre posée en %s (%s)" % [mp[0], at, r.get("fr", "")])
			if not r.ok:
				continue
			for mode in MODES:
				var doc := base.duplicate_map()
				doc.ouvertures.append({"id": "o9", "type": "fenetre", "etage": 0, "position": r.position})
				ed.doc = doc
				ed.changed()
				cv.fine_step = mode[1]
				cv.set_snap_mode(mode[0])
				ed.select_slot(0)
				var p0 := MapGeom.v2(r.position)
				var dl := 2.0 if MapRules.place_opening(doc, 0, "fenetre", p0 + _along(r) * 2.0, 1.0, "o9").ok else -2.0
				_drag(ed, p0 + Vector2(0.1, 0.1), p0 + _along(r) * dl + Vector2(0.1, 0.1))
				var p1 := MapGeom.v2(ed.doc.find("o9").position)
				assert_true(absf((p1 - p0).dot(_along(r)) - dl) < 0.55, "%s %s : fenêtre glissée de %s m le long du mur (%s -> %s) %s" % [mp[0], str(mode), dl, p0, p1, cv.refusal])
				assert_true(MapRules.check_existing(ed.doc, ed.doc.find("o9")).ok, "%s %s : toujours sur un mur extérieur" % [mp[0], str(mode)])
	ed.queue_free()
	await wait_frames(1)


func test_window_moves_to_another_outer_wall() -> void:
	var ed := await _editor()
	var cv := ed.canvas
	for mode in MODES:
		# Pièce de la grille puis pièce tracée sans grille : du mur nord au mur est.
		for geo in [[[2, 2], [13, 2], [13, 10], [2, 10]], [[2.26, 2.27], [12.73, 2.27], [12.73, 10.21], [2.26, 10.21]]]:
			var doc := EditorMap.blank()
			doc.pieces.append({"id": "p1", "nom": "A", "etage": 0, "zone": "z1", "contour": geo})
			var r := MapRules.place_opening(doc, 0, "fenetre", Vector2(8, 1.9), 1.0)
			doc.ouvertures.append({"id": "o9", "type": "fenetre", "etage": 0, "position": r.position})
			ed.doc = doc
			ed.changed()
			cv.fine_step = mode[1]
			cv.set_snap_mode(mode[0])
			ed.select_slot(0)
			var p0 := MapGeom.v2(r.position)
			var east := float(geo[1][0])
			_drag(ed, p0, Vector2(east + 0.2, 6.0), 16)
			var p1 := MapGeom.v2(ed.doc.find("o9").position)
			assert_near(p1.x, east, 0.01, "%s : fenêtre passée sur le mur est (%s)" % [str(mode), p1])
			assert_true(MapRules.check_existing(ed.doc, ed.doc.find("o9")).ok, "%s : fenêtre valide sur le mur est" % str(mode))
	ed.queue_free()
	await wait_frames(1)


func test_windows_placed_with_the_tool_in_every_snap_mode() -> void:
	var ed := await _editor()
	var cv := ed.canvas
	for mode in MODES:
		ed.new_map(true)
		cv.fine_step = mode[1]
		cv.set_snap_mode(mode[0])
		# Pièce rectangle tracée dans ce mode, fenêtre posée à l'outil, puis déplacée.
		ed.select_slot(1)
		_drag(ed, Vector2(2.26, 2.27), Vector2(12.73, 10.21))
		assert_eq(ed.doc.pieces.size(), 1, "%s : pièce tracée" % str(mode))
		ed.select_slot(5)
		for ev in _mouse_events(cv, Vector2(5.1, 2.1), Vector2(5.1, 2.1), 0):
			cv._gui_input(ev)
		var ws: Array = ed.doc.ouvertures.filter(func(o): return o.type == "fenetre")
		assert_eq(ws.size(), 1, "%s : fenêtre posée à l'outil (%s)" % [str(mode), cv.refusal])
		if ws.is_empty():
			continue
		ed.select_slot(0)
		var p0 := MapGeom.v2(ws[0].position)
		_drag(ed, p0 + Vector2(0.1, 0.1), p0 + Vector2(3.1, 0.2))
		var p1 := MapGeom.v2(ed.doc.find(String(ws[0].id)).position)
		assert_true(absf(p1.x - p0.x - 3.0) < 0.55 and absf(p1.y - p0.y) < 0.001, "%s : fenêtre déplacée le long du mur (%s -> %s)" % [str(mode), p0, p1])
		var v := MapRaster.build(ed.doc).v
		v.analyze()
		assert_eq(v.windows.size(), 1, "%s : la vérification voit la fenêtre déplacée" % str(mode))
	cv.set_snap_mode("grille")
	ed.queue_free()
	await wait_frames(1)


func test_doors_and_wall_items_move_in_every_snap_mode() -> void:
	var ed := await _editor()
	var cv := ed.canvas
	for mp in _maps():
		var base: EditorMap = mp[1]
		var tries := []
		for e in MapRules.shared_edges(base, 0):
			var t := (Vector2(e.b) - Vector2(e.a)).normalized()
			tries.append(["porte", (Vector2(e.a) + Vector2(e.b)) * 0.5, t])
			tries.append(["passage", (Vector2(e.a) + Vector2(e.b)) * 0.5, t])
		var poly := base.room_poly(base.pieces[0])
		var c := MapGeom.centroid(poly)
		var m := (poly[0] + poly[1]) * 0.5
		tries.append(["arme", m + (c - m).normalized() * 0.6, (poly[1] - poly[0]).normalized()])
		for tr in tries:
			var kind: String = tr[0]
			var doc0 := base.duplicate_map()
			if kind in ["porte", "passage"]:
				var r := MapRules.place_opening(doc0, 0, kind, tr[1], 1.5, "", true)
				assert_true(r.ok, "%s : %s posée" % [mp[0], kind])
				if not r.ok:
					continue
				doc0.ouvertures.append({"id": "o9", "type": kind, "etage": 0, "position": r.position, "largeur": float(r.get("largeur", 1.5)), "prix": 750})
			else:
				var o := put(doc0, WEAPON, tr[1])
				assert_true(o.has("id"), "%s : arme posée" % mp[0])
				if not o.has("id"):
					continue
				o["id"] = "o9"
			for mode in MODES:
				var doc := doc0.duplicate_map()
				ed.doc = doc
				ed.changed()
				cv.fine_step = mode[1]
				cv.set_snap_mode(mode[0])
				ed.select_slot(0)
				var o := doc.find("o9")
				var grab := MapGeom.v2(o.position) if kind != "arme" else MapRules.footprint_rect(o).get_center()
				var t: Vector2 = tr[2]
				var p0 := MapGeom.v2(o.position)
				var dl := 0.0
				for d in [1.5, -1.5, 1.0, -1.0]:
					var w := MapRules.place_opening(doc, 0, kind, p0 + t * d, float(o.get("largeur", 1.5)), "o9") if kind != "arme" \
						else MapRules.place_wall_item(doc, 0, o, grab + t * d, "o9")
					if w.ok and MapGeom.v2(w.position).distance_to(p0) > 0.7:
						dl = d
						break
				if dl == 0.0:
					continue
				_drag(ed, grab, grab + t * dl)
				var p1 := MapGeom.v2(ed.doc.find("o9").position)
				assert_true(p1.distance_to(p0) > 0.3, "%s %s %s : déplacé le long du mur (%s -> %s) %s" % [mp[0], kind, str(mode), p0, p1, cv.refusal])
	ed.queue_free()
	await wait_frames(1)


func test_wall_item_moves_along_a_free_wall_in_every_snap_mode() -> void:
	var ed := await _editor()
	var cv := ed.canvas
	for mode in MODES:
		ed.doc = free_walls_map()
		var o := put(ed.doc, WEAPON, Vector2(11.4, 7.1))
		ed.changed()
		cv.fine_step = mode[1]
		cv.set_snap_mode(mode[0])
		ed.select_slot(0)
		var grab := MapRules.footprint_rect(o).get_center()
		_drag(ed, grab, grab + Vector2(0, 3.0))
		var p1 := MapGeom.v2(ed.doc.find(String(o.id)).position)
		assert_true(absf(p1.x - 12.0) < 0.001 and p1.y > 9.4, "%s : arme glissée le long du mur libre (%s)" % [str(mode), p1])
		# Passée de l'autre côté du mur : elle se retourne.
		_drag(ed, MapRules.footprint_rect(ed.doc.find(String(o.id))).get_center(), Vector2(12.7, p1.y))
		assert_eq(String(ed.doc.find(String(o.id)).mur), "o", "%s : de l'autre côté, face à l'est" % str(mode))
	cv.set_snap_mode("grille")
	ed.queue_free()
	await wait_frames(1)


## Glisser LENT, comme une vraie souris : beaucoup de petits mouvements (pas
## de `step` m) de `from` à `to`, sans écart de la main.
func _slow_drag(ed: MapEditor, from: Vector2, to: Vector2, step: float) -> void:
	_drag(ed, from, to, maxi(1, roundi(from.distance_to(to) / step)))


func test_slow_drags_in_every_snap_mode() -> void:
	var ed := await _editor()
	var cv := ed.canvas
	var tried := 0
	for mp in _maps():
		var base: EditorMap = mp[1]
		# [type, point de pose, direction du mur]
		var tries := []
		for at in mp[2]:
			var r := MapRules.place_opening(base, 0, "fenetre", at, 1.0)
			if r.ok:
				tries.append(["fenetre", MapGeom.v2(r.position), _along(r)])
		for e in MapRules.shared_edges(base, 0):
			var t := (Vector2(e.b) - Vector2(e.a)).normalized()
			for kind in ["porte", "debris", "passage"]:
				tries.append([kind, (Vector2(e.a) + Vector2(e.b)) * 0.5, t])
		var poly := base.room_poly(base.pieces[0])
		var c := MapGeom.centroid(poly)
		var m := (poly[0] + poly[1]) * 0.5
		tries.append(["arme", m + (c - m).normalized() * 0.6, (poly[1] - poly[0]).normalized()])
		for tr in tries:
			var kind: String = tr[0]
			var doc0 := base.duplicate_map()
			if kind == "arme":
				var o := put(doc0, WEAPON, tr[1])
				if not o.has("id"):
					continue
				o["id"] = "o9"
			else:
				var r := MapRules.place_opening(doc0, 0, kind, tr[1], 1.0 if kind == "fenetre" else 1.5, "", true)
				if not r.ok:
					continue
				var op := {"id": "o9", "type": kind, "etage": 0, "position": r.position}
				if kind != "fenetre":
					op["largeur"] = float(r.get("largeur", 1.5))
				doc0.ouvertures.append(op)
			var o0 := doc0.find("o9")
			var p0 := MapGeom.v2(o0.position)
			var grab := p0 if kind != "arme" else MapRules.footprint_rect(o0).get_center()
			var t: Vector2 = tr[2]
			# Le plus long glissement possible le long du mur (jusqu'à 3 m), dans un sens ou l'autre.
			var dl := 0.0
			for d in [3.0, -3.0, 2.0, -2.0, 1.5, -1.5, 1.0, -1.0]:
				var w := MapRules.place_wall_item(doc0, 0, o0, grab + t * d, "o9") if kind == "arme" \
					else MapRules.place_opening(doc0, 0, kind, p0 + t * d, MapRules.opening_width(o0), "o9")
				if w.ok and absf((MapGeom.v2(w.position) - p0).dot(t) - d) < 0.3:
					dl = d
					break
			if dl == 0.0:
				continue
			for mode in MODES:
				for step in [0.02, 0.08]:
					ed.doc = doc0.duplicate_map()
					ed.changed()
					cv.fine_step = mode[1]
					cv.set_snap_mode(mode[0])
					ed.select_slot(0)
					_slow_drag(ed, grab + Vector2(0.04, 0.03), grab + t * dl + Vector2(0.04, 0.03), step)
					var p1 := MapGeom.v2(ed.doc.find("o9").position)
					tried += 1
					assert_true(absf((p1 - p0).dot(t) - dl) < 0.55, "%s %s %s pas de %s m : glissé de %s m (%s -> %s) %s" % [
						mp[0], kind, str(mode), step, dl, p0, p1, cv.refusal])
	assert_true(tried > 100, "glissements lents essayés : %d" % tried)
	ed.queue_free()
	await wait_frames(1)
