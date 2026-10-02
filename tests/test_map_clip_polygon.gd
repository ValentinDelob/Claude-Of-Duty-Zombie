extends TestCase
## Format 9 de l'éditeur de cartes (docs/MAP_OBJECTS.md § 2 et § 10) :
## barrière invisible tracée en POLYGONE, posée n'importe où (dehors, à
## cheval sur un mur, par-dessus un objet), sommets déplaçables, déplacée,
## tournée, supprimée, annulée ; barrière rectangle d'avant relue comme un
## polygone ; prisme de collision en jeu (CollisionBox, morceaux convexes d'un
## polygone concave, hauteur réglable au dixième de mètre) ; aperçu 3D ;
## contrôle des cartes reçues. Réglage de la carte « chevauchement_decor » :
## décor et obstacles qui se chevauchent, objets de jeu toujours protégés.

const TMP := "res://tests/_out/test_map_clip_polygon"
const OFF := MapGeom.WORLD_OFFSET
const ObjectsTest := preload("res://tests/test_map_objects.gd")
## Barrière en L (concave) dans la salle A : bras nord 2..6 × 2..3, bras ouest 2..3 × 2..6.
const L_SHAPE := [[2, 2], [6, 2], [6, 3], [3, 3], [3, 6], [2, 6]]


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


static func _map() -> EditorMap:
	return ObjectsTest.objects_map()


static func _clip(doc: EditorMap, pts: Array, extra := {}) -> Dictionary:
	var o := {"id": doc.new_id("i"), "type": "bloc_invisible", "etage": 0, "sommets": pts}
	o.merge(extra)
	doc.objets.append(o)
	return o


static func _poly(pts: Array) -> PackedVector2Array:
	return MapGeom.poly(pts)


# ------------------------------------------------------------------ règles de pose

func test_barrier_goes_anywhere_with_sane_outline_rules() -> void:
	var doc := _map()
	var ok_cases := [
		["dans une pièce, en L (concave)", L_SHAPE],
		["dehors, hors de toute pièce", [[30, 2], [33, 2], [33, 4]]],
		["à cheval sur le mur sud de la salle B", [[20, 8], [23, 8], [23, 12], [20, 12]]],
		["par-dessus la boîte et l'atout", [[22.5, 3], [24.6, 3], [24.6, 7], [22.5, 7]]],
		["fine : 0,2 m d'épaisseur", [[5, 8], [8, 8], [8, 8.2], [5, 8.2]]],
	]
	for c in ok_cases:
		var r := MapRules.check_clip(_poly(c[1]))
		assert_true(r.ok, "%s : accepté (%s)" % [c[0], MapRules.why(r)])
	var bad_cases := [
		["deux sommets", [[1, 1], [3, 1]]],
		["côtés qui se croisent (nœud papillon)", [[1, 1], [3, 3], [3, 1], [1, 3]]],
		["x négatif", [[-1, 1], [2, 1], [2, 3]]],
		["minuscule (0,1 × 0,1 m)", [[1, 1], [1.1, 1], [1.1, 1.1], [1, 1.1]]],
		["côté de 1 cm", [[1, 1], [3, 1], [3, 3], [3.01, 3]]],
		["plat (trois points alignés)", [[1, 1], [2, 1], [3, 1]]],
	]
	for c in bad_cases:
		assert_false(MapRules.check_clip(_poly(c[1])).ok, "%s : refusé" % c[0])
	var many := []
	for i in 65:
		many.append([10 + 3 * cos(TAU * i / 65.0), 10 + 3 * sin(TAU * i / 65.0)])
	assert_false(MapRules.check_clip(_poly(many)).ok, "65 sommets : refusé (64 au plus)")
	# Posée sur des objets : aucun ne devient invalide, elle non plus ; un
	# objet posé ensuite sur elle n'est pas gêné.
	var over := _clip(doc, [[8, 6], [10, 6], [10, 8], [8, 8]])   # sur le départ s1 (9, 7)
	assert_true(MapRules.check_existing(doc, over).ok, "barrière sur le départ : valide")
	assert_true(MapRules.check_existing(doc, doc.find("s1")).ok, "départ sous la barrière : toujours valide")
	var crate := {"type": "caisse", "position": [9.0, 6.5]}
	var on_clip := MapRules.place_floor_item(doc, 0, crate, Vector2(8.5, 6.0), "", false)
	assert_true(on_clip.ok, "caisse posée sur une barrière : %s" % MapRules.why(on_clip))
	var v := ObjectsTest._check(doc)
	assert_false(v.errors().any(func(m): return String(m.fr).contains("chevauche")), "validateur : pas de chevauchement signalé\n" + "\n".join(v.errors().map(func(m): return String(m.fr))))


