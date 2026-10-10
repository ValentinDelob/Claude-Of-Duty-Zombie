extends TestCase
## Murs en biais dans l'éditeur de cartes (docs/MAP_AUTHORING.md) :
## aimantation d'angle, mur mitoyen en biais unique, portes, fenêtres et
## objets muraux posés sur un mur en biais (acceptés et refusés selon les
## règles), sol découpé selon le vrai contour (triangulation, pièce concave
## comprise), collisions en CollisionBox tournées (un rayon et un corps ne
## traversent pas le mur oblique), navigation (chemin qui contourne le mur,
## passage par une porte en biais), enregistrement au format 3, lecture des
## formats précédents, DRAFT ARENA inchangée.

const TMP := "res://tests/_out/test_map_editor_diagonal"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


# ------------------------------------------------------------------ carte d'essai

## Octogone (départ) et losange collés par un côté en biais, porte sur ce
## bord commun, une fenêtre en biais chacun, mur libre en biais dans
## l'octogone, caisse contre un mur droit, levier (et son piège) et
## interrupteur contre des murs en biais. Positions posées par les règles de l'éditeur (MapRules).
static func diag_map() -> EditorMap:
	var doc := EditorMap.blank("biais", "BIAIS", "DIAGONAL")
	var za := doc.add_zone("Octogone", "Octagon")
	var zb := doc.add_zone("Losange", "Diamond")
	doc.pieces.append({"id": "p1", "nom": "Octogone", "altitude": 0, "zone": za.id,
		"contour": [[6, 2], [14, 2], [18, 6], [18, 14], [14, 18], [6, 18], [2, 14], [2, 6]]})
	doc.pieces.append({"id": "p2", "nom": "Losange", "altitude": 0, "zone": zb.id, "contour": [[18, 14], [22, 18], [18, 22], [14, 18]],
		"surface_murs": "brick"})
	doc.depart = String(za.id)
	var r := MapRules.place_opening(doc, 0, "porte", Vector2(16, 16), 2.0)
	doc.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": r.position, "largeur": 2.0, "prix": 750})
	for pt in [Vector2(3.8, 3.8), Vector2(20.3, 20.3)]:
		var w := MapRules.place_opening(doc, 0, "fenetre", pt, 1.0)
		doc.ouvertures.append({"id": doc.new_id("o"), "type": "fenetre", "altitude": 0, "position": w.position})
	doc.objets.append({"id": "m1", "type": "mur", "altitude": 0, "a": [8, 12], "b": [12, 8], "epaisseur": 0.5})
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": [14.5, 12.0]})
	# Piège électrique de l'octogone (son levier est contre le mur en biais).
	doc.objets.append({"id": "t1", "type": "piege", "altitude": 0, "rect": [9, 4, 11, 6]})
	for it in [[{"type": "boite"}, Vector2(10, 2.6)], [{"type": "levier"}, Vector2(15.6, 4.3)],
			[{"type": "courant"}, Vector2(20.3, 16.4)]]:
		var o: Dictionary = it[0].duplicate()
		var res := MapRules.place_wall_item(doc, 0, o, it[1])
		o["id"] = doc.new_id("x")
		o["altitude"] = 0.0
		o["position"] = res.position
		MapRules.apply_wall(o, res)
		doc.objets.append(o)
	return MapTestKit.add_evac(doc)


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


# ------------------------------------------------------------------ tracé

