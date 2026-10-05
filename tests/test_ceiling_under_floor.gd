extends TestCase
## Plafond sous une pièce de l'étage du dessus (cartes de l'éditeur) : vu
## d'en bas, la pièce du rez-de-chaussée montre SA texture de plafond (pas le
## sol de la pièce du dessus) ; vu d'en haut, la pièce de l'étage montre son
## sol. Rayons « géométriques » sur les maillages construits par le jeu
## (MapLayoutExport -> MeshMapGeometry), comme en jeu et dans l'aperçu.

const OFF := MapGeom.WORLD_OFFSET


## Carte de test à deux étages : pièce basse (zone A, sol carrelé, plafond
## par défaut ou `ceil_a`) de 10 x 8 m, pièce haute (zone B, sol en bois) au-dessus de sa moitié ouest.
static func _two_floors(ceil_a := "", double_h := false) -> EditorMap:
	var doc := EditorMap.blank("plafond_etage", "PLAFOND", "CEILING")
	var za := doc.add_zone("A", "A")
	za["sol"] = "tiles"
	if ceil_a != "":
		za["plafond"] = ceil_a
	var zb := doc.add_zone("B", "B")
	zb["sol"] = "wood"
	var p1 := {"id": "p1", "nom": "Bas", "altitude": 0, "zone": String(za.id), "contour": [[0, 0], [10, 0], [10, 8], [0, 8]]}
	if double_h:
		# Pièce haute (l'ancienne double hauteur) : jusqu'en haut du niveau 3,5 m.
		p1["plafond"] = 6.5
	doc.pieces.append(p1)
	doc.pieces.append({"id": "p2", "nom": "Haut", "altitude": 3.5, "plafond": 3.0, "zone": String(zb.id), "contour": [[0, 0], [5, 0], [5, 8], [0, 8]]})
	return doc


static func _geometry(doc: EditorMap) -> Node3D:
	# Même chemin que l'aperçu 3D (et, pour la géométrie, que TESTER).
	return MeshMapGeometry.build(MapPreviewWorld.compute(doc).data)


## Première face VISIBLE (faces avant, Godot : sens horaire) touchée par un
## rayon vertical partant de `from` (vers le haut si `up`) : {name, y, p, d, tie}.
static func _hit(root: Node3D, from: Vector3, up: bool) -> Dictionary:
	return _ray(root, from, Vector3.UP if up else Vector3.DOWN)


