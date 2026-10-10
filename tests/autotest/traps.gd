extends AutotestScenario
## Piège électrique : courant requis, 1000 points, zombies foudroyés dans la
## zone (0 point), joueurs blessés, durée puis recharge.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	var pd := game.session.local_data()
	var trap: ElectricTrap = game.interact.get_obj("trap")
	at.check(trap != null and trap.trap_cells.size() == 12, "piège présent (%d cases)" % trap.trap_cells.size())
	game.doors["2"].srv_open()
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	game.session.add_points(1, 2000)  # on part de 0 ferraille
	await seconds(1.0)  # le courant s'établit (levier) avant d'utiliser le piège
	p.teleport_to(MapData.cell_to_world(Vector2i(22, 23), 0.05))
	H.aim_at(p, trap.global_position)
	await until(func(): return game.hud._prompt.text.contains("1000"), 2.0, "invite du piège")
	at.check(game.hud._prompt.text.contains("1000"), "invite : %s" % game.hud._prompt.text)
	p.input.interact_pressed = true
	await until(func(): return trap.state == ElectricTrap.State.ACTIVE and pd.points == 1000, 2.0, "piège activé")
	at.check(trap.state == ElectricTrap.State.ACTIVE and pd.points == 1000, "piège activé (points %d)" % pd.points)

	# Un zombie traverse la zone : foudroyé, sans points.
	var z := await H.dummy_zombie(self, MapData.cell_to_world(Vector2i(28, 23)))
	var pts := pd.points
	z.global_position = MapData.cell_to_world(Vector2i(25, 23))
	await until(func(): return not is_instance_valid(z) or not z.is_alive(), 2.0, "zombie foudroyé")
	at.check(not z.is_alive(), "zombie foudroyé dans la zone")
	at.check(pd.points == pts, "aucun point pour une mort par piège")
	p.teleport_to(MapData.cell_to_world(Vector2i(21, 24), 0.05))
	H.aim_at(p, MapData.cell_to_world(Vector2i(25, 24), 1.3))
	await seconds(0.3)  # capture
	await at.screenshot("active")

	# Le joueur qui entre est blessé.
	var hp0 := pd.health
	p.teleport_to(MapData.cell_to_world(Vector2i(25, 24), 0.05))
	await until(func(): return pd.health < hp0, 2.0, "joueur électrocuté")
	at.check(pd.health < hp0, "le joueur est électrocuté (%d -> %d PV)" % [hp0, pd.health])
	p.teleport_to(MapData.cell_to_world(Vector2i(21, 24), 0.05))

	await until(func(): return trap.state == ElectricTrap.State.COOLDOWN, ElectricTrap.ACTIVE_TIME + 2.0, "fin du piège")
	at.check(trap.state == ElectricTrap.State.COOLDOWN, "recharge après 25 s")
	var z2 := await H.dummy_zombie(self, MapData.cell_to_world(Vector2i(25, 22)))
	await seconds(0.5)  # fenêtre fixe : le zombie doit rester en vie
	at.check(z2.is_alive(), "piège inactif pendant la recharge")
