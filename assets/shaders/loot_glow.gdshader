shader_type spatial;
// Lueurs du BUTIN au sol (LootFx, docs/ART_DIRECTION.md « Butin ») :
// additives, non éclairées, en PIXELS CUBIQUES (paliers de 5 cm, jamais de
// dégradé lisse) :
//   mode 0 : liseré de rareté sur l'objet (material_overlay du modèle :
//            faces rasantes teintées, battement lent) ;
//   mode 1 : flaque de lumière au sol (plan horizontal, disque en pixels
//            de 5 cm, quatre paliers d'intensité, pulsation) ;
//   mode 2 : faisceau vertical (colonne carrée : paliers de 5 cm qui
//            montent, fondu vers le haut et sur les arêtes).
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform int mode = 0;
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.12, 1.0);
uniform float intensity = 1.0;
// Pixel des flaques et des paliers des faisceaux (m).
uniform float px = 0.05;
// Faisceau : hauteur (m) et vitesse de montée des paliers.
uniform float height = 2.0;
uniform float rise = 0.6;
// Apparition (0 caché, 1 plein) et décalage de phase, par objet.
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;

// Faisceau : demi-largeur de la colonne (m) : bords fondus.
uniform float half_width = 0.05;

varying vec3 v_local;
varying vec3 v_n;

float hash(float n) {
	return fract(sin(n * 91.345 + 7.13) * 43758.5453);
}

void vertex() {
	v_local = VERTEX;
	v_n = NORMAL;
}

void fragment() {
	float pulse = 0.82 + 0.18 * sin(TIME * 2.4 + seed * 6.283);
	vec3 col = color.rgb;
	float a = 0.0;
	if (mode == 0) {
		// Faces vues de biais : plus lumineuses (liseré), un fond léger partout.
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		float graze = max(1.0 - facing, 0.0);
		a = (0.16 + 0.84 * graze * graze) * pulse;
	} else if (mode == 1) {
		vec2 pc = floor(v_local.xz / px) + 0.5;
		float r = length(pc * px) / max(height, 0.01);
		float f = clamp(1.0 - r, 0.0, 1.0);
		// Quatre paliers : anneaux de pixels nets.
		f = floor(f * f * 4.0 + 0.6) / 4.0;
		a = f * pulse;
	} else {
		float y = clamp(v_local.y / height + 0.5, 0.0, 1.0);
		// Paliers de `px` m : bandes qui montent lentement.
		float band = floor((v_local.y + height * 0.5) / px);
		float flick = 0.7 + 0.3 * hash(band + floor(TIME * rise * 8.0 + seed * 13.0));
		float vert = smoothstep(0.0, 0.08, y) * pow(max(1.0 - y, 0.0), 1.6);
		vert = floor(vert * 6.0 + 0.5) / 6.0;
		// Bords de la colonne fondus (lumière, pas une planche) ; dessus et
		// dessous invisibles.
		float across = abs(v_n.x) > 0.5 ? v_local.z : v_local.x;
		float core = clamp(1.0 - abs(across) / max(half_width, 0.001), 0.0, 1.0);
		core = core * core * step(abs(v_n.y), 0.5);
		a = vert * flick * core * pulse;
	}
	ALBEDO = col * a * intensity * fade;
}
