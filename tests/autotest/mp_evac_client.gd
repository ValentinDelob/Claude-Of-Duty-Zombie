extends AutotestScenario
## [MP] Client : voit la porte d'évacuation s'ouvrir (état de l'objet reçu du
## serveur), le compte à rebours et les votes au HUD, vote « partir » à la
## porte, puis reçoit la fin de partie « évacuation réussie » décidée par
## l'hôte quand tout le monde est dans la zone.

const PORT := 17907

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var door := game.evac
	at.check(door != null and not door.is_open, "client : porte d'évacuation fermée")
	if door == null:
		return
	# Dans la zone, à gauche de la porte.
	p.teleport_to(door.global_position + door.global_basis.z * 1.6 - door.global_basis.x * 1.0 + Vector3.UP * 0.05)
	await frames(3)
	at.check(door.in_zone(p.global_position), "client : dans la zone de la porte")
	MpHelpers.signal_peer("place")
	if not await MpHelpers.wait_peer(self, "ouverte", 60.0):
		return
	var ok: bool = await until(func(): return door.is_open and game.hud.evac_status() != "", 5.0, "porte ouverte chez le client")
	at.check(ok, "client : porte ouverte, bandeau « %s »" % game.hud.evac_status())
	at.check(door.time_left > EvacRules.DURATION - 15.0, "client : compte à rebours reçu (%.0f s)" % door.time_left)
	H.aim_at(p, door.interact_point())
	await until(func(): return game.interact.focused == door, 3.0, "client : porte visée")
	at.check(door.prompt(p.peer_id).contains(Lang.t("PARTIR", "LEAVE")), "client : invite « %s »" % door.prompt(p.peer_id))
	p.input.interact_pressed = true
	ok = await until(func(): return int(door.votes.get(p.peer_id, 0)) == EvacRules.Vote.LEAVE, 5.0, "vote reçu en retour")
	at.check(ok, "client : vote « partir » enregistré")
	# Bandeau à jour dès l'état reçu (avant : « À la porte 1/2 » suffisait au
	# test alors que le bandeau affichait encore « Partir 0/2 »).
	var leave_txt := Lang.t("Partir 1/2", "Leave 1/2")
	var mine_txt := Lang.t("vous : PARTIR", "you: LEAVE")
	at.check(game.hud.evac_status().contains(leave_txt) and game.hud.evac_status().contains(mine_txt),
			"client : votes au HUD « %s »" % game.hud.evac_status())
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 30.0, "fin de partie")
	at.check(ok and game.last_result.evacuated, "client : évacuation réussie")
	if ok:
		at.check(game.last_result.round_reached == 2, "client : manche atteinte %d" % game.last_result.round_reached)
		at.check(game.hud._center_msg.text == Lang.t("ÉVACUATION RÉUSSIE", "EVACUATED"), "client : écran de fin « %s »" % game.hud._center_msg.text)
	await MpHelpers.finish(self)
