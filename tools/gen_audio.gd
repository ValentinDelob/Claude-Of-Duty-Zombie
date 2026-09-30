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
		# Sons remplacés par des enregistrements libres de droits (CC0) :
		# jamais réécrasés ici, voir tools/audio/sfx_import.gd et docs/ASSETS.md.
		# (Séries numérotées : filtrées une à une dans _save.)
		if SfxRecipes.RECIPES.has(key):
			if key in only:
				print("  %s : remplacé par un son CC0 (sfx_import.gd), ignoré" % key)
			continue
		if only.is_empty() or key in only:
			s = Synth.new(hash(key))
			call(gens[key])
	quit()


## Liste d'exclusion : tout son qui a une recette dans SfxRecipes.RECIPES
## (enregistrement CC0 importé) n'est jamais réécrit par ce générateur.
static func replaced(n: String) -> bool:
	return SfxRecipes.RECIPES.has(n)


func _save(n: String, b: PackedFloat32Array, loop := false) -> void:
	if replaced(n):
		return
	# Intensité perçue ramenée à la cible de la catégorie (SfxLoudness).
	b = SfxLoudness.balance(n, b, float(SfxRecipes.LEVEL_OFFSETS.get(n, 0.0)))
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


func gen_minigun_fire() -> void:
	# FAUCHEUSE : coup très court (20 par seconde) et claquement métallique du
	# barillet qui tourne.
	var b := _gunshot(5000.0, 0.035, 110.0, 0.03, 0.8, 0.3)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.03), 5200.0, 5.0), 0.0005, 0.006), 0.0, 0.3)
	_save("minigun_fire", s.finish(b, 0.9))


func gen_sniper_fire() -> void:
	_save("sniper_fire", _gunshot(7000.0, 0.14, 60.0, 0.16, 1.0, 0.95))


func gen_revolver_fire() -> void:
	# .357 : détonation grave et longue, claquement sec.
	_save("revolver_fire", _gunshot(4200.0, 0.13, 90.0, 0.13, 1.0, 0.85))


func gen_burst_fire() -> void:
	# Fusil de rafale (M16, G11) : claquant, court, un peu métallique.
	var b := _gunshot(6500.0, 0.06, 110.0, 0.06, 1.0, 0.55)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.05), 3800.0, 4.0), 0.0005, 0.01), 0.0, 0.25)
	_save("burst_fire", s.finish(b, 0.95))


func gen_launcher_fire() -> void:
	# « Bloop » du lance-grenades : thump grave et creux, peu de claquement.
	var b := s.env_exp(s.sweep(0.25, 180.0, 60.0), 0.001, 0.08)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.2), 900.0), 0.001, 0.05), 0.0, 0.8)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.05), 2200.0, 2.0), 0.0005, 0.008), 0.0, 0.3)
	b = s.drive(b, 2.0)
	_save("launcher_fire", s.finish(s.reverb(b, 0.6, 0.2, 0.6), 0.9))


func gen_rocket_fire() -> void:
	# Mise à feu + souffle de la roquette qui s'éloigne.
	var b := _gunshot(3000.0, 0.12, 70.0, 0.12, 0.8, 0.7)
	var whoosh := s.env_adsr(s.lowpass_sweep(s.noise(1.0), 2500.0, 500.0), 0.02, 0.2, 0.6, 0.6)
	s.mix(b, whoosh, 0.02, 0.7)
	_save("rocket_fire", s.finish(s.reverb(b, 0.8, 0.3, 0.8), 0.9))


func gen_explosion() -> void:
	# Explosion : craquement, souffle grave et grondement qui s'éteint.
	var b := s.env_exp(s.highpass(s.noise(0.03), 1500.0), 0.0005, 0.01)
	s.mix(b, s.env_exp(s.lowpass_sweep(s.noise(1.4), 3000.0, 150.0), 0.002, 0.35), 0.0, 1.0)
	s.mix(b, s.env_exp(s.sweep(1.0, 90.0, 30.0), 0.002, 0.4), 0.0, 1.4)
	s.mix(b, s.env_exp(s.lowpass(s.noise(1.6), 250.0), 0.05, 0.6), 0.05, 0.8)
	b = s.drive(b, 3.0)
	_save("explosion", s.finish(s.reverb(b, 0.9, 0.3, 1.2), 0.98))


func gen_shell_in() -> void:
	# Cartouche glissée dans le magasin tubulaire.
	var b := s.env_exp(s.bandpass(s.noise(0.06), 2000.0, 1.5), 0.004, 0.02)
	s.mix(b, _clank(1500.0, 0.03, 0.4), 0.03, 0.7)
	_save("shell_in", s.finish(s.reverb(b, 0.3, 0.1, 0.2), 0.6))


func gen_pump() -> void:
	# Pompe : arrière (raclement + choc) puis avant (choc plus sec).
	var b := s.env_exp(s.bandpass(s.noise(0.1), 1800.0, 1.2), 0.005, 0.04)
	s.mix(b, _clank(700.0, 0.05), 0.06, 0.9)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.08), 2200.0, 1.2), 0.005, 0.03), 0.16, 0.8)
	s.mix(b, _clank(950.0, 0.05), 0.2, 1.0)
	_save("pump", s.finish(s.reverb(b, 0.3, 0.1, 0.3), 0.8))


func gen_bolt() -> void:
	# Culasse à verrou : levée, recul, avant, verrouillage.
	var b := _clank(1200.0, 0.03, 0.5)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.1), 2600.0, 1.5), 0.01, 0.04), 0.05, 0.6)
	s.mix(b, _clank(900.0, 0.04), 0.14, 0.9)
	s.mix(b, _clank(1400.0, 0.03), 0.24, 0.8)
	_save("bolt", s.finish(s.reverb(b, 0.3, 0.1, 0.3), 0.75))


func gen_break_open() -> void:
	# Bascule des canons / du barillet : déclic puis charnière.
	var b := _clank(1600.0, 0.02, 0.3)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.12), 900.0, 2.0), 0.01, 0.05), 0.03, 0.7)
	_save("break_open", s.finish(s.reverb(b, 0.3, 0.1, 0.2), 0.65))


func gen_break_close() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.05), 1200.0, 1.5), 0.003, 0.02)
	s.mix(b, _clank(800.0, 0.06), 0.04, 1.0)
	_save("break_close", s.finish(s.reverb(b, 0.3, 0.1, 0.2), 0.8))


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


# (impacts sur le décor : enregistrements CC0 impact_concrete/metal/wood_1..2,
# voir SfxRecipes.)


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


## Atterrissage d'un plongeon : corps lourd sur le béton, équipement qui
## s'entrechoque, frottement du treillis.
func gen_dive_land() -> void:
	var b := s.env_exp(s.lowpass(s.noise(0.5), 260.0), 0.003, 0.12)
	s.mix(b, s.env_exp(s.sweep(0.3, 110.0, 45.0), 0.002, 0.12), 0.0, 1.1)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.08), 3000.0, 3.0), 0.001, 0.02), 0.02, 0.35)
	s.mix(b, s.env_adsr(s.bandpass(s.noise(0.3), 1400.0, 0.8), 0.02, 0.05, 0.4, 0.15), 0.05, 0.3)
	_save("dive_land", s.finish(s.reverb(b, 0.45, 0.18, 0.4), 0.85))


