extends SceneTree
## Génère les sons du menu principal dans res://assets/audio/ (synthèse
## procédurale, graines fixes : résultat déterministe).
##   godot --headless --path . -s res://tools/gen_audio_menu.gd [-- nom1 nom2 ...]
## Sans argument : régénère tout. La boucle « menu_theme » doit être importée
## en boucle (edit/loop_mode=2 dans menu_theme.wav.import).
##
## Identité sonore propre au jeu (docs/ASSETS.md) : un laboratoire en alerte,
## la nuit (néons qui bourdonnent, ventilation, moniteurs, sirène lointaine,
## nappes de synthé) ; ni cuivres, ni chœur, ni boîte à musique, ni glas.

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
	# Intensité perçue ramenée à la cible de la catégorie (SfxLoudness).
	b = SfxLoudness.balance(n, b, float(SfxRecipes.LEVEL_OFFSETS.get(n, 0.0)))
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


## Bip de moniteur : sinus pur, attaque nette, extinction courte.
func _beep(f: float, seconds: float) -> PackedFloat32Array:
	var b := s.tone(seconds + 0.05, f)
	s.mix(b, s.tone(seconds + 0.05, f * 2.0), 0.0, 0.12)
	return s.env_adsr(b, 0.004, 0.02, 0.8, 0.03)


## Note pincée de synthé (onde carrée adoucie, filtre qui se referme).
func _pluck(f: float, seconds: float) -> PackedFloat32Array:
	var b := s.tone(seconds, f, "square")
	s.mix(b, s.tone(seconds, f * 1.004, "saw"), 0.0, 0.5)
	b = s.lowpass_sweep(b, 2400.0, 380.0)
	return s.env_exp(b, 0.004, seconds * 0.28)


