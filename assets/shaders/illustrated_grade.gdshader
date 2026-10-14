shader_type canvas_item;
// Style ILLUSTRÉ (IllustratedPost, docs/ART_DIRECTION.md « Style illustré ») :
// étalonnage de l'image finale (après tonemap, valeurs sRGB) d'après la
// planche cible docs/art/gemini_target.webp. Les tables ci-dessous sont
// MESURÉES (tests/test_illustrated_style.gd les recalcule depuis l'image) :
//   - COURBE DE VALEURS : centiles de luminance d'une vue du jeu en CLASSIQUE
//     (BUNKER K-7, labo avec zombies) -> mêmes centiles sur la cible : ombres
//     relevées, hautes lumières ramenées (la cible est une image « peinte »,
//     sans noir bouché ni blanc brûlé) ;
//   - CARTE DE COULEURS : couleur moyenne de la cible par tranche de
//     luminance (ombres bleu-vert, tons moyens vert d'eau, lumières chaudes) ;
//     l'image prend cette couleur pour `map_k`, en gardant ses propres
//     teintes pour le reste (sang rouge, lueurs vertes, flaques orangées) ;
//   - PALIERS DOUX : valeurs ramenées en partie à `bands` tons (aplats) ;
//   - NETTETÉ LOCALE (clarity) et léger grain de papier.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float map_k : hint_range(0.0, 1.0) = 0.6;
uniform float curve_k : hint_range(0.0, 1.0) = 0.3;
uniform float mid_gamma = 1.15;
uniform vec3 shadow_tint = vec3(0.82, 1.0, 1.12);
uniform float warm_boost = 0.25;
uniform float split_k : hint_range(0.0, 1.0) = 0.7;
uniform float shoulder = 0.6;
uniform float chroma_flat : hint_range(0.0, 1.0) = 0.35;
uniform float glow = 0.6;
uniform float glow_threshold = 0.75;
uniform float vignette = 0.22;
uniform float bands = 4.0;
uniform float band_k : hint_range(0.0, 1.0) = 0.45;
uniform float saturation = 1.45;
uniform float clarity = 0.5;
uniform float paper = 0.02;
uniform float ref_height = 1080.0;

// Courbe : luminance du jeu (centiles 0, 5, 25, 50, 75, 95, 99, 100) ->
// luminance de la cible aux mêmes centiles.
const float CURVE_IN[8] = float[8](0.0, 0.025, 0.059, 0.212, 0.387, 0.728, 0.881, 1.0);
const float CURVE_OUT[8] = float[8](0.02, 0.059, 0.137, 0.218, 0.326, 0.526, 0.678, 0.9);
// Couleur moyenne de la cible par tranche de luminance (12 tranches).
const vec3 TARGET_MAP[12] = vec3[12](
	vec3(0.038, 0.061, 0.051), vec3(0.089, 0.142, 0.121), vec3(0.159, 0.225, 0.190),
	vec3(0.242, 0.308, 0.256), vec3(0.330, 0.386, 0.314), vec3(0.369, 0.486, 0.403),
	vec3(0.406, 0.576, 0.480), vec3(0.534, 0.657, 0.554), vec3(0.699, 0.719, 0.550),
	vec3(0.835, 0.793, 0.575), vec3(0.866, 0.882, 0.690), vec3(0.941, 0.974, 0.669));

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float curve(float l) {
	for (int i = 1; i < 8; i++) {
		if (l <= CURVE_IN[i]) {
			float t = (l - CURVE_IN[i - 1]) / max(CURVE_IN[i] - CURVE_IN[i - 1], 1e-5);
			return mix(CURVE_OUT[i - 1], CURVE_OUT[i], t);
		}
	}
	return CURVE_OUT[7];
}

