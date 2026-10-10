extends AutotestScenario
## Apparence et animations des zombies (façon Black Ops 1), sous les lumières
## du quai du BUNKER K-7 : captures de face, de
## profil et de dos de chaque archétype, gros plans, vue à 10 m, puis chaque
## animation (marche, trot, course, sprint, attaque, émergence, arrachage de
## planches, enjambement, reptation, démembrement, morts).
##
## Les zombies exposés sont des marionnettes locales (ni IA ni physique) :
## le scénario fixe leur état et leur vitesse d'animation.

var H := AutotestHelpers
var game: Game
var p: Player
var zm: ZombieManager
var cam: Camera3D
var _next_id := 60001
var _shown: Array[Zombie] = []
var _prefix := ""
var _stage := Vector3.ZERO
var _far_dir := Vector3.BACK

## [carte, centre de la scène (les zombies y sont alignés sur X, la caméra
## regarde vers -Z)].
const STAGES := [
	["bunker_k7", Vector3(33.5, 0.0, 4.6), Vector3(1, 0, 0)],
]


func run() -> void:
	timeout_sec = 420
	_model_checks()
	for i in STAGES.size():
		var st: Array = STAGES[i]
		if i > 0:
			Router.back_to_menu()
			await seconds(0.5)  # le menu lui-même est attendu par start_solo_game
		p = await H.start_solo_game(self, st[0])
		if p == null:
			return
		_setup(st[0], st[1])
		_far_dir = st[2]
		await _gallery()
		await _animations()
		_clear()
		if i == 0:
			await _perf_ab()
		p.camera.make_current()
		cam.queue_free()


# --------------------------------------------------------------------------
# Vérifications du modèle (hors partie)
# --------------------------------------------------------------------------

func _model_checks() -> void:
	ZombieModel.clear_cache()
	var t0 := Time.get_ticks_usec()
	var counts := []
	var meshes := {}
	for a in ZombieModel.Arch.size():
		var v := ZombieModel.variant_of(a)
		counts.append(ZombieModel.vertex_count(v))
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0 / ZombieModel.Arch.size()
	var tp := Time.get_ticks_usec()
	for a in ZombieModel.Arch.size():
		ZombieModel.parts_for(ZombieModel.variant_of(a))
	print("[zombie_look] dont description des pièces : %.1f ms/look" % ((Time.get_ticks_usec() - tp) / 1000.0 / ZombieModel.Arch.size()))
	print("[zombie_look] sommets par archétype : %s ; construction d'un look %.1f ms" % [counts, first_ms])
	for c in counts:
		at.check(c >= 1500 and c <= 9000, "budget de sommets (%d)" % c)
	at.check(first_ms < 60.0, "construction d'un look raisonnable (%.1f ms)" % first_ms)
	# Toutes les variantes : looks mis en cache et partagés.
	var tb := Time.get_ticks_usec()
	for i in 48:
		var s := ZombieModel.build(i * 131)
		meshes[(s.get_node("Mesh") as MeshInstance3D).mesh] = true
		s.free()
	var build_ms := (Time.get_ticks_usec() - tb) / 1000.0 / 48.0
	print("[zombie_look] construction moyenne (cache rempli au fil de l'eau) : %.2f ms" % build_ms)
	tb = Time.get_ticks_usec()
	for i in 24:
		ZombieModel.build(i * 131).free()
	var cached_ms := (Time.get_ticks_usec() - tb) / 1000.0 / 24.0
	print("[zombie_look] construction en cache : %.3f ms" % cached_ms)
	at.check(cached_ms < 1.0, "zombie en cache construit en %.3f ms (< 1 ms)" % cached_ms)
	at.check(meshes.size() > 10 and meshes.size() <= ZombieModel.LOOK_COUNT, "%d looks distincts partagés" % meshes.size())
	var arch_meshes := {}
	for a in ZombieModel.Arch.size():
		var s := ZombieModel.build(ZombieModel.variant_of(a))
		arch_meshes[(s.get_node("Mesh") as MeshInstance3D).mesh] = true
		var bi := RigBuilder.bone_indices(s)
		at.check(bi.jaw >= 0, "os de mâchoire (%s)" % ZombieModel.ARCH_NAMES[a])
		s.free()
	at.check(arch_meshes.size() == ZombieModel.Arch.size(), "6 archétypes distincts")
	# Yeux émissifs (alpha < 1) et couleurs converties en linéaire.
	var s0 := ZombieModel.build(0)
	var arr := (s0.get_node("Mesh") as MeshInstance3D).mesh.surface_get_arrays(0)
	s0.free()
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var glow := 0
	for c in cols:
		if c.a < 0.5:
			glow += 1
	at.check(glow > 0, "yeux émissifs (%d sommets)" % glow)
	for bones in [["forearm_l"], ["forearm_r"], ["thigh_l", "shin_l"], ["thigh_r", "shin_r"]]:
		var m := ZombieModel.limb_mesh(3, bones)
		at.check(m.get_surface_count() == 1 and m.surface_get_array_len(0) > 50, "morceau arraché %s" % [bones])


