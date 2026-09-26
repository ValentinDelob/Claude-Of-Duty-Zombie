extends SceneTree
## Génère les sons du menu principal dans res://assets/audio/ (synthèse
## procédurale, graines fixes : résultat déterministe).
##   godot --headless --path . -s res://tools/gen_audio_menu.gd [-- nom1 nom2 ...]
## Sans argument : régénère tout. La boucle « menu_theme » doit être importée
## en boucle (edit/loop_mode=2 dans menu_theme.wav.import).

const OUT := "res://assets/audio/"

var s := Synth.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := OS.get_cmdline_user_args()
	var gens := {}
	for m in get_method_list():
		if m.name.begins_with("gen_"):
			gens[m.name.substr(4)] = m.name
	print("Génération audio (menu) :")
	for key in gens:
		if only.is_empty() or key in only:
			s = Synth.new(hash(key))
			var t0 := Time.get_ticks_msec()
			call(gens[key])
			print("    (%d ms)" % (Time.get_ticks_msec() - t0))
	quit()


func _save(n: String, b: PackedFloat32Array, loop := false) -> void:
	s.save(b, OUT + n + ".wav", loop)


# ---------------------------------------------------------------- briques
# (recopiées de tools/gen_audio.gd pour rester indépendant de ce fichier)

## Voix gutturale : dent de scie à hauteur instable dans des formants.
func _growl(seconds: float, f0: float, f0_end: float, vowel: Array, rough: float) -> PackedFloat32Array:
	var n := int(seconds * Synth.RATE)
	var src := PackedFloat32Array()
	src.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var jitter := 1.0 + s.rng.randf_range(-rough, rough) * 0.15 + sin(t * 37.0) * 0.04
		var f := lerpf(f0, f0_end, t) * jitter
		phase += f / Synth.RATE
		var p := fmod(phase, 1.0)
		src[i] = (2.0 * p - 1.0) + s.rng.randf_range(-1.0, 1.0) * rough * 0.5
	var f1 := s.bandpass(src.duplicate(), vowel[0], 4.0)
	var f2 := s.bandpass(src.duplicate(), vowel[1], 5.0)
	var b := s.buf(seconds)
	s.mix(b, f1, 0.0, 1.0)
	s.mix(b, f2, 0.0, 0.6)
	var breath := s.bandpass(s.noise(seconds), 1400.0, 1.0)
	s.mix(b, breath, 0.0, 0.25)
	b = s.env_adsr(b, 0.08, 0.2, 0.8, seconds * 0.4)
	return s.drive(b, 3.0)


## Petit choc métallique (résonances inharmoniques).
func _clank(f: float, decay: float, noise_amt := 0.6) -> PackedFloat32Array:
	var b := s.env_exp(s.bandpass(s.noise(0.2), f * 1.5, 2.0), 0.0005, decay * 0.4)
	b = s.gain(b, noise_amt)
	for ratio in [1.0, 2.76, 5.4]:
		s.mix(b, s.env_exp(s.tone(0.25 + decay, f * ratio), 0.0005, decay / ratio), 0.0, 0.35 / ratio)
	return b


## Cloche / glas (partiels inharmoniques).
func _bell(seconds: float, f: float) -> PackedFloat32Array:
	var b := s.buf(seconds)
	for pr in [[1.0, 1.0], [2.0, 0.6], [2.76, 0.45], [5.4, 0.25], [8.9, 0.12]]:
		s.mix(b, s.env_exp(s.tone(seconds, f * pr[0]), 0.002, seconds / (pr[0] * 0.6)), 0.0, pr[1] * 0.3)
	return b


