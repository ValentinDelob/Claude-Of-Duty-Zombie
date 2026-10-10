class_name SfxLoudness
extends RefCounted
## Intensité perçue des sons (approximation LUFS, ITU-R BS.1770 / EBU R128) :
## pondération K (étagère aiguë +4 dB vers 1,7 kHz, passe-haut 38 Hz), énergie
## par blocs de 400 ms. Les sons ponctuels (tirs, voix, impacts) sont mesurés
## en intensité « momentanée » maximale (LUFS-M max, pas de 50 ms), les boucles
## et musiques en intensité intégrée (portes -70 LUFS absolue, -10 LU relative).
##
## Chaque son appartient à une catégorie (motifs de nom) qui fixe sa cible et
## la tolérance admise : tous les tirs d'armes se valent à ±1,5 LU, etc.
## Utilisé par tools/audio/sfx_import.gd (normalisation des sons CC0 et
## nivellement des sons procéduraux) et vérifié par tests/test_audio.gd.

const RATE := 44100
## Plafond de crête après limitation (dBFS).
const CEILING_DB := -0.8
## Réduction de gain maximale admise du limiteur (dB) pour atteindre la cible.
const MAX_LIMIT_DB := 12.0

## Catégories, dans l'ordre de correspondance (premier motif qui colle).
## mode "max" : LUFS-M max ; "int" : intégré. `tol` : écart admis (LU).
const CATEGORIES := [
	# Mécanique d'arme d'abord (« dry_fire » n'est pas un tir).
	{"id": "rechargement", "match": ["mag_*", "slide", "bolt", "pump", "shell", "shell_in", "break_*", "dry_fire",
		"weapon_switch", "grenade_pin", "grenade_throw", "knife_swing", "monkey_wind"],
		"target": -19.0, "tol": 2.5, "mode": "max"},
	# Tous les tirs d'armes au même niveau perçu (le joueur les entend à -1 dB).
	{"id": "tir", "match": ["*_fire"], "target": -11.0, "tol": 1.5, "mode": "max"},
	# Couche électrique des armes Pack-a-Punchées, jouée par-dessus le tir.
	{"id": "arme_zap", "match": ["pap_zap_*"], "target": -19.0, "tol": 2.0, "mode": "max"},
	{"id": "explosion", "match": ["explosion", "frag_explode"],
		"target": -10.0, "tol": 2.0, "mode": "max"},
	{"id": "impact", "match": ["impact_*", "flesh_hit_*", "headshot", "knife_hit", "knife_flesh", "body_fall",
		"grenade_bounce", "monkey_bounce"], "target": -16.0, "tol": 2.5, "mode": "max"},
	{"id": "zombie", "match": ["zombie_groan_*", "zombie_sprint_*", "zombie_attack_*", "zombie_death_*"],
		"target": -14.0, "tol": 2.0, "mode": "max"},
	{"id": "zombie_bruitage", "match": ["zombie_step_*", "emerge", "barricade_*"], "target": -18.0, "tol": 2.5, "mode": "max"},
	{"id": "chien", "match": ["dog_growl_*", "dog_bark_*", "dog_bite_*", "dog_whine"], "target": -14.0, "tol": 2.0, "mode": "max"},
	{"id": "joueur", "match": ["footstep_*", "dive_land", "player_hurt_*", "player_down", "player_breath_*", "heartbeat", "revive"],
		"target": -18.0, "tol": 3.0, "mode": "max"},
	# Ritournelles originales (manches, caisse...) : identité conservée,
	# seulement mises au même niveau.
	{"id": "ritournelle", "match": ["round_start", "round_end", "dog_round_start", "dog_round_end",
		"box_music", "power_on", "menu_start", "monkey_music"],
		"target": -14.0, "tol": 2.5, "mode": "max"},
	{"id": "musique", "match": ["menu_theme", "dog_round_music"],
		"target": -20.0, "tol": 2.0, "mode": "int"},
	{"id": "ambiance", "match": ["ambience_*"], "target": -24.0, "tol": 2.0, "mode": "int"},
	{"id": "interface", "match": ["ui_*", "menu_*", "hitmarker"], "target": -18.0, "tol": 3.0, "mode": "max"},
	{"id": "decor", "match": ["*"], "target": -15.0, "tol": 3.5, "mode": "max"},
]