func test_angle_snapping() -> void:
	var o := Vector2(2, 2)
	assert_eq(MapGeom.snap_angle(o, Vector2(6.3, 2.4), 1.0), Vector2(6, 2), "presque horizontal -> 0°")
	assert_eq(MapGeom.snap_angle(o, Vector2(5.2, 4.7), 1.0), Vector2(5, 5), "presque à 45° -> 45°, sommet sur la grille")
	assert_eq(MapGeom.snap_angle(o, Vector2(2.3, -1.8), 1.0), Vector2(2, -2), "presque vertical -> 90°")
	assert_eq(MapGeom.snap_angle(o, Vector2(-1.1, 4.8), 0.5), Vector2(-1, 5), "135° avec Maj (0,5 m)")
	assert_eq(MapGeom.snap_angle(o, Vector2(5.2, 3.1), 1.0, true), Vector2(5, 3), "Alt : angle libre, seulement la grille")
	assert_near(MapGeom.line_angle(Vector2(4, -4)), 45.0, 0.001, "inclinaison affichée 45°")
	assert_near(MapGeom.line_angle(Vector2(4, 4)), 45.0, 0.001, "45° dans l'autre sens")
	assert_near(MapGeom.line_angle(Vector2(0, 3)), 90.0, 0.001)
	assert_near(MapGeom.line_angle(Vector2(3, 1)), 18.43, 0.01, "angle libre")
	# Directions des objets muraux : degrés dans le sens horaire depuis le nord.
	assert_near(MapGeom.dir_deg(Vector2(0, -1)), 0.0, 0.001)
	assert_near(MapGeom.dir_deg(Vector2(1, 0)), 90.0, 0.001)
	assert_near(MapGeom.dir_deg(Vector2(1, -1).normalized()), 45.0, 0.001)
	assert_true(MapGeom.deg_dir(225.0).is_equal_approx(Vector2(-1, 1).normalized()), "225° -> sud-ouest")
	assert_eq(MapGeom.cardinal_of(Vector2(0.9, -0.3)), "e")
	# Rectangle tourné de 45° (outil Pièce rectangle + R) : sommets sur la grille.
	var q := MapCanvas.rect45_poly(Vector2(14, 18), Vector2(22, 18))
	assert_eq(q, PackedVector2Array([Vector2(14, 18), Vector2(18, 22), Vector2(22, 18), Vector2(18, 14)]), "losange")
	var b := MapCanvas.rect45_end(Vector2(0, 0), Vector2(3.5, 2.0))
	var q2 := MapCanvas.rect45_poly(Vector2(0, 0), b)
	for p in q2:
		assert_true(is_equal_approx(fposmod(p.x, 0.5), 0.0) or is_equal_approx(fposmod(p.x, 0.5), 0.5), "sommet x sur la grille : %s" % q2)
		assert_true(is_equal_approx(fposmod(p.y, 0.5), 0.0) or is_equal_approx(fposmod(p.y, 0.5), 0.5), "sommet y sur la grille : %s" % q2)
	assert_true(MapGeom.is_simple(q2) and MapGeom.has_oblique(q2), "rectangle à 45° : contour simple en biais")


# ------------------------------------------------------------------ murs

func test_shared_oblique_wall_is_single() -> void:
	var doc := diag_map()
	var v := MapRaster.build(doc).v
	var walls: Array = v.oblique_walls[0]
	var common := walls.filter(func(w): return w.kind == "piece" and w.pos != "" and w.neg != "")
	assert_eq(common.size(), 1, "un seul mur mitoyen en biais")
	var c: Dictionary = common[0]
	assert_true([c.pos, c.neg].has("p1") and [c.pos, c.neg].has("p2"), "une pièce de chaque côté : %s / %s" % [c.pos, c.neg])
	assert_true(c.a.distance_to(Vector2(14, 18)) < 0.01 and c.b.distance_to(Vector2(18, 14)) < 0.01, "de (14, 18) à (18, 14) : %s %s" % [c.a, c.b])
	# Côtés colinéaires : aucun doublon (7 côtés en biais pour 8 côtés en biais tracés).
	assert_eq(walls.filter(func(w): return w.kind == "piece").size(), 7, "4 côtés de l'octogone + 4 du losange, le bord commun une seule fois")
	assert_eq(walls.filter(func(w): return w.kind == "mur").size(), 1, "mur libre en biais")
	var f: MapValidator.Floor = v.floors[0]
	# Cases coupées par le mur (marquage prudent) : un mur continu, sol de chaque côté.
	for s in [0.5, 1.5, 2.5, 3.5]:
		var p: Vector2 = Vector2(14, 18) + Vector2(1, -1).normalized() * float(s) * sqrt(2.0)
		assert_eq(f.at(MapGeom.cell_of(p)), MapValidator.K.MUR if absf(s - 2.0) > 1.2 else MapValidator.K.PORTE, "trait du mur en %s" % p)
	assert_eq(f.at(MapGeom.cell_of(Vector2(15, 16))), MapValidator.K.SOL, "sol de l'octogone")
	assert_eq(f.at(MapGeom.cell_of(Vector2(16.5, 17.5))), MapValidator.K.SOL, "sol du losange")
	assert_true(f.zone_of(MapGeom.cell_of(Vector2(15, 16))) != f.zone_of(MapGeom.cell_of(Vector2(16.5, 17.5))), "deux zones")
	# Jamais de fuite en diagonale : les cases du mur se touchent par un côté.
	for key in v.diag_cells[0]:
		var cell: Vector2i = key
		var n := 0
		for d in MapValidator.DIRS:
			if v.diag_cells[0].has(cell + d) or f.at(cell + d) == MapValidator.K.MUR:
				n += 1
		assert_true(n >= 1, "case de mur isolée %s" % cell)
	# Un mur droit reste en blocs de la grille : seules les cases en biais en sortent.
	assert_false(v.diag_cells[0].has(MapGeom.cell_of(Vector2(10, 2))), "mur droit nord : grille")
	assert_true(v.diag_cells[0].has(MapGeom.cell_of(Vector2(16, 4))), "mur en biais nord-est : mur oblique")


