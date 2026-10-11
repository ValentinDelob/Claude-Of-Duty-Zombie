class_name Nurse
extends Zombie
## L'Infirmière hurlante (mini-boss de vague spéciale, GAME_CONCEPT.md §4.4) :
## infirmière de nuit de l'hôpital, grande et décharnée, la gorge déchirée.
## « Type d'entité » du ZombieManager (KIND_NURSE), comme le Brancardier :
## même canal réseau, mêmes dégâts, ferraille et pièges que les zombies.
## Propres à elle : modèle (NurseModel), animation (NurseAnim), elle GARDE
## SES DISTANCES (fuit quand on s'approche, revient quand on s'éloigne), CRI
## télégraphié qui étourdit les joueurs en vue (Player.srv_daze) et AMEUTE
## les zombies proches (Zombie.rally_*), cri avorté par une touche à la gorge
## pendant la préparation (ÉTRANGLÉE), coup de seringue quand elle est
## acculée. Règles et chiffres : NurseRules.
##
## Réseau (hôte autoritaire) : le serveur décide de tout (fuite, cri, joueurs
## étourdis, zombies ameutés) ; la phase du cri voyage en message FIABLE
## (_cl_phase) et dans le code d'animation (bits 3-4) ; les zombies ameutés
## (_cl_rally, fiable) s'allument chez tous ; l'étourdissement est appliqué
## par la machine du joueur concerné (Player._cl_daze, fiable).

enum Phase { NONE, WINDUP, SCREAM, CHOKE }

## Capsule de déplacement (silhouette fine) et séparation.
const RADIUS_N := 0.24
const HEIGHT_N := 1.7
const SEPARATION_N := 0.8
## Mort : le corps reste puis se dissout cube par cube.
const N_DISSOLVE_DELAY := 2.2
const N_DISSOLVE_TIME := 1.2
## Lueur des yeux et de la gorge par phase (NONE, WINDUP, SCREAM, CHOKE).
const EYE_GLOW := [1.0, 4.0, 3.0, 0.25]
## Lueur des yeux d'un zombie ameuté (chez tous).
const RALLY_GLOW := 4.5

signal scream_started
signal screamed(dazed: Array, rallied: Array)
signal choked

## Toutes les machines : phase du cri et secondes depuis son début.
var scream_phase: int = Phase.NONE
var phase_time := 0.0
## Serveur : délai avant le prochain cri ; compteurs (tests).
var scream_cooldown := NurseRules.FIRST_SCREAM_DELAY
var screams := 0
var chokes := 0
var stabs := 0
var flee_starts := 0
var fleeing := false
var last_dazed: Array = []
var last_rallied: Array = []
## Serveur : fuite (point visé, recalcul), acculée (secondes restantes).
var _flee_goal := Vector3.INF
var _flee_t := 0.0
var _flee_slow := 0.0
var cornered := 0.0
var _retarget_t := 0.0
var _life_t := 0.0
var _hit_t := -1.0
var _gait := 0.0
var _last_step := 0
var _inhale_fx := 0.0
## Client : phases reçues (_cl_phase), à jouer dans l'ordre.
var _net_phases: Array[int] = []
## Toutes les machines : zombies ameutés qui luisent (zid -> secondes).
var _glow := {}
## Zone de touche de la gorge (comptée « tête »).
var hit_throat: Area3D