## Lame qui entre dans la chair : déchirure humide + coup sourd.
func gen_knife_flesh() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.3), 900.0, 1.5), 0.002, 0.07)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.25), 450.0), 0.001, 0.09), 0.01, 0.9)
	s.mix(b, s.env_exp(s.sweep(0.12, 160.0, 70.0), 0.001, 0.04), 0.0, 0.7)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.15), 2200.0, 3.0), 0.001, 0.02), 0.03, 0.25)
	_save("knife_flesh", s.finish(b, 0.8))


## Couteau de chasse sorti de son étui : frottement du cuir puis tintement de la lame.
func gen_bowie_draw() -> void:
	var b := s.env_adsr(s.bandpass(s.noise(0.45), 1800.0, 1.0), 0.12, 0.1, 0.5, 0.15)
	var ring := s.buf(0.9)
	for f in [2900.0, 4350.0, 6100.0]:
		s.mix(ring, s.env_exp(s.tone(0.9, f), 0.001, 0.35 * 3000.0 / f), 0.0, 0.18)
	s.mix(b, ring, 0.4, 1.0)
	s.mix(b, s.env_exp(s.highpass(s.noise(0.05), 3500.0), 0.001, 0.01), 0.4, 0.5)
	_save("bowie_draw", s.finish(s.reverb(b, 0.35, 0.15, 0.3), 0.75))


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


func gen_ambience_kino() -> void:
	# Boucle de 24 s du théâtre : vaste salle vide (souffle grave), cliquetis
	# lointain d'un projecteur, grincements de parquet et de fauteuils,
	# quelques notes d'un orgue de cinéma désaccordé, noyées dans la réverbération.
	var dur := 24.0
	var b := s.lowpass(s.brown_noise(dur), 140.0)
	b = s.gain(b, 0.55)
	var hum := s.tone(dur, 60.0)
	s.mix(hum, s.tone(dur, 120.0), 0.0, 0.25)
	s.mix(b, hum, 0.0, 0.03)
	# Projecteur : claquements réguliers (18 par seconde) qui vont et viennent.
	var proj := s.buf(dur)
	var click := s.env_exp(s.bandpass(s.noise(0.02), 2400.0, 3.0), 0.0005, 0.006)
	var t := 0.0
	while t < dur - 0.1:
		s.mix(proj, click, t, 0.5 + 0.5 * sin(t * 0.5))
		t += 1.0 / 18.0
	s.mix(b, s.lowpass(proj, 3000.0), 0.0, 0.05)
	for k in 6:
		var creak := s.env_adsr(s.bandpass(s.sweep(1.4, s.rng.randf_range(250.0, 420.0), s.rng.randf_range(160.0, 240.0), "saw"), 800.0, 7.0), 0.3, 0.3, 0.6, 0.5)
		s.mix(b, creak, s.rng.randf_range(1.0, dur - 2.5), 0.1)
	# Orgue : accords mineurs lents, légèrement faux.
	var chords := [[220.0, 261.6, 329.6], [196.0, 233.1, 293.7], [174.6, 207.7, 261.6]]
	for k in chords.size():
		var ch := s.buf(5.0)
		for f in chords[k]:
			var detune: float = f * (1.0 + s.rng.randf_range(-0.008, 0.008))
			s.mix(ch, s.tone(5.0, detune, "saw"), 0.0, 0.25)
			s.mix(ch, s.tone(5.0, detune * 2.0), 0.0, 0.15)
		ch = s.env_adsr(s.lowpass(ch, 900.0), 1.5, 0.5, 0.7, 2.0)
		s.mix(b, ch, 3.0 + k * 7.0, 0.05)
	b = s.reverb(b, 0.97, 0.5, 0.1)
	b.resize(int(dur * Synth.RATE))
	var f := int(0.5 * Synth.RATE)
	for i in f:
		var x := float(i) / f
		b[i] = b[i] * x + b[b.size() - f + i] * (1.0 - x)
	b.resize(b.size() - f)
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	_save("ambience_kino", s.gain(b, 0.6 / m), true)


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


func gen_lever() -> void:
	var b := _clank(300.0, 0.25, 1.0)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.3), 500.0), 0.002, 0.06), 0.0, 0.8)
	_save("lever", s.finish(s.reverb(b, 0.6, 0.2, 0.5), 0.8))


func gen_power_on() -> void:
	# Coup sourd, arc électrique, puis ronronnement qui monte (turbine).
	var dur := 5.0
	var b := s.env_exp(s.sweep(0.8, 80.0, 35.0), 0.002, 0.3)
	var arc := s.env_exp(s.highpass(s.noise(0.6), 3000.0), 0.001, 0.12)
	for i in arc.size():
		arc[i] *= 1.0 if s.rng.randf() < 0.3 else 0.2
	s.mix(b, arc, 0.05, 0.6)
	var hum := s.sweep(dur - 0.5, 30.0, 60.0, "saw")
	s.mix(hum, s.sweep(dur - 0.5, 60.0, 120.0), 0.0, 0.5)
	hum = s.env_adsr(s.lowpass(hum, 500.0), 1.5, 0.5, 0.8, 1.2)
	s.mix(b, hum, 0.4, 0.8)
	_save("power_on", s.finish(s.reverb(b, 0.9, 0.3, 1.5), 0.9, 0.2))


func gen_lamp_on() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.2), 2500.0, 2.0), 0.001, 0.02)
	s.mix(b, s.env_adsr(s.tone(0.4, 120.0, "square"), 0.01, 0.05, 0.3, 0.2), 0.02, 0.15)
	_save("lamp_on", s.finish(b, 0.5))


# ---------------------------------------------------------------- atouts

## Petite ritournelle « orgue de barbarie » désaccordée. notes : [demi-tons, durée]
func _jingle(notes: Array, root_hz: float, tempo: float, wave: String) -> PackedFloat32Array:
	var b := s.buf(0.1)
	var t := 0.0
	for n in notes:
		var f: float = root_hz * pow(2.0, float(n[0]) / 12.0) * (1.0 + s.rng.randf_range(-0.006, 0.006))
		var d: float = n[1] * tempo
		if n[0] > -99:
			var v := s.env_adsr(s.tone(d + 0.3, f, wave), 0.01, 0.08, 0.5, 0.25)
			s.mix(v, s.env_exp(s.tone(d + 0.3, f * 2.0), 0.005, 0.1), 0.0, 0.25)
			s.mix(b, v, t, 0.4)
		t += d
	# Basse d'accompagnement.
	var bass := s.env_adsr(s.lowpass(s.tone(t + 0.3, root_hz / 2.0, "tri"), 400.0), 0.05, 0.2, 0.5, 0.4)
	s.mix(b, bass, 0.0, 0.3)
	b = s.bitcrush(s.lowpass(b, 5000.0), 10)
	return s.finish(s.reverb(b, 0.6, 0.25, 0.8), 0.75)


func gen_jingle_titan() -> void:
	_save("jingle_titan", _jingle([[0, 1], [0, 0.5], [3, 0.5], [7, 1], [5, 0.5], [3, 0.5], [0, 2]], 196.0, 0.22, "saw"))


func gen_jingle_rapid() -> void:
	_save("jingle_rapid", _jingle([[0, 0.5], [4, 0.5], [7, 0.5], [12, 0.5], [7, 0.5], [4, 0.5], [0, 0.5], [12, 1.5]], 293.7, 0.15, "square"))


func gen_jingle_twin() -> void:
	_save("jingle_twin", _jingle([[0, 0.5], [0, 0.5], [5, 1], [5, 0.5], [5, 0.5], [9, 1], [7, 0.5], [5, 0.5], [0, 2]], 261.6, 0.18, "tri"))


