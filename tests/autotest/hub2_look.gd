extends AutotestScenario
## @rendu : cadre du hub v2 (docs/HUB_PLAN.md §9, maquettes docs/hub_v2) EN
## COURS DE DÉVELOPPEMENT : captures à comparer aux maquettes (fond 3D en
## direct assombri, barre du haut, invites, verre flouté, polices, anneaux
## pulsés), navigation réelle au clavier et à la manette (E, RB, START, B,
## Échap), fil d'Ariane, anglais, TAILLE DES MENUS 130 %.
## Captures : tests/_out/shots/hub2_look_<écran>_<hauteur>.png.
## HUB_SHOT_RES=1920x1080 : captures à cette taille.
## Scénario retiré (ou réduit aux vérifications logiques) une fois le hub v2
## livré (captures seulement pour un ajout en cours).

var menu: MainMenu
var hub: Hub2Screen
var _saved_name := ""


## Profil de la maquette : niveau 23, 64 % du niveau.
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(23) + int(PlayerProfile.xp_to_next(23) * 0.643)
	return pr


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	var res := OS.get_environment("HUB_SHOT_RES")
	if res != "" and DisplayServer.get_name() != "headless":
		var p := res.split("x")
		if p.size() == 2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
			await frames(3)
	await until(_settled, 5.0, "menu titre affiché")
	_saved_name = Settings.player_name
	Settings.player_name = "Valentin"
	# Ouverture par JOUER avec le réglage caché.
	Settings.hub_v2 = true
	ProfileStore.save_profile(demo_profile())
	await press("ui_accept")
	at.check(menu.current_name == "hub2", "JOUER (réglage hub_v2) : hub v2 (%s)" % menu.current_name)
	await until(_settled, 3.0, "hub v2 affiché")
	hub = menu.current
	at.check(hub.current_id == "lab", "LABO à l'ouverture (%s)" % hub.current_id)
	at.check(not menu._cctv.visible, "habillage du menu titre masqué")
	at.check(_focused() == hub.panels.lab.contracts_button, "focus sur CONTRATS")
	await seconds(1.0)  # anneaux et fond posés
	await shot("lab")
	# Même contenu que la maquette Main.dc.html (comparaison au pixel) :
	# XP 8 420 / 13 100, pastilles LABO, ARSENAL, CODEX, invites manette.
	await _mockup_frame()
	await shot("lab_mockup")
	_mockup_frame_end()
	# Onglets : E, RB, Q (clavier / manette), clic.
	await key(KEY_E)
	at.check(hub.current_id == "arsenal", "E : ARSENAL (%s)" % hub.current_id)
	await seconds(0.3)
	await shot("arsenal")
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	at.check(hub.current_id == "inventory", "RB : INVENTAIRE (%s)" % hub.current_id)
	var d := hub.prompts.describe()
	at.check(d.size() == 2 and d[0] == "A VOIR LE CONTRAT", "invites manette : %s" % ", ".join(d))
	await seconds(0.3)
	await shot("inventory_pad")
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	at.check(hub.current_id == "codex", "RB : CODEX (%s)" % hub.current_id)
	await seconds(0.3)
	await shot("codex_pad")
	await pad(JOY_BUTTON_START)
	at.check(hub.current_id == "play" and hub.top_bar.play_active, "START : JOUER (%s)" % hub.current_id)
	await seconds(0.3)
	await shot("play_pad")
	await pad(JOY_BUTTON_B)
	await frames(2)
	at.check(hub.current_id == "codex", "B sur JOUER : retour au CODEX (%s)" % hub.current_id)
	await key(KEY_TAB, false)  # retour au clavier
	await click(hub.top_bar.get_global_transform() * hub.top_bar.tab_rects.lab.get_center())
	at.check(hub.current_id == "lab", "clic : LABO (%s)" % hub.current_id)
	# Sous-écrans : Entrée sur CONTRATS, fil d'Ariane, Échap.
	hub.panels.lab.contracts_button.grab_focus()
	await frames(2)
	await press("ui_accept")
	at.check(hub.current_id == "contracts" and hub.crumb.visible, "Entrée : LABO / CONTRATS (%s)" % hub.current_id)
	await seconds(0.3)
	await shot("contracts")
	await press("ui_cancel")
	at.check(hub.current_id == "lab", "Échap : retour au LABO (%s)" % hub.current_id)
	hub.open("exchanges")
	await seconds(0.3)
	await shot("exchanges")
	await click(hub.crumb.get_global_transform() * hub.crumb.parent_rect().get_center())
	at.check(hub.current_id == "lab", "clic « ‹ LABO » : retour (%s)" % hub.current_id)
	await press("ui_cancel")
	at.check(hub.hub_menu.is_open(), "Échap au LABO : menu du hub")
	await press("ui_cancel")
	at.check(not hub.hub_menu.is_open(), "Échap : menu fermé")
	hub.open("recap")
	await seconds(0.3)
	at.check(not hub.top_bar.visible and not hub.prompts.visible, "récapitulatif : sans barre du haut ni invites")
	await shot("recap")
	hub.open("lab")
	# TAILLE DES MENUS 130 %.
	Settings.menu_ui_scale = 1.3
	await frames(4)
	hub = menu.current
	await seconds(0.4)
	_check_inside(hub, "taille 130 %")
	await shot("lab_130")
	Settings.menu_ui_scale = 1.0
	await frames(3)
	# Anglais.
	Settings.language = "en"
	menu.show_screen("hub2", {"screen": "lab"})
	await until(_settled, 3.0, "hub v2 en anglais")
	hub = menu.current
	at.check(hub.top_bar.play_text.text == "START", "bouton START en anglais (%s)" % hub.top_bar.play_text.text)
	await seconds(0.5)
	await shot("lab_en")
	Settings.language = "fr"
	Settings.hub_v2 = false
	Settings.player_name = _saved_name
	ProfileStore.reset()


