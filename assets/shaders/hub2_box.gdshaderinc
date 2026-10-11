// Boîte du hub v2 (Hub2Box, docs/HUB_PLAN.md §9) : fond rgba, liseré par
// côté et coins biseautés (clip-path: polygon des maquettes docs/hub_v2),
// antialiasés. Partagé par hub2_box.gdshader (fond plat) et
// hub2_glass.gdshader (fond flouté, backdrop-filter: blur).
//
// Toutes les longueurs sont en unités locales du nœud (pixels logiques déjà
// passés par Hub2Style.px) ; le rectangle est dessiné de (0, 0) à rect_size.

uniform vec2 rect_size = vec2(100.0, 100.0);
uniform vec4 fill : source_color = vec4(0.039, 0.043, 0.051, 0.62);
uniform vec4 border_color : source_color = vec4(1.0, 1.0, 1.0, 0.08);
// Épaisseur du liseré : gauche, haut, droite, bas.
uniform vec4 border_widths = vec4(1.0);
// Biseau du coin haut-droit et du coin bas-gauche (0 : coin droit).
uniform float chamfer_tr = 0.0;
uniform float chamfer_bl = 0.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

// Couverture (0..1) du polygone biseauté au point p ; `aa` : unités locales
// par pixel de l'écran (bord net d'un pixel).
float hub2_mask(vec2 p, float aa) {
	float m = 1.0;
	if (chamfer_tr > 0.0) {
		// Ligne de (w - c, 0) à (w, c) : dedans si (w - x) + y >= c.
		float d = ((rect_size.x - p.x) + p.y - chamfer_tr) * 0.70710678;
		m = min(m, clamp(d / aa + 0.5, 0.0, 1.0));
	}
	if (chamfer_bl > 0.0) {
		// Ligne de (c, h) à (0, h - c) : dedans si x + (h - y) >= c.
		float d = (p.x + (rect_size.y - p.y) - chamfer_bl) * 0.70710678;
		m = min(m, clamp(d / aa + 0.5, 0.0, 1.0));
	}
	return m;
}

// Part (0..1) du pixel couverte par le liseré.
float hub2_border(vec2 p, float aa) {
	float b = 0.0;
	b = max(b, clamp((border_widths.x - p.x) / aa + 0.5, 0.0, 1.0) * step(0.001, border_widths.x));
	b = max(b, clamp((border_widths.y - p.y) / aa + 0.5, 0.0, 1.0) * step(0.001, border_widths.y));
	b = max(b, clamp((p.x - (rect_size.x - border_widths.z)) / aa + 0.5, 0.0, 1.0) * step(0.001, border_widths.z));
	b = max(b, clamp((p.y - (rect_size.y - border_widths.w)) / aa + 0.5, 0.0, 1.0) * step(0.001, border_widths.w));
	return b;
}

// « over » : couleur `top` (alpha droit) posée sur `bottom`.
vec4 hub2_over(vec4 top, vec4 bottom) {
	float a = top.a + bottom.a * (1.0 - top.a);
	if (a <= 0.0) {
		return vec4(0.0);
	}
	vec3 rgb = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / a;
	return vec4(rgb, a);
}
