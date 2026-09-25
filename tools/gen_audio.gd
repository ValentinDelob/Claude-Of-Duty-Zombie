extends SceneTree
## Génère tous les sons du jeu dans res://assets/audio/ (synthèse procédurale).
##   godot --headless --path . -s res://tools/gen_audio.gd [-- nom1 nom2 ...]
## Sans argument : régénère tout. Déterministe (graines fixes).

const OUT := "res://assets/audio/"

var s := Synth.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := OS.get_cmdline_user_args()
	var gens := {}
	for m in get_method_list():
		if m.name.begins_with("gen_"):
			gens[m.name.substr(4)] = m.name
	print("Génération audio :")
	for key in gens:
		if only.is_empty() or key in only:
			s = Synth.new(hash(key))
			call(gens[key])
	quit()


func _save(n: String, b: PackedFloat32Array, loop := false) -> void:
	s.save(b, OUT + n + ".wav", loop)


# ---------------------------------------------------------------- armes

## Coup de feu générique : transitoire + corps de bruit filtré + « thump » grave + écho.
func _gunshot(body_cut: float, body_decay: float, thump_f: float, thump_decay: float, crack: float, room: float) -> PackedFloat32Array:
	var b := s.buf(0.05)
	var transient := s.env_exp(s.highpass(s.noise(0.02), 2500.0), 0.0005, 0.003)
	s.mix(b, transient, 0.0, crack)
	var body := s.env_exp(s.lowpass_sweep(s.noise(0.5), body_cut, body_cut * 0.15), 0.001, body_decay)
	s.mix(b, body, 0.0, 1.0)
	var thump := s.env_exp(s.sweep(0.3, thump_f, thump_f * 0.45), 0.001, thump_decay)
	s.mix(b, thump, 0.0, 1.2)
	b = s.drive(b, 2.5)
	b = s.reverb(b, room, 0.22, 0.7)
	return s.finish(b, 0.95)


func gen_pistol_fire() -> void:
	_save("pistol_fire", _gunshot(5200.0, 0.07, 140.0, 0.06, 0.9, 0.6))


func gen_smg_fire() -> void:
	_save("smg_fire", _gunshot(4600.0, 0.05, 120.0, 0.045, 0.7, 0.5))


func gen_rifle_fire() -> void:
	_save("rifle_fire", _gunshot(6000.0, 0.09, 95.0, 0.09, 1.0, 0.7))


func gen_shotgun_fire() -> void:
	_save("shotgun_fire", _gunshot(3200.0, 0.16, 70.0, 0.14, 1.0, 0.85))


func gen_lmg_fire() -> void:
	_save("lmg_fire", _gunshot(4200.0, 0.1, 80.0, 0.1, 0.8, 0.7))


func gen_sniper_fire() -> void:
	_save("sniper_fire", _gunshot(7000.0, 0.14, 60.0, 0.16, 1.0, 0.95))


func gen_dry_fire() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.05), 3500.0, 3.0), 0.0005, 0.006)
	s.mix(b, s.env_exp(s.tone(0.04, 2200.0), 0.0005, 0.008), 0.0, 0.3)
	_save("dry_fire", s.finish(b, 0.6))


## Petit choc métallique (résonances inharmoniques).
func _clank(f: float, decay: float, noise_amt := 0.6) -> PackedFloat32Array:
	var b := s.env_exp(s.bandpass(s.noise(0.2), f * 1.5, 2.0), 0.0005, decay * 0.4)
	b = s.gain(b, noise_amt)
	for ratio in [1.0, 2.76, 5.4]:
		s.mix(b, s.env_exp(s.tone(0.25, f * ratio), 0.0005, decay / ratio), 0.0, 0.35 / ratio)
	return b


func gen_mag_out() -> void:
	var b := _clank(900.0, 0.05)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.08), 1800.0, 1.0), 0.002, 0.03), 0.04, 0.5)
	_save("mag_out", s.finish(s.reverb(b, 0.3, 0.1, 0.2), 0.7))


func gen_mag_in() -> void:
	var b := _clank(1300.0, 0.04)
	s.mix(b, _clank(1700.0, 0.03), 0.05, 0.8)
	_save("mag_in", s.finish(s.reverb(b, 0.3, 0.1, 0.2), 0.75))


func gen_slide() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.12), 2600.0, 1.5), 0.01, 0.05)
	s.mix(b, _clank(1100.0, 0.05), 0.09, 1.0)
	_save("slide", s.finish(s.reverb(b, 0.3, 0.1, 0.2), 0.8))


func gen_shell() -> void:
	var b := s.buf(0.02)
	for k in 3:
		s.mix(b, _clank(3200.0 + k * 400.0, 0.03, 0.2), 0.0 + k * 0.07, 1.0 / (k + 1))
	_save("shell", s.finish(b, 0.35))


