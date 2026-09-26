shader_type canvas_item;
render_mode unshaded, blend_mul;
// Variante LOW du post-traitement (FilmPost) : aucune lecture de l'écran.
// Le mode multiplicatif ne fait qu'assombrir : grain en fines taches sombres
// et vignettage, pour un coût quasi nul.

uniform float grain = 0.05;
uniform float vignette = 0.32;
uniform float grain_px = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	vec2 px = floor(FRAGCOORD.xy / grain_px);
	float fr = floor(TIME * 24.0);
	float n = hash12(px + fr * vec2(37.13, 17.71));
	float k = 1.0 - grain * 2.2 * n;
	float v = smoothstep(0.3, 0.95, length(c * vec2(1.25, 1.0)));
	k *= 1.0 - vignette * v * v;
	COLOR = vec4(vec3(clamp(k, 0.0, 1.0)), 1.0);
}