func _ready() -> void:
	_mgr = get_parent() as ZombieManager
	game = _mgr.game if _mgr else null
	_multilevel = map_is_multilevel()
	speed_class = 0
	speed_mult = 1.0
	sep_range = SEPARATION_N
	collision_layer = 0
	collision_mask = 1 | (1 << 1) | (1 << 2)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS_N
	cap.height = HEIGHT_N
	cs.shape = cap
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	max_slides = 3
	wall_min_slide_angle = 0.0
	cs.position.y = HEIGHT_N * 0.5 + floor_gap()
	_body_shape = cs
	add_child(cs)
	_update_solidity()

	skel = NurseModel.build(variant)
	add_child(skel)
	mesh = skel.get_node("Mesh")
	bones = RigBuilder.bone_indices(skel)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	_gait = rng.randf() * TAU

	# Zones de touche (NurseModel.hit_shapes) : tronc, tête sur l'os head et
	# GORGE sur l'os neck (comptées « tête » : point faible), bras.
	var shapes := NurseModel.hit_shapes()
	var body: Array = shapes.body
	var body_cap := CapsuleShape3D.new()
	body_cap.radius = body[1]
	body_cap.height = body[2]
	hit_body = _make_hitbox(0, body_cap)
	hit_body.position = body[0]
	add_child(hit_body)
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var sph := SphereShape3D.new()
	sph.radius = shapes.head[1]
	hit_head = _make_hitbox(1, sph)
	hit_head.position = shapes.head[0]
	att.add_child(hit_head)
	var natt := BoneAttachment3D.new()
	natt.bone_name = "neck"
	skel.add_child(natt)
	var tsph := SphereShape3D.new()
	tsph.radius = shapes.throat[1]
	hit_throat = _make_hitbox(1, tsph)
	hit_throat.name = "HitThroat"
	hit_throat.position = shapes.throat[0]
	natt.add_child(hit_throat)
	for side in ["l", "r"]:
		for part in ["arm", "forearm"]:
			var arm_att := BoneAttachment3D.new()
			arm_att.bone_name = part + "_" + side
			skel.add_child(arm_att)
			var acap := CapsuleShape3D.new()
			acap.radius = 0.07
			acap.height = 0.34
			var ha := _make_hitbox(2, acap)
			ha.name = ("HitArm_" if part == "forearm" else "HitUpperArm_") + side
			ha.position = Vector3(0.0, -0.16, 0.0)
			arm_att.add_child(ha)
			if part == "forearm":
				hit_arms.append(ha)
			else:
				hit_upper_arms.append(ha)
	if not server_side:
		set_physics_process(false)
	_update_pose(0.0)


## Gorge (point faible, hitbox « tête » sur l'os neck).
func throat_position() -> Vector3:
	return hit_throat.global_position


func hit_center_height() -> float:
	return 1.0


func move_speed() -> float:
	return NurseRules.FLEE_SPEED if fleeing else NurseRules.WALK_SPEED


func is_crawler() -> bool:
	return false


func _fit_radius(slim: bool) -> float:
	return RADIUS_N + SLIM_MARGIN if slim else RADIUS_N + 0.06


func _leg_radius() -> float:
	return RADIUS_N


## Code d'animation : état (3 bits) | phase du cri (2 bits).
func anim_code() -> int:
	return int(state) | (scream_phase << 3)


## Serveur -> clients : changement de phase du cri (FIABLE : la préparation,
## le cri et leurs sons ne doivent jamais manquer).
@rpc("authority", "call_remote", "reliable")
func _cl_phase(p: int) -> void:
	if server_side or p < Phase.NONE or p > Phase.CHOKE:
		return
	_net_phases.append(p)


## Serveur -> tous : zombies ameutés par le cri (leurs yeux flamboient
## pendant NurseRules.RALLY_TIME).
@rpc("authority", "call_local", "reliable")
func _cl_rally(zids: PackedInt32Array) -> void:
	if zids.size() > 512:
		return
	for zid in zids:
		_glow[zid] = NurseRules.RALLY_TIME


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if state == State.CHASE and scream_phase != Phase.NONE:
		_state_time += delta
		phase_time += delta
		_scream_step(delta)
		return
	if state == State.CHASE:
		scream_cooldown -= delta
		if _try_scream():
			return
	super(delta)


## Le cri peut-il partir vers la proie ? Alors : préparation (WINDUP).
func _try_scream() -> bool:
	if game == null or game.nav == null or scream_cooldown > 0.0:
		return false
	if target == null or not is_instance_valid(target) or not _is_target_valid(target):
		return false
	var to := target.global_position - global_position
	var dy := absf(to.y)
	to.y = 0.0
	var d := to.length()
	if not NurseRules.can_scream(d, dy, true, scream_cooldown):
		return false
	if not game.nav.world_line_clear(global_position, target.global_position):
		scream_cooldown = 0.4
		return false
	fleeing = false
	_set_phase(Phase.WINDUP)
	scream_started.emit()
	return true


func _scream_step(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)
	match scream_phase:
		Phase.WINDUP:
			# Elle suit sa proie des yeux pendant la préparation.
			if target and is_instance_valid(target):
				var to := target.global_position - global_position
				if Vector2(to.x, to.z).length() > 0.1:
					yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 8.0))
					rotation.y = yaw
			if phase_time >= NurseRules.WINDUP_TIME:
				_set_phase(Phase.SCREAM)
				_do_scream()
		Phase.SCREAM:
			if phase_time >= NurseRules.SCREAM_TIME:
				scream_cooldown = NurseRules.SCREAM_COOLDOWN
				_end_phase()
		Phase.CHOKE:
			if phase_time >= NurseRules.CHOKE_TIME:
				scream_cooldown = NurseRules.SCREAM_COOLDOWN * 0.5
				_end_phase()
	velocity.y = 0.0
	move_and_slide()
	if _multilevel:
		_follow_floor()
	elif global_position.y != 0.0:
		global_position.y = 0.0
	anim_speed = Vector2(velocity.x, velocity.z).length()


