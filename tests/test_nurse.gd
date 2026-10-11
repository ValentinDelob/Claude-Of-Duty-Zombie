extends TestCase
## L'Infirmière hurlante (mini-boss de vague spéciale, GAME_CONCEPT.md §4.4) :
## modèle cubique de 2,5 cm (tools/blender/nurse/nurse_voxel.py, NurseModel),
## animations (NurseAnim : poses finies, au-dessus du sol, peu de cubes qui
## se traversent), règles pures (NurseRules : composition, PV, distances,
## cri, étourdissement, zombies ameutés, fuite), échantillons (LootRules,
## icônes du hub), XP (catégorie mini-boss, XpRules), rotation des vagues
## spéciales à trois types (WaveRules) et étourdissement du joueur.

const PATH := NurseModel.MODEL_PATH
const CELLS := "res://tools/blender/nurse/nurse_voxel_cells.json"
const PoseCheck := preload("res://tests/voxel_pose_check.gd")
## Articulations (voir voxel_pose_check.gd).
const LINKS := [["hips", "spine", "plan", 0.1], ["spine", "chest", "plan", 0.1], ["chest", "neck", "boule", 0.15],
		["neck", "head", "boule", 0.15], ["head", "jaw", "boule", 0.2], ["neck", "jaw", "boule", 0.2],
		["chest", "arm_l", "boule", 0.2], ["chest", "arm_r", "boule", 0.2],
		["arm_l", "forearm_l", "plan", 0.1], ["arm_r", "forearm_r", "plan", 0.1],
		["hips", "thigh_l", "plan", 0.15], ["hips", "thigh_r", "plan", 0.15],
		["spine", "thigh_l", "plan", 0.1], ["spine", "thigh_r", "plan", 0.1],
		["thigh_l", "shin_l", "plan", 0.1], ["thigh_r", "shin_r", "plan", 0.1],
		["thigh_l", "thigh_r", "plan", 0.1]]
## Cubes qui se traversent tolérés par pose (jupe en deux moitiés sur les
## cuisses, bras maigres contre le buste, mâchoire décrochée).
const MAX_OVERLAP := 40