func test_openings_on_oblique_walls() -> void:
	var doc := diag_map()
	doc.ouvertures.clear()
	doc.objets = doc.objets.filter(func(o): return o.type in ["mur", "depart"])
	# Porte : seulement sur le bord commun en biais.
	var r := MapRules.place_opening(doc, 0, "porte", Vector2(3.9, 4.1), 2.0)
	assert_false(r.ok, "porte refusée sur un mur extérieur en biais")
	r = MapRules.place_opening(doc, 0, "porte", Vector2(16.3, 16.1), 2.0)
	assert_true(r.ok and MapGeom.v2(r.position).is_equal_approx(Vector2(16, 16)), "porte sur le bord commun en biais : %s" % str(r))
	assert_eq(r.rooms, ["p1", "p2"], "elle relie les deux pièces")
	assert_true(r.has("dir") and absf(absf(r.dir[0]) - sqrt(0.5)) < 0.001, "orientée selon le mur")
	# Trop près d'un bout (0,5 m de mur plein) : le milieu est ramené.
	var e := MapRules.place_opening(doc, 0, "porte", Vector2(14.3, 17.7), 2.0)
	assert_true(e.ok and MapGeom.v2(e.position).distance_to(Vector2(14, 18)) >= 1.5 - 0.01, "0,5 m de mur au bout : %s" % str(e))
	assert_false(MapRules.place_opening(doc, 0, "porte", Vector2(16, 16), 5.0).ok, "mur trop court pour 5 m")
	doc.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": r.position, "largeur": 2.0, "prix": 750})
	assert_false(MapRules.place_opening(doc, 0, "debris", Vector2(15, 17), 1.0).ok, "0,5 m entre deux ouvertures")
	# Fenêtre : mur extérieur en biais, avec la cour dehors ; pas sur le mur commun.
	var w := MapRules.place_opening(doc, 0, "fenetre", Vector2(3.6, 3.7), 1.0)
	assert_true(w.ok and MapGeom.v2(w.position).is_equal_approx(Vector2(4, 4)), "fenêtre sur un mur extérieur en biais : %s" % str(w))
	assert_false(MapRules.place_opening(doc, 0, "fenetre", Vector2(16.4, 15.3), 1.0).ok, "pas de fenêtre sur le mur commun")
	var blocked := doc.duplicate_map()
	blocked.pieces.append({"id": "p9", "nom": "Dehors", "altitude": 0, "zone": "z1", "contour": [[0, 0], [3, 0], [3, 3], [0, 3]]})
	var wb := MapRules.place_opening(blocked, 0, "fenetre", Vector2(3.6, 3.7), 1.0)
	assert_false(wb.ok, "fenêtre refusée : pièce dans la cour des zombies")
	assert_true(String(wb.get("fr", "")).contains("pas de place dehors"), "raison : %s" % wb.get("fr", ""))
	doc.ouvertures.append({"id": "o2", "type": "fenetre", "altitude": 0, "position": w.position})
	# Objets muraux : contre un mur en biais, face vers l'intérieur (angle).
	var arm := MapRules.place_wall_item(doc, 0, {"type": "levier"}, Vector2(15.6, 4.3))
	assert_true(arm.ok and arm.has("angle") and absf(float(arm.angle) - 45.0) < 0.01 and arm.mur == "n", "levier : mur au nord-est (45°) : %s" % str(arm))
	var perk := MapRules.place_wall_item(doc, 0, {"type": "poste_central"}, Vector2(20.3, 16.4))
	assert_true(perk.ok and absf(float(perk.angle) - 45.0) < 0.01, "poste central dans le losange : %s" % str(perk))
	var box := MapRules.place_wall_item(doc, 0, {"type": "boite", "depart": false}, Vector2(4.3, 4.3))
	assert_false(box.ok, "boîte refusée devant la fenêtre en biais : %s" % str(box))
	var west := MapRules.place_wall_item(doc, 0, {"type": "courant"}, Vector2(3.3, 15.0))
	assert_true(west.ok and absf(float(west.angle) - 225.0) < 0.01 and west.mur in ["s", "o"], "courant contre le mur sud-ouest (225°) : %s" % str(west))
	var ax := MapRules.place_wall_item(doc, 0, {"type": "courant", "angle": 45.0}, Vector2(10, 2.6))
	assert_true(ax.ok and not ax.has("angle"), "mur droit : pas de clé angle")
	# Emprise tournée : à l'intérieur de la pièce, collée à la face du mur.
	var o := {"type": "poste_central", "position": perk.position, "mur": perk.mur, "angle": perk.angle}
	for c in MapRules.wall_item_poly(o):
		assert_true(MapGeom.contains(doc.room_poly(doc.pieces[1]), c) or MapGeom.on_boundary(doc.room_poly(doc.pieces[1]), c, 0.02), "emprise dans le losange")
	assert_true(MapRules.check_existing(doc, o.merged({"id": "a9", "altitude": 0})).ok, "objet posé toujours valide")


