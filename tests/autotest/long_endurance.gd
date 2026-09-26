extends AutotestScenario
## ÉTAT : EN COURS D'INVESTIGATION — dans ce scénario, la coroutine cesse d'être
## reprise vers le début de la manche 3 (le jeu, lui, continue de tourner ;
## reproduit aussi sans tir du bot). Exclu de check.sh (préfixe long_).
##
## Endurance (hors check.sh, ~4 min) : un bot joue les manches 1 à 5 sur le
## BUNKER K-7 en abattant lui-même les zombies (vrai chemin client -> serveur).
## Vérifie stabilité, fuites (objets, nœuds, mémoire) et FPS sur la durée.
##   godot --path . --windowed -- --autotest=long_endurance

var H := AutotestHelpers


func nearest_visible(game: Game, p: Player) -> Zombie:
	var best: Zombie = null
	var best_d := 30.0
	for z: Zombie in game.zombies.alive:
		if z.state == Zombie.State.EMERGE:
			continue
		var d := z.global_position.distance_to(p.global_position)
		if d < best_d:
			var q := PhysicsRayQueryParameters3D.create(p.eye_position(), z.head_position(), 1)
			if p.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				best = z
				best_d = d
	return best


func run() -> void:
	timeout_sec = 480
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	WeaponDB.give(pd, "lmg")
	game.session.sync_inventory(1)
	p.teleport_to(MapData.cell_to_world(Vector2i(9, 25), 0.05))
	await seconds(1.0)
	var objects0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var nodes0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var fps_min := 100000.0
	var t := 0.0
	var last_round := 0
	var diag_t := 0.0
	at.begin_perf()
	while game.rounds.round_n <= 5 and t < 420.0:
		var z := nearest_visible(game, p)
		if z:
			H.aim_at(p, z.head_position())
			p.input.fire = true
		else:
			p.input.fire = false
		var w := pd.current_weapon()
		if not w.is_empty() and w.reserve < 100:
			WeaponDB.refill(pd, pd.slot)
			game.session.sync_inventory(1)
		if game.rounds.round_n != last_round:
			last_round = game.rounds.round_n
			var fps := Engine.get_frames_per_second()
			print("[endurance] manche %d, t=%.0f s, %d fps, objets %d, nœuds %d, mém %.0f Mo" % [last_round, t, fps, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
		if fmod(t, 5.0) < 0.1:
			print("[endurance] t=%.1f vivants %d état %s pause %s" % [t, game.zombies.alive_count(), GameState.state_name(GameState.state), tree().paused])
		if diag_t >= 15.0:
			diag_t = 0.0
			for zz: Zombie in game.zombies.alive:
				print("[endurance] zombie %d %s état %d vitesse %.2f bloqué %.1f s" % [zz.id, zz.global_position, zz.state, zz.anim_speed, zz.stuck_time()])
			print("[endurance] joueur %s, à faire apparaître %d" % [p.global_position, game.rounds.to_spawn])
		# Attente par images (un minuteur de SceneTree cessait de se déclencher
		# au bout d'une minute dans cette boucle : cause non identifiée).
		var t0 := Time.get_ticks_msec()
		await frames(6)
		var dt := (Time.get_ticks_msec() - t0) / 1000.0
		t += dt
		diag_t += dt
		if t > 5.0:
			fps_min = minf(fps_min, Engine.get_frames_per_second())
	p.input.fire = false
	at.end_perf("endurance")
	at.check(game.rounds.round_n > 5, "manches 1 à 5 jouées (manche %d atteinte, %d zombies abattus)" % [game.rounds.round_n, pd.kills])
	await seconds(3.0)
	var objects1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	var nodes1 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem1 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("[endurance] objets %d -> %d, nœuds %d -> %d, mémoire %.0f -> %.0f Mo, FPS min %.0f" % [objects0, objects1, nodes0, nodes1, mem0, mem1, fps_min])
	at.check(nodes1 < nodes0 + 60, "pas de fuite de nœuds (%d -> %d)" % [nodes0, nodes1])
	at.check(objects1 < objects0 * 1.25 + 500, "pas de fuite d'objets (%d -> %d)" % [objects0, objects1])
	at.check(mem1 < mem0 + 64.0, "mémoire stable (%.0f -> %.0f Mo)" % [mem0, mem1])
	await at.screenshot("end")
