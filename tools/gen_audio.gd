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


## Batte de baseball fendant l'air : souffle plus grave et plus long que le
## couteau (objet lourd), qui monte puis retombe.
func gen_bat_swing() -> void:
	var b := s.env_adsr(s.bandpass(s.noise(0.38), 900.0, 0.9), 0.12, 0.06, 0.55, 0.16)
	b = s.lowpass_sweep(b, 700.0, 2600.0)
	s.mix(b, s.env_adsr(s.bandpass(s.noise(0.3), 2200.0, 1.5), 0.1, 0.05, 0.3, 0.12), 0.04, 0.35)
	_save("bat_swing", s.finish(b, 0.65))


## Coup de batte sur un zombie : « toc » de bois creux (deux résonances du
## fût), coup sourd de la chair, léger craquement.
func gen_bat_hit() -> void:
	var b := s.env_exp(s.bandpass(s.noise(0.25), 760.0, 6.0), 0.001, 0.06)
	s.mix(b, s.env_exp(s.bandpass(s.noise(0.25), 1480.0, 7.0), 0.001, 0.04), 0.0, 0.6)
	s.mix(b, s.env_exp(s.sweep(0.2, 150.0, 60.0), 0.001, 0.07), 0.0, 1.1)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.2), 900.0), 0.001, 0.05), 0.005, 0.7)
	s.mix(b, s.env_exp(s.highpass(s.noise(0.05), 3500.0), 0.0005, 0.01), 0.012, 0.25)
	_save("bat_hit", s.finish(s.reverb(b, 0.35, 0.12, 0.3), 0.9))


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


# Identité sonore propre au jeu (laboratoire en alerte, GAME_CONCEPT §6) :
# sas pneumatiques, bips de moniteurs, sirènes de confinement, nappes de
# synthé. Aucun cuivre, glas, chœur ni voix d'annonceur.

## Bip de moniteur médical : carré doux filtré, attaque nette.
func _blip(seconds: float, f: float) -> PackedFloat32Array:
	var b := s.env_adsr(s.tone(seconds, f, "square"), 0.004, 0.03, 0.6, seconds * 0.4)
	s.mix(b, s.env_exp(s.tone(seconds, f * 2.0), 0.002, seconds * 0.5), 0.0, 0.25)
	return s.lowpass(b, 3200.0)


## Souffle pneumatique (sas, vérin) : bruit filtré qui s'ouvre puis retombe.
func _hiss(seconds: float, center: float) -> PackedFloat32Array:
	var b := s.bandpass(s.noise(seconds), center, 0.8)
	return s.env_adsr(b, 0.02, seconds * 0.2, 0.55, seconds * 0.6)


## Nappe de synthé (scies désaccordées, filtre qui s'ouvre) : `freqs` en Hz.
func _pad(seconds: float, freqs: Array, attack: float, cutoff: float) -> PackedFloat32Array:
	var b := s.buf(seconds)
	for f in freqs:
		for det in [-0.006, 0.0, 0.007]:
			s.mix(b, s.tone(seconds, f * (1.0 + det), "saw"), 0.0, 0.14)
	b = s.lowpass_sweep(b, cutoff * 0.25, cutoff)
	return s.env_adsr(b, attack, 0.3, 0.75, seconds * 0.4)


## Sirène de confinement : `cycles` montées / descentes entre f0 et f1.
func _siren(cycle: float, f0: float, f1: float, cycles: int) -> PackedFloat32Array:
	var b := s.buf(0.05)
	for k in cycles:
		var up := s.sweep(cycle * 0.5, f0, f1, "square")
		var down := s.sweep(cycle * 0.5, f1, f0, "square")
		s.mix(b, up, k * cycle, 1.0)
		s.mix(b, down, k * cycle + cycle * 0.5, 1.0)
	b = s.lowpass(b, 2600.0)
	return s.env_adsr(b, 0.05, 0.2, 0.85, 0.4)


## Compteur Geiger : clics secs de plus en plus serrés.
func _geiger(seconds: float, rate0: float, rate1: float) -> PackedFloat32Array:
	var b := s.buf(seconds)
	var t := 0.0
	while t < seconds - 0.02:
		var k := t / seconds
		s.mix(b, s.env_exp(s.highpass(s.noise(0.01), 2500.0), 0.0003, 0.002), t, s.rng.randf_range(0.5, 1.0))
		t += s.rng.randf_range(0.3, 1.7) / lerpf(rate0, rate1, k)
	return b


