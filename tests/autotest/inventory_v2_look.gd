extends AutotestScenario
## @rendu : inventaire de partie v2 (docs/hub_v2/InventaireJeu.dc.html),
## ajout en cours : captures à comparer à la maquette (mêmes armes : PÉTOIRE,
## COUPERET avec une pièce, FEU FOLLET en main ; BALAI NEUF et GARDE-CHASSE
## dans le sac ; deux pièces trouvées ; 1 240 de ferraille, manche 12), en
## français, en anglais et à 130 % (TAILLE DES MENUS). Vérifie aussi que rien
## ne sort de l'écran (130 %) et que la fiche compare l'arme du sac à l'arme
## tenue.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var p := await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await until(func(): return game.hud.get_children().all(func(c): return not c is LoadingScreen), 5.0, "écran de chargement parti")
	var lang0 := String(Settings.language)
	var scale0 := Settings.menu_ui_scale
	var pd := game.session.local_data()
	pd.level = 20
	pd.points = 1240
	game.rounds.round_n = 12
	pd.weapons = [GameWeapon.make("m1911", 1, OwnedWeapon.Rarity.COMMON, [], "h0"),
		GameWeapon.make("python", 12, OwnedWeapon.Rarity.RARE, [{"id": "canon", "level": 4, "mods": {"damage": 0.08}}], "h1"),
		GameWeapon.make("spectre", 14, OwnedWeapon.Rarity.EPIC, [], "h2")]
	pd.slot = 0
	pd.bag = [GameWeapon.make("stakeout", 13, OwnedWeapon.Rarity.RARE, [], "b0"),
		GameWeapon.make("olympia", 11, OwnedWeapon.Rarity.COMMON, [], "b1")]
	game.session.sync_inventory(1)
	game.loot.my_parts = [{"id": "ressort", "uid": "p1", "level": 6, "mods": {"fire_rate": 0.06}},
		{"id": "crosse", "uid": "p2", "level": 3, "mods": {"recoil": -0.04}}]
	game.loot.loot_changed.emit()
	await frames(3)
	var inv := game.hud.inventory
	# NEUF : BALAI et GARDE-CHASSE pas encore vus ; le focus va au premier.
	for lang in ["fr", "en"]:
		Settings.language = lang
		inv.open()
		await frames(3)
		at.check(at.get_viewport().gui_get_focus_owner() == inv.bag_buttons[0], "focus sur l'arme NEUVE (%s)" % lang)
		at.check(inv.inspected_slot() == [InventoryPanel.ROW_BAG, 0] and inv.compared_hand([1, 0]) == 0,
				"fiche : BALAI comparé à PÉTOIRE (%s)" % lang)
		at.check(inv.bag_buttons[0].is_new and inv.bag_buttons[1].is_new, "NEUF sur les armes du sac (%s)" % lang)
		at.check(inv._bag_grid.columns == 4, "100 % : sac sur quatre colonnes")
		var d := " ".join(inv.prompts.describe())
		at.check(d.contains(Lang.t("ÉQUIPER", "EQUIP")) and d.contains(Lang.t("I FERMER", "I CLOSE")), "invites : %s" % d)
		await seconds(0.4)
		at.check(not game.hud._crosshair.visible and not game.hud._ammo.is_visible_in_tree(),
				"HUD (réticule, munitions) masqué sous l'inventaire (%s)" % lang)
		await at.screenshot(lang)
		if lang == "fr":
			# Manette : A / X / Y et la croix haut (touche d'inventaire réelle).
			Settings.using_pad = true
			inv.refresh()
			d = " ".join(inv.prompts.describe())
			at.check(d.begins_with("A ÉQUIPER X RECYCLER Y PIÈCES") and d.contains(PadNames.button_label(JOY_BUTTON_DPAD_UP, PadNames.XBOX)),
					"invites manette : %s" % d)
			await at.screenshot("fr_pad")
			Settings.using_pad = false
			inv.refresh()
		# Une arme en main : ÉCHANGER, sans comparaison.
		inv.hand_buttons[1].grab_focus()
		await frames(3)
		at.check(" ".join(inv.prompts.describe()).contains(Lang.t("ÉCHANGER", "SWAP")), "arme en main : ÉCHANGER")
		await at.screenshot(lang + "_hand")
		inv.close()
		await frames(2)
		at.check(game.hud._crosshair.visible and game.hud._ammo.is_visible_in_tree(), "HUD rendu à la fermeture (%s)" % lang)
		inv._seen.clear()
	# 130 % : rien ne sort de l'écran.
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.3
	inv.open()
	await frames(4)
	var vr := Rect2(Vector2.ZERO, at.get_viewport().get_visible_rect().size)
	var ok := true
	for c: Control in [inv._header, inv.prompts] + inv.hand_buttons + inv.bag_buttons:
		var r := c.get_global_rect()
		var inside := vr.grow(1.0).encloses(r) or not c.is_visible_in_tree()
		# Une case peut être sous le bas de la zone qui défile ; son conteneur,
		# lui, doit rester dans l'écran.
		if not inside and c is InventorySlot:
			inside = vr.grow(1.0).encloses(inv._left_scroll.get_global_rect())
		if not inside:
			ok = false
			at.fail("130 %% : %s sort de l'écran (%s)" % [c.name, r])
	at.check(ok, "130 % : en-tête, cases et invites dans l'écran")
	at.check(inv._bag_grid.columns == 2, "130 %% : sac sur deux colonnes (%d)" % inv._bag_grid.columns)
	at.check(vr.grow(1.0).encloses(inv.aside_box.get_global_rect()), "130 % : fiche dans l'écran")
	await seconds(0.4)
	await at.screenshot("fr_130")
	inv.close()
	Settings.menu_ui_scale = scale0
	Settings.language = lang0