func gen_jingle_lazarus() -> void:
	_save("jingle_lazarus", _jingle([[7, 1], [5, 0.5], [4, 0.5], [2, 1], [0, 1], [-5, 1], [0, 2]], 329.6, 0.24, "tri"))


func gen_jingle_stride() -> void:
	_save("jingle_stride", _jingle([[0, 0.5], [2, 0.5], [4, 0.5], [5, 0.5], [7, 1], [9, 0.5], [7, 0.5], [12, 2]], 246.9, 0.17, "saw"))


func gen_jingle_nova() -> void:
	# NOVA FLOP : air de guitare surf, montée puis chute (le plongeon).
	_save("jingle_nova", _jingle([[0, 0.5], [3, 0.5], [5, 0.5], [7, 1], [10, 0.5], [7, 0.5], [12, 1], [-99, 0.5], [0, 0.5], [-5, 2]], 220.0, 0.16, "square"))


func gen_jingle_deadeye() -> void:
	# DEADEYE DRAM : marche lente et grave de western, notes pointées.
	_save("jingle_deadeye", _jingle([[0, 1.5], [0, 0.5], [7, 1], [5, 0.5], [3, 0.5], [2, 1], [-2, 1], [0, 2]], 174.6, 0.2, "tri"))


func gen_nova_blast() -> void:
	# Plongeon explosif : impact sourd, souffle électrique qui s'ouvre, crépitement.
	var b := s.env_exp(s.lowpass(s.noise(0.05), 900.0), 0.0005, 0.02)
	s.mix(b, s.env_exp(s.sweep(0.8, 140.0, 35.0), 0.001, 0.3), 0.0, 1.5)
	s.mix(b, s.env_exp(s.lowpass_sweep(s.noise(1.1), 600.0, 5200.0), 0.004, 0.25), 0.0, 0.9)
	s.mix(b, s.env_exp(s.sweep(0.9, 380.0, 1400.0, "saw"), 0.01, 0.3), 0.02, 0.25)
	for k in 10:
		var crack := s.env_exp(s.bandpass(s.noise(0.03), s.rng.randf_range(2500.0, 7000.0), 3.0), 0.0005, 0.006)
		s.mix(b, crack, 0.08 + s.rng.randf_range(0.0, 0.6), s.rng.randf_range(0.15, 0.35))
	b = s.drive(b, 2.8)
	_save("nova_blast", s.finish(s.reverb(b, 0.85, 0.3, 1.1), 0.97))


func gen_perk_drink() -> void:
	# Capsule, gorgées, bouteille jetée.
	var b := _clank(2200.0, 0.05, 0.4)
	for k in 3:
		var gulp := s.env_exp(s.lowpass(s.sweep(0.18, 300.0, 160.0), 900.0), 0.01, 0.06)
		s.mix(b, gulp, 0.35 + k * 0.28, 0.9)
	s.mix(b, _clank(1200.0, 0.2, 0.6), 1.5, 0.8)
	s.mix(b, _clank(1500.0, 0.15, 0.4), 1.62, 0.5)
	_save("perk_drink", s.finish(s.reverb(b, 0.5, 0.2, 0.4), 0.8))


# ---------------------------------------------------------------- boîte mystère

func gen_box_open() -> void:
	# Grincement de charnière + choc du couvercle.
	var creak := s.env_adsr(s.bandpass(s.sweep(0.7, 420.0, 260.0, "saw"), 900.0, 5.0), 0.05, 0.2, 0.7, 0.2)
	var b := s.gain(creak, 0.6)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.3), 700.0), 0.002, 0.05), 0.65, 0.9)
	_save("box_open", s.finish(s.reverb(b, 0.6, 0.2, 0.5), 0.75))


func gen_box_music() -> void:
	# Boîte à musique qui ralentit et se désaccorde (4 s).
	var notes := [12, 7, 3, 7, 12, 15, 14, 10, 7, 10, 14, 12, 8, 3, 0]
	var b := s.buf(4.5)
	var t := 0.0
	for i in notes.size():
		var k := float(i) / notes.size()
		var f: float = 523.25 * pow(2.0, notes[i] / 12.0) * (1.0 - k * 0.04)
		var n := s.env_exp(s.tone(0.8, f, "tri"), 0.003, 0.25)
		s.mix(n, s.env_exp(s.tone(0.8, f * 3.0), 0.002, 0.08), 0.0, 0.2)
		s.mix(b, n, t, 0.5)
		t += lerpf(0.18, 0.38, k * k)
	_save("box_music", s.finish(s.reverb(b, 0.7, 0.3, 1.0), 0.7))


func gen_box_skull() -> void:
	# Ricanement démoniaque : « ha ha ha » graves et saturés.
	var b := s.buf(0.1)
	for k in 5:
		var ha := _growl(0.22, 140.0 - k * 12.0, 110.0 - k * 10.0, [750.0, 1150.0], 0.7)
		s.mix(b, ha, 0.05 + k * 0.26, 1.0 - k * 0.1)
	var drone := s.env_adsr(s.lowpass(s.tone(2.2, 41.0, "saw"), 200.0), 0.1, 0.5, 0.7, 0.8)
	s.mix(b, drone, 0.0, 0.6)
	_save("box_skull", s.finish(s.reverb(b, 0.9, 0.35, 1.5), 0.9))


func gen_box_fly() -> void:
	var b := s.env_adsr(s.bandpass(s.noise(1.6), 700.0, 1.2), 0.3, 0.4, 0.7, 0.6)
	b = s.lowpass_sweep(b, 400.0, 3000.0)
	s.mix(b, s.env_exp(s.sweep(1.2, 200.0, 900.0, "saw"), 0.2, 0.5), 0.0, 0.15)
	_save("box_fly", s.finish(s.reverb(b, 0.8, 0.3, 1.0), 0.75))


func gen_ray_fire() -> void:
	# Tir d'énergie : glissando descendant, harmoniques, grésillement.
	var b := s.env_exp(s.sweep(0.5, 2400.0, 180.0, "square"), 0.001, 0.12)
	s.mix(b, s.env_exp(s.sweep(0.5, 1200.0, 90.0, "saw"), 0.001, 0.15), 0.0, 0.6)
	var fizz := s.env_exp(s.highpass(s.noise(0.3), 4000.0), 0.001, 0.05)
	s.mix(b, fizz, 0.0, 0.4)
	b = s.lowpass(b, 6000.0)
	_save("ray_fire", s.finish(s.reverb(b, 0.6, 0.25, 0.6), 0.85))


func gen_thunder_fire() -> void:
	# TONNERRE-7 : détonation d'air comprimé énorme. Claquement, coup de
	# boutoir infra-grave, souffle qui balaie la pièce, grondement de tonnerre.
	var dur := 2.6
	var b := s.buf(dur)
	s.mix(b, s.env_exp(s.highpass(s.noise(0.04), 1800.0), 0.0005, 0.012), 0.0, 0.9)
	s.mix(b, s.env_exp(s.sweep(0.9, 75.0, 24.0), 0.002, 0.35), 0.0, 1.6)
	s.mix(b, s.env_exp(s.sweep(0.5, 160.0, 45.0, "saw"), 0.001, 0.12), 0.0, 0.5)
	# Souffle : bruit dont le filtre descend (l'onde s'éloigne).
	s.mix(b, s.env_adsr(s.lowpass_sweep(s.noise(1.2), 5000.0, 250.0), 0.01, 0.25, 0.5, 0.7), 0.0, 1.0)
	# Grondement : bruit brun très grave qui roule et s'éteint.
	var rumble := s.env_adsr(s.lowpass(s.brown_noise(dur - 0.1), 180.0), 0.08, 0.5, 0.6, 1.4)
	s.mix(b, rumble, 0.08, 1.2)
	b = s.drive(b, 3.5)
	_save("thunder_fire", s.finish(s.reverb(b, 0.95, 0.35, 1.6), 0.98, 0.3))


