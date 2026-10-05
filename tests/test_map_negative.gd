extends TestCase
## Format 17, étape 3 de docs/LEVELS_PLAN.md : coordonnées négatives et aucune
## borne de conception. Une carte M et sa copie M' translatée de (−37,5 ;
## −12,5) donnent les mêmes messages du validateur (positions écrites dans le
## repère de l'éditeur), le même export en jeu, un monde >= 0 ; les règles de
## pose et la garde des cartes reçues acceptent les négatifs ; seule la
## mémoire de la grille du validateur refuse (proprement) une carte démesurée ;
## les consommateurs de l'éditeur (plafond réel, élévations, aperçu 3D)
## retirent le décalage.

const REF := preload("res://tests/test_levels_reference.gd")
const T := Vector2(-37.5, -12.5)
## Cases de la translation T (0,5 m).
const TC := Vector2i(-75, -25)


# ------------------------------------------------------------------ outils

## Copie de `doc` déplacée de `delta` (comme un déplacement de l'éditeur).
static func moved(doc: EditorMap, delta: Vector2) -> EditorMap:
	var m := doc.duplicate_map()
	for list in [m.pieces, m.ouvertures, m.objets]:
		for i in list.size():
			list[i] = MapTransform.shifted(list[i], delta)
	return m


## Copie de `doc` posée contre l'origine : son coin bas à moins de 0,5 m de
## (0, 0) (translation d'un multiple de 0,5 m).
static func at_origin(doc: EditorMap) -> EditorMap:
	var bb := MapRaster.extent(doc)
	var d := -Vector2(floorf(bb.position.x / 0.5) * 0.5, floorf(bb.position.y / 0.5) * 0.5)
	return moved(doc, d)


## Messages du validateur sans leurs positions écrites : [niveau, étage, texte].
static func msg_keys(v: MapValidator) -> Array:
	var re := RegEx.create_from_string("\\(x [^()]*\\)")
	var out := []
	for m in v.messages:
		out.append([String(m.level), int(m.get("floor", -1)), re.sub(String(m.fr), "(x …)", true)])
	return out


## Coordonnées monde négatives d'une description en jeu (boîtes, points,
## contours), au plus 5 : [chemin…].
static func negatives(d: Variant, path := "", out: Array = []) -> Array:
	if out.size() >= 5:
		return out
	if d is Dictionary:
		for k in d:
			var v: Variant = d[k]
			var key := String(k)
			if key == "box" and v is Array and v.size() == 6:
				for i in [0, 2, 3, 5]:
					if float(v[i]) < -0.001:
						out.append("%s/box[%d] = %s" % [path, i, str(v[i])])
			elif key in ["p", "fixture_p"] and v is Array and v.size() == 3 and (v[0] is float or v[0] is int):
				if float(v[0]) < -0.001 or float(v[2]) < -0.001:
					out.append("%s/%s = %s" % [path, key, str(v)])
			elif key in ["outline", "path", "poly", "a", "b"] and v is Array:
				var pts: Array = v if (v.size() > 0 and v[0] is Array) else [v]
				for q in pts:
					if q is Array and q.size() == 2 and (q[0] is float or q[0] is int) and (float(q[0]) < -0.001 or float(q[1]) < -0.001):
						out.append("%s/%s : %s" % [path, key, str(q)])
						break
			else:
				negatives(v, "%s/%s" % [path, key], out)
	elif d is Array:
		for i in d.size():
			negatives(d[i], "%s[%d]" % [path, i], out)
	return out


static func _room(id: String, zone: String, x0: float, y0: float, x1: float, y1: float, alt := 0.0) -> Dictionary:
	return {"id": id, "nom": id, "altitude": alt, "zone": zone, "contour": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]}


