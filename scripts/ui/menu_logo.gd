class_name MenuLogo
extends Control
## Logo « CLAUDE OF DUTY ZOMBIE » : emblème original (crâne casqué dans un
## écusson brisé) et texte au pochoir, dessinés une seule fois dans une
## SubViewport, puis usés / ensanglantés par le shader menu_logo. Tremblement
## et parasites occasionnels.

const VIEW := Vector2i(1000, 470)
const DISPLAY_SCALE := 0.62

var _rect: TextureRect
var _mat: ShaderMaterial
var _vp: SubViewport
var _t := 0.0
var _next_glitch := 3.0
var _glitch_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1968
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(VIEW) * DISPLAY_SCALE
	_vp = SubViewport.new()
	_vp.size = VIEW
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var art := LogoArt.new()
	art.size = Vector2(VIEW)
	_vp.add_child(art)
	add_child(_vp)
	_rect = TextureRect.new()
	_rect.texture = _vp.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://assets/shaders/menu_logo.gdshader")
	_rect.material = _mat
	add_child(_rect)
	# Le dessin est statique : quelques images pour être sûr que les polices
	# sont prêtes, puis plus aucun rendu de la SubViewport.
	get_tree().create_timer(0.3).timeout.connect(func():
		if is_instance_valid(_vp):
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED)


func _process(delta: float) -> void:
	_t += delta
	_next_glitch -= delta
	var g := 0.0
	if _next_glitch <= 0.0:
		_glitch_left = _rng.randf_range(0.08, 0.28)
		_next_glitch = _rng.randf_range(3.5, 9.0)
	if _glitch_left > 0.0:
		_glitch_left -= delta
		g = _rng.randf_range(0.4, 1.0)
	_mat.set_shader_parameter("glitch", g)
	# Tremblement : quasi immobile, secousse brève pendant les parasites.
	var shake := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * (3.0 * g)
	_rect.position = shake + Vector2(sin(_t * 0.37), cos(_t * 0.29)) * 0.6