func gen_impact_concrete() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.15), 1400.0, 0.8), 0.0005, 0.03)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.2), 600.0), 0.001, 0.05), 0.0, 0.8)
	_save("impact_concrete", s.finish(b, 0.6))


func gen_weapon_switch() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.2), 1500.0, 1.0), 0.02, 0.06)
	s.mix(b, _clank(800.0, 0.06), 0.12, 0.7)
	_save("weapon_switch", s.finish(b, 0.5))


# ---------------------------------------------------------------- voix de zombie

## Voix gutturale : train d'impulsions (dent de scie) à hauteur instable passé
## dans des formants, + souffle, saturé. `f0` hauteur, `vowel` [F1, F2].
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
	var f3 := s.bandpass(src.duplicate(), 2600.0, 6.0)
	var b := s.buf(seconds)
	s.mix(b, f1, 0.0, 1.0)
	s.mix(b, f2, 0.0, 0.6)
	s.mix(b, f3, 0.0, 0.2)
	var breath := s.bandpass(s.noise(seconds), 1400.0, 1.0)
	s.mix(b, breath, 0.0, 0.25)
	b = s.env_adsr(b, 0.08, 0.2, 0.8, seconds * 0.4)
	b = s.drive(b, 3.0)
	return b


func gen_zombie_groan() -> void:
	var vowels := [[650.0, 1050.0], [480.0, 900.0], [720.0, 1250.0], [400.0, 800.0], [560.0, 1500.0]]
	for k in 5:
		s = Synth.new(900 + k)
		var dur := s.rng.randf_range(1.0, 1.8)
		var f0 := s.rng.randf_range(70.0, 105.0)
		var b := _growl(dur, f0, f0 * s.rng.randf_range(0.7, 0.95), vowels[k], 0.6)
		_save("zombie_groan_%d" % (k + 1), s.finish(s.reverb(b, 0.7, 0.25, 0.8), 0.85))


func gen_zombie_attack() -> void:
	for k in 3:
		s = Synth.new(1000 + k)
		var b := _growl(0.55, 150.0 + k * 20.0, 95.0, [800.0, 1300.0], 0.9)
		b = s.gain(b, 1.3)
		_save("zombie_attack_%d" % (k + 1), s.finish(s.reverb(b, 0.6, 0.2, 0.5), 0.95))


func gen_zombie_death() -> void:
	for k in 3:
		s = Synth.new(1100 + k)
		var b := _growl(0.9, 120.0 + k * 15.0, 55.0, [520.0, 950.0], 0.8)
		var gurgle := s.env_exp(s.bandpass(s.noise(0.9), 400.0, 2.0), 0.05, 0.4)
		s.mix(b, gurgle, 0.1, 0.5)
		_save("zombie_death_%d" % (k + 1), s.finish(s.reverb(b, 0.7, 0.25, 0.7), 0.85))


func gen_zombie_sprint() -> void:
	for k in 2:
		s = Synth.new(1200 + k)
		var b := _growl(1.2, 190.0 + k * 25.0, 150.0, [850.0, 1600.0], 1.0)
		_save("zombie_sprint_%d" % (k + 1), s.finish(s.reverb(b, 0.7, 0.25, 0.7), 0.8))


# ---------------------------------------------------------------- impacts / corps

func gen_flesh_hit() -> void:
	for k in 3:
		s = Synth.new(1300 + k)
		var b := s.env_exp(s.lowpass(s.noise(0.2), 900.0 + k * 200.0), 0.001, 0.035)
		s.mix(b, s.env_exp(s.sweep(0.12, 180.0, 70.0), 0.001, 0.04), 0.0, 0.8)
		var squish := s.env_exp(s.bandpass(s.noise(0.15), 2200.0, 3.0), 0.01, 0.03)
		s.mix(b, squish, 0.015, 0.3)
		_save("flesh_hit_%d" % (k + 1), s.finish(b, 0.8))


func gen_headshot() -> void:
	var b := s.env_exp(s.lowpass(s.noise(0.3), 1400.0), 0.001, 0.05)
	s.mix(b, s.env_exp(s.sweep(0.2, 260.0, 60.0), 0.001, 0.06), 0.0, 1.0)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.3), 3000.0, 2.0), 0.02, 0.06), 0.03, 0.5)
	_save("headshot", s.finish(s.reverb(b, 0.5, 0.15, 0.3), 0.9))


func gen_body_fall() -> void:
	var b := s.env_exp(s.lowpass(s.noise(0.5), 300.0), 0.005, 0.08)
	s.mix(b, s.env_exp(s.sweep(0.3, 90.0, 40.0), 0.002, 0.1), 0.0, 1.0)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.3), 500.0), 0.002, 0.05), 0.18, 0.5)
	_save("body_fall", s.finish(s.reverb(b, 0.5, 0.2, 0.4), 0.7))


