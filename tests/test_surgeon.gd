extends TestCase
## Le Chirurgien (premier boss, GAME_CONCEPT.md §4.4) : modèle cubique de
## 2,5 cm (tools/blender/surgeon/surgeon_voxel.py, SurgeonModel), cœur mutant
## émissif (point faible), animations (SurgeonAnim : poses finies, au-dessus
## du sol, peu de cubes qui se traversent), règles pures (SurgeonRules :
## composition, PV, seuils, entailles, scalpels, onde de choc), schéma des
## vagues de boss (WaveRules, format 22), échantillons (LootRules), XP
## (catégorie boss, XpRules), jauge (BossBar).

const PATH := SurgeonModel.MODEL_PATH
const CELLS := "res://tools/blender/surgeon/surgeon_voxel_cells.json"
const PoseCheck := preload("res://tests/voxel_pose_check.gd")
## Articulations (voir voxel_pose_check.gd).
const LINKS := [["hips", "spine", "plan", 0.1], ["spine", "chest", "plan", 0.1], ["chest", "neck", "boule", 0.22],
		["neck", "head", "boule", 0.2], ["head", "jaw", "boule", 0.3], ["neck", "jaw", "boule", 0.2],
		["chest", "arm_l", "boule", 0.24], ["chest", "arm_r", "boule", 0.24],
		["arm_l", "forearm_l", "plan", 0.1], ["arm_r", "forearm_r", "plan", 0.1],
		["hips", "thigh_l", "plan", 0.15], ["hips", "thigh_r", "plan", 0.15],
		["spine", "thigh_l", "plan", 0.1], ["spine", "thigh_r", "plan", 0.1],
		["thigh_l", "shin_l", "plan", 0.1], ["thigh_r", "shin_r", "plan", 0.1]]
## Cubes qui se traversent tolérés par pose (blouse longue fendue sur les
## cuisses, bras contre le buste).
const MAX_OVERLAP := 160


func test_model() -> void:
	var m := SurgeonModel.model()
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
	assert_true(hi.y > 2.2 and hi.y < 2.45, "géant : %.2f m" % hi.y)
	for b in RigBuilder.BONES:
		assert_true(m.overrides.has(b[0]), "os %s" % b[0])
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var eyes := 0
	var heart := 0
	for c in cols:
		if c.a < 0.25:
			eyes += 1
		elif c.a < 0.75:
			heart += 1
	assert_true(eyes > 0, "yeux émissifs")
	assert_true(heart > 0, "cœur mutant émissif (alpha %.1f)" % ZombieGlb.HEART_ALPHA)
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
	assert_true((data.mats as Array).has("heart"), "matière du cœur")


func test_build_and_hit_shapes() -> void:
	var skel := SurgeonModel.build()
	assert_eq(skel.get_bone_count(), RigBuilder.BONES.size(), "ossature du jeu")
	var mi := skel.get_node("Mesh") as MeshInstance3D
	assert_true(mi.material_override == SurgeonModel.material(), "matériau cubique")
	assert_eq(mi.layers, ZombieModel.RENDER_LAYERS)
	skel.free()
	var s := SurgeonModel.hit_shapes()
	var body: Array = s.body
	assert_true(body[1] > 0.15 and body[1] < 0.4, "rayon du tronc %.2f" % body[1])
	assert_true((body[0] as Vector3).y > 1.0 and (body[0] as Vector3).y < 1.7, "tronc à hauteur du buste (%.2f)" % (body[0] as Vector3).y)
	var heart: Array = s.heart
	assert_true(heart[1] >= 0.12 and heart[1] < 0.25, "rayon du cœur %.2f" % heart[1])
	var bb := SurgeonModel.bone_bounds()
	var hc: Vector3 = (bb.heart as AABB).get_center()
	assert_true(hc.y > 1.45 and hc.y < 1.8 and hc.z > 0.08, "cœur sur la poitrine, devant (%s)" % hc)


func _check_pose(pc: RefCounted, skel: Skeleton3D, bones: Dictionary, p: Dictionary, what: String) -> Dictionary:
	SurgeonAnim.apply(skel, bones, p)
	for n in p.bones:
		var v: Vector3 = p.bones[n]
		assert_true(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "%s : %s fini" % [what, n])
	var r: Dictionary = pc.check(skel, bones)
	assert_true(int(r.count) <= MAX_OVERLAP, "%s : %d cubes se traversent %s" % [what, r.count, r.pairs])
	return r


