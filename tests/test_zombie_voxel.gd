extends TestCase
## Zombie « patient » cubique, cubes de 2,5 cm (tools/blender/zombies/zombie_voxel.py,
## modèle de tous les zombies, ZombieModel) : chargé par ZombieGlb (ossature du jeu,
## matières, couleurs par face de cube, yeux émissifs), instanciable par
## RigBuilder, et conforme au style cubique (VoxelCheck, mode animé).

const PATH := "res://assets/models/zombies/zombie_voxel.glb"


func test_loaded_by_zombie_glb() -> void:
	var m := ZombieGlb.load_model(PATH)
	assert_false(m.is_empty(), "modèle chargé")
	if m.is_empty():
		return
	var mesh: ArrayMesh = m.mesh
	assert_eq(mesh.get_surface_count(), 1, "un seul mesh (un draw call)")
	var a := mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	@warning_ignore("integer_division")
	var tris := idx.size() / 3
	assert_true(tris > 2000 and tris < 15000, "budget : %d triangles (< 15 000)" % tris)
	# Taille : 72 cubes de 2,5 cm (1,80 m), pieds au sol.
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in pos:
		lo = lo.min(p)
		hi = hi.max(p)
	assert_near(lo.y, 0.0, 0.001, "pieds au sol")
	assert_near(hi.y, 1.8, 0.001, "72 cubes de haut")
	# Tous les sommets sur la grille des personnages (2,5 cm).
	var on_grid := true
	for p in pos:
		for i in 3:
			if not VoxelCheck.on_grid(p[i], VoxelCheck.CUBE_CHAR):
				on_grid = false
	assert_true(on_grid, "sommets sur la grille de 2,5 cm")
	# Ossature : tous les os du jeu, repos en position (membres pendants).
	for b in RigBuilder.BONES:
		assert_true(m.overrides.has(b[0]), "os %s" % b[0])
	assert_true(m.overrides.head.y > 0.0 and m.overrides.shin_l.y < 0.0, "tête au-dessus du cou, tibia sous la cuisse")
	# Pondération rigide : un os par sommet, à 100 %.
	var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var rigid := true
	for v in pos.size():
		if absf(w[v * 4] - 1.0) > 0.001:
			rigid = false
			break
	assert_true(rigid, "pondération rigide")
	# Couleurs par face (pas une couleur par matière), yeux émissifs, blouse
	# claire et peau verte.
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var seen := {}
	var emissive := 0
	var cloth := Color(0, 0, 0, 0)
	var skin := Color(0, 0, 0, 0)
	var n_cloth := 0
	var n_skin := 0
	for v in cols.size():
		var c := cols[v]
		seen[Color(snappedf(c.r, 0.01), snappedf(c.g, 0.01), snappedf(c.b, 0.01))] = true
		if c.a < 0.5:
			emissive += 1
			continue
		if int(uv2[v].y) == RigBuilder.MAT_CLOTH:
			cloth += c
			n_cloth += 1
		elif int(uv2[v].y) == RigBuilder.MAT_SKIN:
			skin += c
			n_skin += 1
	assert_true(seen.size() > 20, "couleurs par face de cube (%d teintes)" % seen.size())
	assert_true(emissive >= 8, "yeux émissifs (alpha 0)")
	assert_true(n_cloth > 0 and n_skin > 0, "blouse et peau présentes")
	if n_cloth > 0 and n_skin > 0:
		cloth /= float(n_cloth)
		skin /= float(n_skin)
		assert_true(cloth.get_luminance() > skin.get_luminance() * 1.5, "blouse claire, peau sombre")
		assert_true(skin.g > skin.r, "peau verdâtre")


func test_instantiated_by_rig_builder() -> void:
	var m := ZombieGlb.load_model(PATH)
	if m.is_empty():
		assert_true(false, "modèle chargé")
		return
	var tmp := RigBuilder.build_skeleton(m.overrides)
	var skin := tmp.create_skin_from_rest_transforms()
	tmp.free()
	var skel := RigBuilder.instantiate(m.mesh, ZombieModel.material(), m.overrides, skin)
	assert_eq(skel.get_bone_count(), RigBuilder.BONES.size(), "squelette du jeu")
	assert_true(skel.get_node_or_null("Mesh") is MeshInstance3D, "mesh lié")
	skel.free()


func test_voxel_style() -> void:
	var rep := VoxelCheck.check_file(PATH, 1)
	assert_true(rep.get("ok", false), String(rep.get("fr", "")))
	assert_near(float(rep.cube), VoxelCheck.CUBE_CHAR, 0.0001, "mode animé : grille des personnages")
	assert_false(VoxelCheck.check_file(PATH, 1, 1.0, VoxelCheck.CUBE).ok, "pas un modèle de décor (5 cm)")
	assert_true(int(rep.get("parts", 0)) >= 13, "chaque os vérifié dans son repère")
