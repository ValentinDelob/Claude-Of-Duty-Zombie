extends TestCase
## Le Brancardier (mini-boss de vague spéciale, GAME_CONCEPT.md §4.4) :
## modèle cubique de 2,5 cm (tools/blender/brancardier/brancardier_voxel.py,
## BrancardierModel), animations (BrancardierAnim : poses finies, au-dessus
## du sol, peu de cubes qui se traversent), règles pures (BrancardRules :
## composition, PV, charge, projection, mur), échantillons (LootRules), XP
## (catégorie mini-boss, XpRules) et rotation des vagues spéciales (WaveRules).

const PATH := BrancardierModel.MODEL_PATH
const CELLS := "res://tools/blender/brancardier/brancardier_voxel_cells.json"
const PoseCheck := preload("res://tests/voxel_pose_check.gd")
## Articulations (voir voxel_pose_check.gd) : épaules en « boule », coudes,
## genoux et tronc en « plan ».
const LINKS := [["hips", "spine", "plan", 0.1], ["spine", "chest", "plan", 0.1], ["chest", "neck", "boule", 0.22],
		["neck", "head", "boule", 0.2], ["head", "jaw", "boule", 0.3], ["neck", "jaw", "boule", 0.2],
		["chest", "arm_l", "boule", 0.24], ["chest", "arm_r", "boule", 0.24],
		["arm_l", "forearm_l", "plan", 0.1], ["arm_r", "forearm_r", "plan", 0.1],
		["hips", "thigh_l", "plan", 0.15], ["hips", "thigh_r", "plan", 0.15],
		["spine", "thigh_l", "plan", 0.1], ["spine", "thigh_r", "plan", 0.1],
		["thigh_l", "shin_l", "plan", 0.1], ["thigh_r", "shin_r", "plan", 0.1]]
## Cubes qui se traversent tolérés par pose (pièces rigides massives : le
## gros ventre et les cuisses, les bras contre le buste).
const MAX_OVERLAP := 160


func test_model() -> void:
	var m := BrancardierModel.model()
	assert_false(m.is_empty(), "modèle chargé")
	if m.is_empty():
		return
	var mesh: ArrayMesh = m.mesh
	assert_eq(mesh.get_surface_count(), 1, "un seul mesh (un draw call)")
	var a := mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	@warning_ignore("integer_division")
	var tris := (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_true(tris > 3000 and tris < 12000, "budget : %d triangles (< 12 000)" % tris)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in pos:
		lo = lo.min(p)
		hi = hi.max(p)
	assert_near(lo.y, 0.0, 0.001, "pieds au sol")
	var head_top: float = (BrancardierModel.bone_bounds().head as AABB).end.y
	assert_true(head_top > 2.1 and head_top < 2.35, "colosse : sommet du crâne à %.2f m" % head_top)
	assert_true(hi.y < 2.45, "brancard compris : %.2f m" % hi.y)
	assert_true(hi.x - lo.x > 1.1 and hi.x - lo.x < 1.5, "carrure %.2f m (poings compris)" % (hi.x - lo.x))
	for b in RigBuilder.BONES:
		assert_true(m.overrides.has(b[0]), "os %s" % b[0])
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var eyes := 0
	for c in cols:
		if c.a < 0.5:
			eyes += 1
	assert_true(eyes > 0, "yeux émissifs")
	var on_grid := true
	for p in pos:
		for i in 3:
			if not VoxelCheck.on_grid(p[i], VoxelCheck.CUBE_CHAR):
				on_grid = false
	assert_true(on_grid, "sommets sur la grille de 2,5 cm")


func test_voxel_style_and_cache() -> void:
	var rep := VoxelCheck.check_file(PATH, 1)
	assert_true(rep.get("ok", false), String(rep.get("fr", "")))
	assert_near(float(rep.cube), VoxelCheck.CUBE_CHAR, 0.0001, "mode animé : grille des personnages")
	assert_true(FileAccess.file_exists(CELLS), "cache des cellules (suivi par git)")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CELLS))
	assert_near(float(data.cube), 0.025, 0.0001, "cubes de 2,5 cm")
	# Les deux échantillons sont sur le modèle : sangles de cuir et bracelet.
	assert_true((data.parts as Array).has("bracelet") and (data.parts as Array).has("strap_front"), "bracelet et sangles modélisés")


