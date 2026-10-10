shader_type spatial;
// Texture importée d'une carte de l'éditeur (MapTextureLib, format 15) en
// PIXEL ART : l'image, réduite au chargement à 20 pixels par mètre
// (MapTextureLib.pixelate), est répétée en coordonnées MONDE et lue au plus
// proche, comme les surfaces du jeu (pixel_surface.gdshader) : un pixel = un
// cube de 5 cm, sur la grille du monde, même échelle sur le sol, les murs et
// le plafond, aucune couture entre les morceaux de géométrie.
//   sol      : u vers l'est (x), v vers le sud (z)
//   plafond  : vu d'en dessous (v vers le nord : pas de miroir)
//   mur      : u le long du mur (vers la droite de qui le regarde), v vers le
//              bas ; le bas de l'image touche le sol de la salle (floor_y)
// `tile` : taille d'une répétition de l'image en mètres (largeur, hauteur) =
// côtés de l'image réduite / 20.
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform vec2 tile = vec2(2.0, 2.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_base = 0.85;
uniform float metallic_base = 0.0;
// Paramètres d'instance posés par MeshMapBuilder sur toute l'architecture :
// sol de la salle ; « oblique » sans effet ici (le sens du mur vient
// toujours de la face).
instance uniform float floor_y = 0.0;
instance uniform float oblique = 0.0;

const float PX_PER_M = 20.0;

varying vec3 wpos;
varying vec3 wnorm;

// Vecteur unitaire sans normalize() d'un calcul (NaN possible sur un vecteur
// nul, test_render_quality) : `fb` si la longueur est nulle.
vec3 unit3(vec3 v, vec3 fb) {
	float l = length(v);
	return l > 1e-6 ? v / l : fb;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	// Repère tangent (carte des normales) : sens de u et haut de l'image.
	vec3 nn = unit3(wnorm, vec3(0.0, 1.0, 0.0));
	vec3 t = vec3(1.0, 0.0, 0.0);
	vec3 b = vec3(0.0, 0.0, -1.0);
	if (abs(nn.y) < 0.5) {
		vec3 d = unit3(vec3(nn.z, 0.0, -nn.x), vec3(1.0, 0.0, 0.0));
		t = d;
		b = vec3(0.0, 1.0, 0.0);
	} else if (nn.y < 0.0) {
		b = vec3(0.0, 0.0, 1.0);
	}
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	TANGENT = unit3(inv * t, t);
	BINORMAL = unit3(inv * b, b);
}

void fragment() {
	// Orientation VRAIE de la face (dérivées de la position) : faces d'un mur
	// en escalier de cubes (normale d'éclairage penchée).
	vec3 fc = cross(dFdx(wpos), dFdy(wpos));
	float fl = length(fc);
	vec3 n = fl > 1e-12 ? fc / fl : vec3(0.0, 1.0, 0.0);
	if (dot(n, wnorm) < 0.0) {
		n = -n;
	}
	vec3 p = wpos - n * 0.001;
	vec2 px;
	if (abs(n.y) < 0.5) {
		vec2 t = vec2(n.z, -n.x);
		float tl = length(t);
		vec2 d = tl > 1e-6 ? t / tl : vec2(1.0, 0.0);
		px = vec2(dot(p.xz, d), floor_y - p.y + oblique * 0.0);
	} else if (n.y > 0.0) {
		px = p.xz;
	} else {
		px = vec2(p.x, -p.z);
	}
	px *= PX_PER_M;
	vec2 size_px = max(tile * PX_PER_M, vec2(1.0));
	// Centre du pixel (plus proche exact) ; dérivées du point continu.
	vec2 uv = (floor(px) + 0.5) / size_px;
	vec2 gx = dFdx(px) / size_px;
	vec2 gy = dFdy(px) / size_px;
	vec4 c = textureGrad(albedo_tex, uv, gx, gy);
	ALBEDO = c.rgb * tint.rgb;
	ROUGHNESS = roughness_base;
	METALLIC = metallic_base;
	if (use_normal) {
		NORMAL_MAP = textureGrad(normal_tex, uv, gx, gy).rgb;
	}
}
