extends AutotestScenario
## Pack-a-Punch : courant requis, 5000 points, arme déposée puis rendue
## améliorée (nom, dégâts, chargeur, camouflage), perdue si non récupérée,
## recharge à 2500.

var H := AutotestHelpers
var game: Game
var p: Player
var pap: PackAPunch


func at_machine() -> void:
	var n := (pap.global_position - pap.interact_point())
	n.y = 0.0
	p.teleport_to(pap.global_position - n.normalized() * 1.7 + Vector3(0, 0.05, 0))
	H.aim_at(p, pap.global_position + Vector3.UP * 1.1)
	await seconds(0.3)


func press() -> void:
	p.input.interact_pressed = true
	await seconds(0.3)


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	pap = game.interact.get_obj("pap")
	at.check(pap != null, "Pack-a-Punch présent dans la salle du rituel")
	await at_machine()
	at.check(game.hud._prompt.text.contains("courant"), "courant requis : %s" % game.hud._prompt.text)
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await seconds(0.5)
	# On achète une M14 (don direct) et on se donne des points.
	WeaponDB.give(pd, "m14")
	game.session.sync_inventory(1)
	game.session.add_points(1, 12000)
	await seconds(1.0)
	await at_machine()
	at.check(game.hud._prompt.text.contains("Améliorer") and game.hud._prompt.text.contains("5000"), "invite : %s" % game.hud._prompt.text)
	await press()
	at.check(pap.state == PackAPunch.State.WORKING and pd.has_weapon("m14") < 0, "M14 déposée dans l'autel")
	at.check(pd.points == 12500 - 5000, "5000 points débités (%d)" % pd.points)
	await seconds(2.0)
	await at.screenshot("forge")
	await until(func(): return pap.state == PackAPunch.State.READY, 4.0, "arme prête")
	await seconds(0.6)
	await at.screenshot("ready")
	await press()
	var slot := pd.has_weapon("m14")
	at.check(slot >= 0 and pd.weapons[slot].pap, "M14 améliorée récupérée")
	var s := WeaponDB.stats("m14", true)
	at.check(s.name == "M14 VIEILLE GARDE" and s.damage == 250 and pd.weapons[slot].mag == 15, "%s : %d dégâts, chargeur %d" % [s.name, s.damage, pd.weapons[slot].mag])
	await seconds(1.0)
	await at.screenshot("pap_weapon")

	# Recharge d'une arme améliorée.
	for i in 3:
		await H.shoot(self, p, 0.25)
	await at_machine()
	at.check(game.hud._prompt.text.contains("2500"), "recharge proposée : %s" % game.hud._prompt.text)
	await press()
	at.check(pd.weapons[pd.has_weapon("m14")].mag == 15, "arme améliorée rechargée")

	# Arme oubliée : perdue.
	p.weapons.slot = 0
	game.combat.srv_switch.rpc_id(1, 0)
	await seconds(0.8)
	await at_machine()
	await press()
	at.check(pap.state == PackAPunch.State.WORKING, "M1911 déposé")
	await until(func(): return pap.state == PackAPunch.State.READY, 5.0, "prêt")
	await until(func(): return pap.state == PackAPunch.State.IDLE, PackAPunch.READY_TIME + 1.0, "délai écoulé")
	at.check(pd.has_weapon("m1911") < 0, "arme non récupérée : perdue")
