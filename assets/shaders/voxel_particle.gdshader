shader_type spatial;
// Particules CUBIQUES (VoxelFx, GAME_CONCEPT.md § 4.19) : sang, étincelles,
// flammes, fumée, éclats, arcs électriques. Aucune texture ni panneau face
// caméra : chaque particule est un cube (ou une touffe de cubes, VoxelFx)
// couleur unie donnée par la rampe de la particule (COLOR).
//
// Cubes TOUJOURS à l'échelle : le côté de chaque cube (taille de la
// particule x côté dans le maillage) est arrondi au multiple de `grid`
// (2,5 cm), au moins un pas, au plus `cube_max` ; une touffe qui grossit
// ÉCARTE ses cubes au lieu de les grossir au-delà de `cube_max`. Avec
// `shrink`, l'alpha de la rampe devient la TAILLE : la particule
// disparaît en rétrécissant, pas à pas de 2,5 cm (moins de transparence,
// plus « cube »), l'opacité étant `opacity`.
//
// Plats (`pattern` > 0, maillage à plat FACE_Y : ronds dans l'eau, brume,
// métal chauffé) : dessin en pixels de `px` m alignés sur la particule.
//
// Ce fichier est la variante « mix, non éclairée » ; VoxelFx en tire les
// autres (« add » : additive ; « lit » : éclairée) en changeant render_mode.
render_mode blend_mix, unshaded, cull_back, shadows_disabled;

// Pas des cubes (m) et côté maximal par axe.
uniform float grid = 0.025;
uniform vec3 cube_max = vec3(0.15);
// Opacité ; 1 : l'alpha de la rampe règle la taille (disparition par
// rétrécissement), 0 : il règle la transparence.
uniform float opacity = 1.0;
uniform float shrink = 1.0;
// Multiplicateur de couleur (> 1 : lueur, flammes, étincelles).
uniform float energy = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
// Arêtes assombries (0 : aucune) : rappel du contour noir sur les cubes.
uniform float edge = 0.0;
// Ombrage peint des faces (dessus clair, côtés, dessous sombre) : 1 = oui.
uniform float shade = 1.0;
// Plats : 0 = cubes, 1 = rond (anneau), 2 = disque, 3 = brume en pixels.
uniform int pattern = 0;
uniform float px = 0.025;

varying vec3 v_cell;
varying vec3 v_flat;
varying vec3 v_half;
varying float v_alpha;
varying float v_shade;
varying float v_seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	float a = clamp(COLOR.a, 0.0, 1.0);
	float k = shrink > 0.5 ? a : 1.0;
	v_alpha = opacity * (shrink > 0.5 ? 1.0 : a);
	if (pattern == 0) {
		// Centre du cube dans le maillage (UV, UV2.x) et son côté (UV2.y).
		vec3 c = vec3(UV, UV2.x);
		float cell = UV2.y;
		vec3 local = VERTEX - c;
		v_cell = local / cell;
		vec3 w = max(s * cell, vec3(1e-5));
		vec3 base = min(max(round(w / grid), vec3(1.0)) * grid, max(cube_max, vec3(grid)));
		vec3 t = round(base * k / grid) * grid;
		VERTEX = c + local * t / w;
	} else {
		v_flat = VERTEX * s;
		v_half = abs(VERTEX) * s;
		v_seed = hash(floor(MODEL_MATRIX[3].xz * 7.0) + floor(MODEL_MATRIX[3].y * 13.0));
	}
	vec3 wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_shade = shade > 0.5 ? 0.8 + 0.2 * wn.y : 1.0;
}

void fragment() {
	vec3 col = COLOR.rgb * tint.rgb * energy;
	float alpha = v_alpha * tint.a;
	if (pattern == 0) {
		if (edge > 0.0) {
			// Sur une face, une coordonnée vaut 1 ; près d'une arête, une
			// deuxième s'en approche.
			vec3 q = abs(v_cell) * 2.0;
			float mid = q.x + q.y + q.z - max(q.x, max(q.y, q.z)) - min(q.x, min(q.y, q.z));
			col *= mix(1.0, 1.0 - edge, step(0.8, mid));
		}
		col *= v_shade;
	} else {
		// Pixels de `px` m, comptés depuis le centre de la particule.
		vec2 pc = floor(v_flat.xz / px) + 0.5;
		float r = max(v_half.x, v_half.z) / px;
		float d = length(pc);
		if (pattern == 1) {
			if (abs(d - max(r - 0.5, 0.5)) > 0.55) {
				discard;
			}
		} else if (pattern == 2) {
			if (d > max(r, 0.71)) {
				discard;
			}
		} else {
			float f = 1.0 - d / max(r, 0.5);
			float h = hash(pc + v_seed * 97.0);
			float m = f * 0.9 + h * 0.5 - 0.35;
			if (m <= 0.0) {
				discard;
			}
			alpha *= clamp(floor(m * 4.0 + 1.0) / 4.0, 0.25, 1.0);
		}
	}
	ALBEDO = col;
	ALPHA = alpha;
}
