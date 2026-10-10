extends TestCase
## Boîte mystère posée au sol (format 15, docs/MAP_OBJECTS.md § 15) : pose au
## sol et aimant de mur (MapRules.place_box), refus dans un mur ou hors des
## pièces, rotation, fichier et conversion des cartes d'avant, contrôle des
## cartes reçues, description en jeu (mur fictif, navmesh), emplacement en
## jeu (centre, avant), invite de tous les côtés et jamais à travers un mur,
## cartes existantes (boîtes murales) inchangées.

const DecorFree := preload("res://tests/test_map_decor_free.gd")
const OFF := MapGeom.WORLD_OFFSET

var _root: Node3D


func after_each() -> void:
	if _root:
		_root.free()
		_root = null


static func _tmpl(rot := 0) -> Dictionary:
	return {"type": "boite", "depart": false, "rot": rot}


## Deux salles (A : 0..14 × 0..10, B : 14..24 × 0..10) et une caisse au sol
## dans A, au centre (5, 5), tournée de `rot`, marquée « depart » : c'est la
## caisse unique gardée par l'export (la boîte murale de two_rooms ne l'est
## plus). Départ des joueurs déplacé en (9,5, 7) : la caisse est pleine pour
## le validateur, rien à moins de 1 m du départ.
static func floor_map(rot := 45) -> Dictionary:
	var doc := DecorFree.two_rooms()
	for o in doc.objets:
		if String(o.type) == "depart":
			o["position"] = [9.5, 7.0]
		elif String(o.type) == "boite":
			o["depart"] = false
	var b := DecorFree._obj(doc, {"type": "boite", "position": [5.0, 5.0], "rot": rot, "depart": true})
	return {"doc": doc, "box": b}


# ------------------------------------------------------------------ pose (éditeur)

func test_place_on_the_floor_anywhere_in_a_room() -> void:
	var doc := DecorFree.two_rooms()
	var r := MapRules.place_box(doc, 0, _tmpl(45), Vector2(7.3, 3.2))
	assert_true(r.ok, "au milieu de la salle : %s" % MapRules.why(r))
	assert_false(r.has("mur"), "posée au sol (pas de mur)")
	assert_eq(int(r.rot), 45, "rotation gardée")
	assert_eq(r.position, [7.3, 3.2], "au centimètre, sous le curseur")
	var o := _tmpl(45)
	MapRules.apply_box(o, r)
	assert_true(MapCatalog.floor_box(o) and MapCatalog.tool_of(o) == "floor_item" and MapCatalog.rotates(o), "boîte au sol : outil au sol, pivote")
	# Grille, quart de tour : emprise 2 × 1 m calée sur les cases.
	var g := MapRules.place_box(doc, 0, _tmpl(90), Vector2(7.1, 3.3), "", true)
	assert_true(g.ok and not g.has("mur"), "sur la grille")
	assert_eq(MapCatalog.floor_size({"type": "boite", "rot": 90}), Vector2i(2, 4), "tournée de 90° : 1 × 2 m")


