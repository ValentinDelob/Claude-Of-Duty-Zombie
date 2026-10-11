extends AutotestScenario
## [MP] Hôte : le CLIENT fait une fente au couteau sur un zombie à 2,5 m ; le
## serveur valide le coup depuis la position d'arrivée (répliquée), crédite
## ferraille d'un kill ; puis une seconde fente (couteau de chasse supprimé :
## lot C).

const PORT := 17885


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

	# 1. Fente du client (couteau de départ, 150 PV).
	var z := _spawn(game, client.global_position + Vector3(2.5, 0, 0), 150)
	var pts := cpd.points
	ok = await until(func(): return not z.is_alive(), 20.0, "zombie tué au couteau par le client")
	at.check(ok, "fente du client validée par le serveur")
	await until(func(): return cpd.points - pts >= PointsRules.KILL, 2.0, "points de la fente")
	at.check(cpd.points - pts == PointsRules.KILL, "client crédité de la ferraille du kill (%d)" % (cpd.points - pts))
	# La marionnette du client est interpolée avec un léger retard : on attend
	# que la position d'arrivée de la fente soit répliquée.
	await until(func(): return client.global_position.x - spot.x > 0.8, 2.0, "fente répliquée")
	at.check(client.global_position.x - spot.x > 0.8, "la fente du client est répliquée (%.2f m)" % (client.global_position.x - spot.x))

	# 2. Seconde fente, depuis sa place de départ.
	if not await MpHelpers.wait_peer(self, "retour", 20.0):
		return
	if not await until(func(): return client.global_position.distance_to(spot) < 0.5, 5.0, "client revenu en position"):
		return
	z = _spawn(game, client.global_position + Vector3(2.5, 0, 0), 150)
	ok = await until(func(): return not z.is_alive(), 20.0, "second zombie tué au couteau")
	at.check(ok, "seconde fente du client validée")

	# 3. Batte de baseball (arme de base de corps à corps tenue en main) : le
	# coup du client est validé par le serveur (Combat.srv_swing), aux dégâts
	# de la batte.
	if not await MpHelpers.wait_peer(self, "pret_batte", 20.0):
		return
	if not await until(func(): return client.global_position.distance_to(spot) < 0.5, 5.0, "client revenu en position (batte)"):
		return
	cpd.weapons = [WeaponDB.new_instance("bat")]
	cpd.slot = 0
	game.session.sync_inventory(client_id)
	z = _spawn(game, client.global_position + Vector3(1.5, 0, 0), 1000)
	MpHelpers.signal_peer("batte")
	ok = await until(func(): return z.health < 1000, 20.0, "coup de batte du client")
	var bat_dmg := int(WeaponDB.stats("bat").damage)
	at.check(ok and z.health == 1000 - bat_dmg, "coup de batte du client validé par le serveur (1000 -> %d)" % z.health)
	await MpHelpers.finish(self)


func _spawn(game: Game, pos: Vector3, hp: int) -> Zombie:
	var zid := game.zombies.spawn(Vector3(pos.x, 0.0, pos.z), 0, hp)
	var z := game.zombies.get_zombie(zid)
	z.speed_mult = 0.0
	return z
