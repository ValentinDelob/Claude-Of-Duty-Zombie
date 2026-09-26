extends AutotestScenario
## Atouts : courant requis (sauf Lazarus), prix solo, effets serveur (santé,
## rechargement, cadence), aucune limite (BO1), animation de boisson, icônes,
## LAZARUS limité à 3 achats en solo.

var H := AutotestHelpers
var game: Game
var p: Player


func buy(marker: String) -> PerkMachine:
	var m: PerkMachine = game.interact.get_obj("perk_" + marker)
	p.teleport_to(m.interact_point() + Vector3(0, -1.15, 0))
	H.aim_at(p, m.global_position + Vector3.UP * 1.3)
	await seconds(0.3)
	p.input.interact_pressed = true
	await seconds(0.4)
	return m


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	for id in game.doors:
		game.doors[id].srv_open()
	await seconds(0.5)

	# Lazarus : sans courant, 500 en solo.
	await buy("Q")
	at.check(pd.has_perk("lazarus") and pd.points == 0, "LAZARUS TONIC acheté sans courant pour 500 (points %d)" % pd.points)
	await seconds(0.5)
	at.check(p.weapons.view.is_drinking(), "animation de boisson")
	await at.screenshot("drink")
	await seconds(2.0)

	# Titan : courant requis.
	game.session.add_points(1, 20000)
	var titan := await buy("J")
	at.check(not pd.has_perk("titan"), "TITAN refusé sans courant")
	at.check(game.hud._prompt.text.contains("courant"), "invite : %s" % game.hud._prompt.text)
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await seconds(0.5)
	await buy("J")
	at.check(pd.has_perk("titan") and pd.max_health == 250 and pd.health == 250, "TITAN BREW : 250 PV (%d/%d)" % [pd.health, pd.max_health])
	var back := titan.global_position - titan.interact_point()
	back.y = 0.0
	p.teleport_to(titan.global_position - back.normalized() * 3.2 + Vector3(0, 0.05, 0))
	H.aim_at(p, titan.global_position + Vector3.UP * 1.3)
	await seconds(2.4)
	await at.screenshot("machine")

	# Rapid : rechargement divisé par 2.
	var w := {"id": "m1911", "pap": false}
	var before := game.combat.reload_time(1, w)
	await buy("S")
	await seconds(2.4)
	at.check(pd.has_perk("rapid") and absf(game.combat.reload_time(1, w) - before * 0.5) < 0.01, "RAPID FIZZ : rechargement %.2f s -> %.2f s" % [before, game.combat.reload_time(1, w)])

	# Twin : cadence.
	await buy("D")
	await seconds(2.4)
	at.check(pd.has_perk("twin") and absf(game.combat.game_rate_mult(1) - 1.33) < 0.01, "TWIN SHOT : cadence x1,33")

	# 5e atout : pas de limite dans Black Ops 1.
	await buy("M")
	at.check(pd.has_perk("stride") and pd.perks.size() == 5, "5 atouts (aucune limite)")
	await seconds(2.6)
	await at.screenshot("icons")
	at.check(game.hud._perk_icons.perks.size() == 5, "5 icônes dans le HUD")

	# Solo : 3e LAZARUS consommé -> la machine s'envole.
	var q: PerkMachine = game.interact.get_obj("perk_Q")
	game.perks.solo_revive_buys = PerkDB.SOLO_REVIVE_LIMIT
	at.check(q.visible and not q.can_interact(1), "LAZARUS épuisé : plus d'achat")
	game.perks.srv_clear(1)
	await until(func(): return not q.visible, 4.0, "machine disparue")
	at.check(not q.visible, "la machine LAZARUS a disparu")
