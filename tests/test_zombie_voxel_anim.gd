extends TestCase
## Animations du zombie cubique (ZombieAnim, rampant de ZombieGibs) : à chaque
## image clé de chaque animation, les pièces ne se traversent pas (cubes de
## deux os dans la même case de 2,5 cm, hors voisinage des articulations,
## tests/voxel_pose_check.gd) et le corps ne s'enfonce pas dans le sol ;
## poses lisibles (mains devant en course, une main d'abord à la sortie du
## sol, mains ramenées vers l'arrière à l'arrachage, à plat ventre au passage).

const Samples := preload("res://tests/zombie_anim_samples.gd")
const PoseCheck := preload("res://tests/voxel_pose_check.gd")
const KEYS := 12
## Cubes qui se traversent tolérés par image (sur ~16 600) : frôlements d'un
## cube aux bords des pièces.
const MAX_OVERLAP := 12
## Enfoncement dans le sol toléré (m) : un demi-cube.
const MAX_SINK := 0.0125
## Animations hors sol (sous terre, au-dessus de l'appui).
const OFF_GROUND := ["sortie_du_sol", "passage_fenetre"]

var _check: RefCounted


func _pc() -> RefCounted:
	if _check == null:
		_check = PoseCheck.new(ZombieModel.rest_overrides())
	return _check


## Pire image d'une animation : [cubes qui se traversent, k, paires, plus bas].
func _worst(anim: String) -> Array:
	var z: Zombie = Samples.make(host, anim)
	var worst := [-1, 0.0, {}, INF]
	for i in KEYS + 1:
		var k := float(i) / KEYS
		Samples.pose(z, anim, k)
		var r: Dictionary = _pc().check(z.skel, z.bones)
		if r.count > worst[0]:
			worst = [r.count, k, r.pairs, worst[3]]
		worst[3] = minf(worst[3], r.floor)
	z.free()
	return worst


func test_model_in_use() -> void:
	assert_true(ZombieModel.has_model(), "modèle cubique branché")
	var z: Zombie = Samples.make(host, "marche")
	assert_near(z.skel.get_bone_rest(z.bones.hips).origin.y, 0.7, 0.001, "repos du bassin du modèle cubique")
	# Au repos, aucun cube ne se traverse (référence de l'outil).
	z.skel.position = Vector3.ZERO
	for b in RigBuilder.BONES:
		z.skel.set_bone_pose_rotation(z.bones[b[0]], Quaternion.IDENTITY)
		z.skel.set_bone_pose_position(z.bones[b[0]], z.skel.get_bone_rest(z.bones[b[0]]).origin)
	var r: Dictionary = _pc().check(z.skel, z.bones)
	assert_eq(r.count, 0, "repos sans interpénétration %s" % r.pairs)
	assert_near(r.floor, 0.0, 0.001, "pieds au sol")
	z.free()


func test_no_interpenetration() -> void:
	var report := []
	for a in Samples.ANIMS:
		var w := _worst(a[0])
		report.append("%s %d (k %.2f) sol %.3f %s" % [a[0], w[0], w[1], w[3], w[2]])
		assert_true(w[0] <= MAX_OVERLAP, "%s : %d cubes se traversent à k=%.2f %s" % [a[0], w[0], w[1], w[2]])
		if not a[0] in OFF_GROUND:
			assert_true(w[3] >= -MAX_SINK, "%s : enfoncé de %.3f m dans le sol" % [a[0], -w[3]])
	print("[voxel_anim] pires images :\n  " + "\n  ".join(report))


func test_readable_poses() -> void:
	# Course et sprint : les deux mains devant le buste.
	for anim in ["course", "sprint"]:
		var z: Zombie = Samples.make(host, anim)
		for i in 4:
			Samples.pose(z, anim, i / 4.0)
			for side in ["l", "r"]:
				var hand := _tip(z, side)
				assert_true(hand.z > 0.3, "%s : main %s devant (z %.2f)" % [anim, side, hand.z])
		z.free()
	# Sortie du sol : une seule main dehors au début, puis les deux.
	var e: Zombie = Samples.make(host, "sortie_du_sol")
	Samples.pose(e, "sortie_du_sol", 0.2)
	var out := 0
	for side in ["l", "r"]:
		if _tip(e, side).y > 0.0:
			out += 1
	assert_eq(out, 1, "une main crève le sol d'abord")
	Samples.pose(e, "sortie_du_sol", 0.5)
	for side in ["l", "r"]:
		assert_true(absf(_tip(e, side).y) < 0.2, "main %s posée sur le sol (y %.2f)" % [side, _tip(e, side).y])
	e.free()
	# Arrachage : mains hautes et devant pour agripper, ramenées vers le buste
	# quand la planche cède (TEAR_RIP).
	var t: Zombie = Samples.make(host, "arrachage")
	Samples.pose(t, "arrachage", 0.25)
	var grab := _tip(t, "l")
	Samples.pose(t, "arrachage", BarricadeRules.TEAR_RIP)
	var rip := _tip(t, "l")
	assert_true(grab.z - rip.z > 0.25, "les mains tirent vers l'arrière (%.2f -> %.2f)" % [grab.z, rip.z])
	assert_true(grab.y > 1.1, "planche agrippée en hauteur (%.2f m)" % grab.y)
	t.free()
	# Passage : à plat ventre au-dessus de l'appui (Barricade.SILL_TOP).
	var v: Zombie = Samples.make(host, "passage_fenetre")
	Samples.pose(v, "passage_fenetre", 0.5)
	var hips := v.skel.transform * v.skel.get_bone_global_pose(v.bones.hips).origin
	var head := v.skel.transform * v.skel.get_bone_global_pose(v.bones.head).origin
	assert_true(absf(head.y - hips.y) < 0.35, "corps à l'horizontale (bassin %.2f, tête %.2f)" % [hips.y, head.y])
	assert_true(hips.y - 0.2 > Barricade.SILL_TOP - 0.05, "au-dessus de l'appui (bassin %.2f m)" % hips.y)
	v.free()


## Bout de la main (paume) du côté `side`, repère du zombie.
func _tip(z: Zombie, side: String) -> Vector3:
	var xf := z.skel.transform * z.skel.get_bone_global_pose(z.bones["forearm_" + side])
	return xf * Vector3(0, -0.45, 0)
