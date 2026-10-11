extends AutotestScenario
## @rendu : a besoin du rendu (fenêtre hors écran).
## @niveau perf : mesure, hors check (préfixe perf_).
## Vague du Brancardier au pire : 24 zombies cubiques et 4 Brancardiers
## (BrancardierModel, un mesh partagé) lâchés sur le joueur dans TEST ARENA ;
## les Brancardiers chargent (préparation, charge, chocs). Capture et images
## par seconde (moyenne et pire seconde) ; joueur invulnérable.

const ZOMBIES := 24
const BRANCARDIERS := 4

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
	var n := 0
	var nb := 0
	for i in ZOMBIES + BRANCARDIERS:
		var pos: Variant = game.rounds.dogs.pick_spawn_point(p.global_position, 6.0, 22.0)
		if pos == null:
			continue
		if i < BRANCARDIERS:
			var b := game.rounds.brancard.debug_spawn(pos, 50000)
			if b:
				b.target = p
				b.charge_cooldown = randf_range(0.0, 3.0)
				nb += 1
		else:
			game.zombies.spawn(pos, 2 + i % 2, 5000)
			n += 1
	at.check(n == ZOMBIES and nb == BRANCARDIERS, "%d zombies et %d Brancardiers lâchés" % [n, nb])
	await seconds(1.6)  # sortis de terre
	var t0 := Time.get_ticks_usec()
	var frames_n := 0
	var worst := INF
	var sec_frames := 0
	var sec_t := t0
	var shot := false
	while Time.get_ticks_usec() - t0 < 6_000_000:
		H.aim_at(p, origin + Vector3(6.0, 1.0, 0.0))
		await frames(1)
		frames_n += 1
		sec_frames += 1
		var now := Time.get_ticks_usec()
		if now - sec_t >= 1_000_000:
			worst = minf(worst, sec_frames * 1e6 / float(now - sec_t))
			sec_frames = 0
			sec_t = now
		if not shot and now - t0 > 2_000_000:
			shot = true
			await at.screenshot("horde")
	var avg := frames_n * 1e6 / float(Time.get_ticks_usec() - t0)
	var charges := 0
	for z: Zombie in game.zombies.alive:
		if z is Brancardier:
			charges += (z as Brancardier).charges
	print("[perf_brancard] %d zombies + %d Brancardiers : %.0f img/s en moyenne, pire seconde %.0f img/s, %d charges" % [n, nb, avg, worst, charges])
	at.check_perf(avg, 60.0, "vague du Brancardier, %d entités (moyenne)" % (n + nb))