func gen_thunder_charge() -> void:
	# Mise en pression du tambour : sifflement qui monte, cliquetis, soupape.
	var b := s.env_adsr(s.sweep(1.0, 120.0, 900.0, "saw"), 0.05, 0.2, 0.8, 0.2)
	b = s.lowpass_sweep(b, 400.0, 3500.0)
	s.mix(b, s.env_adsr(s.bandpass(s.noise(1.0), 2500.0, 1.5), 0.3, 0.3, 0.5, 0.2), 0.0, 0.35)
	for k in 3:
		s.mix(b, _clank(260.0 + k * 40.0, 0.06, 0.8), 0.15 + k * 0.22, 0.4)
	s.mix(b, s.env_exp(s.highpass(s.noise(0.3), 3000.0), 0.002, 0.1), 0.85, 0.5)
	_save("thunder_charge", s.finish(s.reverb(b, 0.5, 0.2, 0.4), 0.8))


func gen_zombie_fling() -> void:
	# Zombie projeté : cri étranglé qui s'envole + froissement d'air.
	var b := _growl(0.8, 170.0, 260.0, [760.0, 1400.0], 0.9)
	s.mix(b, s.env_adsr(s.bandpass(s.noise(0.8), 900.0, 0.8), 0.02, 0.2, 0.5, 0.4), 0.0, 0.6)
	_save("zombie_fling", s.finish(s.reverb(b, 0.7, 0.25, 0.6), 0.85))


# ---------------------------------------------------------------- Pack-a-Punch

## Chœur sombre : voyelles « aah » sur un accord (pulsations de voix).
func _choir(seconds: float, freqs: Array) -> PackedFloat32Array:
	var b := s.buf(seconds)
	for f in freqs:
		var v := _growl(seconds, f, f, [700.0, 1100.0], 0.05)
		s.mix(b, v, 0.0, 0.25)
	return s.env_adsr(s.lowpass(b, 2500.0), seconds * 0.3, 0.3, 0.8, seconds * 0.3)


func gen_pap_forge() -> void:
	# Machinerie : martèlement, arcs électriques, chœur qui monte (4 s).
	var dur := 4.0
	var b := _choir(dur, [110.0, 130.8, 164.8])
	for k in 8:
		s.mix(b, _clank(180.0 + s.rng.randf() * 80.0, 0.25, 1.0), 0.2 + k * 0.45, 0.7)
	var arc := s.env_adsr(s.highpass(s.noise(dur), 3500.0), 0.5, 0.5, 0.4, 0.5)
	for i in arc.size():
		@warning_ignore("integer_division")
		arc[i] *= 1.0 if (i / 900) % 3 == 0 else 0.1
	s.mix(b, arc, 0.0, 0.25)
	_save("pap_forge", s.finish(s.reverb(b, 0.9, 0.35, 1.5), 0.9, 0.2))


func gen_pap_ready() -> void:
	var b := _bell(3.0, 110.0)
	s.mix(b, _choir(2.5, [220.0, 277.2, 329.6]), 0.0, 0.9)
	s.mix(b, _timpani(55.0), 0.0, 1.0)
	_save("pap_ready", s.finish(s.reverb(b, 0.9, 0.35, 1.8), 0.9, 0.3))


# ---------------------------------------------------------------- téléporteur

func gen_tele_charge() -> void:
	# Montée de tension (3 s) : sifflement qui grimpe, bourdonnement, arcs.
	var b := s.env_adsr(s.sweep(3.1, 80.0, 900.0, "saw"), 0.2, 0.3, 0.9, 0.1)
	b = s.lowpass_sweep(b, 300.0, 5000.0)
	s.mix(b, s.env_adsr(s.sweep(3.1, 400.0, 3200.0), 0.5, 0.3, 0.6, 0.1), 0.0, 0.3)
	var arcs := s.highpass(s.noise(3.1), 3000.0)
	for i in arcs.size():
		arcs[i] *= 1.0 if s.rng.randf() < 0.12 * (float(i) / arcs.size()) else 0.0
	s.mix(b, arcs, 0.0, 0.5)
	_save("tele_charge", s.finish(s.reverb(b, 0.7, 0.25, 0.6), 0.85))


func gen_tele_warp() -> void:
	var b := s.env_exp(s.sweep(1.0, 1500.0, 40.0, "saw"), 0.002, 0.3)
	s.mix(b, s.env_exp(s.lowpass(s.noise(1.0), 1200.0), 0.002, 0.25), 0.0, 0.8)
	s.mix(b, _timpani(45.0), 0.05, 1.0)
	_save("tele_warp", s.finish(s.reverb(b, 0.9, 0.35, 1.2), 0.9))


# ---------------------------------------------------------------- piège

func gen_trap_hum() -> void:
	# Boucle de 2 s : bourdonnement 50 Hz saturé + crépitements.
	var dur := 2.0
	var b := s.tone(dur, 50.0, "square")
	s.mix(b, s.tone(dur, 100.0, "saw"), 0.0, 0.5)
	b = s.drive(s.lowpass(b, 1200.0), 3.0)
	b = s.gain(b, 0.5)
	var crackle := s.highpass(s.noise(dur), 2500.0)
	for i in crackle.size():
		crackle[i] *= 1.0 if s.rng.randf() < 0.04 else 0.05
	s.mix(b, crackle, 0.0, 0.6)
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	b.resize(int(dur * Synth.RATE))
	_save("trap_hum", s.gain(b, 0.7 / m), true)


func gen_zap() -> void:
	var b := s.env_exp(s.highpass(s.noise(0.4), 2000.0), 0.001, 0.08)
	for i in b.size():
		@warning_ignore("integer_division")
		b[i] *= 1.0 if (i / 300) % 2 == 0 else 0.3
	s.mix(b, s.env_exp(s.sweep(0.3, 900.0, 100.0, "square"), 0.001, 0.08), 0.0, 0.4)
	_save("zap", s.finish(s.reverb(b, 0.5, 0.2, 0.4), 0.8))


# ---------------------------------------------------------------- interface

func gen_ui_move() -> void:
	# Cliquetis de relais + souffle radio.
	var b := s.env_exp(s.bandpass(s.noise(0.08), 2800.0, 4.0), 0.0005, 0.01)
	s.mix(b, s.env_exp(s.tone(0.08, 180.0, "square"), 0.001, 0.015), 0.0, 0.15)
	_save("ui_move", s.finish(s.reverb(b, 0.4, 0.2, 0.3), 0.5))


func gen_ui_select() -> void:
	# Coup sourd métallique + queue grave.
	var b := _clank(220.0, 0.2, 0.8)
	s.mix(b, s.env_exp(s.sweep(0.5, 90.0, 45.0), 0.002, 0.18), 0.0, 1.0)
	_save("ui_select", s.finish(s.reverb(b, 0.8, 0.35, 1.0), 0.85))