## Deux salles collées, une porte, deux fenêtres, départ, boîte, arme, atout
## (comme tests/test_map_preview.gd), toutes en coordonnées négatives.
static func negative_base() -> EditorMap:
	var doc := EditorMap.blank("negatif", "NÉGATIF", "NEGATIVE")
	var za := doc.add_zone("Salle A", "Room A")
	var zb := doc.add_zone("Salle B", "Room B")
	doc.pieces.append(_room("pa", String(za.id), 0, 0, 14, 10))
	doc.pieces.append(_room("pb", String(zb.id), 14, 0, 24, 10))
	doc.depart = String(za.id)
	for o in [{"id": "o1", "type": "porte", "position": [14.0, 5.25], "largeur": 2.0, "prix": 750},
			{"id": "o2", "type": "fenetre", "position": [3.25, 0.0]}, {"id": "o3", "type": "fenetre", "position": [19.25, 0.0]}]:
		o["altitude"] = 0.0
		doc.ouvertures.append(o)
	for o in [{"id": "x1", "type": "depart", "position": [9.0, 7.0]}, {"id": "x2", "type": "boite", "position": [6.75, 10.0], "mur": "s", "depart": false},
			{"id": "x3", "type": "arme", "arme": "m14", "position": [11.25, 10.0], "mur": "s"}, {"id": "x4", "type": "atout", "atout": "titan", "position": [24.0, 5.0], "mur": "e"},
			{"id": "d1", "type": "prefab", "prefab": "caisses", "position": [19.0, 5.0]}]:
		o["altitude"] = 0.0
		doc.objets.append(o)
	return moved(doc, Vector2(-30.0, -20.0))


# ------------------------------------------------------------------ invariance par translation

func test_translation_invariance_on_reference_maps() -> void:
	var names: Array = REF.names()
	assert_true(names.size() >= 16, "cartes de référence (%d)" % names.size())
	for name in names:
		var m0 := at_origin(REF.legacy_map(name))
		var m1 := moved(m0, T)
		var v0 := MapRaster.build(m0).v
		var v1 := MapRaster.build(m1).v
		assert_eq(v0.shift, Vector2.ZERO, "%s : carte >= 0, aucun décalage" % name)
		assert_eq(v1.shift, -T, "%s : décalage de la copie (37,5 ; 12,5)" % name)
		v0.analyze()
		v1.analyze()
		assert_eq(msg_keys(v1), msg_keys(v0), "%s : mêmes messages du validateur" % name)
		for i in mini(v0.messages.size(), v1.messages.size()):
			var c0: Array = v0.cells_ed(v0.messages[i].get("cells", []))
			var c1: Array = v1.cells_ed(v1.messages[i].get("cells", []))
			assert_eq(c1, c0.map(func(c: Vector2i) -> Vector2i: return c + TC), "%s : cases du message %d dans le repère de l'éditeur" % [name, i])
		var e0: Variant = JSON.parse_string(JSON.stringify(MapPreviewWorld.compute(m0).data))
		var e1: Variant = JSON.parse_string(JSON.stringify(MapPreviewWorld.compute(m1).data))
		var d: Array = REF.diff(e0, e1)
		assert_true(d.is_empty(), "%s : export identique\n%s" % [name, "\n".join(d.slice(0, 12))])
		var neg := negatives(e1)
		assert_true(neg.is_empty(), "%s : monde >= 0 (%s)" % [name, ", ".join(neg)])


func test_positive_map_export_unchanged() -> void:
	# Une carte >= 0 n'est jamais décalée : son export reste celui du format 16
	# (références de tests/test_levels_reference.gd, contrôlées là-bas) ; ici,
	# le décalage est nul même pour une carte qui touche l'origine.
	var m := REF.legacy_map("smallest")
	assert_eq(MapRaster.build(m).v.shift, Vector2.ZERO)
	assert_eq(MapRaster.shift_for(Rect2(0, 0, 10, 10)), Vector2.ZERO)
	assert_eq(MapRaster.shift_for(Rect2(-0.0005, 3, 10, 10)), Vector2.ZERO, "tolérance d'un millimètre")
	assert_eq(MapRaster.shift_for(Rect2(-0.2, -37.5, 10, 10)), Vector2(0.5, 37.5), "multiple de 0,5 m au-dessus")
	assert_eq(MapRaster.shift_for(Rect2(-3.75, -0.5, 10, 10)), Vector2(4.0, 0.5))


