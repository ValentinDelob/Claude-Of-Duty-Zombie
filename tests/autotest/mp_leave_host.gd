extends AutotestScenario
## [MP] Hôte : un client quitte en pleine partie ; la partie continue.

const PORT := 17816


func run() -> void:
	timeout_sec = 90
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.combat.debug_invulnerable = true
	var ok: bool = await until(func(): return game.players.size() == 1, 30.0, "départ du client")
	at.check(ok and game.session.data.size() == 1, "le joueur parti est retiré (joueurs et données)")
	await seconds(1.0)  # la partie tourne une seconde sans le client
	at.check(GameState.state in [GameState.State.PLAYING, GameState.State.ROUND_END], "la partie continue pour l'hôte")
	await until(func(): return game.rounds.round_n >= 1, 8.0, "manche 1")
	at.check(game.rounds.round_n >= 1, "les manches continuent")
	await MpHelpers.finish(self)
