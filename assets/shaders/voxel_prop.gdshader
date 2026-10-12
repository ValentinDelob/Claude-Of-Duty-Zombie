shader_type spatial;
// Décor CUBIQUE de la carte (assets/models/props/voxel/*.glb, cubes de 5 cm,
// tools/blender/voxel_props/) : la couleur de chaque face de cube vient du
// modèle (COLOR_0, déjà linéaire), sans texture ; une face d'alpha 0
// est ÉMISSIVE (braises, ampoules, écrans : matière « glow » de voxel_lib).
// Réponse des matières (docs/ART_DIRECTION.md « Lumière et ambiance ») :
// chaque cube de 5 cm un peu plus clair ou plus sombre (+/- `detail` / 2),
// pris sur la grille du monde : les grandes faces fusionnées du modèle ne
// sont plus des aplats.
// Matériau « voxel » de MeshMapBuilder._special.
render_mode cull_back;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float glow_energy = 3.5;
uniform float detail = 0.09;

varying vec3 wpos;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// Cube de 5 cm sous ce point (légèrement rentré dans la face).
	vec3 cell = floor((wpos - wn * 0.01) * 20.0);
	float j = hash31(cell + wn * 7.0);
	ALBEDO = COLOR.rgb * (1.0 + detail * (j - 0.5));
	ROUGHNESS = roughness_value;
	if (COLOR.a < 0.5) {
		EMISSION = COLOR.rgb * glow_energy;
	}
}
