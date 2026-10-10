extends AutotestScenario
## @rendu : hub du scientifique (docs/HUB_PLAN.md, lot B) parcouru au clavier
## et à la manette (événements d'entrée réels) : menu titre réduit (JOUER,
## ÉDITEUR DE CARTES, OPTIONS, CRÉDITS, QUITTER) -> JOUER -> LABO (profil de
## démonstration proche de la maquette, écran 1) -> les 7 onglets (E, Page
## suiv., Q, clic) -> menu du hub (Échap) -> invites à la manette (LB / RB) ->
## TAILLE DES MENUS 80 et 130 % (rien ne sort de l'écran) -> anglais ->
## PARTIE -> SOLO (écran de sélection de carte actuel) -> retour au hub.
## Captures pendant le développement (comparaison avec la maquette), suffixe
## = hauteur de la fenêtre (720, 1080).

var menu: MainMenu
var hub: HubScreen


## Profil de démonstration (maquette : niveau 7, 2 140 / 3 320 XP,
## échantillons 7 / 2 / 5, armes et pièces).
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 2140
	pr.add_samples("dog_fang", 7)
	pr.add_samples("dog_fur", 2)
	pr.add_samples("dog_collar", 5)
	var w := OwnedWeapon.create("mp5k", 7, OwnedWeapon.Rarity.EPIC)
	w.parts.append(WeaponPart.create("damage", 6, {"damage": 0.15}))
	w.parts.append(WeaponPart.create("fire_rate", 5, {"fire_rate": 0.1, "accuracy": -0.06}))
	pr.add_weapon(w)
	pr.add_weapon(OwnedWeapon.create("mp5k", 5, OwnedWeapon.Rarity.RARE))
	pr.add_weapon(OwnedWeapon.create("m16", 6, OwnedWeapon.Rarity.RARE))
	pr.add_weapon(OwnedWeapon.create("python", 9, OwnedWeapon.Rarity.LEGENDARY))
	pr.add_weapon(OwnedWeapon.create("stakeout", 3, OwnedWeapon.Rarity.COMMON))
	pr.add_weapon(OwnedWeapon.create("m14", 4, OwnedWeapon.Rarity.COMMON))
	for p in [["damage", 9], ["mag", 7], ["accuracy", 6], ["recoil", 4], ["reload", 2]]:
		pr.add_part(WeaponPart.create(p[0], p[1], {p[0]: 0.1}))
	return pr


