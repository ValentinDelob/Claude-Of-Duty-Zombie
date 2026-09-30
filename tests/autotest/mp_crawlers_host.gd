extends AutotestScenario
## [MP] Hôte : une explosion non mortelle fait un RAMPANT (décision serveur,
## RPC fiable), qui se traîne vers le client ; le client le vise à la tête sur
## SA marionnette couchée et le tue (touche validée par le serveur). Puis une
## explosion mortelle déchiquette un corps.

const PORT := 17893

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	ZombieGibs.debug_chance = 1.0
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var client: Player = game.players[client_id]
	var ok: bool = await until(func(): return client.global_position.distance_to(MapData.cell_to_world(Vector2i(4, 7))) < 1.0, 20.0, "client en position")
	if not ok:
		return
	var kills := []
	game.combat.zombie_damaged.connect(func(pid, zid, _d, killed, head, _k):
		if killed:
			kills.append([pid, zid, head]))

	# 1. Explosion non mortelle : rampant (une fois le zombie reçu par le client).
	var z := await H.dummy_zombie(self, MapData.cell_to_world(Vector2i(11, 7)), 4000)
	if not await MpHelpers.wait_peer(self, "zombie_1", 20.0):
		return
	game.combat.explosion(1, z.global_position + Vector3(0, 0.2, 0.8), 3.0, 800, 0)
	await until(func(): return z.is_crawler(), 1.0, "rampant")
	at.check(z.is_crawler() and (z.gibs & ZombieGibs.LEGS) != 0, "serveur : rampant (masque %d)" % z.gibs)
	z.health = 60
	z.speed_mult = 1.0
	await at.screenshot("crawler")

	# 2. Le client le tue d'un tir à la tête.
	ok = await until(func(): return not z.is_alive(), 30.0, "rampant tué par le client")
	at.check(ok and not kills.is_empty() and kills[0][0] == client_id and kills[0][1] == z.id and kills[0][2], "tir à la tête du client validé sur le rampant")

	# 3. Explosion mortelle : corps déchiqueté (vu par le client).
	var z2 := await H.dummy_zombie(self, MapData.cell_to_world(Vector2i(10, 9)), 300)
	if not await MpHelpers.wait_peer(self, "zombie_2", 20.0):
		return
	game.combat.explosion(1, z2.global_position + Vector3(0, 0.2, 0.5), 3.0, 1000, 0)
	await until(func(): return not z2.is_alive(), 1.0, "corps déchiqueté")
	at.check(not z2.is_alive() and z2.gibs != 0, "serveur : corps déchiqueté (masque %d)" % z2.gibs)
	await MpHelpers.finish(self)