vec3 target_color(float l) {
	float f = clamp(l * 12.0 - 0.5, 0.0, 11.0);
	int i = int(floor(f));
	int j = min(i + 1, 11);
	return mix(TARGET_MAP[i], TARGET_MAP[j], f - float(i));
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 src = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 c = src;
	// Netteté locale : écart à la moyenne d'un voisinage de ~6 px (1080p).
	float k = (1.0 / px.y) / ref_height;
	vec2 o = px * 6.0 * k;
	vec3 blur = (textureLod(screen_tex, SCREEN_UV + vec2(o.x, 0.0), 0.0).rgb
			+ textureLod(screen_tex, SCREEN_UV - vec2(o.x, 0.0), 0.0).rgb
			+ textureLod(screen_tex, SCREEN_UV + vec2(0.0, o.y), 0.0).rgb
			+ textureLod(screen_tex, SCREEN_UV - vec2(0.0, o.y), 0.0).rgb) * 0.25;
	c = max(c + (c - blur) * clarity, vec3(0.0));
	// Valeurs : courbe mesurée puis paliers doux.
	float l = luma(c);
	float l2 = mix(l, curve(clamp(l, 0.0, 1.0)), curve_k);
	// Tons moyens relevés (gamma), noirs gardés profonds.
	l2 = pow(clamp(l2, 0.0, 1.0), 1.0 / mid_gamma);
	// Épaule douce : les hautes lumières (carrelage sous les lampes) gardent
	// leurs écarts au lieu de saturer en crème uniforme.
	if (l2 > shoulder) {
		float e = l2 - shoulder;
		l2 = shoulder + e / (1.0 + e / max(1.0 - shoulder, 1e-3) * 1.6);
	}
	float y = l2 * bands;
	float lb = (floor(y) + smoothstep(0.3, 0.7, fract(y))) / bands;
	l2 = mix(l2, lb, band_k);
	// Teinte : rapport couleur / luminance, celui de l'image rapproché de
	// celui de la cible à cette luminance (la teinte change, la valeur reste),
	// puis saturation.
	vec3 tc = target_color(l2);
	vec3 hue_own = c / max(l, 1e-4);
	vec3 hue_tgt = tc / max(luma(tc), 1e-4);
	// Carte de la cible seulement sous les hautes lumières (ses tranches
	// claires mélangent lampes chaudes et carrelage bleu-vert : olive).
	vec3 col = l2 * mix(hue_own, hue_tgt, map_k * (1.0 - smoothstep(0.3, 0.5, l2)));
	// Saturation relevée dans les ombres et tons moyens seulement (le
	// carrelage clair ne vire pas au jaune citron).
	col = max(mix(vec3(luma(col)), col, mix(saturation, 1.0, smoothstep(0.3, 0.5, l2))), vec3(0.0));
	// Ombres et tons sombres vers le cyan-bleu-vert ; les hautes lumières
	// gardent leur teinte du CLASSIQUE (le carrelage crème reste crème).
	float lo = 1.0 - smoothstep(0.3, 0.5, l2);
	col *= mix(vec3(1.0), shadow_tint, split_k * lo);
	// Chaleur : seulement les pixels DÉJÀ orange / ambre et assez saturés
	// (ampoules, halos des lampes, peau, bois) : saturation +25 % au plus.
	vec3 hsv_c = rgb2hsv(src);
	float orange = smoothstep(0.02, 0.05, hsv_c.x) * (1.0 - smoothstep(0.11, 0.14, hsv_c.x))
			* smoothstep(0.22, 0.3, hsv_c.y);
	col = max(mix(vec3(luma(col)), col, 1.0 + warm_boost * orange), vec3(0.0));
	// Aplats de couleur : la teinte (rapport couleur / valeur) ramenée en
	// partie à des pas (6 par canal), la valeur intacte.
	float lc = max(luma(col), 1e-4);
	vec3 ratio = col / lc;
	vec3 rq = floor(ratio * 6.0 + 0.5) / 6.0;
	col = mix(col, rq * lc, chroma_flat);
	// Halo des sources lumineuses (yeux, lampes, panneaux) : 8 lectures à
	// ~14 px, seuil sur la luminance.
	if (glow > 0.0) {
		vec3 halo = vec3(0.0);
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			vec3 s = textureLod(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * px * 14.0 * k, 0.0).rgb;
			halo += max(s - vec3(glow_threshold), vec3(0.0));
		}
		col += halo * (glow / 8.0);
	}
	// Vignette douce.
	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - vignette * smoothstep(0.25, 0.75, dot(v, v) * 2.0);
	// Grain de papier (fixe, très léger).
	col += (hash(floor(FRAGCOORD.xy / max(k * 1.5, 1.0))) - 0.5) * paper;
	COLOR = vec4(mix(src, col, amount), 1.0);
}
