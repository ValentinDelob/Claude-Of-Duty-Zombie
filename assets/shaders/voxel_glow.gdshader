shader_type spatial;
// Pièce CUBIQUE qui s'allume (fond et intérieur de la caisse au hasard,
// BoxModel) : couleur de face du modèle (COLOR_0, comme voxel_prop.gdshader),
// lueur `glow_color` × `glow_energy` réglée par pièce selon l'ouverture
// (paramètre d'instance « open », 0 fermée, 1 ouverte).
render_mode cull_back;

uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float glow_energy = 2.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
instance uniform float open = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
	EMISSION = glow_color.rgb * COLOR.rgb * glow_energy * open;
}