## Le cri : joueurs en vue dans DAZE_RADIUS étourdis (et un peu blessés),
## zombies dans RALLY_RADIUS ameutés vers sa proie.
func _do_scream() -> void:
	screams += 1
	var dazed := []
	var origin := head_position()
	for p: Player in game.players.values():
		if not _is_target_valid(p):
			continue
		var d := p.global_position.distance_to(global_position)
		var dt := NurseRules.daze_time(d)
		if dt <= 0.0 or not game.nav.world_line_clear(global_position, p.global_position):
			continue
		dazed.append(p.peer_id)
		game.combat.damage_player(p.peer_id, NurseRules.SCREAM_DAMAGE, origin, self)
		p.srv_daze(dt, NurseRules.daze_strength(d))
	var victim: Player = target if target and is_instance_valid(target) and _is_target_valid(target) else _nearest_player()
	var rallied := PackedInt32Array()
	for z: Zombie in game.zombies.alive:
		if z == self or z is Nurse or z is Hellhound or z is Brancardier or not z.is_alive():
			continue
		if not NurseRules.rallies(z.global_position.distance_to(global_position)):
			continue
		z.rally_left = NurseRules.RALLY_TIME
		z.rally_mult = NurseRules.RALLY_SPEED
		z.rally_target = victim
		rallied.append(z.id)
	last_dazed = dazed
	last_rallied = Array(rallied)
	print("[Infirmière] %d : cri, %d joueur(s) étourdi(s), %d zombie(s) ameuté(s)" % [id, dazed.size(), rallied.size()])
	if Net.is_online() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_cl_rally.rpc(rallied)
	else:
		_cl_rally(rallied)
	screamed.emit(dazed, last_rallied)


## Serveur : touche reçue (NurseRound, Combat.zombie_damaged). Une touche à
## la tête ou à la gorge pendant la préparation étrangle le cri.
func srv_on_damaged(headshot: bool) -> void:
	if state == State.DEAD or not headshot or scream_phase != Phase.WINDUP:
		return
	chokes += 1
	_set_phase(Phase.CHOKE)
	choked.emit()


func _end_phase() -> void:
	_repath_t = 0.0
	_set_phase(Phase.NONE)


func _set_phase(p: int) -> void:
	scream_phase = p
	phase_time = 0.0
	_on_phase(p)
	if Net.is_online() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_cl_phase.rpc(p)


## Poursuite à distance : fuit de près, approche de loin, reste face à sa
## proie entre les deux ; coup de seringue au contact.
func _chase(delta: float) -> void:
	if game == null or game.nav == null:
		return
	_retarget_t -= delta
	cornered = maxf(cornered - delta, 0.0)
	if _retarget_t <= 0.0 or target == null or not is_instance_valid(target) or not _is_target_valid(target):
		target = _nearest_player()
		_retarget_t = 0.5
	if target == null:
		fleeing = false
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		return
	var tpos := target.global_position
	var to := tpos - global_position
	var dy := absf(to.y)
	to.y = 0.0
	var dist := to.length()
	if dist < NurseRules.STAB_RANGE and dy < LEVEL_TOLERANCE:
		fleeing = false
		_start_attack()
		return
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = LOS_PERIOD * 2.0
		_los_ok = dist < NurseRules.KEEP_MAX + 2.0 and game.nav.world_line_clear(global_position, tpos)
	var mode := NurseRules.move_mode(dist, _los_ok)
	if mode == "flee" and cornered <= 0.0:
		_flee(delta)
		return
	if fleeing:
		fleeing = false
		_flee_goal = Vector3.INF
	if mode == "hold":
		# Face à sa proie, petit balancement de côté (elle guette).
		var side := Vector3(to.z, 0.0, -to.x).normalized() * sin(_life_t * 0.9) * 0.35
		var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(side, 6.0 * delta)
		velocity.x = horiz.x
		velocity.z = horiz.z
		if dist > 0.1:
			yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 6.0))
		rotation.y = yaw
		return
	# Approche (ou acculée : elle vient se défendre).
	super(delta)