func gen_ui_back() -> void:
	var b := s.env_exp(s.sweep(0.25, 400.0, 150.0, "tri"), 0.002, 0.06)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.1), 1500.0, 2.0), 0.001, 0.02), 0.0, 0.4)
	_save("ui_back", s.finish(s.reverb(b, 0.5, 0.2, 0.4), 0.6))


func gen_ui_error() -> void:
	var b := s.env_adsr(s.lowpass(s.tone(0.6, 82.0, "saw"), 600.0), 0.01, 0.1, 0.7, 0.3)
	s.mix(b, s.env_adsr(s.lowpass(s.tone(0.6, 87.0, "saw"), 600.0), 0.01, 0.1, 0.7, 0.3), 0.0, 0.8)
	_save("ui_error", s.finish(s.reverb(b, 0.7, 0.3, 0.8), 0.7))


# ---------------------------------------------------------------- à terre / réanimation

func gen_player_down() -> void:
	# Chute lourde, râle, cloche funèbre lointaine.
	var b := s.env_exp(s.lowpass(s.noise(0.5), 400.0), 0.003, 0.1)
	s.mix(b, _growl(0.6, 150.0, 90.0, [650.0, 1000.0], 0.4), 0.05, 0.8)
	s.mix(b, _bell(3.0, 146.8), 0.2, 0.7)
	_save("player_down", s.finish(s.reverb(b, 0.9, 0.35, 1.5), 0.85))


func gen_revive() -> void:
	# Inspiration brusque + accord qui se résout vers le haut.
	var breath := s.env_adsr(s.bandpass(s.noise(0.5), 1800.0, 1.2), 0.2, 0.1, 0.5, 0.2)
	var b := s.gain(breath, 0.7)
	for f in [220.0, 277.2, 329.6, 440.0]:
		s.mix(b, s.env_adsr(s.tone(1.4, f, "tri"), 0.3, 0.3, 0.5, 0.6), 0.2, 0.18)
	_save("revive", s.finish(s.reverb(b, 0.8, 0.3, 1.0), 0.75))


# ---------------------------------------------------------------- bonus

## Boucle sans couture : `b` doit durer au moins `dur` + 0,25 s ; la queue est
## fondue dans le début, puis le tout est normalisé à `peak`.
func _seamless(b: PackedFloat32Array, dur: float, peak: float) -> PackedFloat32Array:
	var n := int(dur * Synth.RATE)
	var x := int(0.25 * Synth.RATE)
	if b.size() < n + x:
		b.resize(n + x)
	for i in x:
		var k := float(i) / x
		b[i] = b[i] * k + b[n + i] * (1.0 - k)
	b.resize(n)
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	return s.gain(b, peak / m)


## Scintillement magique : arpège de clochettes aiguës.
func _sparkle(seconds: float, root_hz: float, count: int) -> PackedFloat32Array:
	var b := s.buf(seconds)
	for k in count:
		var f := root_hz * pow(2.0, float([0, 4, 7, 12, 16, 19, 24][k % 7]) / 12.0)
		s.mix(b, s.env_exp(s.tone(0.6, f), 0.002, 0.18), k * seconds / count * 0.8, 0.25)
	return b


func gen_powerup_spawn() -> void:
	# Apparition : souffle ascendant + arpège de clochettes.
	var b := s.env_adsr(s.lowpass_sweep(s.noise(0.9), 400.0, 5000.0), 0.3, 0.2, 0.5, 0.4)
	b = s.gain(b, 0.35)
	s.mix(b, _sparkle(0.9, 1046.5, 7), 0.1, 1.0)
	_save("powerup_spawn", s.finish(s.reverb(b, 0.8, 0.35, 1.0), 0.7))


func gen_powerup_loop() -> void:
	# Boucle de 2 s : bourdonnement éthéré pulsé (quintes douces, trémolo).
	var dur := 2.0
	var total := dur + 0.3
	var b := s.buf(total)
	for f in [220.0, 330.0, 440.0, 660.0]:
		s.mix(b, s.tone(total, f, "tri"), 0.0, 0.12)
	for i in b.size():
		var t := float(i) / Synth.RATE
		b[i] *= 0.6 + 0.4 * sin(t * TAU * 2.0)  # 2 Hz : entier sur 2 s
	var shimmer := s.bandpass(s.noise(total), 6000.0, 3.0)
	s.mix(b, shimmer, 0.0, 0.15)
	b = s.lowpass(b, 4000.0)
	_save("powerup_loop", _seamless(b, dur, 0.5), true)


func gen_powerup_grab() -> void:
	# Ramassage : accord brillant ascendant + clochettes.
	var b := s.buf(1.2)
	for i in 4:
		var f: float = [523.25, 659.3, 784.0, 1046.5][i]
		s.mix(b, s.env_exp(s.tone(1.0, f, "tri"), 0.003, 0.4), i * 0.05, 0.3)
	s.mix(b, _sparkle(0.8, 2093.0, 6), 0.15, 0.8)
	s.mix(b, s.env_exp(s.sweep(0.4, 300.0, 1400.0), 0.01, 0.15), 0.0, 0.4)
	_save("powerup_grab", s.finish(s.reverb(b, 0.8, 0.35, 1.2), 0.8))


func gen_powerup_end() -> void:
	# Fin d'un bonus temporisé : note descendante voilée.
	var b := s.env_exp(s.sweep(0.9, 660.0, 220.0, "tri"), 0.01, 0.35)
	s.mix(b, s.env_exp(s.sweep(0.9, 990.0, 330.0), 0.01, 0.25), 0.0, 0.4)
	_save("powerup_end", s.finish(s.reverb(b, 0.8, 0.3, 1.0), 0.6))


func gen_powerup_nuke() -> void:
	# Détonation lointaine : choc, grondement qui roule, souffle.
	var b := s.env_exp(s.lowpass(s.noise(3.5), 180.0), 0.005, 1.4)
	b = s.gain(b, 1.6)
	s.mix(b, s.env_exp(s.sweep(1.5, 90.0, 28.0), 0.002, 0.8), 0.0, 1.3)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.4), 1200.0, 0.8), 0.001, 0.08), 0.0, 0.7)
	s.mix(b, s.env_adsr(s.lowpass_sweep(s.noise(2.5), 2500.0, 200.0), 0.2, 0.4, 0.5, 1.2), 0.1, 0.4)
	b = s.drive(b, 2.0)
	_save("powerup_nuke", s.finish(s.reverb(b, 0.95, 0.4, 2.0), 0.95, 0.3))


func gen_fire_sale_loop() -> void:
	# Ritournelle de fête foraine désaccordée (boucle de 6,4 s : 32 croches à 0,2 s).
	var step := 0.2
	var notes := [0, 4, 7, 12, 11, 7, 4, 7, 5, 9, 12, 17, 16, 12, 9, 12,
		7, 11, 14, 19, 17, 14, 11, 14, 12, 7, 4, 0, 2, 4, 5, 7]
	var dur := notes.size() * step
	var b := s.buf(dur + 0.4)
	for i in notes.size():
		var f: float = 392.0 * pow(2.0, float(notes[i]) / 12.0) * (1.0 + s.rng.randf_range(-0.01, 0.01))
		var v := s.env_exp(s.tone(0.5, f, "square"), 0.004, 0.12)
		s.mix(v, s.env_exp(s.tone(0.5, f * 2.0), 0.003, 0.08), 0.0, 0.4)
		s.mix(b, v, i * step, 0.25)
		# Basse « oom-pah ».
		@warning_ignore("integer_division")
		var bass_f: float = 98.0 if (i / 8) % 2 == 0 else 130.8
		if i % 2 == 0:
			s.mix(b, s.env_exp(s.tone(0.3, bass_f, "tri"), 0.004, 0.12), i * step, 0.5)
	b = s.bitcrush(s.lowpass(b, 4500.0), 9)
	_save("fire_sale_loop", _seamless(b, dur, 0.6), true)


