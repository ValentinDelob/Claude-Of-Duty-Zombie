shader_type spatial;
// Contour noir en espace écran (ScreenOutline, docs/ART_DIRECTION.md
// « Contour noir en jeu ») : quad plein écran dessiné en tête de la passe
// transparente (render_priority minimale), qui lit la profondeur de la
// pré-passe opaque et noircit les ruptures du relief.
//
// Tout vient de la PROFONDEUR SEULE : la profondeur brute (inversée) de
// Godot est affine en 1/z, donc affine à l'écran sur tout plan ; sa dérivée
// seconde (d_gauche + d_droite - 2 d) est nulle sur un plan, même rasant
// (aucun trait parasite sur les grands sols et murs), et non nulle :
//   - côté PROCHE d'un saut de profondeur (silhouettes, marches vues de
//     dessus) : grande et du signe « convexe » ;
//   - sur une arête de cube (pli de 90°) : ~ 2 x l'angle d'un pixel ou plus,
//     quelle que soit la distance ; convexe (arête saillante) ou concave
//     (coin rentrant : les deux voisins sont plus proches).
// Le tampon des normales (hint_normal_roughness_texture) n'est pas lu : il
// coûtait 0,28 ms de plus (pré-passe avec un second tampon, mesuré par
// perf_costs) pour le même trait sur des formes faites de plans.
// Trait d'UN pixel : seul le côté proche d'un saut est marqué.
// Rien sur le ciel (profondeur 0), ni sur l'arme vue à la première personne
// (profondeur écrasée vers le plan proche par weapon.gdshader : > 0,92).
// Les particules et la brume transparentes ne sont pas dans la profondeur et
// se dessinent par-dessus : elles n'ont pas de trait et voilent celui du décor.
// Le trait est un noir teinté écrit AVANT le tonemap et l'étalonnage : il en
// prend le relèvement bleu-vert des noirs, comme les ombres.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled,
		shadows_disabled, ambient_light_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// Couleur du trait (linéaire) et opacité.
uniform vec3 line_color : source_color = vec3(0.03, 0.035, 0.04);
uniform float strength : hint_range(0.0, 1.0) = 0.95;
// Pli qui trace un trait, en angles de pixel (un pli de 90° en vaut >= 2).
uniform float crease_threshold = 1.0;
// Coin rentrant : rapport minimal entre les deux voisins plus proches (évite
// de marquer le côté LOINTAIN d'une silhouette : trait de 2 px).
uniform float concave_balance = 0.2;
// Part de la pente ajoutée au seuil (surfaces rasantes, voir axis_edge).
uniform float slope_tolerance = 0.2;
// Fondu au loin (m) : au-delà, les marches de cubes font moins de 2 pixels
// et le trait deviendrait du bruit.
uniform float fade_begin = 10.0;
uniform float fade_end = 24.0;
// Profondeur brute au-delà de laquelle un pixel est l'arme FPS.
uniform float weapon_depth = 0.9;
// Résolution de référence du trait d'un pixel (1080p).
uniform float ref_height = 1080.0;

void vertex() {
	// Quad 1x1 étiré sur tout l'écran, quelle que soit la caméra.
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

float raw_depth(ivec2 p, ivec2 size, float dc) {
	float d = texelFetch(depth_tex, clamp(p, ivec2(0), size - 1), 0).r;
	// Arme voisine : traitée comme le pixel lui-même (pas de trait autour).
	return d > weapon_depth ? dc : d;
}

// Pli ou saut le long d'un axe : > 0 si le pixel doit être noirci.
// a, b : voisins moins le pixel (positif = voisin plus proche), relatifs à dc.
float axis_edge(float a, float b, float t0) {
	float lap = -(a + b);
	// Surface rasante : la pente (a - b) / 2 y est forte, et l'interpolation
	// de la profondeur par le GPU n'est pas parfaitement affine (pointillés
	// sur les sols et murs vus de biais) : seuil relevé d'une part de la pente.
	float t = t0 + slope_tolerance * 0.5 * abs(a - b);
	if (lap > t) {
		// Arête saillante ou côté proche d'un saut.
		return 1.0;
	}
	if (-lap > t && min(a, b) > concave_balance * max(a, b)) {
		// Coin rentrant : les deux voisins plus proches, de façon équilibrée.
		return 1.0;
	}
	return 0.0;
}

void fragment() {
	ivec2 size = ivec2(VIEWPORT_SIZE);
	ivec2 p = ivec2(FRAGCOORD.xy);
	// Épaisseur : 1 px jusqu'à 1080p, 2 px en 2160p...
	int s = max(1, int(round(VIEWPORT_SIZE.y / ref_height)));
	float dc = texelFetch(depth_tex, p, 0).r;
	if (dc <= 0.0 || dc > weapon_depth) {
		discard;
	}
	// Distance de vue du pixel (m).
	vec4 vc = INV_PROJECTION_MATRIX * vec4(0.0, 0.0, dc, 1.0);
	float z = -vc.z / vc.w;
	float fade = 1.0 - smoothstep(fade_begin, fade_end, z);
	if (fade <= 0.0) {
		discard;
	}
	float dl = raw_depth(p - ivec2(s, 0), size, dc);
	float dr = raw_depth(p + ivec2(s, 0), size, dc);
	float dd = raw_depth(p - ivec2(0, s), size, dc);
	float du = raw_depth(p + ivec2(0, s), size, dc);
	// Angle couvert par l'écart des voisins (rad) : le pli d'une arête de 90°
	// en donne au moins le double, à toute distance.
	// abs : la projection de Godot sous Vulkan retourne l'axe Y (terme négatif).
	float px_angle = 2.0 * float(s) / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float t = crease_threshold * px_angle;
	float inv = 1.0 / dc;
	float edge = max(axis_edge((dl - dc) * inv, (dr - dc) * inv, t),
			axis_edge((dd - dc) * inv, (du - dc) * inv, t));
	if (edge <= 0.0) {
		discard;
	}
	ALBEDO = line_color;
	ALPHA = strength * fade;
}
