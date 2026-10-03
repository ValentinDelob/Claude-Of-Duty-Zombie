shader_type spatial;
// Boîte mystère (modèle de tools/blender/props/mystery_box.py) : bois de
// caisse usé (fil, cernes, nœuds, teinte propre à chaque planche, arêtes
// éclaircies par l'usure, crasse au pied), fers noircis piqués de rouille,
// laiton terni, peinture de pochoir écaillée, fond qui s'éclaire à l'ouverture.
// UV en mètres, u dans le sens du fil ; UV2.x : tirage propre à la planche.
// Le relief du fil passe par la normale (dérivées écran), sans texture.
render_mode cull_back;

// 0 bois, 1 fer, 2 laiton, 3 peinture, 4 intérieur sombre, 5 fond lumineux.
uniform int part = 0;
uniform vec4 albedo : source_color = vec4(0.36, 0.23, 0.13, 1.0);
uniform float roughness_base = 0.85;
uniform float metallic_base = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.6, 1.0);
uniform float glow_energy = 3.0;
uniform sampler2D noise_lattice : filter_linear, repeat_enable;
// 0 = fermée, 1 = ouverte (MysteryBox._animate, par boîte).
instance uniform float open = 0.0;

varying vec3 onorm;
varying float oy;

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
	onorm = NORMAL;
	oy = VERTEX.y;
}

// Relief : perturbe la normale (espace vue) selon la hauteur h.
vec3 bump(vec3 n, vec3 pos, float h, float k) {
	vec3 dp1 = dFdx(pos);
	vec3 dp2 = dFdy(pos);
	float dh1 = dFdx(h);
	float dh2 = dFdy(h);
	vec3 r1 = cross(dp2, n);
	vec3 r2 = cross(n, dp1);
	float det = dot(dp1, r1);
	vec3 grad = sign(det) * (dh1 * r1 + dh2 * r2);
	// Dérivées dégénérées (bords de triangle en MSAA, qualité HAUTE) : le
	// vecteur peut être nul, et normalize() d'un nul donne NaN, que le glow
	// étale en tache blanche. Repli sur la normale sans relief. Seuil absolu
	// minuscule : |b|² vaut ~1e-12 pour un pixel de 1 mm (det ~ pixel²).
	vec3 b = abs(det) * n - grad * k;
	float l2 = dot(b, b);
	return l2 > 1e-30 ? b * inversesqrt(l2) : n;
}

void fragment() {
	vec3 an = abs(normalize(onorm));
	// Faces de chanfrein (normale de biais) : arêtes usées.
	float edge = 1.0 - smoothstep(0.86, 0.97, max(an.x, max(an.y, an.z)));
	float s = UV2.x;
	vec2 uv = UV;
	float dist = length(VERTEX);
	// Le relief s'efface au loin (pas de scintillement).
	float near = 1.0 - smoothstep(6.0, 14.0, dist);
	float foot = 1.0 - smoothstep(0.02, 0.3, oy);
	vec3 col;
	float rough = roughness_base;
	float metal = metallic_base;
	float h = 0.0;
	vec3 emit = vec3(0.0);
	if (part == 0 || part == 4) {
		// Fil du bois : cernes étirés dans le sens u, ondulés.
		float warp = fbm(vec2(uv.x * 1.3, uv.y * 7.0) + s * 31.0);
		float rings = fract((uv.y + warp * 0.06 + s) * (22.0 + s * 26.0));
		float ring = smoothstep(0.0, 0.25, rings) * (1.0 - smoothstep(0.55, 1.0, rings));
		float fibre = noise2(vec2(uv.x * 2.5, uv.y * 160.0) + s * 17.0);
		// Nœud de temps en temps (tache sombre en ellipse).
		vec2 kc = vec2(uv.x * 2.2, uv.y * 9.0) + s * 7.0;
		float knot = smoothstep(0.82, 0.92, noise2(kc * 0.9));
		float grain = ring * 0.55 + fibre * 0.45;
		// Teinte propre à chaque planche (clair/sombre, plus ou moins rouge).
		vec3 tint = vec3(0.82 + s * 0.36, 0.84 + s * 0.3, 0.86 + fract(s * 7.3) * 0.25);
		vec3 base = albedo.rgb * tint;
		col = mix(base * 0.62, base * 1.08, grain);
		col = mix(col, base * 0.45, knot * 0.5);
		// Taches d'humidité et crasse (pied du coffre, coins).
		float stain = smoothstep(0.45, 0.8, fbm(uv * vec2(1.6, 4.0) + s * 11.0));
		col *= 1.0 - stain * 0.2 - foot * 0.35;
		// Arêtes : bois mis à nu, plus clair et plus sec.
		float wear = edge * (0.5 + 0.5 * noise2(uv * 40.0 + s * 3.0));
		col = mix(col, albedo.rgb * vec3(1.2, 1.1, 1.0), wear * 0.35);
		rough = mix(roughness_base, 0.97, wear);
		h = grain * 0.6 + fibre * 0.4 - knot * 0.5;
		if (part == 4) {
			col = albedo.rgb * (0.7 + grain * 0.5);
			// Reflet du fond lumineux sur les parois intérieures.
			emit = glow_color.rgb * open * 0.04;
		}
	} else if (part == 1 || part == 2) {
		// Fer noirci / laiton terni : rouille en plaques, arêtes polies.
		vec2 p = uv * 9.0 + s * 5.0;
		float r = fbm(p);
		float rust = smoothstep(0.6, 0.72, r + foot * 0.12) * (part == 1 ? 0.85 : 0.4);
		float pit = noise2(uv * 70.0 + s * 9.0);
		vec3 rust_col = part == 1 ? vec3(0.12, 0.065, 0.035) : vec3(0.14, 0.15, 0.09);
		col = albedo.rgb * (0.8 + pit * 0.35);
		col = mix(col, rust_col * (0.75 + r * 0.4), rust);
		float shine = edge * 0.8;
		col = mix(col, albedo.rgb * (part == 1 ? 1.8 : 1.4), shine * (1.0 - rust));
		rough = mix(roughness_base, 0.9, rust) - shine * 0.15;
		metal = mix(metallic_base, 0.2, rust);
		h = pit * 0.5 + rust * 0.6;
	} else if (part == 3) {
		// Peinture de pochoir : écaillée (bois dessous), voilée de crasse.
		float chip = fbm(uv * 28.0 + s * 9.0);
		float flake = smoothstep(0.69, 0.73, chip + noise2(uv * 90.0) * 0.1);
		float dirt = fbm(uv * 3.0 + 4.0);
		vec3 paint = albedo.rgb * (0.82 + dirt * 0.25);
		vec3 wood = vec3(0.12, 0.075, 0.045);
		col = mix(paint, wood, flake);
		col *= 1.0 - foot * 0.3;
		rough = mix(roughness_base, 0.9, flake);
		h = 1.0 - flake;
	} else {
		// Fond lumineux : éteint couvercle fermé, vif pendant le tirage.
		col = vec3(0.02);
		float ripple = 0.85 + 0.15 * noise2(uv * 6.0 + TIME * 0.6);
		emit = glow_color.rgb * glow_energy * open * ripple;
		rough = 1.0;
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = metal;
	EMISSION = emit;
	NORMAL = bump(NORMAL, VERTEX, h * near, part == 3 ? 0.0006 : 0.0012);
}
