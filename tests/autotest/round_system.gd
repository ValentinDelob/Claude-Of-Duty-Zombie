extends AutotestScenario
## Manches : démarrage, quota de zombies, fin de manche, entracte, manche
## suivante plus dure, respawn des morts.

var H := AutotestHelpers


func kill_all(game: Game) -> void:
	for z: Zombie in game.zombies.alive.duplicate():
		game.combat.damage_zombie(z.id, 99999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)


func run() -> void:
	timeout_sec = 120
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	var rounds := game.rounds
	game.combat.debug_invulnerable = true
	p.teleport_to(MapData.cell_to_world(Vector2i(12, 17), 0.05), 0.0)
	await until(func(): return rounds.round_n == 1, 8.0, "manche 1")
	at.check(rounds.total == 6, "manche 1 : 6 zombies (%d)" % rounds.total)
	at.check(GameState.state == GameState.State.PLAYING, "état PLAYING pendant la manche")
	await seconds(1.0)
	await at.screenshot("round1")
	# On élimine les zombies au fil de leur apparition.
	var t := 0.0
	var max_seen := 0
	while rounds.phase == RoundManager.Phase.ACTIVE and t < 40.0:
		max_seen = maxi(max_seen, game.zombies.alive_count())
		await seconds(0.5)  # scrutation : on laisse les zombies apparaître
		t += 0.5
		if game.zombies.alive_count() > 0:
			var z: Zombie = game.zombies.alive[0]
			if z.max_health != 150:
				at.fail("PV manche 1 = %d au lieu de 150" % z.max_health)
			kill_all(game)
	at.check(rounds.phase == RoundManager.Phase.INTERMISSION, "fin de manche quand tout est mort")
	at.check(GameState.state == GameState.State.ROUND_END, "état ROUND_END pendant l'entracte")
	at.check(game.session.local_data().kills == 6, "6 zombies tués (%d)" % game.session.local_data().kills)
	await until(func(): return rounds.round_n == 2, RoundRules.INTERMISSION + 2.0, "manche 2")
	at.check(rounds.total == 8, "manche 2 : 8 zombies (%d)" % rounds.total)
	await until(func(): return game.zombies.alive_count() > 0, 6.0, "zombie de manche 2")
	at.check(game.zombies.alive[0].max_health == 250, "PV manche 2 = 250")
	# Saut à la manche 12.
	rounds.debug_jump_to(12)
	await until(func(): return game.zombies.alive_count() > 0, 6.0, "zombie de manche 12")
	at.check(game.zombies.alive[0].max_health == RoundRules.zombie_health(12), "PV manche 12 = %d" % RoundRules.zombie_health(12))
	await seconds(0.3)
	await at.screenshot("round12")
