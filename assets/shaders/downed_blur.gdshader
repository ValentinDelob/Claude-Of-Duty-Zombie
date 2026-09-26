shader_type canvas_item;
render_mode unshaded;
// Vision « à terre » façon BO1 : image floue qui respire (mipmaps de l'écran),
// délavée, assombrie, bords rouge sang qui pulsent avec le cœur. Affiché
// uniquement pendant l'état À TERRE (DownedOverlay) : aucun coût sinon.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;
// 0 -> 1 à l'approche de la mort (le flou et le rouge s'intensifient).
uniform float bleed = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c * vec2(1.3, 1.0));
	// Flou plus fort sur les bords, respiration lente.
	float lod = amount * (1.6 + 1.4 * smoothstep(0.1, 0.7, r) + 0.6 * sin(TIME * 1.3) + bleed * 1.2);
	vec3 col = textureLod(screen_tex, uv, lod).rgb;
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(lum), amount * 0.65);
	col *= 1.0 - amount * 0.25;
	// Bords rouges pulsés.
	float edge = smoothstep(0.35, 0.95, r + pulse * 0.05);
	col = mix(col, vec3(0.42, 0.0, 0.0), clamp(edge * amount * (0.75 + bleed * 0.25), 0.0, 0.9));
	col = mix(col, col * vec3(1.15, 0.7, 0.68), amount * 0.5);
	COLOR = vec4(col, 1.0);
}
