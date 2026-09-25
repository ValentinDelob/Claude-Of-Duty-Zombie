shader_type spatial;
// Personnages low-poly (zombies, joueurs) : couleur par sommet, émission
// masquée par l'alpha du sommet (yeux), crasse procédurale, flash de touche et
// dissolution à la mort (uniforms par instance : pas de duplication de matériau).
render_mode cull_back;

uniform vec4 emission_color : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform float emission_energy = 4.0;
uniform float grime = 0.35;
uniform float roughness = 0.85;
uniform float stain_amount = 0.7;
instance uniform float hit_flash = 0.0;
instance uniform float dissolve = 0.0;
instance uniform float eye_glow = 1.0;

varying vec3 local_pos;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i);
	float n100 = hash3(i + vec3(1, 0, 0));
	float n010 = hash3(i + vec3(0, 1, 0));
	float n110 = hash3(i + vec3(1, 1, 0));
	float n001 = hash3(i + vec3(0, 0, 1));
	float n101 = hash3(i + vec3(1, 0, 1));
	float n011 = hash3(i + vec3(0, 1, 1));
	float n111 = hash3(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float n = vnoise(local_pos * 14.0) * 0.6 + vnoise(local_pos * 41.0) * 0.4;
	if (dissolve > 0.0 && n < dissolve) {
		discard;
	}
	vec3 col = COLOR.rgb * (1.0 - grime + grime * n * 1.4);
	// Taches sombres (sang séché / saleté).
	float stain = smoothstep(0.62, 0.72, vnoise(local_pos * 6.0 + 11.0));
	col = mix(col, col * vec3(0.35, 0.08, 0.06), stain * stain_amount);
	float emissive = 1.0 - COLOR.a;
	ALBEDO = mix(col, vec3(1.0, 0.2, 0.15), hit_flash * 0.6);
	ROUGHNESS = roughness;
	EMISSION = emission_color.rgb * emission_energy * emissive * eye_glow + vec3(0.6, 0.05, 0.02) * hit_flash;
	// Bord brûlant de la dissolution.
	if (dissolve > 0.0) {
		float edge = smoothstep(dissolve + 0.06, dissolve, n);
		EMISSION += vec3(1.0, 0.3, 0.05) * edge * 3.0;
	}
}
