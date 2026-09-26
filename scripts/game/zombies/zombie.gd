class_name Zombie
extends CharacterBody3D
## Zombie. Le SERVEUR simule (IA, déplacement, santé) ; les clients n'ont qu'une
## marionnette interpolée à partir des instantanés du ZombieManager, avec des
## hitboxes pour que le tireur puisse viser localement.

## BARRIER : marche vers sa fenêtre et en arrache les planches ; VAULT : l'enjambe.
enum State { EMERGE, IDLE, CHASE, ATTACK, DEAD, BARRIER, VAULT }

## Vitesses par classe (m/s) : marcheur, trotteur, coureur, sprinteur.
const SPEEDS := [1.25, 2.3, 3.7, 5.0]
## Écart entre la capsule de collision et le sol (déplacement flottant).
const FLOOR_GAP := 0.04
## Animation hors champ ou lointaine : cadence réduite (secondes entre deux poses).
const POSE_STEP_OFFSCREEN := 1.0 / 20.0
const POSE_STEP_FAR := 1.0 / 60.0
const POSE_STEP_VERY_FAR := 1.0 / 30.0
## Les membres d'un corps ont fini de retomber après ce délai.
const DEATH_SETTLE_TIME := 1.5
const DEATH_ARMS := ["arm_l", "arm_r"]
const DEATH_LIMBS := ["thigh_l", "thigh_r", "shin_l", "shin_r", "spine", "chest"]
const RADIUS := 0.3
const HEIGHT := 1.75
const EMERGE_TIME := 1.4
## Couche physique « zombies ».
const BODY_LAYER := 1 << 2
const INTERP_DELAY := 0.12
const HITBOX_LAYER := 1 << 3
const ATTACK_RANGE := 1.25
const ATTACK_TIME := 0.9
## En dessous de cette distance, poursuite directe si la ligne de vue est dégagée.
const DIRECT_RANGE := 12.0
const ATTACK_HIT_TIME := 0.42
const DISSOLVE_DELAY := 2.4
const DISSOLVE_TIME := 1.4

var id := 0
var variant := 0
var speed_class := 0
var server_side := false
var state: State = State.EMERGE
var yaw := 0.0
var health := 150
var max_health := 150
var speed_mult := 1.0
var target: Player
## Serveur : attiré par un SINGE-TAMBOUR (ThrowableSystem.lure_for).
var lured := false
## Fenêtre à franchir avant d'entrer dans la zone (null : déjà dedans).
var barricade: Barricade
## Serveur : progression de l'arrachage de la planche en cours.
var tear_t := 0.0
var _vault_from := Vector3.ZERO
var _vault_to := Vector3.ZERO
## Membres arrachés (masque ZombieGibs) ; temps écoulé depuis la chute du
## RAMPANT (< 0 : debout). Toutes les machines (ZombieManager._cl_gib).
var gibs := 0
var crawl_t := -1.0

var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _attack_hit_done := false
var _groan_t := randf_range(ZombieVoice.FIRST_DELAY.x, ZombieVoice.FIRST_DELAY.y)
var _last_vocal := 0
var _step_i := 0
var _headless := false
var _low_move_t := 0.0
var _stuck_sample_t := 0.0
var _stuck_sample_pos := Vector3.ZERO

## Animation (lue sur toutes les machines).
var anim_speed := 0.0      # vitesse horizontale actuelle (m/s)
var _phase := 0.0
var _state_time := 0.0
var _attack_t := -1.0
var _death_t := -1.0
var _death_dir := 1.0
var _flash := 0.0
var _head_tilt := 0.0
var _snapshots: Array = []
var _last_vel := Vector3.ZERO

var skel: Skeleton3D
var mesh: MeshInstance3D
var bones: Dictionary
var hit_body: Area3D
var hit_head: Area3D
var _body_shape: CollisionShape3D
var _mgr: ZombieManager
## Temps écoulé depuis la dernière pose écrite (animation à cadence réduite).
var _pose_accum := 0.0


func setup(zid: int, zvariant: int, zspeed: int, is_server: bool) -> void:
	id = zid
	variant = zvariant
	speed_class = zspeed
	server_side = is_server
	name = "Z%d" % zid


