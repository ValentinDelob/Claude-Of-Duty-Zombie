shader_type spatial;
// Surface « PIXEL ART » (PixelSurfaces, GAME_CONCEPT.md
// § 4.19) : un pixel de l'image = un cube de 5 cm, posé en coordonnées MONDE
// (20 pixels par mètre) : les pixels tombent sur la grille de 5 cm, sans
// étirement ni couture d'un morceau de géométrie à l'autre.
//   sol, plafond : pixel (x, z) × 20
//   mur          : u le long du mur, ligne 0 de l'image au sol de la salle
//                  (floor_y) ; au-dessus de l'image, les lignes [wrap_px,
//                  hauteur) se répètent (soubassement seulement en bas).
// Filtrage au plus proche ; les mipmaps (lues avec les dérivées du point non
// arrondi) évitent le scintillement au loin.
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec2 size_px = vec2(64.0, 64.0);
uniform float wrap_px = 0.0;
uniform float roughness_base = 0.9;
uniform float metallic_base = 0.0;
uniform vec4 glow_color : source_color = vec4(0.8, 0.05, 0.02, 1.0);
uniform float glow = 0.0;
// Paramètres d'instance posés par MeshMapBuilder sur toute l'architecture.
instance uniform float floor_y = 0.0;
instance uniform float oblique = 0.0;

const float PX_PER_M = 20.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Pas de normalize() d'un calcul (NaN possible, test_render_quality) : seul
	// le signe de la normale d'éclairage sert ici.
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// Orientation VRAIE de la face (dérivées de la position) : les faces d'un
	// mur en escalier ont une normale d'éclairage penchée vers le mur
	// (MeshMapGeometry.step_shade), mais leurs pixels suivent la face.
	vec3 fc = cross(dFdx(wpos), dFdy(wpos));
	float fl = length(fc);
	vec3 n = fl > 1e-12 ? fc / fl : vec3(0.0, 1.0, 0.0);
	if (dot(n, wnorm) < 0.0) {
		n = -n;
	}
	// Point légèrement rentré dans la face : un pixel au bord exact d'une
	// face (arête sur la grille de 5 cm) ne flotte pas entre deux cellules.
	vec3 p = wpos - n * 0.001;
	vec2 px;
	bool wall = abs(n.y) < 0.5;
	if (wall) {
		vec2 t = vec2(n.z, -n.x);
		float tl = length(t);
		vec2 d = tl > 1e-6 ? t / tl : vec2(1.0, 0.0);
		px = vec2(dot(p.xz, d), p.y - floor_y) * PX_PER_M;
	} else {
		px = p.xz * PX_PER_M;
	}
	vec2 g = px;
	if (wall && px.y >= size_px.y) {
		g.y = wrap_px + mod(px.y - wrap_px, size_px.y - wrap_px);
	}
	// Centre du pixel (plus proche exact) ; dérivées du point continu.
	vec2 uv = (floor(g) + 0.5) / size_px;
	vec4 c = textureGrad(albedo_tex, uv, dFdx(px) / size_px, dFdy(px) / size_px);
	ALBEDO = c.rgb + oblique * 0.0;
	ROUGHNESS = roughness_base;
	METALLIC = metallic_base;
	// Lueur (veines de la pierre rituelle) : alpha de l'image = 1 - lueur ;
	// pulsation lente, décalée par bandes de 40 cm.
	if (glow > 0.0) {
		float v = 1.0 - c.a;
		EMISSION = glow_color.rgb * v * glow * (0.7 + 0.3 * sin(TIME * 1.5 + floor(px.x / 8.0) * 0.7));
	}
}
