extends AutotestScenario
## Points : +10 par touche, +50 mort, +100 tête, +130 couteau. Crédités par le
## serveur, affichés dans le HUD.

var H := AutotestHelpers


func run() -> void:
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var pd := game.session.local_data()
	var origin := MapData.cell_to_world(Vector2i(4, 7), 0.05)
	p.teleport_to(origin, -PI * 0.5)
	at.check(pd.points == 500, "500 points au départ")

	var z := await H.dummy_zombie(self, origin + Vector3(6, 0, 0))
	for i in 6:
		H.aim_at(p, z.global_position + Vector3.UP * 0.9)
		await H.shoot(self, p)
	at.check(pd.points == 600, "5 touches + mort au corps : 600 (%d)" % pd.points)
	await at.screenshot("popups")

	z = await H.dummy_zombie(self, origin + Vector3(5, 0, 0.5))
	for i in 2:
		H.aim_at(p, z.head_position())
		await H.shoot(self, p)
	at.check(pd.points == 710, "tête + mort à la tête : 710 (%d)" % pd.points)

	z = await H.dummy_zombie(self, origin + Vector3(1.3, 0, 0))
	H.aim_at(p, z.global_position + Vector3.UP)
	p.input.melee = true
	await seconds(0.4)
	at.check(pd.points == 840, "mort au couteau : 840 (%d)" % pd.points)
	at.check(pd.kills == 3 and pd.headshots == 1, "stats : %d tués, %d têtes" % [pd.kills, pd.headshots])
	var label: Label = game.hud._scores._rows.get(1)
	at.check(label != null and label.text == "840", "HUD : %s" % (label.text if label else "absent"))