## Dessin du logo (dans la SubViewport, à la résolution VIEW).
class LogoArt extends Control:
	const BONE := Color(0.87, 0.83, 0.73)
	const BONE_DIM := Color(0.66, 0.62, 0.54)
	const RED := Color(0.62, 0.05, 0.035)
	const OLIVE := Color(0.24, 0.26, 0.18)
	const OLIVE_HI := Color(0.36, 0.38, 0.27)
	const HOLE := Color(0.035, 0.02, 0.02)
	const EMBER := Color(1.0, 0.42, 0.1)

	func _draw() -> void:
		_emblem(Vector2(172, 232))
		var stencil := UiStyle.font("stencil")
		var impact := UiStyle.font("impact")
		_tracked(impact, Vector2(352, 266), "OF  DUTY", 64, 12.0, BONE)
		# Filet sous « CALL OF ».
		draw_rect(Rect2(352, 118, 250, 5), BONE_DIM.darkened(0.3))
		draw_rect(Rect2(610, 118, 36, 5), BONE_DIM.darkened(0.3))
		_tracked(stencil, Vector2(338, 196), "CLAUDE", 150, 4.0, BONE)
		_tracked(stencil, Vector2(338, 404), "ZOMBIE", 150, 4.0, RED)

	func _tracked(font: Font, pos: Vector2, text: String, size: int, spacing: float, col: Color) -> void:
		var x := pos.x
		for ch in text:
			draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing

	## Crâne coiffé d'un casque, dans un écusson circulaire brisé.
	func _emblem(c: Vector2) -> void:
		# Écusson : anneau épais interrompu, graduations.
		var segs := [[-1.35, 0.55], [0.75, 1.9], [2.15, 3.5], [3.75, 4.75]]
		for sg in segs:
			draw_arc(c, 158.0, sg[0], sg[1], 40, RED, 12.0)
		for i in 36:
			var ang := TAU * i / 36.0
			var d := Vector2(cos(ang), sin(ang))
			draw_line(c + d * 140.0, c + d * (133.0 if i % 3 else 124.0), BONE_DIM, 3.0)
		draw_arc(c, 172.0, 0.0, TAU, 64, Color(RED, 0.6), 3.0)
		# Crâne : calotte + mâchoire.
		var skull := PackedVector2Array()
		var r := 92.0
		for i in 25:
			var ang := lerpf(PI * 0.94, PI * 2.06, i / 24.0)
			skull.append(c + Vector2(cos(ang), sin(ang)) * r + Vector2(0, 8))
		for p in [Vector2(84, 52), Vector2(62, 84), Vector2(54, 128), Vector2(-54, 128), Vector2(-62, 84), Vector2(-84, 52)]:
			skull.append(c + p)
		draw_colored_polygon(skull, BONE)
		# Pommettes (ombres).
		draw_colored_polygon(_ellipse(c + Vector2(-62, 62), Vector2(16, 10), 0.4), BONE_DIM)
		draw_colored_polygon(_ellipse(c + Vector2(62, 62), Vector2(16, 10), -0.4), BONE_DIM)
		# Orbites, lueur orangée au fond.
		for side in [-1.0, 1.0]:
			var e := c + Vector2(38.0 * side, 28)
			draw_colored_polygon(_ellipse(e, Vector2(29, 24), 0.25 * side), HOLE)
			draw_circle(e + Vector2(3 * side, 4), 7.0, EMBER)
			draw_circle(e + Vector2(3 * side, 4), 3.5, Color(1, 0.85, 0.6))
		# Cavité nasale.
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, 52), c + Vector2(-14, 82), c + Vector2(0, 78), c + Vector2(14, 82)]), HOLE)
		# Dents.
		draw_rect(Rect2(c + Vector2(-46, 94), Vector2(92, 28)), HOLE)
		for i in 7:
			var x := -44.0 + i * 13.0
			var h := 24.0 if i != 2 else 14.0  # une dent cassée
			draw_rect(Rect2(c + Vector2(x, 95), Vector2(10, h)), BONE)
		draw_line(c + Vector2(-46, 108), c + Vector2(46, 108), HOLE, 2.0)
		# Fêlure du crâne.
		draw_polyline(PackedVector2Array([c + Vector2(-8, -30), c + Vector2(-20, -8), c + Vector2(-12, 4), c + Vector2(-28, 16)]), HOLE, 3.0)
		# Casque : dôme + bord, reflet, impact de balle.
		var helm := PackedVector2Array()
		for i in 29:
			var ang := lerpf(PI, TAU, i / 28.0)
			helm.append(c + Vector2(cos(ang) * 122.0, sin(ang) * 104.0) + Vector2(0, -6))
		draw_colored_polygon(helm, OLIVE)
		var brim := PackedVector2Array([c + Vector2(-140, -12), c + Vector2(140, -12), c + Vector2(128, 6), c + Vector2(-128, 6)])
		draw_colored_polygon(brim, OLIVE.darkened(0.25))
		draw_arc(c + Vector2(0, -6), 100.0, PI * 1.18, PI * 1.45, 16, OLIVE_HI, 7.0)
		draw_circle(c + Vector2(48, -58), 9.0, OLIVE.darkened(0.5))
		draw_circle(c + Vector2(48, -58), 5.0, HOLE)
		for k in 5:
			var ang := TAU * k / 5.0 + 0.3
			draw_line(c + Vector2(48, -58), c + Vector2(48, -58) + Vector2(cos(ang), sin(ang)) * 17.0, OLIVE.darkened(0.45), 2.0)
		# Mentonnière.
		draw_line(c + Vector2(-112, 0), c + Vector2(-58, 110), OLIVE.darkened(0.3), 6.0)
		draw_line(c + Vector2(112, 0), c + Vector2(58, 110), OLIVE.darkened(0.3), 6.0)
		# Marquage au pochoir sur le casque.
		draw_string(UiStyle.font("stencil"), c + Vector2(-26, -34), "K7", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0.62, 0.6, 0.5, 0.8))
		# Sang sur le crâne et le casque (détecté comme « rouge » : coulures).
		draw_colored_polygon(_ellipse(c + Vector2(-30, -2), Vector2(26, 7), -0.2), RED)
		draw_colored_polygon(_ellipse(c + Vector2(20, 126), Vector2(30, 5), 0.0), RED)

	func _ellipse(center: Vector2, radii: Vector2, rot: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 20:
			var ang := TAU * i / 20.0
			pts.append(center + Vector2(cos(ang) * radii.x, sin(ang) * radii.y).rotated(rot))
		return pts