# --------------------------------------------------------------------------
# Mise en scène
# --------------------------------------------------------------------------

func _setup(map_id: String, stage: Vector3) -> void:
	game = Game.instance
	zm = game.zombies
	_prefix = map_id
	_stage = stage
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	for zid in zm.zombies.keys():
		zm.despawn(zid)
	# Joueur hors champ, derrière la caméra.
	p.teleport_to(stage + Vector3(0, 0.05, 6.0), 0.0)
	game.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 80.0
	game.add_child(cam)
	cam.make_current()


func _look(from: Vector3, to: Vector3) -> void:
	cam.look_at_from_position(from, to)


func _show(variant: int, pos: Vector3, yaw: float, cls := 0) -> Zombie:
	# Marionnette pilotée par le scénario (hors ZombieManager : ni IA, ni
	# réseau, ni gerbe de terre d'apparition).
	var z := Zombie.new()
	z.setup(_next_id, variant, cls, false)
	_next_id += 1
	z.yaw = yaw
	zm.add_child(z)
	z.global_position = pos
	z.rotation.y = yaw
	_pose_state(z, Zombie.State.IDLE, 0.0)
	_shown.append(z)
	return z


func _pose_state(z: Zombie, s: Zombie.State, spd: float) -> void:
	z.state = s
	z._state_time = 0.0
	z.anim_speed = spd


func _clear() -> void:
	for z in _shown:
		if is_instance_valid(z):
			z.queue_free()
	_shown.clear()


func _shot(name: String) -> void:
	await at.screenshot("%s_%s" % [_prefix, name])


## Une rangée de zombies (variantes `vars`) alignés sur X, tournés de `yaw`.
func _row(vars: Array, yaw: float, spacing := 1.0, cls := 0) -> Array[Zombie]:
	var out: Array[Zombie] = []
	var n := vars.size()
	for i in n:
		var x := (float(i) - (n - 1) * 0.5) * spacing
		out.append(_show(vars[i], _stage + Vector3(x, 0, 0), yaw, cls))
	return out


func _set_yaw(zs: Array[Zombie], yaw: float) -> void:
	for z in zs:
		z.yaw = yaw
		z.rotation.y = yaw


# --------------------------------------------------------------------------
# Galerie : chaque archétype sous plusieurs angles
# --------------------------------------------------------------------------

func _gallery() -> void:
	var arch := []
	for a in ZombieModel.Arch.size():
		arch.append(ZombieModel.variant_of(a))
	var row := _row(arch, 0.0)
	await frames(3)
	_look(_stage + Vector3(0, 1.15, 4.6), _stage + Vector3(0, 0.95, 0))
	await seconds(0.4)
	# La tête est bien couverte par la hitbox de tête.
	for z in row:
		var hp := z.head_position()
		var hy := hp.y - _stage.y  # au-dessus du sol de la scène
		at.check(hy > 1.35 and hy < 1.85, "hitbox de tête à hauteur de tête (%.2f m)" % hy)
	await _shot("front")
	_set_yaw(row, PI * 0.5)
	await seconds(0.3)
	await _shot("profile")
	_set_yaw(row, PI)
	await seconds(0.3)
	await _shot("back")
	# Gros plans (visage, couvre-chef).
	_set_yaw(row, 0.0)
	await seconds(0.2)
	for i in [0, 2, 3, 4]:
		var z: Zombie = row[i]
		var h := z.head_position()
		_look(h + Vector3(0.3, 0.04, 0.62), h + Vector3(0, -0.04, 0))
		await seconds(0.25)
		await _shot("close_%s" % ZombieModel.ARCH_NAMES[i].replace(" ", "_").replace("é", "e"))
	# Buste, de trois quarts.
	var zc: Zombie = row[1]
	_look(zc.global_position + Vector3(1.0, 1.4, 1.5), zc.global_position + Vector3(0, 1.1, 0))
	await seconds(0.2)
	await _shot("bust")
	# À 10 m (lisibilité de la silhouette et des yeux).
	_set_yaw(row, atan2(_far_dir.x, _far_dir.z))
	_look(_stage + _far_dir * 10.0 + Vector3(0, 1.6, 0), _stage + Vector3(0, 1.0, 0))
	await seconds(0.3)
	await _shot("far_10m")
	_clear()
	# Deuxième série de variantes.
	var arch2 := []
	for a in ZombieModel.Arch.size():
		arch2.append(ZombieModel.variant_of(a, 1))
	_row(arch2, 0.0)
	_look(_stage + Vector3(0, 1.15, 4.6), _stage + Vector3(0, 0.95, 0))
	await seconds(0.4)
	await _shot("front_2")
	_clear()


