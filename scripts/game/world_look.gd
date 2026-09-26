class_name WorldLook
extends RefCounted
## Direction artistique du monde : matériaux, environnement, éclairage.
## Centralisé ici pour pouvoir ajuster l'ambiance (et les réglages de qualité)
## sans toucher au gameplay.

const SURFACE := preload("res://assets/shaders/surface.gdshader")

## clé -> [motif, couleur A, couleur B, échelle, crasse, rugosité, métal]
const SURFACES := {
	"floor": [0, Color(0.24, 0.23, 0.21), Color(0.1, 0.1, 0.1), 0.8, 0.6, 0.95, 0.0],
	"wall": [4, Color(0.36, 0.35, 0.32), Color(0.2, 0.25, 0.21), 1.0, 0.5, 0.9, 0.0],
	"ceiling": [6, Color(0.12, 0.12, 0.12), Color(0.05, 0.05, 0.05), 1.0, 0.4, 1.0, 0.0],
	"concrete": [0, Color(0.25, 0.24, 0.22), Color(0.1, 0.1, 0.1), 0.8, 0.65, 0.95, 0.0],
	"concrete_dark": [0, Color(0.17, 0.17, 0.16), Color(0.08, 0.08, 0.08), 0.8, 0.7, 0.95, 0.0],
	"tiles": [1, Color(0.5, 0.5, 0.46), Color(0.12, 0.11, 0.1), 1.0, 0.7, 0.5, 0.0],
	"wood": [2, Color(0.24, 0.15, 0.09), Color(0.05, 0.03, 0.02), 1.0, 0.6, 0.85, 0.0],
	"metal": [3, Color(0.2, 0.21, 0.22), Color(0.24, 0.15, 0.09), 1.0, 0.5, 0.6, 0.5],
	"stone": [5, Color(0.12, 0.1, 0.1), Color(0.05, 0.04, 0.04), 1.0, 0.3, 0.9, 0.0],
	"wall_green": [4, Color(0.38, 0.36, 0.31), Color(0.16, 0.24, 0.19), 1.0, 0.6, 0.9, 0.0],
	"wall_cell": [4, Color(0.3, 0.3, 0.29), Color(0.13, 0.16, 0.2), 1.0, 0.75, 0.9, 0.0],
	"wall_lab": [1, Color(0.52, 0.53, 0.5), Color(0.18, 0.18, 0.17), 1.0, 0.65, 0.45, 0.0],
	"wall_rust": [3, Color(0.21, 0.21, 0.22), Color(0.27, 0.15, 0.08), 1.0, 0.55, 0.65, 0.5],
	"wall_concrete": [0, Color(0.27, 0.26, 0.24), Color(0.1, 0.1, 0.1), 0.7, 0.6, 0.95, 0.0],
	"wall_ritual": [5, Color(0.14, 0.11, 0.1), Color(0.05, 0.04, 0.04), 1.0, 0.3, 0.9, 0.0],
	# Décor
	"crate": [2, Color(0.3, 0.2, 0.11), Color(0.08, 0.05, 0.03), 1.3, 0.4, 0.9, 0.0],
	"barrel": [3, Color(0.28, 0.08, 0.05), Color(0.3, 0.14, 0.06), 2.0, 0.4, 0.6, 0.4],
	"steel": [3, Color(0.25, 0.26, 0.27), Color(0.28, 0.16, 0.09), 2.0, 0.3, 0.5, 0.6],
	"fabric": [0, Color(0.36, 0.33, 0.27), Color(0.1, 0.1, 0.1), 3.0, 0.9, 1.0, 0.0],
	"door": [3, Color(0.22, 0.23, 0.22), Color(0.3, 0.15, 0.07), 1.4, 0.5, 0.55, 0.6],
	# Théâtre (KINO)
	"carpet_red": [7, Color(0.3, 0.035, 0.04), Color(0.42, 0.28, 0.08), 1.0, 0.55, 1.0, 0.0],
	"marble": [1, Color(0.46, 0.41, 0.34), Color(0.09, 0.07, 0.05), 0.55, 0.55, 0.4, 0.0],
	"stage_wood": [2, Color(0.27, 0.16, 0.08), Color(0.04, 0.025, 0.015), 1.4, 0.35, 0.7, 0.0],
	"parquet": [2, Color(0.25, 0.15, 0.08), Color(0.05, 0.03, 0.02), 2.0, 0.5, 0.6, 0.0],
	"wall_theater": [8, Color(0.3, 0.05, 0.06), Color(0.2, 0.1, 0.05), 1.0, 0.45, 0.85, 0.0],
	"wall_lobby": [8, Color(0.34, 0.25, 0.14), Color(0.19, 0.09, 0.04), 1.0, 0.45, 0.85, 0.0],
	"wall_foyer": [8, Color(0.14, 0.19, 0.13), Color(0.2, 0.1, 0.05), 1.0, 0.5, 0.85, 0.0],
	"wall_loges": [4, Color(0.42, 0.37, 0.3), Color(0.33, 0.2, 0.19), 1.0, 0.6, 0.9, 0.0],
	"brick": [9, Color(0.3, 0.13, 0.08), Color(0.19, 0.18, 0.16), 1.0, 0.6, 0.9, 0.0],
	"cobble": [11, Color(0.2, 0.2, 0.21), Color(0.07, 0.06, 0.05), 1.0, 0.55, 0.9, 0.0],
	"velvet": [10, Color(0.46, 0.035, 0.045), Color(0.1, 0.01, 0.015), 1.0, 0.25, 0.8, 0.0],
	"brass": [0, Color(0.5, 0.36, 0.13), Color(0.2, 0.14, 0.05), 2.0, 0.3, 0.35, 0.85],
	"ceiling_theater": [6, Color(0.16, 0.1, 0.07), Color(0.05, 0.03, 0.02), 0.7, 0.5, 1.0, 0.0],
	"dark_wood": [2, Color(0.13, 0.07, 0.035), Color(0.03, 0.02, 0.01), 2.5, 0.3, 0.6, 0.0],
	"night_sky": [0, Color(0.018, 0.02, 0.032), Color(0.0, 0.0, 0.01), 0.15, 0.0, 1.0, 0.0],
}

