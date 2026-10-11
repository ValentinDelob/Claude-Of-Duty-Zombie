shader_type spatial;
// Joueur de baseball CUBIQUE vu par les autres (PlayerModel, cubes de
// 2,5 cm, tools/blender/player/player_voxel.py) : couleur de la face telle
// quelle (COLOR_0, déjà linéaire, lue par ZombieGlb), sauf la ZONE
// D'ÉQUIPE (matière « team », UV2.y = RigBuilder.MAT_TEAM) : peinte en gris
// dans le modèle (0,8 = teinte pleine), elle prend la couleur du joueur
// (`team_color`, couleur sRGB de HudStyle.PLAYER_COLORS, par instance) :
// couleur = team_color × gris / 0,8, calcul fait en sRGB comme la planche de
// validation de Blender.
render_mode cull_back;

instance uniform vec4 team_color = vec4(1.0, 0.78, 0.28, 1.0);
// Teinte pleine de la zone d'équipe dans le modèle (sRGB).
const float TEAM_GREY = 0.8;
// Identifiant de matière de la zone d'équipe (RigBuilder.MAT_TEAM).
const float MAT_TEAM = 6.0;

varying float mat_id;

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, 0.0), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow(max((c + 0.055) / 1.055, 0.0), vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	mat_id = UV2.y;
}

void fragment() {
	vec3 col = COLOR.rgb;
	if (abs(floor(mat_id + 0.5) - MAT_TEAM) < 0.5) {
		float grey = to_srgb(col).g / TEAM_GREY;
		col = to_linear(clamp(team_color.rgb * grey, 0.0, 1.0));
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	METALLIC = 0.0;
}
