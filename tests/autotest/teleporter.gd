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
	await until(func(): return game.hud._prompt.text.contains("courant"), 2.0, "invite du téléporteur")
	at.check(game.hud._prompt.text.contains("courant"), "courant requis : %s" % game.hud._prompt.text)
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	game.session.add_points(1, 4000)
	await seconds(1.0)  # le courant s'établit (levier) avant d'utiliser le téléporteur
	p.input.interact_pressed = true
	await until(func(): return tp.state == Teleporter.State.CHARGING and pd.points == 4000 - Teleporter.COST, 2.0, "charge du téléporteur")
	at.check(tp.state == Teleporter.State.CHARGING and pd.points == 4000 - Teleporter.COST, "activation : charge en cours (points %d)" % pd.points)
	await seconds(1.5)  # capture : charge en cours
	await at.screenshot("charging")
	await until(func(): return tp.state == Teleporter.State.ACTIVE, 3.0, "départ")
	await until(func(): return game.map_data.zone_at(MapData.world_to_cell(p.global_position)) == "p" and game.hud._hint.text.begins_with("RETOUR DANS"), 2.0, "arrivée dans la salle du rituel")
	var zone := game.map_data.zone_at(MapData.world_to_cell(p.global_position))
	at.check(zone == "p", "joueur transporté dans la salle du rituel (zone %s)" % zone)
	at.check(game.hud._hint.text.begins_with("RETOUR DANS"), "compte à rebours : %s" % game.hud._hint.text)
	await seconds(0.7)  # capture
	await at.screenshot("arrived")
	await until(func(): return tp.state == Teleporter.State.COOLDOWN, Teleporter.ACTIVE_TIME + 2.0, "retour")
	await until(func(): return p.global_position.distance_to(tp.global_position) < 2.5, 2.0, "retour sur la plateforme")
	var back := p.global_position.distance_to(tp.global_position)
	at.check(back < 2.5, "retour sur la plateforme (%.1f m)" % back)
	p.input.interact_pressed = true
	await seconds(0.3)  # fenêtre fixe : aucune activation ne doit partir
	at.check(tp.state == Teleporter.State.COOLDOWN and pd.points == 4000 - Teleporter.COST, "pas d'activation pendant la recharge")
