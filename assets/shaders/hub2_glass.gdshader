shader_type canvas_item;
render_mode unshaded;
// Verre du hub v2 (Hub2Box avec flou) : ce qui est derrière le panneau est
// flouté (backdrop-filter: blur(Npx) des maquettes, écart type N px), puis
// le fond rgba et le liseré sont posés dessus ; biseaux comme hub2_box.
//
// Flou : mipmaps de l'écran (Godot les floute à la copie) lues à un niveau
// adapté à l'écart type, puis 16 échantillons en spirale pondérés par une
// gaussienne (aucun escalier visible des mipmaps). L'écart type est donné en
// unités locales et converti en pixels de l'écran (toute résolution).
//
// La copie de l'écran est faite une fois avant le premier verre dessiné :
// un verre ne floute pas un autre verre dessiné avant lui dans la même image
// (ajouter un BackBufferCopy si un jour il le faut, Hub2Style.blur_barrier).

#include "res://assets/shaders/hub2_box.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
// Écart type du flou (unités locales).
uniform float blur = 12.0;

void fragment() {
	vec2 aa2 = fwidth(local_pos);
	float aa = max(max(aa2.x, aa2.y), 0.0001);
	// Pixels de l'écran par unité locale.
	float k = 1.0 / aa;
	float sigma = blur * k;
	vec3 bg;
	if (sigma < 0.5) {
		bg = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	} else {
		float lod = clamp(log2(sigma) - 1.2, 0.0, 7.0);
		vec3 acc = vec3(0.0);
		float wsum = 0.0;
		// Spirale de Vogel : 16 points sur un disque de 2 écarts types.
		for (int i = 0; i < 16; i++) {
			float r = sqrt((float(i) + 0.5) / 16.0) * 2.0 * sigma;
			float t = float(i) * 2.39996323;
			vec2 o = vec2(cos(t), sin(t)) * r;
			float w = exp(-(r * r) / (2.0 * sigma * sigma));
			acc += textureLod(screen_tex, SCREEN_UV + o * SCREEN_PIXEL_SIZE, lod).rgb * w;
			wsum += w;
		}
		bg = acc / wsum;
	}
	vec4 c = hub2_over(fill, vec4(bg, 1.0));
	c = hub2_over(vec4(border_color.rgb, border_color.a * hub2_border(local_pos, aa)), c);
	c.a *= hub2_mask(local_pos, aa);
	COLOR = c * COLOR;
}
