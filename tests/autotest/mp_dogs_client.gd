extends AutotestScenario
## [MP] Client : reçoit l'annonce de la vague « meute » (compteur qui clignote,
## aboiements lointains, sans brouillard), voit les chiens (même canal réseau
## que les zombies) tapis puis jaillir, se déplacer (instantanés interpolés) et
## les abat.

const PORT := 17871

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var dogs := game.rounds.dogs
	var home := MapData.cell_to_world(Vector2i(10, 7), 0.05)
	p.teleport_to(home, -PI * 0.5)
	var ok: bool = await until(func(): return dogs.cl_active, 40.0, "annonce de manche de chiens")
	if not ok:
		return
	at.check(game.hud.round_counter().special, "client : compteur de manche qui clignote")
	# Aboiements lointains de l'annonce, joués sur chaque machine.
	await until(func(): return dogs.cl_howls > 0, DogRound.HOWL_TIMES[0] + 2.0, "aboiements lointains")
	at.check(dogs.cl_howls > 0, "client : aboiements lointains de l'annonce (%d)" % dogs.cl_howls)
	var seen := {}
	var moved := {}
	var first_pos := {}
	var hidden_ok := true
	var shot_done := false
	var t := 0.0
	while t < 110.0:
		if not is_instance_valid(game):
			at.fail("client : partie fermée avant la fin de la manche de chiens (%d chiens vus)" % seen.size())
			return
		var target: Hellhound = null
		for z: Zombie in game.zombies.alive:
			if not z is Hellhound:
				at.check(false, "entité non-chien pendant la manche de chiens")
				continue
			var d := z as Hellhound
			seen[d.id] = true
			if not first_pos.has(d.id):
				first_pos[d.id] = d.global_position
			elif d.global_position.distance_to(first_pos[d.id]) > 2.0:
				moved[d.id] = true
			# Visible pendant qu'il est tapi = défaut (après, le client révèle le
			# chien de lui-même si l'état du serveur arrive en retard).
			if d.state == Zombie.State.EMERGE and d.skel.visible and d._life_t < DogRules.SPAWN_TIME:
				hidden_ok = false
			if d._revealed and (target == null or d.global_position.distance_to(p.global_position) < target.global_position.distance_to(p.global_position)):
				target = d
		if target:
			H.aim_at(p, target.global_position + Vector3.UP * 0.5)
			p.input.fire = true
			if not shot_done and target.global_position.distance_to(p.global_position) < 6.0:
				shot_done = true
				await at.screenshot("dog")
		else:
			p.input.fire = false
		if p.weapons and p.weapons.current().mag == 0:
			p.input.reload = true
		if p.global_position.distance_to(home) > 3.0:
			p.teleport_to(home)
		if seen.size() >= 12 and game.zombies.alive_count() == 0:
			break
		await frames(1)
		t += at.get_process_delta_time()
	p.input.fire = false
	at.check(seen.size() == 12, "client : 12 chiens reçus (%d)" % seen.size())
	at.check(moved.size() >= 6, "client : chiens en mouvement (%d)" % moved.size())
	at.check(hidden_ok, "client : invisibles tant qu'ils sont tapis")
	at.check(pd.kills >= 2, "client : chiens abattus (%d)" % pd.kills)
	ok = await until(func(): return not dogs.cl_active, 8.0, "fin de l'ambiance")
	at.check(ok and not game.hud.round_counter().special, "client : ambiance terminée")
	await MpHelpers.finish(self)