func _ready() -> void:
	_mgr = get_parent() as ZombieManager
	_update_solidity()
	collision_mask = 1 | (1 << 1) | (1 << 2) | Barricade.BARRIER_LAYER  # monde, joueurs, zombies, fenêtres
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	# Cartes plates : déplacement « flottant » à y = 0, capsule légèrement
	# décollée du sol. move_and_slide ne gère alors ni contact ni accroche au
	# sol (une bonne part de son coût) pour la même trajectoire.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	cs.position.y = HEIGHT * 0.5 + FLOOR_GAP
	_body_shape = cs
	add_child(cs)

	skel = ZombieModel.build(variant)
	add_child(skel)
	mesh = skel.get_node("Mesh")
	bones = RigBuilder.bone_indices(skel)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	_head_tilt = rng.randf_range(-0.35, 0.35)
	_phase = rng.randf() * TAU

	hit_body = _make_hitbox(0, CapsuleShape3D.new())
	(hit_body.get_child(0).shape as CapsuleShape3D).radius = 0.28
	(hit_body.get_child(0).shape as CapsuleShape3D).height = 1.35
	hit_body.position.y = 0.8
	add_child(hit_body)
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var sph := SphereShape3D.new()
	sph.radius = 0.16
	hit_head = _make_hitbox(1, sph)
	hit_head.position = Vector3(0, 0.13, 0.01)
	att.add_child(hit_head)

	if not server_side:
		# Marionnette : pas de simulation physique locale.
		set_physics_process(false)
	_update_pose(0.0)


func _make_hitbox(zone: int, shape: Shape3D) -> Area3D:
	var a := Area3D.new()
	a.name = "HitHead" if zone == 1 else "HitBody"
	a.collision_layer = HITBOX_LAYER
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = false
	a.set_meta("zombie_id", id)
	a.set_meta("zone", zone)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	return a


func is_alive() -> bool:
	return state != State.DEAD


## Code d'animation envoyé dans les instantanés : état (3 bits) | vitesse (2 bits).
func anim_code() -> int:
	return int(state) | (speed_class << 3)