func test_model() -> void:
	var m := NurseModel.model()
	assert_false(m.is_empty(), "modèle chargé")
	if m.is_empty():
		return
	var mesh: ArrayMesh = m.mesh
	assert_eq(mesh.get_surface_count(), 1, "un seul mesh (un draw call)")
	var a := mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	@warning_ignore("integer_division")
	var tris := (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_true(tris > 2000 and tris < 9000, "budget : %d triangles (< 9 000)" % tris)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in pos:
		lo = lo.min(p)
		hi = hi.max(p)
	assert_near(lo.y, 0.0, 0.001, "pieds au sol")
	assert_true(hi.y > 1.75 and hi.y < 2.0, "grande et décharnée : %.2f m avec la coiffe" % hi.y)
	assert_true(hi.x - lo.x > 0.5 and hi.x - lo.x < 0.8, "carrure %.2f m" % (hi.x - lo.x))
	for b in RigBuilder.BONES:
		assert_true(m.overrides.has(b[0]), "os %s" % b[0])
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var glow := 0
	for c in cols:
		if c.a < 0.5:
			glow += 1
	assert_true(glow > 0, "yeux et gorge émissifs")
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
	# Silhouette et échantillons modélisés : coiffe, seringue, badge, cordes vocales.
	for part in ["cap", "syringe", "badge", "vocal_cords", "hair", "skirt"]:
		assert_true((data.parts as Array).has(part), "partie « %s » modélisée" % part)


func test_build_and_hit_shapes() -> void:
	var skel := NurseModel.build()
	assert_eq(skel.get_bone_count(), RigBuilder.BONES.size(), "ossature du jeu")
	var mi := skel.get_node("Mesh") as MeshInstance3D
	assert_true(mi.material_override == NurseModel.material(), "matériau cubique")
	assert_eq(mi.layers, ZombieModel.RENDER_LAYERS, "hors des décalques de sang")
	skel.free()
	var s := NurseModel.hit_shapes()
	var body: Array = s.body
	assert_true(body[1] > 0.12 and body[1] < 0.3, "rayon du tronc %.2f" % body[1])
	assert_true(body[2] > 0.6 and body[2] < 1.2, "hauteur du tronc %.2f" % body[2])
	assert_true((body[0] as Vector3).y > 0.8 and (body[0] as Vector3).y < 1.25, "tronc à hauteur du buste (%.2f)" % (body[0] as Vector3).y)
	var head: Array = s.head
	assert_true(head[1] > 0.09 and head[1] < 0.22, "rayon de tête %.2f" % head[1])
	var throat: Array = s.throat
	assert_true((throat[0] as Vector3).z > 0.0, "gorge devant le cou (%s)" % throat[0])


func _check_pose(pc: RefCounted, skel: Skeleton3D, bones: Dictionary, p: Dictionary, what: String) -> Dictionary:
	NurseAnim.apply(skel, bones, p)
	for n in p.bones:
		var v: Vector3 = p.bones[n]
		assert_true(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "%s : %s fini" % [what, n])
	var r: Dictionary = pc.check(skel, bones)
	assert_true(int(r.count) <= MAX_OVERLAP, "%s : %d cubes se traversent %s" % [what, r.count, r.pairs])
	return r


func test_animations() -> void:
	var skel := NurseModel.build()
	host.add_child(skel)
	var bones := RigBuilder.bone_indices(skel)
	var pc := PoseCheck.new(NurseModel.model().overrides, CELLS, LINKS)
	var worst := 0
	var A := NurseAnim
	for move in [1.8, 1.0, 0.5, 0.0]:
		for i in 8:
			var r := _check_pose(pc, skel, bones, A.pose(i * TAU / 8.0, move, i * 0.3), "marche %.1f #%d" % [move, i])
			worst = maxi(worst, r.count)
			assert_true(float(r.floor) > -0.06, "marche %.1f #%d : au-dessus du sol (%.3f)" % [move, i, r.floor])
	for i in 8:
		var t := i * 0.2
		var r := _check_pose(pc, skel, bones, A.pose(0.0, 0.0, t, A.WINDUP, t), "préparation %.2f s" % t)
		worst = maxi(worst, r.count)
		assert_true(float(r.floor) > -0.06, "préparation : au-dessus du sol (%.3f)" % r.floor)
		r = _check_pose(pc, skel, bones, A.pose(0.0, 0.0, t, A.SCREAM, t * 0.75), "cri %.2f s" % (t * 0.75))
		worst = maxi(worst, r.count)
		assert_true(float(r.floor) > -0.06, "cri : au-dessus du sol (%.3f)" % r.floor)
		r = _check_pose(pc, skel, bones, A.pose(0.0, 0.0, t, A.CHOKE, t * 1.2), "étranglée %.2f s" % (t * 1.2))
		worst = maxi(worst, r.count)
		assert_true(float(r.floor) > -0.08, "étranglée : au-dessus du sol (%.3f)" % r.floor)
		var k := i / 7.0
		r = _check_pose(pc, skel, bones, A.pose(0.0, 0.0, 0.0, A.NONE, 0.0, k), "seringue %.2f" % k)
		worst = maxi(worst, r.count)
		r = _check_pose(pc, skel, bones, A.pose(0.0, 1.0, t, A.NONE, 0.0, -1.0, -1.0, k * A.HIT_TIME), "touchée %.2f" % k)
		worst = maxi(worst, r.count)
	for t in [0.2, 0.5, 0.8, 1.0, 1.3, 2.0]:
		var r := _check_pose(pc, skel, bones, A.pose(0.0, 0.0, t, A.NONE, 0.0, -1.0, t), "mort %.1f s" % t)
		assert_true(float(r.floor) > -0.1, "mort %.1f s : rien sous le sol (%.3f)" % [t, r.floor])
	# Cri : gueule grande ouverte ; préparation : tête renversée ; mort : sur le dos.
	assert_true((A.pose(0.0, 0.0, 0.0, A.SCREAM, 0.5).bones.jaw as Vector3).x > 1.0, "cri : gueule béante")
	assert_true((A.pose(0.0, 0.0, 0.0, A.WINDUP, 1.0).bones.head as Vector3).x < -0.2, "préparation : tête renversée")
	assert_true((A.pose(0.0, 0.0, 0.0, A.WINDUP, 1.0).bones.arm_l as Vector3).z > 0.8, "préparation : bras écartés")
	assert_near(float(A.pose(0.0, 0.0, 0.0, A.NONE, 0.0, -1.0, 3.0).pitch), A.DEATH_PITCH, 0.001, "mort : sur le dos")
	print("[test_nurse] pire recouvrement : %d cubes" % worst)
	skel.free()


func test_rules() -> void:
	assert_eq(NurseRules.count(1), 1, "1 Infirmière par joueur")
	assert_eq(NurseRules.count(3), 3)
	assert_eq(NurseRules.count(8), NurseRules.MAX_TOTAL, "plafond")
	assert_eq(NurseRules.escorts(1), 6, "escorte en solo")
	assert_eq(NurseRules.escorts(8), NurseRules.ESCORT_MAX)
	# PV : 8 × PV d'un zombie de la manche, +20 % par vague de l'Infirmière.
	assert_eq(NurseRules.health(15, 1), 12400)
	assert_eq(NurseRules.health(30, 2), 29280)
	assert_true(NurseRules.health(15, 1) < BrancardRules.health(15, 1), "plus fragile que le Brancardier")
	# Cri : portée, niveau, vue, délai.
	assert_true(NurseRules.can_scream(9.0, 0.0, true, 0.0))
	assert_false(NurseRules.can_scream(20.0, 0.0, true, 0.0), "trop loin")
	assert_false(NurseRules.can_scream(9.0, 3.0, true, 0.0), "autre niveau")
	assert_false(NurseRules.can_scream(9.0, 0.0, false, 0.0), "pas en vue")
	assert_false(NurseRules.can_scream(9.0, 0.0, true, 2.0), "délai")
	# Distances gardées.
	assert_eq(NurseRules.move_mode(3.0, true), "flee", "trop près : elle fuit")
	assert_eq(NurseRules.move_mode(9.0, true), "hold", "à bonne distance : elle guette")
	assert_eq(NurseRules.move_mode(9.0, false), "approach", "hors de vue : elle approche")
	assert_eq(NurseRules.move_mode(20.0, true), "approach", "trop loin : elle approche")
	# Étourdissement : plus long et plus fort de près, rien hors de portée.
	assert_near(NurseRules.daze_time(0.0), NurseRules.DAZE_TIME_MAX, 0.001)
	assert_true(NurseRules.daze_time(2.0) > NurseRules.daze_time(9.0), "plus long de près")
	assert_eq(NurseRules.daze_time(NurseRules.DAZE_RADIUS + 0.5), 0.0, "hors de portée : épargné")
	assert_true(NurseRules.daze_strength(1.0) > NurseRules.daze_strength(10.0))
	assert_near(NurseRules.daze_speed_mult(1.0), 1.0 - NurseRules.DAZE_SLOW, 0.001, "ralenti, jamais immobile")
	assert_near(NurseRules.daze_speed_mult(0.0), 1.0, 0.001)
	assert_true(NurseRules.rallies(15.0) and not NurseRules.rallies(NurseRules.RALLY_RADIUS + 1.0), "zombies ameutés dans le rayon")
	# Fuite : point loin du joueur, du côté opposé ; refusé trop près d'un joueur.
	var me := Vector3.ZERO
	var threat := [Vector3(3, 0, 0)]
	var away := NurseRules.flee_score(me, Vector3(-8, 0, 0), threat)
	var toward := NurseRules.flee_score(me, Vector3(8, 0, 0), threat)
	var side := NurseRules.flee_score(me, Vector3(0, 0, 8), threat)
	assert_true(away > side, "loin du joueur plutôt que de côté (%.1f > %.1f)" % [away, side])
	assert_eq(toward, -INF, "jamais vers le joueur")
	assert_eq(NurseRules.flee_score(me, Vector3(-1, 0, 0), threat), -INF, "trop près d'elle")
	assert_eq(NurseRules.flee_score(me, Vector3(-30, 0, 0), threat), -INF, "trop loin d'elle")


func test_samples_xp() -> void:
	var ids := []
	for s in LootRules.SAMPLES.nurse:
		ids.append(s[0])
	assert_eq(ids, ["nurse_vocal_cords", "nurse_syringe", "nurse_badge"], "cordes vocales, seringue cassée, badge")
	assert_true(LootRules.sample_name("nurse_syringe") in ["SERINGUE CASSÉE", "BROKEN SYRINGE"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var got := {}
	for i in 2000:
		for s in LootRules.roll_samples("nurse", rng):
			got[s] = int(got.get(s, 0)) + 1
	for id in ids:
		assert_true(int(got.get(id, 0)) > 330 and int(got.get(id, 0)) < 470, "%s : ~20 %% (%d / 2000)" % [id, got.get(id, 0)])
	assert_eq(XpRules.category_of(XpRules.NURSE), XpRules.MINIBOSS, "catégorie mini-boss")
	var r: Array = XpRules.CATEGORY_RANGE[XpRules.MINIBOSS]
	assert_true(XpRules.base_xp(XpRules.NURSE) >= r[0] and XpRules.base_xp(XpRules.NURSE) <= r[1], "dans la fourchette")
	assert_eq(XpRules.kill_xp(XpRules.NURSE, 15), roundi(60 * XpRules.round_factor(15)))
	assert_true(HubRenders.has(HubRenders.sample_path("nurse_vocal_cords")), "rendu du hub : nurse_vocal_cords")
	assert_true(HubRenders.has(HubRenders.sample_path("nurse_syringe")), "rendu du hub : nurse_syringe")
	assert_true(HubRenders.has(HubRenders.sample_path("nurse_badge")), "rendu du hub : nurse_badge")
	# Codex : fiche active (plus « prévue »), mêmes sortes que le butin.
	CodexData.clear_cache()
	var e: Dictionary = CodexData.default().entry("nurse")
	assert_false(bool(e.get("planned", false)), "codex : l'Infirmière n'est plus « prévue »")
	assert_eq(Array(e.samples), ids)
	assert_eq(CodexData.xp(e), XpRules.base_xp(XpRules.NURSE))
	assert_eq(int(e.round), WaveRules.next_special_of(WaveRules.DEFAULT, WaveRules.INFIRMIERE, 0, WaveRules.has_boss(WaveRules.DEFAULT)), "codex : manche de la première vague (boss à la 15)")


func test_rotation_three_types() -> void:
	var s := WaveRules.default_schedule()
	var seq := []
	for n in [5, 10, 15, 20, 25, 30]:
		seq.append(WaveRules.special_type_at(s, n))
	assert_eq(seq, ["meute", "brancardier", "infirmiere", "meute", "brancardier", "infirmiere"], "rotation par défaut")
	assert_eq(WaveRules.next_special_of(s, WaveRules.INFIRMIERE, 0), 15)
	assert_eq(WaveRules.next_special_of(s, WaveRules.INFIRMIERE, 15), 30)
	# Avec un boss (15, 30...) : la 15 est de boss, l'Infirmière passe à la 20.
	assert_eq(WaveRules.special_type_at(s, 20, true), "infirmiere")
	var only := WaveRules.parse({"types_speciaux": ["infirmiere"]})
	assert_eq(WaveRules.special_type_at(only, 5), "infirmiere", "carte à Infirmière seule")
	assert_eq(WaveRules.next_special_of(only, WaveRules.MEUTE, 0), 0)
	# Une carte qui listait les deux anciens types les garde (pas d'Infirmière).
	var old := WaveRules.parse({"types_speciaux": ["meute", "brancardier"]})
	assert_eq(WaveRules.next_special_of(old, WaveRules.INFIRMIERE, 0), 0, "carte à deux types : pas d'Infirmière")
	# Carte reçue avec l'Infirmière : acceptée.
	var m := EditorMap.blank()
	EditorMap.set_special_types(m.carte, ["infirmiere", "meute"])
	assert_eq(WaveRules.special_types(EditorMap.waves_of(m.carte)), ["meute", "infirmiere"], "ordre canonique")
	assert_true(CustomMapGuard.check_texts(m.file_texts()).ok, "carte avec l'Infirmière acceptée")


func test_daze_player_rules() -> void:
	# Étourdissement d'un joueur local (sans partie) : force qui s'éteint,
	# vitesse réduite, un nouveau cri prolonge.
	var p := Player.new()
	p._daze_left = 0.0
	assert_eq(p.daze_amount(), 0.0)
	p.daze(2.0, 0.8)
	assert_eq(p.dazes, 1)
	assert_near(p.daze_amount(), 0.8, 0.001, "force pleine au début")
	p._daze_left = 1.0
	assert_near(p.daze_amount(), 0.4, 0.001, "s'éteint avec le temps")
	p.daze(0.5, 0.3)
	assert_near(p._daze_left, 1.0, 0.001, "un cri plus court ne raccourcit pas")
	assert_near(p._daze_k, 0.8, 0.001, "ni n'affaiblit")
	p.downed = true
	p.daze(3.0, 1.0)
	assert_eq(p.dazes, 2, "à terre : pas étourdi")
	p.free()
