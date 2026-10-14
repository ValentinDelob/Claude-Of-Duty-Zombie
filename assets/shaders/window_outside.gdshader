shader_type spatial;
// « Dehors » d'une fenêtre barricadée (WindowOutside) : UNE carte plane posée
// sur le mur du fond de la poche, qui dessine tout ce qu'on voit au-delà :
//   - fenêtre (mode 0) : vitres (intactes, fêlées, cassées, crasse) et, derrière,
//     un dehors brumeux rétroéclairé bleu-vert où passent des silhouettes de
//     zombies (marche, parfois l'un vient se coller à la vitre puis repart) ;
//   - porte (mode 1) : un couloir sombre qui s'enfonce (faux volume par
//     lancer de rayon dans une boîte), néon qui grésille au fond, silhouettes
//     qui traversent sa lumière.
// Profondeur simulée par parallaxe (rayon de la caméra dans le repère de la
// carte) : rien n'est dessiné en vrai derrière le mur. Silhouettes et décor
// sur une grille de 5 cm (style cubique), noyés dans la brume selon leur
// profondeur : on les lit comme lointains et flous, jamais comme de vrais
// zombies. Tout est paramétré par instance (un seul matériau partagé).
render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled;

instance uniform vec4 wo_seed = vec4(0.1, 0.4, 0.7, 0.9);
// Activité des silhouettes (0 : aucune ; 1 : manche en cours).
instance uniform float wo_activity = 1.0;
instance uniform vec4 wo_tint : source_color = vec4(0.30, 0.62, 0.66, 1.0);
// Taille de la carte (m) ; hauteur du milieu de la carte au-dessus du sol.
instance uniform vec2 wo_size = vec2(1.6, 1.3);
instance uniform float wo_floor = 1.6;
// 0 fenêtre, 1 porte (couloir).
instance uniform float wo_mode = 0.0;
// Vitres : colonnes, rangées ; vitres cassées (bits), fêlées (bits).
instance uniform vec2 wo_panes = vec2(3.0, 2.0);
instance uniform float wo_broken = 0.0;
instance uniform float wo_cracked = 0.0;
// 0 : image fixe (préréglage LOW, aucune silhouette ni grésillement).
instance uniform float wo_live = 1.0;

const float CELL = 0.05;
const int FIGURES = 5;

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Membre : pavé de demi-largeur `w`, longueur `len`, qui part du pivot `piv`
// dans la direction d'angle `a` (0 : vers le bas).
float sd_limb(vec2 q, vec2 piv, float a, float len, float w) {
	vec2 l = rot(q - piv, -a);
	return sd_box(l - vec2(0.0, -len * 0.5), vec2(w, len * 0.5));
}

bool bit(float mask, float i) {
	return mod(floor(mask / exp2(i)), 2.0) > 0.5;
}

// Silhouette de zombie, pieds en (0, 0), m. `dir` : sens de la marche (+1 / -1),
// `ph` : phase du pas, `front` : 0 de profil (marche), 1 de face (collé à la
// vitre, bras levés). Distance signée (négative dedans).
float figure(vec2 q, float dir, float ph, float front, float t, float var) {
	q.x *= dir;
	float bob = abs(sin(ph)) * 0.03;
	float s = sin(ph);
	// De profil : jambes qui balancent, buste penché, bras tendus devant.
	float side = sd_limb(q, vec2(0.0, 0.86), s * 0.42, 0.86, 0.07);
	side = min(side, sd_limb(q, vec2(-0.02, 0.86), -s * 0.42, 0.86, 0.07));
	side = min(side, sd_box(rot(q - vec2(0.03, 1.16 + bob), 0.2 + var * 0.1), vec2(0.13, 0.3)));
	side = min(side, sd_box(q - vec2(0.16, 1.52 + bob - var * 0.06), vec2(0.11, 0.12)));
	float arm = 1.3 + sin(ph * 0.5 + var * 6.0) * 0.12;
	side = min(side, sd_limb(q, vec2(0.1, 1.38 + bob), arm, 0.6, 0.05));
	side = min(side, sd_limb(q, vec2(0.04, 1.36 + bob), arm - 0.18 - var * 0.3, 0.58, 0.05));
	// De face : bras levés, mains sur la vitre, balancement.
	float sw = sin(t * 1.7 + var * 5.0) * 0.04;
	vec2 qf = q - vec2(sw, 0.0);
	float fr = sd_box(qf - vec2(-0.1, 0.43), vec2(0.07, 0.43));
	fr = min(fr, sd_box(qf - vec2(0.1, 0.43), vec2(0.07, 0.43)));
	fr = min(fr, sd_box(qf - vec2(0.0, 1.17), vec2(0.2, 0.31)));
	fr = min(fr, sd_box(qf - vec2(sw * 0.5, 1.6), vec2(0.11, 0.12)));
	float rise = sin(t * 2.3 + var * 3.0) * 0.08;
	fr = min(fr, sd_limb(qf, vec2(0.17, 1.42), 2.75 + rise, 0.52, 0.05));
	fr = min(fr, sd_limb(qf, vec2(-0.17, 1.42), -2.65 + rise * 0.7, 0.52, 0.05));
	return mix(side, fr, front);
}

