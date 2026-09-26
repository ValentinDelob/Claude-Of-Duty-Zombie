shader_type canvas_item;
render_mode unshaded;
// Post-traitement plein écran de la partie (MEDIUM / HIGH), sous le HUD :
// aberration chromatique radiale (bords seulement), grain de film animé à
// 24 images/s (surtout dans les tons moyens, comme la pellicule), léger
// vignettage. Voir FilmPost (réglages) et docs/ART_DIRECTION.md.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float grain = 0.05;
uniform float vignette = 0.32;
uniform float aberration = 0.0035;
// Taille d'un grain en pixels d'écran (1 px à 720p, 1,5 px à 1080p).
uniform float grain_px = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec3 col;
	if (aberration > 0.0) {
		vec2 d = c * r2 * aberration * 4.0;
		col.r = texture(screen_tex, uv + d).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - d).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	// Grain : bruit triangulaire (-1..1), nouvelle graine à chaque image
	// de pellicule. Pondéré vers les tons moyens, présent dans les noirs.
	vec2 px = floor(FRAGCOORD.xy / grain_px);
	float fr = floor(TIME * 24.0);
	float n = hash12(px + fr * vec2(37.13, 17.71)) + hash12(px * 1.37 + fr * vec2(11.3, 53.9)) - 1.0;
	float w = 0.35 + 2.6 * lum * (1.0 - lum);
	col += n * grain * w;
	// Vignettage ovale et doux.
	float v = smoothstep(0.3, 0.95, length(c * vec2(1.25, 1.0)));
	col *= 1.0 - vignette * v * v;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
