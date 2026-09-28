shader_type spatial;
// Machines d'atouts (modèles de tools/blender/props/perk_machines.py) :
// peinture émaillée usée (taches de rouille, crasse au pied, coulures),
// chromes piqués, panneaux lumineux pilotés par le courant.
// Motifs en coordonnées de l'objet : ils suivent la machine (envol de
// LAZARUS TONIC) et diffèrent d'une machine à l'autre par `seed`.
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness_base = 0.5;
uniform float metallic_base = 0.0;
// Usure : 0 = neuf, 1 = très rouillé.
uniform float wear = 0.5;
uniform vec4 rust_color : source_color = vec4(0.23, 0.12, 0.06, 1.0);
// Énergie d'émission une fois allumé (0 : pièce non lumineuse).
uniform float glow = 0.0;
// Teinte éteinte des pièces lumineuses (1 = inchangée).
uniform float off_dim = 1.0;
uniform sampler2D noise_lattice : filter_linear, repeat_enable;
// 0 = éteint, 1 = allumé (par machine : PerkMachine._refresh).
instance uniform float lit = 0.0;
instance uniform float seed = 0.0;

varying vec3 opos;
varying vec3 onorm;

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return textureLod(noise_lattice, (i + f + 0.5) / 64.0, 0.0).r;
}

float fbm(vec2 p) {
	float v = noise2(p) * 0.55;
	v += noise2(p * 2.07 + 13.1) * 0.3;
	v += noise2(p * 4.3 + 7.7) * 0.15;
	return v;
}

void vertex() {
	opos = VERTEX;
	onorm = NORMAL;
}

void fragment() {
	vec3 n = normalize(onorm);
	vec2 uv = abs(n.y) > 0.6 ? opos.xz : vec2(abs(n.x) > abs(n.z) ? opos.z : opos.x, opos.y);
	uv += vec2(seed * 7.31, seed * 3.17);
	// Taches de rouille (plus nombreuses en bas et sur les arêtes basses).
	float h = clamp(opos.y / 2.2, 0.0, 1.0);
	float r = fbm(uv * 6.0);
	float rust = smoothstep(0.62 - wear * 0.22 + h * 0.08, 0.72 - wear * 0.2 + h * 0.08, r) * wear;
	// Coulures verticales et crasse au pied.
	float streak = smoothstep(0.55, 0.85, noise2(vec2(uv.x * 18.0, uv.y * 0.9))) * 0.35;
	float foot = 1.0 - smoothstep(0.0, 0.45, opos.y);
	float dirt = clamp(streak * wear + foot * 0.6 * wear + (fbm(uv * 2.5 + 19.0) - 0.5) * 0.4, 0.0, 1.0);
	vec3 base = albedo.rgb * mix(off_dim, 1.0, lit);
	vec3 col = mix(base, base * vec3(0.55, 0.5, 0.45), dirt);
	col = mix(col, rust_color.rgb * (0.7 + r * 0.5), rust);
	ALBEDO = col;
	ROUGHNESS = mix(roughness_base, 0.95, max(rust, dirt * 0.6));
	METALLIC = mix(metallic_base, 0.2, rust);
	// Panneau éclairé de l'intérieur : la crasse et la rouille voilent la lumière.
	EMISSION = albedo.rgb * glow * lit * (1.0 - rust * 0.8) * (1.0 - dirt * 0.5);
}