func test_snaps_to_a_nearby_wall_facing_the_room() -> void:
	var doc := DecorFree.two_rooms()
	# Curseur à 0,9 m du mur nord de A : collée au mur, face au sud (la pièce).
	var r := MapRules.place_box(doc, 0, _tmpl(30), Vector2(9.0, 0.9))
	assert_true(r.ok and String(r.get("mur", "")) == "n", "aimantée au mur nord (%s)" % str(r))
	assert_near(float(r.position[1]), 0.0, 0.001, "position sur le trait du mur")
	var o := _tmpl(30)
	MapRules.apply_box(o, r)
	assert_false(o.has("rot"), "boîte murale : jamais de « rot »")
	assert_eq(MapCatalog.tool_of(o), "wall_item", "outil mural")
	assert_true(MapRules.box_front(o).is_equal_approx(Vector2(0, 1)), "avant vers la pièce")
	# Alt (sans aimant) : au sol, à 0,9 m du mur, si elle tient (droite : 0,5 m de profondeur).
	var free := MapRules.place_box(doc, 0, _tmpl(0), Vector2(9.0, 0.9), "", false, false)
	assert_true(free.ok and not free.has("mur"), "sans aimant : au sol (%s)" % MapRules.why(free))
	# Mur refusé (fenêtre derrière) : posée au sol à la place.
	var win := MapRules.place_box(doc, 0, _tmpl(0), Vector2(3.25, 1.2))
	assert_true(win.ok and not win.has("mur"), "fenêtre dans le mur : au sol devant (%s)" % MapRules.why(win))
	# Mur libre : aimant aussi (des deux côtés).
	DecorFree._obj(doc, {"type": "mur", "a": [7.0, 4.0], "b": [12.0, 4.0], "epaisseur": 0.5})
	var fw := MapRules.place_box(doc, 0, _tmpl(0), Vector2(9.5, 5.0))
	assert_true(fw.ok and String(fw.get("mur", "")) == "n", "collée au mur libre, côté du curseur (%s)" % str(fw))


func test_refused_in_a_wall_or_outside() -> void:
	var doc := DecorFree.two_rooms()
	var out := MapRules.place_box(doc, 0, _tmpl(0), Vector2(30.0, 5.0))
	assert_false(out.ok, "hors des pièces : refusée")
	var on_wall := MapRules.place_box(doc, 0, _tmpl(0), Vector2(14.0, 3.0), "", false, false)
	assert_false(on_wall.ok, "sur le mur commun : refusée")
	# Sans aimant, trop près du mur : refus (le couvercle entrerait dans le mur).
	var close := MapRules.place_box(doc, 0, _tmpl(0), Vector2(9.0, 0.7), "", false, false)
	assert_false(close.ok, "à 0,2 m de la face du mur : refusée")
	assert_true(MapRules.why(close).contains("mur") or MapRules.why(close).contains("wall"), "raison : le mur (%s)" % MapRules.why(close))
	# Tournée de 45° : ses coins entrent dans le mur à 0,9 m.
	var turned := MapRules.place_box(doc, 0, _tmpl(45), Vector2(9.0, 0.9), "", false, false)
	assert_false(turned.ok, "tournée de 45° contre le mur : refusée")
	# Sur un autre objet (départ en 7, 6) : refusée.
	var over := MapRules.place_box(doc, 0, _tmpl(0), Vector2(7.0, 6.0))
	assert_false(over.ok, "sur le départ : refusée")
	# Dans un mur libre : refusée même sans aimant.
	DecorFree._obj(doc, {"type": "mur", "a": [7.0, 4.0], "b": [12.0, 4.0], "epaisseur": 0.5})
	var in_free := MapRules.place_box(doc, 0, _tmpl(0), Vector2(9.5, 4.2), "", false, false)
	assert_false(in_free.ok, "à cheval sur un mur libre : refusée")


func test_rotation_ring_and_typed_angle() -> void:
	var fm := floor_map(0)
	var doc: EditorMap = fm.doc
	var b: Dictionary = fm.box
	assert_true(MapTransform.can_rotate(b) and MapGizmoTop.has_ring(b), "boîte au sol : anneau Z")
	var res := MapTransform.apply(doc, b.duplicate(true), [], MapTransform.pivot(doc, b), 15.0, doc.snapshot())
	assert_true(res.ok, "pas de 15° : %s" % MapRules.why(res))
	assert_eq(MapGeom.rot_of(doc.find(String(b.id))), 15, "rot = 15")
	var b2 := doc.find(String(b.id))
	res = MapTransform.apply(doc, b2.duplicate(true), [], MapTransform.pivot(doc, b2), 22.0, doc.snapshot())
	assert_eq(MapGeom.rot_of(doc.find(String(b.id))), 37, "valeur tapée : 37°")
	# Sans « rot » écrit (fichier à la main) : tourne quand même.
	var bare := {"id": "bx", "type": "boite", "altitude": 0, "position": [5.0, 5.0]}
	assert_eq(MapGeom.rot_of(MapTransform.rotated(bare, Vector2(5, 5), 30.0)), 30, "boîte sans « rot » tournée")
	# Boîte murale : ni anneau ni rotation propre (elle suit son mur).
	var wall: Dictionary = doc.objets.filter(func(o): return String(o.type) == "boite" and o.has("mur"))[0]
	assert_false(MapTransform.can_rotate(wall) or MapGizmoTop.has_ring(wall), "boîte murale : pas d'anneau")


