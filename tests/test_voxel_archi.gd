extends TestCase
## Architecture CUBIQUE (docs/VOXEL_ARCHITECTURE_PLAN.md) : textures pixel
## art générées de TOUTES les surfaces (lot C : un pixel = 5 cm, mêmes clés
## que WorldLook.SURFACES, déterministes, palette du décor égale à
## voxel_lib.DECOR_PALETTE, textures importées réduites à 20 pixels par
## mètre, planche, vignettes de l'éditeur) et murs en biais rendus en escalier
## de cubes de 5 cm (faces axiales, sommets sur la grille du monde, faces des
## deux côtés au bon matériau), collision lisse inchangée.

const Diag := preload("res://tests/test_map_editor_diagonal.gd")
const Free := preload("res://tests/test_map_editor_freeform.gd")
const Walls := preload("res://tests/test_map_editor_walls.gd")


func test_every_surface_key_is_pixel_art() -> void:
	for key: String in WorldLook.SURFACES:
		assert_true(PixelSurfaces.has(key), "clé existante (%s) : texture pixel art" % key)
		var m := WorldLook.surface(key)
		assert_eq(m.shader, PixelSurfaces.shader_for(key), "%s : surface pixel art" % key)
		assert_true(m.shader.code.contains("filter_nearest_mipmap"), "%s : filtrage au plus proche" % key)
		var img := PixelSurfaces.image(key)
		assert_eq(img.get_size(), Vector2i(PixelSurfaces.SIZE, PixelSurfaces.SIZE), "%s : 64 × 64 px (3,2 m)" % key)
		var d := PixelSurfaces.def(key)
		assert_true(int(d.wrap) >= 0 and int(d.wrap) < PixelSurfaces.SIZE, "%s : lignes répétées dans l'image" % key)
		assert_eq(m.get_shader_parameter("size_px"), Vector2(PixelSurfaces.SIZE, PixelSurfaces.SIZE), "%s : 20 px par mètre" % key)
	# Clés propres aux textures (hors éditeur) : la planche seulement.
	for key: String in PixelSurfaces.DEFS:
		assert_true(WorldLook.SURFACES.has(key) or key == "plank", "%s : clé du jeu" % key)
	assert_eq(WorldLook.surface("inconnue"), WorldLook.surface("wall"), "clé inconnue : plâtre")
	assert_eq(Barricade.plank_material(), PixelSurfaces.material("plank"), "bois des encadrements : planche pixel art")
	assert_eq(MeshMapBuilder.material_for("plank"), PixelSurfaces.material("plank"), "clé spéciale « plank » : même planche")


func test_pixel_surfaces_are_deterministic() -> void:
	var total := 0.0
	for key: String in PixelSurfaces.DEFS:
		var a := PixelSurfaces.image(key).get_data()
		PixelSurfaces._images.erase(key)
		var t0 := Time.get_ticks_usec()
		var b := PixelSurfaces.image(key).get_data()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		print("[voxel_archi] texture %s : %.1f ms" % [key, ms])
		assert_eq(a, b, "%s : même image à chaque génération" % key)
	print("[voxel_archi] %d textures générées en %.0f ms" % [PixelSurfaces.DEFS.size(), total])


## Teintes de PixelSurfaces.PAL = celles de voxel_lib.DECOR_PALETTE (relu
## dans tools/blender/voxel/voxel_lib.py) : architecture et décor partagent
## une palette.
func test_palette_matches_voxel_lib() -> void:
	var src := FileAccess.get_file_as_string("res://tools/blender/voxel/voxel_lib.py")
	assert_true(src.contains("DECOR_PALETTE = {"), "voxel_lib.py lu")
	var block := src.get_slice("DECOR_PALETTE = {", 1).get_slice("\n}", 0)
	var re := RegEx.create_from_string("\"(\\w+)\"\\s*:\\s*\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*\\)")
	var py := {}
	for r in re.search_all(block):
		py[r.get_string(1)] = Color(float(r.get_string(2)), float(r.get_string(3)), float(r.get_string(4)))
	assert_true(py.size() >= 40, "teintes de DECOR_PALETTE (%d)" % py.size())
	for name: String in PixelSurfaces.PAL:
		assert_true(py.has(name), "%s : teinte de DECOR_PALETTE" % name)
		if py.has(name):
			assert_true((py[name] as Color).is_equal_approx(PixelSurfaces.PAL[name]), "%s : même valeur (%s / %s)" % [name, py[name], PixelSurfaces.PAL[name]])
	# Chaque teinte citée par une clé existe dans la palette.
	for key: String in PixelSurfaces.DEFS:
		var d := PixelSurfaces.def(key)
		for k in ["tone", "paint", "accent", "wood", "frieze_tone"]:
			if d.has(k):
				var names: Array = [d[k]] if d[k] is String else [d[k][0], d[k][1]]
				for n in names:
					assert_true(PixelSurfaces.PAL.has(n), "%s.%s : %s dans la palette" % [key, k, n])


