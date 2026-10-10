extends AutotestScenario
## Ferraille (nom interne : points, GAME_CONCEPT §4.8) : 0 au départ, +10 par
## touche de balle ou de couteau (au plus 10 touches payées par zombie), rien
## pour une explosion, +50 fixes par élimination (corps, tête ou couteau ; le
## coup qui tue ne paie pas la touche en plus). Créditée par le serveur,
## affichée dans le HUD sous « FERRAILLE ».

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
	var expected := 5 * PointsRules.HIT
	at.check(pd.points == expected, "5 touches sans élimination : +%d (%d)" % [expected, pd.points])
	H.aim_at(p, z.global_position + Vector3.UP * 0.9)
	await H.shoot(self, p)
	expected += PointsRules.KILL
	at.check(pd.points == expected, "mort au corps : élimination seule (%d / %d)" % [pd.points, expected])
	await at.screenshot("popups")

	z = await H.dummy_zombie(self, origin + Vector3(5, 0, 0.5))
	for i in 2:
		H.aim_at(p, z.head_position())
		await H.shoot(self, p)
	expected += PointsRules.HIT + PointsRules.KILL
	at.check(pd.points == expected, "tête : une touche puis l'élimination, sans bonus (%d / %d)" % [pd.points, expected])

	z = await H.dummy_zombie(self, origin + Vector3(1.3, 0, 0))
	H.aim_at(p, z.global_position + Vector3.UP)
	p.input.melee = true
	expected += PointsRules.KILL
	await until(func(): return pd.kills == 3, 2.0, "zombie tué au couteau")
	at.check(pd.points == expected, "mort au couteau : même montant fixe (%d / %d)" % [pd.points, expected])
	at.check(pd.kills == 3 and pd.headshots == 1, "stats : %d tués, %d têtes" % [pd.kills, pd.headshots])
	var label: Label = game.hud._scores._rows.get(1)
	at.check(label != null and label.text == str(expected), "HUD : %s" % (label.text if label else "absent"))
	var title: Label = game.hud._scores.get_node_or_null("ScrapTitle")
	at.check(title != null and title.text == Lang.t("FERRAILLE", "SCRAP"), "HUD : libellé %s" % (title.text if title else "absent"))

	# Coup de couteau qui ne tue pas : une touche.
	await seconds(0.8)
	p.teleport_to(origin, -PI * 0.5)
	z = await H.dummy_zombie(self, origin + Vector3(1.3, 0, 0), 100000)
	H.aim_at(p, z.global_position + Vector3.UP)
	var before := pd.points
	p.input.melee = true
	await until(func(): return z.health < 100000, 2.0, "coup de couteau porté")
	at.check(pd.points - before == PointsRules.HIT, "touche au couteau : +%d" % (pd.points - before))

	# Explosion qui ne tue pas : rien (elle toucherait toute une horde).
	before = pd.points
	var hp := z.health
	game.combat.explosion(1, z.global_position + Vector3.UP * 0.9, 2.0, 50, 0)
	at.check(z.health < hp and pd.points == before, "explosion sans élimination : rien (%d -> %d PV, +%d)" % [hp, z.health, pd.points - before])

	# Plafond : au plus HIT_CAP touches payées par zombie (une touche de
	# couteau déjà payée sur celui-ci).
	p.teleport_to(origin, -PI * 0.5)
	await frames(2)
	before = pd.points
	for i in PointsRules.HIT_CAP + 2:
		var w: Dictionary = pd.current_weapon()
		w.mag = WeaponDB.stats(w.id).mag
		game.session.sync_inventory(1)
		H.aim_at(p, z.global_position + Vector3.UP * 0.9)
		await H.shoot(self, p)
	at.check(z.paid_hits == PointsRules.HIT_CAP, "touches payées plafonnées (%d)" % z.paid_hits)
	at.check(pd.points - before == (PointsRules.HIT_CAP - 1) * PointsRules.HIT,
			"plafond : +%d pour %d tirs" % [pd.points - before, PointsRules.HIT_CAP + 2])
	# L'élimination paie toujours, plafond atteint ou non.
	before = pd.points
	game.combat.damage_zombie(z.id, z.health + 1, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
	at.check(pd.points - before == PointsRules.KILL, "élimination après le plafond : +%d" % (pd.points - before))
	# Zombie déjà mort : plus aucun coup ne compte.
	before = pd.points
	game.combat.damage_zombie(z.id, 10, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
	at.check(pd.points == before, "tir sur un zombie mort : rien")
