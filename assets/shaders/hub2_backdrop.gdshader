shader_type canvas_item;
render_mode unshaded;
// Étalonnage du fond 3D sous le hub v2 (Hub2Screen) : l'image du fond des
// maquettes (docs/hub_v2/img/menu_backdrop.png) est le fond du menu titre
// APRÈS son post-traitement (menu_post.gdshader). Le hub v2 le reproduit SOUS
// l'interface (jamais par-dessus : l'interface reste nette, sans bombé ni
// aberration) : noirs écrasés, teinte froide, lignes de balayage, grain,
// vignette ovale profonde. Mêmes formules et valeurs que menu_post.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float grain_amount = 0.075;
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
	vec3 col = texture(screen_tex, uv).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, 0.86);
	col = max(col - 0.006, 0.0) * 1.02;
	col += vec3(-0.004, 0.0, 0.01) * (1.0 - smoothstep(0.0, 0.3, lum));
	col *= 0.955 + 0.045 * sin(FRAGCOORD.y * 2.0944);
	vec2 seed = FRAGCOORD.xy + vec2(fract(t * 1.37), fract(t * 2.71)) * 1733.0;
	float g = hash12(seed) + hash12(seed + 91.7) - 1.0;
	col += g * grain_amount * (1.0 - lum * 0.7);
	float v = 1.0 - smoothstep(0.28, 0.92, length(c * vec2(1.15, 1.0)));
	col *= mix(1.0 - vignette_strength, 1.0, v);
	COLOR = vec4(max(col, 0.0), 1.0) * vec4(1.0, 1.0, 1.0, COLOR.a);
}
