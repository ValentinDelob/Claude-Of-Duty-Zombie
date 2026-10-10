class_name ScreenOutline
extends MeshInstance3D
## Contour noir en jeu (style des planches de référence : trait net autour des
## pièces et des marches de cubes). Passe plein écran de post-traitement :
## un quad dessiné en tête de la passe transparente, shader
## screen_outline.gdshader (sauts de profondeur et de normale, voir le shader).
##
## Créé par WorldLook.setup_environment (partie seulement : pas dans l'aperçu
## de l'éditeur de cartes, dont les poignées et gizmos prendraient un trait).
## Option : Settings.outline (OPTIONS > VIDÉO > CONTOUR, activé par défaut).
## Actif dans les trois préréglages (coût mesuré par perf_costs, voir
## docs/ARCHITECTURE.md) ; désactivé d'office hors Forward+ (le shader suppose la
## profondeur inversée 0..1 de Vulkan ; Mobile et Compatibility non vérifiés).
##
## Ce qui n'a PAS de trait : le HUD et l'écran de lunette (CanvasLayer, au-
## dessus de la 3D), l'arme et les mains en vue FPS (profondeur écrasée vers
## le plan proche : le trait dessinerait chaque facette de leurs formes
## arrondies), le ciel, la brume et les particules transparentes.

const SHADER := preload("res://assets/shaders/screen_outline.gdshader")
## Seuils et fondu (réglables ici, valeurs choisies sur les captures de
## outline_look : BUNKER K-7 avec zombies).
## Pli tracé, en angles de pixel (une arête de cube de 90° en vaut >= 2).
const CREASE_THRESHOLD := 1.0
## Coin rentrant : équilibre minimal des deux voisins plus proches.
const CONCAVE_BALANCE := 0.2
## Part de la pente ajoutée au seuil sur les surfaces rasantes.
const SLOPE_TOLERANCE := 0.2
const FADE_BEGIN := 10.0
const FADE_END := 24.0
const STRENGTH := 0.95

var material: ShaderMaterial


## Le moteur fournit-il la profondeur de la pré-passe (Forward+, vérifié) ?
static func supported() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## Contour affiché : option des réglages et moteur compatible.
static func wanted() -> bool:
	return Settings.outline and supported()


func _ready() -> void:
	var quad := QuadMesh.new()
	mesh = quad
	material = ShaderMaterial.new()
	material.shader = SHADER
	# Premier des transparents : particules, brume et effets passent par-dessus.
	material.render_priority = Material.RENDER_PRIORITY_MIN
	material.set_shader_parameter("crease_threshold", CREASE_THRESHOLD)
	material.set_shader_parameter("concave_balance", CONCAVE_BALANCE)
	material.set_shader_parameter("slope_tolerance", SLOPE_TOLERANCE)
	material.set_shader_parameter("fade_begin", FADE_BEGIN)
	material.set_shader_parameter("fade_end", FADE_END)
	material.set_shader_parameter("strength", STRENGTH)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Le quad est placé par le vertex shader : jamais écarté par le frustum.
	extra_cull_margin = 16384.0
	ignore_occlusion_culling = true
	Settings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	visible = wanted()
