shader_type sky;
// Ciel des cartes de l'éditeur (pièces sans plafond, WorldLook.apply_sky),
// dans le style cubique du jeu (GAME_CONCEPT.md §4.19) : pas de dégradé lisse
// ni de disque rond, mais des paliers et des pixels carrés.
//   mode 0 « jour » : couvert gris-bleu en bandes de couleur, nuages en cubes
//     (grille carrée sur un plafond de nuages, vue en perspective comme des
//     blocs ; dessous plus sombre, bords ombrés) ;
//   mode 1 « nuit » : bleu nuit en bandes, étoiles en pixels carrés (grille
//     des six faces d'un cube autour du joueur : chaque étoile est une case
//     carrée, trois éclats), lune en pixel art (disque de cases, cratères).
// Rien ne dépend du temps : la carte de radiance n'est calculée qu'une fois.

uniform int mode = 0;
// Luminosité du ciel (réglage de la carte, 1 par défaut).
uniform float brightness = 1.0;
// Jour : couleurs en sRGB (WorldLook.DAY_*), couverture nuageuse, cubes par
// unité de hauteur du plafond de nuages.
uniform vec3 day_top = vec3(0.3, 0.38, 0.5);
uniform vec3 day_horizon = vec3(0.58, 0.6, 0.62);
uniform float cloud_cover = 0.4;
// Cubes de nuage par unité de hauteur du plafond de nuages.
uniform float cloud_scale = 18.0;
// Nuit : part des cases qui portent une étoile, cases par face du cube.
uniform float star_density = 0.012;
uniform float star_cells = 260.0;
uniform vec3 moon_dir = vec3(-0.45, 0.5, -0.74);
// Lune : rayon en cases, taille d'une case (radians).
uniform float moon_radius = 4.6;
uniform float moon_cell = 0.015;
// Nombre de bandes du dégradé (horizon -> zénith).
uniform float bands = 7.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Bruit de valeur lissé sur une grille (forme des amas de nuages).
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Une case du plafond de nuages porte-t-elle un cube ? (bruit lu au centre
// de la case : la forme suit la grille, bords en marches).
float cloud_at(vec2 cell) {
	vec2 q = (cell + 0.5) * 0.075;
	float n = vnoise(q) * 0.66 + vnoise(q * 2.1 + 17.0) * 0.3 + hash12(cell) * 0.04;
	return step(1.0 - cloud_cover, n);
}

// Dégradé en paliers entre l'horizon et le zénith.
vec3 banded(vec3 horizon, vec3 top, float h) {
	float k = floor(clamp(h, 0.0, 0.999) * bands) / (bands - 1.0);
	return mix(horizon, top, pow(clamp(k, 0.0, 1.0), 0.8));
}

vec3 day_sky(vec3 d) {
	float h = d.y;
	if (h < 0.0) {
		// Sol lointain : deux paliers sombres.
		vec3 ground = h > -0.1 ? day_horizon * 0.55 : vec3(0.1);
		return pow(max(ground, 0.0), vec3(2.2));
	}
	vec3 col = banded(day_horizon, day_top, h * 1.6);
	if (h > 0.035) {
		// Plafond de nuages à hauteur 1 : coordonnées du plan, en cases.
		vec2 p = d.xz / h * cloud_scale;
		vec2 cell = floor(p);
		float c = cloud_at(cell);
		if (c > 0.5) {
			// Dessous du cube : gris clair, plus sombre au cœur de l'amas ;
			// bords (case voisine vide) ombrés, comme une arête de cube.
			float edge = (1.0 - cloud_at(cell + vec2(1.0, 0.0))) + (1.0 - cloud_at(cell + vec2(0.0, 1.0)))
					+ (1.0 - cloud_at(cell - vec2(1.0, 0.0))) + (1.0 - cloud_at(cell - vec2(0.0, 1.0)));
			float tone = 0.74 - 0.05 * floor(hash12(cell + 7.0) * 3.0);
			vec3 cc = vec3(tone, tone, tone * 1.02) * mix(0.82, 1.0, min(edge, 1.0));
			// Liseré : la dernière rangée de pixels de la case est plus sombre.
			vec2 f = fract(p);
			cc *= (f.x < 0.08 || f.y < 0.08) ? 0.9 : 1.0;
			// Les cubes lointains (près de l'horizon) se fondent dans le ciel
			// par paliers.
			float far = clamp(floor(h * 16.0 - 1.0) / 3.0, 0.0, 1.0);
			col = mix(col, cc * mix(day_horizon, vec3(1.0), 0.5), far);
		}
	}
	// Couleurs du jour données en sRGB (comme WorldLook.DAY_*) : en linéaire.
	return pow(max(col, 0.0), vec3(2.2));
}

// Coordonnées sur la face du cube que vise `d` : (face, uv dans [-1, 1]).
vec3 cube_face(vec3 d, out vec2 uv) {
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z) {
		uv = d.zy / a.x;
		return vec3(sign(d.x), 0.0, 0.0);
	} else if (a.y >= a.z) {
		uv = d.xz / a.y;
		return vec3(0.0, sign(d.y), 0.0);
	}
	uv = d.xy / a.z;
	return vec3(0.0, 0.0, sign(d.z));
}

vec3 night_sky(vec3 d) {
	float h = d.y;
	vec3 top = vec3(0.004, 0.007, 0.022);
	vec3 horizon = vec3(0.028, 0.034, 0.062);
	vec3 col = banded(horizon, top, h * 1.5);
	if (h < 0.0) {
		col = mix(horizon * 0.6, vec3(0.004, 0.004, 0.006), step(0.1, -h));
	}
	// Étoiles : une case carrée de la grille des faces du cube.
	vec2 uv;
	vec3 face = cube_face(d, uv);
	vec2 cell = floor((uv * 0.5 + 0.5) * star_cells);
	float r = hash13(vec3(cell, dot(face, vec3(1.0, 3.0, 5.0))));
	if (r > 1.0 - star_density) {
		// Trois éclats seulement (paliers), quelques étoiles teintées.
		float mag = floor((r - (1.0 - star_density)) / star_density * 3.0);
		float tint = hash13(vec3(cell + 3.0, face.x + face.z));
		vec3 sc = tint < 0.15 ? vec3(1.0, 0.86, 0.7) : (tint > 0.88 ? vec3(0.75, 0.85, 1.0) : vec3(0.9, 0.93, 1.0));
		float s = (0.35 + 0.55 * mag) * step(0.04, h);
		col += sc * s;
	}
	// Lune en pixel art : disque de cases carrées dans le plan tangent.
	vec3 m = normalize(moon_dir);
	vec3 tx = normalize(cross(vec3(0.0, 1.0, 0.0), m));
	vec3 ty = cross(m, tx);
	float facing = dot(d, m);
	if (facing > 0.9) {
		vec2 lp = vec2(dot(d, tx), dot(d, ty)) / facing / moon_cell;
		vec2 mc = floor(lp) + 0.5;
		if (length(mc) < moon_radius) {
			float crater = step(0.74, hash12(floor(lp) + 11.0)) * 0.32;
			// Ombre du côté opposé à la lumière (croissant en paliers).
			float lit = step(-moon_radius * 0.35, mc.x + mc.y * 0.3);
			col = vec3(0.42, 0.45, 0.5) * (1.0 - crater) * mix(0.25, 1.0, lit);
		} else if (length(mc) < moon_radius + 1.5) {
			// Halo : une couronne de cases à peine plus claire.
			col += vec3(0.05, 0.06, 0.09);
		}
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = mode == 0 ? day_sky(d) : night_sky(d);
	COLOR = col * brightness;
}
