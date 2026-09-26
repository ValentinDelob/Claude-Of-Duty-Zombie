shader_type spatial;
// Surfaces procédurales du bunker (aucune texture externe). Les motifs sont
// calculés en coordonnées monde : continuité parfaite entre les morceaux de
// géométrie et aucun étirement.
//   pattern 0 béton · 1 carrelage · 2 planches · 3 tôle rivetée
//           4 mur peint deux tons · 5 pierre rituelle · 6 plafond à dalles
//           7 moquette · 8 boiserie + papier peint · 9 briques
//           10 velours plissé · 11 pavés
render_mode cull_back;

uniform int pattern = 0;
uniform vec4 color_a : source_color = vec4(0.35, 0.34, 0.32, 1.0);
uniform vec4 color_b : source_color = vec4(0.2, 0.26, 0.22, 1.0);
uniform float scale = 1.0;
uniform float paint_height = 1.25;
uniform float grime = 0.5;
uniform float roughness_base = 0.9;
uniform float metallic_base = 0.0;
uniform vec4 glow_color : source_color = vec4(0.8, 0.05, 0.02, 1.0);
uniform float glow = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = noise2(p) * 0.55;
	v += noise2(p * 2.07 + 13.1) * 0.3;
	v += noise2(p * 4.3 + 7.7) * 0.15;
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnorm);
	bool vertical = abs(n.y) < 0.5;
	// Coordonnées 2D de la surface.
	vec2 uv;
	if (vertical) {
		float along = abs(n.x) > abs(n.z) ? wpos.z : wpos.x;
		uv = vec2(along, wpos.y);
	} else {
		uv = wpos.xz;
	}
	uv *= scale;

	vec3 col = color_a.rgb;
	float rough = roughness_base;
	float metal = metallic_base;
	vec3 emi = vec3(0.0);
	float base_noise = fbm(uv * 1.7);

	if (pattern == 1) {
		// Carrelage 40 cm : joints sombres, teinte par carreau, carreaux cassés.
		vec2 t = uv / 0.4;
		vec2 id = floor(t);
		vec2 f = fract(t);
		float grout = step(0.94, max(f.x, f.y)) + step(max(f.x, f.y), 0.03);
		float tint = hash2(id) * 0.18;
		col = mix(color_a.rgb * (0.9 + tint), color_b.rgb, clamp(grout, 0.0, 1.0));
		float broken = step(0.93, hash2(id + 3.3)) * step(0.5, noise2(t * 5.0));
		col = mix(col, col * 0.35, broken);
		rough = mix(0.35, 0.9, grout + broken);
	} else if (pattern == 2) {
		// Planches de 22 cm, veinage étiré.
		float w = uv.y / 0.22;
		float plank = floor(w);
		float seam = step(0.93, fract(w));
		float grain = noise2(vec2(uv.x * 1.2, w * 9.0 + plank * 17.0));
		col = color_a.rgb * (0.75 + 0.3 * hash2(vec2(plank, 1.0)) + grain * 0.2);
		col = mix(col, color_b.rgb, seam * 0.8);
	} else if (pattern == 3) {
		// Tôles de 1 m, soudures et rivets, rouille.
		vec2 f = fract(uv);
		float seam = step(0.97, max(f.x, f.y));
		vec2 rv = fract(uv * 8.0) - 0.5;
		float rivet = step(length(rv), 0.12) * step(0.85, max(f.x, f.y) + (1.0 - min(f.x, f.y)) * 0.0);
		float rust = smoothstep(0.45, 0.75, fbm(uv * 2.3 + 5.0));
		col = mix(color_a.rgb, color_b.rgb, rust);
		col *= 1.0 - seam * 0.5;
		col += rivet * 0.05;
		metal = mix(0.6, 0.1, rust);
		rough = mix(0.45, 0.95, rust);
	} else if (pattern == 4) {
		// Mur peint : bas peint (color_b) au bord écaillé, haut en plâtre.
		float edge = paint_height + (noise2(vec2(uv.x * 3.0, 0.0)) - 0.5) * 0.12;
		float chip = step(0.72, fbm(uv * 3.1 + 2.0));
		float painted = step(wpos.y, edge) * (1.0 - chip * 0.9);
		col = mix(color_a.rgb * (0.85 + base_noise * 0.3), color_b.rgb * (0.9 + base_noise * 0.15), painted);
		// Liseré sombre à la limite de peinture.
		col *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.04, abs(wpos.y - edge)));
		// Coulures d'eau verticales.
		float streak = smoothstep(0.62, 0.9, noise2(vec2(uv.x * 6.0, uv.y * 0.35)));
		col *= 1.0 - streak * 0.35 * smoothstep(0.5, 3.0, wpos.y);
		rough = mix(0.95, 0.6, painted);
	} else if (pattern == 5) {
		// Blocs de pierre sombre et veines incandescentes.
		vec2 b = uv / vec2(0.8, 0.4);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = fract(b);
		float joint = step(0.95, max(f.x, f.y));
		col = color_a.rgb * (0.7 + hash2(floor(b)) * 0.4) * (1.0 - joint * 0.6);
		float vein = smoothstep(0.012, 0.0, abs(fbm(uv * 1.3) - 0.5)) * smoothstep(0.55, 0.7, noise2(uv * 0.5 + 4.0));
		emi = glow_color.rgb * vein * glow * (0.7 + 0.3 * sin(TIME * 1.5 + uv.x));
	} else if (pattern == 6) {
		// Plafond à dalles de 1,2 m.
		vec2 f = fract(uv / 1.2);
		float joint = step(0.96, max(f.x, f.y));
		col = color_a.rgb * (0.8 + base_noise * 0.4) * (1.0 - joint * 0.6);
	} else if (pattern == 7) {
		// Moquette de théâtre : trame fine, losanges d'une autre teinte, usure.
		vec2 d = uv / 0.9;
		vec2 dd = abs(fract(vec2(d.x + d.y, d.x - d.y) * 0.5) - 0.5);
		float motif = step(max(dd.x, dd.y), 0.08) + step(abs(max(dd.x, dd.y) - 0.3), 0.025);
		float weave = noise2(uv * 60.0) * 0.12;
		col = mix(color_a.rgb, color_b.rgb, clamp(motif, 0.0, 1.0)) * (0.9 + weave + base_noise * 0.15);
		float worn = smoothstep(0.55, 0.8, fbm(uv * 0.35 + 3.0));
		col = mix(col, col * vec3(0.55, 0.5, 0.45), worn * 0.7);
		rough = 1.0;
	} else if (pattern == 8) {
		// Boiserie (lambris jusqu'à paint_height) et papier peint damassé au-dessus.
		float edge = paint_height;
		if (wpos.y < edge) {
			vec2 p = vec2(uv.x / 0.9, wpos.y / edge);
			vec2 f = fract(p);
			float frame = step(0.9, f.x) + step(f.x, 0.1) + step(0.88, p.y) + step(p.y, 0.08);
			float grain = noise2(vec2(uv.x * 3.0, wpos.y * 40.0));
			col = color_b.rgb * (0.8 + grain * 0.35) * (1.0 - clamp(frame, 0.0, 1.0) * 0.35);
			rough = 0.55;
		} else {
			vec2 p = vec2(uv.x / 0.5, (wpos.y - edge) / 0.7);
			vec2 f = fract(p) - 0.5;
			float dam = smoothstep(0.26, 0.22, length(f * vec2(1.0, 1.6))) * (0.5 + 0.5 * sin(atan(f.y, f.x) * 6.0));
			float stripe = step(0.46, abs(f.x));
			col = color_a.rgb * (0.85 + base_noise * 0.25) * (1.0 + dam * 0.35 - stripe * 0.2);
			// Papier décollé par endroits (plâtre dessous).
			float peel = smoothstep(0.74, 0.8, fbm(uv * 1.1 + 17.0));
			col = mix(col, vec3(0.16, 0.14, 0.12) * (0.8 + base_noise * 0.3), peel);
			// Moulure dorée à la limite.
			float mould = 1.0 - smoothstep(0.0, 0.05, abs(wpos.y - edge - 0.03));
			col = mix(col, vec3(0.45, 0.33, 0.14), mould);
			metal = mould * 0.6;
			rough = mix(0.9, 0.4, mould);
		}
	} else if (pattern == 9) {
		// Briques 22 x 7 cm (ruelle), joints de mortier, briques noircies.
		vec2 b = uv / vec2(0.24, 0.08);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = fract(b);
		float joint = step(0.9, f.x) + step(0.82, f.y);
		float tint = hash2(floor(b));
		col = color_a.rgb * (0.7 + tint * 0.45) * (0.9 + base_noise * 0.2);
		col = mix(col, color_b.rgb, clamp(joint, 0.0, 1.0));
		col *= 1.0 - step(0.9, hash2(floor(b) + 7.1)) * 0.45;
	} else if (pattern == 10) {
		// Velours plissé (rideaux, fauteuils) : plis verticaux et lustre.
		float fold = 0.5 + 0.5 * sin(uv.x * 14.0 + noise2(vec2(uv.x * 2.0, uv.y * 0.3)) * 2.0);
		col = mix(color_b.rgb, color_a.rgb, fold) * (0.85 + base_noise * 0.25);
		rough = 0.8;
	} else if (pattern == 11) {
		// Pavés de la ruelle : blocs arrondis, joints boueux, flaques.
		vec2 b = uv / vec2(0.3, 0.22);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = abs(fract(b) - 0.5);
		float joint = smoothstep(0.36, 0.48, max(f.x, f.y));
		col = color_a.rgb * (0.7 + hash2(floor(b)) * 0.5);
		col = mix(col, color_b.rgb, joint);
		float puddle = smoothstep(0.6, 0.7, fbm(uv * 0.5 + 11.0));
		rough = mix(mix(0.8, 1.0, joint), 0.12, puddle);
		col = mix(col, col * 0.55, puddle);
	} else {
		// Béton brut : marbrures, fissures, taches.
		col = color_a.rgb * (0.75 + base_noise * 0.5);
		float crack = smoothstep(0.006, 0.0, abs(noise2(uv * 1.1 + 9.0) - 0.5)) * step(0.62, noise2(uv * 0.4));
		col *= 1.0 - crack * 0.4;
	}

	// Crasse commune : taches sombres et assombrissement au pied des murs.
	float stain = smoothstep(0.58, 0.8, fbm(uv * 0.6 + 31.0));
	col = mix(col, col * vec3(0.4, 0.33, 0.28), stain * grime);
	if (vertical) {
		col *= mix(1.0, 0.45 + 0.55 * smoothstep(0.0, 0.6, wpos.y), grime);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emi;
}
