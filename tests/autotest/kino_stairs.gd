extends AutotestScenario
## @carte kino
## @couvre scripts/game/zombies/zombie.gd
## KINO : un zombie qui MARCHE descend l'escalier du hall (palier du haut,
## x = 75) jusqu'au joueur resté en bas, et le monte jusqu'au joueur à
## l'étage. Trouvé par le soak (long_soak_kino) : chaque chemin recalculé en
## haut (ou au pied) des marches repartait du bord du palier, derrière le
## zombie ; il faisait demi-tour toutes les demi-secondes et restait bloqué
## (manche qui ne finissait pas). Les coureurs, plus rapides que le
## recalcul, passaient.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var p: Player = await H.start_solo_game(self, "kino")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	for id in game.doors:
		game.doors[id].srv_open()
	await H.clear_zombies(self)
	# Descente : joueur sur le disque du hall, zombies sur le palier du haut.
	await walk_to(p, Vector3(76.245, -0.1, 70.896), [Vector3(75.0, 2.1, 88.5), Vector3(79.3, 2.1, 89.9)], "descendu du palier", 20.0)
	# Montée : joueur à l'étage (zone b), zombies au pied des marches.
	await walk_to(p, Vector3(54.77, 2.1, 81.42), [Vector3(75.05, 0.0, 76.5), Vector3(76.0, 0.0, 72.0)], "monté depuis le pied des marches", 35.0)


func walk_to(p: Player, stand: Vector3, starts: Array, what: String, limit: float) -> void:
	var game := Game.instance
	p.teleport_to(stand)
	await seconds(0.5)
	for start: Vector3 in starts:
		var z := game.zombies.get_zombie(game.zombies.spawn(start, RoundRules.WALK, 100000))
		await H.emerged(self, [z])
		var t0 := GameClock.now()
		var ok: bool = await until(func(): return z.global_position.distance_to(p.global_position) < 2.5, limit, "zombie %s (%s)" % [what, start])
		if ok:
			at.check(true, "zombie qui marche %s (%s) en %.1f s" % [what, start, GameClock.now() - t0])
		await H.clear_zombies(self)
