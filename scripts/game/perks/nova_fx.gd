class_name NovaFx
extends RefCounted
## Effet du plongeon explosif de NOVA FLOP : onde de choc violette au sol,
## gerbes d'étincelles tout autour, éclair, son et secousse de la caméra.
## Le plongeur est au centre : rien d'opaque ni d'additif devant ses yeux.

const COLOR := Color(0.62, 0.2, 1.0)
const SHAKE_RANGE := 9.0


static func play(game: Game, pos: Vector3) -> void:
	var fx: Fx = game.fx_root
	for i in 8:
		var a := TAU * i / 8.0
		var o := pos + Vector3(cos(a), 0.0, sin(a)) * 1.3 + Vector3.UP * 0.15
		fx.sparks.burst(o, (Vector3(cos(a), 0.0, sin(a)) + Vector3.UP * 0.8).normalized(), 6, 6.0, 0.6, 0.6, Color(0.75, 0.35, 1.0, 0.95), 1.4)
	fx.dust.burst(pos + Vector3.UP * 0.1, Vector3.UP, 14, 3.0, 1.0, 1.4, Color(0.3, 0.16, 0.42, 0.5), 2.5)
	fx.explosion_light(pos + Vector3.UP * 0.6, COLOR)
	_ring(fx, pos)
	_ring(fx, pos, 0.22, 0.6)
	Audio.play_3d("nova_blast", pos, 5.0, 0.05, 4)
	var lp := game.local_player
	if lp and lp.global_position.distance_to(pos) < SHAKE_RANGE:
		var a := lerpf(0.05, 0.01, lp.global_position.distance_to(pos) / SHAKE_RANGE)
		lp._flinch += Vector2(randf_range(-a, a), a)


static func _mat(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, alpha)
	return m


## Anneau qui s'élargit au ras du sol jusqu'au rayon de l'explosion.
static func _ring(fx: Fx, pos: Vector3, time := 0.35, alpha := 0.95) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.42
	t.outer_radius = 0.5
	t.rings = 32
	t.ring_segments = 6
	mi.mesh = t
	var m := _mat(alpha)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.08
	mi.scale = Vector3(0.4, 0.3, 0.4)
	var s := PerkDB.NOVA_RADIUS * 2.0
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(s, 0.6, s), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, time + 0.1).set_delay(time * 0.3)
	tw.chain().tween_callback(mi.queue_free)


