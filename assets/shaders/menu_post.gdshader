shader_type canvas_item;
render_mode unshaded;
// Post-traitement plein écran du menu (au-dessus de la 3D et de l'interface) :
// léger bombé d'écran, aberration chromatique (renforcée pendant les
// parasites), bandes décalées, lignes de balayage, bande de roulement,
// grain animé, vignette, étalonnage froid et contrasté.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float grain_amount = 0.075;
uniform float aberration = 0.0014;
uniform float vignette_strength = 0.85;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	vec2 c = uv - 0.5;
	// Parasites : bandes horizontales décalées, par saccades.
	if (glitch > 0.001) {
		float frame = floor(t * 24.0);
		float row = floor(uv.y * 48.0);
		float r = hash12(vec2(row, frame));
		float band = step(1.0 - 0.22 * glitch, r);
		uv.x += band * (hash12(vec2(frame, row + 7.0)) - 0.5) * 0.08 * glitch;
		// Petit saut vertical de l'image.
		uv.y += (hash12(vec2(frame, 3.0)) - 0.5) * 0.006 * glitch;
	}
	// Écran très légèrement bombé.
	uv += c * dot(c, c) * 0.03;
	// Aberration chromatique radiale.
	vec2 dir = c * (aberration + glitch * 0.012);
	vec3 col;
	col.r = texture(screen_tex, uv + dir).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir).b;
	// Étalonnage : noirs écrasés, teinte froide dans les ombres.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, 0.86);
	col = max(col - 0.006, 0.0) * 1.02;
	col += vec3(-0.004, 0.0, 0.01) * (1.0 - smoothstep(0.0, 0.3, lum));
	// Lignes de balayage (période 3 px) et bande de roulement lente.
	col *= 0.955 + 0.045 * sin(FRAGCOORD.y * 2.0944);
	float roll = fract(uv.y * 0.7 + t * 0.035);
	col *= 1.0 + 0.04 * smoothstep(0.0, 0.05, roll) * (1.0 - smoothstep(0.05, 0.16, roll));
	// Grain animé, plus présent dans les ombres.
	vec2 seed = FRAGCOORD.xy + vec2(fract(t * 1.37), fract(t * 2.71)) * 1733.0;
	float g = hash12(seed) + hash12(seed + 91.7) - 1.0;
	col += g * grain_amount * (1.0 - lum * 0.7);
	// Parasites : neige et lignes claires.
	if (glitch > 0.001) {
		float frame = floor(t * 24.0);
		float line = step(0.985, hash12(vec2(floor(FRAGCOORD.y / 2.0), frame)));
		col += line * glitch * 0.25 * hash12(FRAGCOORD.xy + frame);
	}
	// Vignette ovale, profonde.
	float v = 1.0 - smoothstep(0.28, 0.92, length(c * vec2(1.15, 1.0)));
	col *= mix(1.0 - vignette_strength, 1.0, v);
	// Scintillement global très léger.
	col *= 1.0 - 0.03 * hash12(vec2(floor(t * 14.0), 5.0));
	COLOR = vec4(max(col, 0.0), 1.0);
}