# --------------------------------------------------------------------------
# Animations
# --------------------------------------------------------------------------

func _anim_row(cls: int, spd: float, yaw := PI * 0.5) -> Array[Zombie]:
	var vars := [ZombieModel.variant_of(0), ZombieModel.variant_of(1, 1), ZombieModel.variant_of(3), ZombieModel.variant_of(4)]
	var row := _row(vars, yaw, 1.3, cls)
	for z in row:
		z.anim_speed = spd
	return row


func _side_view() -> void:
	_look(_stage + Vector3(0, 1.1, 5.0), _stage + Vector3(0, 0.9, 0))


## Attentes fixes voulues : chaque capture montre une phase précise de
## l'animation (temps écoulé depuis le début de l'état ou de la pose).
func _animations() -> void:
	_side_view()
	var names := ["walk", "trot", "run", "sprint"]
	for cls in 4:
		var row := _anim_row(cls, Zombie.SPEEDS[cls])
		await seconds(1.2)
		await _shot(names[cls])
		await seconds(0.17)
		await _shot(names[cls] + "_b")
		if cls == 3:
			_set_yaw(row, 0.0)
			_look(_stage + Vector3(0, 1.3, 5.0), _stage + Vector3(0, 0.9, 0))
			await seconds(0.4)
			await _shot("sprint_front")
			_side_view()
		_clear()

	# Attaque à deux bras (armé, frappe).
	var row := _anim_row(0, 0.0, PI * 0.5)
	await seconds(0.4)
	for z in row:
		z.play_attack()
	await seconds(0.2)
	await _shot("attack_windup")
	await seconds(0.13)
	await _shot("attack_strike")
	_set_yaw(row, 0.0)
	_look(_stage + Vector3(0, 1.3, 3.2), _stage + Vector3(0, 1.1, 0))
	await seconds(0.5)
	for z in row:
		z.play_attack()
	await seconds(0.2)
	await _shot("attack_front")
	_clear()

	# Émergence : les mains d'abord.
	row = _anim_row(0, 0.0, 0.0)
	_look(_stage + Vector3(0, 1.0, 4.4), _stage + Vector3(0, 0.6, 0))
	for z in row:
		_pose_state(z, Zombie.State.EMERGE, 0.0)
	for tt in [0.25, 0.6, 1.05]:
		await seconds(tt - row[0]._state_time)
		await _shot("emerge_%d" % int(tt * 100))
	_clear()

	# Fenêtre : arrachage de planches puis enjambement.
	row = _anim_row(0, 0.0, PI * 0.5)
	_side_view()
	for z in row:
		_pose_state(z, Zombie.State.BARRIER, 0.0)
	for tt in [0.55, 1.3, 1.62]:
		await seconds(tt - row[0]._state_time)
		await _shot("tear_%d" % int(tt * 100))
	for z in row:
		_pose_state(z, Zombie.State.VAULT, 0.0)
	for tt in [0.3, 0.6]:
		await seconds(tt - row[0]._state_time)
		await _shot("vault_%d" % int(tt * 100))
	_clear()

	# Démembrement et reptation.
	row = _anim_row(0, 0.0, PI * 0.5)
	await frames(2)
	ZombieGibs.apply(row[0], ZombieGibs.ARM_L, Vector3.FORWARD, false)
	ZombieGibs.apply(row[1], ZombieGibs.ARM_R | ZombieGibs.ARM_L, Vector3.FORWARD, false)
	ZombieGibs.apply(row[2], ZombieGibs.LEGS, Vector3.FORWARD, false)
	ZombieGibs.apply(row[3], ZombieGibs.LEGS | ZombieGibs.ARM_R, Vector3.FORWARD, false)
	await seconds(0.5)
	await _shot("gibs")
	await seconds(0.8)
	row[2].anim_speed = 0.75
	row[3].anim_speed = 0.75
	await seconds(0.8)
	await _shot("crawl")
	_look(_stage + Vector3(0.6, 0.9, 3.0), _stage + Vector3(0.6, 0.3, 0))
	_set_yaw(row, 0.0)
	await seconds(0.4)
	await _shot("crawl_front")
	_clear()

	# Morts variées.
	row = _anim_row(0, 0.0, 0.0)
	_look(_stage + Vector3(2.5, 1.6, 5.0), _stage + Vector3(0, 0.4, 0))
	await seconds(0.3)
	var styles := [ZombieAnim.Death.TOPPLE, ZombieAnim.Death.CRUMPLE, ZombieAnim.Death.SPIN, ZombieAnim.Death.STIFF]
	for i in row.size():
		var z: Zombie = row[i]
		z.die(Vector3.BACK if i % 2 == 0 else Vector3.FORWARD, i == 3)
		z.anim.death_style = styles[i]
	await seconds(0.3)
	await _shot("death_early")
	await seconds(1.0)
	await _shot("death_down")
	for z in row:
		at.check(z.skel.global_position.y - _stage.y < 0.2 or absf(z.skel.rotation.x) > 1.0 or absf(z.skel.rotation.z) > 1.0,
			"corps au sol (%s)" % ZombieAnim.Death.keys()[z.anim.death_style])
	_clear()


