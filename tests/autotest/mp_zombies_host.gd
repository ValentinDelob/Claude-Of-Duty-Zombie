extends AutotestScenario
## [MP] Hôte : fait apparaître des zombies devant le client ; vérifie que les
## tirs du CLIENT (validés ici) les tuent et lui rapportent des points, puis
## qu'un zombie blesse bien le client.

const PORT := 17813


func run() -> void:
	timeout_sec = 110
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var cpd := game.session.get_data(client_id)
	var client: Player = game.players[client_id]
	# Le client se place en (3,7) face à l'est ; 3 zombies immobiles à 6 m.
	var ok: bool = await until(func(): return client.global_position.distance_to(MapData.cell_to_world(Vector2i(3, 7))) < 1.0, 15.0, "client en position")
	if not ok:
		return
	var zs := []
	for k in 3:
		var zid := game.zombies.spawn(MapData.cell_to_world(Vector2i(9, 6 + k)), 0, 150)
		var z := game.zombies.get_zombie(zid)
		z.speed_mult = 0.0
		zs.append(z)
	ok = await until(func():
		for z in zs:
			if z.is_alive():
				return false
		return true, 40.0, "zombies tués par le client")
	at.check(ok, "les 3 zombies ont été tués par les tirs du client (validés par l'hôte)")
	at.check(cpd.kills == 3 and cpd.points >= 3 * PointsRules.KILL, "le serveur crédite le client : %d tués, %d points" % [cpd.kills, cpd.points])
	# Un zombie va attaquer le client (une fois ses points vérifiés chez lui).
	if not await MpHelpers.wait_peer(self, "points_vus", 15.0):
		return
	var hp := cpd.health
	var zid2 := game.zombies.spawn(client.global_position + Vector3(2.5, 0, 0), 1, 150)
	ok = await until(func(): return cpd.health < hp, 12.0, "client frappé")
	at.check(ok, "un zombie serveur blesse le client (%d -> %d PV)" % [hp, cpd.health])
	game.zombies.despawn(zid2)
	await MpHelpers.finish(self)
