extends AutotestScenario
## [MP] Client : voit les planches arrachées par le serveur, répare en
## maintenant [F] (requête validée par l'hôte), voit un zombie de fenêtre
## arracher les planches.

const PORT := 17820


func run() -> void:
	timeout_sec = 110
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var w: Barricade = null
	for b in game.barricades.windows:
		if b.cell == Vector2i(6, 31):
			w = b
	at.check(w != null and game.barricades.windows.size() >= 12, "fenêtres construites côté client")
	if w == null:
		return
	var ok: bool = await until(func(): return w.planks() == 2, 25.0, "planches arrachées reçues")
	at.check(ok, "état des planches répliqué (%d planches)" % w.planks())
	await seconds(0.8)
	p.teleport_to(w.global_position + w.inward * 1.25 + Vector3(0, 0.05, 0))
	AutotestHelpers.aim_at(p, w.global_position + Vector3.UP * 1.4)
	await seconds(0.3)
	var pts0 := pd.points
	p.input.interact = true
	p.input.interact_pressed = true
	ok = await until(func(): return w.planks() == 6, 12.0, "fenêtre reconstruite")
	p.input.interact = false
	at.check(ok, "maintenir [F] reconstruit la fenêtre côté client")
	await seconds(0.5)
	at.check(pd.points - pts0 == 40, "points de réparation reçus du serveur : +%d" % (pd.points - pts0))
	p.teleport_to(w.global_position + w.inward * 2.4 + Vector3(0, 0.05, 0))
	AutotestHelpers.aim_at(p, w.global_position + Vector3.UP * 1.3)
	ok = await until(func(): return game.zombies.alive_count() >= 1, 15.0, "zombie reçu")
	if ok:
		var z: Zombie = game.zombies.alive[0]
		at.check(z.barricade == w and z.state != Zombie.State.EMERGE, "marionnette : zombie de fenêtre (pas d'émergence)")
		ok = await until(func(): return w.planks() < 6, 8.0, "planche arrachée par le zombie")
		at.check(ok, "le zombie du serveur arrache les planches (vu par le client)")
		await seconds(0.3)
		await at.screenshot("tearing")
	await seconds(3.0)