## Cadre rempli comme la maquette (TopBar et Prompts de Main.dc.html).
func _mockup_frame() -> void:
	var tb := hub.top_bar
	tb.xp_in = 8420
	tb.xp_need = 13100
	for id in ["lab", "arsenal", "codex"]:
		tb.set_badge(id, true)
	tb._layout()
	Settings.using_pad = true
	hub.set_hint("Un contrat est terminé : la récompense t’attend au bureau des contrats.")
	# Un contrat terminé : anneaux pulsés autour de CONTRATS.
	hub.panels.lab.rings.running = true
	hub.panels.lab.rings.t = 0.5
	await seconds(0.3)


func _mockup_frame_end() -> void:
	Settings.using_pad = false
	hub.set_hint("")
	hub.panels.lab.refresh()
	hub.top_bar.show_profile(hub.profile)
	hub.refresh_badges()
	hub.top_bar._layout()


func _check_inside(root: Control, what: String) -> void:
	var screen := Rect2(Vector2.ZERO, root.get_viewport_rect().size).grow(1.0)
	var bad := []
	_scan_inside(root, screen, bad)
	at.check(bad.is_empty(), "%s : rien ne sort de l'écran %s" % [what, str(bad.slice(0, 4))])


func _scan_inside(n: Node, screen: Rect2, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		if not (c is Hub2PulseRings) and not screen.encloses(c.get_global_rect()):
			bad.append("%s %s" % [c.name, c.get_global_rect()])
	for ch in n.get_children():
		_scan_inside(ch, screen, bad)


func shot(n: String) -> void:
	await at.screenshot("%s_%d" % [n, DisplayServer.window_get_size().y])


func _settled() -> bool:
	return is_instance_valid(menu) and menu.current != null and menu.current.modulate.a >= 0.999 \
		and menu._fade_amount < 0.001


func _focused() -> Control:
	return at.get_viewport().gui_get_focus_owner()


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


func key(physical: int, _wait := true) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical as Key
	ev.keycode = physical as Key
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


func pad(button: int, _wait := true) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button as JoyButton
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventJoypadButton
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


func click(global_pos: Vector2) -> void:
	var vp := at.get_viewport()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = global_pos
	ev.global_position = global_pos
	vp.push_input(ev, true)
	await frames(2)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	vp.push_input(up, true)
	await frames(3)