# --------------------------------------------------------------------------
# Serveur : simulation
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.EMERGE:
			if _state_time >= EMERGE_TIME:
				_set_state(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.ATTACK:
			_attack(delta)
		State.BARRIER:
			if is_instance_valid(barricade):
				barricade.srv_zombie_barrier(self, delta)
			else:
				barricade = null
				_set_state(State.CHASE)
		State.VAULT:
			_vault()
		State.DEAD:
			return
	# Déplacement au sol (y = 0) : les cartes sont plates.
	velocity.y = 0.0
	if state != State.EMERGE and state != State.VAULT:
		move_and_slide()
		if global_position.y != 0.0:
			global_position.y = 0.0
	anim_speed = Vector2(velocity.x, velocity.z).length()
	# Mesure de blocage sur des fenêtres d'une seconde (déplacement réel).
	_stuck_sample_t += delta
	if _stuck_sample_t >= 1.0:
		if state == State.CHASE and not lured and global_position.distance_to(_stuck_sample_pos) < 0.6:
			_low_move_t += _stuck_sample_t
		else:
			_low_move_t = 0.0
		_stuck_sample_t = 0.0
		_stuck_sample_pos = global_position


## Poursuite : ligne droite si le joueur est visible et proche, sinon chemin
## A* recalculé régulièrement. Séparation entre zombies pour éviter les amas.
func _chase(delta: float) -> void:
	var game := Game.instance
	if game == null or game.nav == null:
		return
	_repath_t -= delta
	# SINGE-TAMBOUR : un leurre actif passe avant tous les joueurs.
	var lure: Vector3 = game.throwables.lure_for(self) if game.throwables else Vector3.INF
	lured = lure != Vector3.INF
	if lured:
		_chase_lure(lure, delta)
		return
	if _repath_t <= 0.0 or target == null or not is_instance_valid(target) or not _is_target_valid(target):
		target = _nearest_player()
	var desired := Vector3.ZERO
	if target:
		var tpos := target.global_position
		var to := tpos - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < ATTACK_RANGE:
			_start_attack()
			return
		var dir := Vector3.ZERO
		if dist < DIRECT_RANGE and game.nav.world_line_clear(global_position, tpos):
			dir = to / dist
			_path.clear()
		else:
			if _repath_t <= 0.0 or _path_i >= _path.size():
				_path = game.nav.find_path(global_position, tpos)
				_path_i = 0
				_repath_t = randf_range(0.35, 0.7)
			while _path_i < _path.size() and _flat_dist(_path[_path_i]) < 0.45:
				_path_i += 1
			if _path_i < _path.size():
				var wp := _path[_path_i] - global_position
				wp.y = 0.0
				dir = wp.normalized()
		if _repath_t <= 0.0:
			_repath_t = randf_range(0.35, 0.7)
		desired = (dir + _separation() * 0.9).normalized() * move_speed() * speed_mult
		_check_stuck(delta)
	var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, 12.0 * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if horiz.length() > 0.1:
		# Le modèle regarde vers +Z.
		yaw = lerp_angle(yaw, atan2(horiz.x, horiz.z), 1.0 - exp(-delta * 8.0))
	rotation.y = yaw


## Serveur : marche vers le SINGE-TAMBOUR (chemin A*) puis l'encercle.
func _chase_lure(pos: Vector3, delta: float) -> void:
	var game := Game.instance
	var to := pos - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := Vector3.ZERO
	if dist > ThrowableRules.LURE_STOP:
		if dist < DIRECT_RANGE and game.nav.world_line_clear(global_position, pos):
			dir = to / dist
			_path.clear()
		else:
			if _repath_t <= 0.0 or _path_i >= _path.size():
				_path = game.nav.find_path(global_position, pos)
				_path_i = 0
				_repath_t = randf_range(0.35, 0.7)
			while _path_i < _path.size() and _flat_dist(_path[_path_i]) < 0.45:
				_path_i += 1
			if _path_i < _path.size():
				var wp := _path[_path_i] - global_position
				wp.y = 0.0
				dir = wp.normalized()
	if _repath_t <= 0.0:
		_repath_t = randf_range(0.35, 0.7)
	var desired: Vector3 = (dir + _separation() * 0.9).limit_length(1.0) * move_speed() * speed_mult
	var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, 12.0 * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	# Tourné vers le singe.
	if dist > 0.05:
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 8.0))
	rotation.y = yaw


## Vitesse de poursuite (m/s) : classe de vitesse, ou reptation d'un RAMPANT.
func move_speed() -> float:
	if crawl_t >= 0.0:
		return ZombieGibs.crawl_speed(crawl_t)
	return SPEEDS[speed_class]


func is_crawler() -> bool:
	return crawl_t >= 0.0


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


## Répulsion douce des zombies voisins (rayon √0,8 ≈ 0,9 m). Seules les 9
## cases de la grille spatiale du ZombieManager autour du zombie sont lues,
## au lieu de tous les zombies vivants.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	var mgr := get_parent() as ZombieManager
	if mgr == null:
		return push
	var grid := mgr.separation_grid()
	var pos := global_position
	var cx := floori(pos.x / ZombieManager.GRID_CELL)
	var cz := floori(pos.z / ZombieManager.GRID_CELL)
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			var bucket: Array = grid.get(ZombieManager.grid_key(gx, gz), ZombieManager.EMPTY)
			for other: Zombie in bucket:
				if other == self:
					continue
				var d := pos - other.global_position
				d.y = 0.0
				var l2 := d.length_squared()
				if l2 < 0.8 and l2 > 0.0001:
					push += d / l2 * 0.25
	return push.limit_length(1.0)


## Coincé (contre un autre zombie, un angle...) : recalcul immédiat du chemin.
func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < 1.2:
		return
	if global_position.distance_to(_stuck_pos) < 0.3:
		_repath_t = 0.0
		velocity += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 2.0
	_stuck_pos = global_position
	_stuck_t = 0.0


