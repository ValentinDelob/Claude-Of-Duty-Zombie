extends AutotestScenario
## @rendu : station de construction v2 (docs/hub_v2/Station.dc.html), ajout
## en cours : captures à comparer à la maquette (mêmes armes que la
## maquette : GARDE-CHASSE niv. 3 … COUPERET légendaire et rare niv. 20,
## BOURRASQUE niv. 24 ; joueur niveau 23, 2 480 de ferraille, manche 12,
## COUPERET en main 6 / 12), en français (filtres CONSTRUCTIBLES et TOUTES),
## en anglais, à la manette, construction en cours et à 130 % (TAILLE DES
## MENUS). Vérifie aussi que rien ne sort de l'écran (130 %), l'effet de
## rareté (aucun pour une commune, halo dès la rare, rayons pour la
## légendaire) et le HUD masqué sous la station.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(23))
	var R := OwnedWeapon.Rarity
	var specs := [["olympia", 3, R.RARE, 1], ["m14", 5, R.COMMON, 0], ["cz75", 8, R.RARE, 2], ["m16", 12, R.EPIC, 2],
		["stakeout", 14, R.RARE, 1], ["spectre", 18, R.EPIC, 0], ["python", 20, R.LEGENDARY, 2], ["python", 20, R.RARE, 1],
		["galil", 24, R.EPIC, 0]]
	var legend_uid := ""
	for s: Array in specs:
		var o := OwnedWeapon.create(String(s[0]), int(s[1]), int(s[2]))
		for k in int(s[3]):
			o.parts.append(WeaponPart.create("canon", mini(int(s[1]), 4), {"damage": 0.06}))
		var u := pr.add_weapon(o)
		if s[0] == "python" and s[2] == R.LEGENDARY:
			legend_uid = u
	ProfileStore.save_profile(pr)
	var p := await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await until(func(): return game.hud.get_children().all(func(c): return not c is LoadingScreen), 5.0, "écran de chargement parti")
	await H.clear_zombies(self)
	var lang0 := String(Settings.language)
	var scale0 := Settings.menu_ui_scale
	var pd := game.session.local_data()
	pd.level = 23
	pd.points = 2480
	game.rounds.round_n = 12
	var held := GameWeapon.make("python", 20, R.LEGENDARY, [], "h0")
	held.mag = 6
	held.reserve = 12
	pd.weapons = [held]
	pd.slot = 0
	game.session.sync_inventory(1)
	await frames(3)
	var panel := game.hud.station_panel
	var st := game.station
	# À portée de la station (le serveur vérifie la distance d'une construction).
	p.teleport_to(st.global_position + st.global_basis.z * 1.7 + Vector3.UP * 0.05)
	await frames(3)
	for lang in ["fr", "en"]:
		Settings.language = lang
		panel.open(st)
		await frames(3)
		at.check(panel.selected_uid == legend_uid, "ouverte sur le COUPERET légendaire (%s)" % lang)
		# CONSTRUCTIBLES : niveaux atteints (1 à 20), fenêtre de 8 à 20.
		at.check(panel.rail.visible == 5 and panel.rail.selected_level() == 20 and panel.rail.levels[panel.rail.start] == 8,
				"rail : 5 niveaux de 8 à 20 (%s)" % lang)
		var c := panel.selected_card()
		at.check(c != null and c.art.fx.visible and float(c.art.fx.material.get_shader_parameter("rays_px")) > 0.0,
				"légendaire : halo et rayons (%s)" % lang)
		var common := panel.card_of(_uid(pr, "m14"))
		at.check(common == null or not common.art.fx.visible, "commune : aucun effet")
		var short := BuildRules.owned_price(pr.get_weapon(legend_uid)) - 2480
		at.check(panel.note_label.text == Lang.t("IL MANQUE %s", "%s SHORT") % Hub2Style.num(short), "note : %s" % panel.note_label.text)
		var all_fit := true
		for card in panel.cards:
			all_fit = all_fit and (card as StationDraw.Card).texts_fit()
		at.check(all_fit, "textes des cartes sans débordement (%s)" % lang)
		var d := " ".join(panel.prompts.describe())
		at.check(d.contains(Lang.t("NIVEAU", "LEVEL")) and d.contains(Lang.t("FERMER", "CLOSE")), "invites : %s" % d)
		await seconds(0.5)
		at.check(not game.hud._crosshair.visible and not game.hud._ammo.is_visible_in_tree(), "HUD masqué sous la station (%s)" % lang)
		await at.screenshot(lang)
		if lang == "fr":
			# TOUTES, fenêtre de 12 à 24 (la vue de la maquette).
			panel.set_filter(StationPanel.ALL)
			panel.shift(1)
			await seconds(0.3)
			var g := panel.card_of(_uid(pr, "galil"))
			at.check(g != null and g.data.locked and panel.rail.levels[panel.rail.start] == 12, "TOUTES : BOURRASQUE niv. 24 listée, verrouillée")
			await at.screenshot("fr_all")
			panel.set_filter(StationPanel.BUILDABLE)
			Settings.using_pad = true
			panel.refresh()
			d = " ".join(panel.prompts.describe())
			at.check(d.contains("A " + Lang.t("CONSTRUIRE", "BUILD")) and d.contains(Settings.action_label("reload")), "invites manette : %s" % d)
			await at.screenshot("fr_pad")
			Settings.using_pad = false
			panel.refresh()
		panel.close()
		await frames(2)
		at.check(game.hud._crosshair.visible, "HUD rendu à la fermeture (%s)" % lang)
	# Construction en cours : carte EN COURS, fiche EN CONSTRUCTION · MANCHE N.
	Settings.language = "fr"
	game.rounds.phase = RoundManager.Phase.ACTIVE
	panel.open(st)
	var cheap := _uid(pr, "olympia")
	panel.select_uid(cheap)
	panel.press_build()
	await until(func(): return not st.local_build().is_empty(), 2.0, "construction lancée")
	await frames(2)
	at.check(panel.build_label.begins_with("EN CONSTRUCTION · MANCHE"), "fiche : %s" % panel.build_label)
	await seconds(0.3)
	await at.screenshot("fr_busy")
	panel.select_uid(legend_uid)
	await frames(2)
	at.check(panel.note_label.text == "STATION OCCUPÉE", "autre arme : %s" % panel.note_label.text)
	panel.close()
	# 130 % : rien ne sort de l'écran.
	Settings.menu_ui_scale = 1.3
	panel.open(st)
	panel.select_uid(legend_uid)
	await frames(4)
	var vr := Rect2(Vector2.ZERO, at.get_viewport().get_visible_rect().size).grow(1.0)
	var ok := true
	var boxes: Array = [panel._header, panel.prompts, panel.build_button, panel.refill_button, panel.prev_button, panel.next_button]
	boxes.append_array(panel.chips.values())
	for ctl: Control in boxes:
		if ctl.is_visible_in_tree() and not vr.encloses(ctl.get_global_rect()):
			ok = false
			at.fail("130 %% : %s sort de l'écran (%s)" % [ctl, ctl.get_global_rect()])
	at.check(ok, "130 % : en-tête, filtres, flèches, boutons et invites dans l'écran")
	at.check(panel.rail.visible < 5 and panel.rail.visible >= 2, "130 %% : %d colonnes" % panel.rail.visible)
	var fit := true
	for card in panel.cards:
		fit = fit and (card as StationDraw.Card).texts_fit()
	at.check(fit, "130 % : textes des cartes sans débordement")
	await seconds(0.3)
	await at.screenshot("fr_130")
	# Fiche complète (DÉTAILS) ouverte à 130 % : la fiche défile, le bas
	# (prix, CONSTRUIRE) reste dans l'écran.
	panel.toggle_details()
	await frames(4)
	at.check(panel.details.open, "DÉTAILS ouverte")
	at.check(vr.encloses(panel.build_button.get_global_rect()), "130 %, DÉTAILS ouverte : CONSTRUIRE dans l'écran")
	await seconds(0.3)
	await at.screenshot("fr_130_details")
	panel.toggle_details()
	panel.close()
	Settings.menu_ui_scale = scale0
	Settings.language = lang0
	ProfileStore.reset()


## Uid du premier exemplaire de `id` dans l'arsenal.
func _uid(pr: PlayerProfile, id: String) -> String:
	for o in pr.weapons:
		if o.weapon_id == id:
			return o.uid
	return ""
