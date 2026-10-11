shader_type canvas_item;
// Ombre portée d'une image du hub v2 (filter: drop-shadow des maquettes) :
// silhouette (alpha) de la texture, floutée (gaussienne, écart type
// `sigma_uv`), teinte `shadow_color`. Le rectangle dessiné déborde de l'image
// de `inset_uv` de chaque côté (place du flou). Voir Hub2Render.

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform vec2 sigma_uv = vec2(0.01);
uniform vec2 inset_uv = vec2(0.02);

// Couleur du sommet (modulate du nœud et de ses parents : fondus).
varying vec4 vertex_color;

void vertex() {
	vertex_color = COLOR;
}

void fragment() {
	float sum = 0.0;
	float wsum = 0.0;
	vec2 span = max(vec2(1.0) - 2.0 * inset_uv, vec2(0.0001));
	// 7 × 7 échantillons sur ±2 écarts types.
	for (int i = -3; i <= 3; i++) {
		for (int j = -3; j <= 3; j++) {
			vec2 k = vec2(float(i), float(j)) / 1.5;
			float w = exp(-0.5 * dot(k, k));
			vec2 t = (UV + k * sigma_uv - inset_uv) / span;
			float a = 0.0;
			if (t.x >= 0.0 && t.y >= 0.0 && t.x <= 1.0 && t.y <= 1.0) {
				a = texture(TEXTURE, t).a;
			}
			sum += a * w;
			wsum += w;
		}
	}
	COLOR = vec4(shadow_color.rgb, shadow_color.a * sum / wsum) * vertex_color;
}
