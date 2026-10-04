shader_type spatial;
// Texture importée d'une carte de l'éditeur (MapTextureLib, format 15) :
// l'image est répétée en coordonnées MONDE, comme les surfaces du jeu
// (surface.gdshader) : même échelle sur le sol, les murs et le plafond, aucune
// couture entre les morceaux de géométrie, aucun étirement.
//   sol      : u vers l'est (x), v vers le sud (z)
//   plafond  : vu d'en dessous (v vers le nord : pas de miroir)
//   mur      : u le long du mur (vers la droite de qui le regarde), v vers le
//              bas ; le bas de l'image touche le sol de la salle (floor_y)
// `tile` : taille d'une répétition de l'image en mètres (largeur, hauteur).
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform vec2 tile = vec2(2.0, 2.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_base = 0.85;
uniform float metallic_base = 0.0;
// Mêmes paramètres d'instance que surface.gdshader (posés par MeshMapBuilder
// sur toute l'architecture) : sol de la salle ; « oblique » sans effet ici
// (le sens du mur vient toujours de sa normale).
instance uniform float floor_y = 0.0;
instance uniform float oblique = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Repère tangent (carte des normales) : sens de u et haut de l'image.
	vec3 t = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(0.0, 0.0, -1.0);
	if (abs(wnorm.y) < 0.5) {
		vec2 d = normalize(vec2(wnorm.z, -wnorm.x));
		t = vec3(d.x, 0.0, d.y);
		b = vec3(0.0, 1.0, 0.0);
	} else if (wnorm.y < 0.0) {
		b = vec3(0.0, 0.0, 1.0);
	}
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	TANGENT = normalize(inv * t);
	BINORMAL = normalize(inv * b);
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec2 uv;
	if (abs(n.y) < 0.5) {
		vec2 d = normalize(vec2(n.z, -n.x));
		uv = vec2(dot(wpos.xz, d), floor_y - wpos.y + oblique * 0.0);
	} else if (n.y > 0.0) {
		uv = wpos.xz;
	} else {
		uv = vec2(wpos.x, -wpos.z);
	}
	uv /= max(tile, vec2(0.01));
	vec4 c = texture(albedo_tex, uv);
	ALBEDO = c.rgb * tint.rgb;
	ROUGHNESS = roughness_base;
	METALLIC = metallic_base;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
	}
}