func test_build_and_hit_shapes() -> void:
	var skel := BrancardierModel.build()
	assert_eq(skel.get_bone_count(), RigBuilder.BONES.size(), "ossature du jeu")
	var mi := skel.get_node("Mesh") as MeshInstance3D
	assert_true(mi.material_override == BrancardierModel.material(), "matériau cubique")
	assert_eq(mi.layers, ZombieModel.RENDER_LAYERS, "hors des décalques de sang")
	skel.free()
	var s := BrancardierModel.hit_shapes()
	var body: Array = s.body
	assert_true(body[1] > 0.22 and body[1] < 0.45, "rayon du tronc %.2f" % body[1])
	assert_true(body[2] > 0.7 and body[2] < 1.4, "hauteur du tronc %.2f" % body[2])
	assert_true((body[0] as Vector3).y > 1.0 and (body[0] as Vector3).y < 1.6, "tronc à hauteur du buste (%.2f)" % (body[0] as Vector3).y)
	var head: Array = s.head
	assert_true(head[1] > 0.12 and head[1] < 0.3, "rayon de tête %.2f" % head[1])


func _check_pose(pc: RefCounted, skel: Skeleton3D, bones: Dictionary, p: Dictionary, what: String) -> Dictionary:
	BrancardierAnim.apply(skel, bones, p)
	for n in p.bones:
		var v: Vector3 = p.bones[n]
		assert_true(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "%s : %s fini" % [what, n])
	var r: Dictionary = pc.check(skel, bones)
	assert_true(int(r.count) <= MAX_OVERLAP, "%s : %d cubes se traversent %s" % [what, r.count, r.pairs])
	return r


func test_animations() -> void:
	var skel := BrancardierModel.build()
	host.add_child(skel)
	var bones := RigBuilder.bone_indices(skel)
	var pc := PoseCheck.new(BrancardierModel.model().overrides, CELLS, LINKS)
	var worst := 0
	var A := BrancardierAnim
	for move in [1.0, 0.5, 0.0]:
		for i in 8:
			var r := _check_pose(pc, skel, bones, A.pose(i * TAU / 8.0, move, i * 0.3), "marche %.1f #%d" % [move, i])
			worst = maxi(worst, r.count)
			assert_true(float(r.floor) > -0.06, "marche %.1f #%d : au-dessus du sol (%.3f)" % [move, i, r.floor])
	for i in 8:
		var t := i * 0.18
		var r := _check_pose(pc, skel, bones, A.pose(0.0, 0.0, t, A.WINDUP, t), "préparation %.2f s" % t)
		worst = maxi(worst, r.count)
		assert_true(float(r.floor) > -0.08, "préparation %.2f s : au-dessus du sol (%.3f)" % [t, r.floor])
		r = _check_pose(pc, skel, bones, A.pose(i * TAU / 8.0, 1.0, t, A.CHARGE, t), "charge #%d" % i)
		worst = maxi(worst, r.count)
		assert_true(float(r.floor) > -0.08, "charge #%d : au-dessus du sol (%.3f)" % [i, r.floor])
		r = _check_pose(pc, skel, bones, A.pose(0.0, 0.0, t, A.STUN, t * 2.0), "étourdi %.2f s" % (t * 2.0))
		worst = maxi(worst, r.count)
		assert_true(float(r.floor) > -0.08, "étourdi : au-dessus du sol (%.3f)" % r.floor)
		var k := i / 7.0
		r = _check_pose(pc, skel, bones, A.pose(0.0, 0.0, 0.0, A.NONE, 0.0, k), "coup %.2f" % k)
		worst = maxi(worst, r.count)
	for t in [0.2, 0.5, 0.8, 1.2, 2.0]:
		var r := _check_pose(pc, skel, bones, A.pose(0.0, 0.0, 0.0, A.NONE, 0.0, -1.0, t), "mort %.1f s" % t)
		assert_true(float(r.floor) > -0.1, "mort %.1f s : rien sous le sol (%.3f)" % [t, r.floor])
	# Préparation : gueule ouverte (rugissement) ; mort : face contre terre.
	assert_true((A.pose(0.0, 0.0, 0.0, A.WINDUP, 0.7).bones.jaw as Vector3).x > 0.5, "rugissement : gueule ouverte")
	assert_near(float(A.pose(0.0, 0.0, 0.0, A.NONE, 0.0, -1.0, 3.0).pitch), A.DEATH_PITCH, 0.001, "mort : face contre terre")
	print("[test_brancardier] pire recouvrement : %d cubes" % worst)
	skel.free()