func test_animations() -> void:
	var skel := SurgeonModel.build()
	host.add_child(skel)
	var bones := RigBuilder.bone_indices(skel)
	var pc := PoseCheck.new(SurgeonModel.model().overrides, CELLS, LINKS)
	var worst := 0
	var A := SurgeonAnim
	for rage in [false, true]:
		for move in [1.0, 0.0]:
			for i in 8:
				var r := _check_pose(pc, skel, bones, A.pose(i * TAU / 8.0, move, i * 0.3, A.NONE, 0.0, rage), "marche %.1f #%d" % [move, i])
				worst = maxi(worst, r.count)
				assert_true(float(r.floor) > -0.06, "marche #%d : au-dessus du sol (%.3f)" % [i, r.floor])
	for i in 10:
		var t := i * 0.25
		for act in [A.SLASH_WINDUP, A.SLASH, A.THROW_WINDUP, A.THROW, A.SURGERY, A.ROAR]:
			var r := _check_pose(pc, skel, bones, A.pose(0.0, 0.0, t, act, t), "action %d à %.2f s" % [act, t])
			worst = maxi(worst, r.count)
			assert_true(float(r.floor) > -0.08, "action %d à %.2f s : au-dessus du sol (%.3f)" % [act, t, r.floor])
	for t in [0.2, 0.5, 0.9, 1.2, 1.6, 2.5]:
		var r := _check_pose(pc, skel, bones, A.pose(0.0, 0.0, 0.0, A.NONE, 0.0, false, t), "mort %.1f s" % t)
		assert_true(float(r.floor) > -0.1, "mort %.1f s : rien sous le sol (%.3f)" % [t, r.floor])
	# Rugissement : gueule ouverte ; mort : sur le dos.
	assert_true((A.pose(0.0, 0.0, 0.0, A.ROAR, 1.2).bones.jaw as Vector3).x > 0.5, "rugissement : gueule ouverte")
	assert_near(float(A.pose(0.0, 0.0, 0.0, A.NONE, 0.0, false, 3.0).pitch), A.DEATH_PITCH, 0.001, "mort : sur le dos")
	# Entailles en aller-retour : le bras balaie dans un sens puis dans l'autre.
	var y1: float = (A.pose(0.0, 0.0, 0.0, A.SLASH, 0.2).bones.arm_r as Vector3).y
	var y2: float = (A.pose(0.0, 0.0, 0.0, A.SLASH, SurgeonRules.SLASH_TIME + 0.2).bones.arm_r as Vector3).y
	assert_true(y1 > 0.0 and y2 < 0.0, "aller-retour (%.2f, %.2f)" % [y1, y2])
	print("[test_surgeon] pire recouvrement : %d cubes" % worst)
	skel.free()


