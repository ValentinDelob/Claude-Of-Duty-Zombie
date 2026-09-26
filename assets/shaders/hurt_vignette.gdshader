shader_type canvas_item;
// Sang à l'écran quand le joueur est blessé (BO1) : éclaboussures sombres
// aux bords, coulures qui descendent, halo rouge qui pulse avec le cœur, et
// bref voile rouge à chaque coup reçu. Intensité pilotée par la santé.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;
// Voile rouge d'un coup reçu (1 -> 0 en ~0,6 s).
uniform float flash : hint_range(0.0, 1.0) = 0.0;

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
	// Halo irrégulier.
	float edge = smoothstep(0.35, 0.9, d + n * 0.25 - intensity * 0.25);
	// Éclaboussures : taches franches aux bords.
	float splat = noise(UV * vec2(11.0, 7.0) + 3.1) * 0.65 + noise(UV * 27.0 + 1.7) * 0.35;
	float blobs = smoothstep(0.56, 0.62, splat) * smoothstep(0.52, 0.8, d + n * 0.12);
	// Coulures verticales depuis le haut de l'écran.
	float col_id = floor(UV.x * 42.0);
	float len = hash(vec2(col_id, 7.0)) * 0.35 * intensity;
	float drip = step(UV.y, len) * step(0.8, hash(vec2(col_id, 3.0))) * smoothstep(0.5, 0.2, abs(fract(UV.x * 42.0) - 0.5))
			* smoothstep(0.25, 0.45, abs(UV.x - 0.5));
	float a = edge * intensity * (0.85 + pulse * 0.15);
	a = max(a, (blobs * 0.8 + drip * 0.7) * smoothstep(0.25, 0.7, intensity));
	a = max(a, flash * 0.28 * (0.6 + 0.4 * d));
	vec3 col = mix(vec3(0.22, 0.0, 0.0), vec3(0.55, 0.02, 0.02), n);
	COLOR = vec4(col, clamp(a, 0.0, 0.92));
}
