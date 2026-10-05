shader_type sky;
// Ciel « Nuit étoilée » des cartes de l'éditeur (pièces sans plafond,
// WorldLook.apply_sky) : dégradé bleu nuit très sombre, étoiles générées
// (grille 3D sur la direction du regard, deux couches), lune voilée. Rien ne
// dépend du temps : la carte de radiance n'est calculée qu'une fois.

// Luminosité du ciel (réglage de la carte, 1 par défaut).
uniform float brightness = 1.0;
// Part des cellules qui portent une étoile (par couche).
uniform float density = 0.035;
uniform vec3 moon_dir = vec3(-0.45, 0.5, -0.74);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Étoiles d'une couche : grille de `scale` cellules par unité de direction.
float stars(vec3 d, float scale, float radius) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	float r = hash13(cell);
	if (r < 1.0 - density) {
		return 0.0;
	}
	vec3 c = 0.2 + 0.6 * hash33(cell);
	float dist = length(fract(p) - c);
	// Éclat : quelques étoiles vives, beaucoup de faibles.
	float mag = pow(max((r - (1.0 - density)) / density, 0.0), 3.0);
	return smoothstep(radius, 0.0, dist) * (0.25 + 1.75 * mag);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 top = vec3(0.004, 0.006, 0.02);
	vec3 horizon = vec3(0.025, 0.03, 0.055);
	vec3 col = mix(horizon, top, smoothstep(0.0, 0.65, h));
	if (h < 0.0) {
		col = mix(horizon, vec3(0.004, 0.004, 0.006), smoothstep(0.0, -0.25, h));
	}
	float s = stars(d, 110.0, 0.32) + stars(d.zxy, 230.0, 0.3) * 0.7;
	// Étoiles éteintes vers l'horizon (brume).
	s *= smoothstep(-0.02, 0.25, h);
	col += vec3(0.85, 0.9, 1.0) * s;
	// Lune voilée : disque pâle et halo.
	float m = dot(d, normalize(moon_dir));
	col += vec3(0.75, 0.8, 0.9) * smoothstep(0.99955, 0.9997, m) * 1.4;
	col += vec3(0.12, 0.14, 0.2) * pow(max(m, 0.0), 240.0) * 0.6;
	COLOR = col * brightness;
}
