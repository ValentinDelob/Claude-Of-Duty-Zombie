extends AutotestScenario
## Endurance (hors check.sh, préfixe long_, ~4 min) : un bot joue les manches
## 1 à 5 sur le BUNKER K-7 en abattant lui-même les zombies (vrai chemin
## client -> serveur). Vérifie stabilité, fuites (objets, nœuds, mémoire
## statique, orphelins) et FPS sur la durée ; une ligne [perf] par manche.
##   godot --path . --windowed -- --autotest=long_endurance
##
## Historique : le scénario « cessait d'être repris » au bout d'une minute.
## Cause : Autotest armait le délai du scénario AVANT que run() ne fixe
## timeout_sec, donc avec la valeur par défaut (60 s) ; à 60 s, finish()
## libérait la partie (le message affichait pourtant 480 s). Corrigé dans
## scripts/autoload/autotest.gd (délai vérifié chaque seconde). Aucun blocage
## du jeu : un fil de surveillance
## a montré que les images continuaient jusqu'à la fermeture.

var H := AutotestHelpers
var game: Game
var _samples: Array[Dictionary] = []


func nearest_visible(p: Player) -> Zombie:
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


## Relevé mémoire / objets, imprimé en [perf].
func _sample(label: String, t: float) -> Dictionary:
	var s := {
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"mem": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"zombies": game.zombies.zombies.size(),
	}
	print("[perf] endurance %s, t=%.0f s : %d fps, mém statique %.1f Mo, objets %d, nœuds %d, orphelins %d, ressources %d, zombies %d" % [
		label, t, Engine.get_frames_per_second(), s.mem, s.objects, s.nodes, s.orphans, s.resources, s.zombies])
	return s


func run() -> void:
	timeout_sec = 480
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	WeaponDB.give(pd, "hk21")
	game.session.sync_inventory(1)
	p.teleport_to(MapData.cell_to_world(Vector2i(9, 25), 0.05))
	await seconds(1.0)
	var fps_min := 100000.0
	var t := 0.0
	var last_round := 0
	at.begin_perf()
	while game.rounds.round_n <= 5 and t < 420.0:
		var z := nearest_visible(p)
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
			# Relevé au début de chaque manche (aucun zombie encore en vie).
			_samples.append(_sample("manche %d" % last_round, t))
		await seconds(0.1)
		t += 0.1
		if t > 5.0:
			fps_min = minf(fps_min, Engine.get_frames_per_second())
	p.input.fire = false
	at.end_perf("endurance")
	at.check(game.rounds.round_n > 5, "manches 1 à 5 jouées (manche %d atteinte, %d zombies abattus)" % [game.rounds.round_n, pd.kills])
	# Fin : manches figées, zombies de la manche 6 retirés, corps dissous, puis
	# relevé final dans le même état que ceux des débuts de manche.
	game.rounds.paused = true
	for zid in game.zombies.alive.map(func(zz: Zombie): return zz.id):
		game.zombies.kill(zid, false, Vector3.FORWARD)
	await until(func(): return game.zombies.zombies.is_empty(), 20.0, "corps dissous")
	await seconds(2.0)
	var end := _sample("fin", t)
	if _samples.size() < 2:
		return
	# Fuite ou plafond ? Trois vagues identiques de 24 zombies tués au tir
	# (sang, décalques, sons, corps) : la mémoire ne doit plus croître.
	var waves: Array[Dictionary] = []
	for wave in 3:
		for k in 24:
			var pos: Variant = game.spawner.pick_spawn_point()
			if pos != null:
				game.zombies.spawn(pos, k % 4, 100)
		await seconds(Zombie.EMERGE_TIME + 0.2)
		for zz: Zombie in game.zombies.alive.duplicate():
			game.combat.damage_zombie(zz.id, 1000, 1, zz.id % 2 == 0, Vector3.FORWARD, Combat.HitKind.BULLET)
		await until(func(): return game.zombies.zombies.is_empty(), 20.0, "corps dissous (vague)")
		await seconds(1.0)
		waves.append(_sample("vague %d" % (wave + 1), t))
	var growth: float = waves[2].mem - waves[0].mem
	at.check(growth < 1.0 and waves[2].objects <= waves[0].objects + 30, "vagues répétées : mémoire %.1f -> %.1f Mo, objets %d -> %d (pas de croissance)" % [waves[0].mem, waves[2].mem, waves[0].objects, waves[2].objects])
	var first: Dictionary = _samples[0]
	var r2: Dictionary = _samples[1]
	print("[perf] endurance : objets %d -> %d, nœuds %d -> %d, mémoire %.1f -> %.1f Mo, FPS min %.0f" % [first.objects, end.objects, first.nodes, end.nodes, first.mem, end.mem, fps_min])
	# Référence : manche 2 (les caches de sons, d'ombres et de chemins sont
	# remplis pendant la manche 1).
	at.check(end.nodes <= first.nodes + 20, "pas de fuite de nœuds (%d -> %d)" % [first.nodes, end.nodes])
	at.check(end.orphans <= first.orphans + 5, "pas de nœuds orphelins (%d -> %d)" % [first.orphans, end.orphans])
	at.check(end.objects < r2.objects + 300, "pas de fuite d'objets (manche 2 : %d, fin : %d)" % [r2.objects, end.objects])
	at.check(end.mem < r2.mem + 16.0, "mémoire statique stable (manche 2 : %.1f Mo, fin : %.1f Mo)" % [r2.mem, end.mem])
	await at.screenshot("end")