func gen_knife_swing() -> void:
	var b := s.env_adsr(s.bandpass(s.noise(0.25), 2500.0, 1.2), 0.08, 0.05, 0.6, 0.1)
	b = s.lowpass_sweep(b, 1500.0, 5000.0)
	_save("knife_swing", s.finish(b, 0.6))


func gen_knife_hit() -> void:
	var b := s.env_exp(s.lowpass(s.noise(0.2), 1200.0), 0.001, 0.04)
	s.mix(b, s.env_exp(s.sweep(0.15, 220.0, 90.0), 0.001, 0.05), 0.0, 0.9)
	_save("knife_hit", s.finish(b, 0.85))


func gen_emerge() -> void:
	var b := s.env_adsr(s.lowpass(s.brown_noise(1.4), 700.0), 0.2, 0.3, 0.6, 0.5)
	for k in 6:
		var crumb := s.env_exp(s.bandpass(s.noise(0.1), 900.0 + s.rng.randf() * 1500.0, 2.0), 0.002, 0.02)
		s.mix(b, crumb, s.rng.randf_range(0.1, 1.2), 0.4)
	_save("emerge", s.finish(b, 0.7))


func gen_footstep() -> void:
	for k in 4:
		s = Synth.new(1400 + k)
		var b := s.env_exp(s.lowpass(s.noise(0.15), 500.0 + k * 90.0), 0.002, 0.02)
		s.mix(b, s.env_exp(s.bandpass(s.noise(0.1), 2500.0, 2.0), 0.001, 0.008), 0.0, 0.25)
		_save("footstep_%d" % (k + 1), s.finish(b, 0.5))


func gen_player_hurt() -> void:
	for k in 2:
		s = Synth.new(1500 + k)
		var b := _growl(0.35, 170.0 + k * 30.0, 130.0, [700.0, 1200.0], 0.3)
		var hit := s.env_exp(s.lowpass(s.noise(0.2), 700.0), 0.001, 0.04)
		s.mix(b, hit, 0.0, 1.0)
		_save("player_hurt_%d" % (k + 1), s.finish(b, 0.8))


func gen_hitmarker() -> void:
	var b := s.env_exp(s.tone(0.06, 2400.0, "tri"), 0.0005, 0.012)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.03), 4000.0, 2.0), 0.0005, 0.004), 0.0, 0.4)
	_save("hitmarker", s.finish(b, 0.5))


func gen_heartbeat() -> void:
	var b := s.buf(1.0)
	for at in [0.0, 0.22]:
		var beat := s.env_exp(s.sweep(0.2, 70.0, 40.0), 0.005, 0.06)
		s.mix(b, beat, at, 1.0 if at == 0.0 else 0.7)
	_save("heartbeat", s.finish(s.lowpass(b, 300.0), 0.8))


# ---------------------------------------------------------------- musique / ambiance

## Nappe de cuivres sombres : scies désaccordées, filtrées, attaque lente.
func _brass(seconds: float, freqs: Array, attack: float, cutoff: float) -> PackedFloat32Array:
	var b := s.buf(seconds)
	for f in freqs:
		for det in [-0.004, 0.0, 0.005]:
			var v := s.tone(seconds, f * (1.0 + det), "saw")
			s.mix(b, v, 0.0, 0.18)
	b = s.lowpass_sweep(b, cutoff * 0.3, cutoff)
	b = s.env_adsr(b, attack, 0.4, 0.7, seconds * 0.35)
	return b


## Cloche / glas (partiels inharmoniques).
func _bell(seconds: float, f: float) -> PackedFloat32Array:
	var b := s.buf(seconds)
	for pr in [[1.0, 1.0], [2.0, 0.6], [2.76, 0.45], [5.4, 0.25], [8.9, 0.12]]:
		s.mix(b, s.env_exp(s.tone(seconds, f * pr[0]), 0.002, seconds / (pr[0] * 0.6)), 0.0, pr[1] * 0.3)
	return b


func _timpani(f: float) -> PackedFloat32Array:
	var b := s.env_exp(s.sweep(1.2, f * 1.3, f), 0.003, 0.35)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.3), 400.0), 0.001, 0.05), 0.0, 0.6)
	return b


func gen_round_start() -> void:
	# Accord mineur grave qui enfle, glas et timbales.
	var b := _brass(4.5, [55.0, 65.4, 82.4, 110.0], 1.2, 1400.0)
	s.mix(b, _timpani(55.0), 0.0, 1.2)
	s.mix(b, _timpani(55.0), 0.35, 0.9)
	s.mix(b, _bell(4.0, 220.0), 0.1, 1.0)
	s.mix(b, _bell(4.0, 207.6), 1.4, 0.8)
	b = s.reverb(b, 0.9, 0.35, 2.5)
	_save("round_start", s.finish(b, 0.9, 0.3))


