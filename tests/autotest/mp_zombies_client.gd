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
	var targets: Array = game.zombies.alive.duplicate()
	await until(func(): return targets.all(func(z): return z.state != Zombie.State.EMERGE), Zombie.EMERGE_TIME + 3.0, "zombies sortis de terre")
	await seconds(0.3)  # fin du redressement (animation)
	await at.screenshot("zombies")
	var t := 0.0
	# Seulement les 3 cibles : le 4e zombie (envoyé ensuite par l'hôte) doit
	# pouvoir frapper le client.
	while game.zombies.alive_count() > 0 and pd.kills < 3 and t < 30.0:
		var z: Zombie = game.zombies.alive[0]
		AutotestHelpers.aim_at(p, z.head_position())
		await AutotestHelpers.shoot(self, p, 0.2)
		if p.weapons.current().mag == 0:
			# Rechargement automatique.
			await until(func(): return p.weapons.current().mag > 0, 4.0, "rechargement")
		t += 0.25
	await until(func(): return pd.kills == 3 and pd.points > 500, 3.0, "kills et points reçus du serveur")
	at.check(pd.kills == 3, "zombies abattus côté client")
	at.check(pd.points > 500 and pd.kills == 3, "points reçus du serveur : %d (tués %d)" % [pd.points, pd.kills])
	MpHelpers.signal_peer("points_vus")
	ok = await until(func(): return pd.health < pd.max_health, 20.0, "coup reçu")
	at.check(ok, "santé répliquée après un coup de zombie (%d PV)" % pd.health)
	await at.screenshot("hurt")
	await MpHelpers.finish(self)