## Dernière partie de démonstration (maquette : BUNKER K7, solo, évacuation
## manche 10, 171 zombies, +2 312 XP, 2 armes, 1 pièce, 6 échantillons).
static func demo_last_match() -> Dictionary:
	var r := MatchResult.new()
	r.evacuated = true
	r.round_reached = 10
	r.kills = 171
	r.xp = 2312
	r.loot = {"kept": true, "weapons": [["mp5k", 7, 2], ["m14", 4, 0]], "parts": 1,
		"samples": {"dog_fang": 2, "dog_fur": 2, "dog_collar": 2}}
	return {"result": r, "map": "BUNKER K7", "solo": true}


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	# HUB_SHOT_RES=1920x1080 : captures à cette taille (la fenêtre, hors
	# écran, serait sinon ramenée à la zone de travail de l'écran).
	var res := OS.get_environment("HUB_SHOT_RES")
	if res != "" and DisplayServer.get_name() != "headless":
		var p := res.split("x")
		if p.size() == 2:
			# Sans bordure : Windows ne la ramène plus à la zone de travail.
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
			await frames(3)
			print("[hub_nav] fenêtre %s" % DisplayServer.window_get_size())
	await until(_settled, 5.0, "menu titre affiché")
	var labels := []
	for b in _buttons(menu.current):
		labels.append(b.label)
	at.check(labels == ["JOUER", "ÉDITEUR DE CARTES", "OPTIONS", "CRÉDITS", "QUITTER"], "menu titre réduit : %s" % ", ".join(labels))
	ProfileStore.save_profile(demo_profile())
	Router.last_match = demo_last_match()
	await press("ui_accept")  # JOUER
	at.check(menu.current_name == "hub", "JOUER : hub (%s)" % menu.current_name)
	await until(_settled, 3.0, "hub affiché")
	hub = menu.current
	at.check(hub.tab == "lab", "onglet LABO à l'ouverture (%s)" % hub.tab)
	at.check(_focused() == hub.panels.lab.contracts_button, "focus sur VOIR LES CONTRATS")
	at.check(not menu._cctv.visible, "habillage du menu titre masqué sous le hub")
	await seconds(0.4)
	await shot("lab")
	# Onglets : E, Page suiv., Q (clavier) puis clic.
	await key(KEY_E)
	at.check(hub.tab == "arsenal", "E : ARSENAL (%s)" % hub.tab)
	await press("ui_page_down")
	at.check(hub.tab == "parts", "Page suiv. : PIÈCES (%s)" % hub.tab)
	await key(KEY_Q)
	at.check(hub.tab == "arsenal", "Q : ARSENAL (%s)" % hub.tab)
	await seconds(0.3)
	await shot("arsenal_placeholder")
	for i in 5:
		await key(KEY_E)
	at.check(hub.tab == "play", "E x5 : PARTIE (%s)" % hub.tab)
	at.check(_focused() == hub.panels.play.solo_button, "PARTIE : focus sur SOLO")
	await seconds(0.3)
	await shot("play_stub")
	await click(hub.tab_bar.get_global_transform() * hub.tab_bar.tab_rect(3).get_center())
	at.check(hub.tab == "contracts", "clic : CONTRATS (%s)" % hub.tab)
	await key(KEY_E)
	await key(KEY_E)
	await key(KEY_E)
	await key(KEY_E)
	at.check(hub.tab == "lab", "E en boucle : retour au LABO (%s)" % hub.tab)
	# Menu du hub (Échap), puis fermeture (Échap).
	await press("ui_cancel")
	at.check(hub.hub_menu.is_open(), "Échap : menu du hub ouvert")
	await seconds(0.3)
	await shot("hub_menu")
	await press("ui_cancel")
	at.check(not hub.hub_menu.is_open(), "Échap : menu du hub fermé")
	# Manette : invites LB / RB, A, START.
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	at.check(Settings.using_pad, "manette utilisée en dernier")
	at.check(hub.tab == "arsenal", "RB : ARSENAL (%s)" % hub.tab)
	await pad(JOY_BUTTON_LEFT_SHOULDER)
	at.check(hub.tab == "lab", "LB : LABO (%s)" % hub.tab)
	var d := hub.prompts.describe()
	at.check(d.size() == 3 and d[1] == "LB RB Onglets", "invites manette : %s" % ", ".join(d))
	await seconds(0.3)
	await shot("lab_pad")
	await pad(JOY_BUTTON_START)
	at.check(hub.hub_menu.is_open(), "Start : menu du hub")
	await pad(JOY_BUTTON_B)
	at.check(not hub.hub_menu.is_open(), "B : menu fermé")
	await key(KEY_TAB, false)  # retour au clavier (aucun effet au LABO)
	# Taille des menus.
	for f in [0.8, 1.3]:
		Settings.menu_ui_scale = f
		await frames(4)
		hub = menu.current
		_check_inside(hub, "taille %d %%" % roundi(f * 100.0))
		await seconds(0.3)
		await shot("lab_%d" % roundi(f * 100.0))
	Settings.menu_ui_scale = 1.0
	await frames(3)
	# Anglais.
	Settings.language = "en"
	menu.show_screen("hub")
	await until(_settled, 3.0, "hub réaffiché en anglais")
	hub = menu.current
	at.check(hub.tab_bar.labels[0] == "LAB" and hub.tab_bar.labels[6] == "PLAY", "onglets en anglais : %s" % ", ".join(hub.tab_bar.labels))
	await seconds(0.3)
	await shot("lab_en")
	await pad(JOY_BUTTON_Y, false)
	await frames(2)
	await seconds(0.3)
	await shot("lab_en_pad")
	Settings.language = "fr"
	Settings.using_pad = false
	menu.show_screen("hub")
	await until(_settled, 3.0, "hub réaffiché")
	hub = menu.current
	# PARTIE -> SOLO : écran de sélection de carte actuel, Échap : retour au hub.
	hub.select_tab("play")
	await frames(3)
	await press("ui_accept")
	at.check(menu.current_name == "map_select", "PARTIE > SOLO : sélection de carte (%s)" % menu.current_name)
	await until(_settled, 3.0, "sélection de carte affichée")
	await press("ui_cancel")
	at.check(menu.current_name == "hub", "Échap : retour au hub (%s)" % menu.current_name)
	await until(_settled, 3.0, "hub réaffiché")
	at.check(menu.current.tab == "play", "retour sur l'onglet PARTIE (%s)" % menu.current.tab)
	ProfileStore.reset()


## Aucun contrôle visible du hub ne sort de l'écran (1280 × 720 logiques).
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
		if not screen.encloses(c.get_global_rect()):
			bad.append("%s %s" % [c.name, c.get_global_rect()])
		if c is ScrollContainer:
			return  # le contenu défile : il peut dépasser
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
	# Coordonnées de la toile (1280 × 720 logiques), quelle que soit la fenêtre.
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


func _buttons(root: Node) -> Array:
	var out := []
	_collect(root, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is MenuActionButton:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