## Voix de chœur lointaine (voyelle « ooh / aah »), vibrato lent.
func _voice(seconds: float, f: float, vowel: Array) -> PackedFloat32Array:
	var n := int(seconds * Synth.RATE)
	var src := PackedFloat32Array()
	src.resize(n)
	var phase := 0.0
	var vib_rate := s.rng.randf_range(4.2, 5.4)
	for i in n:
		var t := float(i) / Synth.RATE
		var ff := f * (1.0 + 0.006 * sin(TAU * vib_rate * t) + s.rng.randf_range(-0.002, 0.002))
		phase += ff / Synth.RATE
		src[i] = 2.0 * fmod(phase, 1.0) - 1.0
	var b := s.buf(seconds)
	s.mix(b, s.bandpass(src.duplicate(), vowel[0], 5.0), 0.0, 1.0)
	s.mix(b, s.bandpass(src, vowel[1], 6.0), 0.0, 0.5)
	s.mix(b, s.bandpass(s.noise(seconds), vowel[1], 3.0), 0.0, 0.05)
	return b


## Respiration : souffle filtré qui monte (inspiration) ou descend (expiration).
func _breath(seconds: float, inhale: bool) -> PackedFloat32Array:
	var b := s.noise(seconds)
	var c0 := 500.0 if inhale else 1300.0
	var c1 := 1300.0 if inhale else 450.0
	b = s.bandpass(b, (c0 + c1) * 0.5, 1.2)
	b = s.lowpass_sweep(b, c0 * 2.0, c1 * 2.0)
	var n := b.size()
	for i in n:
		var t := float(i) / n
		b[i] *= sin(PI * pow(t, 0.7 if inhale else 1.4)) * (1.0 + 0.3 * sin(t * 60.0) * t)
	return b


## Battement de cœur étouffé (« lub-dub »).
func _heartbeat() -> PackedFloat32Array:
	var b := s.buf(0.7)
	s.mix(b, s.env_exp(s.sweep(0.3, 62.0, 38.0), 0.006, 0.07), 0.0, 1.0)
	s.mix(b, s.env_exp(s.sweep(0.3, 55.0, 34.0), 0.006, 0.06), 0.24, 0.7)
	return s.lowpass(b, 220.0)


## Grincement de métal (porte, tôle) : dent de scie lente passée dans des résonances.
func _creak(seconds: float, f0: float, f1: float) -> PackedFloat32Array:
	var src := s.sweep(seconds, f0, f1, "saw")
	# Frottement irrégulier : modulation d'amplitude en saccades.
	var n := src.size()
	var g := 0.0
	for i in n:
		if i % 400 == 0:
			g = s.rng.randf_range(0.2, 1.0)
		src[i] *= g
	var b := s.bandpass(src.duplicate(), 900.0, 7.0)
	s.mix(b, s.bandpass(src.duplicate(), 1750.0, 9.0), 0.0, 0.6)
	s.mix(b, s.bandpass(src, 3100.0, 10.0), 0.0, 0.3)
	return s.env_adsr(b, seconds * 0.2, 0.2, 0.7, seconds * 0.4)


## Bouclage sans couture : la queue qui dépasse `dur` est repliée sur le début.
func _fold_loop(b: PackedFloat32Array, dur: float) -> PackedFloat32Array:
	var n := int(dur * Synth.RATE)
	if b.size() > n:
		for i in range(n, b.size()):
			b[(i - n) % n] += b[i]
	b.resize(n)
	return b


