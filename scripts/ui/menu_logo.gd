class_name MenuLogo
extends Control
## Logo « CLAUDE OF DUTY ZOMBIE » : texte au pochoir seul, dessiné une seule
## fois dans une SubViewport, puis usés / ensanglantés par le shader menu_logo. Tremblement
## et parasites occasionnels.

const VIEW := Vector2i(680, 470)
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

	func _draw() -> void:
		var stencil := UiStyle.font("stencil")
		var impact := UiStyle.font("impact")
		_tracked(impact, Vector2(34, 266), "OF  DUTY", 64, 12.0, BONE)
		# Filet sous « CLAUDE ».
		draw_rect(Rect2(34, 118, 250, 5), BONE_DIM.darkened(0.3))
		draw_rect(Rect2(292, 118, 36, 5), BONE_DIM.darkened(0.3))
		_tracked(stencil, Vector2(20, 196), "CLAUDE", 150, 4.0, BONE)
		_tracked(stencil, Vector2(20, 404), "ZOMBIE", 150, 4.0, RED)

	func _tracked(font: Font, pos: Vector2, text: String, font_size: int, spacing: float, col: Color) -> void:
		var x := pos.x
		for ch in text:
			draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
