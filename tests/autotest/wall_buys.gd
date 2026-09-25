extends AutotestScenario
## Achats muraux : arme achetée, 2e emplacement, remplacement de l'arme en
## main quand les emplacements sont pleins, munitions à moitié prix.

var H := AutotestHelpers


func use(p: Player, wb: WallBuy) -> void:
	p.teleport_to(wb.interact_point() + Vector3(0, -1.0, 0) + (wb.interact_point() - wb.global_position).normalized() * 0.6)
	H.aim_at(p, wb.global_position)
	await seconds(0.25)
	p.input.interact_pressed = true
	await seconds(0.4)


func run() -> void:
	timeout_sec = 90
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	var carbine: WallBuy = game.interact.get_obj("wallbuy_R")
	at.check(carbine != null, "achat mural M-14 présent")
	# Vue de la craie.
	p.teleport_to(carbine.interact_point() + Vector3(0, -1.0, 0) - (carbine.global_position - carbine.interact_point()).normalized() * 1.5)
	H.aim_at(p, carbine.global_position)
	await seconds(0.4)
	await at.screenshot("chalk")
	at.check(game.interact.focused == carbine and game.hud._prompt.text.contains("500"), "invite : %s" % game.hud._prompt.text)

	await use(p, carbine)
	at.check(pd.points == 0 and pd.weapons.size() == 2 and pd.current_weapon().id == "carbine", "M-14 achetée (points %d, %d armes)" % [pd.points, pd.weapons.size()])
	await seconds(0.8)
	at.check(p.weapons.current().id == "carbine", "le client tient la M-14")
	await at.screenshot("carbine")

	# Munitions : on tire puis on rachète à 250.
	for i in 3:
		H.aim_at(p, p.global_position + Vector3(0, 1.5, 0) - (carbine.global_position - carbine.interact_point()).normalized() * 5.0)
		await H.shoot(self, p, 0.2)
	game.session.add_points(1, 250)
	await use(p, carbine)
	at.check(pd.points == 0 and pd.current_weapon().mag == 8 and pd.current_weapon().reserve == 96, "munitions rachetées 250 (mag %d, réserve %d)" % [pd.current_weapon().mag, pd.current_weapon().reserve])

	# Emplacements pleins : la KRAKEN remplace l'arme en main.
	game.session.add_points(1, 1000)
	var smg: WallBuy = game.interact.get_obj("wallbuy_U")
	game.doors["2"].srv_open()
	await use(p, smg)
	at.check(pd.weapons.size() == 2 and pd.has_weapon("smg") >= 0 and pd.has_weapon("carbine") < 0, "la KRAKEN-9 remplace l'arme en main")
	at.check(pd.has_weapon("pistol") >= 0, "le pistolet est conservé")

	# Trop pauvre.
	pd.points = 100
	var shotgun: WallBuy = game.interact.get_obj("wallbuy_V")
	game.doors["1"].srv_open()
	await use(p, shotgun)
	at.check(pd.has_weapon("shotgun") < 0 and pd.points == 100, "BRUTE-12 refusé (100 points)")