## Sirène lointaine à deux tons (montée, palier, descente), étouffée.
func _siren(seconds: float, f_low: float, f_high: float) -> PackedFloat32Array:
	var n := int(seconds * Synth.RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / Synth.RATE
		# Va-et-vient lent entre les deux tons (cycle de 2,6 s).
		var k := 0.5 - 0.5 * cos(TAU * t / 2.6)
		var f := lerpf(f_low, f_high, k)
		phase += f / Synth.RATE
		var p := fmod(phase, 1.0)
		b[i] = (4.0 * absf(p - 0.5) - 1.0) * 0.8 + sin(p * TAU) * 0.2
	b = s.lowpass(b, 1500.0)
	return s.env_adsr(b, seconds * 0.3, 0.2, 0.9, seconds * 0.35)


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

## Thème du menu, boucle de 40 s à 96 bpm (64 temps) : le couloir du
## laboratoire, la nuit, en alerte. Bourdonnement des néons et ventilation,
## nappe de synthé suspendue qui change d'accord à mi-boucle, motif de
## synthé pincé en 7 croches (boiteux, inquiet), bips de moniteur réguliers,
## pulsation grave, crépitements de compteur Geiger, sirène très lointaine.
func gen_menu_theme() -> void:
	var dur := 40.0
	var beat := dur / 64.0
	var total := dur + 5.0  # queue repliée sur le début
	var b := s.buf(total)
	# Néons : 50 Hz et harmoniques, grésillement filtré ; ventilation.
	var hum := s.buf(total)
	for h in [[50.0, 0.5], [100.0, 0.35], [150.0, 0.18], [250.0, 0.06]]:
		s.mix(hum, s.tone(total, h[0]), 0.0, h[1])
	s.mix(hum, s.bandpass(s.tone(total, 100.0, "square"), 1800.0, 2.0), 0.0, 0.05)
	s.mix(b, hum, 0.0, 0.16)
	s.mix(b, s.lowpass(s.brown_noise(total), 260.0), 0.0, 0.3)
	s.mix(b, s.bandpass(s.noise(total), 900.0, 0.7), 0.0, 0.025)
	# Nappe : deux accords suspendus (la sus2 puis fa add9), scies désaccordées,
	# filtre qui s'ouvre et se referme lentement.
	var chords := [[110.0, 164.81, 246.94, 329.63], [87.31, 130.81, 196.0, 293.66]]
	for k in 2:
		var pad := s.buf(24.0)
		for f: float in chords[k]:
			for det in [-0.004, 0.003]:
				s.mix(pad, s.tone(24.0, f * (1.0 + det), "saw"), 0.0, 0.045)
		pad = s.lowpass_sweep(pad, 300.0, 1100.0)
		pad = s.env_adsr(pad, 6.0, 2.0, 0.75, 8.0)
		s.mix(b, pad, k * 20.0, 0.5)
	# Motif pincé : 7 croches par mesure (mi, si, ré, fa dièse, sol, ré, si),
	# deux fois 8 mesures dans la boucle, la deuxième fois une quarte plus bas.
	var motif := [329.63, 493.88, 587.33, 739.99, 783.99, 587.33, 493.88]
	var step := beat * 0.5
	var t := 0.0
	var i := 0
	while t < dur - 0.01:
		var f: float = motif[i % motif.size()] * (1.0 if t < dur * 0.5 else 0.75)
		var accent := 1.0 if i % motif.size() == 0 else 0.6
		# Entrée progressive : le motif ne joue que dans les mesures 3 à 7 de
		# chaque moitié (respiration du thème).
		var bar := int(t / (beat * 4.0)) % 8
		if bar >= 2 and bar <= 6:
			s.mix(b, _pluck(f, 0.6), t, 0.09 * accent)
		t += step
		i += 1
	# Bips de moniteur : un toutes les deux mesures, doublé de temps en temps.
	var bt := beat * 2.0
	var n := 0
	while bt < dur:
		s.mix(b, _beep(1046.5, 0.09), bt, 0.07)
		if n % 4 == 3:
			s.mix(b, _beep(1046.5, 0.09), bt + beat * 0.5, 0.05)
		bt += beat * 8.0
		n += 1
	# Pulsation grave sur chaque temps fort (sinus qui tombe).
	var pt := 0.0
	while pt < dur:
		s.mix(b, s.env_exp(s.sweep(0.5, 62.0, 40.0), 0.004, 0.12), pt, 0.35)
		pt += beat * 4.0
	# Compteur Geiger : clics épars, regroupés par bouffées.
	for burst: float in [6.5, 17.2, 31.0, 36.4]:
		var c := burst
		for k in s.rng.randi_range(5, 11):
			s.mix(b, s.env_exp(s.highpass(s.noise(0.01), 2500.0), 0.0002, 0.0015), c, 0.25)
			c += s.rng.randf_range(0.03, 0.25)
	# Sirène très lointaine (étouffée par les murs), une fois par boucle.
	s.mix(b, s.lowpass(_siren(9.0, 560.0, 760.0), 900.0), 22.0, 0.07)
	# Métal qui travaille, loin.
	s.mix(b, s.lowpass(_clank(140.0, 0.9, 0.8), 1600.0), 13.3, 0.22)
	b = s.reverb(b, 0.92, 0.38, 2.0)
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


## Lancement d'une partie : le sas du laboratoire s'ouvre (souffle
## pneumatique, verrou qui claque), montée de synthé, trois bips d'alarme
## qui montent, grondement grave qui retombe.
func gen_menu_start() -> void:
	var b := s.buf(3.4)
	# Verrou et sas : choc métallique, souffle pneumatique qui s'éteint.
	s.mix(b, _clank(110.0, 1.0, 1.0), 0.0, 0.9)
	s.mix(b, _clank(260.0, 0.4, 0.6), 0.03, 0.4)
	var hiss := s.env_adsr(s.bandpass(s.noise(1.4), 3200.0, 0.9), 0.01, 0.15, 0.6, 0.9)
	s.mix(b, s.lowpass_sweep(hiss, 9000.0, 1800.0), 0.05, 0.4)
	# Montée : scies qui glissent d'une quinte, filtre qui s'ouvre.
	var rise := s.buf(1.6)
	for f in [110.0, 164.81, 220.0]:
		s.mix(rise, s.sweep(1.6, f, f * 1.5, "saw"), 0.0, 0.12)
	rise = s.lowpass_sweep(rise, 300.0, 3200.0)
	rise = s.env_adsr(rise, 1.3, 0.05, 1.0, 0.2)
	s.mix(b, rise, 0.25, 0.5)
	# Trois bips d'alarme qui montent (sas ouvert).
	for k in 3:
		s.mix(b, _beep([880.0, 1046.5, 1318.5][k], 0.12), 1.55 + k * 0.17, 0.3)
	# Grondement grave qui tombe.
	s.mix(b, s.env_exp(s.sweep(2.5, 70.0, 28.0), 0.003, 0.9), 0.0, 0.8)
	s.mix(b, s.env_exp(s.lowpass(s.noise(1.5), 500.0), 0.002, 0.3), 0.0, 0.6)
	b = s.drive(b, 1.4)
	_save("menu_start", s.finish(s.reverb(b, 0.9, 0.35, 2.0), 0.9, 0.2))


## Présence : râle lointain, étouffé, quand le zombie passe au fond.
func gen_menu_presence() -> void:
	var b := _growl(2.4, 62.0, 48.0, [420.0, 780.0], 0.7)
	b = s.lowpass(b, 900.0)
	s.mix(b, s.gain(_breath(1.6, false), 0.4), 0.5, 1.0)
	_save("menu_presence", s.finish(s.reverb(b, 0.95, 0.55, 2.0), 0.7, 0.3))
