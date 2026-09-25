class_name Zombie
extends CharacterBody3D
## Zombie. Le SERVEUR simule (IA, déplacement, santé) ; les clients n'ont qu'une
## marionnette interpolée à partir des instantanés du ZombieManager, avec des
## hitboxes pour que le tireur puisse viser localement.

enum State { EMERGE, IDLE, CHASE, ATTACK, DEAD }

## Vitesses par classe (m/s) : marcheur, trotteur, coureur, sprinteur.
const SPEEDS := [1.25, 2.3, 3.7, 5.0]
const GRAVITY := 16.0
const RADIUS := 0.3
const HEIGHT := 1.75
const EMERGE_TIME := 1.4
const INTERP_DELAY := 0.12
const HITBOX_LAYER := 1 << 3

var id := 0
var variant := 0
var speed_class := 0
var server_side := false
var state: State = State.EMERGE
var yaw := 0.0
var health := 150
var max_health := 150

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

var skel: Skeleton3D
var mesh: MeshInstance3D
var bones: Dictionary
var hit_body: Area3D
var hit_head: Area3D


func setup(zid: int, zvariant: int, zspeed: int, is_server: bool) -> void:
	id = zid
	variant = zvariant
	speed_class = zspeed
	server_side = is_server
	name = "Z%d" % zid


func _ready() -> void:
	collision_layer = 1 << 2
	collision_mask = 1 | (1 << 1) | (1 << 2)  # monde, joueurs, zombies
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	cs.position.y = HEIGHT * 0.5
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
		State.DEAD:
			return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	if state != State.EMERGE:
		move_and_slide()
	anim_speed = Vector2(velocity.x, velocity.z).length()


## Poursuite directe du joueur le plus proche (remplacée par la navigation).
func _chase(delta: float) -> void:
	var target := _nearest_player()
	var desired := Vector3.ZERO
	if target:
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() > 1.1:
			desired = to.normalized() * SPEEDS[speed_class]
	var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, 12.0 * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if horiz.length() > 0.1:
		# Le modèle regarde vers +Z.
		yaw = lerp_angle(yaw, atan2(horiz.x, horiz.z), 1.0 - exp(-delta * 8.0))
	rotation.y = yaw


func _nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	if Game.instance == null:
		return null
	for p in Game.instance.players.values():
		var d: float = p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0


# --------------------------------------------------------------------------
# Clients : interpolation des instantanés
# --------------------------------------------------------------------------

func push_snapshot(t: float, pos: Vector3, net_yaw: float, code: int) -> void:
	_snapshots.append([t, pos, net_yaw, code])
	if _snapshots.size() > 12:
		_snapshots.pop_front()


func _interpolate() -> void:
	if _snapshots.is_empty():
		return
	var render_t := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	while _snapshots.size() >= 2 and _snapshots[1][0] <= render_t:
		_snapshots.pop_front()
	var a: Array = _snapshots[0]
	var pos: Vector3 = a[1]
	var ny: float = a[2]
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
		state = new_state
		_state_time = 0.0


# --------------------------------------------------------------------------
# Animation procédurale (toutes les machines)
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not server_side and state != State.DEAD:
		_interpolate()
	if server_side == false:
		_state_time += delta
	_update_pose(delta)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		mesh.set_instance_shader_parameter("hit_flash", _flash)


func flash_hit() -> void:
	_flash = 1.0


func play_attack() -> void:
	_attack_t = 0.0


func _q(x: float, y := 0.0, z := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))


func _update_pose(delta: float) -> void:
	if skel == null:
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
	skel.position.y = hips_y

	# Jambes
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
