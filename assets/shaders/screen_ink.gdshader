shader_type spatial;
// ENCRAGE du style ILLUSTRÉ (IllustratedStyle, prototype ; docs/ART_DIRECTION.md
// « Style illustré ») : variante de screen_outline.gdshader prise par
// ScreenOutline quand Settings.art_style = ILLUSTRATED. Même principe (quad
// plein écran en tête de la passe transparente, PROFONDEUR SEULE : rien sur
// les aplats des textures pixel art, aucun trait lu dans la couleur), mais :
//   - SILHOUETTES (sauts de profondeur) : trait ÉPAIS (ink_px pixels à
//     1080p, proportionnel à la hauteur de l'image), le plus foncé ;
//   - ARÊTES INTÉRIEURES (plis de 90° des cubes, coins rentrants, creux du
//     relief) : trait plus fin (crease_px) et plus léger (crease_strength) :
//     la différence de forme se lit sans que l'architecture devienne une
//     grille noire ; `inner` = 0 les coupe (préréglage BASSE, voir
//     RenderQuality « ink_inner ») ;
//   - ARME ET MAINS FPS encrées aussi (modèles cubiques) : leur profondeur,
//     écrasée vers le plan proche par weapon.gdshader (0,92 + 0,08 d), est
//     dépliée avant la comparaison ; autour, le décor n'a pas de trait.
// Les plis se mesurent par la dérivée seconde de la profondeur brute (nulle
// sur tout plan, même rasant : aucun pointillé sur les grands sols), voir
// screen_outline.gdshader. Un pixel de trait est classé « silhouette » si un
// voisin est nettement plus loin (saut), « pli » sinon.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled,
		shadows_disabled, ambient_light_disabled, blend_mix;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// Encre (linéaire) : noir teinté, pris avant l'étalonnage comme les ombres.
uniform vec3 line_color : source_color = vec3(0.02, 0.025, 0.03);
// Épaisseurs à 1080p (pixels ; arrondies à la résolution, 1 au minimum).
uniform float ink_px = 3.0;
uniform float crease_px = 1.0;
// Opacité des silhouettes et des arêtes intérieures.
uniform float strength = 1.0;
uniform float crease_strength = 0.7;
// 0 : silhouettes seulement (préréglage BASSE).
uniform float inner = 1.0;
// Pli tracé, en angles de pixel (voir screen_outline.gdshader).
uniform float crease_threshold = 1.0;
uniform float concave_balance = 0.2;
uniform float slope_tolerance = 0.2;
// Saut : le voisin lointain est plus loin que `jump_k` seuils.
uniform float jump_k = 6.0;
// ... et d'au moins cette part de sa distance (les marches de 5 cm du
// relief restent des arêtes fines, pas des silhouettes épaisses).
uniform float jump_min = 0.03;
// Fondus au loin (m) : arêtes intérieures plus tôt que les silhouettes.
uniform float crease_fade_begin = 12.0;
uniform float crease_fade_end = 26.0;
uniform float fade_begin = 22.0;
uniform float fade_end = 40.0;
// Profondeur brute au-delà de laquelle un pixel est l'arme FPS, et
// écrasement de weapon.gdshader (POSITION.z = mix(z, w, 0.92)).
uniform float weapon_depth = 0.9;
uniform float weapon_squash = 0.92;
uniform float ref_height = 1080.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

// Profondeur d'un voisin comparable au pixel central `dc` (déjà déplié si
// arme) : `cw` = le pixel central est l'arme.
float nb_depth(ivec2 q, ivec2 size, float dc, bool cw) {
	float d = texelFetch(depth_tex, clamp(q, ivec2(0), size - 1), 0).r;
	bool w = d > weapon_depth;
	if (cw) {
		// Hors de l'arme : infiniment loin (silhouette de l'arme).
		return w ? (d - weapon_squash) / (1.0 - weapon_squash) : 0.0;
	}
	// Arme voisine d'un pixel du décor : pas de trait côté décor.
	return w ? dc : d;
}

// Pli le long d'un axe (voir screen_outline.gdshader) : 1 si tracé.
float axis_crease(float a, float b, float t0) {
	float lap = -(a + b);
	float t = t0 + slope_tolerance * 0.5 * abs(a - b);
	if (lap > t) {
		return 1.0;
	}
	if (-lap > t && min(a, b) > concave_balance * max(a, b)) {
		return 1.0;
	}
	return 0.0;
}

// Saut le long d'un axe : côté proche, voisin lointain au-delà du seuil.
float axis_jump(float a, float b, float t0) {
	float lap = -(a + b);
	float t = t0 + slope_tolerance * 0.5 * abs(a - b);
	return (lap > t && -min(a, b) > max(jump_k * t0, jump_min)) ? 1.0 : 0.0;
}

void fragment() {
	ivec2 size = ivec2(VIEWPORT_SIZE);
	ivec2 p = ivec2(FRAGCOORD.xy);
	float k = VIEWPORT_SIZE.y / ref_height;
	int s = max(1, int(round(ink_px * k)));
	int sc = max(1, int(round(crease_px * k)));
	float dc = texelFetch(depth_tex, p, 0).r;
	if (dc <= 0.0) {
		discard;
	}
	bool cw = dc > weapon_depth;
	float fade = 1.0;
	float cfade = 1.0;
	if (cw) {
		dc = (dc - weapon_squash) / (1.0 - weapon_squash);
		if (dc <= 0.0) {
			discard;
		}
	} else {
		vec4 vc = INV_PROJECTION_MATRIX * vec4(0.0, 0.0, dc, 1.0);
		float z = -vc.z / vc.w;
		fade = 1.0 - smoothstep(fade_begin, fade_end, z);
		cfade = 1.0 - smoothstep(crease_fade_begin, crease_fade_end, z);
		if (fade <= 0.0) {
			discard;
		}
	}
	float inv = 1.0 / dc;
	float px1 = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	// Silhouettes : voisins à `s` pixels (trait de `s` pixels côté proche).
	float t = crease_threshold * px1 * float(s);
	float jl = nb_depth(p - ivec2(s, 0), size, dc, cw);
	float jr = nb_depth(p + ivec2(s, 0), size, dc, cw);
	float jd = nb_depth(p - ivec2(0, s), size, dc, cw);
	float ju = nb_depth(p + ivec2(0, s), size, dc, cw);
	float jump = max(axis_jump((jl - dc) * inv, (jr - dc) * inv, t),
			axis_jump((jd - dc) * inv, (ju - dc) * inv, t));
	float a = jump * strength * fade;
	if (a < 1.0 && inner > 0.0 && cfade > 0.0) {
		// Arêtes intérieures : voisins à `sc` pixels.
		float tc = crease_threshold * px1 * float(sc);
		float cl = nb_depth(p - ivec2(sc, 0), size, dc, cw);
		float cr = nb_depth(p + ivec2(sc, 0), size, dc, cw);
		float cd = nb_depth(p - ivec2(0, sc), size, dc, cw);
		float cu = nb_depth(p + ivec2(0, sc), size, dc, cw);
		float crease = max(axis_crease((cl - dc) * inv, (cr - dc) * inv, tc),
				axis_crease((cd - dc) * inv, (cu - dc) * inv, tc));
		a = max(a, crease * crease_strength * cfade * inner);
	}
	if (a <= 0.0) {
		discard;
	}
	ALBEDO = line_color;
	ALPHA = a;
}