func test_rules() -> void:
	assert_eq(SurgeonRules.count(1), 1, "un seul boss")
	assert_eq(SurgeonRules.count(4), 1)
	assert_eq(SurgeonRules.escorts(1), 6)
	assert_eq(SurgeonRules.escorts(8), SurgeonRules.ESCORT_MAX)
	assert_eq(SurgeonRules.summons(1), 2)
	assert_eq(SurgeonRules.summons(8), SurgeonRules.SUMMON_MAX)
	# PV : 30 × zombie de la manche, +75 % par joueur en plus, +25 % par apparition.
	assert_eq(SurgeonRules.health(15, 1, 1), 46500)
	assert_eq(SurgeonRules.health(15, 1, 4), 151125)
	assert_eq(SurgeonRules.health(30, 2, 1), 114375)
	assert_true(SurgeonRules.health(30, 2, 1) > SurgeonRules.health(30, 1, 1), "plus fort à chaque apparition")
	# Seuils.
	assert_false(SurgeonRules.enraged(600, 1000))
	assert_true(SurgeonRules.enraged(500, 1000), "phase 2 à 50 %")
	assert_eq(SurgeonRules.surgery_due(800, 1000, 0), -1)
	assert_eq(SurgeonRules.surgery_due(750, 1000, 0), 0, "1re opération à 75 %")
	assert_eq(SurgeonRules.surgery_due(700, 1000, 1), -1, "faite une fois")
	assert_eq(SurgeonRules.surgery_due(200, 1000, 1), 1, "2e opération à 25 %")
	assert_eq(SurgeonRules.surgery_due(200, 1000, 0), 0, "les deux seuils franchis d'un coup : dans l'ordre")
	# Phase 2 : plus de coups et de scalpels, préparations plus courtes, plus rapide.
	assert_true(SurgeonRules.slash_hits(true) > SurgeonRules.slash_hits(false))
	assert_true(SurgeonRules.throw_count(true) > SurgeonRules.throw_count(false))
	assert_true(SurgeonRules.slash_windup(true) < SurgeonRules.slash_windup(false))
	assert_true(SurgeonRules.walk_speed(true) > SurgeonRules.walk_speed(false))
	# Entaille : arc devant lui.
	var fwd := Vector3(0, 0, 1)
	assert_true(SurgeonRules.in_slash_arc(Vector3(0.5, 0, 1.5), fwd), "devant : touché")
	assert_false(SurgeonRules.in_slash_arc(Vector3(0, 0, -1.5), fwd), "derrière : épargné")
	assert_false(SurgeonRules.in_slash_arc(Vector3(0, 0, 3.5), fwd), "trop loin")
	# Lancer : portée, vue, recharge.
	assert_true(SurgeonRules.can_throw(10.0, 0.0, true, 0.0))
	assert_false(SurgeonRules.can_throw(3.0, 0.0, true, 0.0), "trop près : combo")
	assert_false(SurgeonRules.can_throw(10.0, 0.0, false, 0.0), "pas en vue")
	assert_false(SurgeonRules.can_throw(10.0, 0.0, true, 1.0), "recharge")
	var fan := SurgeonRules.fan_dirs(Vector3(0, 0, 1), 3)
	assert_eq(fan.size(), 3)
	assert_near(fan[1].x, 0.0, 0.001, "scalpel du milieu droit sur la cible")
	assert_true(fan[0].x < 0.0 and fan[2].x > 0.0, "éventail symétrique")
	# Vol : un scalpel visé atteint la cible (chute compensée).
	var from := Vector3(0, 1.75, 0)
	var to := Vector3(0, 1.1, 12)
	var v := SurgeonRules.throw_velocity(from, to, Vector3(0, 0, 1))
	var t := 12.0 / SurgeonRules.THROW_SPEED
	var at := SurgeonRules.scalpel_pos(from, v, t)
	assert_true(at.distance_to(to) < 0.3, "le scalpel arrive sur la cible (%s)" % at)
	assert_true(SurgeonRules.scalpel_hits(Vector3(0, 1.2, 11.8), Vector3(0, 1.2, 12.2), Vector3(0.2, 0, 12)), "joueur touché")
	assert_false(SurgeonRules.scalpel_hits(Vector3(1.5, 1.2, 11.8), Vector3(1.5, 1.2, 12.2), Vector3(0, 0, 12)), "à côté : esquivé")
	assert_false(SurgeonRules.scalpel_hits(Vector3(0, 2.6, 11.8), Vector3(0, 2.6, 12.2), Vector3(0, 0, 12)), "au-dessus de la tête")
	# Onde de choc.
	assert_true(SurgeonRules.in_shock(Vector3(2, 0, 2)))
	assert_false(SurgeonRules.in_shock(Vector3(5, 0, 5)))
	var kv := SurgeonRules.shock_velocity(Vector3(2, 0, 0))
	assert_true(kv.x > 5.0 and kv.y > 2.0, "repoussé et soulevé %s" % kv)


func test_boss_schedule() -> void:
	var s := WaveRules.default_schedule()
	assert_true(WaveRules.has_boss(s), "boss par défaut")
	assert_eq(WaveRules.boss_types(s), ["chirurgien"])
	assert_eq(WaveRules.wave_kind(s, 15, WaveRules.has_boss(s)), WaveRules.BOSS)
	assert_eq(WaveRules.boss_type_at(s, 15), "chirurgien")
	assert_eq(WaveRules.boss_type_at(s, 14), "")
	assert_eq(WaveRules.boss_rank(s, 30), 2)
	assert_eq(WaveRules.next_boss_of(s, WaveRules.CHIRURGIEN, 0), 15)
	assert_eq(WaveRules.next_boss_of(s, WaveRules.CHIRURGIEN, 15), 30)
	# Rotation des vagues spéciales avec le boss : la 15 est une vague de boss.
	var seq := []
	for n in [5, 10, 15, 20, 25, 30, 35]:
		seq.append(WaveRules.special_type_at(s, n, true))
	assert_eq(seq, ["meute", "brancardier", "", "infirmiere", "meute", "", "brancardier"], "boss exclus de la rotation")
	# Carte sans boss : rien.
	var none := WaveRules.parse({"boss": {"premiere": 0, "intervalle": 0}})
	assert_false(WaveRules.has_boss(none))
	assert_eq(WaveRules.next_boss_of(none, WaveRules.CHIRURGIEN, 0), 0)
	# Lecture tolérante des types de boss.
	assert_eq(WaveRules.parse_boss_types(["x", "chirurgien"]), ["chirurgien"])
	assert_eq(WaveRules.parse_boss_types("x"), ["chirurgien"], "illisible : tous")


