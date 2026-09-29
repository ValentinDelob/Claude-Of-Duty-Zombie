extends TestCase
## Mixage des voix des personnages (docs/ASSETS.md « Mixage ») : bus « Voice »,
## voix simplement plus fortes que le reste, AUCUNE baisse des autres sons
## pendant une réplique (choix de l'utilisateur), réglage « VOIX DES
## PERSONNAGES » enregistré, rechargé et appliqué au bus.


## Lecteur qui « parle » indéfiniment (générateur : reste en lecture).
func _speaker(p: Node) -> Node:
	p.set("stream", AudioStreamGenerator.new())
	host.add_child(p)
	Audio.track_voice(p)
	p.call("play")
	return p


func _bus_state(bus: String) -> Array:
	var idx := AudioServer.get_bus_index(bus)
	return [AudioServer.get_bus_volume_db(idx), AudioServer.get_bus_effect_count(idx)]


func test_voice_bus_in_layout() -> void:
	var layout := FileAccess.get_file_as_string("res://default_bus_layout.tres")
	assert_true(layout.contains("name = &\"Voice\""), "bus Voice dans default_bus_layout.tres")
	assert_true(layout.contains("AudioEffectHardLimiter"), "limiteur du Master conservé")
	assert_false(layout.contains("Duck"), "aucun effet de baisse dans les bus")
	var idx := AudioServer.get_bus_index(Audio.VOICE_BUS)
	assert_true(idx > 0, "bus Voice chargé")
	assert_eq(String(AudioServer.get_bus_send(idx)), "Master", "Voice -> Master")
	for bus in ["SFX", "Music"]:
		assert_eq(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(bus)), 0, "aucun effet sur %s" % bus)


func test_vox_players_on_voice_bus() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/game/vox/vox_system.gd")
	assert_eq(src.count("Audio.track_voice("), 2, "voix 2D et 3D déclarées")
	assert_false(src.contains("bus = \"SFX\""), "plus de voix sur le bus SFX")
	var p := AudioStreamPlayer3D.new()
	Audio.track_voice(p)
	assert_eq(String(p.bus), Audio.VOICE_BUS, "lecteur basculé sur Voice")
	p.free()


func test_voices_louder_than_the_rest() -> void:
	assert_true(VoxSystem.VOLUME_2D >= 6.0, "sa propre voix au-dessus du reste (+%.0f dB)" % VoxSystem.VOLUME_2D)
	assert_true(VoxSystem.VOLUME_3D >= 8.0, "voix des coéquipiers au-dessus du reste (+%.0f dB)" % VoxSystem.VOLUME_3D)


func test_nothing_else_lowered_while_speaking() -> void:
	var before := {"SFX": _bus_state("SFX"), "Music": _bus_state("Music"), "UI": _bus_state("UI")}
	var p: AudioStreamPlayer = _speaker(AudioStreamPlayer.new())
	await wait_seconds(0.3)
	assert_true(p.playing, "réplique en cours")
	for bus in before:
		assert_eq(_bus_state(bus), before[bus], "%s inchangé pendant une réplique" % bus)
	p.stop()
	p.queue_free()


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
