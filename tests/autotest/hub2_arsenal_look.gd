extends "res://tests/autotest/hub2_look.gd"
## @rendu : ARSENAL du hub v2 (docs/hub_v2/Arsenal.dc.html) EN COURS DE
## DÉVELOPPEMENT : captures à comparer à la maquette, avec le même contenu
## (joueur niveau 23, COUPERET légendaire niveau 20 choisi, fenêtre des
## niveaux 12 à 24, NEUF, BASE, NIV. 24 REQUIS) ; navigation réelle au
## clavier et à la manette (◄ ► ▲ ▼, Y, A, X, B), sous-onglet PIÈCES,
## fenêtre d'installation, anglais, TAILLE DES MENUS 130 %.
## Captures : tests/_out/shots/hub2_arsenal_look_<écran>_<hauteur>.png.
## Scénario retiré une fois l'écran livré (captures seulement pour un ajout
## en cours).


## Profil de la maquette : niveau 23 ; armes de la maquette (modèles réels
## du jeu) rangées par niveau, pièces en stock de plusieurs niveaux.
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(23) + int(PlayerProfile.xp_to_next(23) * 0.643)
	var R := OwnedWeapon.Rarity
	var specs := [
		["mp40", 1, R.COMMON, [], false],
		["olympia", 3, R.RARE, [[3, {"damage": 0.06}]], false],
		["m14", 5, R.COMMON, [], false],
		["cz75", 8, R.RARE, [[6, {"fire_rate": 0.1}], [8, {"mag": 0.2}]], false],
		["m16", 12, R.EPIC, [[10, {"accuracy": 0.15}], [11, {"damage": 0.1}]], false],
		["m14", 14, R.RARE, [[12, {"reload": 0.12}]], false],
		["stakeout", 18, R.RARE, [], true],
		["python", 20, R.LEGENDARY, [[18, {"damage": 0.08}], [18, {"fire_rate": 0.06, "reload": -0.12}]], false],
		["python", 20, R.RARE, [[15, {"damage": 0.05}]], false],
		["spectre", 20, R.EPIC, [], true],
		["galil", 24, R.UNIQUE, [], true],
		["m14", 24, R.EPIC, [], false],
	]
	for s in specs:
		var w := OwnedWeapon.create(s[0], s[1], s[2])
		for pp in s[3]:
			var mods: Dictionary = pp[1]
			w.parts.append(WeaponPart.create("part_" + String(mods.keys()[0]), int(pp[0]), mods))
		pr.add_weapon(w)
		if not s[4]:
			pr.mark_weapon_seen(w.uid)
		for p in w.parts:
			pr.mark_part_seen(p.uid)
	for pp in [[3, {"damage": 0.12}], [7, {"fire_rate": 0.08, "accuracy": -0.05}], [7, {"mag": 0.25}],
			[12, {"reload": 0.2}], [18, {"accuracy": 0.18, "damage": 0.05}], [22, {"damage": 0.22}]]:
		var mods2: Dictionary = pp[1]
		var p2 := WeaponPart.create("part_" + String(mods2.keys()[0]), int(pp[0]), mods2)
		pr.add_part(p2)
		if int(pp[0]) != 22:
			pr.mark_part_seen(p2.uid)
	return pr