## Fuite vers un point dégagé loin des joueurs (NurseRules.flee_score).
func _flee(delta: float) -> void:
	if not fleeing:
		fleeing = true
		flee_starts += 1
		_flee_goal = Vector3.INF
		_flee_slow = 0.0
	_flee_t -= delta
	if _flee_goal == Vector3.INF or _flee_t <= 0.0 or _flat_dist(_flee_goal) < 0.8:
		_flee_goal = _pick_flee_goal()
		_flee_t = 1.0
		if _flee_goal == Vector3.INF:
			_corner()
			return
		_set_path(game.nav.find_path(global_position, _flee_goal, lane_bias()))
		if _path.is_empty():
			_corner()
			return
	var dir := _follow_path()
	if dir == Vector3.ZERO:
		_flee_goal = Vector3.INF
		return
	var desired := (dir + _wall_safe(_separation()) * 0.5).normalized() * move_speed() * speed_mult * _lane_speed
	var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, 14.0 * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if horiz.length() > 0.1:
		yaw = lerp_angle(yaw, atan2(horiz.x, horiz.z), 1.0 - exp(-delta * 10.0))
	rotation.y = yaw
	# Bloquée (coin, horde) : acculée, elle se défend.
	_flee_slow = _flee_slow + delta if anim_speed < 0.5 else 0.0
	if _flee_slow > 1.2:
		_corner()


func _corner() -> void:
	fleeing = false
	_flee_goal = Vector3.INF
	_flee_slow = 0.0
	cornered = NurseRules.CORNERED_TIME


## Meilleur point de fuite parmi les points de sol dégagé de la carte
## (au plus 48 essayés), ou Vector3.INF.
func _pick_flee_goal() -> Vector3:
	if game.layout == null:
		return Vector3.INF
	var pts: Array = game.layout.open_floor_points()
	if pts.is_empty():
		return Vector3.INF
	var threats := []
	for p: Player in game.players.values():
		if _is_target_valid(p):
			threats.append(p.global_position)
	var best := Vector3.INF
	var best_s := -INF
	var n := mini(pts.size(), 48)
	var start := randi() % pts.size()
	for i in n:
		var p: Vector3 = pts[(start + i * 7919) % pts.size()]
		p.y = global_position.y if not _multilevel else p.y
		var sc := NurseRules.flee_score(global_position, p, threats)
		if sc > best_s and game.layout.is_walkable_at(p):
			best_s = sc
			best = p
	return best


## Coup de seringue (acculée, au contact).
func _start_attack() -> void:
	_set_state(State.ATTACK)
	_attack_hit_done = false
	velocity.x = 0.0
	velocity.z = 0.0
	play_attack()


func _attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	if target and is_instance_valid(target) and _state_time < NurseRules.STAB_HIT_TIME:
		var to := target.global_position - global_position
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 8.0))
		rotation.y = yaw
	if not _attack_hit_done and _state_time >= NurseRules.STAB_HIT_TIME:
		_attack_hit_done = true
		if target and is_instance_valid(target) and _is_target_valid(target):
			var d := target.global_position - global_position
			var dy := absf(d.y)
			d.y = 0.0
			if d.length() < NurseRules.STAB_REACH and dy < LEVEL_TOLERANCE:
				stabs += 1
				game.combat.damage_player(target.peer_id, NurseRules.STAB_DAMAGE, global_position + Vector3.UP * 1.2, self)
	if _state_time >= NurseRules.STAB_TIME:
		_set_state(State.CHASE)
		# Après le coup, elle tente de nouveau de s'enfuir.
		cornered = 0.0


func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < 1.2:
		return
	if global_position.distance_to(_stuck_pos) < 0.3:
		_repath_t = 0.0
	_stuck_pos = global_position
	_stuck_t = 0.0


# --------------------------------------------------------------------------
# Toutes les machines
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _life_t == 0.0:
		Audio.play_3d("nurse_moan_1", global_position + Vector3.UP * 1.6, 0.0, 0.08, 3)
	_life_t += maxf(delta, 0.0001)
	_tick_glow(delta)
	if state == State.DEAD:
		_process_death(delta)
		return
	if not server_side:
		_interpolate()
		_state_time += delta
		phase_time += delta
		if not _net_phases.is_empty():
			scream_phase = _net_phases.pop_front()
			phase_time = 0.0
			_on_phase(scream_phase)
	if _hit_t >= 0.0:
		_hit_t += delta
		if _hit_t > NurseAnim.HIT_TIME:
			_hit_t = -1.0
	_groan(delta)
	_phase_fx(delta)
	_pose_accum += delta
	var step := _mgr.pose_step(global_position) if _mgr else 0.0
	if _pose_accum >= step:
		_update_pose(_pose_accum)
		_pose_accum = 0.0
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		mesh.set_instance_shader_parameter("hit_flash", _flash)


