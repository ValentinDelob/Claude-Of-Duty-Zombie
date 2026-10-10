extends TestCase
## Chien errant contaminé cubique, cubes de 2,5 cm (tools/blender/dogs/dog_voxel.py,
## HellhoundModel) : chargé par ZombieGlb (ossature du jeu en quadrupède,
## couleurs par face, yeux émissifs), budget, taille d'un gros chien, style
## cubique (VoxelCheck, mode animé), zones de touche mesurées, et animations
## (DogAnim) : poses finies, pattes au-dessus du sol, peu de cubes qui se
## traversent (tests/voxel_pose_check.gd), chien couché sur le flanc à la mort.

const PATH := HellhoundModel.MODEL_PATH
const CELLS := "res://tools/blender/dogs/dog_voxel_cells.json"
const PoseCheck := preload("res://tests/voxel_pose_check.gd")
## Articulations du chien (voir voxel_pose_check.gd) : tronc et épaules en
## « boule » (jointures le long du dos), coudes et genoux en « plan ».
const LINKS := [["hips", "spine", "boule", 0.2], ["spine", "chest", "boule", 0.2], ["chest", "neck", "boule", 0.22],
		["neck", "head", "boule", 0.2], ["head", "jaw", "boule", 0.3], ["spine", "neck", "boule", 0.1],
		["chest", "arm_l", "boule", 0.3], ["chest", "arm_r", "boule", 0.3], ["spine", "arm_l", "boule", 0.12], ["spine", "arm_r", "boule", 0.12],
		["arm_l", "forearm_l", "plan", 0.075], ["arm_r", "forearm_r", "plan", 0.075],
		["hips", "thigh_l", "boule", 0.3], ["hips", "thigh_r", "boule", 0.3],
		["spine", "thigh_l", "boule", 0.2], ["spine", "thigh_r", "boule", 0.2],
		["thigh_l", "shin_l", "plan", 0.1], ["thigh_r", "shin_r", "plan", 0.1]]
## Cubes qui se traversent tolérés par pose (pièces rigides d'un quadrupède :
## l'épaule glisse sur le poitrail, la cuisse dans la croupe).
const MAX_OVERLAP := 30


func test_loaded_by_zombie_glb() -> void:
	var m := HellhoundModel.model()
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
	assert_true(tris > 2000 and tris < 8000, "budget : %d triangles (< 8 000)" % tris)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in pos:
		lo = lo.min(p)
		hi = hi.max(p)
	assert_near(lo.y, 0.0, 0.001, "pattes au sol")
	# Gros chien : ~0,75 m au garrot (dessus du poitrail), oreilles au-dessus.
	var bb := HellhoundModel.bone_bounds()
	var withers: float = (bb.chest as AABB).end.y
	assert_true(withers > 0.7 and withers < 0.8, "garrot à %.3f m" % withers)
	assert_true(hi.z > 0.6 and lo.z < -0.5, "museau devant (+Z %.2f), queue derrière (%.2f)" % [hi.z, lo.z])
	assert_true(hi.x - lo.x < 0.36, "largeur %.2f m" % (hi.x - lo.x))
	var on_grid := true
	for p in pos:
		for i in 3:
			if not VoxelCheck.on_grid(p[i], VoxelCheck.CUBE_CHAR):
				on_grid = false
	assert_true(on_grid, "sommets sur la grille de 2,5 cm")
	for b in RigBuilder.BONES:
		assert_true(m.overrides.has(b[0]), "os %s" % b[0])
	# Quadrupède : poitrail devant le bassin, pattes sous le tronc.
	assert_true(m.overrides.spine.z > 0.0 and m.overrides.chest.z > 0.0, "échine vers l'avant")
	assert_true(m.overrides.forearm_l.y < 0.0 and m.overrides.shin_l.y < 0.0, "pattes vers le bas")
	var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var rigid := true
	for v in pos.size():
		if absf(w[v * 4] - 1.0) > 0.001:
			rigid = false
			break
	assert_true(rigid, "pondération rigide")
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var eyes := 0
	var seen := {}
	for c in cols:
		if c.a < 0.5:
			eyes += 1
		seen[c.to_html()] = true
	assert_true(eyes > 0, "yeux émissifs")
	assert_true(seen.size() > 30, "couleurs par face (%d teintes)" % seen.size())


func test_voxel_style() -> void:
	var rep := VoxelCheck.check_file(PATH, 1)
	assert_true(rep.get("ok", false), String(rep.get("fr", "")))
	assert_near(float(rep.cube), VoxelCheck.CUBE_CHAR, 0.0001, "mode animé : grille des personnages")
	assert_true(int(rep.get("parts", 0)) >= 13, "chaque os vérifié dans son repère")


func test_cache_tracked() -> void:
	assert_true(FileAccess.file_exists(CELLS), "cache des cellules (suivi par git)")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CELLS))
	assert_near(float(data.cube), 0.025, 0.0001, "cubes de 2,5 cm")
	assert_true((data.cells as Array).size() > 5000, "%d cellules" % (data.cells as Array).size())


