shader_type canvas_item;
// Titres d'écran au pochoir : peinture écaillée (trous, piqûres) et
// irrégulière. Motif lié au texte (coordonnées locales) : il suit les
// animations au lieu de glisser dessus.

varying vec2 lp;

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
	lp = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	float n = noise(lp * vec2(0.07, 0.12)) * 0.65 + noise(lp * 0.4) * 0.35;
	float wear = smoothstep(0.64, 0.7, n);
	float pits = step(0.84, noise(lp * 0.8 + 11.0));
	c.a *= 1.0 - max(wear, pits * 0.75);
	c.rgb *= 0.7 + 0.45 * noise(lp * 0.05 + 3.0);
	COLOR = c;
}
