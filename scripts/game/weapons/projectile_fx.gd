class_name ProjectileFx
extends Node3D
## Projectile visible (grenade de China Lake, roquette de LAW, balle explosive
## du M1911 amélioré). Purement visuel et local : il file de la bouche du
## canon au point d'impact à `speed` m/s puis disparaît. Les dégâts et
## l'explosion sont décidés par le serveur au même instant (Combat, délai
## WeaponDB.projectile_delay).

var _from: Vector3
var _to: Vector3
var _dur := 0.1
var _t := 0.0
var _fx: Fx
var _kind := "grenade"
var _smoke_acc := 0.0

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}


## Lance un projectile visuel sous `fx` (effets de la partie).
static func launch(fx: Fx, from: Vector3, to: Vector3, speed: float, kind: String, pap := false) -> ProjectileFx:
	if fx == null or not is_instance_valid(fx):
		return null
	var p := ProjectileFx.new()
	p._from = from
	p._to = to
	p._dur = maxf(from.distance_to(to) / maxf(speed, 1.0), 0.02)
	p._fx = fx
	p._kind = kind
	p._build(pap)
	fx.add_child(p)
	p.global_position = from
	if from.distance_to(to) > 0.01:
		p.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	return p


func _build(pap: bool) -> void:
	var body := MeshInstance3D.new()
	body.mesh = _mesh(_kind)
	body.material_override = _mat("body_pap" if pap else "body")
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _kind == "rocket":
		body.rotation.x = PI * 0.5
	add_child(body)
	# Flamme de propulsion : un cube lumineux (style cubique, VoxelFx).
	var flame := MeshInstance3D.new()
	var q := BoxMesh.new()
	q.size = Vector3.ONE * (0.125 if _kind == "rocket" else 0.05)
	flame.mesh = q
	flame.material_override = _mat("flame_pap" if pap else "flame")
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position = Vector3(0, 0, 0.12 if _kind == "rocket" else 0.03)
	add_child(flame)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / _dur, 0.0, 1.0)
	global_position = _from.lerp(_to, k)
	# Traînée de fumée (roquette surtout).
	_smoke_acc += delta
	var every := 0.02 if _kind == "rocket" else 0.05
	if _smoke_acc >= every and is_instance_valid(_fx):
		_smoke_acc = 0.0
		_fx.dust.burst(global_position, Vector3.UP, 1, 0.3, 0.6, 0.8, Color(0.5, 0.48, 0.45, 0.45), 0.8)
	if k >= 1.0:
		queue_free()


static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	# Pavés en cubes de 2,5 cm : roquette 2 x 10 cubes, grenade 2 x 2 x 3.
	var b := BoxMesh.new()
	b.size = Vector3(0.05, 0.25, 0.05) if kind == "rocket" else Vector3(0.05, 0.05, 0.075)
	var m: Mesh = b
	_meshes[kind] = m
	return m


static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"body":
			m.albedo_color = Color(0.22, 0.24, 0.16)
		"body_pap":
			m.albedo_color = Color(0.35, 0.1, 0.4)
			m.emission_enabled = true
			m.emission = Color(0.5, 0.15, 0.7)
		"flame", "flame_pap":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(1.0, 0.6, 0.2) if key == "flame" else Color(0.8, 0.4, 1.0)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mats[key] = m
	return m
