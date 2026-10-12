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

// Réponse des matières : variation par cube et crasse (0 : texture seule),
// sol mouillé (flaques, 0 : sec ; posé par PixelSurfaces.material d'après
// WorldLook.WET_SURFACES), assombrissement du pied des murs.
uniform float detail = 1.0;
uniform float wet = 0.0;
uniform float contact_ao = 0.6;
uniform vec4 puddle_sheen : source_color = vec4(0.11, 0.21, 0.24, 1.0);

const float PX_PER_M = 20.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Bruit de valeur lissé (grandes taches de crasse, flaques).
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

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
	// Réponse des matières (docs/ART_DIRECTION.md « Lumière et ambiance ») :
	// tout reste en pixels de 5 cm (valeurs prises au pixel, bords nets).
	vec2 cell = floor(px);
	vec2 cid = cell + (wall ? n.xz * 913.0 : vec2(n.y * 517.0));
	vec3 col = c.rgb;
	float rough = roughness_base;
	//  - chaque cube de 5 cm un peu plus clair ou plus sombre (+/- 4 %) ;
	col *= 1.0 + detail * 0.08 * (hash21(cid) - 0.5);
	//  - crasse : grandes taches (~1,5 m) qui assombrissent et matifient ;
	float gr = vnoise(cell / 30.0 + n.xz * 3.1 + vec2(n.y * 7.7));
	float grime = smoothstep(0.5, 0.85, gr) * detail;
	col *= 1.0 - 0.14 * grime;
	rough = mix(rough, 1.0, 0.5 * grime);
	//  - pied des murs assombri (occlusion de contact, 45 cm, en paliers
	//    de 5 cm) : les murs « posent » sur le sol ;
	if (wall) {
		float h = (cell.y + 0.5) / PX_PER_M;
		col *= mix(contact_ao, 1.0, smoothstep(0.0, 0.45, h));
	}
	//  - flaques sur les sols mouillés (`wet`) : formes en pixels, sombres
	//    et presque lisses (reflets des lampes ; SSR en HIGH), liseré foncé.
	float spec = 0.5;
	vec3 sheen = vec3(0.0);
	if (wet > 0.0 && n.y > 0.5) {
		float pud = vnoise(cell / 26.0 + vec2(17.3, 5.1)) * 0.7 + vnoise(cell / 8.0 + vec2(3.7, 9.2)) * 0.3;
		float m = step(0.77, pud) * wet;
		float rim = (step(0.73, pud) - step(0.77, pud)) * wet;
		// Eau : sombre (le sol se voit à peine dessous), lisse : elle ne
		// s'éclaircit que par les reflets ; le liseré humide est plus sombre.
		col = mix(col, col * 0.18 + vec3(0.008, 0.016, 0.02), m);
		col *= 1.0 - 0.3 * rim;
		rough = mix(rough, 0.1, m);
		rough = mix(rough, rough * 0.6, rim);
		spec = mix(0.5, 1.0, m);
		// Reflet de la pièce (bleu-vert) qui monte en vue rasante (Fresnel) :
		// sans lui, une flaque hors des reflets des lampes n'est qu'une tache.
		float fres = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		sheen = puddle_sheen.rgb * fres * m;
	}
	ALBEDO = col + oblique * 0.0;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metallic_base;
	EMISSION = sheen;
	// Lueur (veines de la pierre rituelle) : alpha de l'image = 1 - lueur ;
	// pulsation lente, décalée par bandes de 40 cm.
	if (glow > 0.0) {
		float v = 1.0 - c.a;
		EMISSION += glow_color.rgb * v * glow * (0.7 + 0.3 * sin(TIME * 1.5 + floor(px.x / 8.0) * 0.7));
	}
}
