// Expressivité des ennemis cubiques (inclus par zombie_body.gdshaderinc,
// variante VOXEL ; docs/ART_DIRECTION.md « Zombie patient », visage) :
//   - yeux : léger scintillement propre à chaque instance (look_seed),
//     renfort de lueur avec la distance (deux points lumineux encore lisibles
//     au fond d'un couloir sombre, sans éblouir de près), reflet de la lueur
//     au fond des orbites (faces « socket » : alpha SOCKET_ALPHA du sommet,
//     ZombieGlb) ;
//   - zombies « patient » seulement (face_detail = 1, ZombieModel) : variantes
//     déterministes par zombie (look_seed) peintes CUBE PAR CUBE (cellule de
//     repos : jamais de dégradé sous la grille) : éclaboussures de sang sur la
//     blouse, et un visage parmi quatre (tel quel, menton ensanglanté,
//     orbites meurtries, crâne entaillé).
// Fonctions à part, appelées par deux lignes de zombie_body.gdshaderinc.

uniform float face_detail = 0.0;
// Renfort de la lueur des yeux à distance : x (1 + eye_far_boost) au-delà
// de ~22 m, rien sous 5 m.
uniform float eye_far_boost = 1.6;
// Part de la lueur des yeux renvoyée par les faces d'orbite.
uniform float socket_spill = 0.045;
// Sang lisible dans la pénombre (x couleur des faces rouges).
uniform float blood_lift = 0.45;
// Peau des zombies « patient » (face_detail) : saturation et valeur (le
// vert ressort sous la lumière froide au lieu de blanchir).
uniform float skin_saturation = 1.6;
uniform float skin_value = 0.9;
// Graine de l'instance (0..1) : phase du scintillement, variantes de visage.
instance uniform float look_seed = 0.0;

float xp_hash(vec3 c) {
	return fract(sin(dot(c, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Gain de la lueur des yeux : scintillement (lent, irrégulier, rares
// baisses brèves) et renfort à distance `dist` (m, repère de la vue).
float xp_eye_gain(float t, float dist) {
	float s = look_seed * 40.0;
	float f = 0.93 + 0.05 * sin(t * 6.1 + s) + 0.03 * sin(t * 15.7 + s * 2.3);
	f -= 0.35 * smoothstep(0.985, 1.0, sin(t * 0.83 + s * 1.7));
	return f * (1.0 + eye_far_boost * smoothstep(5.0, 22.0, dist));
}

// Émission ajoutée : yeux (alpha <= 0,25) et orbites (0,8..0,95) ; sang
// (faces nettement rouges de `albedo`) un peu éclairé par lui-même : sous la
// lumière bleu-vert des cartes, le rouge sombre virait au noir.
vec3 xp_emission(vec4 col, vec3 albedo, vec3 glow, float t, float dist) {
	float eye_k = step(col.a, 0.25);
	float socket_k = step(0.8, col.a) * step(col.a, 0.95);
	float g = xp_eye_gain(t, dist);
	float red = step(albedo.g * 4.0, albedo.r) * step(0.02, albedo.r) * (1.0 - eye_k);
	return glow * (eye_k * (g - 1.0) + socket_k * socket_spill * g) + albedo * blood_lift * red;
}

// Couleur de face des zombies « patient » : variantes par instance.
// `vm` matière (0 tissu, 1 peau), `p` position de repos (m ; y en haut,
// avant vers +z, gauche du zombie vers +x), `n` normale de repos.
vec3 xp_albedo(vec3 col, float vm, vec3 p, vec3 n, float cell_size) {
	if (face_detail < 0.5) {
		return col;
	}
	vec3 cell = floor(p / cell_size - n * 0.5);
	float h = xp_hash(cell + look_seed * 31.0);
	vec3 dry = vec3(0.075, 0.006, 0.005);
	vec3 fresh = vec3(0.16, 0.008, 0.006);
	if (vm < 0.5) {
		// Blouse : éclaboussures en grappes de cubes (blocs de 3 × 3 × 3).
		vec3 blk = floor(cell / 3.0);
		float b = xp_hash(blk + look_seed * 97.0);
		if (b < 0.03 && p.y > 0.4 && p.y < 1.36 && h > 0.3) {
			return mix(dry, fresh, step(0.75, h));
		}
		return col;
	}
	if (vm > 1.5) {
		return col;
	}
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = max(mix(vec3(l), col, skin_saturation), vec3(0.0)) * skin_value;
	float v = floor(fract(look_seed * 7.13) * 4.0);
	bool front = n.z > 0.5;
	if (v > 0.5 && v < 1.5) {
		// Menton et cou ensanglantés (coulures de la bouche).
		if (p.y > 1.12 && p.y < 1.33 && abs(p.x) < 0.11 && (front || n.y < -0.5) && h > 0.35) {
			return mix(dry, fresh, step(0.6, h));
		}
	} else if (v > 1.5 && v < 2.5) {
		// Orbites meurtries (violacées) autour des yeux.
		if (p.y > 1.44 && p.y < 1.6 && abs(p.x) > 0.02 && abs(p.x) < 0.17 && h > 0.25) {
			return col * vec3(0.55, 0.42, 0.62);
		}
	} else if (v > 2.5) {
		// Crâne entaillé : plaie ouverte sur le dessus (côté droit).
		if (p.y > 1.7 && p.x < 0.02 && p.x > -0.16 && p.z > -0.12 && h > 0.4) {
			return mix(dry, fresh, step(0.7, h));
		}
	}
	return col;
}