## Sombres mais lisibles (l'architecture est plus sombre que le décor),
## jamais d'un seul aplat ; lueur seulement sur la pierre à veines.
func test_pixel_surfaces_levels_and_glow() -> void:
	for key: String in PixelSurfaces.DEFS:
		var img := PixelSurfaces.image(key)
		var sum := 0.0
		var colors := {}
		var glow := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				sum += PixelSurfaces.lum(c)
				colors[c.to_rgba32()] = true
				if c.a < 0.99:
					glow += 1
		var mean := sum / (img.get_width() * img.get_height())
		assert_true(mean > 0.04 and mean < 0.6, "%s : luminance moyenne %.3f" % [key, mean])
		assert_true(colors.size() >= 4, "%s : plusieurs teintes (%d)" % [key, colors.size()])
		if float(PixelSurfaces.def(key).glow) > 0.0:
			assert_true(glow > 10, "%s : veines lumineuses (%d px)" % [key, glow])
		else:
			assert_eq(glow, 0, "%s : aucune lueur" % key)


## Textures importées d'une carte : réduites à la volée à `taille` × 20 px de
## large (moyenne de zone), agrandies au plus proche si l'image est petite.
func test_imported_textures_are_pixelated() -> void:
	var big := Image.create(256, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 256:
			big.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
	var p := MapTextureLib.pixelate(big, 2.0)
	assert_eq(p.get_size(), Vector2i(40, 20), "2 m -> 40 × 20 px (proportions de l'image)")
	var c := p.get_pixel(17, 9)
	assert_true(absf(c.r - 0.5) < 0.12, "moyenne de zone (damier -> gris, %.2f)" % c.r)
	var small := Image.create(4, 4, false, Image.FORMAT_RGB8)
	small.fill(Color(0.2, 0.4, 0.6))
	small.set_pixel(0, 0, Color.RED)
	var q := MapTextureLib.pixelate(small, 1.0)
	assert_eq(q.get_size(), Vector2i(20, 20), "1 m -> 20 × 20 px")
	assert_true(q.get_pixel(0, 0).is_equal_approx(Color.RED) and q.get_pixel(4, 4).is_equal_approx(Color.RED) and q.get_pixel(5, 5).is_equal_approx(Color(0.2, 0.4, 0.6)), "agrandie au plus proche (un pixel de l'image = 5 × 5 pixels)")
	assert_true(MapTextureLib.SHADER.code.contains("filter_nearest_mipmap"), "textures importées au plus proche")


## Vignettes des surfaces dans l'éditeur : la texture pixel art elle-même.
func test_editor_surface_icons() -> void:
	for key: String in WorldLook.SURFACES:
		var img := MapIcons.surface_icon_image(key)
		assert_eq(img.get_size(), MapIcons.SURFACE_ICON, "%s : vignette 40 × 24" % key)
		var colors := {}
		for y in img.get_height():
			for x in img.get_width():
				colors[img.get_pixel(x, y).to_rgba32()] = true
		assert_true(colors.size() >= 3, "%s : vignette du motif (%d teintes)" % [key, colors.size()])
	# Mur : vu de face, le pied en bas : le liseré sombre du soubassement
	# (ligne 25 de l'image, 1,25 m) tombe sur la ligne 33 - 25 = 8 de la vignette.
	var wall := MapIcons.surface_icon_image("wall")
	var row := func(y: int) -> float:
		var s := 0.0
		for x in wall.get_width():
			s += PixelSurfaces.lum(wall.get_pixel(x, y))
		return s
	assert_true(row.call(8) < row.call(6) * 0.85 and row.call(8) < row.call(10) * 0.85, "mur : liseré du soubassement à sa place (pied en bas)")


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


## Lot B : toute l'architecture des cartes de l'éditeur en faces axiales sur
## la grille de 5 cm (nœuds *__wall, *__biais, *__block) : murs en biais,
## raccords, murs courbes, piliers tournés, cours tournées des fenêtres en
## biais ; collisions inchangées (pavés lisses tournés).
func test_lot_b_walls_are_axial_cubes() -> void:
	for it in [["biais", Diag.diag_map()], ["ronde", Free.round_map()], ["murs_libres", Walls.free_walls_map()], ["pente", Free.slanted_map()]]:
		var L: Dictionary = MapPreviewWorld.compute(it[1]).data
		var arch := MeshMapGeometry.build(L)
		var bad := 0
		var off_grid := 0
		var tris := 0
		for kind in ["*__wall", "*__biais", "*__block"]:
			for mi: MeshInstance3D in arch.find_children(kind, "MeshInstance3D", true, false):
				var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				tris += vs.size() / 3
				for i in range(0, vs.size(), 3):
					var n := (vs[i + 1] - vs[i]).cross(vs[i + 2] - vs[i]).normalized()
					if maxf(absf(n.x), maxf(absf(n.y), absf(n.z))) < 0.9999:
						bad += 1
				for p in vs:
					if not (VoxelCheck.on_grid(p.x, 0.05) and VoxelCheck.on_grid(p.y, 0.05) and VoxelCheck.on_grid(p.z, 0.05)):
						off_grid += 1
		assert_eq(bad, 0, "%s : faces axiales seulement (murs, murs en biais, blocs)" % it[0])
		assert_eq(off_grid, 0, "%s : sommets sur la grille de 5 cm" % it[0])
		# Collisions : un pavé tourné par morceau de mur en biais, les cours
		# tournées gardent leurs pavés (BoxShape3D).
		var pieces := 0
		for w in L.get("obliques", []):
			var length := Vector2(w.a[0], w.a[1]).distance_to(Vector2(w.b[0], w.b[1]))
			pieces += MeshMapGeometry.wall_pieces(0.0, length, float(w.y0), float(w.y1), w.get("openings", [])).filter(
				func(pc): return pc[1] - pc[0] >= 0.001 and pc[3] - pc[2] >= 0.001).size()
		assert_eq(arch.find_children("Biais_*", "CollisionBox", false, false).size(), pieces, "%s : collisions des murs en biais inchangées" % it[0])
		print("[voxel_archi] %s : %d triangles de murs" % [it[0], tris])
		arch.free()


## Mur courbe : chaque segment exporté porte le centre de l'arc (raccords
## entre ses segments aussi) ; rendu d'un bloc, ses faces s'éclairent selon
## la normale du vrai arc (rayon), pas selon celle de chaque segment.
func test_curved_wall_is_one_contour() -> void:
	var L: Dictionary = MapPreviewWorld.compute(Walls.free_walls_map()).data
	var arcs: Array = L.obliques.filter(func(w): return w.has("arc"))
	assert_true(arcs.size() >= 4, "segments du mur courbe marqués (%d)" % arcs.size())
	var c := Vector2(8.0 + MapGeom.WORLD_OFFSET, 12.0 + MapGeom.WORLD_OFFSET)
	for w in arcs:
		assert_true(Vector2(w.arc[0], w.arc[1]).distance_to(c) < 0.001, "centre de l'arc (%s)" % [w.arc])
	assert_true(arcs.any(func(w): return w.get("joint", false)), "raccords entre segments de l'arc marqués")
	assert_eq(MapLayoutExport.off_grid(L), [], "description sur la grille de 5 cm")
	# Rendu seul de l'arc : normales d'éclairage des faces verticales penchées
	# vers le rayon de l'arc (moins de 25° d'écart avec la face elle-même, du
	# côté du rayon).
	var g := MeshMapGeometry.new()
	var gn := g._group("wall", "x")
	for w in arcs:
		var a := Vector2(w.a[0], w.a[1])
		var b := Vector2(w.b[0], w.b[1])
		var d := (b - a).normalized()
		var o := g._owner(gn, gn, Vector2(-d.y, d.x), c, 1 if w.get("joint", false) else 0)
		g._raster_piece(o, a, d, 0.0, a.distance_to(b), float(w.thick), 0.0, 3.0)
	g._emit_cols()
	var radial := 0
	var faces := 0
	for i in range(0, gn.v.size(), 3):
		var ln: Vector3 = gn.n[i]
		if absf(ln.y) > 0.5:
			continue
		faces += 1
		var mid: Vector3 = (gn.v[i] + gn.v[i + 1] + gn.v[i + 2]) / 3.0
		var r := (Vector2(mid.x, mid.z) - c).normalized()
		if absf(Vector2(ln.x, ln.z).normalized().dot(r)) > 0.8:
			radial += 1
	assert_true(faces > 50 and radial == faces, "faces éclairées selon le rayon de l'arc (%d / %d)" % [radial, faces])


## Ouverture dans un mur en biais : le cadre cubique couvre le plan vrai du
## jambage (sans lui, l'escalier laisse un jour derrière la porte tournée).
func test_oblique_opening_frame_covers_the_jamb() -> void:
	var a := Vector2(10.0, 10.0)
	var d := Vector2(1, 1).normalized()
	var u := Vector2(-d.y, d.x)
	var t := 0.5
	var o0 := 2.0
	var o1 := 3.5
	var gaps := []
	for frame in [false, true]:
		var g := MeshMapGeometry.new()
		var gn := g._group("wall", "x")
		var o := g._owner(gn, gn, u)
		for pc in MeshMapGeometry.wall_pieces(0.0, 6.0, 0.0, 3.0, [{"t": (o0 + o1) / 2.0, "w": o1 - o0, "y0": 0.0, "y1": 2.1}]):
			g._raster_piece(o, a, d, pc[0], pc[1], t, pc[2], pc[3])
		if frame:
			g._raster_jamb(o, a, d, o0, 1.0, t, 0.0, 3.0)
			g._raster_jamb(o, a, d, o1, -1.0, t, 0.0, 3.0)
		var miss := 0
		for sj in [[o0, -1.0], [o1, 1.0]]:
			for k in range(-20, 21):
				var p: Vector2 = a + d * (float(sj[0]) + float(sj[1]) * 0.005) + u * (k / 20.0 * (t / 2.0 - 0.01))
				if not _filled(g, p, 1.0):
					miss += 1
		gaps.append(miss)
	assert_true(gaps[0] > 0, "sans cadre : jour derrière le jambage (%d points)" % gaps[0])
	assert_eq(gaps[1], 0, "avec le cadre : jambages pleins")


## Cellule pleine au point (x, z) du monde à la hauteur y (rangées de MeshMapGeometry).
static func _filled(g: MeshMapGeometry, p: Vector2, y: float) -> bool:
	var i := floori(p.x / MeshMapGeometry.CUBE)
	var j := floori(p.y / MeshMapGeometry.CUBE)
	for sp: Array in g._rows.get(j, []):
		if i >= int(sp[0]) and i <= int(sp[1]):
			for iv: Array in sp[2]:
				if y >= float(iv[0]) and y <= float(iv[1]):
					return true
	return false


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


## Lot E : les marches des murs en biais ne projettent pas d'ombre les unes
## sur les autres (rayures sous une lampe proche) : leurs faces visibles sans
## ombre, l'ombre du mur portée par des pavés lisses amincis (ombre seule)
## dont aucune face visible n'est à l'intérieur ; idem pour un escalier tourné.
func test_stepped_walls_cast_smooth_shadows() -> void:
	var L: Dictionary = MapPreviewWorld.compute(Diag.diag_map()).data
	var g := MeshMapGeometry.new()
	var arch := g._build(L)
	var steps := arch.find_children("*__biais", "MeshInstance3D", true, false)
	assert_true(steps.size() >= 1, "murs en biais")
	for mi: MeshInstance3D in steps:
		assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s : sans ombre propre" % mi.name)
	var sh := arch.get_node_or_null("StepShadows") as MeshInstance3D
	assert_true(sh != null and sh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "ombre seule des murs en biais")
	assert_true(g._shadow_boxes.size() >= arch.find_children("Biais_*", "CollisionBox", false, false).size(), "un pavé d'ombre par morceau de mur en biais et de cour tournée")
	# Aucun centre de face visible à l'intérieur d'un pavé d'ombre aminci.
	var inside := 0
	for mi: MeshInstance3D in steps:
		var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0, vs.size(), 3):
			var c := (vs[i] + vs[i + 1] + vs[i + 2]) / 3.0
			for sb: Array in g._shadow_boxes:
				var yaw := float(sb[2])
				var q: Vector3 = Basis(Vector3(cos(yaw), 0, -sin(yaw)), Vector3.UP, Vector3(sin(yaw), 0, cos(yaw))).inverse() * (c - (sb[0] as Vector3))
				var h: Vector3 = (sb[1] as Vector3) * 0.5
				var t := maxf(h.z - float(sb[3]), 0.0)
				# Hors des bouts (15 cm) : au raccord de deux murs, quelques
				# faces du coin rentrant sont dans l'ombre de l'autre mur.
				if absf(q.x) < h.x - 0.15 and absf(q.y) < h.y - 0.001 and absf(q.z) < t - 0.001:
					inside += 1
					break
	assert_eq(inside, 0, "aucune marche dans l'ombre de son propre mur")
	arch.free()
	# Escalier tourné : marches et garde-corps sans ombre propre, prismes d'ombre.
	var st := StairGen.spec(Vector2(12.0, 12.0), Vector2(0, -1).rotated(deg_to_rad(30.0)), 7.0, 2.0, 0.0, 3.5, "palier", {"rail": true})
	st["room"] = "r"
	var sa := MeshMapGeometry.build({"stairs": [st]})
	var tilted := sa.find_children("*__stair_biais", "MeshInstance3D", true, false) + sa.find_children("*__rail_biais", "MeshInstance3D", true, false)
	assert_eq(tilted.size(), 2, "marches et garde-corps de l'escalier tourné")
	for mi: MeshInstance3D in tilted:
		assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s : sans ombre propre" % mi.name)
	assert_true(sa.get_node_or_null("StepShadows") != null, "ombre seule de l'escalier tourné")
	assert_true(sa.get_node_or_null("wood__r__stair__col") != null, "collisions inchangées (groupe « stair »)")
	sa.free()
