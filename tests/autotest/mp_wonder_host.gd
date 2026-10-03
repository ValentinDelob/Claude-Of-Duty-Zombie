extends AutotestScenario
## [MP] Hôte : donne le TONNERRE-7 au CLIENT, fait apparaître 4 zombies de
## manche 30 devant lui. C'est le serveur qui calcule le cône du tir du
## client : les 4 zombies sont tués et projetés, 50 points chacun au client,
## et l'arme n'est plus proposée par la boîte.

const PORT := 17891

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var client: Player = game.players[client_id]
	var cpd := game.session.get_data(client_id)
	var start := MapData.cell_to_world(Vector2i(4, 7))
	var ok: bool = await until(func(): return client.global_position.distance_to(start) < 1.0, 20.0, "client en position")
	if not ok:
		return
	WeaponDB.give(cpd, "thunder")
	game.session.sync_inventory(client_id)
	at.check(MysteryBox.wonders_taken(game).has("thunder"), "TONNERRE-7 du client exclu de la boîte")
	var hp := RoundRules.zombie_health(30)
	var zs := []
	for off in [Vector3(3, 0, 0), Vector3(6, 0, -1), Vector3(9, 0, 1), Vector3(13, 0, 0)]:
		var z := game.zombies.get_zombie(game.zombies.spawn(start + off, 0, hp))
		z.speed_mult = 0.0
		zs.append(z)
	var points0 := cpd.points
	ok = await until(func():
		for z: Zombie in zs:
			if z.is_alive():
				return false
		return true, 25.0, "zombies tués par le tir du client")
	var flung := 0
	for z: Zombie in zs:
		if z.is_flung():
			flung += 1
	at.check(ok and flung == 4, "serveur : %d/4 zombies de manche 30 tués et projetés" % flung)
	await until(func(): return cpd.points - points0 >= 4 * PointsRules.KILL, 1.0, "points du client")
	at.check(cpd.points - points0 == 4 * PointsRules.KILL, "50 points par kill au client (+%d)" % (cpd.points - points0))
	at.check(cpd.current_weapon().id == "thunder" and cpd.current_weapon().mag == 1, "munition décomptée par le serveur (%d)" % cpd.current_weapon().mag)
	await at.screenshot("host")
	await MpHelpers.finish(self)
