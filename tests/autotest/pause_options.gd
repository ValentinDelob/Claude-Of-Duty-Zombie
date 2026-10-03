extends AutotestScenario
## OPTIONS en jeu (solo), avec de vraies entrées clavier : Échap ouvre le menu
## pause (partie suspendue), OPTIONS ouvre l'écran d'options du menu
## principal par-dessus la partie, onglet COMMANDES, RECHARGER réaffecté à T
## (première case ; InputMap et settings.cfg vérifiés), touche partagée avec
## GRENADE, Échap qui annule une saisie, deuxième touche sur un cran de
## molette (qui ne change plus d'arme) puis effacée, case manette (A, Y, partagé avec
## CHANGER D'ARME, Start qui annule, invites manette puis clavier),
## commandes par défaut, RETOUR au menu pause et reprise.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 60
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	await until(func(): return game.hud.pause_menu != null, 2.0, "menu pause construit")
	var pm: PauseMenu = game.hud.pause_menu
	var z := await H.dummy_zombie(self, p.global_position + Vector3(0, 0, -8))
	z.speed_mult = 1.0

	# Échap : menu pause, partie suspendue (comme BO1 en solo).
	await key(KEY_ESCAPE)
	at.check(pm.visible and tree().paused, "Échap : menu pause, partie suspendue")
	var labels := _labels(pm)
	at.check(labels.slice(0, 3) == ["REPRENDRE", "OPTIONS", "QUITTER LA PARTIE"], "entrées : %s" % ", ".join(labels))
	at.check(_focused_label() == "REPRENDRE", "focus sur REPRENDRE (%s)" % _focused_label())
	var zpos := z.global_position
	await seconds(0.4)  # rien ne doit bouger : fenêtre d'observation fixe
	at.check(z.global_position.distance_to(zpos) < 0.01, "zombies figés pendant la pause")

	# OPTIONS : ↓ puis Entrée.
	await action("ui_down")
	at.check(_focused_label() == "OPTIONS", "↓ : OPTIONS (%s)" % _focused_label())
	await action("ui_accept")
	at.check(pm.current_name == "options" and pm.current != null, "OPTIONS : écran d'options par-dessus la partie")
	if pm.current == null:
		return
	var opt = pm.current
	at.check(opt.get_script() == load(MainMenu.SCREENS.options), "même écran que celui du menu principal")
	at.check(opt.in_game and tree().paused, "toujours en pause dans les options")
	await frames(2)
	at.check(_focused_label() == "JEU", "focus sur l'onglet JEU (%s)" % _focused_label())

	# Onglet COMMANDES (►).
	await action("ui_right")
	at.check(opt.tab == "controls" and opt.bind_rows.size() == Settings.REBINDABLE.size(),
			"► : onglet COMMANDES, %d actions réaffectables" % opt.bind_rows.size())
	at.check(opt.rows.has("mouse_sensitivity") and opt.rows.has("pad_look_sensitivity") and opt.rows.has("ads_sensitivity") and opt.rows.has("invert_y"),
			"sensibilités souris, manette et en visée, inversion")
	# Molette sur la liste des touches : la page défile (ni les lignes de
	# touches ni les jauges de cette page ne la consomment).
	var sv0: int = opt.scroll.scroll_vertical
	var ms0 := Settings.mouse_sensitivity
	await wheel(opt.bind_rows.jump, MOUSE_BUTTON_WHEEL_DOWN)
	await wheel(opt.rows.mouse_sensitivity, MOUSE_BUTTON_WHEEL_DOWN)
	at.check(opt.scroll.scroll_vertical > sv0, "molette : la page défile (%d -> %d)" % [sv0, opt.scroll.scroll_vertical])
	at.check(Settings.mouse_sensitivity == ms0, "la molette ne change pas la sensibilité")
	# ▼ jusqu'à RECHARGER (la page défile pour la garder visible).
	var row: MenuBindRow = opt.bind_rows.reload
	var guard := 0
	while at.get_viewport().gui_get_focus_owner() != row and guard < 20:
		await action("ui_down")
		guard += 1
	at.check(row.has_focus(), "▼ : ligne RECHARGER (%d appuis)" % guard)
	await frames(2)
	var sr := opt.scroll.get_global_rect() as Rect2
	at.check(sr.grow(2.0).encloses(row.get_global_rect()), "ligne visible dans la page qui défile (défilement %d)" % opt.scroll.scroll_vertical)

	# Entrée -> « Appuyez sur une touche… » -> T (une seule touche : R remplacée).
	await action("ui_accept")
	at.check(opt.capturing() and row.capturing == MenuBindRow.SLOT_KEY, "Entrée : attente d'une touche")
	await key(KEY_T)
	at.check(not opt.capturing(), "touche reçue")
	@warning_ignore("static_called_on_instance")
	at.check(Settings.bindings.reload == [Settings.key_code(KEY_T)], "Settings : RECHARGER = T (%s)" % str(Settings.bindings.reload))
	at.check(_has_key("reload", KEY_T) and not _has_key("reload", KEY_R), "InputMap : T recharge, R ne recharge plus")
	var cfg := ConfigFile.new()
	var ok := cfg.load(Settings.path) == OK
	@warning_ignore("static_called_on_instance")
	at.check(ok and Array(cfg.get_value("bindings", "reload", [])) == [Settings.key_code(KEY_T)], "enregistré dans %s" % Settings.path)
	at.check(pm.visible and tree().paused, "la saisie ne ferme pas le menu")

	# Touche déjà utilisée : G sur RECHARGER reste aussi sur GRENADE
	# (partagée), et c'est affiché.
	await action("ui_accept")
	await key(KEY_G)
	@warning_ignore("static_called_on_instance")
	at.check(Settings.bindings.reload == [Settings.key_code(KEY_G)], "RECHARGER = G")
	@warning_ignore("static_called_on_instance")
	at.check(Settings.bindings.grenade == [Settings.key_code(KEY_G)] and _has_key("grenade", KEY_G)
			and _has_key("reload", KEY_G), "G partagée : GRENADE la garde")
	at.check(pm._hint.text.contains("GRENADE"), "partage affiché : « %s »" % pm._hint.text)

	# Échap pendant une saisie : annule, l'écran reste ouvert.
	await action("ui_accept")
	await key(KEY_ESCAPE)
	at.check(not opt.capturing() and pm.current == opt, "Échap : saisie annulée, options toujours ouvertes")
	@warning_ignore("static_called_on_instance")
	at.check(Settings.bindings.reload == [Settings.key_code(KEY_G)], "rien n'a changé")

	# Quatre cases par ligne (deux touches, deux boutons), dans la page.
	var last_slot := MenuBindRow.slot_rect(MenuBindRow.SLOT_PAD2).end.x
	at.check(row.position.x + last_slot <= opt.scroll.size.x - opt.scroll.get_v_scroll_bar().size.x,
			"quatre cases dans la page (fin %.0f, page %.0f)" % [row.position.x + last_slot, opt.scroll.size.x])
	# Deuxième touche : ► puis Entrée, cran de molette bas -> RECHARGER = G
	# et molette bas ; ce cran ne change plus d'arme. L'invite reste G.
	await action("ui_right")
	at.check(row.slot == MenuBindRow.SLOT_KEY2, "► : deuxième case touche")
	await action("ui_accept")
	at.check(opt.capturing() and row.capturing == MenuBindRow.SLOT_KEY2, "Entrée : attente d'une deuxième touche")
	await wheel(row, MOUSE_BUTTON_WHEEL_DOWN)
	at.check(not opt.capturing(), "cran de molette reçu")
	@warning_ignore("static_called_on_instance")
	var wd := Settings.mouse_code(MOUSE_BUTTON_WHEEL_DOWN)
	@warning_ignore("static_called_on_instance")
	at.check(Settings.bindings.reload == [Settings.key_code(KEY_G), wd], "RECHARGER = G + molette bas (%s)" % str(Settings.bindings.reload))
	at.check(_has_mouse("reload", MOUSE_BUTTON_WHEEL_DOWN) and not _has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN)
			and _has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_UP), "molette bas : recharge ; molette haut : change d'arme")
	at.check(pm._hint.text.contains("molette") or pm._hint.text.contains("wheel"), "aide : « %s »" % pm._hint.text)
	at.check(Settings.action_label("reload") == "G", "invite : la première touche (%s)" % Settings.action_label("reload"))
	cfg = ConfigFile.new()
	at.check(cfg.load(Settings.path) == OK and Array(cfg.get_value("bindings", "reload", [])) == Settings.bindings.reload,
			"deux touches enregistrées")
	# Retour arrière : la deuxième case est vidée, la molette rechange d'arme.
	await key(KEY_BACKSPACE)
	@warning_ignore("static_called_on_instance")
	at.check(Settings.bindings.reload == [Settings.key_code(KEY_G)] and _has_mouse("switch_weapon", MOUSE_BUTTON_WHEEL_DOWN),
			"deuxième touche effacée, molette bas : changement d'arme")

	# Manette : ► case manette, A lance la saisie, Y est affecté à RECHARGER
	# et garde CHANGER D'ARME (partagé) ; l'invite du HUD passe à la manette.
	await action("ui_right")
	at.check(row.slot == MenuBindRow.SLOT_PAD, "► : case manette")
	await pad(JOY_BUTTON_A)
	at.check(opt.capturing() and row.capturing == MenuBindRow.SLOT_PAD, "A : attente d'un bouton de manette")
	await key(KEY_J)
	at.check(opt.capturing(), "une touche ne répond pas à la case manette")
	await pad(JOY_BUTTON_Y)
	at.check(not opt.capturing(), "bouton reçu")
	at.check(Settings.pad_bindings.reload == ["joy:%d" % JOY_BUTTON_Y] and Settings.pad_bindings.switch_weapon == ["joy:%d" % JOY_BUTTON_Y],
			"RECHARGER = Y, partagé avec CHANGER D'ARME (%s)" % str(Settings.pad_bindings.reload))
	@warning_ignore("static_called_on_instance")
	at.check(Settings.bindings.reload == [Settings.key_code(KEY_G)], "la touche reste")
	at.check(Settings.using_pad and Settings.action_label("reload") == "Y", "invites manette : « %s »" % Settings.action_label("reload"))
	# Start annule une saisie à la manette (B, lui, s'affecte).
	await pad(JOY_BUTTON_A)
	await pad(JOY_BUTTON_START)
	at.check(not opt.capturing() and pm.current == opt, "Start : saisie annulée, options toujours ouvertes")
	at.check(Settings.pad_bindings.reload == ["joy:%d" % JOY_BUTTON_Y], "rien n'a changé")

	# Rétablir les commandes par défaut (les deux colonnes).
	opt.reset_button.grab_focus()
	await frames(2)
	await action("ui_accept")
	@warning_ignore("static_called_on_instance")
	at.check(Settings.bindings == Settings.default_bindings() and Settings.pad_bindings == Settings.default_pad_bindings(),
			"commandes par défaut rétablies")
	at.check(_has_key("reload", KEY_R) and _has_key("grenade", KEY_G), "InputMap : R et G d'origine")
	at.check(Settings.action_label("reload") == "RB", "invite manette : RB recharge (%s)" % Settings.action_label("reload"))
	await key(KEY_J)
	at.check(not Settings.using_pad and Settings.action_label("reload") == "R", "clavier : invites clavier")

	# Onglet GRAPHISMES : nouvelles options appliquées tout de suite.
	opt.switch_tab(1)
	await frames(2)
	at.check(opt.tab == "graphics", "onglet GRAPHISMES")
	for k in ["quality", "fov", "fullscreen", "vsync", "film_grain", "render_scale", "max_fps", "brightness"]:
		at.check(opt.rows.has(k), "option %s" % k)
	var rs: MenuOptionRow = opt.rows.render_scale
	rs.grab_focus()
	await frames(2)
	await action("ui_left")
	at.check(is_equal_approx(Settings.render_scale, 0.95) and is_equal_approx(at.get_viewport().scaling_3d_scale, 0.95),
			"échelle de rendu 3D appliquée (%.2f)" % at.get_viewport().scaling_3d_scale)
	await action("ui_right")
	var br: MenuOptionRow = opt.rows.brightness
	var env: Environment = game.get_viewport().world_3d.environment if game.get_viewport().world_3d else null
	var we := game.find_child("WorldEnvironment", true, false) as WorldEnvironment
	env = we.environment if we else env
	var lut0 = env.adjustment_color_correction if env else null
	br.grab_focus()
	await frames(2)
	await action("ui_right")
	at.check(is_equal_approx(Settings.brightness, 1.05) and env != null and env.adjustment_color_correction != lut0,
			"luminosité appliquée à la carte (%.2f)" % Settings.brightness)
	await action("ui_left")
	at.check(env != null and env.adjustment_color_correction == lut0, "luminosité d'origine : table d'origine")
	# Limite d'images : --max-fps de la ligne de commande (tests) conservé.
	var mf: MenuOptionRow = opt.rows.max_fps
	mf.grab_focus()
	await frames(2)
	await action("ui_right")
	at.check(Settings.max_fps == 30, "limite d'images : 30 (%d)" % Settings.max_fps)
	if Settings._cmdline_max_fps > 0:
		at.check(Engine.max_fps == Settings._cmdline_max_fps, "--max-fps %d de la ligne de commande conservé (%d)" % [Settings._cmdline_max_fps, Engine.max_fps])
	await action("ui_left")
	at.check(Settings.max_fps == 0, "limite d'images : illimitée")

	# RETOUR (Échap) : menu pause, focus sur OPTIONS ; Échap : reprise.
	await key(KEY_ESCAPE)
	at.check(pm.visible and pm.current == null and tree().paused, "Échap : retour au menu pause")
	await frames(2)
	at.check(_focused_label() == "OPTIONS", "focus rendu à OPTIONS (%s)" % _focused_label())
	await key(KEY_ESCAPE)
	at.check(not pm.visible and not tree().paused, "Échap : reprise de la partie")
	await until(func(): return is_instance_valid(z) and z.global_position.distance_to(zpos) > 0.2, 3.0, "zombie reparti après la pause")
	at.check(z.global_position.distance_to(zpos) > 0.2, "les zombies repartent")
	# Rouvert puis refermé par REPRENDRE : l'état « options » ne reste pas.
	await key(KEY_ESCAPE)
	at.check(pm.visible and pm.current == null, "Échap : menu pause rouvert")
	await action("ui_accept")
	at.check(not pm.visible and not tree().paused, "REPRENDRE")


func key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


func action(a: String) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = a
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


## Cran de molette au-dessus du contrôle `c`.
func wheel(c: Control, b: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = b
	ev.pressed = true
	ev.factor = 1.0
	ev.position = at.get_viewport().get_final_transform() * c.get_global_rect().get_center()
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


func _has_key(a: String, k: Key) -> bool:
	for ev in InputMap.action_get_events(a):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == k:
			return true
	return false


func _has_mouse(a: String, b: MouseButton) -> bool:
	for ev in InputMap.action_get_events(a):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == b:
			return true
	return false


func _labels(n: Node, out := []) -> Array:
	if n is MenuActionButton and not n.is_queued_for_deletion():
		out.append(n.label)
	for c in n.get_children():
		_labels(c, out)
	return out


func _focused_label() -> String:
	var f := at.get_viewport().gui_get_focus_owner()
	if f is MenuActionButton:
		return f.label
	return str(f)


## Appui puis relâche d'un bouton de manette.
func pad(b: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = b
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)