func test_messages_and_helpers_in_editor_frame() -> void:
	var doc := negative_base()
	var v := MapRaster.build(doc).v
	assert_eq(v.shift, Vector2(30.0, 20.0), "décalage de la carte (−30 ; −20)")
	assert_eq(v.shift_cells(), Vector2i(60, 40))
	# Aller-retour éditeur <-> grille.
	var p := Vector2(-21.3, -14.8)
	var g := v.to_grid(p)
	assert_eq(g, MapVertical.cell(p + v.shift))
	assert_eq(v.grid_cell(v.cell_ed(g)), g)
	assert_eq(v.cell_ed(Vector2i(60, 40)), Vector2i.ZERO, "case de l'origine")
	assert_eq(v.point_ed(Vector2(30.0, 20.0)), Vector2.ZERO)
	# Position écrite d'une case : en mètres de l'éditeur (négatifs).
	var at: Array = v._at(0, v.grid_cell(Vector2i(-10, -4)))
	assert_true(String(at[1]).contains("x -5 m") and String(at[1]).contains("y -2 m"), "position écrite : %s" % at[1])
	v.analyze()
	assert_true(v.ok(), "carte négative jouable :\n%s" % "\n".join(v.errors().map(func(m): return String(m.fr))))
	assert_false(v.messages.any(func(m): return String(m.fr).contains("hors du terrain")), "plus d'erreur « hors du terrain »")


func test_editor_consumers_remove_the_shift() -> void:
	var doc := negative_base()
	var pos := at_origin(doc)
	var d := MapRaster.extent(pos).position - MapRaster.extent(doc).position
	var vn := MapRaster.build(doc).v
	var vp := MapRaster.build(pos).v
	var room_n: Dictionary = doc.find("pb")
	var room_p: Dictionary = pos.find("pb")
	for q in [Vector2(-10.0, -15.0), Vector2(-2.0, -12.0), Vector2(-15.9, -19.9)]:
		assert_near(MapVertical.ceil_z(vn, 0, q), MapVertical.ceil_z(vp, 0, q + d), 0.0001, "plafond réel en %s" % q)
	assert_near(MapElevationItems.room_top(doc, vn, room_n), MapElevationItems.room_top(pos, vp, room_p), 0.0001, "haut de la pièce (élévations)")
	var crate_n: Dictionary = doc.find("d1")
	var crate_p: Dictionary = pos.find("d1")
	assert_near(MapVertical.room_h(vn, crate_n), MapVertical.room_h(vp, crate_p), 0.0001, "hauteur sous plafond d'un décor")
	assert_eq(MapVertical.pose_bounds(vn, crate_n), MapVertical.pose_bounds(vp, crate_p), "bornes de la hauteur de pose")


# ------------------------------------------------------------------ règles de pose et garde

func test_rules_accept_negative_coordinates() -> void:
	var doc := negative_base()
	var poly := PackedVector2Array([Vector2(-60, -40), Vector2(-50, -40), Vector2(-50, -32), Vector2(-60, -32)])
	var r := MapRules.check_room(doc, 0, poly)
	assert_true(r.ok, "pièce en négatif : %s" % MapRules.why(r))
	r = MapRules.check_clip(PackedVector2Array([Vector2(-5, -5), Vector2(-2, -5), Vector2(-2, -1)]))
	assert_true(r.ok, "barrière invisible en négatif : %s" % MapRules.why(r))
	r = MapRules.check_wall(Vector2(-8, -3), Vector2(-2, -3))
	assert_true(r.ok, "mur libre en négatif : %s" % MapRules.why(r))
	r = MapRules.check_arc({"type": "mur_courbe", "centre": [-20.0, -20.0], "rayon": 4.0, "ouverture": 180.0, "debut": 0.0})
	assert_true(r.ok, "mur courbe en négatif : %s" % MapRules.why(r))
	# Pose réelle dans la carte : chaque élément existant reste valide.
	for o in doc.ouvertures + doc.objets:
		var c := MapRules.check_existing(doc, o)
		assert_true(c.ok, "%s valide : %s" % [o.id, MapRules.why(c)])


func test_guard_accepts_negative_maps() -> void:
	var doc := negative_base()
	var texts := doc.file_texts()
	var r := CustomMapGuard.check_texts(texts)
	assert_eq(r.reasons, [], "carte négative reçue : acceptée")
	assert_true(bool(CustomMapGuard.check_full(texts).get("ok", false)), "et jouable")
	# Relue telle quelle : coordonnées gardées.
	var back := EditorMap.from_texts(texts)
	assert_eq(back.find("pa").contour[0], doc.find("pa").contour[0], "contour négatif relu")