## Yeux des zombies ameutés : flamboient, puis reviennent à la normale.
func _tick_glow(delta: float) -> void:
	if _glow.is_empty() or _mgr == null:
		return
	for zid in _glow.keys():
		var left: float = _glow[zid] - delta
		var z := _mgr.get_zombie(zid)
		if z == null or not z.is_alive() or z.mesh == null:
			_glow.erase(zid)
			continue
		if left <= 0.0:
			z.mesh.set_instance_shader_parameter("eye_glow", 1.0)
			_glow.erase(zid)
		else:
			_glow[zid] = left
			z.mesh.set_instance_shader_parameter("eye_glow", RALLY_GLOW if fmod(left, 0.5) > 0.12 else 2.0)


func _exit_tree() -> void:
	# Retirée avant la fin de la lueur : les zombies retrouvent leurs yeux.
	if _mgr == null:
		return
	for zid in _glow:
		var z := _mgr.get_zombie(zid)
		if z and z.mesh and is_instance_valid(z.mesh):
			z.mesh.set_instance_shader_parameter("eye_glow", 1.0)
	_glow.clear()


## Touchée (toutes les machines) : flash et recul bref.
func flash_hit() -> void:
	_flash = 1.0
	_hit_t = 0.0
	if randf() < 0.5:
		Audio.play_3d("nurse_hit", global_position + Vector3.UP * 1.6, -3.0, 0.1, 2)


## Début d'une phase du cri : sons et effets (toutes les machines).
func _on_phase(p: int) -> void:
	if p != Phase.NONE:
		print("[Infirmière] %d : %s (%s)" % [id, ["poursuite", "préparation", "cri", "étranglée"][p], "serveur" if server_side else "client"])
	if mesh and state != State.DEAD:
		mesh.set_instance_shader_parameter("eye_glow", EYE_GLOW[clampi(p, 0, EYE_GLOW.size() - 1)])
	var head := global_position + Vector3.UP * 1.6
	match p:
		Phase.WINDUP:
			Audio.play_3d("nurse_inhale", head, 2.0, 0.03, 3)
			_inhale_fx = 0.0
		Phase.SCREAM:
			Audio.play_3d("nurse_scream", head, 4.0, 0.03, 3)
			var fx := NurseScreamFx.new()
			var parent: Node = game.fx_root if game and game.fx_root else get_parent()
			parent.add_child(fx)
			fx.start(global_position, NurseRules.DAZE_RADIUS)
			# Secousse de la vue du joueur local proche (même non étourdi).
			if game and game.local_player:
				var dist := game.local_player.global_position.distance_to(global_position)
				if dist < NurseRules.RALLY_RADIUS:
					var amp := 0.05 * (1.0 - dist / NurseRules.RALLY_RADIUS)
					game.local_player.add_flinch(Vector2(randf_range(-amp, amp), amp))
		Phase.CHOKE:
			Audio.play_3d("nurse_choke", head, 2.0, 0.05, 3)
			var fx: Fx = game.fx_root if game else null
			if fx:
				fx.blood_hit(head - Vector3.UP * 0.15 + Vector3(sin(yaw), 0.0, cos(yaw)) * 0.15, Vector3(sin(yaw), 0.3, cos(yaw)), 1.2)


## Effets continus : souffle aspiré vers la bouche pendant la préparation
## (petits cubes roses qui convergent), crachats de sang étranglée.
func _phase_fx(delta: float) -> void:
	var fx: Fx = game.fx_root if game else null
	if fx == null or state == State.DEAD:
		return
	if scream_phase == Phase.WINDUP:
		_inhale_fx -= delta
		if _inhale_fx <= 0.0:
			_inhale_fx = 0.08
			var mouth := global_position + Vector3.UP * 1.58 + Vector3(sin(yaw), 0.0, cos(yaw)) * 0.12
			var a := randf() * TAU
			var e := randf_range(-0.6, 0.9)
			var from := mouth + Vector3(cos(a) * cos(e), sin(e), sin(a) * cos(e)) * 1.1
			fx.sparks.burst(from, (mouth - from).normalized(), 3, 2.6, 0.15, 0.4, Color(1.0, 0.55, 0.65), 0.8)


