extends AutotestScenario
## @rendu : a besoin du rendu (fenêtre hors écran).
## @niveau perf : mesure, hors check (préfixe perf_).
## Meute de 24 chiens cubiques (HellhoundModel, un mesh partagé, un draw call
## par chien, ombres limitées par ZombieShadows) lâchée sur le joueur dans
## TEST ARENA : tous tapis puis jaillissant, course, bonds, morsures (joueur
## invulnérable) ; captures de la meute et images par seconde (moyenne et
## pire seconde) avec rendu. Sans rendu : coût CPU de la simulation.

const PACK := 24

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	var p := await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	var game := Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	var origin := MapData.cell_to_world(Vector2i(10, 7), 0.05)
	p.teleport_to(origin, -PI * 0.5)
	await seconds(0.3)
	var dogs: Array[Hellhound] = []
	for i in PACK:
		var pos: Variant = game.rounds.dogs.pick_spawn_point(p.global_position)
		if pos == null:
			continue
		var zid := game.zombies.spawn(pos, 3, 400, ZombieManager.KIND_DOG)
		var d := game.zombies.get_zombie(zid) as Hellhound
		if d:
			d.target = p
			d.favorite_enemy = p
			dogs.append(d)
	at.check(dogs.size() == PACK, "%d chiens lâchés" % dogs.size())
	await until(func(): return dogs.all(func(d): return d._revealed), DogRules.SPAWN_TIME + 1.0, "meute révélée")
	# La meute fonce : capture quand les premiers sont à mi-chemin.
	var t0 := Time.get_ticks_usec()
	var frames_n := 0
	var worst := INF
	var sec_frames := 0
	var sec_t := t0
	var shot := false
	while Time.get_ticks_usec() - t0 < 5_000_000:
		H.aim_at(p, origin + Vector3(6.0, 0.6, 0.0))
		await frames(1)
		frames_n += 1
		sec_frames += 1
		var now := Time.get_ticks_usec()
		if now - sec_t >= 1_000_000:
			worst = minf(worst, sec_frames * 1e6 / float(now - sec_t))
			sec_frames = 0
			sec_t = now
		if not shot and now - t0 > 1_200_000:
			shot = true
			await at.screenshot("pack")
	var avg := frames_n * 1e6 / float(Time.get_ticks_usec() - t0)
	print("[perf_dog_pack] %d chiens : %.0f img/s en moyenne, pire seconde %.0f img/s, ombres %d" % [dogs.size(), avg, worst, ZombieShadows.casting(game.zombies.alive)])
	at.check_perf(avg, 60.0, "meute de %d chiens (moyenne)" % dogs.size())
	# Tir dans la meute : morts sur le flanc, giclées.
	var killed := 0
	for d in dogs:
		if is_instance_valid(d) and d.is_alive() and killed < 8:
			game.combat.damage_zombie(d.id, 1000, 1, false, Vector3.RIGHT, Combat.HitKind.BULLET)
			killed += 1
	await seconds(1.0)
	await at.screenshot("pack_deaths")
	at.check(killed == 8, "8 chiens abattus dans la meute")
