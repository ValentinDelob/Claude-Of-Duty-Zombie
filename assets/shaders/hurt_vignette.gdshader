shader_type canvas_item;
// Vignette de sang quand le joueur est blessé : bords rouges irréguliers qui
// pulsent, intensité pilotée par la santé.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.6;
	float d = length(uv);
	float n = noise(UV * 7.0) * 0.6 + noise(UV * 19.0) * 0.4;
	float edge = smoothstep(0.35, 0.9, d + n * 0.25 - intensity * 0.25);
	float a = edge * intensity * (0.85 + pulse * 0.15);
	vec3 col = mix(vec3(0.25, 0.0, 0.0), vec3(0.55, 0.02, 0.02), n);
	COLOR = vec4(col, clamp(a, 0.0, 0.92));
}
