// Corps commun des shaders de zombie (zombie.gdshader, zombie_dissolve.gdshader).
// Couleur par sommet, matière par pièce (UV2.y : 0 tissu, 1 peau, 2 cuir,
// 3 métal, 4 plaie/sang, 5 os/dents), bruit calculé sur la position de REPOS
// (UV.xy, UV2.x : les taches ne glissent pas pendant l'animation), yeux
// émissifs (alpha du sommet), flash de touche (uniforms par instance).
// DISSOLVE (variante des corps qui se dissolvent) : `discard`. Un shader sans
// `discard` garde la pré-passe de profondeur et les passes d'ombre simples
// (ce fragment n'y est pas exécuté) : les zombies vivants n'en paient pas le
// coût (voir docs/ARCHITECTURE.md, « Rendu et performances »).

uniform vec4 emission_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float emission_energy = 8.0;
uniform float grime = 0.35;
uniform float stain_amount = 0.75;
instance uniform float hit_flash = 0.0;
instance uniform float dissolve = 0.0;
instance uniform float eye_glow = 1.0;
// Modèle CUBIQUE (ZombieModel.MODEL_CUBE, côté d'un cube en m ; 0 : zombies
// procéduraux) : la couleur de la face (COLOR_0, palette validée) est gardée
// telle quelle, sans crasse ni marbrures ; seule la dissolution lit un
// tirage, un par CUBE (normale de repos en CUSTOM0, ZombieGlb) : le corps
// disparaît cube par cube.
uniform float voxel_cell = 0.0;
// Teinte de variante (modèle cubique, ZombieModel.MODEL_TINTS) : blouse
// (rgb) et peau (a).
instance uniform vec4 look_tint = vec4(1.0);

varying vec3 rest_pos;
varying float mat_id;
varying vec3 rest_n;

// Treillis de valeurs aléatoires (NoiseLattice.tex3d, 32³, un texel par
// nœud) : le filtrage trilinéaire lu en i + s(f) donne le bruit de valeur
// lissé en UNE lecture au lieu de 8 hachages.
uniform sampler3D noise_lattice : filter_linear, repeat_enable;

float vnoise(vec3 p) {
#ifdef FLAT_NOISE
	return 0.5;  // mesure du coût du bruit (tests/autotest/perf_costs.gd)
#endif
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return textureLod(noise_lattice, (i + f + 0.5) / 32.0, 0.0).r;
}

void vertex() {
	rest_pos = vec3(UV.x, UV.y, UV2.x);
	mat_id = UV2.y;
	rest_n = CUSTOM0.rgb * 2.0 - 1.0;
}