func test_wall_box_dragged_away_keeps_facing() -> void:
	var doc := DecorFree.two_rooms()
	# Boîte du mur sud de B (avant vers le nord) décollée vers le milieu de B.
	var wb: Dictionary = doc.objets.filter(func(o): return String(o.type) == "boite")[0]
	var r := MapRules.place_box(doc, 0, wb, Vector2(19.0, 5.0), String(wb.id))
	assert_true(r.ok and not r.has("mur"), "décollée : au sol (%s)" % MapRules.why(r))
	assert_eq(int(r.rot), 180, "avant toujours vers le nord (rot 180)")
	var o := wb.duplicate()
	MapRules.apply_box(o, r)
	assert_true(MapRules.box_front(o).is_equal_approx(Vector2(0, -1)), "avant vers le nord")
	assert_false(o.has("mur") or o.has("angle"), "plus de mur")


# ------------------------------------------------------------------ fichier, conversion, contrôle

func test_file_round_trip_and_older_maps() -> void:
	var fm := floor_map(45)
	var doc: EditorMap = fm.doc
	var texts := doc.file_texts()
	assert_eq(int(JSON.parse_string(texts["carte.json"]).format), EditorMap.FORMAT, "format courant")
	assert_true(EditorMap.FORMAT >= 15, "format 15 et plus")
	assert_true(String(texts["objets.json"]).contains("\"rot\":45"), "rot écrit")
	var back := EditorMap.from_texts(texts)
	assert_eq(back.load_errors, [], "relue sans message")
	assert_eq(back.file_texts(), texts, "réécrite à l'identique")
	assert_true(MapCatalog.floor_box(back.find(String(fm.box.id))), "toujours au sol")
	# Carte au format 14 : une boîte sans « mur » (écrite à la main) était
	# contre le mur nord : elle le reste ; les boîtes murales sont inchangées.
	var old := DecorFree.two_rooms()
	DecorFree._obj(old, {"type": "boite", "position": [9.0, 0.0], "depart": false})
	var t14 := old.file_texts()
	t14 = load("res://tests/test_levels_migration.gd").as_format(t14, 14)
	var m14 := EditorMap.from_texts(t14)
	assert_eq(m14.format_read, 14)
	var conv: Array = m14.objets.filter(func(o): return String(o.type) == "boite" and MapGeom.v2(o.position) == Vector2(9, 0))
	assert_true(conv.size() == 1 and String(conv[0].get("mur", "")) == "n", "boîte sans mur d'avant : mur nord (%s)" % str(conv))
	assert_eq(MapCatalog.tool_of(conv[0]) if conv.size() == 1 else "", "wall_item", "toujours murale")
	var walls14: Array = old.objets.filter(func(o): return String(o.type) == "boite" and o.has("mur"))
	for w in walls14:
		var now := m14.find(String(w.id))
		assert_true(String(now.get("mur", "")) == String(w.mur) and MapGeom.v2(now.position) == MapGeom.v2(w.position) and not now.has("rot"),
			"boîte murale d'avant inchangée (%s)" % str(now))