func _start_attack() -> void:
	_set_state(State.ATTACK)
	_attack_hit_done = false
	velocity.x = 0.0
	velocity.z = 0.0
	play_attack()


func _attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	if target and is_instance_valid(target):
		var to := target.global_position - global_position
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 10.0))
		rotation.y = yaw
	if not _attack_hit_done and _state_time >= ATTACK_HIT_TIME:
		_attack_hit_done = true
		if target and is_instance_valid(target) and _is_target_valid(target):
			var d := target.global_position - global_position
			d.y = 0.0
			# À travers une fenêtre, le bras passe au-dessus de l'allège.
			if d.length() < ATTACK_RANGE + (0.65 if barricade else 0.45):
				Game.instance.combat.damage_player(target.peer_id, Combat.ZOMBIE_DAMAGE, global_position + Vector3.UP * 1.2)
	if _state_time >= ATTACK_TIME:
		_set_state(State.BARRIER if barricade else State.CHASE)


# --------------------------------------------------------------------------
# Fenêtres barricadées (logique dans Barricade)
# --------------------------------------------------------------------------

## Toutes les machines : le zombie est apparu derrière la fenêtre `b`.
func enter_barricade(b: Barricade) -> void:
	barricade = b
	tear_t = 0.0
	_set_state(State.BARRIER)
	yaw = atan2(b.inward.x, b.inward.z)
	rotation.y = yaw


## Serveur : coup porté à travers la fenêtre au joueur `target`.
func barrier_attack() -> void:
	_start_attack()


## Serveur : enjambe la fenêtre de `from` (dehors) à `to` (dedans).
func start_vault(from: Vector3, to: Vector3) -> void:
	_vault_from = from
	_vault_to = to
	velocity = Vector3.ZERO
	_set_state(State.VAULT)


func _vault() -> void:
	var k := clampf(_state_time / BarricadeRules.VAULT_TIME, 0.0, 1.0)
	global_position = _vault_from.lerp(_vault_to, ease(k, -1.6))
	if k >= 1.0:
		if is_instance_valid(barricade):
			barricade.srv_vault_done(self)
		barricade = null
		_repath_t = 0.0
		_set_state(State.CHASE)


func _is_target_valid(p: Player) -> bool:
	var pd := Game.instance.session.get_data(p.peer_id)
	return pd != null and pd.life == PlayerData.Life.ALIVE and not p.untargetable


func _nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	if Game.instance == null:
		return null
	for p: Player in Game.instance.players.values():
		if not _is_target_valid(p):
			continue
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	_update_solidity()


## Pendant l'émergence, le corps n'est pas solide : un joueur debout sur le
## point d'apparition n'est ni poussé ni soulevé (les hitboxes restent actives).
func _update_solidity() -> void:
	if state == State.DEAD:
		return
	collision_layer = 0 if state == State.EMERGE else BODY_LAYER


# --------------------------------------------------------------------------
# Clients : interpolation des instantanés
# --------------------------------------------------------------------------

func push_snapshot(t: float, pos: Vector3, net_yaw: float, code: int) -> void:
	if not _snapshots.is_empty():
		var prev: Array = _snapshots[_snapshots.size() - 1]
		var dt: float = t - prev[0]
		if dt > 0.001:
			_last_vel = (pos - prev[1]) / dt
			_last_vel.y = 0.0
	_snapshots.append([t, pos, net_yaw, code])
	if _snapshots.size() > 12:
		_snapshots.pop_front()


