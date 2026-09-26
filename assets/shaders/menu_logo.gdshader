shader_type canvas_item;
// Logo du menu : le texte et l'emblème sont dessinés une fois dans une
// SubViewport ; ce shader les use (bords rongés, trous, rayures, crasse),
// les éclabousse de sang, fait couler des gouttes sous les lettres rouges
// et ajoute des parasites occasionnels (tranches décalées, couches RVB).

uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform vec4 blood : source_color = vec4(0.42, 0.02, 0.02, 1.0);
uniform vec4 blood_wet : source_color = vec4(0.72, 0.06, 0.04, 1.0);
uniform float drip_amount = 1.0;

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.5 + noise(p * 2.03 + 11.7) * 0.3 + noise(p * 4.11 + 3.1) * 0.2;
}

// Vrai si le texel est une lettre rouge (« ZOMBIE », sang de l'emblème).
float redness(vec4 s) {
	vec3 c = s.rgb / max(s.a, 0.001);
	return step(0.5, s.a) * step(0.3, c.r) * step(c.g, 0.16);
}

void fragment() {
	vec2 uv = UV;
	vec2 px = TEXTURE_PIXEL_SIZE;
	float t = TIME;
	float frame = floor(t * 20.0);
	// Parasites : tranches horizontales décalées.
	if (glitch > 0.001) {
		float row = floor(uv.y * 18.0);
		float r = hash12(vec2(row, frame));
		uv.x += step(1.0 - 0.45 * glitch, r) * (hash12(vec2(frame, row)) - 0.5) * 0.05 * glitch;
	}
	// Bords déchiquetés : l'échantillon est légèrement déplacé par du bruit.
	vec2 wob = (vec2(noise(uv * vec2(260.0, 100.0)), noise(uv * vec2(260.0, 100.0) + 17.0)) - 0.5) * px * 3.0;
	vec4 s = texture(TEXTURE, uv + wob);
	float split = (0.0015 + glitch * 0.012);
	float ar = texture(TEXTURE, uv + wob + vec2(split, 0.0)).a;
	float ab = texture(TEXTURE, uv + wob - vec2(split, 0.0)).a;
	float a = s.a;
	vec3 col = s.rgb / max(a, 0.001);
	float red = redness(s);

	// Usure : zones rongées, piqûres, rayures fines.
	float n1 = fbm(uv * vec2(26.0, 10.0));
	float n2 = noise(uv * vec2(420.0, 170.0));
	float wear = smoothstep(0.68, 0.74, n1 * 0.72 + n2 * 0.4);
	float sc = abs(fract(dot(uv, vec2(7.0, 2.2)) * 7.0 + noise(uv * vec2(6.0, 3.0)) * 3.0) - 0.5);
	float scratch = (1.0 - smoothstep(0.0, 0.012, sc)) * step(0.6, noise(uv * vec2(4.0, 9.0) + 2.0));
	float pits = step(0.9, noise(uv * vec2(700.0, 280.0)));
	float keep = (1.0 - wear) * (1.0 - scratch * 0.95) * (1.0 - pits * 0.8);
	a *= keep;
	// Crasse et variations de peinture.
	col *= 0.62 + 0.5 * fbm(uv * vec2(40.0, 16.0) + 4.0);
	// Éclaboussures de sang sur les lettres claires.
	float spl = smoothstep(0.7, 0.76, fbm(uv * vec2(16.0, 7.0) + 5.0) + noise(uv * vec2(120.0, 50.0)) * 0.12);
	col = mix(col, blood.rgb, spl * (1.0 - red) * 0.9);
	// Sang plus sombre et « mouillé » sur les lettres rouges.
	col = mix(col, mix(blood_wet.rgb, blood.rgb, noise(uv * vec2(60.0, 25.0)) * 0.7), red * 0.5);

	// Coulures sous les lettres rouges.
	float drip = 0.0;
	float gloss = 0.0;
	float colw = px.x * 9.0;
	float cid = floor(uv.x / colw);
	float h = hash12(vec2(cid, 3.7));
	if (drip_amount > 0.0 && h > 0.68 && a < 0.5) {
		float h2 = hash12(vec2(cid, 9.1));
		float len = (0.025 + 0.15 * h2 * h2) * drip_amount * (0.92 + 0.08 * sin(t * 0.21 + h * 40.0));
		float cx = (cid + 0.5) * colw + (h2 - 0.5) * colw * 0.4;
		float found = -1.0;
		for (int i = 1; i <= 18; i++) {
			float d = float(i) / 18.0 * len;
			vec4 up = texture(TEXTURE, vec2(cx, uv.y - d));
			if (redness(up) > 0.5) {
				found = d;
				break;
			}
		}
		if (found > 0.0) {
			float k = found / len;
			float half_w = colw * (0.42 - 0.26 * k);
			// Goutte arrondie au bout.
			float tip = smoothstep(0.82, 1.0, k);
			half_w += colw * 0.2 * tip * (1.0 - smoothstep(0.96, 1.0, k));
			float dx = abs(uv.x - cx);
			drip = 1.0 - smoothstep(half_w * 0.75, half_w, dx);
			drip *= 1.0 - smoothstep(0.97, 1.0, k);
			gloss = (1.0 - smoothstep(0.0, half_w * 0.35, abs(uv.x - cx + half_w * 0.35))) * 0.6;
		}
	}
	vec3 drip_col = mix(blood.rgb * 0.8, blood_wet.rgb, gloss);
	col = mix(col, drip_col, drip);
	a = max(a, drip);

	// Ombre portée sombre (lisibilité sur la 3D).
	float sh = texture(TEXTURE, uv - px * vec2(4.0, 5.0)).a * keep;
	vec3 outc = col;
	float outa = a;
	outa = max(a, sh * 0.55);
	outc = mix(vec3(0.0), col, a / max(outa, 0.001));
	// Couches rouge / bleue séparées (surtout pendant les parasites).
	outc.r += (ar - s.a) * 0.25 * (0.3 + glitch);
	outc.b += (ab - s.a) * 0.3 * glitch;
	// Scintillement pendant les parasites.
	outa *= 1.0 - glitch * 0.35 * step(0.5, hash12(vec2(frame, 1.0)));
	COLOR = vec4(max(outc, 0.0), clamp(outa, 0.0, 1.0) * v_mod.a);
}
