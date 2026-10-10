class_name Hellhound
extends Zombie
## Chien de l'enfer (manches de chiens de BO1). C'est un « type d'entité » du
## ZombieManager : même canal réseau (apparition, instantanés, mort), mêmes
## dégâts, points, bonus et pièges que les zombies. Seuls changent le modèle
## (quadrupède), l'apparition par la foudre, la course, le bond de morsure et
## l'explosion de flammes à la mort.

## Bond : déclenché à cette distance, élan puis morsure.
const LUNGE_RANGE := 2.3
const LUNGE_SPEED := 7.5
const LUNGE_TIME := 0.28
const BITE_TIME := 0.3
const BITE_REACH := 1.9
const DOG_ATTACK_TIME := 0.8
## Capsule de déplacement (corps de profil, debout) et portée de la séparation
## entre deux chiens ou un chien et un zombie : deux corps au contact et 0,3 m
## (comme Zombie.SEPARATION_RANGE).
const RADIUS_DOG := 0.3
const SEPARATION_DOG := 0.9
const DEATH_BURN := 0.9
## Flammes : particules par seconde (image proche) et couleur.
const FLAME_RATE := 26.0
const FLAME_COLOR := Color(1.0, 0.38, 0.06, 0.5)

## Serveur : joueur que ce chien chasse en priorité (get_favorite_enemy).
var favorite_enemy: Player
var _life_t := 0.0
var _revealed := false
var _lunge_dir := Vector3.ZERO
var _flame_accum := 0.0
var _light: OmniLight3D
var _lightning: DogLightning


func _ready() -> void:
	_mgr = get_parent() as ZombieManager
	game = _mgr.game if _mgr else null
	_multilevel = map_is_multilevel()
	speed_class = 3
	speed_mult = DogRules.RUN_SPEED / Zombie.SPEEDS[3]
	sep_range = SEPARATION_DOG
	collision_layer = 0
	collision_mask = 1 | (1 << 1) | (1 << 2)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS_DOG
	cap.height = 0.9
	cs.shape = cap
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Glisse le long d'un mur abordé presque de face (comme Zombie).
	wall_min_slide_angle = 0.0
	cs.position.y = 0.45 + floor_gap()
	_body_shape = cs
	add_child(cs)

	skel = HellhoundModel.build(variant)
	add_child(skel)
	mesh = skel.get_node("Mesh")
	bones = RigBuilder.bone_indices(skel)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	_phase = rng.randf() * TAU

	# Tronc : capsule couchée le long du dos.
	var body_cap := CapsuleShape3D.new()
	body_cap.radius = 0.24
	body_cap.height = 1.05
	hit_body = _make_hitbox(0, body_cap)
	hit_body.position = Vector3(0, 0.52, 0.02)
	hit_body.rotation.x = PI * 0.5
	add_child(hit_body)
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var sph := SphereShape3D.new()
	sph.radius = 0.15
	hit_head = _make_hitbox(1, sph)
	hit_head.position = Vector3(0, 0.0, 0.1)
	att.add_child(hit_head)
	# Invisible et intouchable tant que la foudre n'a pas frappé.
	hit_body.collision_layer = 0
	hit_head.collision_layer = 0
	skel.visible = false

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.15)
	_light.omni_range = 3.2
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.7, 0.1)
	add_child(_light)

	_lightning = DogLightning.new()
	add_child(_lightning)
	if not server_side:
		set_physics_process(false)
	_update_pose(0.0)


## Hitbox de la tête : conserve la hauteur réelle du chien.
func head_position() -> Vector3:
	return hit_head.global_position


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.EMERGE:
		_state_time += delta
		if _state_time >= DogRules.SPAWN_TIME:
			_set_state(State.CHASE)
		return
	super(delta)


func _chase(delta: float) -> void:
	# Bond dès que la cible est à portée et en vue directe.
	if target and is_instance_valid(target) and _is_target_valid(target):
		var to := target.global_position - global_position
		var dy := absf(to.y)
		to.y = 0.0
		var d := to.length()
		if d < LUNGE_RANGE and d > 0.01 and dy < 0.9 and game.nav.world_line_clear(global_position, target.global_position):
			_lunge_dir = to / d
			_start_attack()
			return
	super(delta)


## Balayages de Zombie._body_fits / _leg_clear : capsule du chien (0,3 m, pas
## d'épaules plus larges), au milieu de sa hauteur (0,9 m), pas à la poitrine
## d'un zombie (1,1 m, au-dessus du chien).
func _fit_radius(_slim: bool) -> float:
	return RADIUS_DOG


func _leg_radius() -> float:
	return RADIUS_DOG


func _fit_height() -> float:
	return 0.45 + floor_gap()


func _nearest_player() -> Player:
	if favorite_enemy and is_instance_valid(favorite_enemy) and _is_target_valid(favorite_enemy):
		return favorite_enemy
	return super()