func _normalize(b: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	return s.gain(b, peak / m)


# ---------------------------------------------------------------- musique

## Thème du menu, boucle de 40 s : bourdon grave, nappe mineure qui enfle,
## chœur lointain, motif de boîte à musique désaccordée, battements de cœur,
## métal qui grince, respirations, glas lointain.
func gen_menu_theme() -> void:
	var dur := 40.0
	var total := dur + 6.0  # queue repliée sur le début
	var b := s.buf(total)
	# Bourdon : ré grave + quinte, scies désaccordées très filtrées, respiration lente du filtre.
	var drone := s.buf(total)
	for f in [36.71, 36.9, 55.0, 73.42]:
		s.mix(drone, s.tone(total, f, "saw"), 0.0, 0.22 if f < 60.0 else 0.1)
	drone = s.lowpass(drone, 160.0)
	for i in drone.size():
		var t := float(i) / Synth.RATE
		drone[i] *= 0.75 + 0.25 * sin(TAU * t / dur * 2.0)
	s.mix(b, drone, 0.0, 0.9)
	s.mix(b, s.lowpass(s.brown_noise(total), 90.0), 0.0, 0.35)
	# Nappe : accord ré mineur (+ sol dièse dissonant) qui enfle deux fois.
	for k in 2:
		var pad := s.buf(18.0)
		for f in [146.83, 174.61, 220.0, 207.65]:
			for det in [-0.003, 0.004]:
				s.mix(pad, s.tone(18.0, f * (1.0 + det), "saw"), 0.0, 0.05)
		pad = s.lowpass_sweep(pad, 250.0, 900.0)
		pad = s.env_adsr(pad, 7.0, 2.0, 0.6, 7.0)
		s.mix(b, pad, 2.0 + k * 20.0, 0.55)
	# Chœur lointain (voix ooh), une fois par boucle.
	var choir := s.buf(14.0)
	var vowels := [[400.0, 800.0], [350.0, 700.0], [450.0, 850.0], [380.0, 760.0]]
	var notes := [293.66, 349.23, 440.0, 415.3]
	for i in notes.size():
		s.mix(choir, _voice(14.0, notes[i] * (1.0 if i < 3 else 0.5), vowels[i]), 0.0, 0.3)
	choir = s.env_adsr(choir, 5.0, 2.0, 0.7, 6.0)
	s.mix(b, s.lowpass(choir, 1800.0), 17.0, 0.5)
	# Motif de boîte à musique désaccordée (ré - fa - mi - la), deux fois.
	var motif := [[587.33, 0.0], [698.46, 0.9], [659.26, 1.8], [440.0, 3.2], [466.16, 4.6]]
	for rep in [7.0, 29.0]:
		for m in motif:
			var f: float = m[0] * (1.0 + s.rng.randf_range(-0.012, 0.012))
			var note := s.env_exp(s.tone(2.5, f, "tri"), 0.003, 0.7)
			s.mix(note, s.env_exp(s.tone(2.5, f * 2.01), 0.003, 0.25), 0.0, 0.25)
			s.mix(note, s.env_exp(s.tone(2.5, f * 3.98), 0.002, 0.1), 0.0, 0.1)
			s.mix(b, note, rep + m[1], 0.14 if rep < 20.0 else 0.1)
	# Battements de cœur dans la seconde moitié.
	var hb := _heartbeat()
	var at := 21.0
	while at < 34.0:
		s.mix(b, hb, at, 0.5)
		at += 1.15
	# Métal qui grince, chocs lointains.
	s.mix(b, _creak(2.6, 210.0, 150.0), 4.5, 0.12)
	s.mix(b, _creak(1.8, 320.0, 240.0), 25.5, 0.1)
	s.mix(b, _creak(3.2, 180.0, 120.0), 36.0, 0.1)
	s.mix(b, s.lowpass(_clank(140.0, 0.9, 0.8), 1800.0), 13.3, 0.35)
	s.mix(b, s.lowpass(_clank(95.0, 1.2, 0.9), 1400.0), 33.8, 0.3)
	# Respirations toutes proches (très bas).
	for pair in [[11.0, 1.6], [37.5, 1.4]]:
		s.mix(b, _breath(1.3, true), pair[0], 0.05)
		s.mix(b, _breath(1.9, false), pair[0] + pair[1], 0.06)
	# Glas lointain.
	s.mix(b, s.lowpass(_bell(6.0, 98.0), 1200.0), 0.5, 0.35)
	s.mix(b, s.lowpass(_bell(6.0, 92.5), 1200.0), 20.5, 0.3)
	b = s.reverb(b, 0.95, 0.45, 2.0)
	b = _fold_loop(b, dur)
	_save("menu_theme", _normalize(b, 0.8), true)


# ---------------------------------------------------------------- interface

## Survol : relais sec + coup sourd, petite résonance métallique.
func gen_menu_move() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.06), 2200.0, 3.0), 0.0005, 0.008)
	s.mix(b, s.env_exp(s.sweep(0.15, 140.0, 70.0), 0.001, 0.035), 0.0, 0.9)
	s.mix(b, s.env_exp(s.tone(0.3, 1320.0, "tri"), 0.001, 0.05), 0.004, 0.06)
	_save("menu_move", s.finish(s.reverb(b, 0.5, 0.18, 0.35), 0.6))