// Dehors (fenêtre) à la hauteur `y` (m, depuis le sol) et à l'abscisse `x`
// d'un plan lointain : brume rétroéclairée, plus claire en haut, sol sombre.
vec3 sky(vec2 p, vec3 tint) {
	float y = p.y;
	float glow = 0.22 + 0.62 * smoothstep(0.2, 3.4, y);
	// Grande source diffuse (lampadaire, lune derrière la brume), placée selon la graine.
	vec2 src = vec2((wo_seed.z - 0.5) * 6.0, 3.4);
	glow += 0.55 * exp(-length((p - src) * vec2(0.3, 0.45)));
	vec3 c = tint * glow;
	// Grillage lointain : poteaux de 20 cm tous les 2,4 m, à peine plus sombres
	// (de la matière dans la brume, sans encombrer).
	float post = abs(fract(p.x / 2.4 + wo_seed.w) - 0.5) * 2.4;
	if (post < 0.1 && y < 2.2) {
		c = mix(c, tint * 0.3, 0.3);
	}
	// Sol.
	if (y < 0.0) {
		c = tint * (0.22 + 0.1 * exp(y));
	}
	return c;
}

// Couloir sombre (porte) : rayon `rd` depuis le point `p0` de la carte ; rend
// la couleur et la profondeur (m) du point touché.
vec3 corridor(vec2 p0, vec3 rd, vec3 tint, float t, out float hit_d) {
	float hw = wo_size.x * 0.5 + 0.15;
	float floor_y = -wo_floor;
	float ceil_y = floor_y + 2.4;
	float len = 7.0;
	float dz = max(-rd.z, 0.05);
	float tx = rd.x > 0.0 ? (hw - p0.x) / rd.x : (-hw - p0.x) / min(rd.x, -1e-4);
	float ty = rd.y > 0.0 ? (ceil_y - p0.y) / rd.y : (floor_y - p0.y) / min(rd.y, -1e-4);
	float tz = len / dz;
	float th = min(min(tx, ty), tz);
	vec3 hp = vec3(p0, 0.0) + rd * th;
	hit_d = -hp.z;
	// Néon au plafond, au fond (grésille).
	vec3 lamp = vec3(0.0, ceil_y - 0.1, -4.6);
	float flick = 1.0;
	if (wo_live > 0.5) {
		float k = floor(t * 9.0);
		flick = h11(k + wo_seed.x * 50.0) > 0.18 ? 1.0 : 0.15;
		flick *= 0.85 + 0.15 * sin(t * 50.0);
	}
	vec3 lamp_col = vec3(0.75, 0.9, 0.7) * flick;
	vec3 to = lamp - hp;
	float att = 1.0 / (1.0 + dot(to, to) * 1.8);
	// Grille de 20 cm (dalles, briques) ; plus sombre au loin.
	vec3 cell = floor(hp / 0.2);
	float tex = 0.85 + 0.3 * h21(cell.xz + cell.y * 7.0);
	vec3 base = tint * 0.06 * tex;
	vec3 c = base + lamp_col * att * 0.7 * tex;
	// Tube du néon lui-même.
	if (abs(hp.y - (ceil_y)) < 0.01 && abs(hp.z - lamp.z) < 0.6 && abs(hp.x) < 0.08) {
		c = lamp_col * 2.2;
	}
	// Mur du fond : porte entrouverte, rien qu'une fente plus claire.
	if (th == tz) {
		c *= 0.6;
		if (abs(hp.x - 0.3) < 0.06 && hp.y < floor_y + 2.0) {
			c += tint * 0.5 * flick;
		}
	}
	return c * exp(-hit_d * 0.08);
}

