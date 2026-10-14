shader_type spatial;
// Poussière dans les faisceaux d'une fenêtre barricadée (WindowOutside) :
// cubes de 2,5 cm qui flottent lentement devant l'ouverture, côté salle.
// Un grain ne s'allume que s'il est dans la lumière du dehors : le rayon qui
// va de la source (light_pos) au grain doit passer par l'ouverture (faces du
// mur) et par un interstice des planches (texture `gap_mask` : l'ouverture
// vue de face, blanc = jour, ligne 0 en haut) ; planches arrachées ou
// reposées : la texture change, les grains suivent. Même règle que
// window_beams.gdshader. Repère : celui de la barricade (+Z vers la salle).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D gap_mask : filter_nearest, repeat_disable;
uniform vec3 light_pos = vec3(0.0, 3.4, -3.5);
uniform float plane_z = -0.375;
uniform vec2 faces = vec2(-0.5, 0.5);
// Ouverture dans le plan des planches : x0, y0, largeur, hauteur.
uniform vec4 area = vec4(-0.5, 0.95, 1.0, 1.4);
// Boîte où flottent les grains (repère de la barricade) : min, taille.
uniform vec3 box_min = vec3(-0.8, 0.3, 0.4);
uniform vec3 box_size = vec3(1.6, 2.1, 2.6);
uniform vec4 color : source_color = vec4(0.55, 0.85, 0.85, 1.0);
uniform float energy = 0.6;

varying float v_lit;

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

bool in_area(vec2 p) {
	return p.x >= area.x && p.x <= area.x + area.z && p.y >= area.y && p.y <= area.y + area.w;
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 r = vec3(h11(id * 1.37 + 0.1), h11(id * 2.71 + 0.3), h11(id * 3.97 + 0.7));
	// Dérive lente : monte un peu, ondule, revient par le bas de la boîte.
	float t = TIME * (0.02 + 0.015 * h11(id * 5.1));
	vec3 p = r + vec3(sin(TIME * 0.31 + id) * 0.03, t, cos(TIME * 0.27 + id * 1.7) * 0.03);
	p = fract(p);
	vec3 pos = box_min + p * box_size;
	vec3 dir = pos - light_pos;
	float lit = 0.0;
	if (dir.z > 0.001) {
		vec2 o = light_pos.xy + dir.xy * ((faces.x - light_pos.z) / dir.z);
		vec2 i = light_pos.xy + dir.xy * ((faces.y - light_pos.z) / dir.z);
		vec2 hit = light_pos.xy + dir.xy * ((plane_z - light_pos.z) / dir.z);
		if (in_area(o) && in_area(i)) {
			vec2 uv = (hit - area.xy) / area.zw;
			lit = texture(gap_mask, vec2(uv.x, 1.0 - uv.y)).r;
		}
	}
	// Scintillement (le grain tourne dans la lumière) ; fondu en haut et en bas
	// de la boîte, et tout près de la caméra (pas de gros carré blanc).
	lit *= 0.5 + 0.5 * sin(TIME * (1.5 + h11(id * 7.3) * 2.0) + id);
	lit *= smoothstep(0.0, 0.15, p.y) * smoothstep(1.0, 0.8, p.y);
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	lit *= smoothstep(0.6, 1.4, distance(cam, pos));
	v_lit = lit;
	VERTEX = pos + VERTEX * step(0.02, lit);
}

void fragment() {
	if (v_lit < 0.02) {
		discard;
	}
	ALBEDO = color.rgb * energy * v_lit;
}