# --------------------------------------------------------------------------
# Coût de rendu : nouveau modèle contre l'ancien (boîtes), en alternance
# (A/B/A/B dans la même partie : la charge des autres programmes s'annule).
# --------------------------------------------------------------------------

func _perf_ab() -> void:
	var zs: Array[Zombie] = []
	for i in 24:
		@warning_ignore("integer_division")
		var pos := _stage + Vector3((i % 6 - 2.5) * 0.9, 0, -float(i / 6) * 1.4 + 1.0)
		var z := _show(i * 7 + 1, pos, 0.0, i % 4)
		z.anim_speed = Zombie.SPEEDS[i % 4]
		zs.append(z)
	_look(_stage + Vector3(0, 1.6, 4.6), _stage + Vector3(0, 1.0, -1.0))
	var new_meshes := []
	var old_meshes := []
	var old_mat := ShaderMaterial.new()
	old_mat.shader = preload("res://assets/shaders/character.gdshader")
	old_mat.set_shader_parameter("emission_color", Color(1.0, 0.45, 0.12))
	old_mat.set_shader_parameter("emission_energy", 5.0)
	for z in zs:
		new_meshes.append(z.mesh.mesh)
		old_meshes.append(RigBuilder.build_mesh(_legacy_parts(z.variant)))
	await seconds(1.0)  # chauffe avant mesure
	# Coût CPU des poses (24 zombies, une image).
	var ta := Time.get_ticks_usec()
	for r in 50:
		for z in zs:
			z._update_pose(0.016)
	var pose_ms := (Time.get_ticks_usec() - ta) / 1000.0 / 50.0
	print("[perf] animation : %.3f ms/image pour 24 zombies" % pose_ms)
	at.check(pose_ms < 1.5, "poses de 24 zombies en %.2f ms/image" % pose_ms)
	var fps_new := 0.0
	var fps_old := 0.0
	for round_i in 4:
		var legacy := round_i % 2 == 1
		for k in zs.size():
			zs[k].mesh.mesh = old_meshes[k] if legacy else new_meshes[k]
			zs[k].mesh.material_override = old_mat if legacy else ZombieModel.material()
		await seconds(0.4)  # changement de modèle digéré avant mesure
		at.begin_perf()
		await seconds(2.5)  # fenêtre de mesure
		at.end_perf("24 zombies de près (%s)" % ("ancien modèle" if legacy else "nouveau modèle"))
		# Temps GPU (et non fps) : insensible à la charge CPU des autres jeux.
		var f: float = 1000.0 / maxf(at.last_gpu_ms, 0.01)
		if legacy:
			fps_old += f * 0.5
		else:
			fps_new += f * 0.5
		if round_i == 0:
			await _shot("perf_horde")
	var ratio := fps_new / maxf(fps_old, 1.0)
	print("[perf] nouveau modèle %.0f fps GPU contre ancien %.0f fps GPU (%.0f %%)" % [fps_new, fps_old, ratio * 100.0])
	if OS.get_environment("AUTOTEST_PARALLEL") == "1":
		print("[autotest] AVERTISSEMENT perf non vérifiée (exécution parallèle)")
	else:
		at.check(ratio > 0.85, "rendu de 24 zombies : au plus ~15 %% plus lent que l'ancien modèle (%.0f %%)" % (ratio * 100.0))
	_clear()


