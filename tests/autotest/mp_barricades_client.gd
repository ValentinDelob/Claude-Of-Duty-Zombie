extends AutotestScenario
## [MP] Client : voit les planches arrachées par le serveur, répare en
## maintenant [F] collé à la fenêtre (requête validée par l'hôte ; demande
## forcée à 1,5 m refusée), voit un zombie de fenêtre
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
	MpHelpers.signal_peer("fenetres")
	var ok: bool = await until(func(): return w.planks() == 2, 25.0, "planches arrachées reçues")
	at.check(ok, "état des planches répliqué (%d planches)" % w.planks())
	# À 1,5 m de la barrière : pas d'invite ; une demande forcée (client
	# modifié) est refusée par l'hôte, qui juge la portée lui-même.
	p.teleport_to(w.global_position + w.inward * (w.barrier_face() + 1.5) + Vector3(0, 0.05, 0))
	AutotestHelpers.aim_at(p, w.global_position + Vector3.UP * 1.4)
	MpHelpers.signal_peer("loin_fenetre")
	if not await MpHelpers.wait_peer(self, "vu_loin_fenetre", 20.0):
		return
	at.check(game.interact.focused != w, "à 1,5 m de la fenêtre : pas d'invite")
	game.interact.srv_interact.rpc_id(1, w.interact_id)
	MpHelpers.signal_peer("demande_loin")
	if not await MpHelpers.wait_peer(self, "refus_loin", 20.0):
		return
	game.interact.srv_release.rpc_id(1, w.interact_id)
	at.check(w.planks() == 2, "demande de loin refusée : toujours %d planches" % w.planks())
	# Le joueur AVANCE vers la fenêtre et appuie sur [F] dès que l'invite
	# apparaît (position prédite du client) : le serveur, qui juge sur une
	# position en retard, accepte quand même (marge de latence, demande
	# renvoyée tant que [F] reste maintenu).
	MpHelpers.signal_peer("devant_fenetre")
	var pts0 := pd.points
	p.input.move = Vector2(0, 1)
	ok = await until(func(): return game.interact.focused == w, 6.0, "invite de réparation en avançant")
	at.check(ok, "en avançant vers la fenêtre : invite de réparation")
	p.input.interact = true
	p.input.interact_pressed = true
	await frames(3)
	p.input.move = Vector2.ZERO
	ok = await until(func(): return w.planks() == 6, 12.0, "fenêtre reconstruite")
	p.input.interact = false
	at.check(ok, "maintenir [F] reconstruit la fenêtre côté client")
	await until(func(): return pd.points - pts0 >= 40, 3.0, "points de réparation reçus")
	at.check(pd.points - pts0 == 40, "points de réparation reçus du serveur : +%d" % (pd.points - pts0))
	p.teleport_to(w.global_position + w.inward * 2.4 + Vector3(0, 0.05, 0))
	AutotestHelpers.aim_at(p, w.global_position + Vector3.UP * 1.3)
	MpHelpers.signal_peer("recule")
	ok = await until(func(): return game.zombies.alive_count() >= 1, 15.0, "zombie reçu")
	if ok:
		var z: Zombie = game.zombies.alive[0]
		at.check(z.barricade == w and z.state != Zombie.State.EMERGE, "marionnette : zombie de fenêtre (pas d'émergence)")
		ok = await until(func(): return w.planks() < 6, 8.0, "planche arrachée par le zombie")
		at.check(ok, "le zombie du serveur arrache les planches (vu par le client)")
		await seconds(0.3)
		await at.screenshot("tearing")
	MpHelpers.signal_peer("arrachage_vu")
	await MpHelpers.finish(self)
