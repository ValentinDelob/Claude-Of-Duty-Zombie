class_name Hellhound
extends Zombie
## Chien errant contaminé (vague spéciale « meute », GAME_CONCEPT.md § 4.4).
## C'est un « type d'entité » du ZombieManager : même canal réseau
## (apparition, instantanés, mort), mêmes dégâts, points, bonus et pièges que
## les zombies. Seuls changent le modèle (quadrupède cubique, HellhoundModel),
## l'animation (DogAnim), l'arrivée de la meute (DogRound : tapi hors de vue,
## annoncé par un grognement, il jaillit accroupi), la course, le bond de
## morsure et la mort (il s'effondre sur le flanc et son sang contaminé
## gicle : brûlure des joueurs tout proches, DogRules.EXPLODE_*).

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
## Mort : le corps reste couché puis se dissout cube par cube (avant le
## retrait par ZombieManager, DISSOLVE_DELAY + DISSOLVE_TIME + 0,3 s).
const DOG_DISSOLVE_DELAY := 1.6
const DOG_DISSOLVE_TIME := 1.2
## Giclée de sang contaminé à la mort (couleur des particules).
const SPLATTER_COLOR := Color(0.32, 0.05, 0.03, 0.95)

## Serveur : joueur que ce chien chasse en priorité (get_favorite_enemy).
var favorite_enemy: Player
var _life_t := 0.0
var _revealed := false
var _appear_t := -1.0
var _lunge_dir := Vector3.ZERO
var _death_side := 1.0


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

	# Zones taillées sur le modèle : tronc (capsule couchée le long du dos) et
	# tête (sphère sur l'os de la tête : suit le bond et la secousse).
	var shapes := HellhoundModel.hit_shapes()
	var body: Array = shapes.body
	var body_cap := CapsuleShape3D.new()
	body_cap.radius = body[1]
	body_cap.height = maxf(body[2] + body[1], body[1] * 2.0)
	hit_body = _make_hitbox(0, body_cap)
	hit_body.position = body[0]
	hit_body.rotation.x = PI * 0.5
	add_child(hit_body)
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var sph := SphereShape3D.new()
	sph.radius = shapes.head[1]
	hit_head = _make_hitbox(1, sph)
	hit_head.position = shapes.head[0]
	att.add_child(hit_head)
	# Tapi hors de vue, invisible et intouchable jusqu'à son irruption.
	hit_body.collision_layer = 0
	hit_head.collision_layer = 0
	skel.visible = false
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
		# Première image (position connue) : grognement sourd depuis sa cachette.
		Audio.play_3d("dog_growl_%d" % (1 + randi() % 3), global_position + Vector3.UP * 0.5, -2.0, 0.1, 3)
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
	if _appear_t >= 0.0:
		_appear_t += delta / DogAnim.APPEAR_TIME
		if _appear_t >= 1.0:
			_appear_t = -1.0
	_groan(delta)
	_pose_accum += delta
	var step := _mgr.pose_step(global_position) if _mgr else 0.0
	if _pose_accum >= step:
		_update_pose(_pose_accum)
		_pose_accum = 0.0
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		mesh.set_instance_shader_parameter("hit_flash", _flash)


## Irruption : le chien devient visible, solide et touchable, et jaillit
## accroupi de sa cachette (aboiement, poussière soulevée).
func _reveal() -> void:
	_revealed = true
	_appear_t = 0.0
	skel.visible = true
	collision_layer = 1 << 2
	hit_body.collision_layer = HITBOX_LAYER
	hit_head.collision_layer = HITBOX_LAYER
	Audio.play_3d("dog_bark_%d" % (1 + randi() % 2), global_position + Vector3.UP * 0.6, 0.0, 0.1, 3)
	var fx: Fx = game.fx_root if game else null
	if fx:
		fx.dust.burst(global_position + Vector3.UP * 0.1, Vector3.UP, 6, 1.2, 0.8, 0.9, Color(0.22, 0.2, 0.18, 0.45), 1.6)


func play_attack() -> void:
	_attack_t = 0.0
	Audio.play_3d("dog_bark_%d" % (1 + randi() % 2), global_position + Vector3.UP * 0.7, 0.0, 0.1, 3)
	# Morsure en fin de bond (claquement de mâchoires).
	get_tree().create_timer(0.22).timeout.connect(func():
		if is_instance_valid(self) and state != State.DEAD:
			Audio.play_3d("dog_bite_%d" % (1 + randi() % 2), global_position + Vector3.UP * 0.6, 0.0, 0.1, 3))


## Mort : glapissement, giclée de sang contaminé ; le chien s'effondre sur le
## flanc opposé au coup puis se dissout.
func die(dir: Vector3, _headshot: bool) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_state_time = 0.0
	_death_t = 0.0
	# Côté de la chute : poussé par le coup (+1 : sur son flanc droit, -X).
	var left := Vector3(cos(yaw), 0.0, -sin(yaw))
	_death_side = 1.0 if dir.dot(left) <= 0.0 else -1.0
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
		# Tué avant son irruption : rien à montrer.
		skel.visible = false
		return
	var c := global_position + Vector3.UP * 0.5
	var fx: Fx = game.fx_root if game else null
	if fx:
		fx.blood_hit(c, Vector3.UP, 3.0)
		fx.blood.burst(c, Vector3.UP, 16, 3.2, 0.9, 0.7, SPLATTER_COLOR, 1.4)
		fx.blood_decal(global_position + Vector3.UP * 0.1, Vector3.UP, 1.3)
	Audio.play_3d("dog_whine", c, -1.0, 0.1, 3)
	Audio.play_3d("flesh_hit_%d" % (1 + randi() % 3), c, 0.0, 0.1, 3)


func _process_death(delta: float) -> void:
	var before := _death_t
	_death_t += delta
	if not skel.visible:
		return
	if before <= DogAnim.DEATH_SETTLE + 0.1:
		DogAnim.apply(skel, bones, DogAnim.pose(_phase, 0.0, _life_t, -1.0, -1.0, _death_t, _death_side))
	if before < DogAnim.DEATH_BUCKLE + DogAnim.DEATH_ROLL * 0.7 and _death_t >= DogAnim.DEATH_BUCKLE + DogAnim.DEATH_ROLL * 0.7:
		Audio.play_3d("body_fall", global_position, -8.0, 0.1, 3)
	if _death_t > DOG_DISSOLVE_DELAY:
		var k := clampf((_death_t - DOG_DISSOLVE_DELAY) / DOG_DISSOLVE_TIME, 0.0, 1.0)
		HellhoundModel.set_dissolve(mesh, k)
		if before <= DOG_DISSOLVE_DELAY:
			mesh.set_instance_shader_parameter("eye_glow", 0.0)
		if k >= 1.0:
			skel.visible = false


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
	# Galop : fréquence de foulée croissante avec la vitesse.
	_phase += delta * (3.0 + spd * 1.75)
	if _attack_t >= 0.0:
		_attack_t += delta / DogAnim.ATTACK_TIME
		if _attack_t > 1.0:
			_attack_t = -1.0
	var p := DogAnim.pose(_phase, spd / DogRules.RUN_SPEED, _life_t, _attack_t, _appear_t)
	DogAnim.apply(skel, bones, p)


## Le chien reste non solide tant qu'il n'a pas jailli de sa cachette.
func _update_solidity() -> void:
	if not _revealed:
		collision_layer = 0
		return
	super()
