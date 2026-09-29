extends AutotestScenario
## @rendu : captures de l'écran d'options EN JEU (BUNKER K-7, solo) : menu
## pause, onglets COMMANDES (touches) et GRAPHISMES, une touche en attente de
## saisie, puis la même page en anglais. La capture de l'onglet COMMANDES est
## aussi enregistrée en JPEG 1280x720 (tests/_out/shots/options_look.jpg),
## prête pour les notes de version (changelogs/next/01_options.jpg).

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 60
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	await until(func(): return game.hud.pause_menu != null, 2.0, "menu pause construit")
	var pm: PauseMenu = game.hud.pause_menu
	await seconds(1.0)
	pm.open()
	await seconds(0.3)
	await at.screenshot("pause")
	pm.show_screen("options")
	var opt = pm.current
	await seconds(0.4)
	opt.switch_tab(1)
	await seconds(0.3)
	opt.bind_rows.move_forward.grab_focus()
	await seconds(0.4)
	await at.screenshot("controls")
	_check_drawn("onglet COMMANDES")
	_save_jpg("options_look")
	opt.bind_rows.reload.grab_focus()
	opt._on_rebind_requested(opt.bind_rows.reload, 0)
	await seconds(0.3)
	await at.screenshot("capture")
	opt._cancel_capture()
	opt.switch_tab(1)
	await seconds(0.3)
	opt.rows.brightness.grab_focus()
	await seconds(0.4)
	await at.screenshot("graphics")
	_check_drawn("onglet GRAPHISMES")
	# Limite d'images appliquée au moteur (pas de --max-fps ici).
	if Settings._cmdline_max_fps == 0:
		opt.rows.max_fps.nudge(1)
		await frames(2)
		at.check(Engine.max_fps == 30, "limite de 30 images/s appliquée (%d)" % Engine.max_fps)
		opt.rows.max_fps.nudge(-1)
		await frames(2)
		at.check(Engine.max_fps == 0, "limite retirée (%d)" % Engine.max_fps)
	# Anglais : tout l'écran est réécrit.
	opt.switch_tab(-2)
	await frames(2)
	opt.rows.language.grab_focus()
	await frames(2)
	opt.rows.language.nudge(1)
	await seconds(0.3)
	at.check(Settings.language == "en" and opt.tab_buttons.controls.label == "CONTROLS", "anglais : onglet « %s »" % opt.tab_buttons.controls.label)
	opt.switch_tab(1)
	await seconds(0.4)
	await at.screenshot("controls_en")
	Settings.language = "fr"
	Settings.save_settings()
	pm.close()


## L'écran n'est pas vide : du texte clair sur le voile sombre.
func _check_drawn(what: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := at.get_viewport().get_texture().get_image()
	var bright := 0
	for y in range(80, img.get_height() - 80, 6):
		for x in range(100, 900, 6):
			if img.get_pixel(x, y).get_luminance() > 0.6:
				bright += 1
	at.check(bright > 150, "%s dessiné (%d points clairs)" % [what, bright])


func _save_jpg(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var img := at.get_viewport().get_texture().get_image()
	if img.get_size() != Vector2i(1280, 720):
		img.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	var dir := ProjectSettings.globalize_path("res://tests/_out/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.jpg" % [dir, shot_name]
	at.check(img.save_jpg(path, 0.85) == OK, "capture JPEG : " + path)
