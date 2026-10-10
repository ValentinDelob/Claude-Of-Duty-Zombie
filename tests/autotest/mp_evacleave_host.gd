extends AutotestScenario
## [MP] Hôte : client parti pendant la fenêtre d'évacuation (GAME_CONCEPT.md
## §4.5). Le client vote « partir » puis sort de la zone ; l'hôte vote
## « partir » dans la zone : il attend le client. Le client quitte la partie :
## son vote est oublié et l'hôte, seul restant, s'évacue aussitôt (personne
## n'attend un absent).

const PORT := 17935

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var door := game.evac
	if door == null:
		at.fail("porte d'évacuation absente")
		return
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	var client: Player = game.players[cid]
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
	dogs.spawned = dogs.total
	if not await until(func(): return door.is_open, 3.0, "porte ouverte"):
		return
	MpHelpers.signal_peer("ouverte")
	if not await MpHelpers.wait_peer(self, "sorti", 30.0):
		return
	var ok: bool = await until(func(): return int(door.votes.get(cid, 0)) == EvacRules.Vote.LEAVE and not door.in_zone(client.srv_origin()), 5.0, "client : « partir » puis hors de la zone")
	at.check(ok, "hôte : le client a voté « partir » puis est sorti de la zone")
	var p := game.local_player
	p.bot_controlled = true
	p.teleport_to(door.global_position + door.global_basis.z * 1.6 + Vector3.UP * 0.05)
	await frames(3)
	H.aim_at(p, door.interact_point())
	await until(func(): return game.interact.focused == door, 2.0, "hôte : porte visée")
	p.input.interact_pressed = true
	await until(func(): return int(door.votes.get(1, 0)) == EvacRules.Vote.LEAVE, 2.0, "vote de l'hôte")
	await seconds(1.0)
	at.check(door.is_open and GameState.state != GameState.State.GAME_OVER, "hôte : client hors de la zone, on l'attend")
	MpHelpers.signal_peer("attente")
	ok = await until(func(): return not game.players.has(cid), 15.0, "client parti")
	at.check(ok, "hôte : client parti pendant la fenêtre")
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 3.0, "évacuation")
	at.check(ok and game.last_result.evacuated, "hôte seul restant : évacuation sans attendre l'absent")
	at.check(not door.votes.has(cid), "hôte : vote de l'absent oublié")
	await MpHelpers.finish(self)
