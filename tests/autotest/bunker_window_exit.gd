extends AutotestScenario
## @couvre scripts/game/barricades/barricade.gd
## Fenêtre ouverte, joueur un moment hors d'atteinte (à terre, téléporteur) :
## les zombies entrés attendent devant la fenêtre et les suivants n'enjambent
## pas tant que la sortie est occupée ; ensuite tous repartent. Trouvé par le
## soak (BUNKER K-7, fenêtre sud du générateur) : chaque enjambement posait le
## zombie dans celui qui attendait, la file tassée entre le générateur et la
## fenêtre, alignée sur x = 58,5, ne pouvait plus bouger.

var H := AutotestHelpers
const COUNT := 8


func run() -> void:
	timeout_sec = 120
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	for id in game.doors:
		game.doors[id].srv_open()
	await H.clear_zombies(self)
	var w: Barricade = null
	for b in game.barricades.windows:
		if b.cell == Vector2i(58, 30):
			w = b
	at.check(w != null, "fenêtre sud du générateur (58, 30)")
	if w == null:
		return
	w.srv_set_mask(0)
	p.teleport_to(Vector3(9.5, 0.05, 15.5))  # dortoir : loin, chemin vers l'ouest
	await seconds(0.5)
	p.untargetable = true
	var spawn := MapData.cell_to_world(w.spawn_cells[0])
	var zs: Array[Zombie] = []
	for i in COUNT:
		zs.append(game.zombies.get_zombie(game.zombies.spawn(spawn + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), [RoundRules.WALK, RoundRules.SPRINT][i % 2], 100000)))
		await seconds(0.3)  # arrivées échelonnées
	await seconds(10.0)  # le temps d'enjamber pour ceux qui le peuvent
	# Dedans, aucun zombie posé dans un autre.
	var inside := zs.filter(func(z: Zombie): return w.is_inside(z.global_position))
	var closest := INF
	for i in inside.size():
		for j in range(i + 1, inside.size()):
			closest = minf(closest, Barricade._flat_dist(inside[i].global_position, inside[j].global_position))
	at.check(closest > 2.0 * Zombie.RADIUS - 0.1, "%d zombie(s) entré(s), aucun dans un autre (écart mini %.2f m)" % [inside.size(), closest])
	p.untargetable = false
	var p0 := {}
	for z in zs:
		p0[z.id] = z.global_position
	var left := func() -> int:
		var n := 0
		for z in zs:
			if z.state == Zombie.State.CHASE and w.is_inside(z.global_position) and z.global_position.distance_to(p0[z.id]) > 2.0:
				n += 1
		return n
	var ok: bool = await until(func(): return left.call() == COUNT, 30.0, "les %d zombies repartent de la fenêtre" % COUNT)
	if ok:
		at.check(true, "les %d zombies sont repartis de la fenêtre" % COUNT)
	await H.clear_zombies(self)