func test_map_format_22() -> void:
	assert_true(EditorMap.FORMAT >= 22, "format 22 et plus")
	var m := EditorMap.blank()
	EditorMap.set_boss_types(m.carte, ["chirurgien"])
	assert_false(m.carte.has("vagues"), "tous les boss : défaut, non écrit")
	EditorMap.set_waves(m.carte, WaveRules.BOSS, 0, 0)
	assert_true(m.carte.has("vagues"), "carte sans boss : écrit")
	assert_false(WaveRules.has_boss(EditorMap.waves_of(m.carte)))
	var texts := m.file_texts()
	assert_true(CustomMapGuard.check_texts(texts).ok, "carte reçue acceptée : %s" % str(CustomMapGuard.check_texts(texts).get("reasons")))
	# Liste de boss écrite à la main : acceptée si connue, refusée sinon.
	(m.carte.vagues as Dictionary)[WaveRules.BOSS_TYPES_KEY] = ["chirurgien"]
	texts = m.file_texts()
	assert_true(String(texts["carte.json"]).contains("types_boss"), "liste écrite")
	assert_true(CustomMapGuard.check_texts(texts).ok, "types_boss connu accepté : %s" % str(CustomMapGuard.check_texts(texts).get("reasons")))
	texts["carte.json"] = String(texts["carte.json"]).replace("\"chirurgien\"", "\"dentiste\"")
	assert_true(String(texts["carte.json"]).contains("dentiste"), "remplacement fait")
	assert_false(CustomMapGuard.check_texts(texts).ok, "boss inconnu refusé")
	# Ancienne carte (format 21) : lue telle quelle, boss par défaut.
	var old := EditorMap.blank().file_texts()
	old["carte.json"] = String(old["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 21")
	var o := EditorMap.from_texts(old)
	assert_true(o.load_errors.is_empty(), "format 21 lu sans erreur")
	assert_true(WaveRules.has_boss(EditorMap.waves_of(o.carte)), "boss par défaut")


func test_samples_xp_loot() -> void:
	var ids := []
	for s in LootRules.SAMPLES.surgeon:
		ids.append(s[0])
	assert_eq(ids, ["surgeon_scalpel", "surgeon_heart"], "scalpel, cœur mutant")
	assert_true(HubData.known_sample("surgeon_heart"))
	assert_true(LootRules.sample_name("surgeon_heart") in ["CŒUR MUTANT", "MUTANT HEART"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_eq(Array(LootRules.roll_samples("surgeon", rng, LootRules.BOSS_SAMPLE_CHANCE)), ids, "le boss : les deux à coup sûr")
	assert_eq(XpRules.category_of(XpRules.SURGEON), XpRules.BOSS, "catégorie boss")
	var r: Array = XpRules.CATEGORY_RANGE[XpRules.BOSS]
	assert_true(XpRules.base_xp(XpRules.SURGEON) >= r[0] and XpRules.base_xp(XpRules.SURGEON) <= r[1], "dans la fourchette")
	assert_eq(HubIcon.sample_art("surgeon_scalpel"), "scalpel", "icône du hub")
	assert_eq(HubIcon.sample_art("surgeon_heart"), "heart")
	# Butin d'une vague de boss : 2 armes par joueur, raretés plus hautes.
	assert_eq(LootRules.weapons_for_wave(WaveRules.BOSS), 2)
	var sum := 0.0
	for w in LootRules.RARITY_WEIGHTS_BOSS:
		sum += w
	assert_near(sum, 100.0, 0.001, "probabilités de boss : 100 %")
	assert_true(LootRules.RARITY_WEIGHTS_BOSS[0] < LootRules.RARITY_WEIGHTS[0], "moins de communes qu'une vague spéciale")
	var rare := [0, 0]
	rng.seed = 11
	for i in 4000:
		if LootRules.roll_rarity(rng) >= OwnedWeapon.Rarity.EPIC:
			rare[0] += 1
		if LootRules.roll_rarity(rng, WaveRules.BOSS) >= OwnedWeapon.Rarity.EPIC:
			rare[1] += 1
	assert_true(rare[1] > rare[0] * 1.5, "épiques et mieux plus fréquentes au boss (%d contre %d)" % [rare[1], rare[0]])
	# Codex : fiche réelle (plus « prévue »), XP de son propre barème.
	CodexData.clear_cache()
	var e := CodexData.default().entry("surgeon")
	assert_false(e.is_empty() or e.planned, "fiche du codex jouable")
	assert_eq(CodexData.xp(e), XpRules.base_xp(XpRules.SURGEON))


func test_boss_bar() -> void:
	assert_eq(BossBar.lit_cells(1.0), BossBar.CELLS)
	assert_eq(BossBar.lit_cells(0.0), 0)
	assert_eq(BossBar.lit_cells(0.001), 1, "au moins un cube tant qu'il vit")
	assert_eq(BossBar.lit_cells(0.5), BossBar.CELLS / 2)
	var bar := BossBar.new(SurgeonRound.bar_title())
	host.add_child(bar)
	bar.set_fraction(0.3, true)
	assert_near(bar.fraction, 0.3, 0.001)
	assert_true(bar.rage)
	bar.free()
	for t in [SurgeonRound.banner_text(), SurgeonRound.surgery_text(), SurgeonRound.rage_text(), SurgeonRound.death_text()]:
		assert_true(t != "", "texte")
