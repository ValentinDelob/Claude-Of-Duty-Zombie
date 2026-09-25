extends AutotestScenario
## Navigation : les zombies contournent les murs, trouvent les passages et ne
## restent pas coincés en groupe.

var game: Game
var p: Player


func clear_zombies() -> void:
	for zid in game.zombies.zombies.keys():
		game.zombies.despawn(zid)
	await frames(2)


func reach_test(player_cell: Vector2i, zombie_cell: Vector2i, limit: float, label: String) -> void:
	await clear_zombies()
	p.teleport_to(MapData.cell_to_world(player_cell, 0.05))
	var zid := game.zombies.spawn(MapData.cell_to_world(zombie_cell), 2, 150)
	var z := game.zombies.get_zombie(zid)
	var t0 := Time.get_ticks_msec()
	var ok: bool = await until(func(): return z.global_position.distance_to(p.global_position) < 1.6, limit, label)
	if ok:
		at.check(true, "%s (%.1f s)" % [label, (Time.get_ticks_msec() - t0) / 1000.0])


func run() -> void:
	p = await AutotestHelpers.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.debug_spawning = false
	await reach_test(Vector2i(16, 11), Vector2i(16, 7), 14.0, "contourne la salle fermée jusqu'à son entrée")
	await reach_test(Vector2i(12, 17), Vector2i(2, 1), 16.0, "traverse l'arène jusqu'à la petite salle")

	# Foule : 14 zombies de partout vers le joueur.
	await clear_zombies()
	p.teleport_to(MapData.cell_to_world(Vector2i(12, 17), 0.05))
	var spots := [Vector2i(1, 1), Vector2i(24, 1), Vector2i(1, 14), Vector2i(24, 14), Vector2i(12, 3), Vector2i(20, 8), Vector2i(5, 10)]
	for i in 14:
		game.zombies.spawn(MapData.cell_to_world(spots[i % spots.size()]) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), i % 4, 150)
	await seconds(4.0)
	at.begin_perf()
	await seconds(12.0)
	at.end_perf("14 zombies en navigation")
	var near := 0
	for z: Zombie in game.zombies.alive:
		if z.global_position.distance_to(p.global_position) < 4.5:
			near += 1
	at.check(near >= 12, "la foule a rejoint le joueur (%d/14 à moins de 4,5 m)" % near)
	p.yaw = 0.0
	p.pitch = deg_to_rad(-10)
	await seconds(0.2)
	await at.screenshot("crowd")
