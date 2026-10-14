shader_type spatial;
// Faisceaux de lumière d'une fenêtre barricadée (WindowOutside) : la
// lumière du dehors entre par les interstices des planches et se voit dans la
// poussière de la salle. La brume volumétrique de Godot ignore la texture de
// projection d'un projecteur (elle dessinait un cône plein, à travers le
// mur) : le faisceau est donc marché ici, dans une boîte devant l'ouverture.
// Pour chaque point du rayon de vue dans la boîte, le rayon qui vient de la
// source (light_pos) doit passer par l'ouverture (faces extérieure et
// intérieure du mur) et par un interstice des planches (texture gap_mask,
// refaite à chaque planche arrachée ou reposée) : des nappes de lumière nettes,
// une par interstice. Faces arrière seulement (un passage par pixel), arrêt
// sur la profondeur de la scène (zombie, caisse, mur devant).
// Repère : celui de la barricade (+Z vers la salle, X le long du mur).
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

uniform sampler2D gap_mask : filter_nearest, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 light_pos = vec3(0.0, 3.4, -3.5);
uniform float plane_z = -0.375;
// Faces extérieure et intérieure du mur (z).
uniform vec2 faces = vec2(-0.5, 0.5);
// Ouverture : x0, y0, largeur, hauteur.
uniform vec4 area = vec4(-0.5, 0.95, 1.0, 1.4);
uniform vec3 box_min = vec3(-1.0, 0.0, -0.4);
uniform vec3 box_max = vec3(1.0, 2.4, 3.2);
uniform vec4 color : source_color = vec4(0.5, 0.8, 0.8, 1.0);
uniform float energy = 0.5;
// Longueur de décroissance du faisceau dans la salle (m).
uniform float falloff = 1.6;

// Pas de la marche (préréglage : 10 en MEDIUM, 16 en HIGH).
uniform int steps = 10;

// Milieu de la boîte dans le repère de la barricade (le nœud y est placé).
uniform vec3 offset = vec3(0.0);

varying vec3 v_local;
varying vec3 v_cam;

void vertex() {
	v_local = VERTEX + offset;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz + offset;
}

bool in_area(vec2 p) {
	return p.x >= area.x && p.x <= area.x + area.z && p.y >= area.y && p.y <= area.y + area.w;
}

float lit(vec3 p) {
	vec3 d = p - light_pos;
	if (d.z <= 0.001) {
		return 0.0;
	}
	vec2 o = light_pos.xy + d.xy * ((faces.x - light_pos.z) / d.z);
	vec2 i = light_pos.xy + d.xy * ((faces.y - light_pos.z) / d.z);
	if (!in_area(o) || !in_area(i)) {
		return 0.0;
	}
	vec2 h = light_pos.xy + d.xy * ((plane_z - light_pos.z) / d.z);
	vec2 uv = (h - area.xy) / area.zw;
	return texture(gap_mask, vec2(uv.x, 1.0 - uv.y)).r;
}

void fragment() {
	vec3 ro = v_cam;
	vec3 seg = v_local - ro;
	float t_back = length(seg);
	vec3 rd = seg / t_back;
	// Entrée dans la boîte (la caméra peut être dedans).
	vec3 inv = 1.0 / rd;
	vec3 t0 = (box_min - ro) * inv;
	vec3 t1 = (box_max - ro) * inv;
	vec3 tmin = min(t0, t1);
	float t_near = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	// Surface de la scène devant la face arrière.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float t_far = min(t_back, length(view.xyz / view.w));
	if (t_far <= t_near) {
		discard;
	}
	float stp = (t_far - t_near) / float(steps);
	float jit = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	float acc = 0.0;
	for (int k = 0; k < steps; k++) {
		vec3 p = ro + rd * (t_near + (float(k) + jit) * stp);
		float l = lit(p);
		if (l > 0.0) {
			// Plus dense près de l'ouverture, nul au sol.
			float fade = exp(-max(p.z - faces.y, 0.0) / falloff) * smoothstep(0.0, 0.4, p.y);
			acc += l * fade * stp;
		}
	}
	ALBEDO = color.rgb * energy * acc;
}
