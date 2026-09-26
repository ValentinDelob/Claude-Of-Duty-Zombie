class_name FilmPost
extends CanvasLayer
## Post-traitement plein écran de la partie, façon BO1 : grain de film animé,
## léger vignettage, aberration chromatique sur les bords.
##
## Au-dessus de la 3D, SOUS le HUD (Hud.layer = 10) : l'interface reste nette.
## Créé par WorldLook.setup_environment. Deux variantes :
##   - MEDIUM / HIGH : film_post.gdshader (lit l'écran : vrai grain +/-,
##     aberration) ;
##   - LOW : film_post_low.gdshader (multiplicatif, aucune lecture d'écran).
## Intensité du grain : Settings.film_grain (OPTIONS > VIDÉO > GRAIN DE FILM).

const LAYER := 5
## Amplitude du grain pour Settings.film_grain = 1.
const GRAIN_MAX := 0.085
const VIGNETTE := 0.32
const SHADER := preload("res://assets/shaders/film_post.gdshader")
const SHADER_LOW := preload("res://assets/shaders/film_post_low.gdshader")

var rect: ColorRect
var material: ShaderMaterial
var _quality: Dictionary = {}


func _ready() -> void:
	layer = LAYER
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	rect.material = material
	add_child(rect)
	add_to_group(RenderQuality.GROUP)
	Settings.changed.connect(_refresh)
	get_viewport().size_changed.connect(_refresh)
	apply_quality(RenderQuality.current())


func apply_quality(q: Dictionary) -> void:
	_quality = q
	material.shader = SHADER if q.get("post_screen", true) else SHADER_LOW
	_refresh()


## Amplitude effective du grain (0 = désactivé dans les options).
static func grain_amount() -> float:
	return clampf(Settings.film_grain, 0.0, 1.0) * GRAIN_MAX


func _refresh() -> void:
	if material == null:
		return
	var g := grain_amount()
	material.set_shader_parameter("grain", g)
	material.set_shader_parameter("vignette", VIGNETTE)
	material.set_shader_parameter("grain_px", maxf(1.0, get_viewport().get_visible_rect().size.y / 720.0))
	if material.shader == SHADER:
		material.set_shader_parameter("aberration", float(_quality.get("aberration", 0.0)))