varying vec3 v_local;
varying vec3 v_cam;

void vertex() {
	v_local = VERTEX;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

// Silhouettes : FIGURES places, chacune rejoue des cycles (période, sens,
// profondeur, comportement tirés de la graine de la fenêtre et du n° de
// cycle). Composées sur `c` (vue depuis le point `p0` de la carte suivant
// `rd`), noyées dans la brume `haze` selon leur profondeur.
vec3 figures(vec3 c, vec2 p0, vec3 rd, vec3 tint, float t, float max_d, float frost, out float eye) {
	eye = 0.0;
	float dz = max(-rd.z, 0.12);
	float half_w = wo_size.x * 0.5;
	for (int k = 0; k < FIGURES; k++) {
		float fk = float(k);
		float period = mix(9.0, 16.0, h11(fk * 3.7 + wo_seed.x * 91.0));
		float tt = t + period * h11(fk * 5.3 + wo_seed.y * 47.0) + 13.0 * fk;
		float cyc = floor(tt / period);
		float f = fract(tt / period);
		float hc = h21(vec2(cyc, fk) + wo_seed.xy * 37.0);
		// Présence : les premières places tournent plus souvent ; l'activité
		// (calme entre deux manches, fenêtre forcée) en éteint en fondu.
		float need = 0.06 + 0.15 * fk + 0.2 * hc;
		float pres = smoothstep(need - 0.12, need + 0.12, wo_activity);
		if (pres <= 0.003) {
			continue;
		}
		float dir = h21(vec2(cyc, fk + 9.0) + wo_seed.zw * 13.0) < 0.5 ? -1.0 : 1.0;
		float var = h21(vec2(cyc, fk + 4.0) + wo_seed.wx * 7.0);
		// Une place sur deux colle parfois son zombie à la vitre (fenêtres).
		bool press = wo_mode < 0.5 && k < 2 && h21(vec2(cyc, fk + 17.0) + wo_seed.yz * 5.0) < 0.38;
		float d;
		float x;
		float front = 0.0;
		float walk_ph;
		if (press) {
			float x0 = (h21(vec2(cyc, fk + 23.0)) - 0.5) * wo_size.x * 0.6;
			float a = smoothstep(0.0, 0.35, f);
			float b = smoothstep(0.72, 1.0, f);
			d = mix(mix(3.2, 0.1, a), 3.6, b);
			float from_x = x0 - dir * (half_w + 2.4);
			x = mix(mix(from_x, x0, a), x0 + dir * (half_w + 2.6), b);
			front = smoothstep(0.22, 0.36, f) * (1.0 - smoothstep(0.72, 0.8, f));
			walk_ph = tt * 4.2;
		} else {
			// Traverse de part en part pendant 70 % du cycle, rien ensuite.
			float span = 0.75;
			if (f > span) {
				continue;
			}
			float u = f / span;
			d = wo_mode < 0.5 ? mix(0.5, 3.4, var) : mix(4.0, 5.4, var);
			float reach = (wo_mode < 0.5 ? half_w + d * 0.9 : wo_size.x * 0.5 + 0.4) + 0.6;
			x = dir * mix(-reach, reach, u);
			walk_ph = tt * mix(3.6, 5.0, var);
		}
		if (d > max_d) {
			continue;
		}
		vec2 p = p0 + rd.xy * (d / dz);
		vec2 q = p - vec2(x, -wo_floor);
		if (abs(q.x) > 1.0 || q.y < -0.1 || q.y > 2.1) {
			continue;
		}
		// Grille de 5 cm (cubique) puis bord adouci par la profondeur et le
		// verre dépoli : jamais net, toujours lointain.
		vec2 qq = (floor(q / CELL) + 0.5) * CELL;
		float sd = figure(qq, dir, walk_ph, front, t, var);
		float soft = 0.012 + d * 0.006 + frost * 0.008;
		float cov = (1.0 - smoothstep(-soft, soft, sd)) * pres;
		// Couleur : presque noire, rendue à la brume avec la distance ; la
		// vitre crasseuse en garde toujours une part.
		float fog = 1.0 - exp(-d * 0.22);
		vec3 sil = mix(tint * 0.025, c, clamp(fog * 0.7 + frost * 0.1, 0.0, 0.7));
		c = mix(c, sil, cov);
		// Yeux faibles du zombie collé à la vitre (de face).
		if (front > 0.6) {
			vec2 e = qq - vec2(dir * 0.0, 1.62);
			float blink = step(0.08, fract(t * 0.23 + var));
			if (abs(abs(e.x) - 0.05) < CELL * 0.5 && abs(e.y) < CELL * 0.5) {
				eye = max(eye, cov * front * blink);
			}
		}
	}
	return c;
}

void fragment() {
	vec3 tint = wo_tint.rgb;
	float t = TIME * wo_live;
	vec3 rd = normalize(v_local - v_cam);
	vec2 p0 = v_local.xy;
	float dz = max(-rd.z, 0.12);
	vec3 c;
	float eye = 0.0;
	if (wo_mode < 0.5) {
		// Vitre de la case.
		vec2 uv = p0 / wo_size + 0.5;
		vec2 pane = clamp(floor(uv * wo_panes), vec2(0.0), wo_panes - 1.0);
		float idx = pane.x + pane.y * wo_panes.x;
		vec2 ps = wo_size / wo_panes;
		vec2 pl = (uv * wo_panes - pane) * ps;  // m dans la vitre
		vec2 g = floor(p0 / CELL);              // grille de 5 cm
		bool broken = bit(wo_broken, idx);
		float edge = min(min(pl.x, ps.x - pl.x), min(pl.y, ps.y - pl.y));
		// Éclats restés dans le cadre d'une vitre cassée (dents de cubes).
		// Vitre cassée : un liseré d'un cube et des éclats en escalier dans les
		// coins (triangles de cubes, taille tirée par coin).
		vec2 pc = (floor(pl / CELL) + 0.5) * CELL;
		vec2 cq = step(ps * 0.5, pc);  // coin le plus proche
		vec2 dc = abs(pc - cq * ps);
		float shard = (0.08 + 0.22 * h21(cq + idx * 3.0 + wo_seed.zw)) * min(ps.x, ps.y);
		bool glass = !broken || edge < CELL || dc.x + dc.y < shard;
		float frost = glass ? 1.0 : 0.0;
		vec2 pf = p0 + rd.xy * (8.0 / dz);
		c = sky(vec2(pf.x, pf.y + wo_floor), tint);
		c = figures(c, p0, rd, tint, t, 8.0, frost, eye);
		if (glass) {
			// Verre crasseux : voile, salissures en pixels (plus en bas),
			// coulures, reflet en biais.
			float grime = h21(floor(g * 0.5) + vec2(idx * 13.0, 3.0));
			float low = 1.0 - smoothstep(0.0, ps.y * 0.7, pl.y);
			vec3 haze = tint * 0.42;
			c = mix(c, haze, 0.1 + 0.15 * low + 0.05 * grime);
			float streak = step(0.86, h11(g.x * 1.7 + idx * 5.0)) * step(h11(g.x + 3.0) * ps.y, pl.y);
			c *= 1.0 - 0.18 * streak;
			float refl = smoothstep(0.1, 0.0, abs(fract((p0.x + p0.y) * 0.9 + wo_seed.w) - 0.5) - 0.38);
			c += tint * 0.12 * refl;
			// Fêlures : rayons pixelisés depuis un point d'impact.
			if (bit(wo_cracked, idx) && !broken) {
				vec2 ctr = ps * vec2(0.3 + 0.4 * h11(idx + wo_seed.x * 7.0), 0.3 + 0.4 * h11(idx * 2.0 + wo_seed.y * 9.0));
				vec2 dd = (floor(pl / CELL) + 0.5) * CELL - ctr;
				float ang = atan(dd.y, dd.x) / 6.2832 * 6.0 + h11(idx * 4.0);
				float line = abs(fract(ang) - 0.5) * length(dd) * 6.2832 / 6.0;
				if (line < CELL * 0.5 && length(dd) < ps.x * 0.6) {
					c = c * 0.55 + tint * 0.35;
				}
			}
			// Bord de la vitre cassée : arête claire.
			if (broken) {
				c = c * 0.7 + tint * 0.3;
			}
		}
		// Crasse au pied de la vitre et contre le cadre.
		c *= 0.82 + 0.18 * smoothstep(0.0, 0.12, edge);
	} else {
		float hit_d;
		c = corridor(p0, rd, tint, t, hit_d);
		c = figures(c, p0, rd, tint * 0.6, t, hit_d, 0.4, eye);
	}
	c += vec3(0.9, 0.85, 0.35) * eye * 1.4;
	ALBEDO = c;
}
