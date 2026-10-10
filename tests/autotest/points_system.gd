extends AutotestScenario
## Ferraille (nom interne : points, GAME_CONCEPT §4.8) : 0 au départ, rien
## pour les touches, +50 fixes par élimination (corps, tête ou couteau).
## Créditée par le serveur, affichée dans le HUD sous « FERRAILLE ».

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
	at.check(pd.points == 0, "0 ferraille au départ (%d)" % pd.points)

	var z := await H.dummy_zombie(self, origin + Vector3(6, 0, 0))
	for i in 5:
		H.aim_at(p, z.global_position + Vector3.UP * 0.9)
		await H.shoot(self, p)
	at.check(pd.points == 0, "touches sans élimination : rien (%d)" % pd.points)
	H.aim_at(p, z.global_position + Vector3.UP * 0.9)
	await H.shoot(self, p)
	at.check(pd.points == PointsRules.KILL, "mort au corps : %d (%d)" % [PointsRules.KILL, pd.points])
	await at.screenshot("popups")

	z = await H.dummy_zombie(self, origin + Vector3(5, 0, 0.5))
	for i in 2:
		H.aim_at(p, z.head_position())
		await H.shoot(self, p)
	at.check(pd.points == 2 * PointsRules.KILL, "mort à la tête : même montant fixe (%d)" % pd.points)

	z = await H.dummy_zombie(self, origin + Vector3(1.3, 0, 0))
	H.aim_at(p, z.global_position + Vector3.UP)
	p.input.melee = true
	await until(func(): return pd.points >= 3 * PointsRules.KILL, 2.0, "ferraille du coup de couteau créditée")
	at.check(pd.points == 3 * PointsRules.KILL, "mort au couteau : même montant fixe (%d)" % pd.points)
	at.check(pd.kills == 3 and pd.headshots == 1, "stats : %d tués, %d têtes" % [pd.kills, pd.headshots])
	var label: Label = game.hud._scores._rows.get(1)
	at.check(label != null and label.text == str(3 * PointsRules.KILL), "HUD : %s" % (label.text if label else "absent"))
	var title: Label = game.hud._scores.get_node_or_null("ScrapTitle")
	at.check(title != null and title.text == Lang.t("FERRAILLE", "SCRAP"), "HUD : libellé %s" % (title.text if title else "absent"))
