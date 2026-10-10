extends AutotestScenario
## [MP] Hôte : met le client à terre, le réanime en maintenant [F], puis le
## laisse succomber ; le client réapparaît à la manche suivante.

const PORT := 17814


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	var p := game.local_player
	p.bot_controlled = true
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	var cpd := game.session.get_data(cid)
	var client: Player = game.players[cid]
	await until(func(): return client.global_position.distance_to(MapData.cell_to_world(Vector2i(6, 7))) < 1.0, 15.0, "client en place")
	var hpd := game.session.local_data()
	cpd.points = 1000
	hpd.points = 2000
	game.combat.damage_player(cid, 500, client.global_position + Vector3(1, 1, 0))
	await until(func(): return cpd.life == PlayerData.Life.DOWNED and game.downed.is_downed(cid), 2.0, "client à terre")
	at.check(cpd.life == PlayerData.Life.DOWNED and game.downed.is_downed(cid), "client à terre (serveur)")
	at.check(cpd.points == 950, "à terre : 5 %% des points perdus (1000 -> %d)" % cpd.points)
	at.check(game.players.size() == 2 and GameState.state == GameState.State.PLAYING, "la partie continue (l'hôte est debout)")
	# Réanimation : on s'approche et on maintient [F].
	p.teleport_to(client.global_position + Vector3(-1.2, 0, 0), -PI * 0.5)
	AutotestHelpers.aim_at(p, client.global_position + Vector3.UP * 0.4)
	await until(func(): return game.interact.focused == client.revive_target, 2.0, "invite de réanimation")
	at.check(game.interact.focused == client.revive_target, "invite de réanimation : %s" % game.hud._prompt.text)
	# L'hôte voit le client assis au sol (PlayerModel), tête à la hauteur de
	# la caméra du client à terre.
	await until(func(): return client.visual._down_k >= 1.0, 2.0, "pose à terre vue par l'hôte")
	var hips_y: float = client.visual.skel.get_bone_pose_position(client.visual.bones.hips).y
	at.check(client.visual._down_k >= 1.0 and hips_y < 0.2, "client vu assis au sol (bassin à %.2f m)" % hips_y)
	at.check(absf(client.head.position.y - client.downed_eye()) < 0.01, "tête du client à la hauteur de sa caméra à terre (%.2f m)" % client.head.position.y)
	p.input.interact_pressed = true
	p.input.interact = true
	await seconds(2.0)  # [F] maintenu (la réanimation dure 4 s)
	await at.screenshot("reviving")
	await until(func(): return cpd.life == PlayerData.Life.ALIVE, 4.0, "réanimation")
	p.input.interact = false
	at.check(cpd.life == PlayerData.Life.ALIVE, "client réanimé par l'hôte (maintien de 4 s)")
	at.check(game.session.local_data().revives == 1, "réanimation comptée pour l'hôte")
	at.check(hpd.points == 2000, "le sauveteur ne gagne pas de ferraille (2000 -> %d)" % hpd.points)
	# Le client a vu sa réanimation ; saignement jusqu'à la mort.
	if not await MpHelpers.wait_peer(self, "releve", 15.0):
		return
	await until(func(): return client.visual._down_k <= 0.0, 2.0, "client vu debout")
	at.check(client.visual._down_k <= 0.0 and client.visual.skel.get_bone_pose_position(client.visual.bones.hips).y > 0.8, "client réanimé vu debout")
	game.downed.bleedout_time = 3.0
	game.combat.damage_player(cid, 500, client.global_position)
	await until(func(): return cpd.life == PlayerData.Life.DEAD, 6.0, "mort par saignement")
	at.check(cpd.life == PlayerData.Life.DEAD, "client mort après le délai de saignement")
	at.check(hpd.points == 1800, "coéquipier succombé : 10 %% de la ferraille perdue (2000 -> %d)" % hpd.points)
	# Manche suivante (une fois la mort vue par le client) : retour du client.
	if not await MpHelpers.wait_peer(self, "mort", 15.0):
		return
	game.rounds.debug_jump_to(2)
	await until(func(): return cpd.life == PlayerData.Life.ALIVE, 3.0, "réapparition")
	at.check(cpd.life == PlayerData.Life.ALIVE, "le client réapparaît à la manche suivante")
	await MpHelpers.finish(self)
