class_name TheaterLook
extends RefCounted
## Matériaux procéduraux du théâtre (KINO) : affiches de films d'époque,
## écran de cinéma (amorce de film qui défile quand le courant est rétabli),
## faisceau poussiéreux du projecteur. Aucune texture externe.

const POSTERS := 4

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
	float shutter = 0.85 + 0.15 * hash(vec2(floor(TIME * 24.0), 1.0));
	float fade = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.85, UV.y);
	ALBEDO = tint.rgb * strength * edge * dust * shutter * fade;
}
"""

static var _posters: Dictionary = {}
static var _screen: ShaderMaterial
static var _beam: ShaderMaterial


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


static func poster_material(variant: int) -> StandardMaterial3D:
	variant = posmod(variant, POSTERS)
	if _posters.has(variant):
		return _posters[variant]
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(poster_image(variant))
	m.roughness = 0.75
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_posters[variant] = m
	return m


## Affiche d'époque (128 x 192) : fond, motif central, bandeaux de « titre »,
## puis vieillissement (plis, taches, coin déchiré, jaunissement).
static func poster_image(variant: int) -> Image:
	var w := 128
	var h := 192
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + variant * 31
	var noise := FastNoiseLite.new()
	noise.seed = 90 + variant
	noise.frequency = 0.05
	var palettes := [
		[Color(0.45, 0.04, 0.03), Color(0.08, 0.01, 0.01), Color(0.92, 0.86, 0.7)],   # épouvante rouge
		[Color(0.85, 0.62, 0.12), Color(0.12, 0.08, 0.03), Color(0.1, 0.07, 0.04)],   # rayons dorés
		[Color(0.1, 0.24, 0.26), Color(0.02, 0.05, 0.07), Color(0.9, 0.9, 0.78)],     # nuit et lune
		[Color(0.07, 0.06, 0.05), Color(0.02, 0.02, 0.02), Color(0.8, 0.62, 0.25)],   # art déco
	]
	var pal: Array = palettes[variant]
	var bg_a: Color = pal[0]
	var bg_b: Color = pal[1]
	var ink: Color = pal[2]
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var c := bg_b.lerp(bg_a, clampf(1.0 - absf(v - 0.42) * 1.8, 0.0, 1.0))
			var p := Vector2(u - 0.5, (v - 0.42) * 1.5)
			match variant:
				0:
					# Crâne : ovale clair, orbites et mâchoire.
					var skull := Vector2(p.x / 0.28, (p.y + 0.02) / 0.32).length() < 1.0
					var eye := (Vector2(p.x + 0.1, p.y + 0.04).length() < 0.07) or (Vector2(p.x - 0.1, p.y + 0.04).length() < 0.07)
					var jaw := absf(p.x) < 0.14 and p.y > 0.2 and p.y < 0.32 and fmod(u * 40.0, 2.0) < 1.4
					if (skull and not eye) or jaw:
						c = ink * (0.8 + 0.2 * noise.get_noise_2d(x * 3.0, y * 3.0))
				1:
					# Rayons de soleil et silhouette.
					var a := atan2(p.y, p.x)
					if fmod(a * 6.0 / PI + 12.0, 2.0) < 1.0:
						c = c.lerp(bg_b, 0.55)
					var body := absf(p.x) < 0.06 + p.y * 0.18 and p.y > -0.12 and p.y < 0.45
					var head := Vector2(p.x, p.y + 0.2).length() < 0.07
					if body or head:
						c = ink
				2:
					# Lune et arbres morts.
					if Vector2(p.x - 0.12, p.y + 0.18).length() < 0.16:
						c = ink * 0.95
					var trunk := absf(p.x + 0.22 + sin(p.y * 9.0) * 0.02) < 0.025 and p.y > -0.1
					var ground := p.y > 0.34 + sin(p.x * 11.0) * 0.03
					var branch := absf(p.y + 0.02 - (p.x + 0.22) * 0.9) < 0.012 and p.x > -0.22 and p.x < 0.05
					if trunk or ground or branch:
						c = Color(0.01, 0.01, 0.015)
				3:
					# Losange et cadres art déco.
					var d := absf(p.x) + absf(p.y)
					if absf(d - 0.3) < 0.015 or absf(d - 0.22) < 0.008 or (d < 0.12):
						c = ink
					if absf(u - 0.5) > 0.4 and fmod(v * 30.0, 2.0) < 0.3:
						c = ink * 0.7
			# Bandeaux de titre et de générique.
			if (v > 0.8 and v < 0.87 and absf(u - 0.5) < 0.38) or (v > 0.9 and v < 0.92 and absf(u - 0.5) < 0.3) or (v > 0.05 and v < 0.09 and absf(u - 0.5) < 0.3):
				if fmod(u * 26.0 + (v * 3.0), 1.0) < 0.78:
					c = ink
			# Cadre clair.
			if u < 0.04 or u > 0.96 or v < 0.03 or v > 0.97:
				c = Color(0.78, 0.72, 0.6)
			img.set_pixel(x, y, c)
	# Vieillissement.
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			c = c.lerp(Color(0.55, 0.45, 0.28), 0.18 + n * 0.12)
			if x == w / 2 or y == h / 3 or y == 2 * h / 3:
				c = c.darkened(0.25)
			if n > 0.78:
				c = c.darkened(0.35)
			# Coin déchiré.
			if x + (h - y) < 26 + int(noise.get_noise_2d(x * 4.0, 0) * 8.0):
				c = Color(0.1, 0.08, 0.06)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return img