func _interpolate() -> void:
	if _snapshots.is_empty():
		return
	var render_t := Time.get_ticks_usec() / 1000000.0 - INTERP_DELAY
	while _snapshots.size() >= 2 and _snapshots[1][0] <= render_t:
		_snapshots.pop_front()
	var a: Array = _snapshots[0]
	var pos: Vector3 = a[1]
	var ny: float = a[2]
	if _snapshots.size() == 1 and render_t > a[0] and _last_vel != Vector3.ZERO:
		# Paquet en retard : on prolonge brièvement le dernier mouvement connu
		# au lieu de figer le zombie (max 0,25 s).
		pos = a[1] + _last_vel * minf(render_t - a[0], 0.25)
	if _snapshots.size() >= 2 and render_t > a[0]:
		var b: Array = _snapshots[1]
		var t := clampf((render_t - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
		pos = a[1].lerp(b[1], t)
		ny = lerp_angle(a[2], b[2], t)
	var prev := global_position
	global_position = pos
	yaw = ny
	rotation.y = yaw
	var dt := get_process_delta_time()
	if dt > 0.0:
		var v := (pos - prev) / dt
		anim_speed = lerpf(anim_speed, Vector2(v.x, v.z).length(), 0.2)
	var code: int = a[3]
	var new_state: State = code & 7
	speed_class = (code >> 3) & 3
	if new_state != state and state != State.DEAD:
		if new_state == State.ATTACK:
			play_attack()
		state = new_state
		_state_time = 0.0
		_update_solidity()


# --------------------------------------------------------------------------
# Animation procédurale (toutes les machines)
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if state == State.DEAD:
		_process_death(delta)
		return
	if not server_side:
		_interpolate()
		_state_time += delta
	_groan(delta)
	if crawl_t >= 0.0:
		crawl_t += delta
	# Pose recalculée à chaque image de près ; hors champ ou au loin, à cadence
	# réduite avec le temps cumulé (même animation, moins d'écritures d'os).
	_pose_accum += delta
	if _mgr == null or _pose_accum >= _mgr.pose_step(global_position):
		_update_pose(_pose_accum)
		_pose_accum = 0.0
		_footstep()
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		mesh.set_instance_shader_parameter("hit_flash", _flash)


func flash_hit() -> void:
	_flash = 1.0


func play_attack() -> void:
	_attack_t = 0.0
	Audio.play_3d("zombie_attack_%d" % (1 + randi() % ZombieVoice.ATTACKS), global_position + Vector3.UP * 1.5, 0.0, 0.08, 3, 1.0, ZombieVoice.GROUP)
	_groan_t = maxf(_groan_t, 1.5)


func head_position() -> Vector3:
	return hit_head.global_position


## Mort (toutes les machines). `dir` : direction du coup fatal.
func die(dir: Vector3, headshot: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_state_time = 0.0
	_death_t = 0.0
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	_death_dir = 1.0 if fwd.dot(dir) > 0.0 else -1.0
	collision_layer = 0
	collision_mask = 1
	hit_body.collision_layer = 0
	hit_head.collision_layer = 0
	# Corps : plus aucune forme dans l'espace physique (hitboxes, capsule).
	hit_body.get_child(0).set_deferred("disabled", true)
	hit_head.get_child(0).set_deferred("disabled", true)
	if _body_shape:
		_body_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	set_physics_process(false)
	_snapshots.clear()
	if headshot:
		_headless = true
		skel.set_bone_pose_scale(bones.head, Vector3.ONE * 0.001)
		var neck := skel.global_transform * skel.get_bone_global_pose(bones.neck).origin
		var fx: Fx = Game.instance.fx_root
		fx.blood_hit(neck, Vector3.UP, 3.0)
		ZombieGibs.head_pop(self, neck, dir)
		Audio.play_3d("headshot", neck, 0.0, 0.08)
	else:
		Audio.play_3d("zombie_death_%d" % (1 + randi() % ZombieVoice.DEATHS), global_position + Vector3.UP * 1.4, -1.0, 0.08, 3, 1.0, ZombieVoice.GROUP)


## Mort projetée (onde de choc du TONNERRE-7) : le corps s'envole à la vitesse
## `vel` calculée par le serveur (vol procédural : ZombieFling).
func die_flung(vel: Vector3) -> void:
	if state == State.DEAD:
		return
	die(vel, false)
	add_child(ZombieFling.new(vel))


func _q(x: float, y := 0.0, z := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))


func _update_pose(delta: float) -> void:
	if skel == null:
		return
	if crawl_t >= 0.0:
		ZombieGibs.crawl_pose(self, delta)
		return
	var spd := anim_speed
	var running := speed_class >= 2
	var stride := 1.1 if not running else 1.9
	_phase += delta * (1.2 + spd * stride)
	var s := sin(_phase)
	var c := cos(_phase)
	var move_k := clampf(spd / 1.2, 0.0, 1.0)
	var leg_amp := (0.35 if not running else 0.7) * move_k + 0.03
	var lean := 0.18 + (0.25 if running else 0.0) * move_k

	var hips_y := 0.0
	var emerge_k := 1.0
	if state == State.EMERGE:
		emerge_k = clampf(_state_time / EMERGE_TIME, 0.0, 1.0)
		hips_y = lerpf(-1.7, 0.0, ease(emerge_k, 0.4))
	# Fenêtre : enjambement (saut par-dessus l'allège) ou arrachage sur place.
	var vault_k := -1.0
	var tearing := state == State.BARRIER and spd < 0.4
	if state == State.VAULT:
		vault_k = sin(clampf(_state_time / BarricadeRules.VAULT_TIME, 0.0, 1.0) * PI)
		# Pieds au-dessus de l'allège, buste plié sous le linteau.
		hips_y = vault_k * 0.95
		lean += vault_k * 1.1
	elif tearing:
		lean = 0.32
	skel.position.y = hips_y

	# Jambes
	if vault_k >= 0.0:
		skel.set_bone_pose_rotation(bones.thigh_l, _q(-1.2 * vault_k))
		skel.set_bone_pose_rotation(bones.thigh_r, _q(-0.9 * vault_k))
		skel.set_bone_pose_rotation(bones.shin_l, _q(1.5 * vault_k))
		skel.set_bone_pose_rotation(bones.shin_r, _q(1.3 * vault_k))
	else:
		skel.set_bone_pose_rotation(bones.thigh_l, _q(s * leg_amp))
		skel.set_bone_pose_rotation(bones.thigh_r, _q(-s * leg_amp))
		skel.set_bone_pose_rotation(bones.shin_l, _q(-maxf(0.0, -c) * leg_amp * 1.4))
		skel.set_bone_pose_rotation(bones.shin_r, _q(-maxf(0.0, c) * leg_amp * 1.4))
	# Tronc : penché, balancement
	var sway := sin(_phase * 0.5) * 0.12
	skel.set_bone_pose_rotation(bones.spine, _q(lean, sway * 0.5, sway))
	skel.set_bone_pose_rotation(bones.chest, _q(lean * 0.5, -sway, 0.0))
	skel.set_bone_pose_rotation(bones.head, _q(-0.25 + sin(_phase * 1.7) * 0.08, 0.0, _head_tilt))
	skel.set_bone_pose_position(bones.hips, Vector3(0, skel.get_bone_rest(bones.hips).origin.y + absf(c) * 0.04 * move_k, 0))

	# Bras : tendus vers l'avant (marcheurs) ou balancés (coureurs)
	var arm_l := -1.35 + s * 0.12
	var arm_r := -1.25 - s * 0.12
	var fore := -0.2
	if running:
		arm_l = -0.6 - s * 0.7 * move_k
		arm_r = -0.6 + s * 0.7 * move_k
		fore = -0.9
	if state == State.EMERGE:
		arm_l = lerpf(-2.8, arm_l, emerge_k)
		arm_r = lerpf(-2.6, arm_r, emerge_k)
	if tearing:
		# Agrippe une planche (bras tendus vers le haut) puis l'arrache d'un coup.
		var t := fmod(_state_time, BarricadeRules.TEAR_TIME) / BarricadeRules.TEAR_TIME
		var grab := -1.45 - 0.55 * ease(t / 0.7, 0.6) if t < 0.7 else lerpf(-2.0, -0.8, (t - 0.7) / 0.3)
		arm_l = grab + 0.08 * s
		arm_r = grab - 0.1 - 0.08 * s
		fore = -0.6
	elif vault_k >= 0.0:
		arm_l = -1.9 + vault_k * 0.4
		arm_r = -1.7 + vault_k * 0.3
	if _attack_t >= 0.0:
		_attack_t += delta / 0.7
		var k := sin(clampf(_attack_t, 0.0, 1.0) * PI)
		arm_l = lerpf(arm_l, -2.4 + _attack_t * 2.4, k)
		arm_r = lerpf(arm_r, -2.2 + _attack_t * 2.0, k)
		if _attack_t >= 1.0:
			_attack_t = -1.0
	skel.set_bone_pose_rotation(bones.arm_l, _q(arm_l, 0.0, -0.15))
	skel.set_bone_pose_rotation(bones.arm_r, _q(arm_r, 0.0, 0.15))
	skel.set_bone_pose_rotation(bones.forearm_l, _q(fore + c * 0.1))
	skel.set_bone_pose_rotation(bones.forearm_r, _q(fore - c * 0.1))


## Grognements d'ambiance (cosmétique, non synchronisé).
func _groan(delta: float) -> void:
	_groan_t -= delta
	if _groan_t > 0.0:
		return
	_groan_t = ZombieVoice.interval(speed_class, randf())
	if state == State.EMERGE:
		Audio.play_3d("emerge", global_position, -4.0, 0.1, 2)
		return
	_last_vocal = ZombieVoice.pick(ZombieVoice.vocal_count(speed_class), _last_vocal, randi())
	Audio.play_3d(ZombieVoice.vocal_name(speed_class, _last_vocal), global_position + Vector3.UP * 1.5,
		-3.0, 0.06, 3, 1.0, ZombieVoice.GROUP)


## Pas traînants (de près seulement), un par demi-cycle de marche.
func _footstep() -> void:
	var step := int(floor(_phase / PI))
	if step == _step_i:
		return
	_step_i = step
	if state == State.DEAD or state == State.EMERGE or anim_speed < 0.3:
		return
	var ear: Variant = Audio.listener_position()
	if ear == null or global_position.distance_to(ear) > ZombieVoice.STEP_RANGE:
		return
	Audio.play_3d("zombie_step_%d" % (1 + randi() % ZombieVoice.STEPS), global_position + Vector3.UP * 0.05,
		-9.0 if speed_class < 2 else -6.0, 0.1, 6, 1.0, ZombieVoice.STEP_GROUP)


## Chute, puis dissolution. Le nœud est libéré par ZombieManager (despawn).
func _process_death(delta: float) -> void:
	var before := _death_t
	_death_t += delta
	# Chute et membres qui retombent mollement ; ensuite le corps est immobile
	# (les rotations ont convergé) : plus aucune écriture d'os.
	if before <= DEATH_SETTLE_TIME:
		var k := ease(clampf(_death_t / 0.65, 0.0, 1.0), 0.4)
		if crawl_t < 0.0:  # un rampant est déjà au sol
			skel.rotation.x = _death_dir * k * PI * 0.47
			skel.position.y = -k * 0.08
		for b in DEATH_ARMS:
			var q := skel.get_bone_pose_rotation(bones[b])
			skel.set_bone_pose_rotation(bones[b], q.slerp(_q(-0.4 * _death_dir), minf(delta * 5.0, 1.0)))
		for b in DEATH_LIMBS:
			var q2 := skel.get_bone_pose_rotation(bones[b])
			skel.set_bone_pose_rotation(bones[b], q2.slerp(Quaternion.IDENTITY, minf(delta * 4.0, 1.0)))
	if before < 0.6 and _death_t >= 0.6:
		Audio.play_3d("body_fall", global_position, -6.0, 0.1, 3)
		if Game.instance:
			Game.instance.fx_root.blood_decal(global_position + Vector3.UP * 0.1 + Vector3(sin(yaw), 0, cos(yaw)) * _death_dir * 0.8, Vector3.UP, randf_range(0.8, 1.4))
	if _death_t > DISSOLVE_DELAY:
		mesh.set_instance_shader_parameter("dissolve", clampf((_death_t - DISSOLVE_DELAY) / DISSOLVE_TIME, 0.0, 1.0))
		if before <= DISSOLVE_DELAY:
			mesh.set_instance_shader_parameter("eye_glow", 0.0)


## Temps passé quasi immobile en poursuite (serveur) : sert au recyclage.
func stuck_time() -> float:
	return _low_move_t
