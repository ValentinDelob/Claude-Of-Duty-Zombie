extends AutotestScenario
## [MP] Hôte : évacuation à deux (GAME_CONCEPT.md §4.5). Vague spéciale
## (manche de chiens forcée) vaincue : la porte s'ouvre chez tout le monde ;
## le CLIENT vote ÉVACUER dans la zone (vote validé ici) : on attend
## l'hôte ; l'hôte vote ÉVACUER dans la zone : toute l'équipe s'évacue,
## fin de partie « évacuation réussie » chez les deux.

const PORT := 17907

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var door := game.evac
	at.check(door != null, "hôte : porte d'évacuation")
	if door == null:
		return
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var client: Player = game.players[client_id]
	# Le client se place lui-même dans la zone de la porte.
	if not await MpHelpers.wait_peer(self, "place", 30.0):
		return
	await until(func(): return door.in_zone(client.srv_origin()), 10.0, "client vu dans la zone")
	await H.clear_zombies(self)
	var dogs := game.rounds.dogs
	dogs.debug_force_next(2)
	game.rounds.paused = false
	game.rounds.debug_jump_to(2)
	if not await until(func(): return dogs.active, 2.0, "vague spéciale lancée"):
		return
	dogs.spawned = dogs.total  # vague vaincue aussitôt
	if not await until(func(): return door.is_open, 3.0, "porte ouverte"):
		return
	MpHelpers.signal_peer("ouverte")
	# Vote du client, validé par le serveur (joueur de la partie, pas mort ; de n'importe où).
	var ok: bool = await until(func(): return int(door.votes.get(client_id, 0)) == EvacRules.Vote.LEAVE, 20.0, "vote ÉVACUER du client")
	at.check(ok, "hôte : vote ÉVACUER du client reçu")
	await seconds(0.5)
	at.check(door.is_open and GameState.state != GameState.State.GAME_OVER, "hôte : un seul vote, on attend l'hôte")
	# L'hôte rejoint la zone et vote ÉVACUER.
	var p := game.local_player
	p.bot_controlled = true
	p.teleport_to(door.global_position + door.global_basis.z * 1.6 + door.global_basis.x * 1.0 + Vector3.UP * 0.05)
	await frames(3)
	p.input.vote = EvacRules.Vote.LEAVE  # F2, de n'importe où
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 3.0, "évacuation")
	at.check(ok and game.last_result.evacuated, "hôte : toute l'équipe évacuée")
	if ok:
		at.check(game.last_result.round_reached == 2, "hôte : manche atteinte %d" % game.last_result.round_reached)
	await MpHelpers.finish(self)
