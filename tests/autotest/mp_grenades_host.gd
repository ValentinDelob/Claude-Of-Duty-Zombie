extends AutotestScenario
## [MP] Hôte : c'est le CLIENT qui lance. Le serveur décompte sa réserve,
## simule la grenade (objet serveur appartenant au client), applique
## l'explosion (3 zombies tués, 50 points chacun au client), puis simule le
## SINGE-TAMBOUR du client qui attire les zombies avant d'exploser.

const PORT := 17881

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	var sys := game.throwables
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var client: Player = game.players[client_id]
	var cpd := game.session.get_data(client_id)
	var booms := []
	sys.exploded.connect(func(kind, pos, pid): booms.append([kind, pos, pid]))
	var ok: bool = await until(func(): return client.global_position.distance_to(MapData.cell_to_world(Vector2i(4, 7))) < 1.0, 20.0, "client en position")
	if not ok:
		return
	# 1. Grenade du client : 3 zombies immobiles (sortis de terre ensemble).
	var zs := []
	for k in 3:
		var zid := game.zombies.spawn(MapData.cell_to_world(Vector2i(12, 7)) + Vector3(0, 0, (k - 1) * 0.75), 0, 900)
		var z := game.zombies.get_zombie(zid)
		z.speed_mult = 0.0
		zs.append(z)
	await until(func(): return zs.all(func(z): return z.state != Zombie.State.EMERGE), Zombie.EMERGE_TIME + 3.0, "zombies sortis de terre")
	var points0 := cpd.points
	ok = await until(func(): return not sys.items.is_empty(), 25.0, "grenade du client simulée par le serveur")
	if not ok:
		return
	var t: Throwable = sys.items.values()[0]
	at.check(t.server_side and t.owner_pid == client_id and t.kind == ThrowableRules.Kind.FRAG, "objet serveur : grenade du client %d" % t.owner_pid)
	at.check(cpd.grenades == 1, "réserve du client décomptée par le serveur (%d)" % cpd.grenades)
	ok = await until(func(): return booms.size() >= 1, 6.0, "explosion")
	await until(func(): return zs.all(func(z): return not z.is_alive()), 1.0, "zombies tués par l'explosion")
	var dead := 0
	for z: Zombie in zs:
		if not z.is_alive():
			dead += 1
	at.check(ok and booms[0][2] == client_id and dead == 3, "explosion du client : %d/3 zombies tués" % dead)
	at.check(cpd.points - points0 == 3 * PointsRules.SPLASH_KILL, "50 points par kill au client (+%d)" % (cpd.points - points0))
	await at.screenshot("frag")
	await H.clear_zombies(self)

	# 2. SINGE-TAMBOUR du client : les zombies convergent.
	sys.srv_give_monkeys(client_id)
	var runners := []
	for c in [Vector2i(22, 2), Vector2i(23, 12)]:
		runners.append(game.zombies.get_zombie(game.zombies.spawn(MapData.cell_to_world(c), 1, 150)))
	ok = await until(func(): return sys.lure_count() == 1, 25.0, "singe du client posé")
	if not ok:
		return
	var mpos: Vector3 = sys._lures[0].position
	var lured_count := func() -> int:
		var n := 0
		for z: Zombie in runners:
			if z.is_alive() and z.lured and Vector2(z.global_position.x - mpos.x, z.global_position.z - mpos.z).length() < 4.0:
				n += 1
		return n
	# Les trotteurs rejoignent le singe en moins de 4 s de jeu.
	var t0 := GameClock.now()
	await until(func(): return lured_count.call() == runners.size(), 4.0, "zombies au pied du singe")
	var lured: int = lured_count.call()
	var took := GameClock.now() - t0
	at.check(lured == runners.size() and took <= 4.0, "zombies attirés par le singe du client (%d/%d en %.1f s)" % [lured, runners.size(), took])
	ok = await until(func(): return booms.size() >= 2, ThrowableRules.MONKEY_TIME, "explosion du singe")
	at.check(ok and booms[1][0] == ThrowableRules.Kind.MONKEY, "explosion du singe")
	await MpHelpers.finish(self)
