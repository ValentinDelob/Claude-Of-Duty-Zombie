extends AutotestScenario
## Téléporteur : courant requis, 1500 points, charge, transport des joueurs
## présents sur la plateforme vers la salle du rituel, retour, recharge.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	var tp := game.teleporter
	at.check(tp != null, "téléporteur présent sur le quai")
	p.teleport_to(tp.global_position + Vector3(0.3, 0.2, 0.3))
	H.aim_at(p, tp.global_position + Vector3.UP * 0.2)
	await seconds(0.4)
	at.check(game.hud._prompt.text.contains("courant"), "courant requis : %s" % game.hud._prompt.text)
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	game.session.add_points(1, 4000)
	await seconds(1.0)
	p.input.interact_pressed = true
	await seconds(0.3)
	at.check(tp.state == Teleporter.State.CHARGING and pd.points == 3000, "activation : charge en cours (points %d)" % pd.points)
	await seconds(1.5)
	await at.screenshot("charging")
	await until(func(): return tp.state == Teleporter.State.ACTIVE, 3.0, "départ")
	await seconds(0.5)
	var zone := game.map_data.zone_at(MapData.world_to_cell(p.global_position))
	at.check(zone == "p", "joueur transporté dans la salle du rituel (zone %s)" % zone)
	at.check(game.hud._hint.text.begins_with("RETOUR DANS"), "compte à rebours : %s" % game.hud._hint.text)
	await seconds(0.7)
	await at.screenshot("arrived")
	await until(func(): return tp.state == Teleporter.State.COOLDOWN, Teleporter.ACTIVE_TIME + 2.0, "retour")
	await seconds(0.5)
	var back := p.global_position.distance_to(tp.global_position)
	at.check(back < 2.5, "retour sur la plateforme (%.1f m)" % back)
	p.input.interact_pressed = true
	await seconds(0.3)
	at.check(tp.state == Teleporter.State.COOLDOWN and pd.points == 3000, "pas d'activation pendant la recharge")