func test_huge_or_high_maps_accepted_or_refused_by_memory() -> void:
	# Très haute : deux niveaux à 0 et 1 200 m, une salle chacun, et loin en
	# négatif : acceptée (aucune borne d'altitude ni d'étendue).
	var doc := negative_base()
	var z := doc.add_zone("Haut", "Up")
	doc.pieces.append(_room("ph", String(z.id), -400, -300, -390, -292, 1200.0))
	var v := MapRaster.build(doc).v
	assert_eq(v.floors.size(), 2, "deux niveaux")
	assert_near(v.floors[1].sol, 1200.0, 0.001, "niveau à 1 200 m")
	assert_false(v.messages.any(func(m): return String(m.fr).contains("mémoire")), "grille raisonnable")
	assert_true(CustomMapGuard.grid_ok(CustomMapGuard.grid_bytes(doc.pieces)), "garde : admise")
	# Démesurée : un décor à 5 000 km -> refus expliqué (jamais un plantage),
	# par l'éditeur (validateur) comme par la garde des cartes reçues.
	var far := negative_base()
	far.objets.append({"id": "loin", "type": "prefab", "prefab": "caisses", "altitude": 0.0, "position": [-5.0e6, 3.0]})
	var vf := MapRaster.build(far).v
	assert_true(vf.errors().any(func(m): return String(m.fr).contains("mémoire")), "validateur : refus par la mémoire")
	vf.analyze()
	assert_false(vf.ok(), "carte démesurée injouable")
	var rf := CustomMapGuard.check_texts(far.file_texts())
	assert_false(rf.ok, "garde : refusée")
	assert_true(CustomMapGuard.reasons_text(rf.reasons).contains("validat"), "raison : %s" % CustomMapGuard.reasons_text(rf.reasons))
	# Pièce de 4 km de côté : refusée à la pose, avec la raison.
	var big := PackedVector2Array([Vector2(-2000, -2000), Vector2(2000, -2000), Vector2(2000, 2000), Vector2(-2000, 2000)])
	var rr := MapRules.check_room(doc, 0, big)
	assert_false(rr.ok, "pièce démesurée refusée")
	assert_true(MapRules.why(rr).contains("mémoire") or MapRules.why(rr).contains("memory"), "raison : %s" % MapRules.why(rr))
	# Nombres absurdes : bornés, sans débordement.
	assert_false(CustomMapGuard.grid_ok(CustomMapGuard.extent_bytes(Vector2(1e30, 1e30), 1)))
	assert_false(CustomMapGuard.grid_ok(CustomMapGuard.extent_bytes(Vector2(INF, 3), 1)))


# ------------------------------------------------------------------ aperçu 3D

func test_preview_pick_on_negative_map() -> void:
	var doc := negative_base()
	var w := MapPreviewWorld.new()
	host.add_child(w)
	w.doc = doc
	w.auto = false
	w.rebuild_now()
	await wait_frames(2)
	assert_eq(Vector2(w.ox, w.oz), Vector2.ONE * MapGeom.WORLD_OFFSET + Vector2(30.0, 20.0), "repère du monde construit")
	var c := MapGeom.v2(doc.find("d1").position)
	assert_eq(w.to_map(w.to_world(c, 1.0)), c, "aller-retour éditeur <-> monde")
	w.set_options({"ceil": true})
	var rig := w.rig
	rig.yaw = 0.0
	rig.pitch = -1.5
	rig.dist = 15.0
	var center := Vector2(w.viewport.size) * 0.5
	rig.pivot = w.to_world(c)
	rig._apply()
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	assert_eq(w.pick(center), "d1", "clic sur le décor d'une carte négative")
	rig.pivot = w.to_world(Vector2(-10.0, -12.0))
	rig._apply()
	await host.get_tree().physics_frame
	assert_eq(w.pick(center), "pb", "clic sur le sol de la salle B")
	w.queue_free()
	await wait_frames(2)
