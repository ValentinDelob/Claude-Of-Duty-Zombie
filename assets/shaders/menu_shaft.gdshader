shader_type spatial;
// Faux rayon de lumière (cône additif) : bords adoucis selon l'angle de vue,
// dégradé vertical, poussière qui ondule. Aucun brouillard volumétrique.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.45, 0.55, 0.8, 1.0);
uniform float intensity = 0.25;
uniform float flicker = 1.0;

varying vec3 lpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 4.0);
	// UV.y : 0 en haut du cône, 1 en bas. S'éteint avant le sol.
	float fall = (1.0 - smoothstep(0.05, 0.85, UV.y)) * smoothstep(0.0, 0.08, UV.y);
	float dust = 0.65 + 0.35 * noise(vec2(atan(lpos.x, lpos.z) * 3.0, lpos.y * 2.0 - TIME * 0.12));
	ALBEDO = tint.rgb * intensity * edge * fall * dust * flicker;
}