func test_rules() -> void:
	assert_eq(BrancardRules.count(1), 1, "1 Brancardier par joueur")
	assert_eq(BrancardRules.count(4), 4)
	assert_eq(BrancardRules.count(8), BrancardRules.MAX_TOTAL, "plafond")
	assert_eq(BrancardRules.escorts(1), 5, "escorte en solo")
	assert_eq(BrancardRules.escorts(8), BrancardRules.ESCORT_MAX)
	# PV : 10 × PV d'un zombie de la manche, +20 % par vague du Brancardier.
	assert_eq(BrancardRules.health(10, 1), 10500)
	assert_eq(BrancardRules.health(20, 2), 24600)
	assert_eq(BrancardRules.health(5, 1), 10 * RoundRules.zombie_health(5))
	# Charge : distance, niveau, ligne dégagée, recharge.
	assert_true(BrancardRules.can_charge(8.0, 0.0, true, 0.0))
	assert_false(BrancardRules.can_charge(2.0, 0.0, true, 0.0), "trop près : coup de poing")
	assert_false(BrancardRules.can_charge(20.0, 0.0, true, 0.0), "trop loin")
	assert_false(BrancardRules.can_charge(8.0, 2.0, true, 0.0), "autre niveau")
	assert_false(BrancardRules.can_charge(8.0, 0.0, false, 0.0), "obstacle")
	assert_false(BrancardRules.can_charge(8.0, 0.0, true, 1.0), "recharge")
	var dir := Vector3(0, 0, 1)
	assert_true(BrancardRules.in_charge_path(Vector3(0.5, 0, 0.8), dir), "joueur devant : percuté")
	assert_false(BrancardRules.in_charge_path(Vector3(2.0, 0, 0.8), dir), "à côté : épargné")
	assert_false(BrancardRules.in_charge_path(Vector3(0, 0, -1.5), dir), "derrière : épargné")
	var kv := BrancardRules.knock_velocity(Vector3(0.4, 0, 0.6), dir)
	assert_true(kv.z > 5.0 and kv.y > 2.0, "projeté vers l'avant et en l'air %s" % kv)
	assert_true(kv.x > 0.0 and BrancardRules.knock_velocity(Vector3(-0.4, 0, 0.6), dir).x < 0.0, "repoussé du côté où il se trouve")
	assert_true(BrancardRules.hits_wall(Vector3(0, 0, -1), dir), "mur de face")
	assert_false(BrancardRules.hits_wall(Vector3(1, 0, 0), dir), "mur longé : pas de choc")
	assert_false(BrancardRules.hits_wall(Vector3(0, 1, 0), dir), "sol")


func test_samples_xp() -> void:
	var ids := []
	for s in LootRules.SAMPLES.brancardier:
		ids.append(s[0])
	assert_eq(ids, ["brancard_strap", "brancard_bracelet"], "sangle de cuir, bracelet d'identification")
	assert_true(LootRules.sample_name("brancard_strap") in ["SANGLE DE CUIR", "LEATHER STRAP"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var got := {}
	for i in 2000:
		for s in LootRules.roll_samples("brancardier", rng):
			got[s] = int(got.get(s, 0)) + 1
	for id in ids:
		assert_true(int(got.get(id, 0)) > 330 and int(got.get(id, 0)) < 470, "%s : ~20 %% (%d / 2000)" % [id, got.get(id, 0)])
	assert_eq(XpRules.category_of(XpRules.BRANCARDIER), XpRules.MINIBOSS, "catégorie mini-boss")
	var r: Array = XpRules.CATEGORY_RANGE[XpRules.MINIBOSS]
	assert_true(XpRules.base_xp(XpRules.BRANCARDIER) >= r[0] and XpRules.base_xp(XpRules.BRANCARDIER) <= r[1], "dans la fourchette")
	assert_eq(XpRules.kill_xp(XpRules.BRANCARDIER, 10), roundi(60 * XpRules.round_factor(10)))
	assert_eq(HubIcon.sample_art("brancard_strap"), "strap", "icône du hub")
	assert_eq(HubIcon.sample_art("brancard_bracelet"), "bracelet")


func test_rotation_default() -> void:
	var s := WaveRules.default_schedule()
	var seq := []
	for n in [5, 10, 15, 20, 25]:
		seq.append(WaveRules.special_type_at(s, n))
	assert_eq(seq, ["meute", "brancardier", "infirmiere", "meute", "brancardier"], "rotation par défaut")
	assert_eq(WaveRules.next_special_of(s, WaveRules.BRANCARDIER, 0), 10)
	assert_eq(WaveRules.next_special_of(s, WaveRules.MEUTE, 5), 20)
