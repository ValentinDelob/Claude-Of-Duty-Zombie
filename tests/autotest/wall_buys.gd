extends AutotestScenario
## Achats muraux (arsenal de Kino der Toten) : contours à la craie, arme achetée,
## 2e emplacement, remplacement de l'arme en main quand les emplacements sont
## pleins, munitions à moitié prix (4500 pour une arme améliorée).

var H := AutotestHelpers


func use(p: Player, wb: WallBuy) -> void:
	p.teleport_to(wb.interact_point() + Vector3(0, -1.0, 0) + (wb.interact_point() - wb.global_position).normalized() * 0.6)
	H.aim_at(p, wb.global_position)
	await seconds(0.25)
	p.input.interact_pressed = true
	await seconds(0.4)


## Se place face au dessin à la craie, un peu en retrait.
func look_at_chalk(p: Player, wb: WallBuy) -> void:
	p.teleport_to(wb.interact_point() + Vector3(0, -1.0, 0) - (wb.global_position - wb.interact_point()).normalized() * 1.5)
	H.aim_at(p, wb.global_position)
	await seconds(0.4)


func run() -> void:
	timeout_sec = 120
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()

	# Tous les achats muraux de la carte : arme connue, prix BO1, craie.
	var expected := {"A": ["olympia", 500], "R": ["m14", 500], "U": ["mp5k", 1000], "V": ["stakeout", 1500],
		"+": ["mp40", 1000], "B": ["pm63", 1000], "!": ["mpl", 1000], "$": ["ak74u", 1200], "&": ["m16", 1200]}
	for marker in expected:
		var wb: WallBuy = game.interact.get_obj("wallbuy_" + marker)
		at.check(wb != null and wb.weapon_id == expected[marker][0] and wb.cost == expected[marker][1],
			"achat mural %s : %s %d" % [marker, wb.weapon_id if wb else "?", wb.cost if wb else 0])
		at.check(wb != null and wb.get_node_or_null("Chalk") != null, "contour à la craie %s" % marker)
	for id in game.doors:
		game.doors[id].srv_open()
	await seconds(0.3)
	for marker in ["A", "U", "$", "&"]:
		await look_at_chalk(p, game.interact.get_obj("wallbuy_" + marker))
		await at.screenshot("chalk_%s" % expected[marker][0])

	var m14: WallBuy = game.interact.get_obj("wallbuy_R")
	await look_at_chalk(p, m14)
	await at.screenshot("chalk")
	at.check(game.interact.focused == m14 and game.hud._prompt.text.contains("500"), "invite : %s" % game.hud._prompt.text)

	await use(p, m14)
	at.check(pd.points == 0 and pd.weapons.size() == 2 and pd.current_weapon().id == "m14", "M14 achetée (points %d, %d armes)" % [pd.points, pd.weapons.size()])
	await seconds(0.8)
	at.check(p.weapons.current().id == "m14", "le client tient la M14")
	await at.screenshot("m14")

	# Munitions : on tire puis on rachète à 250.
	for i in 3:
		H.aim_at(p, p.global_position + Vector3(0, 1.5, 0) - (m14.global_position - m14.interact_point()).normalized() * 5.0)
		await H.shoot(self, p, 0.2)
	game.session.add_points(1, 250)
	await use(p, m14)
	at.check(pd.points == 0 and pd.current_weapon().mag == 8 and pd.current_weapon().reserve == 96, "munitions rachetées 250 (mag %d, réserve %d)" % [pd.current_weapon().mag, pd.current_weapon().reserve])

	# Arme améliorée : munitions au mur à 4500.
	pd.weapons[pd.slot] = WeaponDB.new_instance("m14", true)
	pd.current_weapon().mag = 3
	game.session.sync_inventory(1)
	await seconds(0.3)
	p.teleport_to(m14.interact_point() + Vector3(0, -1.0, 0) + (m14.interact_point() - m14.global_position).normalized() * 0.6)
	H.aim_at(p, m14.global_position)
	await seconds(0.3)
	at.check(game.hud._prompt.text.contains("4500"), "munitions d'une arme améliorée : %s" % game.hud._prompt.text)
	game.session.add_points(1, 4500)
	await use(p, m14)
	at.check(pd.points == 0 and pd.current_weapon().mag == 15 and pd.current_weapon().pap, "munitions améliorées rachetées 4500 (mag %d)" % pd.current_weapon().mag)

	# Emplacements pleins : la MP5K remplace l'arme en main.
	game.session.add_points(1, 1000)
	var mp5k: WallBuy = game.interact.get_obj("wallbuy_U")
	await use(p, mp5k)
	at.check(pd.weapons.size() == 2 and pd.has_weapon("mp5k") >= 0 and pd.has_weapon("m14") < 0, "la MP5K remplace l'arme en main")
	at.check(pd.has_weapon("m1911") >= 0, "le M1911 est conservé")

	# Trop pauvre.
	pd.points = 100
	var stakeout: WallBuy = game.interact.get_obj("wallbuy_V")
	await use(p, stakeout)
	at.check(pd.has_weapon("stakeout") < 0 and pd.points == 100, "STAKEOUT refusé (100 points)")

	# Olympia de la salle de départ.
	game.session.add_points(1, 400)
	await use(p, game.interact.get_obj("wallbuy_A"))
	at.check(pd.has_weapon("olympia") >= 0 and pd.points == 0, "OLYMPIA achetée 500")
