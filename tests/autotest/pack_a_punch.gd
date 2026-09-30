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
	await until(func(): return game.interact.focused == pap and game.hud._prompt.text == pap.prompt(p.peer_id), 2.0, "Pack-a-Punch visé")


## Appuie sur [F] et attend l'effet (état de la machine ou points changés).
func press() -> void:
	var pd := game.session.local_data()
	var state0 := pap.state
	var points0 := pd.points
	p.input.interact_pressed = true
	await until(func(): return pap.state != state0 or pd.points != points0, 2.0, "Pack-a-Punch utilisé")


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
	at.check(game.hud._prompt.text == Interactable.need_power_text(), "courant requis : %s" % game.hud._prompt.text)
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await until(func(): return game.power_on, 2.0, "courant rétabli")
	# On achète une M14 (don direct) et on se donne des points.
	WeaponDB.give(pd, "m14")
	game.session.sync_inventory(1)
	game.session.add_points(1, 12000)
	await until(func(): return pd.points == 12500 and p.weapons.current().get("id", "") == "m14", 3.0, "M14 en main et points crédités")
	await at_machine()
	at.check(game.hud._prompt.text.contains(Lang.t("Améliorer", "Upgrade")) and game.hud._prompt.text.contains("5000"), "invite : %s" % game.hud._prompt.text)
	await press()
	at.check(pap.state == PackAPunch.State.WORKING and pd.has_weapon("m14") < 0, "M14 déposée dans l'autel")
	at.check(pd.points == 12500 - 5000, "5000 points débités (%d)" % pd.points)
	await seconds(2.0)  # capture : au milieu de la forge
	await at.screenshot("forge")
	await until(func(): return pap.state == PackAPunch.State.READY, 4.0, "arme prête")
	await seconds(0.6)  # capture : arme sortie de la machine
	await at.screenshot("ready")
	await press()
	var slot := pd.has_weapon("m14")
	at.check(slot >= 0 and pd.weapons[slot].pap, "M14 améliorée récupérée")
	var s := WeaponDB.stats("m14", true)
	at.check(s.name == "M14 VIEILLE GARDE" and s.damage == 250 and pd.weapons[slot].mag == 15, "%s : %d dégâts, chargeur %d" % [s.name, s.damage, pd.weapons[slot].mag])
	await seconds(1.0)  # capture : arme améliorée sortie en main
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
	await until(func(): return pd.current_weapon().get("id", "") == "m1911", 2.0, "M1911 en main")
	await at_machine()
	await press()
	at.check(pap.state == PackAPunch.State.WORKING, "M1911 déposé")
	await until(func(): return pap.state == PackAPunch.State.READY, 5.0, "prêt")
	await until(func(): return pap.state == PackAPunch.State.IDLE, PackAPunch.READY_TIME + 1.0, "délai écoulé")
	at.check(pd.has_weapon("m1911") < 0, "arme non récupérée : perdue")
