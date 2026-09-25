extends AutotestScenario
## Courant : coupé au départ (éclairage de secours), levier gratuit, cascade
## d'allumage, état répliqué, définitif.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	at.check(not game.power_on, "courant coupé au départ")
	var sw: PowerSwitch = game.interact.get_obj("power")
	at.check(sw != null, "levier présent")
	# Accès au générateur.
	for id in ["2", "3", "4"]:
		game.doors[id].srv_open()
	await seconds(0.5)
	p.teleport_to(MapData.cell_to_world(Vector2i(61, 25), 0.05))
	H.aim_at(p, sw.global_position)
	await seconds(0.4)
	await at.screenshot("before")
	at.check(game.interact.focused == sw, "le levier est visé : %s" % game.hud._prompt.text)
	p.input.interact_pressed = true
	await seconds(0.3)
	at.check(game.power_on and sw.is_on, "courant rétabli")
	await seconds(3.0)
	await at.screenshot("after")
	at.check(game.interact.focused != sw, "plus d'invite une fois le courant rétabli")
	# Vue du labo éclairé.
	p.teleport_to(MapData.cell_to_world(Vector2i(35, 31), 0.05))
	H.aim_at(p, MapData.cell_to_world(Vector2i(52, 18), 1.2))
	await seconds(0.4)
	await at.screenshot("lab_lit")