## Même chose dans une direction quelconque. `tie` : une autre face visible
## (autre nœud) à moins de 2 mm de la première (z-fighting).
static func _ray(root: Node3D, from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var hits := []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() and mi.is_inside_tree():
			continue
		var faces := mi.mesh.get_faces()
		var xf := mi.global_transform if mi.is_inside_tree() else mi.transform
		for i in range(0, faces.size(), 3):
			var a := xf * faces[i]
			var b := xf * faces[i + 1]
			var c := xf * faces[i + 2]
			# Face avant (MeshMapGeometry._tri) : sa normale vaut -nrm, elle doit
			# faire face au rayon (sinon elle est éliminée, faces arrière).
			var nrm := (b - a).cross(c - a)
			if nrm.dot(dir) < 0.0:
				continue
			var p = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
			if p == null:
				continue
			var d := from.distance_to(p)
			hits.append([d, String(mi.name)])
			if best.is_empty() or d < float(best.d) - 0.0005:
				best = {"name": String(mi.name), "y": (p as Vector3).y, "p": p, "d": d}
	if not best.is_empty():
		best["tie"] = ""
		for h in hits:
			if String(h[1]) != String(best.name) and absf(float(h[0]) - float(best.d)) < 0.002:
				best["tie"] = String(h[1])
	return best


func _mat(hit: Dictionary) -> String:
	return String(hit.get("name", "")).split("__")[0]


func _kind(hit: Dictionary) -> String:
	var parts := String(hit.get("name", "")).split("__")
	return parts[2] if parts.size() > 2 else ""


func test_default_ceiling_under_the_room_above() -> void:
	var root := _geometry(_two_floors())
	# Sous la pièce de l'étage 1 : le plafond (matériau par défaut) de la pièce du bas.
	var h := _hit(root, Vector3(2 + OFF, 1.6, 4 + OFF), true)
	assert_false(h.is_empty(), "une face au-dessus de la tête")
	assert_eq(_kind(h), "ceil", "vu d'en bas : un plafond (%s)" % h.get("name"))
	assert_eq(_mat(h), "ceiling", "texture de plafond de la pièce du bas")
	assert_near(float(h.y), 3.5 - MapValidator.DALLE, 0.03, "sous la dalle")
	assert_eq(String(h.tie), "", "sans z-fighting avec le dessous de la dalle (%s)" % h.tie)
	# Vu d'en haut : le sol en bois de la pièce de l'étage.
	var t := _hit(root, Vector3(2 + OFF, 5.0, 4 + OFF), false)
	assert_eq(_kind(t), "floor", "vu d'en haut : le sol (%s)" % t.get("name"))
	assert_eq(_mat(t), "wood")
	assert_near(float(t.y), 3.5, 0.001)
	# Hors de la pièce du dessus : le plafond de la pièce, à sa hauteur.
	var o := _hit(root, Vector3(8 + OFF, 1.6, 4 + OFF), true)
	assert_eq(_kind(o), "ceil")
	assert_eq(_mat(o), "ceiling")
	assert_near(float(o.y), 3.2, 0.001)
	root.free()


func test_chosen_ceiling_under_the_room_above() -> void:
	var root := _geometry(_two_floors("ceiling_theater"))
	var h := _hit(root, Vector3(2 + OFF, 1.6, 4 + OFF), true)
	assert_eq(_kind(h), "ceil", "vu d'en bas : %s" % h.get("name"))
	assert_eq(_mat(h), "ceiling_theater", "texture de plafond choisie pour la zone")
	var t := _hit(root, Vector3(2 + OFF, 5.0, 4 + OFF), false)
	assert_eq(_mat(t), "wood")
	root.free()


func test_double_height_room_under_a_catwalk() -> void:
	# Pièce en double hauteur sous une passerelle (comme l'entrepôt de DRAFT ARENA).
	var root := _geometry(_two_floors("", true))
	var h := _hit(root, Vector3(2 + OFF, 1.6, 4 + OFF), true)
	assert_eq(_kind(h), "ceil", "sous la passerelle : %s" % h.get("name"))
	assert_eq(_mat(h), "ceiling")
	var t := _hit(root, Vector3(2 + OFF, 5.0, 4 + OFF), false)
	assert_eq(_mat(t), "wood")
	assert_near(float(t.y), 3.5, 0.001)
	root.free()


func test_draft_arena_catwalk_underside() -> void:
	var doc := EditorMap.load_dir("res://assets/maps/draft_arena/")
	var root := _geometry(doc)
	# Entrepôt (p3) sous la passerelle (p5, 2,5-7,5 x 4,5-9,5).
	var h := _hit(root, Vector3(5 + OFF, 1.6, 7 + OFF), true)
	assert_eq(_kind(h), "ceil", "sous la passerelle : %s" % h.get("name"))
	assert_eq(_mat(h), "ceiling")
	assert_near(float(h.y), 3.5 - MapValidator.DALLE, 0.03)
	var t := _hit(root, Vector3(5 + OFF, 5.0, 7 + OFF), false)
	assert_eq(_mat(t), "wood", "dessus de la passerelle : %s" % t.get("name"))
	root.free()


# ------------------------------------------------------------------ passages entre pièces de hauteurs différentes

## Un étage : pièce A (0-6 x 0-8, plafond 4,5 m, murs en brique) et pièce B
## (6-12 x 0-8, plafond de l'étage 3,2 m, murs verts), mur commun x = 6 :
## passage libre de 2 m centré en z = 5,5 et porte de 2 m centrée en z = 1,5.
static func _two_heights() -> EditorMap:
	var doc := EditorMap.blank("passage_hauteurs", "PASSAGE", "PASSAGE")
	var za := doc.add_zone("A", "A")
	za["murs"] = "brick"
	var zb := doc.add_zone("B", "B")
	zb["murs"] = "wall_green"
	doc.pieces.append({"id": "p1", "nom": "Haute", "altitude": 0, "zone": String(za.id), "plafond": 4.5, "contour": [[0, 0], [6, 0], [6, 8], [0, 8]]})
	doc.pieces.append({"id": "p2", "nom": "Basse", "altitude": 0, "zone": String(zb.id), "contour": [[6, 0], [12, 0], [12, 8], [6, 8]]})
	doc.ouvertures.append({"id": "o1", "type": "passage", "altitude": 0, "position": [6.0, 5.5], "largeur": 2.0})
	doc.ouvertures.append({"id": "o2", "type": "porte", "altitude": 0, "position": [6.0, 1.5], "largeur": 2.0, "prix": 750})
	return doc


func test_passage_opens_up_to_the_lower_ceiling() -> void:
	var doc := _two_heights()
	var root := _geometry(doc)
	# Au milieu du passage, en regardant vers le haut : le dessous du linteau
	# à la hauteur du plafond le plus BAS (3,2 m), pas un trou jusqu'à 4,5 m.
	var h := _hit(root, Vector3(6.1 + OFF, 1.6, 5.3 + OFF), true)
	assert_false(h.is_empty(), "une face au-dessus du passage")
	assert_near(float(h.get("y", 0.0)), 3.2, 0.02, "passage ouvert jusqu'au plafond le plus bas (%s)" % h.get("name"))
	assert_eq(String(h.get("tie", "")), "", "sans z-fighting (%s / %s)" % [h.get("name"), h.get("tie")])
	# Dans la pièce haute, à 4 m (au-dessus du plafond de la pièce basse) : le
	# mur au-dessus du passage, avec la texture de la pièce haute, côté A.
	var a := _ray(root, Vector3(3 + OFF, 4.0, 5.5 + OFF), Vector3.RIGHT)
	assert_false(a.is_empty(), "mur au-dessus du passage, vu de la pièce haute")
	assert_near(float((a.get("p", Vector3.ZERO) as Vector3).x - OFF), 6.0 - MapGeom.WALL_HALF, 0.02, "dans le plan du mur (%s)" % a.get("name"))
	assert_eq(_mat(a), "brick", "texture de mur de la pièce haute")
	assert_eq(String(a.get("tie", "")), "")
	# Côté pièce basse, entre le dessous de la retombée et son plafond : la
	# retombée avec SA texture.
	var b := _ray(root, Vector3(9 + OFF, 3.195, 5.5 + OFF), Vector3.LEFT)
	assert_near(float((b.get("p", Vector3.ZERO) as Vector3).x - OFF), 6.0 + MapGeom.WALL_HALF, 0.02, "linteau côté B (%s)" % b.get("name"))
	assert_eq(_mat(b), "wall_green", "texture de mur de la pièce basse")
	# Porte sur le même mur : ouverte jusqu'à hauteur_portes, mur au-dessus.
	var d := _hit(root, Vector3(6 + OFF, 1.6, 1.5 + OFF), true)
	assert_near(float(d.get("y", 0.0)), doc.carte.get("hauteur_portes", MapValidator.DOOR_HEIGHT), 0.02, "porte : linteau (%s)" % d.get("name"))
	var da := _ray(root, Vector3(3 + OFF, 4.0, 1.5 + OFF), Vector3.RIGHT)
	assert_eq(_mat(da), "brick", "au-dessus de la porte, côté pièce haute (%s)" % da.get("name"))
	# Vues de côté de l'éditeur : le passage s'arrête au même plafond.
	var v := MapRaster.build(doc).v
	assert_near(MapVertical.ceil_z(v, 0, Vector2(6.0, 5.5)), 3.2, 0.001, "élévation : haut du passage")
	root.free()


# ------------------------------------------------------------------ escalier sous une pièce à plafond réglé

## Deux étages ; escalier du rez-de-chaussée (1-3,5 x 3-9,5, monte au nord)
## vers une pièce de l'étage 1 au plafond réglé à 5 m (au lieu de 3 m).
static func _stairs_high_room(plafond := 5.0) -> EditorMap:
	var doc := EditorMap.blank("escalier_haut", "ESCALIER", "STAIRS")
	var za := doc.add_zone("A", "A")
	doc.pieces.append({"id": "p1", "nom": "Bas", "altitude": 0, "zone": String(za.id), "contour": [[0, 0], [12, 0], [12, 10], [0, 10]]})
	var p2 := {"id": "p2", "nom": "Haut", "altitude": 3.5, "plafond": 3.0, "zone": String(za.id), "contour": [[0, 0], [12, 0], [12, 10], [0, 10]]}
	if plafond > 0.0:
		p2["plafond"] = plafond
	doc.pieces.append(p2)
	doc.objets.append({"id": "x1", "type": "escalier", "altitude": 0, "rect": [1.0, 3.0, 3.5, 9.5], "monte": "n"})
	return doc


func test_ceiling_above_stairs_follows_the_room_height() -> void:
	var doc := _stairs_high_room()
	var root := _geometry(doc)
	var top := 3.5 + 5.0
	# Au-dessus de la trémie de l'escalier, à l'étage 1 : le plafond de la pièce (8,5 m).
	var h := _hit(root, Vector3(2.25 + OFF, 4.5, 6 + OFF), true)
	assert_eq(_kind(h), "ceil", "au-dessus de l'escalier : %s" % h.get("name"))
	assert_near(float(h.get("y", 0.0)), top, 0.02, "plafond réglé de la pièce, pas un faux plafond plus bas")
	# Depuis les marches (rez-de-chaussée), droit vers le haut : le même plafond.
	var s := _hit(root, Vector3(2.25 + OFF, 2.0, 5 + OFF), true)
	assert_near(float(s.get("y", 0.0)), top, 0.02, "trémie ouverte jusqu'au plafond de la pièce du dessus (%s)" % s.get("name"))
	# Ailleurs dans la pièce : même hauteur.
	var o := _hit(root, Vector3(8 + OFF, 4.5, 5 + OFF), true)
	assert_near(float(o.get("y", 0.0)), top, 0.02)
	var v := MapRaster.build(doc).v
	assert_near(MapVertical.ceil_z(v, 1, Vector2(2.25, 6.0)), top, 0.001, "élévation : plafond au-dessus de l'escalier")
	root.free()
	# Sans plafond réglé : celui de l'étage (6,5 m), trémie comprise.
	var root2 := _geometry(_stairs_high_room(0.0))
	assert_near(float(_hit(root2, Vector3(2.25 + OFF, 4.5, 6 + OFF), true).get("y", 0.0)), 6.5, 0.02)
	root2.free()


func test_draft_arena_passage_under_the_floor_above() -> void:
	# Passage o4 (x = 11,75, mur z = 17) de l'atelier (3,2 m) vers l'entrepôt en
	# double hauteur : sous l'étage 1 (mur de la trémie au-dessus), ouvert
	# jusqu'au dessous de la dalle, et au-dessus un seul mur (pas deux murs
	# l'un dans l'autre).
	var root := _geometry(EditorMap.load_dir("res://assets/maps/draft_arena/"))
	var h := _hit(root, Vector3(11.6 + OFF, 1.6, 17.0 + OFF), true)
	assert_near(float(h.get("y", 0.0)), 3.5 - MapValidator.DALLE, 0.02, "haut du passage (%s)" % h.get("name"))
	for y in [3.6, 4.5, 6.0]:
		var w := _ray(root, Vector3(11.6 + OFF, y, 12.0 + OFF), Vector3.BACK)
		assert_near(float((w.get("p", Vector3.ZERO) as Vector3).z - OFF), 17.0 - MapGeom.WALL_HALF, 0.02, "mur au-dessus du passage à %.1f m (%s)" % [y, w.get("name")])
		assert_eq(String(w.get("tie", "")), "", "sans z-fighting à %.1f m (%s / %s)" % [y, w.get("name"), w.get("tie")])
	root.free()
