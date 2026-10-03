extends AutotestScenario
## @rendu : OPTIONS > COMMANDES avec des commandes partagées entre actions
## (capture de la fonction en cours, à retirer une fois validée). F affectée à
## RECHARGER (deuxième case) en passant par la vraie saisie de l'écran : elle
## reste sur INTERAGIR / ACHETER ; molette bas sur COUTEAU et GRENADE ; X de la
## manette aussi sur SAUTER. Les cases partagées portent « AUSSI : … » et la
## barre d'aide nomme les autres actions ; captures en français puis en
## anglais. Réglages du test seulement (fichier d'autotest, jamais celui du
## joueur).


func run() -> void:
	timeout_sec = 40
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var menu: MainMenu = tree().current_scene
	var lang0 := String(Settings.language)
	Settings.language = "fr"
	menu.show_screen("options", {"tab": "controls"})
	var opt = menu.current
	await until(func(): return is_instance_valid(opt) and opt.modulate.a >= 0.999, 3.0, "écran d'options affiché")
	# Saisie réelle : Entrée sur la case 2 de RECHARGER, puis la touche F.
	var reload_row: MenuBindRow = opt.bind_rows.reload
	reload_row.grab_focus()
	await frames(2)
	opt._on_rebind_requested(reload_row, MenuBindRow.SLOT_KEY2)
	await frames(2)
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	f.pressed = true
	Input.parse_input_event(f)
	await frames(2)
	at.check(Settings.bindings.reload == ["key:%d" % KEY_R, "key:%d" % KEY_F], "F en case 2 de RECHARGER (%s)" % [Settings.bindings.reload])
	at.check(Settings.bindings.interact == ["key:%d" % KEY_F], "INTERAGIR garde F (%s)" % [Settings.bindings.interact])
	var hint: String = menu._hint.text
	at.check(hint.contains("INTERAGIR"), "aide après la saisie : « %s »" % hint)
	Settings.bind("melee", "mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN, 1)
	Settings.bind("grenade", "mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN, 1)
	Settings.bind("jump", "joy:%d" % JOY_BUTTON_X, 1)
	# Case partagée choisie : l'aide détaille.
	reload_row._select(MenuBindRow.SLOT_KEY2, false)
	await frames(2)
	hint = menu._hint.text
	at.check(hint.contains("INTERAGIR") and hint.contains("sert aussi"), "aide de la case partagée : « %s »" % hint)
	await seconds(0.6)  # éclats des cases éteints, rendu posé
	await at.screenshot("controls_fr")
	# Plus bas : INTERAGIR (F), COUTEAU et GRENADE (molette bas).
	opt.bind_rows.grenade.grab_focus()
	await seconds(0.5)
	await at.screenshot("controls_fr_bas")
	# Anglais : écran reconstruit.
	Settings.language = "en"
	menu.show_screen("options", {"tab": "controls"}, false)
	opt = menu.current
	await until(func(): return is_instance_valid(opt) and opt.modulate.a >= 0.999, 3.0, "écran d'options (anglais)")
	reload_row = opt.bind_rows.reload
	reload_row.grab_focus()
	await frames(2)
	reload_row._select(MenuBindRow.SLOT_KEY2, false)
	await frames(2)
	hint = menu._hint.text
	at.check(hint.contains("USE / BUY") and hint.contains("also used"), "aide en anglais : « %s »" % hint)
	await seconds(0.6)
	await at.screenshot("controls_en")
	Settings.language = lang0
	Settings.reset_bindings()
