shader_type spatial;
// Contour de RARETÉ d'un butin au sol (LootFx.dress) : coque du modèle
// gonflée le long des normales, faces arrière seulement, couleur de la
// rareté pleine et lumineuse (le contour noir de l'écran se dessine autour).
// Posée en material_overlay des maillages de l'objet ; `next_pass` : le
// liseré additif (loot_glow.gdshader, mode 0).
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.12, 1.0);
uniform float width = 0.012;
uniform float energy = 1.6;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	float pulse = 0.85 + 0.15 * sin(TIME * 2.4);
	ALBEDO = color.rgb * energy * pulse;
}
