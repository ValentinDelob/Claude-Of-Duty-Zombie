extends AutotestScenario
## Apparitions : zones actives uniquement, jamais sous le nez du joueur, points
## visibles évités, recyclage des zombies égarés, effet d'émergence.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var sp := game.spawner
	at.check(sp.points.size() == 4, "4 points d'apparition sur la carte (%d)" % sp.points.size())
	at.check(sp.active_points().size() == 3, "3 actifs (zone a) au départ")

	# 1. Jamais dans une zone fermée ni à moins de 7 m.
	p.teleport_to(MapData.cell_to_world(Vector2i(6, 3), 0.05), 0.0)
	await seconds(0.2)
	var bad_zone := 0
	var too_close := 0
	for i in 200:
		var pos: Variant = sp.pick_spawn_point()
		if pos == null:
			continue
		if game.map_data.zone_at(MapData.world_to_cell(pos)) != "a":
			bad_zone += 1
		if pos.distance_to(p.global_position) < Spawner.MIN_PLAYER_DIST:
			too_close += 1
	at.check(bad_zone == 0, "aucune apparition en zone fermée")
	at.check(too_close == 0, "aucune apparition à moins de 7 m (point à 1 m exclu)")

	# 2. Un point visible est évité au profit d'un point caché.
	var visible_pt := MapData.cell_to_world(Vector2i(22, 2))
	p.teleport_to(MapData.cell_to_world(Vector2i(12, 2), 0.05), 0.0)
	H.aim_at(p, visible_pt + Vector3.UP)
	await seconds(0.2)
	var hits_visible := 0
	for i in 200:
		var pos2: Variant = sp.pick_spawn_point()
		if pos2 != null and pos2.distance_to(visible_pt) < 0.5:
			hits_visible += 1
	at.check(hits_visible < 40, "le point dans le champ de vision est évité (%d/200)" % hits_visible)

	# 3. Zone b ouverte : son point devient disponible.
	sp.activate_zone("b")
	at.check(sp.active_points().size() == 4, "zone b ouverte : 4 points actifs")

	# 4. Recyclage d'un zombie coincé loin des joueurs.
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 7), 0.05), 0.0)
	var z := await H.dummy_zombie(self, MapData.cell_to_world(Vector2i(22, 13)))
	sp.recycle_time = 2.0
	var recycled := 0
	for i in 20:
		await seconds(0.5)
		recycled += sp.recycle(0.5)
		if recycled > 0:
			break
	at.check(recycled == 1 and game.zombies.alive_count() == 0, "zombie égaré recyclé (%d)" % recycled)

	# 5. Émergence visible.
	p.teleport_to(MapData.cell_to_world(Vector2i(12, 9), 0.05), 0.0)
	var zid := game.zombies.spawn(MapData.cell_to_world(Vector2i(12, 5)), 0, 150)
	H.aim_at(p, MapData.cell_to_world(Vector2i(12, 5), 0.6))
	await seconds(0.7)
	await at.screenshot("emerge")
	at.check(game.zombies.get_zombie(zid).state == Zombie.State.EMERGE, "le zombie sort du sol")