func gen_round_start() -> void:
	# Début de manche : un sas s'ouvre (choc sourd, vérin), trois bips de
	# moniteur qui montent, puis une nappe tendue qui s'ouvre.
	var b := s.env_exp(s.sweep(0.6, 95.0, 40.0), 0.002, 0.22)
	s.mix(b, _clank(150.0, 0.35, 0.8), 0.0, 0.7)
	s.mix(b, _hiss(1.4, 2600.0), 0.06, 0.55)
	for i in 3:
		s.mix(b, _blip(0.13, [880.0, 987.8, 1318.5][i]), 0.32 + i * 0.22, 0.42)
	s.mix(b, _pad(2.8, [110.0, 164.8, 246.9], 0.9, 2200.0), 0.9, 0.9)
	s.mix(b, s.env_adsr(s.tone(3.2, 55.0), 0.4, 0.5, 0.6, 1.2), 0.8, 0.5)
	b = s.reverb(b, 0.75, 0.28, 1.4)
	_save("round_start", s.finish(b, 0.9, 0.3))


func gen_round_end() -> void:
	# Fin de manche : carillon d'annonce à trois tons qui descend
	# (« décontamination terminée »), air relâché, ronronnement qui s'éteint.
	var b := s.buf(3.5)
	var notes := [783.99, 659.26, 523.25]
	for i in notes.size():
		var n := s.env_exp(s.tone(1.6, notes[i]), 0.004, 0.5)
		s.mix(n, s.env_exp(s.tone(1.6, notes[i] * 2.0), 0.003, 0.25), 0.0, 0.3)
		s.mix(n, s.env_exp(s.tone(1.6, notes[i] * 3.01), 0.002, 0.12), 0.0, 0.12)
		s.mix(b, n, i * 0.36, 0.55)
	s.mix(b, s.env_adsr(s.lowpass_sweep(s.noise(2.2), 5000.0, 700.0), 0.05, 0.3, 0.5, 1.2), 0.9, 0.3)
	s.mix(b, s.env_adsr(s.lowpass(s.tone(3.0, 110.0, "tri"), 400.0), 0.2, 0.4, 0.5, 1.6), 0.0, 0.35)
	b = s.reverb(b, 0.8, 0.3, 1.6)
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


# ---------------------------------------------------------------- caisse au hasard

func gen_box_open() -> void:
	# Grincement de charnière + choc du couvercle.
	var creak := s.env_adsr(s.bandpass(s.sweep(0.7, 420.0, 260.0, "saw"), 900.0, 5.0), 0.05, 0.2, 0.7, 0.2)
	var b := s.gain(creak, 0.6)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.3), 700.0), 0.002, 0.05), 0.65, 0.9)
	_save("box_open", s.finish(s.reverb(b, 0.6, 0.2, 0.5), 0.75))


func gen_box_music() -> void:
	# Tirage de la caisse au hasard (~4 s) : un barillet mécanique cliquette de
	# plus en plus lentement, chaque cran avec un petit bip de compteur, puis
	# le verrou tombe et deux bips confirment (aucune boîte à musique).
	var b := s.buf(4.8)
	var t := 0.0
	var i := 0
	while t < 3.75:
		var k := t / 3.75
		var click := s.env_exp(s.bandpass(s.noise(0.03), 2400.0, 3.0), 0.0005, 0.008)
		s.mix(click, s.env_exp(s.tone(0.03, 3100.0), 0.0005, 0.006), 0.0, 0.3)
		s.mix(b, click, t, 0.9)
		s.mix(b, _blip(0.05, [1046.5, 1174.7, 1318.5, 1174.7][i % 4]), t + 0.005, 0.14)
		t += lerpf(0.055, 0.34, k * k)
		i += 1
	s.mix(b, _clank(210.0, 0.3, 0.9), 3.95, 0.9)
	s.mix(b, s.env_exp(s.lowpass(s.noise(0.2), 600.0), 0.001, 0.05), 3.95, 0.7)
	s.mix(b, _blip(0.12, 1046.5), 4.1, 0.35)
	s.mix(b, _blip(0.22, 1568.0), 4.24, 0.35)
	_save("box_music", s.finish(s.reverb(b, 0.6, 0.22, 0.8), 0.7))


func gen_zombie_fling() -> void:
	# Zombie projeté : cri étranglé qui s'envole + froissement d'air.
	var b := _growl(0.8, 170.0, 260.0, [760.0, 1400.0], 0.9)
	s.mix(b, s.env_adsr(s.bandpass(s.noise(0.8), 900.0, 0.8), 0.02, 0.2, 0.5, 0.4), 0.0, 0.6)
	_save("zombie_fling", s.finish(s.reverb(b, 0.7, 0.25, 0.6), 0.85))


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


