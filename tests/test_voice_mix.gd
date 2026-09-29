extends TestCase
## Mixage des voix des personnages (docs/ASSETS.md « Mixage ») : bus « Voice »,
## baisse des effets et de la musique pendant une réplique (comme BO1), réglage
## « VOIX DES PERSONNAGES » enregistré, rechargé et appliqué au bus.


## Lecteur qui « parle » indéfiniment (générateur : reste en lecture).
func _speaker(p: Node) -> Node:
	p.set("stream", AudioStreamGenerator.new())
	host.add_child(p)
	Audio.track_voice(p)
	p.call("play")
	return p


func _duck_fx(bus: String) -> AudioEffectAmplify:
	var idx := AudioServer.get_bus_index(bus)
	for e in AudioServer.get_bus_effect_count(idx):
		var eff := AudioServer.get_bus_effect(idx, e)
		if eff is AudioEffectAmplify and eff.resource_name == "Duck":
			return eff
	return null


func test_voice_bus_in_layout() -> void:
	var layout := FileAccess.get_file_as_string("res://default_bus_layout.tres")
	assert_true(layout.contains("name = &\"Voice\""), "bus Voice dans default_bus_layout.tres")
	assert_true(layout.contains("AudioEffectHardLimiter"), "limiteur du Master conservé")
	var idx := AudioServer.get_bus_index(Audio.VOICE_BUS)
	assert_true(idx > 0, "bus Voice chargé")
	assert_eq(String(AudioServer.get_bus_send(idx)), "Master", "Voice -> Master")
	for bus in ["SFX", "Music"]:
		assert_true(_duck_fx(bus) != null, "effet Duck sur %s" % bus)
	assert_true(_duck_fx("UI") == null, "interface jamais baissée")
	# Profondeurs raisonnables (zombies et effets plus baissés que la musique).
	assert_true(Audio.DUCK_DB.SFX <= -6.0 and Audio.DUCK_DB.SFX >= -9.0, "SFX -6 à -9 dB")
	assert_true(Audio.DUCK_DB.Music < 0.0 and Audio.DUCK_DB.Music > Audio.DUCK_DB.SFX, "musique moins baissée")


func test_vox_players_on_voice_bus() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/game/vox/vox_system.gd")
	assert_eq(src.count("Audio.track_voice("), 2, "voix 2D et 3D déclarées")
	assert_false(src.contains("bus = \"SFX\""), "plus de voix sur le bus SFX")
	var p := AudioStreamPlayer3D.new()
	Audio.track_voice(p)
	assert_eq(String(p.bus), Audio.VOICE_BUS, "lecteur basculé sur Voice")
	p.free()


func test_ducking_follows_voice() -> void:
	await wait_seconds(0.8)
	assert_near(Audio.duck, 0.0, 0.01, "rien ne parle : pas de baisse")
	var p: AudioStreamPlayer = _speaker(AudioStreamPlayer.new())
	await wait_seconds(0.15)
	assert_true(p.playing, "réplique en cours")
	assert_true(Audio.duck > 0.9, "baisse rapide (attaque) : %.2f" % Audio.duck)
	assert_near(_duck_fx("SFX").volume_db, Audio.DUCK_DB.SFX * Audio.duck, 0.01, "SFX baissé")
	assert_near(_duck_fx("Music").volume_db, Audio.DUCK_DB.Music * Audio.duck, 0.01, "musique baissée")
	p.stop()
	await wait_seconds(0.1)
	assert_true(Audio.duck > 0.3, "retour en douceur, pas d'un coup : %.2f" % Audio.duck)
	await wait_seconds(1.5)
	assert_near(Audio.duck, 0.0, 0.01, "retour complet après la réplique")
	assert_near(_duck_fx("SFX").volume_db, 0.0, 0.01, "SFX rétabli")
	# Voix coupées dans les options : aucune baisse.
	var before := Settings.voice_volume
	Settings.voice_volume = 0.0
	Settings.apply()
	p.play()
	await wait_seconds(0.2)
	assert_near(Audio.duck, 0.0, 0.01, "voix à 0 % : rien ne baisse")
	Settings.voice_volume = before
	Settings.apply()
	p.queue_free()
	await wait_seconds(1.5)


func test_ducking_weighted_by_distance() -> void:
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	var v: AudioStreamPlayer3D = _speaker(AudioStreamPlayer3D.new())
	var cases := [[5.0, 1.0], [20.0, 0.5], [40.0, 0.0]]
	for c in cases:
		v.global_position = Vector3(c[0], 0, 0)
		assert_near(Audio.duck_target(), c[1], 0.01, "coéquipier à %d m" % int(c[0]))
	v.queue_free()
	cam.queue_free()
	await wait_seconds(1.5)


func test_voice_volume_saved_and_applied() -> void:
	var saved_path := Settings.path
	var before := Settings.voice_volume
	Settings.path = "user://settings_unit_voice.cfg"
	Settings.voice_volume = 0.35
	Settings.save_settings()
	var cfg := ConfigFile.new()
	assert_true(cfg.load(Settings.path) == OK and is_equal_approx(float(cfg.get_value("audio", "voice", -1.0)), 0.35), "enregistré dans [audio] voice")
	Settings.voice_volume = 1.0
	Settings.load_settings()
	assert_near(Settings.voice_volume, 0.35, 0.001, "rechargé")
	Settings.apply()
	assert_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Voice")), linear_to_db(0.35), 0.01, "appliqué au bus Voice")
	DirAccess.remove_absolute(Settings.path)
	Settings.path = saved_path
	Settings.voice_volume = before
	Settings.apply()
	var opts := FileAccess.get_file_as_string("res://scripts/ui/screens/options_screen.gd")
	assert_true(opts.contains("VOIX DES PERSONNAGES") and opts.contains("CHARACTER VOICES"), "option en français et en anglais")
