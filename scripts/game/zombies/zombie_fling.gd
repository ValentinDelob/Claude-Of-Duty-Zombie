class_name ZombieFling
extends Node
## Vol procédural d'un zombie tué par l'onde de choc du TONNERRE-7 (toutes
## les machines, même vitesse initiale reçue du serveur : même trajectoire).
##
## Enfant du zombie mort : traité APRÈS lui à chaque image, il écrase la pose
## de chute de Zombie._process_death. Le corps suit une parabole, tournoie,
## bras et jambes ballants, ricoche sur les murs, rebondit au sol puis reste
## allongé jusqu'à la dissolution (le ZombieManager libère le zombie).

const GRAVITY := 20.0
const WALL_BOUNCE := 0.25
const GROUND_BOUNCE := 0.3
const SETTLE_TIME := 0.25
## Hauteur du centre du corps pour les collisions avec les murs.
const BODY_Y := 0.8

var velocity := Vector3.ZERO
var flying := true
var _z: Zombie
var _ground_y := 0.0
var _t := 0.0
var _spin_axis := Vector3.RIGHT
var _spin_rate := 9.0
var _angle := 0.0
var _land_t := -1.0
var _land_basis := Basis.IDENTITY
var _lie_basis := Basis.IDENTITY
var _bounces := 0


func _init(vel: Vector3) -> void:
	velocity = vel
	name = "Fling"


func _ready() -> void:
	_z = get_parent() as Zombie
	if _z == null:
		queue_free()
		return
	_ground_y = _z.global_position.y
	# Culbute vers l'arrière autour de l'axe horizontal perpendiculaire au vol,
	# dans le repère du zombie (le squelette est tourné selon son lacet).
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var local := _z.global_basis.inverse() * (flat.normalized() if flat.length_squared() > 0.01 else Vector3.BACK)
	_spin_axis = Vector3.UP.cross(local).normalized()
	if _spin_axis.length_squared() < 0.01:
		_spin_axis = Vector3.RIGHT
	var rng := RandomNumberGenerator.new()
	rng.seed = _z.variant
	_spin_rate = rng.randf_range(7.0, 12.0) * clampf(flat.length() / 15.0, 0.6, 1.3)
	# Pose finale : allongé dans le sens du vol (tête vers l'avant du vol).
	_lie_basis = Basis(_spin_axis, PI * 0.47)
	Audio.play_3d("zombie_fling", _z.global_position + Vector3.UP, -1.0, 0.12, 4)


func _process(delta: float) -> void:
	if _z == null or _z.skel == null:
		return
	_t += delta
	var skel := _z.skel
	if flying:
		_fly(minf(delta, 0.05))
		_angle += _spin_rate * delta
		skel.basis = Basis(_spin_axis, _angle)
		skel.position = Vector3(0, BODY_Y, 0) - skel.basis * Vector3(0, BODY_Y, 0)
		_flail()
	elif _land_t >= 0.0:
		_land_t += delta
		var k := ease(clampf(_land_t / SETTLE_TIME, 0.0, 1.0), 0.5)
		skel.basis = Basis(_land_basis.get_rotation_quaternion().slerp(_lie_basis.get_rotation_quaternion(), k))
		skel.position = Vector3(0, -0.06 * k, 0)
		# Zombie cubique : couché sur son point le plus bas, pas dans le sol.
		if _z.anim:
			_z.anim.ground(false)


func _fly(dt: float) -> void:
	velocity.y -= GRAVITY * dt
	var pos := _z.global_position
	var next := pos + velocity * dt
	# Murs : ricochet amorti (le corps ne traverse pas le décor).
	var from := pos + Vector3.UP * BODY_Y
	var to := next + Vector3.UP * BODY_Y
	var q := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * 0.3, 1)
	var hit := _z.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and absf(hit.normal.y) < 0.7:
		var n: Vector3 = hit.normal
		velocity = (velocity - 2.0 * velocity.dot(n) * n) * WALL_BOUNCE
		next = hit.position + n * 0.35 - Vector3.UP * BODY_Y
		next.y = maxf(next.y, _ground_y)
		if _z.game:
			_z.game.fx_root.blood_hit(hit.position, n, 1.0)
		Audio.play_3d("body_fall", hit.position, -3.0, 0.15, 3)
	if next.y <= _ground_y:
		next.y = _ground_y
		_bounces += 1
		if _z.game:
			_z.game.fx_root.dust.burst(next + Vector3.UP * 0.1, Vector3.UP, 5, 1.2, 0.8, 1.0, Color(0.35, 0.32, 0.28, 0.45), 2.5)
		if velocity.y < -4.0 and _bounces < 3:
			velocity.y = -velocity.y * GROUND_BOUNCE
			velocity.x *= 0.5
			velocity.z *= 0.5
			Audio.play_3d("body_fall", next, -2.0, 0.1, 3)
		else:
			_land()
	_z.global_position = next


func _land() -> void:
	flying = false
	velocity = Vector3.ZERO
	_land_t = 0.0
	_land_basis = _z.skel.basis.orthonormalized()
	if _z.game:
		_z.game.fx_root.blood_decal(_z.global_position + Vector3.UP * 0.1, Vector3.UP, randf_range(0.9, 1.4))


## Bras en croix qui battent, jambes qui pédalent.
func _flail() -> void:
	var skel := _z.skel
	var b: Dictionary = _z.bones
	var s := sin(_t * 17.0 + float(_z.variant % 7))
	var c := cos(_t * 13.0)
	_rot(skel, b, "arm_l", Vector3(-2.4 + s * 0.6, 0.0, -0.9))
	_rot(skel, b, "arm_r", Vector3(-2.2 - s * 0.6, 0.0, 0.9))
	_rot(skel, b, "forearm_l", Vector3(-0.4 + c * 0.4, 0.0, 0.0))
	_rot(skel, b, "forearm_r", Vector3(-0.4 - c * 0.4, 0.0, 0.0))
	_rot(skel, b, "thigh_l", Vector3(-0.7 + c * 0.6, 0.0, -0.2))
	_rot(skel, b, "thigh_r", Vector3(-0.5 - c * 0.6, 0.0, 0.2))
	_rot(skel, b, "shin_l", Vector3(0.9 + s * 0.4, 0.0, 0.0))
	_rot(skel, b, "shin_r", Vector3(0.7 - s * 0.4, 0.0, 0.0))
	_rot(skel, b, "spine", Vector3(-0.5, 0.0, 0.0))


static func _rot(skel: Skeleton3D, b: Dictionary, bone: String, euler: Vector3) -> void:
	if b.has(bone):
		skel.set_bone_pose_rotation(b[bone], Quaternion.from_euler(euler))