func test_validator_accepts_oblique_map() -> void:
	var v := _check(diag_map())
	assert_true(v.ok(), "carte à murs en biais jouable :\n" + _errs(v))
	assert_eq(v.doors.size(), 1)
	assert_true(v.doors[0].has("oblique") and v.doors[0].zones == ["a", "b"], "porte en biais entre les deux zones")
	assert_eq(v.windows.size(), 2)
	assert_true(v.windows.all(func(w): return w.has("oblique") and absf(Vector2(w.inward).length() - 1.0) < 0.001), "fenêtres en biais")
	var ww: Dictionary = v.windows.filter(func(w): return w.zone == "a")[0]
	assert_true(Vector2(ww.inward).is_equal_approx(Vector2(1, 1).normalized()), "fenêtre de l'octogone tournée vers l'intérieur : %s" % ww.inward)
	var items := v.wall_items.filter(func(it): return it.has("oblique"))
	assert_eq(items.size(), 2, "levier et interrupteur contre des murs en biais")
	# Refus : porte en biais entre deux pièces de la même zone.
	var same := diag_map()
	same.pieces[1]["zone"] = same.pieces[0].zone
	same.tidy_zones()
	var vs := _check(same)
	assert_true(_errs(vs).contains("même zone"), "porte en biais dans une même zone refusée :\n" + _errs(vs))
	# Refus : objet mural devant une ouverture en biais (placé à la main).
	var bad := diag_map()
	bad.objets.append({"id": "g1", "type": "levier", "altitude": 0, "position": [4.0, 4.0], "mur": "n", "angle": 315.0})
	var vb := _check(bad)
	assert_false(vb.ok(), "levier collé à la fenêtre en biais refusé")


# ------------------------------------------------------------------ jeu : sol, murs, collisions

