class_name SfxDsp
extends RefCounted
## Traitement hors-ligne des sons libres de droits (CC0) importés dans
## assets/audio/ : décodage OGG/MP3/WAV, découpe, hauteur, égalisation,
## compression, saturation, réverbération, normalisation, analyse.
## Tous les buffers sont des PackedFloat32Array mono à RATE Hz.
## Utilisé par tools/audio/sfx_import.gd (jamais par le jeu lui-même).

const RATE := 44100


## Décode un fichier audio en mono 44,1 kHz (moyenne des canaux).
static func decode(path: String) -> PackedFloat32Array:
	var st: AudioStream
	match path.get_extension().to_lower():
		"ogg": st = AudioStreamOggVorbis.load_from_file(path)
		"mp3": st = AudioStreamMP3.load_from_file(path)
		"wav": st = AudioStreamWAV.load_from_file(path)
	var out := PackedFloat32Array()
	if st == null:
		push_error("[SfxDsp] impossible de décoder " + path)
		return out
	var pb := st.instantiate_playback()
	pb.start(0.0)
	var rate := AudioServer.get_mix_rate()
	var want := int(st.get_length() * rate) + 1
	while out.size() < want:
		var fr: PackedVector2Array = pb.mix_audio(1.0, 4096)
		if fr.is_empty():
			break
		var base := out.size()
		out.resize(base + fr.size())
		for i in fr.size():
			out[base + i] = (fr[i].x + fr[i].y) * 0.5
	out.resize(mini(out.size(), want))
	if absf(rate - RATE) > 1.0:
		out = resample(out, rate / RATE)
	return out


## Rééchantillonnage linéaire : ratio > 1 raccourcit (hauteur plus aiguë).
static func resample(b: PackedFloat32Array, ratio: float) -> PackedFloat32Array:
	if absf(ratio - 1.0) < 0.0001:
		return b.duplicate()
	var n := int(b.size() / ratio)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var p := i * ratio
		var j := int(p)
		var f := p - j
		var a := b[j] if j < b.size() else 0.0
		var c := b[j + 1] if j + 1 < b.size() else 0.0
		out[i] = a + (c - a) * f
	return out


static func slice(b: PackedFloat32Array, start: float, end: float) -> PackedFloat32Array:
	var s := clampi(int(start * RATE), 0, b.size())
	var e := b.size() if end <= 0.0 else clampi(int(end * RATE), s, b.size())
	return b.slice(s, e)


static func peak(b: PackedFloat32Array) -> float:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	return m


static func rms(b: PackedFloat32Array) -> float:
	if b.is_empty():
		return 0.0
	var acc := 0.0
	for v in b:
		acc += v * v
	return sqrt(acc / b.size())


static func db(x: float) -> float:
	return linear_to_db(maxf(x, 0.000001))


static func gain(b: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] *= g
	return b


## Coupe le silence au début (seuil relatif au pic, en dB) et à la fin.
static func trim_silence(b: PackedFloat32Array, head_db := -45.0, tail_db := -60.0) -> PackedFloat32Array:
	var pk := peak(b)
	if pk <= 0.0:
		return b
	var th := pk * db_to_linear(head_db)
	var tt := pk * db_to_linear(tail_db)
	var s := 0
	while s < b.size() and absf(b[s]) < th:
		s += 1
	s = maxi(s - int(0.002 * RATE), 0)
	var e := b.size() - 1
	while e > s and absf(b[e]) < tt:
		e -= 1
	return b.slice(s, e + 1)


static func fade(b: PackedFloat32Array, fade_in: float, fade_out: float) -> PackedFloat32Array:
	var n := b.size()
	var fi := int(fade_in * RATE)
	var fo := int(fade_out * RATE)
	for i in mini(fi, n):
		b[i] *= float(i) / fi
	for i in mini(fo, n):
		b[n - 1 - i] *= float(i) / fo
	return b


## Coupe à `seconds` avec un fondu de sortie `fade_out`.
static func truncate(b: PackedFloat32Array, seconds: float, fade_out := 0.05) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	if n < b.size():
		b = b.slice(0, n)
	return fade(b, 0.0, fade_out)