func run() -> void:
	timeout_sec = 150
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
	Settings.hub_v2 = true
	var pr := demo_profile()
	ProfileStore.save_profile(pr)
	menu.show_screen("hub2", {"screen": "arsenal"})
	await until(_settled, 3.0, "hub v2 affiché")
	hub = menu.current
	at.check(hub.current_id == "arsenal", "ARSENAL ouvert (%s)" % hub.current_id)
	var ap: Hub2ArsenalPanel = hub.panels.arsenal
	at.check(ap.selected_weapon() != null and ap.selected_weapon().weapon_id == "python" and ap.selected_weapon().rarity == OwnedWeapon.Rarity.LEGENDARY,
			"COUPERET légendaire choisi à l'ouverture")
	at.check(ap.rail.start == 4 and ap.rail.visible == 5, "fenêtre NIV. 12 à 24 (start %d)" % ap.rail.start)
	await seconds(0.8)
	await shot("weapons")
	# Même cadre que la maquette : invites manette, aide de l'écran.
	Settings.using_pad = true
	hub.set_hint("")
	await seconds(0.3)
	var d: PackedStringArray = hub.prompts.describe()
	at.check(d.size() == 4 and d[0].begins_with("A ") and d[1].begins_with("X ") and d[2].begins_with("Y ") and d[3].begins_with("B "),
			"invites de la maquette : %s" % ", ".join(d))
	await shot("weapons_mockup")
	# Manette : ▼ (même niveau), ► (niveau suivant), ◄ ◄, Y (filtre).
	await press("ui_down")
	at.check(ap.rail.sel_row == 1, "▼ : carte suivante du niveau 20")
	await press("ui_right")
	at.check(ap.rail.selected_level() == 24, "► : niveau 24 (%d)" % ap.rail.selected_level())
	await seconds(0.2)
	await shot("weapons_locked_pad")
	await press("ui_left")
	await press("ui_left")
	await press("ui_left")
	at.check(ap.rail.selected_level() == 14, "◄ ◄ ◄ : niveau 14 (%d)" % ap.rail.selected_level())
	await pad(JOY_BUTTON_Y)
	at.check(ap.filter == "firearm", "Y : À FEU (%s)" % ap.filter)
	await seconds(0.2)
	await shot("weapons_filter_pad")
	await pad(JOY_BUTTON_Y)
	await pad(JOY_BUTTON_Y)
	await pad(JOY_BUTTON_Y)
	at.check(ap.filter == "all", "Y en boucle : TOUTES")
	# A : emplacements de la fiche ; A sur un emplacement libre : fenêtre.
	ap.selected_uid = ""
	for w in hub.profile.weapons:
		if w.weapon_id == "m14" and w.level == 5:
			ap.selected_uid = w.uid
	ap.refresh()
	await frames(2)
	ap.selected_card().grab_focus()
	await frames(2)
	await pad(JOY_BUTTON_A)
	var f := _focused()
	at.check(f in ap.slots, "A sur la carte : emplacement libre de la fiche")
	await seconds(0.2)
	await shot("weapons_slot_pad")
	await pad(JOY_BUTTON_A)
	at.check(ap.picker != null, "A : fenêtre d'installation")
	await seconds(0.3)
	await shot("picker_pad")
	await pad(JOY_BUTTON_B)
	at.check(ap.picker == null, "B : fenêtre fermée")
	# Sous-onglet PIÈCES.
	Settings.using_pad = false
	ap.set_tab(Hub2ArsenalPanel.PARTS)
	await seconds(0.3)
	at.check(ap.tab == Hub2ArsenalPanel.PARTS and ap.rail.count() == hub.profile.parts.size(), "PIÈCES : toutes les pièces en stock")
	await shot("parts")
	# Anglais.
	Settings.language = "en"
	ap.set_tab(Hub2ArsenalPanel.WEAPONS)
	hub.rebuild()
	await seconds(0.5)
	ap = hub.panels.arsenal
	at.check(ap.name_text == "CLEAVER", "anglais : CLEAVER (%s)" % ap.name_text)
	await shot("weapons_en")
	Settings.language = "fr"
	# TAILLE DES MENUS 130 %.
	Settings.menu_ui_scale = 1.3
	await frames(4)
	hub = menu.current
	await seconds(0.5)
	ap = hub.panels.arsenal
	_check_inside(hub, "ARSENAL à 130 %")
	at.check(ap.rail.visible == 3, "130 %% : 3 colonnes (%d)" % ap.rail.visible)
	await shot("weapons_130")
	ap.set_tab(Hub2ArsenalPanel.PARTS)
	await seconds(0.3)
	_check_inside(hub, "PIÈCES à 130 %")
	await shot("parts_130")
	Settings.menu_ui_scale = 1.0
	await frames(3)
	Settings.using_pad = false
	Settings.hub_v2 = false
	Settings.player_name = _saved_name
	ProfileStore.reset()


func _scan_inside(n: Node, screen: Rect2, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		if not (c is Hub2PulseRings) and not screen.encloses(c.get_global_rect()):
			bad.append("%s %s" % [c.name, c.get_global_rect()])
		# Contenu d'une liste qui défile : coupé par la liste.
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_scan_inside(ch, screen, bad)