func test_received_maps_are_checked() -> void:
	var texts: Dictionary = floor_map(45).doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "boîte au sol acceptée")
	var with_obj := func(change: Callable) -> Dictionary:
		var j: Dictionary = JSON.parse_string(texts["objets.json"])
		for o in j.objets:
			if String(o.type) == "boite" and not o.has("mur"):
				change.call(o)
		var t := texts.duplicate()
		t["objets.json"] = JSON.stringify(j)
		return CustomMapGuard.check_texts(t)
	assert_false(with_obj.call(func(o): o["mur"] = "n").ok, "« rot » avec « mur » : refusée")
	assert_false(with_obj.call(func(o): o["angle"] = 30).ok, "« rot » avec « angle » : refusée")
	# Boîte de départ (même type « boite », « depart » vrai) : même règle.
	assert_eq(with_obj.call(func(o): o["depart"] = true).reasons, [], "boîte de départ au sol acceptée")
	var start_wall := func(o: Dictionary) -> void:
		o["depart"] = true
		o["mur"] = "n"
	assert_false(with_obj.call(start_wall).ok, "boîte de départ : « rot » avec « mur » refusée")
	var start_angle := func(o: Dictionary) -> void:
		o["depart"] = true
		o["angle"] = 30
	assert_false(with_obj.call(start_angle).ok, "boîte de départ : « rot » avec « angle » refusée")
	assert_false(with_obj.call(func(o): o["rot"] = 400).ok, "rot 400 : refusée")
	assert_false(with_obj.call(func(o): o["rot"] = "x").ok, "rot texte : refusée")
	assert_false(with_obj.call(func(o): o["rot"] = 12.5).ok, "rot non entier : refusée")
	assert_false(with_obj.call(func(o): o["echelle"] = [2, 2, 2]).ok, "échelle : refusée (taille fixe)")
	# Carte plus récente que le jeu : refusée.
	var t2 := texts.duplicate()
	t2["carte.json"] = String(t2["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": %d" % (EditorMap.FORMAT + 1))
	assert_false(CustomMapGuard.check_texts(t2).ok, "format plus récent : refusée")


# ------------------------------------------------------------------ vérification et description en jeu

func test_validator_and_game_layout() -> void:
	var fm := floor_map(45)
	var doc: EditorMap = fm.doc
	var v := MapRaster.build(doc).v
	v.analyze()
	assert_eq(v.errors().map(func(e): return e.fr), [], "carte valide")
	var items: Array = v.wall_items.filter(func(it): return it.get("floor_box", false))
	assert_eq(items.size(), 1, "boîte au sol comptée parmi les emplacements")
	var cells: Array = items[0].cells
	assert_eq(cells.filter(func(c): return v.floors[0].at(c) != MapValidator.K.MARQUEUR).size(), 0, "ses cases sont occupées")
	assert_true(cells.size() >= 6, "emprise tournée de 2 × 1 m (%d cases)" % cells.size())
	var lay := MapLayoutExport.build(v)
	var boxes: Array = lay.markers.box
	assert_eq(boxes.size(), 1, "une seule caisse exportée (celle de départ)")
	var fb: Array = boxes.filter(func(x): return bool(x.get("floor", false)))
	assert_eq(fb.size(), 1, "la caisse au sol")
	var front := Vector3(0, 0, 1).rotated(Vector3.UP, -deg_to_rad(45.0))
	var wall := MeshMapLayout.vec(fb[0].wall)
	assert_true(wall.is_equal_approx(-front) or (wall + front).length() < 0.002, "mur fictif derrière la boîte (%s)" % wall)
	var center := MeshMapLayout.vec(fb[0].p) - wall * MysteryBox.SPOT_WALL_GAP
	assert_true(center.distance_to(Vector3(5.0 + OFF, 0.0, 5.0 + OFF)) < 0.003, "centre de la boîte en jeu (%s)" % center)
	# Navmesh : son emprise retirée (boîte ou tas de planches) ; la boîte murale non.
	var nb: Array = lay.get("nav_blocks", [])
	assert_eq(nb.size(), 1, "un emplacement retiré du navmesh")
	assert_near(float(nb[0].h), MysteryBox.BODY_SIZE.y, 0.001, "hauteur de la boîte")
	var poly := PackedVector2Array()
	for q in nb[0].poly:
		poly.append(Vector2(float(q[0]), float(q[1])))
	assert_true(Geometry2D.is_point_in_polygon(Vector2(5.0 + OFF, 5.0 + OFF), poly), "emprise autour du centre")
	# Jeu : marqueurs, emplacement, avant et collision.
	var ml := MeshMapLayout.new(null, lay)
	var spots := ml.box_spots()
	var fi := -1
	for i in spots.size():
		if bool(spots[i].data.get("floor", false)):
			fi = i
	assert_true(fi >= 0, "marqueur au sol en jeu")
	var box := MysteryBox.new()
	box.setup_spot(spots[fi])
	assert_true((box.spot.pos as Vector3).distance_to(Vector3(5.0 + OFF, 0.0, 5.0 + OFF)) < 0.003, "caisse posée sur son centre")
	box._place()
	assert_true(box.basis.z.distance_to(front) < 0.002, "avant de la caisse (+z) tourné comme dans l'éditeur (%s)" % box.basis.z)
	box.free()
	# Description de la DRAFT ARENA (boîtes murales) : aucun « floor », aucun navmesh retiré.
	var da := EditorMap.load_dir("res://assets/maps/draft_arena/")
	var vd := MapRaster.build(da).v
	vd.analyze()
	var ld := MapLayoutExport.build(vd)
	assert_false((ld.markers.box as Array).any(func(x): return x.has("floor")), "DRAFT ARENA : boîtes murales")
	assert_false(ld.has("nav_blocks"), "DRAFT ARENA : navmesh inchangé")


func test_front_blocked_is_flagged() -> void:
	var doc := DecorFree.two_rooms()
	# Avant (sud, rot 0) contre le mur sud de A, sans aimant : 0,4 m de vide.
	DecorFree._obj(doc, {"type": "boite", "position": [9.0, 9.1], "rot": 0, "depart": false})
	var v := MapRaster.build(doc).v
	v.analyze()
	var warn: Array = v.warnings().filter(func(m): return String(m.fr).contains("son avant"))
	assert_eq(warn.size(), 1, "avant face au mur signalé")


# ------------------------------------------------------------------ invite en jeu (physique)

func _wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	_root.add_child(body)
	body.global_position = pos


## Boîte au sol en (0, 0, 2), tournée de 45° ; un mur plein en z = 0,4.
func _floor_box() -> MysteryBox:
	_root = Node3D.new()
	host.add_child(_root)
	var front := Vector3(0, 0, 1).rotated(Vector3.UP, -deg_to_rad(45.0))
	var m := MapMarker.new()
	m.id = "box_0"
	m.wall = -front
	m.wall_gap = MeshMapLayout.GAP
	m.pos = Vector3(0, 0, 2) + m.wall * MysteryBox.SPOT_WALL_GAP - m.wall * MeshMapLayout.GAP
	m.data = {"floor": true}
	var box := MysteryBox.new()
	box.setup_spot(m)
	_root.add_child(box)
	_wall(Vector3(0, 1.5, 0.4), Vector3(8, 3, 0.3))
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	return box


func test_prompt_from_every_side_never_through_a_wall() -> void:
	var box := await _floor_box()
	assert_true(box.global_position.is_equal_approx(Vector3(0, 0, 2)), "boîte sur son centre (%s)" % box.global_position)
	assert_true(box.interact_point().is_equal_approx(Vector3(0, MysteryBox.SIGHT_HEIGHT, 2)), "point visé : le milieu du coffre")
	var sys := InteractionSystem.new()
	sys.register(box)
	var pd := PlayerData.new(1)
	var front := Vector3(0, 0, 1).rotated(Vector3.UP, -deg_to_rad(45.0))
	var side := front.cross(Vector3.UP)
	var target := box.interact_point()
	# Devant, sur les côtés et derrière (BO1 : tout autour du coffre).
	for d: Vector3 in [front * 1.0, side * 1.4, -side * 1.4, -front * 1.0]:
		var eye := Vector3(0, 0, 2) + d + Vector3.UP * 1.6
		assert_eq(sys.pick_focus(eye, (target - eye).normalized(), 1, pd), box, "visée depuis %s" % d)
		assert_true(box.sight_ok(eye), "ligne de vue depuis %s" % d)
	# Derrière le mur (z = 0,1), à portée : jamais.
	var behind := Vector3(0.3, 1.6, 0.1)
	assert_true(behind.distance_to(target) < box.interact_range + 0.6, "à portée de la boîte")
	assert_false(box.sight_ok(behind), "mur entre le joueur et la boîte")
	assert_eq(sys.pick_focus(behind, (target - behind).normalized(), 1, pd), null, "aucune invite à travers le mur")
	assert_eq(InteractionSystem.srv_eye_offset(null), Vector3.UP * 1.5, "œil du serveur par défaut")
	sys.unregister(box)
	sys.free()


func test_wall_box_not_through_its_wall() -> void:
	# Boîte murale contre le mur z = 0,4 (côté z > 0) : le joueur de l'autre
	# côté du mur, tout près, ne la voit pas ; devant, oui.
	_root = Node3D.new()
	host.add_child(_root)
	var m := MapMarker.new()
	m.id = "box_0"
	m.wall = Vector3(0, 0, -1)
	m.pos = Vector3(0, 0, 0.55 + 0.5)
	var box := MysteryBox.new()
	box.setup_spot(m)
	_root.add_child(box)
	_wall(Vector3(0, 1.5, 0.4), Vector3(8, 3, 0.3))
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	assert_true(box.sight_ok(Vector3(0, 1.6, 2.0)), "devant : vue")
	assert_false(box.sight_ok(Vector3(0, 1.6, -0.2)), "derrière son mur : jamais")


# ------------------------------------------------------------------ étages (jamais par-dessous ni par-dessus)

class Obj extends Interactable:
	func prompt(_pid: int) -> String:
		return "x"

	# Comme les vrais objets : au sol, 1,1 m au-dessus ; au mur, devant lui.
	func interact_point() -> Vector3:
		return global_position + Vector3(0, 0.0 if mount_height > 0.0 else 1.1, 0.3)


## Depuis un escalier raide : l'écart permis croît avec la distance à plat,
## jamais jusqu'à une hauteur d'étage.
func test_objects_from_the_stairs() -> void:
	var S := InteractionSystem
	# Porte en haut d'un escalier raide : 2 m avant elle sur les marches, 1,45 m plus bas.
	assert_true(S.same_level(2.032 - 1.45, 2.032, 2.0), "porte d'un palier à 2 m depuis les marches")
	assert_true(S.same_level(4.445 - 1.45, 4.445, 2.0), "porte d'un palier à 4,4 m depuis les marches")
	# Coéquipier à terre 1,6 m plus bas, 2,2 m à plat sur les marches (portée 2,4 m).
	assert_true(S.same_level(3.0, 1.4, 2.2), "réanimation sur un escalier")
	assert_true(S.same_level(1.4, 3.0, 2.2), "réanimation d'un coéquipier plus haut sur l'escalier")
	# Juste dessous (ou dessus) : toujours refusé.
	assert_false(S.same_level(-1.45, 0.0, 0.3), "1,45 m dessous, presque à l'aplomb : non")
	# Étage du dessous, même loin à plat : jamais (borne sous la hauteur d'étage).
	for flat in [1.0, 2.5, 4.0, 6.0]:
		assert_false(S.same_level(0.0, 2.2, flat), "étage du dessous (2,2 m), à %.1f m à plat : non" % flat)
		assert_false(S.same_level(0.0, 3.5, flat), "boîte à l'étage 1 (3,5 m), à %.1f m à plat : non" % flat)
	assert_true(S.level_gap(100.0) < 2.0, "borne sous la plus petite hauteur d'étage")


func test_objects_only_from_their_floor() -> void:
	assert_true(InteractionSystem.same_level(0.0, 0.0) and InteractionSystem.same_level(0.9, 0.0), "même étage, marche d'escalier : oui")
	assert_false(InteractionSystem.same_level(-2.0, 0.0) or InteractionSystem.same_level(2.0, 0.0), "étage du dessous ou du dessus : non")
	assert_false(InteractionSystem.same_level(0.0, 3.5), "boîte à l'étage 1, joueur à l'étage 0 : refus serveur")
	# Objet mural (arme, grenades : 1,45 m ; courant, levier, piège : 1,3 m) à l'étage 1 (sol 3,5).
	_root = Node3D.new()
	host.add_child(_root)
	var sys := InteractionSystem.new()
	var pd := PlayerData.new(1)
	for mh in [0.0, 1.3, 1.45]:
		var o := Obj.new()
		o.interact_id = "o%d" % roundi(mh * 100)
		o.mount_height = mh
		_root.add_child(o)
		o.global_position = Vector3(0, 3.5 + mh, 0)
		sys.register(o)
		assert_near(o.level_y(), 3.5, 0.0001, "sol de l'objet (accroché à %s m)" % mh)
		var p := o.interact_point()
		var aim := func(eye: Vector3) -> Vector3: return (p - eye).normalized()
		# Devant, à son étage : oui ; depuis une marche à 0,9 m sous lui : oui.
		var eye := Vector3(0, 3.5 + 1.6, 1.0)
		assert_eq(sys.pick_focus(eye, aim.call(eye), 1, pd, 3.5), o, "à son étage (accroché à %s m)" % mh)
		eye = Vector3(0, 2.6 + 1.6, 1.0)
		assert_eq(sys.pick_focus(eye, aim.call(eye), 1, pd, 2.6), o, "depuis une marche (accroché à %s m)" % mh)
		# Par-dessous (pieds 2 m plus bas : saut, mezzanine basse) et par-dessus : jamais,
		# même à portée.
		eye = Vector3(0, 1.5 + 1.6, 0.3)
		assert_true(eye.distance_to(p) < o.interact_range + 0.6, "à portée par-dessous")
		assert_eq(sys.pick_focus(eye, aim.call(eye), 1, pd, 1.5), null, "par-dessous : pas d'invite (accroché à %s m)" % mh)
		eye = Vector3(0, 5.5 + 1.6, 0.3)
		if eye.distance_to(p) < o.interact_range + 0.6:
			assert_eq(sys.pick_focus(eye, aim.call(eye), 1, pd, 5.5), null, "par-dessus : pas d'invite")
		sys.unregister(o)
	sys.free()


func test_floor_box_upstairs_not_from_below() -> void:
	# Boîte au sol à l'étage 1 (sol 3,5), dalle de 0,25 m sous elle ; joueur
	# dessous (pieds à 1,5 m : sur une caisse, en plein saut).
	_root = Node3D.new()
	host.add_child(_root)
	var m := MapMarker.new()
	m.id = "box_0"
	m.wall = Vector3(0, 0, -1)
	m.pos = Vector3(0, 3.5, 2) + m.wall * MysteryBox.SPOT_WALL_GAP - m.wall * MeshMapLayout.GAP
	m.data = {"floor": true}
	var box := MysteryBox.new()
	box.setup_spot(m)
	_root.add_child(box)
	_wall(Vector3(0, 3.375, 2), Vector3(8, 0.25, 8))
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var sys := InteractionSystem.new()
	sys.register(box)
	var pd := PlayerData.new(1)
	var t := box.interact_point()
	var below := Vector3(0.3, 1.5 + 1.6, 2.4)
	assert_true(below.distance_to(t) < box.interact_range + 0.6, "à portée par-dessous")
	assert_false(box.sight_ok(below), "la dalle coupe la ligne de vue")
	assert_eq(sys.pick_focus(below, (t - below).normalized(), 1, pd, 1.5), null, "pas d'invite sous la boîte")
	assert_false(InteractionSystem.same_level(1.5, box.level_y()), "refus serveur sous la boîte")
	var above := Vector3(0, 3.5 + 1.6, 3.2)
	assert_eq(sys.pick_focus(above, (t - above).normalized(), 1, pd, 3.5), box, "invite à son étage")
	sys.unregister(box)
	sys.free()