## Biquad RBJ générique. kind : lp, hp, peak, lowshelf, highshelf.
static func biquad(b: PackedFloat32Array, kind: String, f: float, q := 0.707, gain_db := 0.0) -> PackedFloat32Array:
	var w0 := TAU * clampf(f, 10.0, RATE * 0.45) / RATE
	var cw := cos(w0)
	var sw := sin(w0)
	var alpha := sw / (2.0 * q)
	var a := pow(10.0, gain_db / 40.0)
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a0 := 1.0
	var a1 := 0.0
	var a2 := 0.0
	match kind:
		"lp":
			b0 = (1.0 - cw) / 2.0; b1 = 1.0 - cw; b2 = b0
			a0 = 1.0 + alpha; a1 = -2.0 * cw; a2 = 1.0 - alpha
		"hp":
			b0 = (1.0 + cw) / 2.0; b1 = -(1.0 + cw); b2 = b0
			a0 = 1.0 + alpha; a1 = -2.0 * cw; a2 = 1.0 - alpha
		"peak":
			b0 = 1.0 + alpha * a; b1 = -2.0 * cw; b2 = 1.0 - alpha * a
			a0 = 1.0 + alpha / a; a1 = -2.0 * cw; a2 = 1.0 - alpha / a
		"lowshelf":
			var s2 := 2.0 * sqrt(a) * alpha
			b0 = a * ((a + 1.0) - (a - 1.0) * cw + s2)
			b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cw)
			b2 = a * ((a + 1.0) - (a - 1.0) * cw - s2)
			a0 = (a + 1.0) + (a - 1.0) * cw + s2
			a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cw)
			a2 = (a + 1.0) + (a - 1.0) * cw - s2
		"highshelf":
			var s3 := 2.0 * sqrt(a) * alpha
			b0 = a * ((a + 1.0) + (a - 1.0) * cw + s3)
			b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cw)
			b2 = a * ((a + 1.0) + (a - 1.0) * cw - s3)
			a0 = (a + 1.0) - (a - 1.0) * cw + s3
			a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cw)
			a2 = (a + 1.0) - (a - 1.0) * cw - s3
	b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var x := b[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		b[i] = y
	return b


## Saturation douce (tanh) dosée : amount 1 = léger, 4 = forte.
static func drive(b: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	var pk := maxf(peak(b), 0.0001)
	var norm := 1.0 / tanh(amount)
	for i in b.size():
		b[i] = tanh(b[i] / pk * amount) * norm * pk
	return b


## Compresseur simple (détection crête, attaque/relâche en s).
static func compress(b: PackedFloat32Array, threshold_db: float, ratio: float, attack := 0.002, release := 0.08) -> PackedFloat32Array:
	var th := db_to_linear(threshold_db) * peak(b)
	var ga := exp(-1.0 / (attack * RATE))
	var gr := exp(-1.0 / (release * RATE))
	var env := 0.0
	for i in b.size():
		var x := absf(b[i])
		env = (ga if x > env else gr) * env + (1.0 - (ga if x > env else gr)) * x
		if env > th:
			var over := env / th
			b[i] *= pow(over, 1.0 / ratio - 1.0)
	return b


## Réverbération d'intérieur (Schroeder : 6 combs amortis + 2 allpass),
## pré-délai `predelay` s, queue `tail` s, `wet` 0..1, `damp` 0..1 (aigus absorbés).
static func room(b: PackedFloat32Array, size := 0.6, wet := 0.25, tail := 0.8, damp := 0.4, predelay := 0.012) -> PackedFloat32Array:
	var n := b.size() + int(tail * RATE)
	var dry := b.duplicate()
	dry.resize(n)
	var acc := PackedFloat32Array()
	acc.resize(n)
	var pd := int(predelay * RATE)
	for delay_ms in [25.3, 26.9, 28.9, 30.7, 32.2, 33.8]:
		var d := int(delay_ms * 0.001 * RATE * (0.7 + size * 0.9))
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		var fb := 0.72 + size * 0.22
		var lp := 0.0
		for i in n:
			var y := line[idx]
			lp = y * (1.0 - damp) + lp * damp
			var src := dry[i - pd] if i >= pd else 0.0
			line[idx] = src + lp * fb
			idx = (idx + 1) % d
			acc[i] += y / 6.0
	for delay_ms in [5.0, 1.7]:
		var d := int(delay_ms * 0.001 * RATE)
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		for i in n:
			var bv := line[idx]
			var x := acc[i]
			line[idx] = x + bv * 0.5
			idx = (idx + 1) % d
			acc[i] = bv - x
	for i in n:
		dry[i] = dry[i] * (1.0 - wet * 0.3) + acc[i] * wet
	return dry


## Mélange `src` dans `dst` à `at` secondes (agrandit dst si besoin).
static func mix(dst: PackedFloat32Array, src: PackedFloat32Array, at := 0.0, g := 1.0) -> PackedFloat32Array:
	var off := int(at * RATE)
	if off + src.size() > dst.size():
		dst.resize(off + src.size())
	for i in src.size():
		dst[off + i] += src[i] * g
	return dst


## Normalise au pic `peak_db` (dBFS).
static func normalize(b: PackedFloat32Array, peak_db := -1.0) -> PackedFloat32Array:
	var pk := peak(b)
	if pk <= 0.0:
		return b
	return gain(b, db_to_linear(peak_db) / pk)


## Retire la composante continue (passe-haut 20 Hz).
static func dc_block(b: PackedFloat32Array) -> PackedFloat32Array:
	return biquad(b, "hp", 20.0)


## Instants (s) des attaques détectées (fenêtres de 5 ms, saut d'énergie).
static func onsets(b: PackedFloat32Array, rel_db := -24.0) -> PackedFloat32Array:
	var w := int(0.005 * RATE)
	var pk := peak(b)
	var th := pk * db_to_linear(rel_db)
	var out := PackedFloat32Array()
	var prev := 0.0
	var last := -1.0
	for s in range(0, b.size() - w, w):
		var m := 0.0
		for i in range(s, s + w):
			m = maxf(m, absf(b[i]))
		var t := float(s) / RATE
		if m > th and m > prev * 3.0 and t - last > 0.06:
			out.append(t)
			last = t
		prev = maxf(m, prev * 0.9)
	return out


## Résumé chiffré d'un buffer : durée, crête, RMS (dB), part de graves
## (< 200 Hz), brillance (> 4 kHz), attaques, et enveloppe ASCII.
static func analyze(b: PackedFloat32Array) -> Dictionary:
	var pk := peak(b)
	var r := rms(b)
	var low := biquad(b.duplicate(), "lp", 200.0)
	var high := biquad(b.duplicate(), "hp", 4000.0)
	var env := ""
	var cols := 48
	var chars := " .:-=+*#%@"
	var step := maxi(b.size() / cols, 1)
	for c in cols:
		var m := 0.0
		for i in range(c * step, mini((c + 1) * step, b.size())):
			m = maxf(m, absf(b[i]))
		var lv := clampf((db(m / maxf(pk, 0.000001)) + 48.0) / 48.0, 0.0, 1.0)
		env += chars[int(lv * (chars.length() - 1))]
	return {
		"dur": float(b.size()) / RATE,
		"peak_db": db(pk),
		"rms_db": db(r),
		"low": rms(low) / maxf(r, 0.000001),
		"high": rms(high) / maxf(r, 0.000001),
		"onsets": onsets(b),
		"env": env,
	}


static func describe(name: String, b: PackedFloat32Array) -> String:
	var a := analyze(b)
	var ons: PackedFloat32Array = a.onsets
	var ot := []
	for i in mini(ons.size(), 8):
		ot.append("%.2f" % ons[i])
	return "%-8s %5.2fs pk %5.1f rms %5.1f bas %.2f aigu %.2f att %d [%s] |%s|" % [
		name, a.dur, a.peak_db, a.rms_db, a.low, a.high, ons.size(), ",".join(ot), a.env]


## Écrit un WAV mono 16 bits 44,1 kHz.
static func save_wav(b: PackedFloat32Array, path: String, loop := false) -> Error:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = b.size()
	return w.save_to_wav(path)