func test_floor_follows_the_true_outline() -> void:
	# Triangulation d'un contour concave avec un côté en biais.
	var concave := PackedVector2Array([Vector2(0, 0), Vector2(8, 0), Vector2(8, 8), Vector2(4, 4), Vector2(0, 8)])
	var tris := MapGeom.triangulate(concave)
	var s := 0.0
	for t in tris:
		s += MapGeom.area(PackedVector2Array(t))
	assert_eq(tris.size(), 3, "3 triangles")
	assert_near(s, MapGeom.area(concave), 0.001, "les triangles couvrent exactement le contour concave")
	# Sol construit par le jeu : rectangles de cases + morceaux découpés selon le
	# vrai contour = exactement la surface de la pièce (sans marches).
	var doc := diag_map()
	doc.objets = doc.objets.filter(func(o): return o.type != "mur")
	var v := _check(doc)
	assert_true(v.ok(), _errs(v))
	var L := MapLayoutExport.build(v)
	var octo := doc.room_poly(doc.pieces[0]).duplicate()
	var floors := []
	var inside_total := 0.0
	for r in L.rooms:
		if String(r.id).begins_with("dehors") or String(r.id).begins_with("porte"):
			continue
		var p := PackedVector2Array()
		for q in r.outline:
			p.append(Vector2(q[0], q[1]) - Vector2.ONE * MapGeom.WORLD_OFFSET)
		floors.append(p)
		for part in Geometry2D.intersect_polygons(p, octo):
			inside_total += MapGeom.area(part)
	# Le long des murs droits, le sol s'arrête à la face du mur (0,25 m) comme
	# avant ; le long des murs en biais, il va jusqu'au trait (sous le mur).
	var axis_len := 0.0
	for i in octo.size():
		if MapGeom.is_axis_seg(octo[i], octo[(i + 1) % octo.size()]):
			axis_len += octo[i].distance_to(octo[(i + 1) % octo.size()])
	var expected := MapGeom.area(octo) - axis_len * MapGeom.WALL_HALF
	assert_near(inside_total, expected, 0.6, "sol de l'octogone (%.2f m² pour %.2f)" % [inside_total, expected])
	# Aucune marche : chaque point à 0,3 m d'un côté en biais (devant la face du
	# mur) est sur le sol, tout du long.
	for i in octo.size():
		var a := octo[i]
		var b := octo[(i + 1) % octo.size()]
		if MapGeom.is_axis_seg(a, b):
			continue
		var t := (b - a).normalized()
		var inward := Vector2(-t.y, t.x)
		if not MapGeom.contains(octo, (a + b) * 0.5 + inward * 0.3):
			inward = -inward
		for k in range(1, 20):
			var q := a.lerp(b, k / 20.0) + inward * 0.3
			assert_true(floors.any(func(fp): return MapGeom.contains(fp, q) or MapGeom.on_boundary(fp, q, 0.001)), "trou dans le sol le long du mur en biais en %s" % q)
	assert_true(L.rooms.any(func(r): return String(r.id).begins_with("biais_")), "morceaux de sol le long des murs en biais")
	# Aucun bloc de la grille sur un mur en biais.
	for bl in L.blocks:
		var b: Array = bl.box
		var c := Vector2((b[0] + b[3]) * 0.5, (b[2] + b[5]) * 0.5) - Vector2.ONE * MapGeom.WORLD_OFFSET
		assert_false(v.diag_cells[0].has(MapGeom.cell_of(c)), "bloc en escalier sur un mur en biais en %s" % c)
	# Murs obliques : une texture par face (brique côté losange, plâtre côté octogone).
	var obl: Array = L.get("obliques", [])
	assert_true(obl.size() >= 7, "murs obliques décrits (%d)" % obl.size())
	var shared := obl.filter(func(o): return String(o.mat_n) != String(o.mat_m))
	assert_eq(shared.size(), 1, "mur mitoyen : deux textures")
	assert_true([shared[0].mat_n, shared[0].mat_m].has("brick"), "brique côté losange")
	assert_eq(shared[0].openings.size(), 1, "porte découpée dans le mur mitoyen")
	assert_true(obl.any(func(o): return o.get("joint", false)), "raccords aux pointes du losange")
	var wins := obl.filter(func(o): return o.openings.any(func(c): return absf(float(c.y0) - MapValidator.SILL) < 0.001))
	assert_eq(wins.size(), 2, "fenêtres : allège et linteau dans le mur oblique")


