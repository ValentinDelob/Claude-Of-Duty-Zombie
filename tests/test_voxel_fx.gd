extends TestCase
## Effets cubiques (VoxelFx, GAME_CONCEPT.md § 4.19) : maillages de cubes
## (centres et côtés lus par voxel_particle.gdshader), flamme de bouche sur
## la grille de 2,5 cm, chaînes des arcs, matériaux sans texture.


## Sommets d'un maillage : demi-côté de cube autour des centres codés en UV.
func test_cluster_encodes_cube_centers() -> void:
	for kind in ["cube", "puff", "cloud", "tongue"]:
		var m := VoxelFx.cluster(kind)
		var a := m.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
		assert_true(v.size() > 0 and v.size() % 36 == 0, "%s : 36 sommets par cube (%d)" % [kind, v.size()])
		var bad := 0
		var ext := Vector3.ZERO
		var far := 0.0
		for i in v.size():
			var c := Vector3(uv[i].x, uv[i].y, uv2[i].x)
			var h := uv2[i].y * 0.5
			var d := (v[i] - c).abs()
			if not (is_equal_approx(d.x, h) and is_equal_approx(d.y, h) and is_equal_approx(d.z, h)):
				bad += 1
			ext = ext.max(c.abs())
			far = maxf(far, c.length())
		assert_eq(bad, 0, "%s : chaque sommet à un demi-côté du centre de son cube" % kind)
		assert_true((m.get_meta("vox_ext") as Vector3).is_equal_approx(ext), "%s : vox_ext = étendue des centres" % kind)
		# Une touffe garde à peu près le diamètre de la particule (1).
		assert_true(far <= 0.52, "%s : centres dans la particule (%.2f)" % [kind, far])


func test_flash_is_on_the_character_grid() -> void:
	for v in 4:
		var m := VoxelFx.flash_mesh(3, 6, 2, v)
		var verts: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		assert_eq(cols.size(), verts.size(), "flamme %d : une couleur par sommet" % v)
		var off := 0
		for p in verts:
			# Sommets à ±1,25 cm des centres, eux sur la grille de 2,5 cm.
			var q := (p / VoxelFx.GRID) - Vector3.ONE * 0.5
			if not q.is_equal_approx(q.round()):
				off += 1
		assert_eq(off, 0, "flamme %d : cubes de 2,5 cm alignés sur la grille" % v)


func test_chain_fills_a_polyline_with_cubes() -> void:
	var mm := VoxelFx.chain_multimesh(64)
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 1, 0)])
	# (Les transformations d'instances ne sont pas relues : le serveur de
	# rendu factice des tests sans fenêtre ne les garde pas ; elles sont
	# vues sur les captures de map_effects_look et fx_look.)
	var n := VoxelFx.fill_chain(mm, pts, 0.05)
	assert_eq(n, 41, "2 m de ligne : un cube tous les 5 cm")
	# Trop peu d'instances : cubes plus espacés, jamais au-delà.
	var few := VoxelFx.chain_multimesh(64)
	assert_eq(VoxelFx.fill_chain(few, pts, 0.05, Vector3.ONE, 50), 14, "14 instances libres : 14 cubes")
	assert_eq(VoxelFx.fill_chain(few, pts, 0.05, Vector3.ONE, 63), 0, "moins de 2 instances : rien")
	# Repère étiré (arc : 0,4 m de large, 2 m de long) : espacement en mètres.
	var arc := VoxelFx.chain_multimesh(64)
	assert_eq(VoxelFx.fill_chain(arc, PackedVector3Array([Vector3(0, -0.5, 0), Vector3(0, 0.5, 0)]), 0.05, Vector3(0.4, 2.0, 1.0)), 41, "arc de 2 m : 41 cubes")


func test_materials_have_no_texture_and_snap_to_grid() -> void:
	for blend in ["mix", "add", "lit"]:
		var m := VoxelFx.material(blend, {"max": VoxelFx.SMALL})
		assert_true(m.shader.code.contains("round(w / grid)"), "%s : côté arrondi à la grille" % blend)
		assert_false(m.shader.code.contains("sampler2D"), "%s : aucune texture" % blend)
		assert_near(float(m.get_shader_parameter("grid")), 0.025, 0.00001, "%s : pas de 2,5 cm" % blend)
	assert_true(VoxelFx.material("add") == VoxelFx.material("add"), "matériaux partagés")


func test_map_effect_layers_are_cubes() -> void:
	MapCatalog.items()
	for id in MapCatalog.EFFECTS:
		var e := MapEffects.build(id, {"room_h": 3.2})
		for p in e.parts:
			var flat := p.draw_pass_1 is QuadMesh
			assert_true(flat or p.draw_pass_1.has_meta("vox_cell"), "%s : couche %d en cubes" % [id, p.get_index()])
			assert_true(p.material_override is ShaderMaterial, "%s : matériau cubique" % id)
			# Rayon : jamais moins que le plus petit cube.
			var r := MapEffects.part_radius(p)
			assert_true(flat or r.x >= VoxelFx.GRID * 0.5 - 0.0001, "%s : rayon >= demi-cube" % id)
		e.free()
