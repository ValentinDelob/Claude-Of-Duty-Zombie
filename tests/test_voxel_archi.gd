extends TestCase
## Architecture CUBIQUE (pilote, docs/VOXEL_ARCHITECTURE_PLAN.md) : textures
## pixel art générées (un pixel = 5 cm, mêmes clés que WorldLook.SURFACES,
## déterministes, palette du décor) et murs en biais rendus en escalier de
## cubes de 5 cm (faces axiales, sommets sur la grille du monde, faces des
## deux côtés au bon matériau), collision lisse inchangée.

const Diag := preload("res://tests/test_map_editor_diagonal.gd")


func test_pixel_surfaces_replace_pilot_keys() -> void:
	for key: String in PixelSurfaces.DEFS:
		assert_true(WorldLook.SURFACES.has(key), "clé existante (%s) : les cartes se chargent telles quelles" % key)
		var m := WorldLook.surface(key)
		assert_eq(m.shader, PixelSurfaces.SHADER, "%s : surface pixel art" % key)
		var img := PixelSurfaces.image(key)
		var d: Dictionary = PixelSurfaces.DEFS[key]
		assert_eq(img.get_size(), Vector2i(int(d.w), int(d.h)), "%s : taille de l'image" % key)
		assert_true(int(d.wrap) >= 0 and int(d.wrap) < int(d.h), "%s : lignes répétées dans l'image" % key)
	# Clé non convertie : surface procédurale d'avant (lots suivants).
	assert_eq(WorldLook.surface("metal").shader, WorldLook.SURFACE, "tôle : pas encore convertie")


func test_pixel_surfaces_are_deterministic() -> void:
	for key: String in PixelSurfaces.DEFS:
		var a := PixelSurfaces.image(key).get_data()
		PixelSurfaces._images.erase(key)
		var t0 := Time.get_ticks_usec()
		var b := PixelSurfaces.image(key).get_data()
		print("[voxel_archi] texture %s : %.1f ms" % [key, (Time.get_ticks_usec() - t0) / 1000.0])
		assert_eq(a, b, "%s : même image à chaque génération" % key)


func test_painted_wall_band_and_grime() -> void:
	var img := PixelSurfaces.image("wall")
	# Soubassement (ligne 10) plus vert que le plâtre du haut (ligne 40).
	var green_lo := 0.0
	var green_hi := 0.0
	for x in img.get_width():
		green_lo += img.get_pixel(x, 12).g - img.get_pixel(x, 12).r
		green_hi += img.get_pixel(x, 40).g - img.get_pixel(x, 40).r
	assert_true(green_lo > green_hi + 0.5, "soubassement vert d'eau, plâtre au-dessus (%.2f / %.2f)" % [green_lo, green_hi])
	# Crasse au pied du mur : la ligne 0 est plus sombre que la ligne 12.
	var dark := 0.0
	var mid := 0.0
	for x in img.get_width():
		dark += img.get_pixel(x, 0).get_luminance()
		mid += img.get_pixel(x, 12).get_luminance()
	assert_true(dark < mid * 0.8, "pied du mur assombri")


## Sommets visibles des murs en biais : faces axiales, x et z sur la grille de
## 5 cm du monde.
func test_oblique_walls_are_stepped_cubes() -> void:
	var v := Diag._check(Diag.diag_map())
	var L := MapLayoutExport.build(v)
	var arch := MeshMapGeometry.build(L)
	var walls := arch.find_children("*__biais", "MeshInstance3D", true, false)
	assert_true(walls.size() >= 1, "maillages des murs en biais (%d)" % walls.size())
	var tris := 0
	var bad := 0
	var off_grid := 0
	for mi: MeshInstance3D in walls:
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		tris += vs.size() / 3
		# Faces géométriques axiales (la normale d'éclairage peut pencher :
		# MeshMapGeometry.step_shade).
		for i in range(0, vs.size(), 3):
			var n := (vs[i + 1] - vs[i]).cross(vs[i + 2] - vs[i]).normalized()
			if maxf(absf(n.x), maxf(absf(n.y), absf(n.z))) < 0.9999:
				bad += 1
		for i in vs.size():
			var p := mi.transform * vs[i]
			if not (VoxelCheck.on_grid(p.x, 0.05) and VoxelCheck.on_grid(p.z, 0.05)):
				off_grid += 1
	assert_eq(bad, 0, "faces axiales seulement")
	assert_eq(off_grid, 0, "sommets sur la grille de 5 cm")
	# Coût : avant, un pavé tourné (12 triangles) par morceau de mur.
	var pieces := 0
	for w in L.obliques:
		var length := Vector2(w.a[0], w.a[1]).distance_to(Vector2(w.b[0], w.b[1]))
		pieces += MeshMapGeometry.wall_pieces(0.0, length, float(w.y0), float(w.y1), w.get("openings", [])).size()
	print("[voxel_archi] murs en biais : %d maillages, %d triangles (avant : %d morceaux, %d triangles)" % [walls.size(), tris, pieces, pieces * 12])
	# Mur mitoyen : brique côté losange, mur peint côté octogone (deux maillages).
	assert_true(walls.any(func(m): return String(m.name).begins_with("brick__")), "face brique du mur mitoyen")
	# Collision : toujours les pavés lisses tournés.
	assert_true(arch.find_children("Biais_*", "CollisionBox", false, false).size() >= 8, "collisions CollisionBox inchangées")
	arch.free()


## Mur libre à 45° : chaque rangée de cellules d'un mur plein est d'un seul
## tenant, l'escalier suit le mur à moins d'une demi-diagonale de cube.
func test_stepped_piece_follows_the_wall() -> void:
	var grain0 := MeshMapGeometry.step_grain
	MeshMapGeometry.step_grain = 1
	var g := MeshMapGeometry.new()
	var gn := g._group("wall", "x")
	var gm := g._group("brick", "x")
	var a := Vector3(1.0, 0, 1.0)
	var d := Vector3(1, 0, 1).normalized()
	var rows := g._stepped_piece(gn, gm, a, d, 0.0, 4.0, 0.5, 0.0, 3.0)
	assert_true(rows > 40 and rows < 80, "rangées de 5 cm (%d)" % rows)
	# Escalier à 45° : pas plus d'une demi-diagonale de cube hors du pavé.
	var u := Vector3(-d.z, 0, d.x)
	for p: Vector3 in gn.v + gm.v:
		var k := absf((p - a).dot(u))
		assert_true(k <= 0.25 + 0.036, "sommet à %.3f m du plan du mur (≤ épaisseur/2 + 3,5 cm)" % k)
	# Faces des deux côtés : normale vers +u -> gn, vers -u -> gm.
	for i in range(0, gm.n.size(), 3):
		assert_true(gm.n[i].dot(u) < 0.0, "face de l'autre côté au second matériau")
	# Marche de 10 cm : deux fois moins de rangées, sommets toujours sur 5 cm.
	MeshMapGeometry.step_grain = 2
	var g2 := MeshMapGeometry.new()
	var rows2 := g2._stepped_piece(g2._group("wall", "x"), g2._group("brick", "x"), a, d, 0.0, 4.0, 0.5, 0.0, 3.0)
	MeshMapGeometry.step_grain = grain0
	assert_eq(grain0, 2, "marche de 10 cm par défaut")
	assert_true(absi(rows2 * 2 - rows) <= 2, "marche de 10 cm : %d rangées au lieu de %d" % [rows2, rows])