func _start_attack() -> void:
	_set_state(State.ATTACK)
	_attack_hit_done = false
	if _lunge_dir == Vector3.ZERO:
		_lunge_dir = Vector3(sin(yaw), 0.0, cos(yaw))
	play_attack()


func _attack(delta: float) -> void:
	if _state_time < LUNGE_TIME:
		velocity.x = _lunge_dir.x * LUNGE_SPEED
		velocity.z = _lunge_dir.z * LUNGE_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)
	if target and is_instance_valid(target):
		var to := target.global_position - global_position
		yaw = lerp_angle(yaw, atan2(to.x, to.z), 1.0 - exp(-delta * 10.0))
		rotation.y = yaw
	if not _attack_hit_done and _state_time >= BITE_TIME:
		_attack_hit_done = true
		if target and is_instance_valid(target) and _is_target_valid(target):
			var d := target.global_position - global_position
			var dy := absf(d.y)
			d.y = 0.0
			if d.length() < BITE_REACH and dy < LEVEL_TOLERANCE:
				game.combat.damage_player(target.peer_id, DogRules.BITE_DAMAGE, global_position + Vector3.UP * 0.6)
	if _state_time >= DOG_ATTACK_TIME:
		_lunge_dir = Vector3.ZERO
		_set_state(State.CHASE)