## Voix d'annonceur démoniaque : syllabes = [[F1, F2], durée], très graves,
## saturées, doublées à l'octave inférieure, dans une grande réverbe.
func _announcer(syllables: Array, f0: float) -> PackedFloat32Array:
	var b := s.buf(0.1)
	var t := 0.0
	for syl in syllables:
		var d: float = syl[1]
		var v := _growl(d, f0, f0 * 0.85, syl[0], 0.25)
		s.mix(v, _growl(d, f0 * 0.5, f0 * 0.43, syl[0], 0.2), 0.0, 0.6)
		s.mix(b, v, t, 1.0)
		t += d * 0.9
	return b


const VA := [750.0, 1150.0]
const VE := [500.0, 1700.0]
const VI := [320.0, 2200.0]
const VO := [450.0, 800.0]
const VU := [330.0, 700.0]


func _announce_save(n: String, voice: PackedFloat32Array, sting: PackedFloat32Array) -> void:
	var b := s.gain(sting, 0.8)
	s.mix(b, voice, 0.15, 1.0)
	_save(n, s.finish(s.reverb(b, 0.9, 0.35, 1.5), 0.9))


func gen_announce_max_ammo() -> void:
	# « MAX AM-MO » + cuivres ascendants.
	var voice := _announcer([[VA, 0.32], [VA, 0.22], [VO, 0.4]], 88.0)
	var sting := _brass(1.4, [110.0, 138.6, 164.8], 0.05, 2500.0)
	s.mix(sting, _timpani(55.0), 0.0, 1.0)
	_announce_save("announce_max_ammo", voice, sting)


func gen_announce_insta_kill() -> void:
	# « INS-TA KILL » + glas et timbale.
	var voice := _announcer([[VI, 0.2], [VA, 0.2], [VI, 0.45]], 80.0)
	var sting := _bell(2.0, 98.0)
	s.mix(sting, _timpani(41.0), 0.0, 1.2)
	_announce_save("announce_insta_kill", voice, sting)


func gen_announce_double_points() -> void:
	# « DOU-BLE POINTS » + deux tintements de pièces.
	var voice := _announcer([[VU, 0.22], [VE, 0.18], [VO, 0.22], [VI, 0.3]], 90.0)
	var sting := s.buf(1.2)
	for k in 2:
		s.mix(sting, _clank(2600.0 + k * 500.0, 0.3, 0.2), k * 0.18, 0.8)
	_announce_save("announce_double_points", voice, sting)


func gen_announce_nuke() -> void:
	# « KA-BOUM » + sirène grave.
	var voice := _announcer([[VA, 0.2], [VU, 0.6]], 76.0)
	var sting := s.env_adsr(s.sweep(1.6, 220.0, 440.0, "saw"), 0.2, 0.3, 0.6, 0.6)
	sting = s.lowpass(sting, 1500.0)
	_announce_save("announce_nuke", voice, s.gain(sting, 0.5))


func gen_announce_carpenter() -> void:
	# « CHAR-PEN-TIER » + trois coups de marteau.
	var voice := _announcer([[VA, 0.24], [VE, 0.2], [VE, 0.36]], 86.0)
	var sting := s.buf(1.0)
	for k in 3:
		s.mix(sting, _clank(700.0, 0.12, 1.0), k * 0.2, 0.9)
	_announce_save("announce_carpenter", voice, sting)


func gen_announce_fire_sale() -> void:
	# « LI-QUI-DA-TION » + trois notes de manège.
	var voice := _announcer([[VI, 0.16], [VI, 0.16], [VA, 0.18], [VO, 0.4]], 92.0)
	var sting := s.buf(1.2)
	for k in 3:
		var f: float = [523.25, 659.3, 784.0][k]
		s.mix(sting, s.env_exp(s.tone(0.5, f, "square"), 0.004, 0.15), k * 0.14, 0.2)
	_announce_save("announce_fire_sale", voice, sting)


func gen_announce_death_machine() -> void:
	# « FAU-CHEU-SE » + rafale grave de minigun au loin.
	var voice := _announcer([[VO, 0.22], [VE, 0.22], [VE, 0.42]], 82.0)
	var sting := s.buf(1.2)
	for k in 12:
		s.mix(sting, s.env_exp(s.lowpass(s.noise(0.06), 1400.0), 0.001, 0.025), k * 0.05, 0.5)
	s.mix(sting, _timpani(49.0), 0.0, 1.0)
	_announce_save("announce_death_machine", voice, sting)
# ---------------------------------------------------------------- fenêtres barricadées

## Planche arrachée : craquement du bois qui plie, clous qui grincent, rupture
## sèche puis éclats.
func gen_barricade_tear() -> void:
	for k in 3:
		s = Synth.new(2100 + k)
		var dur := 0.75
		var creak := s.bandpass(s.noise(0.32), 420.0 + k * 90.0, 6.0)
		for i in creak.size():
			creak[i] *= 0.5 + 0.5 * sin(TAU * i / (Synth.RATE * (0.018 + k * 0.004)))
		creak = s.env_adsr(creak, 0.08, 0.1, 0.8, 0.05)
		var b := s.buf(dur)
		b = s.mix(b, creak, 0.0, 0.7)
		b = s.mix(b, s.env_adsr(s.sweep(0.25, 2600.0 - k * 300.0, 1700.0, "tri"), 0.03, 0.05, 0.5, 0.1), 0.08, 0.12)
		var snap := s.env_exp(s.highpass(s.noise(0.08), 1200.0), 0.0005, 0.012)
		b = s.mix(b, snap, 0.3, 1.3)
		b = s.mix(b, s.env_exp(s.lowpass(s.noise(0.3), 700.0), 0.001, 0.05), 0.3, 1.0)
		b = s.mix(b, s.env_exp(s.sweep(0.2, 210.0, 90.0), 0.001, 0.05), 0.3, 0.7)
		for j in 5:
			var chip := s.env_exp(s.bandpass(s.noise(0.05), 1500.0 + s.rng.randf() * 2500.0, 3.0), 0.001, 0.01)
			b = s.mix(b, chip, 0.34 + s.rng.randf() * 0.3, 0.35)
		_save("barricade_tear_%d" % (k + 1), s.finish(s.reverb(b, 0.6, 0.2, 0.5), 0.9))


## Planche reposée : elle claque contre le cadre, deux coups de marteau.
func gen_barricade_slam() -> void:
	for k in 2:
		s = Synth.new(2200 + k)
		var b := s.env_exp(s.lowpass(s.noise(0.25), 900.0), 0.001, 0.035)
		b = s.mix(b, s.env_exp(s.sweep(0.2, 190.0, 110.0), 0.001, 0.05), 0.0, 1.0)
		for hit in 2:
			var t := 0.14 + hit * (0.12 + k * 0.03)
			b = s.mix(b, s.env_exp(s.lowpass(s.noise(0.12), 1600.0), 0.0005, 0.018), t, 0.8)
			b = s.mix(b, _clank(1900.0 + k * 250.0 + hit * 120.0, 0.12, 0.4), t, 0.5)
		_save("barricade_slam_%d" % (k + 1), s.finish(s.reverb(b, 0.55, 0.18, 0.4), 0.85))


