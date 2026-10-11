shader_type canvas_item;
// Étourdissement par le cri de l'Infirmière (NurseDazeFx) : l'image se
// « cubifie » (mosaïque de gros pixels carrés, flou cubique du jeu, GAME_CONCEPT
// §4.19), se dédouble et ondule, bords teintés de rose. `amount` 0..1.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;
uniform float time_s = 0.0;

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float a = clamp(amount, 0.0, 1.0);
	// Taille d'un « cube » à l'écran : 1 pixel (rien) à ~1/100 de la largeur.
	float cell = max(1.0, mix(1.0, res.x / 100.0, a));
	vec2 uv = SCREEN_UV;
	uv.x += sin(uv.y * 9.0 + time_s * 7.0) * 0.008 * a;
	uv.y += sin(uv.x * 7.0 + time_s * 5.3) * 0.005 * a;
	vec2 q = (floor(uv * res / cell) + 0.5) * cell / res;
	vec3 c0 = texture(screen_tex, q).rgb;
	vec2 off = vec2(cos(time_s * 3.1), sin(time_s * 2.3)) * 0.018 * a;
	vec3 c1 = texture(screen_tex, q + off).rgb;
	vec3 c = mix(c0, (c0 + c1) * 0.5, 0.55 * a);
	float v = smoothstep(0.3, 0.85, distance(SCREEN_UV, vec2(0.5)));
	c = mix(c, vec3(0.6, 0.12, 0.2), v * 0.4 * a);
	COLOR = vec4(c, 1.0);
}