# --------------------------------------------------------------------------
# Toutes les machines
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _life_t == 0.0:
		# Première image : la position d'apparition est maintenant connue.
		Audio.play_3d("dog_prespawn", global_position + Vector3.UP * 2.0, 0.0, 0.08, 3)
	_life_t += maxf(delta, 0.0001)
	if state == State.DEAD:
		_process_death(delta)
		return
	if not server_side:
		_interpolate()
		_state_time += delta
	if not _revealed and (state != State.EMERGE or _life_t >= DogRules.SPAWN_TIME + 0.4):
		_reveal()
	if not _revealed:
		return
	_groan(delta)
	_pose_accum += delta
	var step := _mgr.pose_step(global_position) if _mgr else 0.0
	if _pose_accum >= step:
		_update_pose(_pose_accum)
		_pose_accum = 0.0
	_emit_flames(delta, step)
	_light.light_energy = 1.1 + 0.35 * sin(_life_t * 23.0) * sin(_life_t * 7.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		mesh.set_instance_shader_parameter("hit_flash", _flash)


## La foudre a frappé : le chien devient visible, solide et touchable.
func _reveal() -> void:
	_revealed = true
	skel.visible = true
	collision_layer = 1 << 2
	hit_body.collision_layer = HITBOX_LAYER
	hit_head.collision_layer = HITBOX_LAYER
	_light.light_energy = 1.2


## Flammes qui lèchent le dos et les pattes (pool de particules partagé).
func _emit_flames(delta: float, step: float) -> void:
	var pool := DogRound.flame_pool()
	if pool == null:
		return
	# Hors champ ou au loin : beaucoup moins de particules.
	var rate := FLAME_RATE if step <= 0.0 else FLAME_RATE * 0.2
	_flame_accum += delta * rate
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var base := global_position + skel.position
	while _flame_accum >= 1.0:
		_flame_accum -= 1.0
		var along := randf_range(-0.35, 0.35)
		var at := base + fwd * along + right * randf_range(-0.12, 0.12) + Vector3.UP * randf_range(0.35, 0.7)
		var vel := Vector3(randf_range(-0.2, 0.2), randf_range(0.6, 1.4), randf_range(-0.2, 0.2)) - fwd * anim_speed * 0.15
		var col := FLAME_COLOR.lerp(Color(1.0, 0.7, 0.2, 0.45), randf() * 0.4)
		pool.emit(at, vel, randf_range(0.25, 0.45), col, randf_range(0.8, 1.5))


func play_attack() -> void:
	_attack_t = 0.0
	Audio.play_3d("dog_bark_%d" % (1 + randi() % 2), global_position + Vector3.UP * 0.7, 0.0, 0.1, 3)
	# Morsure en fin de bond (claquement de mâchoires).
	get_tree().create_timer(0.22).timeout.connect(func():
		if is_instance_valid(self) and state != State.DEAD:
			Audio.play_3d("dog_bite_%d" % (1 + randi() % 2), global_position + Vector3.UP * 0.6, 0.0, 0.1, 3))


## Mort : explosion de flammes et gémissement ; le corps se consume.
func die(_dir: Vector3, _headshot: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_state_time = 0.0
	_death_t = 0.0
	collision_layer = 0
	collision_mask = 1
	hit_body.collision_layer = 0
	hit_head.collision_layer = 0
	hit_body.get_child(0).set_deferred("disabled", true)
	hit_head.get_child(0).set_deferred("disabled", true)
	if _body_shape:
		_body_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	set_physics_process(false)
	clear_snapshots()
	if not _revealed:
		# Tué avant d'apparaître : rien à faire exploser.
		skel.visible = false
		_light.light_energy = 0.0
		return
	var c := global_position + Vector3.UP * 0.5
	var fx: Fx = game.fx_root if game else null
	if fx:
		fx.sparks.burst(c, Vector3.UP, 14, 5.0, 1.1, 0.6, Color(1.0, 0.5, 0.12, 0.9), 0.8)
		fx.explosion_light(c, Color(1.0, 0.45, 0.12))
	var pool := DogRound.flame_pool()
	if pool:
		pool.burst(c, Vector3.UP, 14, 2.0, 0.9, 0.55, FLAME_COLOR, 1.6)
	Audio.play_3d("dog_explode", c, 2.0, 0.08, 4)
	Audio.play_3d("dog_whine", c, -2.0, 0.1, 3)


func _process_death(delta: float) -> void:
	_death_t += delta
	var k := clampf(_death_t / DEATH_BURN, 0.0, 1.0)
	if skel.visible:
		mesh.set_instance_shader_parameter("dissolve", k)
		skel.rotation.z = ease(minf(_death_t / 0.35, 1.0), 0.5) * 1.4
		skel.position.y = -k * 0.1
		if k >= 1.0:
			skel.visible = false
			mesh.set_instance_shader_parameter("eye_glow", 0.0)
	_light.light_energy = maxf(1.0 - k, 0.0) * 2.0


func _groan(delta: float) -> void:
	_groan_t -= delta
	if _groan_t > 0.0:
		return
	_groan_t = randf_range(1.6, 3.6)
	Audio.play_3d("dog_growl_%d" % (1 + randi() % 3), global_position + Vector3.UP * 0.7, -3.0, 0.12, 3)


func _update_pose(delta: float) -> void:
	if skel == null:
		return
	var spd := anim_speed
	var move_k := clampf(spd / 3.0, 0.0, 1.0)
	# Galop : fréquence de foulée croissante avec la vitesse.
	_phase += delta * (2.5 + spd * 1.9)
	var ph := _phase
	var amp := 0.25 + 0.5 * move_k
	var f_l := sin(ph) * amp
	var f_r := sin(ph + 0.35) * amp
	var r_l := sin(ph + PI) * amp
	var r_r := sin(ph + PI + 0.35) * amp
	var hips_pitch := sin(ph + PI * 0.5) * 0.07 * move_k
	var bob := absf(sin(ph)) * 0.05 * move_k
	var head_pitch := 0.15 * move_k + sin(ph * 2.0) * 0.05
	var neck_pitch := -0.1 + 0.2 * move_k
	var jaw := 0.0
	if _attack_t >= 0.0:
		# Bond : l'avant se cabre, pattes avant lancées, gueule en avant.
		_attack_t += delta / 0.6
		var a := sin(clampf(_attack_t, 0.0, 1.0) * PI)
		hips_pitch = lerpf(hips_pitch, -0.45, a)
		bob += a * 0.22
		f_l = lerpf(f_l, -1.1, a)
		f_r = lerpf(f_r, -1.0, a)
		r_l = lerpf(r_l, 0.6, a)
		r_r = lerpf(r_r, 0.55, a)
		head_pitch = lerpf(head_pitch, 0.35, a)
		jaw = a
		if _attack_t >= 1.0:
			_attack_t = -1.0
	elif spd < 0.3:
		# Arrêt : respiration haletante, tête basse.
		bob = sin(_life_t * 9.0) * 0.008
		head_pitch = 0.25 + sin(_life_t * 9.0) * 0.03
	skel.position.y = bob
	skel.set_bone_pose_rotation(bones.hips, _q(hips_pitch))
	skel.set_bone_pose_rotation(bones.spine, _q(-hips_pitch * 0.5))
	skel.set_bone_pose_rotation(bones.chest, _q(-hips_pitch * 0.5))
	skel.set_bone_pose_rotation(bones.neck, _q(neck_pitch))
	skel.set_bone_pose_rotation(bones.head, _q(head_pitch - jaw * 0.2, 0.0, sin(ph * 0.5) * 0.06))
	skel.set_bone_pose_rotation(bones.arm_l, _q(f_l))
	skel.set_bone_pose_rotation(bones.arm_r, _q(f_r))
	skel.set_bone_pose_rotation(bones.thigh_l, _q(r_l))
	skel.set_bone_pose_rotation(bones.thigh_r, _q(r_r))
	# Genoux : les pattes se replient quand elles reviennent vers l'avant.
	skel.set_bone_pose_rotation(bones.forearm_l, _q(maxf(0.0, cos(ph)) * 0.9 * move_k))
	skel.set_bone_pose_rotation(bones.forearm_r, _q(maxf(0.0, cos(ph + 0.35)) * 0.9 * move_k))
	skel.set_bone_pose_rotation(bones.shin_l, _q(-maxf(0.0, cos(ph + PI)) * 0.8 * move_k))
	skel.set_bone_pose_rotation(bones.shin_r, _q(-maxf(0.0, cos(ph + PI + 0.35)) * 0.8 * move_k))


## Le chien reste non solide tant que la foudre ne l'a pas révélé.
func _update_solidity() -> void:
	if not _revealed:
		collision_layer = 0
		return
	super()