# ---------------------------------------------------------------- chiens de l'enfer

func gen_dog_growl() -> void:
	# Grondement rauque de molosse : voix très basse, souffle, râle saturé.
	for k in 3:
		s = Synth.new(2100 + k)
		var dur := s.rng.randf_range(0.8, 1.3)
		var f0 := s.rng.randf_range(78.0, 100.0)
		var b := _growl(dur, f0, f0 * 1.15, [420.0 + k * 60.0, 950.0], 1.2)
		s.mix(b, s.env_adsr(s.lowpass(s.brown_noise(dur), 260.0), 0.1, 0.2, 0.8, 0.3), 0.0, 0.6)
		b = s.drive(b, 2.0)
		_save("dog_growl_%d" % (k + 1), s.finish(s.reverb(b, 0.5, 0.18, 0.4), 0.85))


func gen_dog_bark() -> void:
	# Aboiement agressif (bond) : attaque brutale, voix aiguë qui retombe.
	for k in 2:
		s = Synth.new(2200 + k)
		var b := _growl(0.32, 300.0 + k * 40.0, 170.0, [900.0, 1600.0], 0.8)
		s.mix(b, s.env_exp(s.bandpass(s.noise(0.08), 1500.0, 1.0), 0.001, 0.02), 0.0, 0.8)
		s.mix(b, _growl(0.25, 250.0, 150.0, [850.0, 1500.0], 0.9), 0.22, 0.7)
		b = s.gain(b, 1.3)
		_save("dog_bark_%d" % (k + 1), s.finish(s.reverb(b, 0.55, 0.2, 0.4), 0.95))


func gen_dog_whine() -> void:
	# Gémissement de mort : glapissement qui monte puis s'effondre.
	var b := _growl(0.35, 520.0, 780.0, [800.0, 1900.0], 0.3)
	s.mix(b, _growl(0.6, 700.0, 240.0, [700.0, 1500.0], 0.4), 0.3, 0.9)
	_save("dog_whine", s.finish(s.reverb(b, 0.6, 0.25, 0.6), 0.8))


func gen_dog_explode() -> void:
	# Embrasement : souffle grave, crépitements de flammes.
	var b := s.env_exp(s.lowpass_sweep(s.noise(1.2), 3000.0, 250.0), 0.004, 0.35)
	s.mix(b, s.env_exp(s.sweep(0.5, 110.0, 40.0), 0.002, 0.2), 0.0, 1.0)
	for k in 14:
		var crack := s.env_exp(s.bandpass(s.noise(0.04), s.rng.randf_range(1500.0, 5000.0), 3.0), 0.0005, 0.008)
		s.mix(b, crack, s.rng.randf_range(0.02, 0.9), s.rng.randf_range(0.2, 0.5))
	b = s.drive(b, 1.8)
	_save("dog_explode", s.finish(s.reverb(b, 0.7, 0.3, 0.8), 0.9))


func gen_dog_prespawn() -> void:
	# Boule de foudre : bourdonnement électrique qui enfle, grésillements.
	var dur := 1.6
	var hum := s.tone(dur, 60.0, "saw")
	s.mix(hum, s.tone(dur, 120.5, "square"), 0.0, 0.3)
	hum = s.lowpass(hum, 900.0)
	var b := s.env_adsr(hum, 1.2, 0.1, 0.9, 0.2)
	b = s.gain(b, 0.5)
	for k in 40:
		var t := s.rng.randf_range(0.0, dur - 0.05)
		var zap := s.env_exp(s.highpass(s.noise(0.03), 3000.0), 0.0005, 0.006)
		s.mix(b, zap, t, 0.2 + 0.6 * t / dur)
	s.mix(b, s.env_adsr(s.sweep(dur, 200.0, 900.0), 1.3, 0.05, 0.8, 0.1), 0.0, 0.25)
	_save("dog_prespawn", s.finish(s.reverb(b, 0.6, 0.2, 0.5), 0.75))


func gen_dog_bolt() -> void:
	# Coup de tonnerre : claquement sec puis grondement qui roule.
	var b := s.env_exp(s.highpass(s.noise(0.05), 1800.0), 0.0003, 0.012)
	b = s.gain(b, 1.5)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.3), 2500.0), 0.001, 0.06), 0.0, 1.0)
	var rumble := s.env_adsr(s.lowpass(s.brown_noise(2.2), 160.0), 0.05, 0.4, 0.6, 1.2)
	s.mix(b, s.gain(rumble, 1.6), 0.03, 1.0)
	s.mix(b, s.env_exp(s.sweep(0.6, 80.0, 35.0), 0.002, 0.3), 0.0, 1.0)
	b = s.drive(b, 2.2)
	_save("dog_bolt", s.finish(s.reverb(b, 0.9, 0.35, 1.5), 0.95, 0.2))


func gen_dog_spawn() -> void:
	# Le chien surgit : grésillement de braises et grognement.
	var b := s.env_exp(s.bandpass(s.noise(0.8), 2500.0, 0.8), 0.005, 0.25)
	b = s.gain(b, 0.5)
	s.mix(b, _growl(0.7, 95.0, 120.0, [450.0, 1000.0], 1.1), 0.1, 1.0)
	_save("dog_spawn", s.finish(s.reverb(b, 0.6, 0.2, 0.5), 0.85))


func gen_dog_round_start() -> void:
	# Annonce de manche de chiens : cuivres graves dissonants, tonnerre et voix
	# démoniaque (« VIENS... LEURS ÂMES »).
	var b := _brass(5.5, [41.2, 43.65, 61.7, 82.4], 0.6, 1100.0)
	var thunder := s.env_adsr(s.lowpass(s.brown_noise(3.0), 150.0), 0.02, 0.5, 0.5, 1.5)
	s.mix(b, s.gain(thunder, 1.4), 0.0, 1.0)
	s.mix(b, s.env_exp(s.highpass(s.noise(0.05), 1500.0), 0.0003, 0.015), 0.0, 1.2)
	s.mix(b, _timpani(41.0), 0.0, 1.3)
	s.mix(b, _timpani(41.0), 0.5, 1.0)
	s.mix(b, _timpani(38.9), 0.8, 1.0)
	var voice := _announcer([[VE, 0.3], [VI, 0.22], [VE, 0.26], [VO, 0.7]], 66.0)
	s.mix(b, s.gain(voice, 1.2), 1.1, 1.0)
	s.mix(b, _bell(4.0, 110.0), 1.0, 0.7)
	b = s.reverb(b, 0.95, 0.4, 2.5)
	_save("dog_round_start", s.finish(b, 0.95, 0.3))


func gen_dog_round_end() -> void:
	# Fin de la manche de chiens : glas et accord qui se résout vers le haut.
	var b := _brass(4.0, [55.0, 69.3, 82.4, 110.0], 0.3, 1600.0)
	s.mix(b, _bell(4.0, 164.8), 0.0, 1.0)
	s.mix(b, _bell(4.0, 220.0), 0.6, 0.8)
	s.mix(b, _timpani(55.0), 0.0, 1.0)
	b = s.reverb(b, 0.9, 0.35, 2.0)
	_save("dog_round_end", s.finish(b, 0.85, 0.3))