func test_oblique_collisions_block_rays_and_bodies() -> void:
	var v := _check(diag_map())
	var L := MapLayoutExport.build(v)
	var arch := MeshMapGeometry.build(L)
	var world := Node3D.new()
	host.add_child(world)
	world.add_child(arch)
	var boxes := arch.find_children("Biais_*", "CollisionBox", false, false)
	assert_true(boxes.size() >= 8, "pavés CollisionBox (%d)" % boxes.size())
	for b in boxes:
		assert_false(b.get_children().any(func(c): return c is MeshInstance3D), "collision sans maillage (jamais un modèle Blender)")
	await wait_frames(2)
	await host.get_tree().physics_frame
	var off := MapGeom.WORLD_OFFSET
	var space := world.get_world_3d().direct_space_state
	# Rayon (balle) à travers le mur libre en biais : arrêté sur sa face.
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off + 8, 1.2, off + 8), Vector3(off + 12, 1.2, off + 12), 1))
	assert_true(not hit.is_empty() and hit.collider is CollisionBox, "rayon arrêté par une CollisionBox")
	if not hit.is_empty():
		assert_near(hit.position.x + hit.position.z - 2.0 * off, 20.0 - MapGeom.WALL_HALF * sqrt(2.0), 0.02, "sur la vraie face du mur")
	# Rayon vers l'extérieur par le mur nord-est de l'octogone.
	var out := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off + 14, 1.5, off + 6), Vector3(off + 19, 1.5, off + 1), 1))
	assert_false(out.is_empty(), "le mur extérieur en biais arrête le rayon")
	# Rayon par la fenêtre (entre l'allège et le linteau) : il passe.
	var through := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off + 5, 1.6, off + 5), Vector3(off + 3, 1.6, off + 3), 1))
	assert_true(through.is_empty(), "la fenêtre est ouverte dans le mur oblique : %s" % str(through.get("position", "")))
	# Un corps (joueur) poussé contre le mur ne le traverse pas.
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.95
	body.add_child(cs)
	world.add_child(body)
	body.global_position = Vector3(off + 9, 0.05, off + 9)
	await host.get_tree().physics_frame
	for i in 60:
		body.move_and_collide(Vector3(1, 0, 1).normalized() * 0.1)
	var e := Vector2(body.global_position.x, body.global_position.z) - Vector2.ONE * off
	assert_true(e.x + e.y < 20.0 - MapGeom.WALL_HALF * sqrt(2.0) - 0.4 * sqrt(2.0) + 0.05, "le corps bute sur le mur (x + y = %.2f)" % (e.x + e.y))
	world.queue_free()
	await wait_frames(1)


func test_navigation_goes_around_and_through_oblique_door() -> void:
	var v := _check(diag_map())
	var L := MapLayoutExport.build(v)
	var world := Node3D.new()
	host.add_child(world)
	world.add_child(MeshMapGeometry.build(L))
	await host.get_tree().physics_frame
	var nav := MeshNav.new()
	nav.setup(world)
	nav.bake()
	# Le serveur de navigation prend la nouvelle région en compte au fil des images.
	for i in 20:
		await host.get_tree().process_frame
	NavigationServer3D.map_force_update(nav.map)
	var off := MapGeom.WORLD_OFFSET
	var w0 := Vector2(8, 12)
	var w1 := Vector2(12, 8)
	# Derrière le mur libre en biais : le chemin le contourne, jamais au travers.
	var path := nav.find_path(Vector3(off + 7, 0, off + 7), Vector3(off + 12.5, 0, off + 12.5))
	assert_true(path.size() >= 3, "chemin trouvé, avec un détour (%d points)" % path.size())
	for i in path.size() - 1:
		var a := Vector2(path[i].x, path[i].z) - Vector2.ONE * off
		var b := Vector2(path[i + 1].x, path[i + 1].z) - Vector2.ONE * off
		assert_true(Geometry2D.segment_intersects_segment(a, b, w0, w1) == null, "le chemin traverse le mur en biais entre %s et %s" % [a, b])
		assert_true(MapGeom.dist_to_segment(a, w0, w1) > MapGeom.WALL_HALF, "point du chemin dans le mur : %s" % a)
	assert_false(nav.world_line_clear(Vector3(off + 8, 0, off + 8), Vector3(off + 12, 0, off + 12)), "pas de ligne de vue à travers le mur")
	# Porte en biais ouverte (sans battant) : le losange est atteint par elle.
	var to_b := nav.find_path(Vector3(off + 12, 0, off + 13), Vector3(off + 19.5, 0, off + 18))
	assert_false(to_b.is_empty(), "le losange est atteint par la porte en biais")
	var by_door := false
	for p in to_b:
		if Vector2(p.x, p.z).distance_to(Vector2(16, 16) + Vector2.ONE * off) < 1.2:
			by_door = true
	assert_true(by_door, "le chemin passe par la porte : %s" % str(to_b))
	nav.region.queue_free()
	world.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ format