# ------------------------------------------------------------------ fichiers

func test_old_rect_barriers_become_polygons_and_round_trip() -> void:
	var doc := _map()
	doc.objets[-1]["rot"] = 30
	var texts := doc.file_texts()
	assert_true(String(texts["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT), "écrite au format %d" % EditorMap.FORMAT)
	assert_true(EditorMap.FORMAT >= 9, "format 9 : barrière en polygone")
	# Même carte relue au format 8 (barrière rectangle d'avant).
	texts["carte.json"] = String(texts["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 8")
	var m := EditorMap.from_texts(texts)
	assert_eq(m.load_errors, [], "format 8 lu sans erreur")
	assert_eq(m.format_read, 8)
	var cl := m.find("i1")
	assert_true(cl.has("sommets") and not cl.has("rect") and not cl.has("rot"), "rectangle -> polygone de 4 sommets")
	assert_true(MapRaster.clip_poly(cl).size() == 4 and absf(MapGeom.area(MapRaster.clip_poly(cl)) - 5.0) < 0.01, "même surface (5 m²)")
	var t2 := m.file_texts()
	assert_true(String(t2["objets.json"]).contains("\"sommets\":"), "écrite avec ses sommets")
	assert_eq(EditorMap.from_texts(t2).file_texts(), t2, "relue puis réécrite à l'identique")
	assert_eq(CustomMapGuard.check_texts(t2).reasons, [], "contrôle des cartes reçues : polygone accepté")
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "et le rectangle d'avant aussi")
	# Même collision et mêmes cases en jeu : la carte d'avant (rectangle droit)
	# et la carte relue (polygone).
	var d0 := _map()
	var t0 := d0.file_texts()
	t0["carte.json"] = String(t0["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 8")
	var m0 := EditorMap.from_texts(t0)
	assert_eq(MapRaster.clip_cells(m0.find("i1")), MapRaster.clip_cells(d0.find("i1")), "mêmes cases pour le validateur")
	var a: Array = EditorMapDef.from_map(d0, "perso:a").layout_data.blockers.filter(func(x): return x.get("clip", false))
	var b: Array = EditorMapDef.from_map(m0, "perso:b").layout_data.blockers.filter(func(x): return x.get("clip", false))
	assert_eq(a.size(), 1)
	assert_eq(b.size(), 1)
	if a.size() == 1 and b.size() == 1:
		for i in 3:
			assert_near(float(a[0].center[i]), float(b[0].center[i]), 0.01, "centre %d" % i)
		assert_eq((a[0].poly as Array).size(), 4, "4 sommets décrits")
	# Hauteur illisible ou trop basse : jusqu'au plafond ; trop haute : bornée.
	for hv in [["\"x\"", false], ["0.2", false], ["100", true]]:
		var hand := t2.duplicate()
		hand["objets.json"] = String(hand["objets.json"]).replace("\"type\":\"bloc_invisible\"", "\"type\":\"bloc_invisible\",\"hauteur\":%s" % hv[0])
		var hm := EditorMap.from_texts(hand).find("i1")
		assert_eq(hm.has("hauteur"), hv[1], "hauteur %s" % hv[0])
		if hv[1]:
			assert_near(float(hm.hauteur), MapCatalog.CLIP_HEIGHT[1], 0.001, "bornée à 30 m")


func test_guard_checks_polygon_barriers() -> void:
	var doc := _map()
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	_clip(doc, L_SHAPE, {"hauteur": 1.2})
	var texts := doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "barrière en L acceptée")
	assert_true(bool(CustomMapGuard.check_full(texts).get("ok", false)), "et jouable")
	var src := String(texts["objets.json"])
	var key := "\"sommets\":[[2,2],[6,2],[6,3],[3,3],[3,6],[2,6]]"
	assert_true(src.contains(key), "sommets écrits en entiers (%s)" % src)
	for bc in [
			["\"sommets\":[[2,2],[6,2]]", "deux sommets"],
			["\"sommets\":[[2,2],[6,2],[6,\"x\"]]", "coordonnée texte"],
			["\"sommets\":[[2,2],[6,2],[600,3]]", "hors du terrain"],
			["\"sommets\":[2,2,6,2,6,3]", "nombres à plat"],
			["\"sommets\":\"res://x.tscn\"", "chemin de ressource"],
			["\"position\":[2,2]", "ni sommets ni rect"]]:
		var t := texts.duplicate()
		t["objets.json"] = src.replace(key, bc[0])
		assert_false(CustomMapGuard.check_texts(t).reasons.is_empty(), "refusée : %s" % bc[1])


# ------------------------------------------------------------------ jeu

func test_concave_barrier_blocks_with_its_exact_shape_and_height() -> void:
	var doc := _map()
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	var cl := _clip(doc, L_SHAPE, {"hauteur": 1.2})
	var def := EditorMapDef.from_map(doc, "perso:clip")
	assert_true(def.is_valid(), "\n".join(def.validator.errors().map(func(m): return String(m.fr))))
	var clips: Array = def.layout_data.blockers.filter(func(b): return b.get("clip", false))
	assert_eq(clips.size(), 1, "une barrière décrite")
	if clips.size() != 1:
		return
	var d: Dictionary = clips[0]
	assert_eq((d.poly as Array).size(), 6, "6 sommets")
	assert_near(float(d.size[1]), 1.2, 0.001, "hauteur 1,2 m")
	assert_near(float(d.center[1]), 0.6, 0.001, "posée sur le sol")
	assert_near(float(d.center[0]), 4.0 + OFF, 0.001, "centre du rectangle englobant (x)")
	# Validateur : cases des deux bras seulement (pas l'intérieur du L).
	var f := def.validator.floors[0]
	# Cases de 0,5 m (centre en c × 0,5) ; un bord droit compte comme [x0, x1[.
	var mine := "decor#" + String(cl.id)
	assert_eq(f.key_at(Vector2i(5, 10)), mine, "bras ouest plein (2,5 ; 5)")
	assert_eq(f.key_at(Vector2i(10, 4)), mine, "bras nord plein (5 ; 2)")
	assert_eq(f.key_at(Vector2i(4, 4)), mine, "coin nord-ouest plein (2 ; 2)")
	assert_true(f.key_at(Vector2i(12, 4)) != mine, "bord est [.., 6[ : (6 ; 2) libre")
	assert_true(f.key_at(Vector2i(9, 9)) != mine, "creux du L libre (4,5 ; 4,5)")
	var n := MapRaster.clip_cells(cl).size()
	assert_eq(n, 8 * 2 + 2 * 6, "bras nord 8 × 2 cases, bras ouest 2 × 6 de plus (%d)" % n)
	assert_eq(MapRaster.clip_cells({"type": "bloc_invisible", "sommets": [[5, 5], [5.5, 5], [5.5, 8], [5, 8]]}).size(), 6,
		"polygone de 0,5 × 3 m sur la grille : une rangée de 6 cases, comme le rectangle d'avant")
	# En jeu : un prisme en morceaux convexes, sur la couche BARRIER.
	var world := Node3D.new()
	host.add_child(world)
	MeshMapBuilder.new(def.layout_data, "").build(world)
	var boxes := world.find_children("*", "CollisionBox", true, false).filter(func(n): return (n as CollisionBox).polygon.size() == 6)
	assert_eq(boxes.size(), 1, "CollisionBox du polygone")
	await wait_frames(1)
	if boxes.size() == 1:
		var box: CollisionBox = boxes[0]
		var shapes := box.find_children("*", "CollisionShape3D", false, false)
		assert_true(shapes.size() >= 2 and shapes.all(func(s): return s.shape is ConvexPolygonShape3D), "L : au moins 2 formes convexes (%d)" % shapes.size())
		assert_eq(box.collision_layer, Barricade.BARRIER_LAYER, "joueurs et zombies seulement")
		assert_eq(box.find_children("*", "MeshInstance3D", true, false).size(), 0, "aucun maillage")
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var walk := 1 | Barricade.BARRIER_LAYER
	var ray := func(a: Vector3, b: Vector3, mask: int) -> Dictionary:
		return space.intersect_ray(PhysicsRayQueryParameters3D.create(a + Vector3(OFF, 0, OFF), b + Vector3(OFF, 0, OFF), mask))
	var hit_arm: Dictionary = ray.call(Vector3(1, 0.6, 4.5), Vector3(4.5, 0.6, 4.5), walk)
	assert_true(not hit_arm.is_empty() and hit_arm.collider is CollisionBox, "bras ouest : arrêt")
	if not hit_arm.is_empty():
		assert_near(hit_arm.position.x - OFF, 2.0, 0.05, "arrêt sur le bord du polygone (x = 2)")
	assert_true((ray.call(Vector3(4.5, 0.6, 3.5), Vector3(4.5, 0.6, 5.5), walk) as Dictionary).is_empty(), "creux du L : on passe")
	assert_false((ray.call(Vector3(4.5, 0.6, 1.0), Vector3(4.5, 0.6, 2.8), walk) as Dictionary).is_empty(), "bras nord : arrêt")
	assert_true((ray.call(Vector3(1, 1.5, 4.5), Vector3(4.5, 1.5, 4.5), walk) as Dictionary).is_empty(), "au-dessus de 1,2 m : on passe")
	assert_true((ray.call(Vector3(1, 0.6, 4.5), Vector3(4.5, 0.6, 4.5), 1) as Dictionary).is_empty(), "les balles passent")
	# Aperçu 3D : le prisme translucide, à la hauteur de la barrière.
	var pv := Node3D.new()
	host.add_child(pv)
	MapPreviewBuilder.new(def.layout_data).build_decor(pv)
	var views := pv.find_children("ClipView_*", "MeshInstance3D", true, false)
	assert_eq(views.size(), 1, "barrière dans l'aperçu")
	if views.size() == 1:
		var mesh: Mesh = (views[0] as MeshInstance3D).mesh
		assert_true(mesh is ArrayMesh, "prisme du polygone (pas un pavé)")
		assert_near(mesh.get_aabb().size.y, 1.2, 0.01, "à la hauteur réglée")
		assert_near(mesh.get_aabb().size.x, 4.0, 0.01, "4 m de large")
	pv.queue_free()
	world.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ éditeur

func test_editor_draws_edits_rotates_and_undoes_a_polygon_barrier() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	ed._reset(_map())
	ed.canvas.set_snap_mode("grille")
	ed.set_hotbar(8, "bloc_invisible")
	assert_eq(ed.tool(), "poly", "outil polygone")
	var cv := ed.canvas
	# L à cheval sur le mur sud de la salle B et dehors ; fermé en recliquant le premier point.
	var pts := [Vector2(20, 8), Vector2(23, 8), Vector2(23, 12), Vector2(22, 12), Vector2(22, 9), Vector2(20, 9)]
	var n0 := ed.doc.objets.size()
	for p in pts:
		cv.mouse_m = p
		cv._press(false)
	assert_eq(cv.poly_pts.size(), 6, "6 sommets tracés")
	cv.mouse_m = pts[0]
	cv._press(false)
	assert_eq(ed.doc.objets.size(), n0 + 1, "barrière posée en recliquant le premier point")
	var e := ed.doc.find(ed.selected)
	assert_eq(String(e.get("type", "")), "bloc_invisible")
	assert_eq(MapGeom.poly(e.get("sommets", [])), PackedVector2Array(pts), "sommets tracés")
	assert_true(ed.invalid.is_empty(), "rien de rouge : %s" % str(ed.invalid))
	var eid := String(e.id)
	assert_eq(cv.handles().size(), 6, "une poignée par sommet")
	# Entrée termine aussi un tracé.
	for p in [Vector2(30, 2), Vector2(32, 2), Vector2(32, 4)]:
		cv.mouse_m = p
		cv._press(false)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	ed._input(key)
	assert_eq(ed.doc.objets.size(), n0 + 2, "Entrée : triangle posé dehors")
	# Sommet déplacé (poignée), refus d'un contour qui se croise.
	var res := ed.try_handle(ed.doc.find(eid).duplicate(true), 0, Vector2(19, 7), ed.doc.snapshot())
	assert_true(res.ok, "sommet déplacé : %s" % MapRules.why(res))
	assert_eq(MapGeom.v2(ed.doc.find(eid).sommets[0]), Vector2(19, 7))
	var before := ed.doc.find(eid).duplicate(true)
	res = ed.try_handle(before.duplicate(true), 0, Vector2(23.5, 10), ed.doc.snapshot())
	assert_false(res.ok, "contour qui se croise : refusé")
	assert_eq(ed.doc.find(eid).sommets, before.sommets, "barrière inchangée après le refus")
	# Déplacement.
	res = ed.try_move(before, [], Vector2(1, 0), ed.doc.snapshot())
	assert_true(res.ok, "déplacée : %s" % MapRules.why(res))
	assert_eq(MapGeom.v2(ed.doc.find(eid).sommets[0]), Vector2(20, 7), "déplacée d'un mètre vers l'est")
	ed.changed()
	# Rotation (R) puis annulation.
	ed.select(eid)
	var area := MapGeom.area(MapRaster.clip_poly(ed.doc.find(eid)))
	var moved: Array = ed.doc.find(eid).sommets.duplicate(true)
	ed.rotate_selected()
	assert_true(ed.doc.find(eid).sommets != moved, "R : tournée de 90°")
	assert_near(MapGeom.area(MapRaster.clip_poly(ed.doc.find(eid))), area, 0.01, "même surface")
	ed.undo()
	assert_eq(ed.doc.find(eid).sommets, moved, "Ctrl+Z : avant la rotation")
	# Hauteur : « Jusqu'au plafond » coché par défaut, champ au dixième de mètre.
	ed.select(eid)
	ed.panels.refresh_now()
	var spins := ed.panels._props.find_children("*", "SpinBox", true, false).filter(func(s): return absf(s.step - 0.1) < 0.0001)
	assert_eq(spins.size(), 1, "champ Hauteur au pas de 0,1 m")
	var boxes := ed.panels._props.find_children("*", "CheckBox", true, false).filter(func(c): return String(c.text).contains(Lang.t("plafond", "ceiling")))
	assert_eq(boxes.size(), 1, "case « Jusqu'au plafond »")
	if spins.size() == 1 and boxes.size() == 1:
		var hs: SpinBox = spins[0]
		var cb: CheckBox = boxes[0]
		assert_true(cb.button_pressed and not hs.editable, "jusqu'au plafond : champ grisé")
		cb.button_pressed = false
		assert_true(ed.doc.find(eid).has("hauteur"), "décochée : une hauteur")
		await wait_frames(1)
		ed.panels.refresh_now()
		hs = ed.panels._props.find_children("*", "SpinBox", true, false).filter(func(s): return absf(s.step - 0.1) < 0.0001)[0]
		assert_true(hs.editable, "champ Hauteur modifiable")
		hs.value = 1.3
		assert_near(float(ed.doc.find(eid).hauteur), 1.3, 0.001, "hauteur 1,3 m")
		var data := EditorMapDef.from_map(ed.doc, "perso:ed").layout_data
		var mine: Array = data.blockers.filter(func(b): return String(b.get("eid", "")) == eid)
		assert_eq(mine.size(), 1, "barrière exportée")
		if mine.size() == 1:
			assert_near(float(mine[0].size[1]), 1.3, 0.001, "hauteur appliquée en jeu")
	# Suppression puis annulation.
	ed.delete_element(eid)
	assert_true(ed.doc.find(eid).is_empty(), "supprimée")
	ed.undo()
	assert_false(ed.doc.find(eid).is_empty(), "Ctrl+Z : revenue")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ chevauchements (réglage de la carte)

func test_overlap_setting_frees_decor_and_obstacles_only() -> void:
	var doc := _map()
	var crate := {"id": "c1", "type": "caisse", "etage": 0, "position": [5.0, 5.0]}
	doc.objets.append(crate)
	var crate2 := {"type": "caisse", "position": [5.5, 5.0]}
	var desk := {"type": "prefab", "prefab": "bureau", "rot": 0, "position": [5.0, 5.5]}
	assert_false(MapRules.overlaps_allowed(doc), "par défaut : pas de chevauchement")
	assert_false(MapRules.place_floor_item(doc, 0, crate2, Vector2(5.5, 5.0), "", false).ok, "caisse sur caisse : refusée par défaut")
	assert_false(MapRules.check_rect(doc, 0, "pilier", Rect2(4.5, 4.5, 1, 1)).ok, "pilier sur caisse : refusé par défaut")
	doc.carte[MapCatalog.OVERLAP_KEY] = true
	assert_true(MapRules.overlaps_allowed(doc))
	var r := MapRules.place_floor_item(doc, 0, crate2, Vector2(5.5, 5.0), "", false)
	assert_true(r.ok, "caisse sur caisse : acceptée (%s)" % MapRules.why(r))
	r = MapRules.place_floor_item(doc, 0, desk, Vector2(5.0, 5.5), "", false)
	assert_true(r.ok, "bureau sur caisse : accepté (%s)" % MapRules.why(r))
	r = MapRules.check_rect(doc, 0, "pilier", Rect2(4.5, 4.5, 1, 1))
	assert_true(r.ok, "pilier sur caisse : accepté (%s)" % MapRules.why(r))
	# Objets de jeu : jamais.
	assert_false(MapRules.place_floor_item(doc, 0, crate2, Vector2(9.0, 7.0), "", false).ok, "caisse sur le départ : refusée")
	assert_false(MapRules.place_floor_item(doc, 0, {"type": "depart"}, Vector2(5.0, 5.0), "", false).ok, "départ sur une caisse : refusé")
	assert_false(MapRules.check_rect(doc, 0, "escalier", Rect2(4, 4, 2, 3)).ok, "escalier sur une caisse : refusé")
	# Posés : rien de rouge, carte valide ; décoché : redeviennent rouges.
	var c2 := crate2.duplicate()
	c2["id"] = "c2"
	c2["etage"] = 0
	doc.objets.append(c2)
	doc.objets.append({"id": "x9", "type": "pilier", "etage": 0, "rect": [4.5, 4.5, 5.5, 5.5]})
	for id in ["c1", "c2", "x9"]:
		assert_true(MapRules.check_existing(doc, doc.find(id)).ok, "%s valide avec le réglage" % id)
	var v := ObjectsTest._check(doc)
	assert_eq(v.errors().size(), 0, "carte valide :\n" + "\n".join(v.errors().map(func(m): return String(m.fr))))
	var def := EditorMapDef.from_map(doc, "perso:chev")
	assert_true(def.is_valid(), "jouable")
	doc.carte.erase(MapCatalog.OVERLAP_KEY)
	assert_false(MapRules.check_existing(doc, doc.find("c2")).ok, "réglage retiré : c2 chevauche c1")
	# Fichiers : le réglage voyage avec la carte, contrôlé ; « faux » n'est pas écrit.
	doc.carte[MapCatalog.OVERLAP_KEY] = true
	var texts := doc.file_texts()
	assert_true(String(texts["carte.json"]).contains("\"chevauchement_decor\": true"), "réglage écrit")
	assert_true(MapRules.overlaps_allowed(EditorMap.from_texts(texts)), "et relu")
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "accepté par le contrôle des cartes reçues")
	var bad := texts.duplicate()
	bad["carte.json"] = String(bad["carte.json"]).replace("\"chevauchement_decor\": true", "\"chevauchement_decor\": \"oui\"")
	assert_false(CustomMapGuard.check_texts(bad).reasons.is_empty(), "valeur qui n'est pas vrai / faux : refusée")
	var off := texts.duplicate()
	off["carte.json"] = String(off["carte.json"]).replace("\"chevauchement_decor\": true", "\"chevauchement_decor\": false")
	assert_false(EditorMap.from_texts(off).carte.has(MapCatalog.OVERLAP_KEY), "faux : clé retirée (règles d'avant)")
	assert_false(EditorMap.blank().carte.has(MapCatalog.OVERLAP_KEY), "carte neuve : réglage décoché")
