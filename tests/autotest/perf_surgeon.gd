extends AutotestScenario
## @rendu : a besoin du rendu (fenêtre hors écran).
## @niveau perf : mesure, hors check (préfixe perf_).
## Vague de boss au pire : le Chirurgien enragé (cœur et yeux qui flamboient,
## combos, éventails de 5 scalpels) au milieu de 24 zombies cubiques et 8
## patients relevés, dans TEST ARENA ; jauge de vie affichée. Capture et
## images par seconde (moyenne et pire seconde) ; joueur invulnérable.

const ZOMBIES := 24

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
	var sr := game.rounds.surgeon
	sr._cl_round(true)
	var n := 0
	for i in ZOMBIES:
		var pos: Variant = game.rounds.dogs.pick_spawn_point(p.global_position, 6.0, 22.0)
		if pos != null:
			game.zombies.spawn(pos, 2 + i % 2, 5000)
			n += 1
	var spot: Variant = game.rounds.dogs.pick_spawn_point(p.global_position, 8.0, 14.0)
	var s: Surgeon = sr.debug_spawn(spot if spot != null else origin + Vector3(8, 0, 0), 400000)
	s.target = p
	s.surgeries = 1  # première opération déjà faite
	s.health = 190000  # enragé (rugissement), puis la 2e opération plus tard
	for i in 4:
		sr.srv_summon(s)
	at.check(n == ZOMBIES and s != null, "%d zombies et le Chirurgien lâchés" % n)
	await seconds(1.6)
	var t0 := Time.get_ticks_usec()
	var frames_n := 0
	var worst := INF
	var sec_frames := 0
	var sec_t := t0
	var shot := false
	while Time.get_ticks_usec() - t0 < 6_000_000:
		H.aim_at(p, s.global_position + Vector3.UP * 1.5)
		if sr.bar:
			sr.bar.set_fraction(float(s.health) / s.max_health, s.rage)
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
			await at.screenshot("boss")
	var avg := frames_n * 1e6 / float(Time.get_ticks_usec() - t0)
	print("[perf_surgeon] %d zombies + %d patients + Chirurgien : %.0f img/s en moyenne, pire seconde %.0f img/s, %d combos, %d lancers, %d scalpels" % [
		n, sr.summoned, avg, worst, s.combos, s.throws, sr.scalpels.thrown])
	at.check_perf(avg, 60.0, "vague du Chirurgien, %d entités (moyenne)" % (n + sr.summoned + 1))
