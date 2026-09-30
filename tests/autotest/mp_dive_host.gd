extends AutotestScenario
## @temps-reel : reste en temps réel (mélange de minuteurs réseau réels et de temps de jeu, à revoir : docs/TESTING_PLAN.md).
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
	ok = await until(func(): return client.net_flags() & Player.FLAG_DIVE != 0, 20.0, "plongeon du client vu")
	at.check(ok and client.diving, "l'hôte voit le client plonger")
	await seconds(0.12)
	await at.screenshot("client_dive")
	ok = await until(func(): return client.net_flags() & Player.FLAG_PRONE != 0, 3.0, "client allongé")
	at.check(ok and client.prone, "l'hôte voit le client à plat ventre")
	await seconds(0.6)
	at.check(client.visual._prone_k > 0.8, "soldat du client allongé (%.2f)" % client.visual._prone_k)
	await at.screenshot("client_prone")
	at.check(landings.size() == 1 and landings[0][0] == client_id, "serveur : player_dived_landed du client (%d)" % landings.size())
	if not landings.is_empty():
		at.check(landings[0][1].distance_to(client.global_position) < 1.5, "position d'atterrissage cohérente")
	ok = await until(func(): return client.net_flags() & Player.FLAG_PRONE == 0, 6.0, "client relevé")
	await seconds(0.8)
	at.check(ok and client.visual._prone_k < 0.2, "le client se relève (%.2f)" % client.visual._prone_k)
	await at.screenshot("client_up")
	await seconds(3.0)
