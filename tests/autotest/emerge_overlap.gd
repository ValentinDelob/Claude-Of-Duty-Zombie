extends AutotestScenario
## Un zombie qui sort du sol sous les pieds du joueur ne le pousse ni ne le
## soulève (corps non solide pendant l'émergence), puis redevient solide.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 60
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var spot := MapData.cell_to_world(Vector2i(6, 6), 0.05)
	p.teleport_to(spot, 0.0)
	await seconds(0.6)
	var y0 := p.global_position.y
	var xz0 := Vector2(p.global_position.x, p.global_position.z)
	var zid := game.zombies.spawn(Vector3(spot.x, 0.0, spot.z), 0, 150)
	var z := game.zombies.get_zombie(zid)
	z.speed_mult = 0.0
	at.check(z.state == Zombie.State.EMERGE and z.collision_layer == 0, "émergence : corps non solide")
	var max_rise := 0.0
	var max_push := 0.0
	var t := 0.0
	while t < Zombie.EMERGE_TIME - 0.1:
		max_rise = maxf(max_rise, p.global_position.y - y0)
		max_push = maxf(max_push, Vector2(p.global_position.x, p.global_position.z).distance_to(xz0))
		await frames(1)
		t += at.get_process_delta_time()
	at.check(max_rise < 0.05, "le joueur n'est pas soulevé (%.2f m)" % max_rise)
	at.check(max_push < 0.05, "le joueur n'est pas poussé (%.2f m)" % max_push)
	await until(func(): return z.state != Zombie.State.EMERGE, 2.0, "fin de l'émergence")
	at.check(z.collision_layer == Zombie.BODY_LAYER, "après l'émergence, le zombie redevient solide")
	await at.screenshot("after")
