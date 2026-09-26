class_name ParticlePool
extends MultiMeshInstance3D
## Particules CPU très légères : un seul MultiMesh (1 draw call) pour toutes les
## particules d'un type (étincelles, sang, poussière...). Mises à jour en
## GDScript, sans allocation par image.

## Densité des gerbes (réglée par RenderQuality : 0.5 en qualité LOW).
static var density := 1.0

var capacity := 256
var gravity := 9.0
var drag := 1.5
var base_size := 0.05
var grow := 0.0            # variation de taille par seconde
var _pos: PackedVector3Array
var _vel: PackedVector3Array
var _life: PackedFloat32Array
var _max_life: PackedFloat32Array
var _size: PackedFloat32Array
var _col: PackedColorArray
var _count := 0


func setup(cap: int, mat: Material, size := 0.05) -> ParticlePool:
	capacity = cap
	base_size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = cap
	mm.visible_instance_count = 0
	multimesh = mm
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pos.resize(cap)
	_vel.resize(cap)
	_life.resize(cap)
	_max_life.resize(cap)
	_size.resize(cap)
	_col.resize(cap)
	# Les particules sont en coordonnées monde.
	top_level = true
	global_transform = Transform3D.IDENTITY
	custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 200, 1000))
	return self


func emit(pos: Vector3, vel: Vector3, life: float, color: Color, size_mult := 1.0) -> void:
	var i := _count
	if i >= capacity:
		# Pool plein : on remplace la particule la plus ancienne (index 0).
		i = randi() % capacity
	else:
		_count += 1
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = life
	_max_life[i] = life
	_size[i] = base_size * size_mult
	_col[i] = color


## Gerbe de particules autour d'une normale.
func burst(pos: Vector3, normal: Vector3, n: int, speed: float, spread: float, life: float, color: Color, size_mult := 1.0) -> void:
	if density < 1.0:
		# Moins de particules, un peu plus grosses : même masse visuelle.
		n = maxi(1, roundi(n * density))
		size_mult *= 1.0 + (1.0 - density) * 0.4
	for k in n:
		var dir := (normal + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
		emit(pos, dir * speed * randf_range(0.5, 1.2), life * randf_range(0.6, 1.2), color, size_mult * randf_range(0.6, 1.4))


func _process(delta: float) -> void:
	if _count == 0:
		return
	var i := 0
	var damp := exp(-drag * delta)
	while i < _count:
		_life[i] -= delta
		if _life[i] <= 0.0:
			_count -= 1
			_pos[i] = _pos[_count]
			_vel[i] = _vel[_count]
			_life[i] = _life[_count]
			_max_life[i] = _max_life[_count]
			_size[i] = _size[_count]
			_col[i] = _col[_count]
			continue
		_vel[i] = _vel[i] * damp + Vector3.DOWN * gravity * delta
		_pos[i] += _vel[i] * delta
		if _pos[i].y < 0.01:
			_pos[i].y = 0.01
			_vel[i] = Vector3(_vel[i].x * 0.3, 0.0, _vel[i].z * 0.3)
		i += 1
	var mm := multimesh
	mm.visible_instance_count = _count
	for k in _count:
		var t := _life[k] / _max_life[k]
		var s := _size[k] * (1.0 + grow * (1.0 - t))
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(s, s, s)), _pos[k]))
		var c := _col[k]
		c.a *= clampf(t * 2.0, 0.0, 1.0)
		mm.set_instance_color(k, c)