func gen_round_end() -> void:
	# Mélodie descendante de boîte à musique désaccordée, sur un bourdon.
	var b := s.buf(5.0)
	var notes := [659.3, 622.3, 523.3, 493.9, 440.0, 415.3]
	for i in notes.size():
		var n := s.env_exp(s.tone(1.5, notes[i] * (1.0 + s.rng.randf_range(-0.008, 0.008)), "tri"), 0.004, 0.45)
		s.mix(n, s.env_exp(s.tone(1.5, notes[i] * 2.01), 0.004, 0.2), 0.0, 0.3)
		s.mix(b, n, i * 0.42, 0.5)
	var drone := s.env_adsr(s.lowpass(s.tone(5.0, 55.0, "saw"), 300.0), 0.5, 1.0, 0.6, 2.0)
	s.mix(b, drone, 0.0, 0.5)
	b = s.reverb(b, 0.9, 0.4, 2.5)
	_save("round_end", s.finish(b, 0.8, 0.3))


func gen_ambience_bunker() -> void:
	# Boucle de 20 s : bourdon grave, souffle de ventilation, grincements lointains.
	var dur := 20.0
	var b := s.lowpass(s.brown_noise(dur), 180.0)
	b = s.gain(b, 0.6)
	var hum := s.tone(dur, 50.0)
	s.mix(hum, s.tone(dur, 100.0), 0.0, 0.3)
	s.mix(b, hum, 0.0, 0.05)
	var air := s.bandpass(s.noise(dur), 700.0, 0.7)
	for i in air.size():
		air[i] *= 0.5 + 0.5 * sin(TAU * i / (Synth.RATE * 5.0))
	s.mix(b, air, 0.0, 0.08)
	for k in 5:
		var creak := s.env_adsr(s.bandpass(s.sweep(1.2, s.rng.randf_range(300.0, 500.0), s.rng.randf_range(200.0, 280.0), "saw"), 900.0, 6.0), 0.3, 0.3, 0.6, 0.4)
		s.mix(b, creak, s.rng.randf_range(1.0, dur - 2.0), 0.12)
	for k in 4:
		s.mix(b, _clank(s.rng.randf_range(200.0, 400.0), 0.3), s.rng.randf_range(1.0, dur - 1.5), 0.15)
	b = s.reverb(b, 0.95, 0.4, 0.1)
	b.resize(int(dur * Synth.RATE))
	# Fondu de bouclage.
	var f := int(0.5 * Synth.RATE)
	for i in f:
		var t := float(i) / f
		b[i] = b[i] * t + b[b.size() - f + i] * (1.0 - t)
	b.resize(b.size() - f)
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	_save("ambience_bunker", s.gain(b, 0.6 / m), true)


# ---------------------------------------------------------------- interactions

func gen_purchase() -> void:
	# Loquet métallique + petite cloche fêlée : achat validé.
	var b := _clank(700.0, 0.08)
	s.mix(b, _bell(1.2, 880.0), 0.05, 0.7)
	s.mix(b, _bell(1.2, 1318.5), 0.14, 0.4)
	_save("purchase", s.finish(s.reverb(b, 0.6, 0.25, 0.6), 0.75))


func gen_denied() -> void:
	var b := s.env_adsr(s.lowpass(s.tone(0.35, 110.0, "square"), 900.0), 0.005, 0.05, 0.8, 0.08)
	s.mix(b, s.env_adsr(s.lowpass(s.tone(0.35, 116.0, "square"), 900.0), 0.005, 0.05, 0.8, 0.08), 0.0, 0.8)
	_save("denied", s.finish(b, 0.5))


func gen_door_open() -> void:
	# Grondement de moteur, raclement métallique, choc final.
	var dur := 2.2
	var b := s.env_adsr(s.lowpass(s.tone(dur, 55.0, "saw"), 250.0), 0.2, 0.3, 0.8, 0.4)
	var scrape := s.env_adsr(s.bandpass(s.noise(dur), 1800.0, 3.0), 0.3, 0.3, 0.6, 0.5)
	for i in scrape.size():
		scrape[i] *= 0.6 + 0.4 * sin(TAU * i / (Synth.RATE * 0.11))
	s.mix(b, scrape, 0.0, 0.4)
	s.mix(b, _clank(160.0, 0.5, 1.0), 1.7, 1.2)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.5), 300.0), 0.002, 0.12), 1.7, 1.0)
	_save("door_open", s.finish(s.reverb(b, 0.8, 0.3, 1.0), 0.85))