# ---------------------------------------------------------------- boucles

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


# ---------------------------------------------------------------- chiens errants contaminés (meute)

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


func gen_special_wave_start() -> void:
	# Annonce d'une vague spéciale (meute, puis les autres mini-boss) : alerte
	# de confinement du laboratoire. Sirène à deux montées, pulsation grave,
	# compteur Geiger qui s'emballe, puis une porte blindée qui claque.
	var b := s.buf(5.0)
	s.mix(b, s.drive(_siren(1.2, 430.0, 780.0, 2), 1.6), 0.0, 0.5)
	var throb := s.tone(3.2, 52.0)
	for i in throb.size():
		throb[i] *= 0.55 + 0.45 * sin(TAU * 4.0 * i / Synth.RATE)
	s.mix(b, s.env_adsr(throb, 0.3, 0.4, 0.8, 0.8), 0.0, 0.8)
	s.mix(b, _geiger(2.6, 6.0, 40.0), 0.1, 0.35)
	s.mix(b, s.env_exp(s.sweep(1.0, 120.0, 34.0), 0.002, 0.3), 2.55, 1.2)
	s.mix(b, _clank(120.0, 0.6, 1.0), 2.55, 0.9)
	s.mix(b, _hiss(1.6, 1800.0), 2.6, 0.35)
	b = s.reverb(b, 0.85, 0.32, 1.8)
	_save("special_wave_start", s.finish(b, 0.95, 0.3))


func gen_special_wave_end() -> void:
	# Fin de la vague spéciale : la sirène retombe et s'éteint, puis trois
	# bips montants (« zone sécurisée ») et l'air des sas qui se relâche.
	var b := s.buf(4.0)
	var wind := s.lowpass(s.sweep(1.8, 720.0, 160.0, "square"), 2000.0)
	s.mix(b, s.env_adsr(wind, 0.02, 0.4, 0.7, 1.0), 0.0, 0.45)
	for i in 3:
		s.mix(b, _blip(0.16, [523.25, 659.26, 783.99][i]), 1.6 + i * 0.2, 0.45)
	s.mix(b, _hiss(1.8, 2200.0), 1.9, 0.3)
	s.mix(b, _pad(2.0, [130.8, 196.0, 261.6], 0.3, 1800.0), 1.8, 0.45)
	b = s.reverb(b, 0.8, 0.3, 1.5)
	_save("special_wave_end", s.finish(b, 0.85, 0.3))


func gen_special_wave_music() -> void:
	# Boucle de vague spéciale, 16 temps à 112 bpm (~8,6 s) : basse de synthé
	# en croches, battement de cœur électronique sur les temps forts, tics
	# métalliques, bip d'alarme toutes les deux mesures, bourdon grave.
	var beat := 60.0 / 112.0
	var dur := beat * 16.0
	var b := s.buf(dur + 2.0)
	s.mix(b, s.lowpass(s.tone(dur + 2.0, 55.0, "tri"), 200.0), 0.0, 0.25)
	var line := [0, 0, 12, 0, 0, 0, 10, 0, 0, 0, 12, 0, 3, 0, 1, 0]
	for i in 32:
		var t := i * beat * 0.5
		var f: float = 55.0 * pow(2.0, float(line[i % 16]) / 12.0)
		var note := s.env_exp(s.lowpass(s.tone(beat * 0.5, f, "saw"), 520.0), 0.003, beat * 0.22)
		s.mix(b, note, t, 0.55)
		if i % 2 == 1:
			s.mix(b, s.env_exp(s.highpass(s.noise(0.04), 6000.0), 0.0005, 0.012), t, 0.18)
	for i in 16:
		if i % 2 == 0:
			var t := i * beat
			s.mix(b, s.env_exp(s.sweep(0.25, 85.0, 42.0), 0.002, 0.09), t, 0.9)
			s.mix(b, s.env_exp(s.sweep(0.2, 75.0, 40.0), 0.002, 0.07), t + 0.17, 0.55)
	for k in 2:
		var t := k * beat * 8.0 + beat * 6.0
		s.mix(b, _blip(0.12, 1479.98), t, 0.16)
		s.mix(b, _blip(0.12, 1046.5), t + 0.16, 0.16)
	b = s.reverb(b, 0.7, 0.22, 0.9)
	_save("special_wave_music", _seamless(b, dur, 0.7), true)


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
