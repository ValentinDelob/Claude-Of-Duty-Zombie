shader_type spatial;
// Matériau des armes et des mains (vue FPS et 3e personne).
// viewmodel = 1 : la profondeur est écrasée vers le plan proche pour que
// l'arme ne traverse jamais les murs (profondeur inversée de Godot 4 : 1 = proche),
// et l'image est rendue avec le champ de vision propre à l'arme (vm_fov_scale).
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.4;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float viewmodel = 0.0;
uniform float wear = 0.18;
// Usure des arêtes (COLOR.r des maillages de WeaponMesh : chanfreins).
uniform float edge_wear = 0.0;
// Bois : veinage le long de l'arme et vernis.
uniform float grain = 0.0;
// Variation de teinte d'une pièce à l'autre (COLOR.g).
uniform float tone_var = 0.0;
// Tissu (manches) : trame fine et plis.
uniform float fabric = 0.0;
// Effet Pack-a-Punch (camouflage animé).
uniform float pap = 0.0;
uniform vec4 pap_color : source_color = vec4(0.55, 0.1, 0.9, 1.0);
// Rapport tan(fov caméra / 2) / tan(fov arme / 2) (ViewModel).
global uniform float vm_fov_scale;
// Joue de visée (ViewModel.bend_params) : début, fin (profondeurs, m), abaissement (m).
global uniform vec3 vm_bend;

varying vec3 obj_pos;
varying vec2 vdata;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	obj_pos = VERTEX;
	vdata = COLOR.rg;
	// POSITION doit être écrit dans TOUS les cas : dès qu'un shader l'écrit,
	// Godot n'applique plus la projection par défaut.
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (viewmodel > 0.5) {
		// Joue de visée (ViewModel.bend, même formule) : ce qui est plus près
		// de l'œil que le cran est abaissé, jusqu'à vm_bend.z m à vm_bend.y m.
		if (vm_bend.z > 0.0) {
			vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
			float s = clamp((vm_bend.x + vp.z) / max(vm_bend.x - vm_bend.y, 0.0001), 0.0, 1.0);
			vp.y -= vm_bend.z * s * s;
			POSITION = PROJECTION_MATRIX * vp;
		}
		POSITION.xy *= vm_fov_scale;
		POSITION.z = mix(POSITION.z, POSITION.w, 0.92);
	}
}

void fragment() {
	float n = hash3(floor(obj_pos * 90.0));
	float n2 = hash3(floor(obj_pos * 23.0) + 3.1);
	float smear = vnoise(obj_pos * vec3(40.0, 40.0, 14.0));
	vec3 col = albedo.rgb * (1.0 - wear + wear * (0.6 * n + 0.4 * n2));
	col *= 1.0 + (vdata.g - 0.5) * tone_var;
	float rough = roughness;
	float metal = metallic;
	if (grain > 0.0) {
		// Veines étirées le long de l'axe de l'arme (Z), cernes ondulés, pores.
		float warp = vnoise(obj_pos * vec3(18.0, 18.0, 3.0)) * 6.0;
		float rings = sin((obj_pos.y * 260.0 + obj_pos.x * 90.0) + warp * 2.2);
		float streak = smoothstep(0.35, 1.0, rings) * 0.55 + smoothstep(0.6, 1.0, vnoise(obj_pos * vec3(120.0, 120.0, 8.0))) * 0.35;
		col *= mix(1.0, 0.62, streak * grain);
		col *= 0.9 + 0.1 * n;
		// Vernis : plus lisse, reflets marqués ; usé par plaques.
		rough = mix(rough, 0.45 + 0.3 * smoothstep(0.55, 0.8, smear), grain);
	}
	if (fabric > 0.0) {
		float weave = sin(obj_pos.x * 900.0) * sin(obj_pos.z * 900.0 + obj_pos.y * 900.0);
		float folds = vnoise(obj_pos * vec3(30.0, 30.0, 60.0));
		col *= mix(1.0, (0.86 + 0.14 * weave) * (0.72 + 0.4 * folds), fabric);
		rough = mix(rough, 0.95, fabric);
	}
	if (edge_wear > 0.0) {
		// Arêtes et saillies polies par l'usage : le métal nu (ou le bois
		// clair) apparaît sous le bronzage, par endroits.
		float e = vdata.r * edge_wear * (0.35 + 0.4 * smoothstep(0.3, 0.7, smear));
		vec3 bare = metal > 0.3 ? max(col * 1.9, vec3(0.2, 0.2, 0.19)) : col * 1.35;
		col = mix(col, bare, e);
		rough = mix(rough, metal > 0.3 ? 0.28 : rough, e);
	}
	// Taches de crasse et de doigts sur les surfaces (moins brillantes).
	rough = clamp(rough + (smear - 0.5) * 0.18, 0.05, 1.0);
	vec3 emi = emission.rgb * emission_energy;
	if (pap > 0.5) {
		float t = TIME * 0.6;
		float pattern = sin(obj_pos.x * 60.0 + t * 3.0) * sin(obj_pos.z * 45.0 - t * 2.0) * sin(obj_pos.y * 70.0 + t);
		float m = smoothstep(0.1, 0.6, pattern);
		col = mix(col * 0.4, pap_color.rgb, m * 0.8);
		emi += pap_color.rgb * m * (0.8 + 0.4 * sin(TIME * 4.0));
		rough = 0.35;
	}
	if (viewmodel > 0.5) {
		// Lumière d'appoint de la vue FPS (comme les armes de BO1) : les faces
		// tournées vers l'œil restent lisibles même dos aux lampes (visée).
		float facing = clamp(NORMAL.z, 0.0, 1.0);
		float top = clamp(NORMAL.y, 0.0, 1.0);
		emi += (col * 0.3 + vec3(0.012, 0.012, 0.011)) * (0.22 + 0.5 * facing + 0.22 * top);
		// Liseré de contre-jour sur les bords (lecture des silhouettes).
		float rim = pow(clamp(1.0 - dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		emi += col * rim * 0.2;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emi;
}
