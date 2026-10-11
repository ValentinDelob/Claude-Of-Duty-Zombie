extends AutotestScenario
## [MP] Client : voit le Chirurgien (même canal réseau que les zombies)
## préparer et lancer ses scalpels (actions en RPC fiable, scalpels simulés
## ici aussi), est touché ; voit le changement de phase et subit l'onde de
## choc décidée par l'hôte ; reçoit l'annonce de la vague (bandeau, jauge de
## vie qui baisse), abat le boss en visant son cœur et reçoit ses
## échantillons et l'XP du boss.

const PORT := 17877

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 190
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var sr := game.rounds.surgeon
	var home := MapData.cell_to_world(Vector2i(18, 3), 0.05)
	p.teleport_to(home, PI * 0.5)
	# ------------------------------------------------ scalpels, onde de choc
	var acts := {}
	var saw_scalpel := [false]
	var k0 := p.knockbacks
	await until(func():
		for z: Zombie in game.zombies.alive:
			if z is Surgeon:
				acts[(z as Surgeon).action] = true
				if (z as Surgeon).rage:
					acts["rage"] = true
		if not sr.scalpels.flying.is_empty():
			saw_scalpel[0] = true
		return acts.has(Surgeon.Action.ROAR) and p.knockbacks > k0, 45.0, "lancer et changement de phase")
	at.check(acts.has(Surgeon.Action.THROW_WINDUP) and acts.has(Surgeon.Action.THROW), "client : préparation et lancer reçus (%s)" % str(acts.keys()))
	at.check(saw_scalpel[0], "client : scalpels en vol visibles")
	at.check(acts.has(Surgeon.Action.ROAR) and acts.has("rage"), "client : changement de phase, enragé")
	at.check(p.knockbacks == k0 + 1, "client : projeté par l'onde de choc")
	at.check(pd.health < pd.max_health, "client : blessé (%d PV)" % pd.health)
	p.teleport_to(home, PI * 0.5)
	# ------------------------------------------------ vague
	var ok: bool = await until(func(): return sr.cl_active, 30.0, "annonce de la vague")
	if not ok:
		return
	at.check(game.hud.round_counter().special, "client : compteur qui clignote")
	at.check(game.hud._center_msg.text == SurgeonRound.banner_text(), "client : bandeau « %s »" % game.hud._center_msg.text)
	at.check(sr.bar != null, "client : jauge de vie du boss")
	var low := [1.0]
	var seen := false
	var t := 0.0
	while t < 120.0:
		if not is_instance_valid(game):
			return
		var target: Surgeon = null
		for z: Zombie in game.zombies.alive:
			if z is Surgeon and z.state != Zombie.State.EMERGE:
				target = z
				seen = true
		if sr.bar:
			low[0] = minf(low[0], sr.bar.fraction)
		if target:
			H.aim_at(p, target.head_position())
			p.input.fire = true
		else:
			p.input.fire = false
		if p.weapons and p.weapons.current().mag == 0:
			p.input.reload = true
		if p.global_position.distance_to(home) > 3.0:
			p.teleport_to(home)
		if seen and not sr.cl_active:
			break
		if seen and game.rounds.phase == RoundManager.Phase.INTERMISSION:
			break
		await frames(1)
		t += at.get_process_delta_time()
	p.input.fire = false
	at.check(seen, "client : le Chirurgien reçu")
	at.check(low[0] < 0.05, "client : jauge vidée (%.2f)" % low[0])
	ok = await until(func(): return int(game.xp.my_ledger.kills.get(XpRules.SURGEON, 0)) == 1, 5.0, "XP du boss")
	at.check(ok, "client : XP du boss (%s)" % str(game.xp.my_ledger.kills))
	ok = await until(func(): return int(game.loot.my_samples.get("surgeon_heart", 0)) == 13, 5.0, "échantillons")
	at.check(ok and int(game.loot.my_samples.get("surgeon_scalpel", 0)) == 13, "client : scalpels et cœurs reçus (%s)" % str(game.loot.my_samples))
	await MpHelpers.finish(self)
