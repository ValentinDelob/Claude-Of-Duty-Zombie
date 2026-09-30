extends AutotestScenario
## [MP] Hôte : voit le CLIENT plonger (état réseau DIVE puis PRONE, pose du
## soldat à plat ventre) et reçoit le signal serveur player_dived_landed.

const PORT := 17883


func run() -> void:
	timeout_sec = 90
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	var host := game.local_player
	host.bot_controlled = true
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var client: Player = game.players[client_id]
	var landings := []
	game.combat.player_dived_landed.connect(func(pid: int, pos: Vector3, h: float): landings.append([pid, pos, h]))
	# Spectateur sur le côté de l'allée du plongeon.
	host.teleport_to(MapData.cell_to_world(Vector2i(6, 12), 0.05), 0.0)
	AutotestHelpers.aim_at(host, MapData.cell_to_world(Vector2i(6, 7), 0.4))
	var spot := MapData.cell_to_world(Vector2i(2, 7))
	var ok: bool = await until(func(): return client.global_position.distance_to(spot) < 0.6, 20.0, "client en position")
	if not ok:
		return
	# Le client ne s'élance qu'une fois vu à son point de départ.
	MpHelpers.signal_peer("depart_vu")
	ok = await until(func(): return client.net_flags() & Player.FLAG_DIVE != 0, 20.0, "plongeon du client vu")
	at.check(ok and client.diving, "l'hôte voit le client plonger")
	await seconds(0.12)
	await at.screenshot("client_dive")
	ok = await until(func(): return client.net_flags() & Player.FLAG_PRONE != 0, 3.0, "client allongé")
	at.check(ok and client.prone, "l'hôte voit le client à plat ventre")
	# Attente bornée plutôt qu'un instant fixe : l'affichage du client (délai
	# d'interpolation en temps réel) décale la pose en temps de jeu accéléré.
	await until(func(): return client.visual._prone_k > 0.8, 3.0, "soldat du client allongé")
	at.check(client.visual._prone_k > 0.8, "soldat du client allongé (%.2f)" % client.visual._prone_k)
	await at.screenshot("client_prone")
	at.check(landings.size() == 1 and landings[0][0] == client_id, "serveur : player_dived_landed du client (%d)" % landings.size())
	if not landings.is_empty():
		at.check(landings[0][1].distance_to(client.global_position) < 1.5, "position d'atterrissage cohérente (%s / client %s)" % [landings[0][1], client.global_position])
	# Le client reste allongé jusqu'ici, puis se relève.
	MpHelpers.signal_peer("allonge_vu")
	ok = await until(func(): return client.net_flags() & Player.FLAG_PRONE == 0, 6.0, "client relevé")
	await until(func(): return client.visual._prone_k < 0.2, 3.0, "soldat du client debout")
	at.check(ok and client.visual._prone_k < 0.2, "le client se relève (%.2f)" % client.visual._prone_k)
	await at.screenshot("client_up")
	await MpHelpers.finish(self)
