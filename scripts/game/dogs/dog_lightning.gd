class_name DogLightning
extends Node3D
## Apparition d'un chien de l'enfer (effet local, toutes les machines) : une
## boule de foudre bleue descend du plafond en crépitant, puis un éclair frappe
## le sol (flash, étincelles) et le chien apparaît.

const CEILING := 3.0
const BOLT_TIME := 0.35
const BLUE := Color(0.45, 0.7, 1.0)

static var _ball_mat: StandardMaterial3D
static var _bolt_mat: StandardMaterial3D

var duration := DogRules.SPAWN_TIME
## Préchauffage des shaders : ni son ni particules.
var silent := false
var _t := 0.0
var _struck := false
var _ball: MeshInstance3D
var _bolt: Node3D
var _light: OmniLight3D


static func glow_material() -> StandardMaterial3D:
	if _ball_mat == null:
		_ball_mat = StandardMaterial3D.new()
		_ball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ball_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ball_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ball_mat.albedo_color = Color(1.4, 2.1, 3.2, 0.9)
		_ball_mat.albedo_texture = Fx.soft_dot_texture()
		_ball_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return _ball_mat


static func bolt_material() -> StandardMaterial3D:
	if _bolt_mat == null:
		_bolt_mat = StandardMaterial3D.new()
		_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_bolt_mat.albedo_color = Color(2.2, 2.8, 3.6, 1.0)
	return _bolt_mat


func _ready() -> void:
	_ball = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.4)
	_ball.mesh = q
	_ball.material_override = glow_material()
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball)
	_light = OmniLight3D.new()
	_light.light_color = BLUE
	_light.omni_range = 7.0
	_light.light_energy = 1.5
	_light.shadow_enabled = false
	add_child(_light)
	_bolt = _make_bolt()
	_bolt.visible = false
	add_child(_bolt)
	_place(0.0)


## Éclair en zigzag du plafond au sol : quelques segments fins.
func _make_bolt() -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var a := Vector3(0, CEILING, 0)
	var segs := 7
	for i in segs:
		var y := CEILING * (1.0 - float(i + 1) / segs)
		var b := Vector3(rng.randf_range(-0.28, 0.28) if i < segs - 1 else 0.0, y, rng.randf_range(-0.28, 0.28) if i < segs - 1 else 0.0)
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		var seg_len := a.distance_to(b)
		box.size = Vector3(0.07, seg_len, 0.07)
		m.mesh = box
		m.material_override = bolt_material()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mid := (a + b) * 0.5
		var up := (a - b).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		m.transform = Transform3D(Basis(side, up, side.cross(up)), mid)
		root.add_child(m)
		a = b
	return root


func _place(k: float) -> void:
	var y := lerpf(CEILING - 0.2, 0.6, ease(k, 1.8))
	_ball.position = Vector3(0, y, 0)
	var flick := 0.8 + 0.4 * sin(_t * 53.0) * sin(_t * 31.0)
	_ball.scale = Vector3.ONE * (0.55 + 0.45 * k) * flick
	_light.position = _ball.position
	_light.light_energy = (1.0 + 2.0 * k) * flick


func _process(delta: float) -> void:
	_t += delta
	if not _struck:
		_place(clampf(_t / duration, 0.0, 1.0))
		if _t >= duration:
			_strike()
		return
	var k := clampf((_t - duration) / BOLT_TIME, 0.0, 1.0)
	_bolt.visible = fmod(_t, 0.07) < 0.05 and k < 1.0
	_light.light_energy = (1.0 - k) * 8.0
	_ball.scale = Vector3.ONE * (1.0 - k) * 1.6
	if k >= 1.0:
		queue_free()


func _strike() -> void:
	_struck = true
	_bolt.visible = true
	_light.position = Vector3(0, 1.0, 0)
	_light.omni_range = 11.0
	if silent:
		return
	var fx: Fx = Game.instance.fx_root if Game.instance else null
	if fx:
		fx.sparks.burst(global_position + Vector3.UP * 0.1, Vector3.UP, 28, 5.0, 1.2, 0.5, Color(0.55, 0.8, 1.0, 0.95), 1.3)
		fx.dust.burst(global_position + Vector3.UP * 0.1, Vector3.UP, 8, 1.5, 1.0, 1.2, Color(0.2, 0.2, 0.22, 0.5), 2.0)
	Audio.play_3d("dog_bolt", global_position + Vector3.UP * 1.5, 2.0, 0.08, 3)
	Audio.play_3d("dog_spawn", global_position + Vector3.UP * 0.6, 0.0, 0.08, 3)
