extends AutotestScenario
## @rendu : le hub (Hub2Screen, docs/HUB_PLAN.md §9) parcouru au clavier, à
## la manette et à la souris (événements d'entrée réels) depuis le menu
## titre : JOUER -> LABO (habillage du menu titre masqué, focus sur
## CONTRATS) ; onglets E, RB, clic ; START : JOUER, B : retour ; Entrée sur
## CONTRATS (fil d'Ariane), Échap ; clic « ‹ LABO » ; Échap au LABO : menu du
## hub ; récapitulatif sans cadre ; TAILLE DES MENUS 130 % (rien ne sort de
## l'écran) ; anglais.
## Seul scénario du hub avec captures (tests/_out/shots/hub_look_<écran>_
## <hauteur>.png) : informatives, pour la revue humaine, elles ne bloquent
## rien ; seules les vérifications logiques comptent. HUB_SHOT_RES=1920x1080 :
## captures à cette taille.

var menu: MainMenu
var hub: Hub2Screen
var _saved_name := ""


## Profil de niveau 23, 64 % du niveau.
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
	ProfileStore.save_profile(demo_profile())
	await press("ui_accept")
	at.check(menu.current_name == "hub" and menu.current is Hub2Screen, "JOUER : le hub (%s)" % menu.current_name)
	await until(_settled, 3.0, "hub affiché")
	hub = menu.current
	at.check(hub.current_id == "lab", "LABO à l'ouverture (%s)" % hub.current_id)
	at.check(not menu._cctv.visible, "habillage du menu titre masqué")
	at.check(_focused() == hub.panels.lab.contracts_button, "focus sur CONTRATS")
	await seconds(1.0)  # anneaux et fond posés
	await shot("lab")
	# Onglets : E, RB (clavier / manette), clic.
	await key(KEY_E)
	at.check(hub.current_id == "arsenal", "E : ARSENAL (%s)" % hub.current_id)
	await seconds(0.3)
	await shot("arsenal")
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	at.check(hub.current_id == "inventory", "RB : INVENTAIRE (%s)" % hub.current_id)
	var d := hub.prompts.describe()
	at.check(d.size() == 2 and d[0] == "A VOIR LE CONTRAT", "invites manette : %s" % ", ".join(d))
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	at.check(hub.current_id == "codex", "RB : CODEX (%s)" % hub.current_id)
	await seconds(0.3)
	await shot("codex")
	await pad(JOY_BUTTON_START)
	at.check(hub.current_id == "play" and hub.top_bar.play_active, "START : JOUER (%s)" % hub.current_id)
	await seconds(0.3)
	await shot("play")
	await pad(JOY_BUTTON_B)
	await frames(2)
	at.check(hub.current_id == "codex", "B sur JOUER : retour au CODEX (%s)" % hub.current_id)
	await key(KEY_TAB)  # retour au clavier
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
	await frames(3)
	await click(hub.crumb.get_global_transform() * hub.crumb.parent_rect().get_center())
	at.check(hub.current_id == "lab", "clic « ‹ LABO » : retour (%s)" % hub.current_id)
	await press("ui_cancel")
	at.check(hub.hub_menu.is_open(), "Échap au LABO : menu du hub")
	await shot("menu")
	await press("ui_cancel")
	at.check(not hub.hub_menu.is_open(), "Échap : menu fermé")
	hub.open("recap")
	await frames(3)
	at.check(not hub.top_bar.visible and not hub.prompts.visible, "récapitulatif : sans barre du haut ni invites")
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
	menu.show_screen("hub", {"screen": "lab"})
	await until(_settled, 3.0, "hub en anglais")
	hub = menu.current
	at.check(hub.top_bar.play_text.text == "START", "bouton START en anglais (%s)" % hub.top_bar.play_text.text)
	Settings.language = "fr"
	Settings.player_name = _saved_name
	ProfileStore.reset()


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


## Capture informative (revue humaine), jamais comparée.
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


func key(physical: int) -> void:
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


func pad(button: int) -> void:
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
