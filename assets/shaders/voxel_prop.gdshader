shader_type spatial;
// Décor CUBIQUE de la carte (assets/models/props/voxel/*.glb, cubes de 5 cm,
// tools/blender/voxel_props/) : la couleur de chaque face de cube vient du
// modèle (COLOR_0, déjà linéaire), sans texture ni bruit ; une face d'alpha 0
// est ÉMISSIVE (braises, ampoules : matière « glow » de voxel_lib).
// Matériau « voxel » de MeshMapBuilder._special.
render_mode cull_back;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float glow_energy = 2.5;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
	if (COLOR.a < 0.5) {
		EMISSION = COLOR.rgb * glow_energy;
	}
}
