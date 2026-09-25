class_name Synth
extends RefCounted
## Mini synthétiseur hors-ligne pour générer les sons du jeu (aucun asset externe).
## Tous les buffers sont des PackedFloat32Array mono à RATE Hz, valeurs ~[-1, 1].

const RATE := 44100

var rng := RandomNumberGenerator.new()


func _init(seed_value := 1234) -> void:
	rng.seed = seed_value


func buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func noise(seconds: float) -> PackedFloat32Array:
	var b := buf(seconds)
	for i in b.size():
		b[i] = rng.randf_range(-1.0, 1.0)
	return b


## Bruit « brun » (grave, grondant).
func brown_noise(seconds: float) -> PackedFloat32Array:
	var b := buf(seconds)
	var v := 0.0
	for i in b.size():
		v = clampf(v + rng.randf_range(-0.06, 0.06), -1.0, 1.0)
		v *= 0.998
		b[i] = v * 3.0
	return b


## Sinus à fréquence glissante f0 -> f1 (exponentielle).
func sweep(seconds: float, f0: float, f1: float, shape := "sine") -> PackedFloat32Array:
	var b := buf(seconds)
	var phase := 0.0
	var n := b.size()
	for i in n:
		var t := float(i) / n
		var f := f0 * pow(f1 / f0, t)
		phase += f / RATE
		var p := fmod(phase, 1.0)
		match shape:
			"saw": b[i] = 2.0 * p - 1.0
			"square": b[i] = 1.0 if p < 0.5 else -1.0
			"tri": b[i] = 4.0 * absf(p - 0.5) - 1.0
			_: b[i] = sin(p * TAU)
	return b


func tone(seconds: float, f: float, shape := "sine") -> PackedFloat32Array:
	return sweep(seconds, f, f, shape)


## Enveloppe exponentielle décroissante (attaque linéaire courte).
func env_exp(b: PackedFloat32Array, attack: float, decay: float) -> PackedFloat32Array:
	var a := int(attack * RATE)
	for i in b.size():
		var t := float(i) / RATE
		var g := exp(-maxf(t - attack, 0.0) / maxf(decay, 0.0001))
		if i < a:
			g *= float(i) / maxf(a, 1)
		b[i] *= g
	return b


## Enveloppe ADSR simple (durées en secondes, sustain en niveau).
func env_adsr(b: PackedFloat32Array, a: float, d: float, s: float, r: float) -> PackedFloat32Array:
	var n := b.size()
	var total := float(n) / RATE
	for i in n:
		var t := float(i) / RATE
		var g := 1.0
		if t < a:
			g = t / a
		elif t < a + d:
			g = lerpf(1.0, s, (t - a) / d)
		elif t < total - r:
			g = s
		else:
			g = s * maxf((total - t) / r, 0.0)
		b[i] *= g
	return b


func lowpass(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var rc := 1.0 / (TAU * cutoff)
	var alpha := (1.0 / RATE) / (rc + 1.0 / RATE)
	var y := 0.0
	for i in b.size():
		y += alpha * (b[i] - y)
		b[i] = y
	return b


func highpass(b: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var rc := 1.0 / (TAU * cutoff)
	var alpha := rc / (rc + 1.0 / RATE)
	var prev_x := 0.0
	var y := 0.0
	for i in b.size():
		var x := b[i]
		y = alpha * (y + x - prev_x)
		prev_x = x
		b[i] = y
	return b


## Passe-bande biquad (RBJ). q ~ 0.5 (large) à 10 (résonant).
func bandpass(b: PackedFloat32Array, center: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * center / RATE
	var alpha := sin(w0) / (2.0 * q)
	var b0 := alpha
	var b2 := -alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var x := b[i]
		var y := (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		b[i] = y
	return b


## Filtre passe-bas dont la coupure varie de c0 à c1 sur la durée.
func lowpass_sweep(b: PackedFloat32Array, c0: float, c1: float) -> PackedFloat32Array:
	var y := 0.0
	var n := b.size()
	for i in n:
		var c := c0 * pow(c1 / c0, float(i) / n)
		var rc := 1.0 / (TAU * c)
		var alpha := (1.0 / RATE) / (rc + 1.0 / RATE)
		y += alpha * (b[i] - y)
		b[i] = y
	return b


## Saturation douce (tanh).
func drive(b: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] = tanh(b[i] * amount) / tanh(amount)
	return b


## Réduction de résolution (grain lo-fi).
func bitcrush(b: PackedFloat32Array, bits: int) -> PackedFloat32Array:
	var steps := pow(2.0, bits)
	for i in b.size():
		b[i] = round(b[i] * steps) / steps
	return b


func gain(b: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in b.size():
		b[i] *= g
	return b


## Mélange `src` dans `dst` à partir de `at` secondes (agrandit dst si besoin).
func mix(dst: PackedFloat32Array, src: PackedFloat32Array, at := 0.0, g := 1.0) -> PackedFloat32Array:
	var off := int(at * RATE)
	if off + src.size() > dst.size():
		dst.resize(off + src.size())
	for i in src.size():
		dst[off + i] += src[i] * g
	return dst


## Réverbe simple (4 combs + 2 allpass, type Schroeder). `wet` 0..1.
func reverb(b: PackedFloat32Array, room := 0.8, wet := 0.3, tail := 1.0) -> PackedFloat32Array:
	var out := b.duplicate()
	out.resize(b.size() + int(tail * RATE))
	var dry := out.duplicate()
	var acc := PackedFloat32Array()
	acc.resize(out.size())
	for delay_ms in [29.7, 37.1, 41.1, 43.7]:
		var d := int(delay_ms * 0.001 * RATE * (0.6 + room * 0.6))
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		var fb := 0.6 + room * 0.3
		for i in out.size():
			var y := line[idx]
			line[idx] = dry[i] + y * fb
			idx = (idx + 1) % d
			acc[i] += y * 0.25
	for delay_ms in [5.0, 1.7]:
		var d := int(delay_ms * 0.001 * RATE)
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		for i in acc.size():
			var buf_v := line[idx]
			var x := acc[i]
			var y := -x + buf_v
			line[idx] = x + buf_v * 0.5
			idx = (idx + 1) % d
			acc[i] = y
	for i in out.size():
		out[i] = dry[i] * (1.0 - wet * 0.5) + acc[i] * wet
	return out


## Normalise au pic `peak` et applique un fondu de sortie anti-clic.
func finish(b: PackedFloat32Array, peak := 0.9, fade := 0.01) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var g := peak / m
	var f := int(fade * RATE)
	var n := b.size()
	for i in n:
		b[i] *= g
		if i > n - f:
			b[i] *= float(n - i) / f
	# Coupe le silence final.
	var last := n - 1
	while last > 0 and absf(b[last]) < 0.0005:
		last -= 1
	b.resize(mini(n, last + 64))
	return b


func save(b: PackedFloat32Array, path: String, loop := false) -> void:
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
	var err := w.save_to_wav(path)
	if err != OK:
		push_error("échec d'écriture " + path)
	else:
		print("  %s (%.2f s)" % [path.get_file(), float(b.size()) / RATE])
