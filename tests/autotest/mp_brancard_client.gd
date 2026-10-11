extends AutotestScenario
## [MP] Client : voit le Brancardier (même canal réseau que les zombies)
## préparer sa charge, charger et rester étourdi (phase transmise dans les
## instantanés) ; subit la projection décidée par l'hôte ; reçoit l'annonce
## de la vague (bandeau, compteur qui clignote), abat un Brancardier et reçoit
## ses échantillons (sangles, bracelets) et l'XP du mini-boss.

const PORT := 17873

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 170
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var br := game.rounds.brancard
	var home := MapData.cell_to_world(Vector2i(18, 3), 0.05)
	p.teleport_to(home, PI * 0.5)
	# ------------------------------------------------ charge
	var phases := {}
	var t := 0.0
	var k0 := p.knockbacks
	while t < 40.0:
		for z: Zombie in game.zombies.alive:
			if z is Brancardier:
				phases[(z as Brancardier).charge_phase] = true
		if phases.has(Brancardier.Phase.STUN):
			break
		await frames(1)
		t += at.get_process_delta_time()
	at.check(phases.has(Brancardier.Phase.WINDUP) and phases.has(Brancardier.Phase.CHARGE) and phases.has(Brancardier.Phase.STUN),
			"client : préparation, charge et étourdissement reçus (%s)" % str(phases.keys()))
	at.check(p.knockbacks == k0 + 1, "client : projeté par la charge (%d)" % (p.knockbacks - k0))
	at.check(pd.health < pd.max_health, "client : blessé par la charge (%d PV)" % pd.health)
	p.teleport_to(home, PI * 0.5)
	# ------------------------------------------------ vague
	var ok: bool = await until(func(): return br.cl_active, 30.0, "annonce de la vague")
	if not ok:
		return
	at.check(game.hud.round_counter().special, "client : compteur qui clignote")
	at.check(game.hud._center_msg.text == BrancardRound.banner_text(2), "client : bandeau « %s »" % game.hud._center_msg.text)
	var seen := {}
	t = 0.0
	while t < 120.0:
		if not is_instance_valid(game):
			return
		var target: Brancardier = null
		for z: Zombie in game.zombies.alive:
			if z is Brancardier:
				seen[z.id] = true
				if z.state != Zombie.State.EMERGE and (target == null or z.global_position.distance_to(p.global_position) < target.global_position.distance_to(p.global_position)):
					target = z
		if target:
			H.aim_at(p, target.head_position())
			p.input.fire = true
		else:
			p.input.fire = false
		if p.weapons and p.weapons.current().mag == 0:
			p.input.reload = true
		if p.global_position.distance_to(home) > 3.0:
			p.teleport_to(home)
		if seen.size() >= 2 and not br.cl_active:
			break
		if game.rounds.phase == RoundManager.Phase.INTERMISSION and seen.size() >= 2:
			break
		await frames(1)
		t += at.get_process_delta_time()
	p.input.fire = false
	at.check(seen.size() == 2, "client : 2 Brancardiers reçus (%d)" % seen.size())
	ok = await until(func(): return int(game.xp.my_ledger.kills.get(XpRules.BRANCARDIER, 0)) == 1, 5.0, "XP du Brancardier")
	at.check(ok, "client : XP du mini-boss (%s)" % str(game.xp.my_ledger.kills))
	ok = await until(func(): return int(game.loot.my_samples.get("brancard_strap", 0)) == 12, 5.0, "échantillons")
	at.check(ok and int(game.loot.my_samples.get("brancard_bracelet", 0)) == 12, "client : sangles et bracelets reçus (%s)" % str(game.loot.my_samples))
	await MpHelpers.finish(self)