## Ancien zombie en boîtes (référence de coût, avant la refonte R4).
static func _legacy_parts(variant: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7919 + 17
	var skin := Color(0.36, 0.38, 0.3)
	var shirt := Color(0.2, 0.22, 0.15)
	var pants := Color(0.14, 0.15, 0.11)
	var wound := Color(0.32, 0.03, 0.03)
	var pts: Array = []
	pts.append(["hips", Vector3(0.34, 0.2, 0.2), Vector3(0, 0, 0), pants, 0.0])
	pts.append(["spine", Vector3(0.31, 0.26, 0.19), Vector3(0, 0.12, 0), shirt, 0.0])
	pts.append(["chest", Vector3(0.4, 0.28, 0.22), Vector3(0, 0.1, 0), shirt, 0.0])
	pts.append(["chest", Vector3(0.14, 0.12, 0.02), Vector3(rng.randf_range(-0.1, 0.1), 0.08, 0.112), wound, 0.0])
	pts.append(["spine", Vector3(0.1, 0.08, 0.02), Vector3(rng.randf_range(-0.1, 0.1), 0.1, 0.098), wound, 0.0])
	pts.append(["neck", Vector3(0.1, 0.12, 0.1), Vector3(0, 0.03, 0), skin, 0.0])
	pts.append(["head", Vector3(0.22, 0.25, 0.23), Vector3(0, 0.14, 0.0), skin, 0.0])
	pts.append(["head", Vector3(0.19, 0.06, 0.17), Vector3(0, 0.0, 0.04), skin.darkened(0.25), 0.0, Vector3(12, 0, 0)])
	pts.append(["head", Vector3(0.16, 0.025, 0.02), Vector3(0, 0.035, 0.121), Color(0.12, 0.05, 0.04), 0.0])
	pts.append(["head", Vector3(0.05, 0.028, 0.02), Vector3(0.052, 0.15, 0.116), Color(1.0, 0.55, 0.2), 1.0])
	pts.append(["head", Vector3(0.05, 0.028, 0.02), Vector3(-0.052, 0.15, 0.116), Color(1.0, 0.55, 0.2), 1.0])
	pts.append(["head", Vector3(0.24, 0.04, 0.05), Vector3(0, 0.185, 0.1), skin.darkened(0.35), 0.0])
	pts.append(["head", Vector3(0.235, 0.06, 0.24), Vector3(0, 0.27, -0.01), Color(0.08, 0.07, 0.06), 0.0])
	for side in ["l", "r"]:
		pts.append(["arm_" + side, Vector3(0.1, 0.3, 0.1), Vector3(0, -0.14, 0), shirt, 0.0])
		pts.append(["forearm_" + side, Vector3(0.085, 0.27, 0.085), Vector3(0, -0.13, 0), skin, 0.0])
		pts.append(["forearm_" + side, Vector3(0.075, 0.11, 0.045), Vector3(0, -0.31, 0.01), skin.darkened(0.1), 0.0])
		pts.append(["thigh_" + side, Vector3(0.14, 0.46, 0.15), Vector3(0, -0.22, 0), pants, 0.0])
		pts.append(["shin_" + side, Vector3(0.12, 0.44, 0.12), Vector3(0, -0.22, 0), pants.darkened(0.1), 0.0])
		pts.append(["shin_" + side, Vector3(0.12, 0.07, 0.23), Vector3(0, -0.45, 0.04), Color(0.06, 0.05, 0.04), 0.0])
	return pts
