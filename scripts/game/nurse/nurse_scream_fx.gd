class_name NurseScreamFx
extends Node3D
## Onde du cri de l'Infirmière (toutes les machines, effets cubiques,
## GAME_CONCEPT.md §4.19) : deux anneaux de cubes roses lumineux de 5 cm
## (au sol et à hauteur de tête) qui s'élargissent jusqu'au rayon
## d'étourdissement en DURATION s, en rétrécissant ; lisible de loin, il
## montre exactement la portée du cri. Se retire seul.

const DURATION := 0.75
const CUBES := 56
const CUBE := 0.05
const COLOR := Color(1.0, 0.5, 0.6)
## Hauteurs des anneaux (m) et décalage d'angle entre eux.
const HEIGHTS := [0.12, 1.55]

var radius := 10.0
var t := 0.0
var _mm: MultiMesh


func start(at: Vector3, max_radius: float) -> void:
	top_level = true
	global_position = at
	radius = max_radius
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CUBE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COLOR
	box.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = box
	_mm.instance_count = CUBES * HEIGHTS.size()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_place()


func _process(delta: float) -> void:
	t += delta
	if t >= DURATION:
		queue_free()
		return
	_place()


func _place() -> void:
	if _mm == null:
		return
	var k := clampf(t / DURATION, 0.0, 1.0)
	var r := lerpf(0.4, radius, ease(k, 0.45))
	var s := lerpf(1.6, 0.25, k)
	for ring in HEIGHTS.size():
		for i in CUBES:
			var a := TAU * (i + 0.5 * ring) / CUBES
			var p := Vector3(cos(a) * r, float(HEIGHTS[ring]) + sin(a * 5.0 + t * 20.0) * 0.06, sin(a) * r)
			var b := Basis(Vector3.UP, a + t * 6.0).scaled(Vector3.ONE * s)
			_mm.set_instance_transform(ring * CUBES + i, Transform3D(b, p))
