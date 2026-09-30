extends AutotestScenario
## Portes payantes : invite, refus faute de points, achat validé par le
## serveur, ouverture, passage, navigation et zones d'apparition débloquées.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	var door: Door = game.doors["2"]
	p.teleport_to(MapData.cell_to_world(Vector2i(16, 24), 0.05))
	H.aim_at(p, door.interact_point())
	await until(func(): return game.interact.focused == door and game.hud._prompt.text == door.prompt(p.peer_id), 2.0, "porte 2 visée")
	at.check(game.interact.focused == door, "la porte 2 est visée")
	var txt: String = game.hud._prompt.text
	at.check(txt.contains("750") and txt.contains(Lang.t("Couloir", "Cell Block")), "invite : « %s »" % txt)
	await at.screenshot("prompt")

	# 500 points : trop pauvre.
	pd.points = 500
	p.input.interact_pressed = true
	await until(func(): return game.hud._flash.text != "", 2.0, "message de refus")
	at.check(not door.is_open and pd.points == 500, "achat refusé sans assez de points")
	at.check(game.hud._flash.text != "", "message de refus affiché")

	# Ouverture.
	game.session.add_points(1, 1000)
	await until(func(): return pd.points > 500, 2.0, "points crédités")
	p.input.interact_pressed = true
	await until(func(): return door.is_open, 2.0, "porte ouverte")
	at.check(door.is_open, "porte ouverte après achat")
	at.check(pd.points == 750, "750 points débités (%d)" % pd.points)
	at.check(game.spawner.active_zones.has("b"), "zone b activée pour les apparitions")
	var path := game.nav.find_path(p.global_position, MapData.cell_to_world(Vector2i(28, 24)))
	at.check(not path.is_empty(), "les zombies peuvent passer")
	await until(func(): return not door._slab.visible, Door.OPEN_TIME + 2.0, "fin de l'ouverture de la porte")
	await at.screenshot("open")
	# On traverse.
	p.yaw = -PI * 0.5
	p.input.move = Vector2(0, 1)
	await seconds(1.2)  # marche mesurée
	p.input.move = Vector2.ZERO
	at.check(p.global_position.x > 19.5, "le joueur passe la porte (x=%.1f)" % p.global_position.x)
	at.check(game.interact.focused != door, "plus d'invite sur une porte ouverte")

	# Une porte non achetée ne s'ouvre pas via une demande lointaine (triche).
	var far: Door = game.doors["5"]
	game.interact.srv_interact.rpc_id(1, far.interact_id)
	await seconds(0.2)  # rien à attendre : on vérifie que rien ne se passe
	at.check(not far.is_open, "demande d'ouverture à distance refusée")
