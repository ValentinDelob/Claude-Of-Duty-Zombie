shader_type canvas_item;
// Style ILLUSTRÉ (IllustratedPost, docs/ART_DIRECTION.md « Style illustré ») :
// filtre de KUWAHARA à 4 quadrants sur l'image finale (après tonemap) :
// chaque pixel prend la couleur moyenne du quadrant le plus uniforme autour
// de lui. Le bruit des textures pixel art devient des aplats peints, les
// bords (arêtes des cubes, contour noir) restent nets.
// `radius` en pixels à 1080p (proportionnel à la hauteur de l'image) ;
// 0 : pass-through. Le pas d'échantillonnage grandit avec le rayon (au plus
// 3 x 3 lectures bilinéaires par quadrant, 36 en tout) : coût borné.
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float radius = 3.0;
uniform float ref_height = 1080.0;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float r = radius * (1.0 / px.y) / ref_height;
	if (r < 0.75) {
		COLOR = vec4(textureLod(screen_tex, SCREEN_UV, 0.0).rgb, 1.0);
	} else {
		// 3 lectures par axe et par quadrant, entre les pixels (filtrage
		// bilinéaire : chaque lecture moyenne 4 pixels).
		float st = r / 2.0;
		vec3 m[4];
		vec3 s2[4];
		for (int q = 0; q < 4; q++) {
			m[q] = vec3(0.0);
			s2[q] = vec3(0.0);
		}
		for (int j = 0; j < 3; j++) {
			for (int i = 0; i < 3; i++) {
				vec2 o = vec2(float(i), float(j)) * st;
				vec3 a = textureLod(screen_tex, SCREEN_UV + vec2(-o.x, -o.y) * px, 0.0).rgb;
				vec3 b = textureLod(screen_tex, SCREEN_UV + vec2(o.x, -o.y) * px, 0.0).rgb;
				vec3 c = textureLod(screen_tex, SCREEN_UV + vec2(-o.x, o.y) * px, 0.0).rgb;
				vec3 d = textureLod(screen_tex, SCREEN_UV + vec2(o.x, o.y) * px, 0.0).rgb;
				m[0] += a; s2[0] += a * a;
				m[1] += b; s2[1] += b * b;
				m[2] += c; s2[2] += c * c;
				m[3] += d; s2[3] += d * d;
			}
		}
		float best = 1e9;
		vec3 col = vec3(0.0);
		for (int q = 0; q < 4; q++) {
			vec3 mu = m[q] / 9.0;
			vec3 v = abs(s2[q] / 9.0 - mu * mu);
			float sig = v.r + v.g + v.b;
			if (sig < best) {
				best = sig;
				col = mu;
			}
		}
		COLOR = vec4(col, 1.0);
	}
}
