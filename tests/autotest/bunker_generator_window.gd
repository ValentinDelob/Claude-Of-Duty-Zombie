extends AutotestScenario
## @couvre scripts/game/map/maps/bunker_k7.gd
## BUNKER K-7, salle du générateur : une horde qui entre par la fenêtre sud
## (case 58,30) rejoint le joueur acculé dans l'angle sud-est. Trouvé par le
## soak : une caisse posée juste à droite de la sortie de la fenêtre ne
## laissait qu'un passage d'une capsule entre elle et le mur ; les zombies s'y
## mettaient en file et ceux qui sortaient de la fenêtre restaient plantés en
## colonne entre le générateur et la fenêtre.

var H := AutotestHelpers
const COUNT := 14


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
	p.teleport_to(Vector3(62.5, 0.05, 29.5))
	await seconds(0.5)
	var spawn := MapData.cell_to_world(w.spawn_cells[0])
	var zs: Array[Zombie] = []
	for i in COUNT:
		zs.append(game.zombies.get_zombie(game.zombies.spawn(spawn + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), i % 4, 100000)))
		await seconds(0.4)  # arrivées échelonnées, comme une manche
	# Comme le soak : immobile (< 0,6 m) 12 s à plus de 4 m du joueur = coincé.
	var track := {}
	var stuck := []
	var t0 := GameClock.now()
	var near := func() -> int:
		var n := 0
		for z in zs:
			if is_instance_valid(z) and z.global_position.distance_to(p.global_position) < 3.0:
				n += 1
		return n
	while GameClock.now() - t0 < 40.0 and near.call() < COUNT:
		for z in zs:
			if z.state != Zombie.State.CHASE or z.global_position.distance_to(p.global_position) < 4.0:
				track.erase(z.id)
				continue
			var tr: Array = track.get(z.id, [])
			if tr.is_empty() or (tr[0] as Vector3).distance_to(z.global_position) > 0.6:
				track[z.id] = [z.global_position, GameClock.now()]
			elif GameClock.now() - float(tr[1]) > 12.0 and not stuck.has(z.id):
				stuck.append(z.id)
				print("[autotest] zombie %d coincé en %s" % [z.id, z.global_position])
		await frames(1)
	at.check(stuck.is_empty(), "aucun zombie planté à la sortie de la fenêtre (%d)" % stuck.size())
	at.check(near.call() == COUNT, "%d/%d zombies autour du joueur en %.1f s" % [near.call(), COUNT, GameClock.now() - t0])
	await H.clear_zombies(self)
