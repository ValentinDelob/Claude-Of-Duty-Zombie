class_name NurseDazeFx
extends CanvasLayer
## Effet d'écran du joueur local étourdi par le cri de l'Infirmière
## (Player.daze) : image en gros cubes qui se dédouble et ondule
## (nurse_daze.gdshader), sous le HUD. Invisible quand `amount` est nul (aucun
## coût). Le son n'est jamais baissé : l'acouphène s'ajoute (nurse_ring).

const SHADER := preload("res://assets/shaders/nurse_daze.gdshader")

var amount := 0.0:
	set(v):
		amount = clampf(v, 0.0, 1.0)
		if _rect:
			_rect.visible = amount > 0.005
			_mat.set_shader_parameter("amount", amount)
var _rect: ColorRect
var _mat: ShaderMaterial
var _t := 0.0


func _ready() -> void:
	# Au-dessus du grain de film (FilmPost, 5), sous le HUD (10).
	layer = 6
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = "Daze"
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	if _rect.visible:
		_t += delta
		_mat.set_shader_parameter("time_s", _t)