func test_build_and_hit_shapes() -> void:
	var skel := HellhoundModel.build(3)
	assert_eq(skel.get_bone_count(), RigBuilder.BONES.size(), "ossature du jeu")
	var mi := skel.get_node("Mesh") as MeshInstance3D
	assert_true(mi.mesh != null and mi.mesh.get_surface_count() == 1, "mesh partagé")
	assert_eq(mi.layers, ZombieModel.RENDER_LAYERS, "hors des décalques de sang")
	assert_true(mi.material_override == HellhoundModel.material(), "matériau cubique des chiens")
	var other := HellhoundModel.build(4)
	assert_true((other.get_node("Mesh") as MeshInstance3D).mesh == mi.mesh, "un mesh pour toute la meute")
	other.free()
	skel.free()
	var s := HellhoundModel.hit_shapes()
	var body: Array = s.body
	assert_true(body[1] > 0.12 and body[1] < 0.3, "rayon du tronc %.2f" % body[1])
	assert_true(body[2] > 0.7 and body[2] < 1.1, "longueur du tronc %.2f" % body[2])
	assert_true((body[0] as Vector3).y > 0.4 and (body[0] as Vector3).y < 0.7, "tronc à hauteur du dos")
	var head: Array = s.head
	assert_true((head[0] as Vector3).z > 0.0, "zone de tête vers le museau")
	assert_true(head[1] > 0.1 and head[1] < 0.25, "rayon de tête %.2f" % head[1])


func _check_pose(pc: RefCounted, skel: Skeleton3D, bones: Dictionary, p: Dictionary, what: String) -> Dictionary:
	DogAnim.apply(skel, bones, p)
	for n in p.bones:
		var v: Vector3 = p.bones[n]
		assert_true(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "%s : %s fini" % [what, n])
	var r: Dictionary = pc.check(skel, bones)
	assert_true(int(r.count) <= MAX_OVERLAP, "%s : %d cubes se traversent %s" % [what, r.count, r.pairs])
	return r


func test_animations() -> void:
	var skel := HellhoundModel.build(1)
	host.add_child(skel)  # poses globales des os à jour
	var bones := RigBuilder.bone_indices(skel)
	var pc := PoseCheck.new(HellhoundModel.model().overrides, CELLS, LINKS)
	var worst := 0
	# Galop à pleine vitesse, au trot, arrêt (halètement).
	for move in [1.0, 0.5, 0.0]:
		for i in 12:
			var r := _check_pose(pc, skel, bones, DogAnim.pose(i * TAU / 12.0, move, i * 0.1), "galop %.1f #%d" % [move, i])
			worst = maxi(worst, r.count)
			assert_true(float(r.floor) > -0.05, "galop %.1f #%d : pattes au-dessus du sol (%.3f)" % [move, i, r.floor])
	# Apparition (accroupi -> course) et bond de morsure.
	for i in 6:
		var k := i / 5.0
		var r := _check_pose(pc, skel, bones, DogAnim.pose(1.0, 1.0, 0.0, -1.0, k), "apparition %.1f" % k)
		worst = maxi(worst, r.count)
		assert_true(float(r.floor) > -0.05, "apparition %.1f : au-dessus du sol (%.3f)" % [k, r.floor])
		r = _check_pose(pc, skel, bones, DogAnim.pose(1.0, 1.0, 0.0, k), "bond %.1f" % k)
		worst = maxi(worst, r.count)
		assert_true(float(r.floor) > -0.05, "bond %.1f : au-dessus du sol (%.3f)" % [k, r.floor])
	# Le contrôle voit bien les cubes qui se traversent : patte avant repliée
	# dans le poitrail.
	var bad := DogAnim.pose(0.0, 0.0, 0.0)
	bad.bones.arm_l = Vector3(-2.6, 0, 0)
	DogAnim.apply(skel, bones, bad)
	assert_true(int(pc.check(skel, bones).count) > MAX_OVERLAP, "contrôle des recouvrements actif")
	# Bond : gueule ouverte en vol, refermée après la morsure.
	var fly := DogAnim.pose(0.0, 1.0, 0.0, 0.3)
	var bit := DogAnim.pose(0.0, 1.0, 0.0, 0.6)
	assert_true((fly.bones.jaw as Vector3).x > 0.5 and (bit.bones.jaw as Vector3).x < 0.15, "gueule ouverte puis claquée")
	assert_true(float(fly.lift) > 0.1 and float(fly.pitch) < -0.1, "bond : décolle, cabré")
	# Mort : couché sur le flanc, au-dessus du sol.
	for side in [1.0, -1.0]:
		for t in [0.1, 0.3, 0.6, 1.0, 2.0]:
			var r := _check_pose(pc, skel, bones, DogAnim.pose(0.0, 0.0, 0.0, -1.0, -1.0, t, side), "mort %.1f s (%+d)" % [t, side])
			assert_true(float(r.floor) > -0.06, "mort %.1f s : rien sous le sol (%.3f)" % [t, r.floor])
	var dead := DogAnim.pose(0.0, 0.0, 0.0, -1.0, -1.0, 3.0, 1.0)
	assert_near(float(dead.roll), DogAnim.DEATH_ROLL_ANGLE, 0.001, "sur le flanc")
	print("[test_dog_voxel] pire recouvrement : %d cubes" % worst)
	skel.free()