void fragment() {
	vec3 p = rest_pos;
	if (voxel_cell > 0.0) {
		// Cube du fragment : un demi-cube sous la face, vers l'intérieur.
		vec3 cell = floor(p / voxel_cell - rest_n * 0.5);
		float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
#ifdef DISSOLVE
		if (h < dissolve) {
			discard;
		}
#endif
		float vm = floor(mat_id + 0.5);
		vec3 vcol = COLOR.rgb;
		if (vm < 0.5) {
			vcol *= look_tint.rgb;
		} else if (vm < 1.5) {
			vcol *= look_tint.a;
		}
		bool wet = vm > 3.5 && vm < 4.5;
		ALBEDO = mix(vcol, vec3(1.0, 0.2, 0.15), hit_flash * 0.6);
		ROUGHNESS = wet ? 0.3 : 0.85;
		SPECULAR = wet ? 0.6 : 0.3;
		METALLIC = 0.0;
		EMISSION = emission_color.rgb * emission_energy * (1.0 - COLOR.a) * eye_glow + vec3(0.6, 0.05, 0.02) * hit_flash;
#ifdef DISSOLVE
		// Cubes au bord de la dissolution : braise.
		EMISSION += vec3(1.0, 0.3, 0.05) * step(h, dissolve + 0.08) * 3.0;
#endif
	} else {
	// Zombies procéduraux (repli) : crasse, marbrures, sang peint.
	float n = vnoise(p * 14.0) * 0.6 + vnoise(p * 41.0) * 0.4;
#ifdef DISSOLVE
	if (n < dissolve) {
		discard;
	}
#endif
	vec3 col = COLOR.rgb;
	float rough = 0.9;
	float spec = 0.35;
	float metal = 0.0;
	// Matière = partie entière ; fraction (0..0,45) = sang peint du sommet.
	float m = floor(mat_id + 0.5);
	float bl = clamp((mat_id - m) / 0.45, 0.0, 1.0);
	// Grandes taches (sang séché, boue) communes à toutes les matières.
	float big = vnoise(p * 6.0 + 11.0);
	float blot = smoothstep(0.6, 0.72, big);
	if (m < 0.5) {
		// Tissu : crasse, usure, sang séché brun.
		col *= (1.0 - grime + grime * n * 1.4);
		col = mix(col, col * vec3(0.4, 0.12, 0.08), blot * stain_amount);
		// Crasse plus forte en bas (ourlets, bas de pantalon).
		col *= mix(0.7, 1.0, smoothstep(0.1, 0.6, p.y));
		rough = 0.95;
		spec = 0.25;
	} else if (m < 1.5) {
		// Peau morte : marbrures grises, veines sombres, ecchymoses violacées.
		float mottle = n;
		col *= 0.78 + 0.4 * mottle;
		float vein = 1.0 - smoothstep(0.0, 0.045, abs(vnoise(p * 9.0 + 3.0) - 0.5));
		col = mix(col, col * vec3(0.45, 0.4, 0.5), vein * 0.6);
		float bruise = smoothstep(0.38, 0.55, big) * (1.0 - blot);
		col = mix(col, col * vec3(0.55, 0.42, 0.5), bruise * 0.7);
		col = mix(col, col * vec3(0.45, 0.08, 0.06), blot * stain_amount * 0.8);
		rough = 0.55;
		spec = 0.45;
	} else if (m < 2.5) {
		// Cuir : patiné, légèrement brillant.
		col *= 0.8 + 0.35 * n;
		rough = 0.45 + 0.3 * n;
		spec = 0.5;
	} else if (m < 3.5) {
		// Métal peint (casques, boucles) : peinture écaillée.
		float chip = smoothstep(0.78, 0.84, vnoise(p * 70.0));
		col = mix(col * (0.85 + 0.25 * n), vec3(0.2, 0.19, 0.18), chip);
		metal = mix(0.25, 0.8, chip);
		rough = mix(0.55, 0.35, chip);
		spec = 0.5;
	} else if (m < 4.5) {
		// Plaie, sang frais : rouge profond humide.
		col *= 0.65 + 0.7 * n;
		rough = 0.18 + 0.25 * n;
		spec = 0.65;
	} else {
		// Os, dents : jaunis, crasse dans les creux (peu tachés de sang).
		col *= 0.7 + 0.45 * n;
		rough = 0.6;
		spec = 0.4;
		bl *= 0.45;
	}
	// Sang peint : bord irrégulier (bruit), coulures sombres, reflet humide.
	if (bl > 0.0) {
		float bm = smoothstep(0.32, 0.5, bl * (0.55 + 0.9 * n));
		vec3 bc = mix(vec3(0.07, 0.008, 0.006), vec3(0.2, 0.018, 0.012), big);
		col = mix(col, bc, bm);
		rough = mix(rough, 0.28, bm * 0.8);
		spec = mix(spec, 0.6, bm);
		metal = mix(metal, 0.0, bm);
	}
	float emissive = 1.0 - COLOR.a;
	ALBEDO = mix(col, vec3(1.0, 0.2, 0.15), hit_flash * 0.6);
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = metal;
	EMISSION = emission_color.rgb * emission_energy * emissive * eye_glow + vec3(0.6, 0.05, 0.02) * hit_flash;
#ifdef DISSOLVE
	// Bord brûlant de la dissolution.
	float edge = smoothstep(dissolve + 0.06, dissolve, n);
	EMISSION += vec3(1.0, 0.3, 0.05) * edge * 3.0;
#endif
	}
}