func gen_dog_round_music() -> void:
	# Boucle de 12 s (4 mesures à 80 bpm) : pulsation de timbales, bourdon
	# dissonant, cuivres en ostinato, cloche. Tempo et tonalité oppressants.
	var beat := 60.0 / 80.0
	var dur := beat * 16.0
	var b := s.buf(dur + 3.0)
	var drone := s.lowpass(s.tone(dur + 3.0, 41.2, "saw"), 220.0)
	s.mix(drone, s.lowpass(s.tone(dur + 3.0, 43.65, "saw"), 220.0), 0.0, 0.8)
	s.mix(b, drone, 0.0, 0.35)
	for i in 16:
		var t := i * beat
		s.mix(b, _timpani(41.0 if i % 4 != 3 else 46.2), t, 0.9 if i % 2 == 0 else 0.6)
		if i % 2 == 1:
			s.mix(b, s.env_exp(s.lowpass(s.noise(0.2), 900.0), 0.001, 0.05), t + beat * 0.5, 0.4)
	var riff := [0, 1, 0, 6, 0, 1, 3, 1]
	for i in riff.size():
		var f: float = 82.4 * pow(2.0, float(riff[i]) / 12.0)
		var stab := _brass(beat * 1.6, [f, f * 1.5], 0.04, 1300.0)
		s.mix(b, stab, i * beat * 2.0, 0.45)
	for k in 2:
		s.mix(b, _bell(3.0, 196.0 * (1.0 if k == 0 else 1.06)), k * beat * 8.0, 0.4)
	b = s.reverb(b, 0.9, 0.3, 1.2)
	_save("dog_round_music", _seamless(b, dur, 0.7), true)


# ---------------------------------------------------------------- grenades / singe

func gen_grenade_pin() -> void:
	# Goupille arrachée : tintement de l'anneau, puis la cuillère qui claque.
	var b := _clank(2600.0, 0.05, 0.4)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.06), 5200.0, 3.0), 0.001, 0.02), 0.03, 0.5)
	s.mix(b, _clank(1500.0, 0.06, 0.5), 0.16, 0.8)
	_save("grenade_pin", s.finish(s.reverb(b, 0.3, 0.12, 0.2), 0.7))


func gen_grenade_throw() -> void:
	# Souffle du bras (whoosh court).
	var b := s.env_adsr(s.bandpass(s.noise(0.3), 900.0, 0.8), 0.06, 0.1, 0.5, 0.12)
	s.mix(b, s.env_adsr(s.lowpass_sweep(s.noise(0.3), 2500.0, 600.0), 0.04, 0.08, 0.4, 0.1), 0.0, 0.6)
	_save("grenade_throw", s.finish(b, 0.5))


func gen_grenade_bounce() -> void:
	# Petit corps métallique lourd qui heurte le béton.
	var b := s.env_exp(s.lowpass(s.noise(0.1), 1800.0), 0.0005, 0.02)
	s.mix(b, _clank(720.0, 0.06, 0.3), 0.0, 1.0)
	s.mix(b, s.env_exp(s.tone(0.1, 180.0), 0.0005, 0.03), 0.0, 0.6)
	_save("grenade_bounce", s.finish(s.reverb(b, 0.35, 0.12, 0.25), 0.65))


func gen_monkey_bounce() -> void:
	# Jouet de fer-blanc qui cogne le sol (les cymbales tintent).
	var b := s.env_exp(s.lowpass(s.noise(0.1), 1500.0), 0.0005, 0.02)
	s.mix(b, _cymbal(0.25, 0.4), 0.0, 0.5)
	_save("monkey_bounce", s.finish(s.reverb(b, 0.3, 0.1, 0.2), 0.6))


func gen_frag_explode() -> void:
	# Grenade : détonation sèche et violente, souffle, éclats qui retombent.
	var b := s.env_exp(s.highpass(s.noise(0.02), 1800.0), 0.0003, 0.006)
	s.mix(b, s.env_exp(s.lowpass_sweep(s.noise(1.2), 4200.0, 180.0), 0.001, 0.22), 0.0, 1.1)
	s.mix(b, s.env_exp(s.sweep(0.9, 110.0, 32.0), 0.001, 0.3), 0.0, 1.5)
	s.mix(b, s.env_exp(s.lowpass(s.noise(1.8), 300.0), 0.03, 0.55), 0.03, 0.7)
	for k in 7:
		s.mix(b, s.env_exp(s.bandpass(s.noise(0.05), 2500.0 + k * 350.0, 3.0), 0.0005, 0.02), 0.25 + k * 0.11 + s.rng.randf() * 0.05, 0.12)
	b = s.drive(b, 3.5)
	_save("frag_explode", s.finish(s.reverb(b, 0.95, 0.32, 1.4), 0.98))


func gen_monkey_wind() -> void:
	# Remontage du ressort du singe (cliquetis de la clé).
	var b := s.buf(0.5)
	for k in 6:
		s.mix(b, _clank(3000.0 + (k % 2) * 500.0, 0.02, 0.3), k * 0.07, 0.6)
	_save("monkey_wind", s.finish(b, 0.5))


## Cymbale de laiton : bruit aigu et partiels métalliques inharmoniques.
func _cymbal(seconds: float, decay: float) -> PackedFloat32Array:
	var b := s.env_exp(s.highpass(s.noise(seconds), 4500.0), 0.0005, decay)
	for pr in [1.0, 1.47, 2.09, 2.56, 3.71]:
		s.mix(b, s.env_exp(s.tone(seconds, 1180.0 * pr, "square"), 0.0005, decay * 0.5), 0.0, 0.05)
	return s.bandpass(b, 6500.0, 0.5)


func gen_monkey_music() -> void:
	# SINGE-TAMBOUR : air de fête foraine à 135 bpm (orgue de barbarie
	# désaccordé, basse « oum-pa ») et un coup de cymbales à chaque temps,
	# pendant 8 s ; la dernière mesure ralentit comme un ressort qui se détend.
	var beat := 60.0 / 135.0
	var b := s.buf(8.0 + 0.6)
	var melody := [7, 9, 11, 12, 11, 9, 7, 4, 5, 7, 9, 7, 5, 4, 2, 0,
		7, 9, 11, 12, 14, 12, 11, 9, 7, 11, 14, 12, 11, 9, 7, 0]
	var n := int(8.0 / beat)
	var t := 0.0
	for i in n:
		var slow := 1.0 + maxf(0.0, float(i - (n - 4))) * 0.12
		# Cymbales.
		s.mix(b, _cymbal(0.4, 0.14), t, 0.55)
		# Basse oum-pa.
		@warning_ignore("integer_division")
		var bass: float = 98.0 if (i / 2) % 2 == 0 else 73.4
		s.mix(b, s.env_exp(s.tone(beat, bass if i % 2 == 0 else bass * 1.5, "tri"), 0.004, 0.12), t, 0.35)
		# Mélodie (croches).
		for h in 2:
			var note: int = melody[(i * 2 + h) % melody.size()]
			var f: float = 523.25 * pow(2.0, note / 12.0) * (1.0 - 0.02 * float(i) / n)
			var v := s.env_exp(s.tone(beat * 0.6, f, "square"), 0.003, 0.09)
			s.mix(v, s.env_exp(s.tone(beat * 0.6, f * 1.006, "saw"), 0.003, 0.07), 0.0, 0.5)
			s.mix(b, s.lowpass(v, 3200.0), t + h * beat * 0.5 * slow, 0.16)
		t += beat * slow
	_save("monkey_music", s.finish(s.reverb(b, 0.6, 0.22, 0.6), 0.8))
