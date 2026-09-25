shader_type spatial;
// Matériau des armes (vue FPS et 3e personne).
// viewmodel = 1 : la profondeur est écrasée vers le plan proche pour que
// l'arme ne traverse jamais les murs (profondeur inversée de Godot 4 : 1 = proche).
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.4;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float viewmodel = 0.0;
uniform float wear = 0.18;
// Effet Pack-a-Punch (camouflage animé).
uniform float pap = 0.0;
uniform vec4 pap_color : source_color = vec4(0.55, 0.1, 0.9, 1.0);

varying vec3 obj_pos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	obj_pos = VERTEX;
	if (viewmodel > 0.5) {
		POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		POSITION.z = mix(POSITION.z, POSITION.w, 0.92);
	}
}

void fragment() {
	float n = hash3(floor(obj_pos * 90.0));
	float n2 = hash3(floor(obj_pos * 23.0) + 3.1);
	vec3 col = albedo.rgb * (1.0 - wear + wear * (0.6 * n + 0.4 * n2));
	float rough = roughness;
	vec3 emi = emission.rgb * emission_energy;
	if (pap > 0.5) {
		float t = TIME * 0.6;
		float pattern = sin(obj_pos.x * 60.0 + t * 3.0) * sin(obj_pos.z * 45.0 - t * 2.0) * sin(obj_pos.y * 70.0 + t);
		float m = smoothstep(0.1, 0.6, pattern);
		col = mix(col * 0.4, pap_color.rgb, m * 0.8);
		emi += pap_color.rgb * m * (0.8 + 0.4 * sin(TIME * 4.0));
		rough = 0.35;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metallic;
	EMISSION = emi;
}