## Environnement normal (voir aussi apply_dog_round_look).
const BASE_FOG_COLOR := Color(0.085, 0.09, 0.105)
const BASE_FOG_DENSITY := 0.016
const BASE_AMBIENT_ENERGY := 0.5
const BASE_SATURATION := 0.78

static var _cache: Dictionary = {}


static func surface(key: String) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var s: Array = SURFACES.get(key, SURFACES.wall)
	var m := ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter("pattern", s[0])
	m.set_shader_parameter("color_a", s[1])
	m.set_shader_parameter("color_b", s[2])
	m.set_shader_parameter("scale", s[3])
	m.set_shader_parameter("grime", s[4])
	m.set_shader_parameter("roughness_base", s[5])
	m.set_shader_parameter("metallic_base", s[6])
	if key == "stone" or key == "wall_ritual":
		m.set_shader_parameter("glow", 1.6)
	_cache[key] = m
	return m


static func map_materials() -> Dictionary:
	var d := {}
	for key in SURFACES:
		d[key] = surface(key)
	return d


## `look` : surcharges propres à la carte (MapDef.look).
static func setup_environment(parent: Node3D, look := {}) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.38, 0.44)
	env.ambient_light_energy = BASE_AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.3
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = BASE_FOG_COLOR
	env.fog_density = BASE_FOG_DENSITY
	env.adjustment_enabled = true
	env.adjustment_saturation = BASE_SATURATION
	env.adjustment_contrast = 1.08
	env.ambient_light_color = look.get("ambient_color", env.ambient_light_color)
	env.ambient_light_energy = look.get("ambient_energy", env.ambient_light_energy)
	env.fog_light_color = look.get("fog_color", env.fog_light_color)
	env.fog_density = look.get("fog_density", env.fog_density)
	env.adjustment_saturation = look.get("saturation", env.adjustment_saturation)
	env.tonemap_exposure = look.get("exposure", env.tonemap_exposure)
	# Valeurs « normales » de la carte, reprises après une manche de chiens.
	env.set_meta("base_look", {"fog_color": env.fog_light_color, "fog_density": env.fog_density,
			"ambient_energy": env.ambient_light_energy, "saturation": env.adjustment_saturation})
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)
	# Préréglages de qualité : appliqués maintenant puis à chaque changement
	# d'options (glow, SSAO, ombres des lampes, résolution 3D...).
	var rq := RenderQuality.new()
	rq.name = "RenderQuality"
	rq.environment = env
	parent.add_child(rq)


## Ambiance d'une manche de chiens (k = 0 : normale, 1 : pleine) : brouillard
## plus épais et plus sombre, lumière ambiante baissée, couleurs délavées.
const DOG_FOG_COLOR := Color(0.07, 0.035, 0.03)
const DOG_FOG_DENSITY := 0.05
const DOG_AMBIENT_ENERGY := 0.3
const DOG_SATURATION := 0.62


static func apply_dog_round_look(env: Environment, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	# Point de départ : l'ambiance propre à la carte (MapDef.look), sinon la base.
	var base: Dictionary = env.get_meta("base_look", {})
	env.fog_light_color = (base.get("fog_color", BASE_FOG_COLOR) as Color).lerp(DOG_FOG_COLOR, k)
	env.fog_density = lerpf(base.get("fog_density", BASE_FOG_DENSITY), DOG_FOG_DENSITY, k)
	env.ambient_light_energy = lerpf(base.get("ambient_energy", BASE_AMBIENT_ENERGY), DOG_AMBIENT_ENERGY, k)
	env.adjustment_saturation = lerpf(base.get("saturation", BASE_SATURATION), DOG_SATURATION, k)