static func _glob(n: String, pat: String) -> bool:
	return n.match(pat)


## Catégorie d'un son (dictionnaire de CATEGORIES).
static func category(n: String) -> Dictionary:
	for c in CATEGORIES:
		for pat in c.match:
			if _glob(n, pat):
				return c
	return CATEGORIES[CATEGORIES.size() - 1]


## Coefficients biquad RBJ [b0, b1, b2, a1, a2] (normalisés).
static func _coefs(kind: String, f: float, q: float, gain_db := 0.0) -> PackedFloat32Array:
	var w0 := TAU * f / RATE
	var cw := cos(w0)
	var alpha := sin(w0) / (2.0 * q)
	var a := pow(10.0, gain_db / 40.0)
	var c := PackedFloat32Array([1, 0, 0, 1, 0, 0])
	if kind == "hp":
		c = PackedFloat32Array([(1.0 + cw) / 2.0, -(1.0 + cw), (1.0 + cw) / 2.0, 1.0 + alpha, -2.0 * cw, 1.0 - alpha])
	else:  # highshelf
		var s := 2.0 * sqrt(a) * alpha
		c = PackedFloat32Array([a * ((a + 1.0) + (a - 1.0) * cw + s), -2.0 * a * ((a - 1.0) + (a + 1.0) * cw),
			a * ((a + 1.0) + (a - 1.0) * cw - s), (a + 1.0) - (a - 1.0) * cw + s,
			2.0 * ((a - 1.0) - (a + 1.0) * cw), (a + 1.0) - (a - 1.0) * cw - s])
	return PackedFloat32Array([c[0] / c[3], c[1] / c[3], c[2] / c[3], c[4] / c[3], c[5] / c[3]])


## Énergie pondérée K par tranches de 50 ms (moyenne des carrés).
## `max_seconds` borne l'analyse (longues musiques).
static func _chunks(b: PackedFloat32Array, max_seconds := 0.0) -> PackedFloat32Array:
	var n := b.size() if max_seconds <= 0.0 else mini(b.size(), int(max_seconds * RATE))
	var s1 := _coefs("highshelf", 1681.97, 0.7072, 4.0)
	var s2 := _coefs("hp", 38.135, 0.5003)
	var hop := int(0.05 * RATE)
	var out := PackedFloat32Array()
	out.resize(int(ceil(float(n) / hop)))
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	var u1 := 0.0; var u2 := 0.0; var z1 := 0.0; var z2 := 0.0
	var acc := 0.0
	var k := 0
	for i in n:
		var x := b[i]
		var y := s1[0] * x + s1[1] * x1 + s1[2] * x2 - s1[3] * y1 - s1[4] * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		var z := s2[0] * y + s2[1] * u1 + s2[2] * u2 - s2[3] * z1 - s2[4] * z2
		u2 = u1; u1 = y; z2 = z1; z1 = z
		acc += z * z
		k += 1
		if k == hop:
			@warning_ignore("integer_division")
			out[i / hop] = acc / hop
			acc = 0.0
			k = 0
	if k > 0:
		out[out.size() - 1] = acc / hop
	return out


static func _lufs(ms: float) -> float:
	return -0.691 + 10.0 * log(maxf(ms, 1e-12)) / log(10.0)


