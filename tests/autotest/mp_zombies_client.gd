extends AutotestScenario
## [MP] Client : voit les zombies du serveur (marionnettes interpolées), les
## abat, reçoit ses points, subit les coups.

const PORT := 17813


func run() -> void:
	timeout_sec = 110
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	var ok: bool = await until(func(): return game.zombies.alive_count() >= 3, 30.0, "zombies reçus")
	if not ok:
		return
	at.check(not game.zombies.alive[0].server_side, "zombies = marionnettes côté client")
	await seconds(Zombie.EMERGE_TIME + 0.6)
	await at.screenshot("zombies")
	var t := 0.0
	while game.zombies.alive_count() > 0 and t < 30.0:
		var z: Zombie = game.zombies.alive[0]
		AutotestHelpers.aim_at(p, z.head_position())
		await AutotestHelpers.shoot(self, p, 0.2)
		if p.weapons.current().mag == 0:
			await seconds(1.8)
		t += 0.25
	at.check(game.zombies.alive_count() == 0, "zombies abattus côté client")
	await seconds(0.5)
	at.check(pd.points > 500 and pd.kills == 3, "points reçus du serveur : %d (tués %d)" % [pd.points, pd.kills])
	ok = await until(func(): return pd.health < pd.max_health, 20.0, "coup reçu")
	at.check(ok, "santé répliquée après un coup de zombie (%d PV)" % pd.health)
	await seconds(0.3)
	await at.screenshot("hurt")
	await seconds(4.0)