func play_attack() -> void:
	_attack_t = 0.0
	Audio.play_3d("nurse_hit", global_position + Vector3.UP * 1.6, 0.0, 0.1, 3)
	get_tree().create_timer(NurseRules.STAB_HIT_TIME).timeout.connect(func():
		if is_instance_valid(self) and state != State.DEAD:
			Audio.play_3d("nurse_stab", global_position + Vector3(sin(yaw), 1.1, cos(yaw)), 0.0, 0.1, 3))


## Mort : mains à la gorge, cri qui s'étouffe, chute sur le dos.
func die(_dir: Vector3, _headshot: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_state_time = 0.0
	_death_t = 0.0
	scream_phase = Phase.NONE
	fleeing = false
	collision_layer = 0
	collision_mask = 1
	for c in skel.get_children():
		for a in c.get_children():
			if a is Area3D:
				(a as Area3D).collision_layer = 0
				a.get_child(0).set_deferred("disabled", true)
	hit_body.collision_layer = 0
	hit_body.get_child(0).set_deferred("disabled", true)
	if _body_shape:
		_body_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	set_physics_process(false)
	clear_snapshots()
	if mesh:
		mesh.set_instance_shader_parameter("eye_glow", 1.0)
	Audio.play_3d("nurse_death", global_position + Vector3.UP * 1.6, 2.0, 0.05, 3)
	var fx: Fx = game.fx_root if game else null
	if fx:
		fx.blood_hit(global_position + Vector3.UP * 1.45, Vector3.UP, 3.0)


func _process_death(delta: float) -> void:
	var before := _death_t
	_death_t += delta
	if before <= NurseAnim.DEATH_CLUTCH + NurseAnim.DEATH_SETTLE:
		NurseAnim.apply(skel, bones, NurseAnim.pose(_gait, 0.0, _life_t, 0, 0.0, -1.0, _death_t))
	var land := NurseAnim.DEATH_CLUTCH + NurseAnim.DEATH_FALL * 0.85
	if before < land and _death_t >= land:
		var at := global_position - Vector3(sin(yaw), 0.0, cos(yaw)) * 1.0
		Audio.play_3d("body_fall", at, 0.0, 0.1, 3)
		var fx: Fx = game.fx_root if game else null
		if fx:
			fx.dust.burst(at + Vector3.UP * 0.1, Vector3.UP, 10, 1.6, 1.2, 0.9, Color(0.3, 0.28, 0.25, 0.5), 1.6)
			fx.blood_decal(at + Vector3.UP * 0.1, Vector3.UP, 1.3)
	if _death_t > N_DISSOLVE_DELAY:
		var k := clampf((_death_t - N_DISSOLVE_DELAY) / N_DISSOLVE_TIME, 0.0, 1.0)
		NurseModel.set_dissolve(mesh, k)
		if before <= N_DISSOLVE_DELAY:
			mesh.set_instance_shader_parameter("eye_glow", 0.0)
		if k >= 1.0:
			skel.visible = false


func _groan(delta: float) -> void:
	_groan_t -= delta
	if _groan_t > 0.0:
		return
	_groan_t = randf_range(3.0, 6.0)
	if scream_phase == Phase.NONE and state != State.EMERGE:
		Audio.play_3d("nurse_moan_%d" % (1 + randi() % 2), global_position + Vector3.UP * 1.6, -4.0, 0.08, 3)


func _update_pose(delta: float) -> void:
	if skel == null:
		return
	var spd := anim_speed
	var move := spd / NurseRules.WALK_SPEED
	_gait += delta * (2.6 + spd * 2.1)
	var step := int(floor(_gait / PI))
	if step != _last_step:
		_last_step = step
		if spd > 0.3 and state != State.EMERGE:
			var ear: Variant = Audio.listener_position()
			if ear != null and global_position.distance_to(ear) < 20.0:
				Audio.play_3d("nurse_step_%d" % (1 + step % 2), global_position, -6.0, 0.08, 6)
	if _attack_t >= 0.0:
		_attack_t += delta / NurseRules.STAB_TIME
		if _attack_t > 1.0:
			_attack_t = -1.0
	var p := NurseAnim.pose(_gait, move, _life_t, scream_phase, phase_time, _attack_t, -1.0, _hit_t)
	NurseAnim.apply(skel, bones, p)