## Blocs de 400 ms (8 tranches), pas de 50 ms ; un son plus court que 400 ms
## est complété par du silence (un clic bref paraît moins fort qu'un râle).
static func _blocks(ch: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var last := maxi(ch.size() - 8, 0)
	for s in range(0, last + 1):
		var acc := 0.0
		for j in range(s, mini(s + 8, ch.size())):
			acc += ch[j]
		out.append(acc / 8.0)
	return out


## Intensité momentanée maximale (LUFS-M max).
static func momentary_max(b: PackedFloat32Array, max_seconds := 0.0) -> float:
	var m := 0.0
	for v in _blocks(_chunks(b, max_seconds)):
		m = maxf(m, v)
	return _lufs(m)


## Intensité intégrée (LUFS-I) avec portes absolue et relative.
static func integrated(b: PackedFloat32Array, max_seconds := 0.0) -> float:
	var bl := _blocks(_chunks(b, max_seconds))
	var gated := []
	for v in bl:
		if _lufs(v) > -70.0:
			gated.append(v)
	if gated.is_empty():
		return -70.0
	var mean := 0.0
	for v in gated:
		mean += v
	mean /= gated.size()
	var rel := _lufs(mean) - 10.0
	var acc := 0.0
	var n := 0
	for v in gated:
		if _lufs(v) > rel:
			acc += v
			n += 1
	return _lufs(acc / maxi(n, 1))


## Intensité selon le mode de la catégorie du son.
static func measure(n: String, b: PackedFloat32Array, max_seconds := 0.0) -> float:
	return integrated(b, max_seconds) if category(n).mode == "int" else momentary_max(b, max_seconds)


static func peak_db(b: PackedFloat32Array) -> float:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	return linear_to_db(maxf(m, 0.000001))


## Limiteur à anticipation (1,5 ms) et relâche douce (60 ms) : aucune crête
## au-dessus de `ceiling_db`.
static func limit(b: PackedFloat32Array, ceiling_db := CEILING_DB) -> PackedFloat32Array:
	var c := db_to_linear(ceiling_db)
	var n := b.size()
	var g := PackedFloat32Array()
	g.resize(n)
	for i in n:
		var a := absf(b[i])
		g[i] = 1.0 if a <= c else c / a
	# Anticipation : la réduction commence avant la crête (rampe linéaire).
	var look := int(0.0015 * RATE)
	var nxt := 1.0
	for i in range(n - 1, -1, -1):
		nxt = minf(g[i], nxt + (1.0 - nxt) / look)
		g[i] = nxt
	# Relâche exponentielle.
	var rel := 1.0 - exp(-1.0 / (0.06 * RATE))
	var cur := 1.0
	for i in n:
		cur = g[i] if g[i] < cur else cur + (g[i] - cur) * rel
		b[i] = clampf(b[i] * cur, -c, c)
	return b


## Met un son à l'intensité cible de sa catégorie (gain puis limiteur), en
## quelques itérations. `offset` : décalage de cible propre au son (dB).
static func level(n: String, b: PackedFloat32Array, offset := 0.0, max_seconds := 0.0) -> PackedFloat32Array:
	var target: float = float(category(n).target) + offset
	var pk0 := peak_db(b)
	if pk0 < -100.0:
		return b
	var src := b.duplicate()
	var total := 0.0
	for it in 8:
		var cur := measure(n, b, max_seconds)
		var err := target - cur
		if absf(err) < 0.2:
			break
		total += err
		# Pas plus de MAX_LIMIT_DB de limitation au-dessus du plafond.
		total = minf(total, CEILING_DB - pk0 + MAX_LIMIT_DB)
		b = src.duplicate()
		for i in b.size():
			b[i] *= db_to_linear(total)
		b = limit(b)
	if peak_db(b) > CEILING_DB + 0.01:
		b = limit(b)
	return b


## Nivellement doux des sons procéduraux : un son déjà à moins de la moitié
## de la tolérance de sa catégorie n'est pas touché (identité conservée),
## sinon il est mis à la cible. `offset` : SfxRecipes.LEVEL_OFFSETS.
static func balance(n: String, b: PackedFloat32Array, offset := 0.0) -> PackedFloat32Array:
	if absf(deviation(n, b, offset, 20.0)) <= float(category(n).tol) * 0.5:
		return b
	return level(n, b, offset, 20.0)


## Écart (LU) d'un son à la cible de sa catégorie.
static func deviation(n: String, b: PackedFloat32Array, offset := 0.0, max_seconds := 0.0) -> float:
	return measure(n, b, max_seconds) - (float(category(n).target) + offset)


## Buffer mono flottant d'un WAV 16 bits (fichier source, pas l'import QOA).
static func read_wav(path: String) -> PackedFloat32Array:
	var w := AudioStreamWAV.load_from_file(path)
	var out := PackedFloat32Array()
	if w == null or w.format != AudioStreamWAV.FORMAT_16_BITS:
		return out
	var d := w.data
	var ch := 2 if w.stereo else 1
	@warning_ignore("integer_division")
	var n := d.size() / (2 * ch)
	out.resize(n)
	for i in n:
		var v := d.decode_s16(i * 2 * ch) / 32768.0
		if ch == 2:
			v = (v + d.decode_s16(i * 4 + 2) / 32768.0) * 0.5
		out[i] = v
	return out
