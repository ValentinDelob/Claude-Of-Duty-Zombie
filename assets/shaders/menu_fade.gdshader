shader_type canvas_item;
// Fondu au noir des menus : noir parcouru de neige vidéo et de lignes
// de balayage, plus présentes au milieu de la transition.

uniform float amount : hint_range(0.0, 1.0) = 0.0;

// Hachage sans motif visible (Dave Hoskins).
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 px = floor(FRAGCOORD.xy / 2.0);
	float t = floor(TIME * 24.0);
	float n = hash(px + t * 17.0);
	float line = 0.6 + 0.4 * sin(FRAGCOORD.y * 1.4 + TIME * 40.0);
	// Bandes horizontales de parasites.
	float band = step(0.93, hash(vec2(floor(FRAGCOORD.y / 18.0), t)));
	float peak = 1.0 - abs(amount * 2.0 - 1.0);  // max au milieu
	float snow = n * line * (0.05 + 0.1 * peak + 0.12 * band * peak);
	COLOR = vec4(vec3(snow), amount);
}