## Validation : impact grave, claquement de culasse, longue queue.
func gen_menu_select() -> void:
	var b := s.env_exp(s.sweep(0.9, 95.0, 32.0), 0.002, 0.28)
	s.mix(b, _clank(180.0, 0.35, 0.9), 0.0, 0.8)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.4), 700.0), 0.001, 0.07), 0.0, 0.7)
	s.mix(b, _clank(420.0, 0.12, 0.5), 0.07, 0.35)
	b = s.drive(b, 1.8)
	_save("menu_select", s.finish(s.reverb(b, 0.9, 0.35, 1.4), 0.85))


## Retour : souffle descendant + choc étouffé.
func gen_menu_back() -> void:
	var b := s.env_adsr(s.lowpass_sweep(s.noise(0.35), 2400.0, 300.0), 0.02, 0.05, 0.6, 0.2)
	b = s.gain(b, 0.35)
	s.mix(b, s.env_exp(s.sweep(0.4, 120.0, 55.0), 0.002, 0.08), 0.12, 0.8)
	s.mix(b, s.lowpass(_clank(160.0, 0.2, 0.6), 1500.0), 0.12, 0.4)
	_save("menu_back", s.finish(s.reverb(b, 0.8, 0.3, 0.9), 0.65))


## Transition entre écrans : bouffée de parasites, grave qui passe.
func gen_menu_whoosh() -> void:
	var b := s.bandpass(s.noise(0.6), 1200.0, 0.8)
	b = s.bitcrush(b, 5)
	b = s.env_adsr(b, 0.12, 0.1, 0.5, 0.3)
	s.mix(b, s.env_adsr(s.sweep(0.6, 60.0, 90.0), 0.15, 0.1, 0.6, 0.3), 0.0, 0.5)
	_save("menu_whoosh", s.finish(s.reverb(b, 0.7, 0.3, 0.6), 0.45))


## Lancement d'une partie : porte blindée qui claque, chœur qui hurle et
## se coupe, grondement.
func gen_menu_start() -> void:
	var b := s.env_exp(s.sweep(2.5, 70.0, 26.0), 0.003, 0.9)
	s.mix(b, _clank(110.0, 1.2, 1.0), 0.0, 1.0)
	s.mix(b, _clank(260.0, 0.5, 0.6), 0.02, 0.5)
	s.mix(b, s.env_exp(s.lowpass(s.noise(1.5), 500.0), 0.002, 0.35), 0.0, 0.9)
	var swell := s.buf(2.6)
	for f in [146.83, 155.56, 220.0, 311.13]:
		s.mix(swell, _growl(2.6, f, f * 1.06, [700.0, 1150.0], 0.1), 0.0, 0.2)
	swell = s.env_adsr(swell, 1.9, 0.2, 1.0, 0.25)
	s.mix(b, s.lowpass(swell, 3000.0), 0.4, 0.55)
	s.mix(b, s.env_exp(s.sweep(3.0, 45.0, 30.0), 1.0, 1.2), 0.9, 0.7)
	b = s.drive(b, 1.6)
	_save("menu_start", s.finish(s.reverb(b, 0.95, 0.4, 2.5), 0.9, 0.2))


## Présence : râle lointain, étouffé, quand la silhouette apparaît au fond.
func gen_menu_presence() -> void:
	var b := _growl(2.4, 62.0, 48.0, [420.0, 780.0], 0.7)
	b = s.lowpass(b, 900.0)
	s.mix(b, s.gain(_breath(1.6, false), 0.4), 0.5, 1.0)
	_save("menu_presence", s.finish(s.reverb(b, 0.95, 0.55, 2.0), 0.7, 0.3))
