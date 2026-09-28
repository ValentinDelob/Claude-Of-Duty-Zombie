class_name TheaterLook
extends RefCounted
## Ambiance et matériaux procéduraux du théâtre (KINO) : étalonnage,
## poussière en suspension, écran de cinéma (amorce de film qui défile quand
## le courant est rétabli), faisceau poussiéreux du projecteur et rais de
## lumière. Aucune texture externe.

## Étalonnage de KINO (surcharge de WorldLook.GRADE_DEFAULT) : dans BO1, le
## théâtre est plus chaud que les bunkers (velours rouge, dorures, ampoules
## jaunes) mais ses recoins restent froids, bleu-vert ; noirs un peu moins
## denses pour garder la salle lisible.
const GRADE := {
	"shadow_tint": Color(0.84, 0.98, 1.08),
	"highlight_tint": Color(1.06, 1.0, 0.9),
	"toe": 1.22,
	"desat": 0.16,
}
## Poussière en suspension du théâtre : brume volumétrique légèrement ocre.
const DUST_ALBEDO := Color(0.84, 0.8, 0.74)
const DUST_DENSITY := 0.005

const SCREEN_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float playing = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	// Toile tachée, légèrement jaunie.
	float stain = hash(floor(uv * vec2(40.0, 18.0))) * 0.08;
	vec3 cloth = vec3(0.5, 0.48, 0.44) * (0.92 - stain);
	vec3 film = vec3(0.0);
	if (playing > 0.5) {
		float t = floor(TIME * 18.0);
		float flick = 0.8 + 0.2 * hash(vec2(t, 3.0));
		vec2 p = (uv - 0.5) * vec2(2.35, 1.0);
		float r = length(p);
		// Amorce de film : cercles, réticule et balayage « radar », chiffre
		// qui change chaque seconde (luminosité du disque).
		float ang = atan(p.y, p.x);
		float sweep = fract(TIME) * 6.2831 - 3.1416;
		float swept = step(mod(ang - sweep + 6.2831, 6.2831), 6.2831 * fract(TIME));
		float rings = smoothstep(0.012, 0.0, abs(r - 0.42)) + smoothstep(0.012, 0.0, abs(r - 0.36));
		float cross = smoothstep(0.006, 0.0, abs(p.x)) + smoothstep(0.006, 0.0, abs(p.y));
		float disc = step(r, 0.36);
		float lum = 0.55 + disc * swept * 0.25 + rings * 0.4 + cross * 0.3;
		// Grain, rayures verticales, poussières, vignettage.
		lum += (hash(uv * vec2(420.0, 240.0) + t) - 0.5) * 0.18;
		float scratch = step(0.992, hash(vec2(floor(uv.x * 260.0), floor(TIME * 6.0))));
		lum -= scratch * 0.35;
		lum -= step(0.9985, hash(floor(uv * vec2(90.0, 50.0)) + t)) * 0.6;
		lum *= 1.0 - smoothstep(0.35, 0.75, length((uv - 0.5) * vec2(1.3, 1.6)));
		film = vec3(1.0, 0.94, 0.82) * clamp(lum, 0.0, 1.0) * flick;
	}
	ALBEDO = cloth * (1.0 - playing * 0.6);
	ROUGHNESS = 0.95;
	EMISSION = film * 0.75;
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.93, 0.78, 1.0);
uniform float strength = 0.032;
uniform float flicker = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// Bords adoucis (vue rasante), poussière qui dérive dans le faisceau,
	// scintillement de l'obturateur.
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	float dust = 0.6 + 0.8 * noise(UV * vec2(18.0, 6.0) + vec2(TIME * 0.05, TIME * 0.12));
	float shutter = mix(1.0, 0.85 + 0.15 * hash(vec2(floor(TIME * 24.0), 1.0)), flicker);
	float fade = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.85, UV.y);
	ALBEDO = tint.rgb * strength * edge * dust * shutter * fade;
}
"""

static var _screen: ShaderMaterial
static var _beam: ShaderMaterial
static var _shaft: ShaderMaterial


static func screen_material() -> ShaderMaterial:
	if _screen == null:
		var sh := Shader.new()
		sh.code = SCREEN_SHADER
		_screen = ShaderMaterial.new()
		_screen.shader = sh
	return _screen


static func beam_material() -> ShaderMaterial:
	if _beam == null:
		var sh := Shader.new()
		sh.code = BEAM_SHADER
		_beam = ShaderMaterial.new()
		_beam.shader = sh
	return _beam


## Rai de lumière froide tombant d'un trou du plafond (sans obturateur).
static func shaft_material() -> ShaderMaterial:
	if _shaft == null:
		_shaft = beam_material().duplicate()
		_shaft.set_shader_parameter("tint", Color(0.82, 0.9, 1.0))
		_shaft.set_shader_parameter("strength", 0.006)
		_shaft.set_shader_parameter("flicker", 0.0)
	return _shaft

