extends AutotestScenario
## [MP] Hôte : le CLIENT fait une fente au couteau sur un zombie à 2,5 m ; le
## serveur valide le coup depuis la position d'arrivée (répliquée), crédite
## 130 points ; puis, couteau de chasse donné au client, un zombie de manche 10
## meurt d'un seul coup.

const PORT := 17881


func run() -> void:
	timeout_sec = 110
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var cpd := game.session.get_data(client_id)
	var client: Player = game.players[client_id]
	var spot := MapData.cell_to_world(Vector2i(3, 7))
	var ok: bool = await until(func(): return client.global_position.distance_to(spot) < 0.5, 20.0, "client en position")
	if not ok:
		return
	await seconds(1.0)

	# 1. Fente du client (couteau de départ, 150 PV).
	var z := _spawn(game, client.global_position + Vector3(2.5, 0, 0), 150)
	var pts := cpd.points
	ok = await until(func(): return not z.is_alive(), 20.0, "zombie tué au couteau par le client")
	at.check(ok, "fente du client validée par le serveur")
	at.check(cpd.points - pts == 130, "client crédité de 130 points (%d)" % (cpd.points - pts))
	at.check(client.global_position.x - spot.x > 0.8, "la fente du client est répliquée (%.2f m)" % (client.global_position.x - spot.x))

	# 2. Couteau de chasse : zombie de manche 10 tué d'un coup.
	await seconds(1.5)
	cpd.knife = "bowie"
	game.session.sync_inventory(client_id)
	await seconds(3.0)
	var hp := RoundRules.zombie_health(10)
	z = _spawn(game, client.global_position + Vector3(2.5, 0, 0), hp)
	ok = await until(func(): return not z.is_alive() or z.health < hp, 20.0, "coup de couteau de chasse du client")
	at.check(not z.is_alive(), "zombie de manche 10 tué d'un coup (PV restants %d)" % z.health)
	await seconds(4.0)


func _spawn(game: Game, pos: Vector3, hp: int) -> Zombie:
	var zid := game.zombies.spawn(Vector3(pos.x, 0.0, pos.z), 0, hp)
	var z := game.zombies.get_zombie(zid)
	z.speed_mult = 0.0
	return z
