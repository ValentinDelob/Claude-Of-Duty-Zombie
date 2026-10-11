extends AutotestScenario
## [MP] Client : voit l'Infirmière (même canal réseau que les zombies)
## préparer son cri et hurler (phases reçues en message fiable), subit
## l'étourdissement décidé par l'hôte (vue qui tangue, ralenti), voit les
## zombies ameutés s'allumer ; reçoit l'annonce de la vague (bandeau,
## compteur qui clignote), abat une Infirmière et reçoit ses échantillons
## (cordes vocales, seringues, badges) et l'XP du mini-boss.

const PORT := 17875

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 170
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var nr := game.rounds.nurse
	var home := MapData.cell_to_world(Vector2i(18, 3), 0.05)
	p.teleport_to(home, PI * 0.5)
	# ------------------------------------------------ cri
	var phases := {}
	var glowing := [false]
	var d0 := p.dazes
	await until(func():
		for z: Zombie in game.zombies.alive:
			if z is Nurse:
				phases[(z as Nurse).scream_phase] = true
				if not (z as Nurse)._glow.is_empty():
					glowing[0] = true
		return phases.has(Nurse.Phase.SCREAM) and p.dazes > d0, 40.0, "cri de l'Infirmière")
	at.check(phases.has(Nurse.Phase.WINDUP) and phases.has(Nurse.Phase.SCREAM),
			"client : préparation et cri reçus (%s)" % str(phases.keys()))
	at.check(p.dazes == d0 + 1 and p.daze_amount() > 0.0, "client : étourdi par le cri (%.2f)" % p.daze_amount())
	at.check(p.current_max_speed() < Player.WALK_SPEED, "client : ralenti (%.2f m/s)" % p.current_max_speed())
	await until(func():
		for z: Zombie in game.zombies.alive:
			if z is Nurse and not (z as Nurse)._glow.is_empty():
				glowing[0] = true
		return glowing[0], 2.0, "zombies ameutés")
	at.check(glowing[0], "client : zombies ameutés allumés")
	await until(func(): return pd.health < pd.max_health, 2.0, "dégâts du cri")
	at.check(pd.health < pd.max_health, "client : blessé par le cri (%d PV)" % pd.health)
	p.teleport_to(home, PI * 0.5)
	# ------------------------------------------------ vague
	var ok: bool = await until(func(): return nr.cl_active, 30.0, "annonce de la vague")
	if not ok:
		return
	at.check(game.hud.round_counter().special, "client : compteur qui clignote")
	at.check(game.hud._center_msg.text == NurseRound.banner_text(2), "client : bandeau « %s »" % game.hud._center_msg.text)
	var seen := {}
	var t := 0.0
	while t < 120.0:
		if not is_instance_valid(game):
			return
		var target: Nurse = null
		for z: Zombie in game.zombies.alive:
			if z is Nurse:
				seen[z.id] = true
				if z.state != Zombie.State.EMERGE and (target == null or z.global_position.distance_to(p.global_position) < target.global_position.distance_to(p.global_position)):
					target = z
		if target:
			H.aim_at(p, target.global_position + Vector3.UP * 1.1)
			p.input.fire = true
		else:
			p.input.fire = false
		if p.weapons and p.weapons.current().mag == 0:
			p.input.reload = true
		if p.global_position.distance_to(home) > 3.0:
			p.teleport_to(home)
		if seen.size() >= 2 and not nr.cl_active:
			break
		if game.rounds.phase == RoundManager.Phase.INTERMISSION and seen.size() >= 2:
			break
		await frames(1)
		t += at.get_process_delta_time()
	p.input.fire = false
	at.check(seen.size() == 2, "client : 2 Infirmières reçues (%d)" % seen.size())
	ok = await until(func(): return int(game.xp.my_ledger.kills.get(XpRules.NURSE, 0)) == 1, 5.0, "XP de l'Infirmière")
	at.check(ok, "client : XP du mini-boss (%s)" % str(game.xp.my_ledger.kills))
	ok = await until(func(): return int(game.loot.my_samples.get("nurse_syringe", 0)) == 14, 5.0, "échantillons")
	at.check(ok and int(game.loot.my_samples.get("nurse_vocal_cords", 0)) == 14, "client : cordes vocales, seringues et badges reçus (%s)" % str(game.loot.my_samples))
	await MpHelpers.finish(self)
