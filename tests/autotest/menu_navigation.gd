extends AutotestScenario
## Menu principal parcouru au clavier (événements d'entrée réels) :
## principal -> OPTIONS (une option modifiée, vérifiée dans le fichier de
## réglages, puis restaurée) -> retour -> CRÉDITS (défilement) -> retour ->
## MULTIJOUEUR -> retour -> apparition de la silhouette du fond -> SOLO
## (fondu au noir cinématique avant le chargement). Captures de chaque écran.

const EXPECTED := ["SOLO", "MULTIJOUEUR", "OPTIONS", "DOSSIER DE COMBAT", "CRÉDITS", "QUITTER"]

var menu: MainMenu


func run() -> void:
	timeout_sec = 100
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await seconds(2.6)  # ouverture en fondu
	at.check(menu.current_name == "main", "écran principal affiché")
	# Ambiance : fond 3D, musique, logo.
	at.check(menu.backdrop != null and menu.backdrop.camera.current, "fond 3D du bunker affiché (caméra active)")
	at.check(Audio._music_name == MainMenu.MUSIC, "musique du menu : %s" % Audio._music_name)
	at.check(menu.current.logo != null and menu.current.logo.is_visible_in_tree(), "logo affiché")
	at.begin_perf()
	await seconds(1.5)
	at.check_perf(at.end_perf("menu 3D"), 150.0, "menu 3D")
	var labels := []
	for b in _buttons():
		labels.append(b.label)
	at.check(labels == EXPECTED, "entrées du menu : %s" % ", ".join(labels))
	at.check(_focused_label() == "SOLO", "focus initial sur SOLO (%s)" % _focused_label())
	await at.screenshot("main")

	# Navigation clavier jusqu'à OPTIONS.
	await press("ui_down")
	at.check(_focused_label() == "MULTIJOUEUR", "↓ : MULTIJOUEUR (%s)" % _focused_label())
	await press("ui_down")
	at.check(_focused_label() == "OPTIONS", "↓ : OPTIONS (%s)" % _focused_label())
	await seconds(0.3)
	await at.screenshot("main_focus_options")
	await press("ui_accept")
	at.check(menu.current_name == "options", "Entrée : écran OPTIONS")
	await seconds(0.9)
	await at.screenshot("options")
	await _check_option_saved()

	await press("ui_cancel")
	at.check(menu.current_name == "main", "Échap : retour au principal depuis OPTIONS")
	await seconds(0.8)

	# CRÉDITS (5e entrée).
	for i in 4:
		await press("ui_down")
	at.check(_focused_label() == "CRÉDITS", "focus sur CRÉDITS (%s)" % _focused_label())
	await press("ui_accept")
	at.check(menu.current_name == "credits", "écran CRÉDITS")
	var y0: float = menu.current.scroll_y()
	await seconds(2.5)
	var y1: float = menu.current.scroll_y()
	at.check(y1 < y0 - 30.0, "le générique défile (%.0f -> %.0f)" % [y0, y1])
	await at.screenshot("credits")
	await press("ui_cancel")
	at.check(menu.current_name == "main", "retour au principal depuis CRÉDITS")
	await seconds(0.8)

	# MULTIJOUEUR.
	await press("ui_down")
	await press("ui_accept")
	at.check(menu.current_name == "multiplayer", "écran MULTIJOUEUR")
	await seconds(0.8)
	await at.screenshot("multiplayer")
	await press("ui_cancel")
	at.check(menu.current_name == "main", "retour au principal depuis MULTIJOUEUR")
	await seconds(0.25)
	await at.screenshot("transition")
	await seconds(0.8)
	at.check(_focused_label() == "SOLO", "focus rendu à SOLO")

	# La silhouette du fond apparaît dans l'embrasure, puis disparaît.
	menu.backdrop.force_figure(true)
	await seconds(0.5)
	at.check(menu.backdrop.figure_visible(), "silhouette visible au fond")
	await at.screenshot("presence")
	menu.backdrop.force_figure(false)
	at.check(not menu.backdrop.figure_visible(), "silhouette disparue")

	# SOLO : fondu au noir cinématique AVANT le chargement.
	await press("ui_accept")
	await seconds(0.5)
	at.check(tree().current_scene == menu, "SOLO : toujours dans le menu pendant le fondu")
	at.check(menu._fade_amount > 0.15, "fondu au noir en cours (%.2f)" % menu._fade_amount)
	await at.screenshot("launch_fade")
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 30.0, "partie solo lancée après le fondu")
	if ok:
		at.check(GameState.state == GameState.State.PLAYING, "partie en cours")
		at.check(get_window_scale_mode() == Window.CONTENT_SCALE_MODE_DISABLED, "mise à l'échelle du menu restaurée en jeu")


func get_window_scale_mode() -> int:
	return at.get_window().content_scale_mode


## Modifie le volume de la musique avec ► et vérifie qu'il est appliqué et
## enregistré dans user://settings.cfg, puis rétablit la valeur d'origine.
func _check_option_saved() -> void:
	var screen := menu.current
	var row: MenuOptionRow = screen.rows.music_volume
	var before := Settings.music_volume
	row.grab_focus()
	await frames(2)
	var dir := "ui_left" if before >= 0.99 else "ui_right"
	await press(dir)
	var expected := snappedf(before + (-0.05 if dir == "ui_left" else 0.05), 0.05)
	at.check(is_equal_approx(Settings.music_volume, expected), "musique %.2f -> %.2f (attendu %.2f)" % [before, Settings.music_volume, expected])
	var cfg := ConfigFile.new()
	var ok := cfg.load(Settings.path) == OK
	var saved: float = cfg.get_value("audio", "music", -1.0) if ok else -1.0
	at.check(ok and is_equal_approx(saved, expected), "réglage enregistré dans %s (%.2f)" % [Settings.path, saved])
	var bus := AudioServer.get_bus_index("Music")
	at.check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(expected)), "volume du bus Musique appliqué")
	at.check(row.value_text() == "%d %%" % int(round(expected * 100.0)), "valeur affichée : %s" % row.value_text())
	await seconds(0.3)
	await at.screenshot("options_changed")
	# Restauration (les réglages sont ceux de la machine).
	await press("ui_right" if dir == "ui_left" else "ui_left")
	Settings.music_volume = before
	Settings.apply()
	Settings.save_settings()
	at.check(is_equal_approx(row.value, before), "valeur d'origine restaurée")


func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


func _buttons() -> Array:
	var out := []
	_collect(menu.current, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is MenuActionButton:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _focused_label() -> String:
	var f := at.get_viewport().gui_get_focus_owner()
	if f is MenuActionButton:
		return f.label
	return str(f)