func test_save_reload_format_3() -> void:
	var doc := diag_map()
	var dir := ProjectSettings.globalize_path(TMP + "/biais")
	assert_eq(doc.save_dir(dir), OK)
	var t := doc.file_texts()
	assert_true(String(t["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT), "format courant (%d)" % EditorMap.FORMAT)
	assert_true(String(t["objets.json"]).contains("\"angle\":45"), "clé angle des objets muraux en biais")
	assert_false(String(t["objets.json"]).contains("\"angle\":0"), "pas d'angle sur un mur droit")
	var back := EditorMap.load_dir(dir)
	assert_true(back.load_errors.is_empty() and back.same_as(doc), "relue à l'identique")
	assert_true(_check(back).ok(), "toujours jouable")
	# Rotation de 90° (R) : l'angle tourne avec la pièce.
	var o := {"type": "courant", "position": [20.25, 16.25], "mur": "n", "angle": 45.0}
	var r := MapEditor._rot(o, Vector2(18, 18))
	assert_near(float(r.angle), 135.0, 0.001, "angle + 90°")
	# Angle non fini ou d'un autre type dans un fichier écrit à la main : ignoré.
	var texts := doc.file_texts()
	texts["objets.json"] = String(texts["objets.json"]).replace("\"angle\":45", "\"angle\":\"nord\"")
	var m := EditorMap.from_texts(texts)
	assert_false(m.objets.any(func(q): return q.has("angle") and not q.angle is float), "angle illisible retiré")


func test_previous_formats_are_read() -> void:
	# Format 2 écrit à la main : pièce polygone avec un côté en biais, sans angle.
	var doc := diag_map()
	var texts := doc.file_texts()
	texts = load("res://tests/test_levels_migration.gd").as_format(texts, 2)
	var m := EditorMap.from_texts(texts)
	assert_true(m.load_errors.is_empty() and m.format_read == 2, "format 2 lu tel quel")
	assert_true(_check(m).ok(), "carte du format 2 jouable")
	assert_true(m.file_texts()["carte.json"].contains("\"format\": %d" % EditorMap.FORMAT), "réenregistrée au format courant")
	# Format plus récent que le jeu : signalé.
	texts["carte.json"] = String(texts["carte.json"]).replace("\"format\": 2", "\"format\": %d" % (EditorMap.FORMAT + 1))
	assert_false(EditorMap.from_texts(texts).load_errors.is_empty(), "format plus récent signalé")
	# DRAFT ARENA (format 1, murs droits) : aucune case en biais, rien d'oblique.
	var draft := EditorMap.load_dir("res://tests/fixtures/maps/legacy_draft_arena/")
	assert_eq(draft.format_read, 1)
	var v := _check(draft)
	assert_true(v.ok(), _errs(v))
	assert_true(v.diag_cells.all(func(d): return d.is_empty()) and v.oblique_walls.all(func(w): return w.is_empty()), "DRAFT ARENA : aucun mur en biais")
	assert_false(MapLayoutExport.build(v).has("obliques"), "description en maillage inchangée (pas de clé obliques)")
