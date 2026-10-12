extends AutotestScenario
## [MP] Client : voit la porte d'évacuation s'ouvrir (état de l'objet reçu du
## serveur), le compte à rebours et les votes au cadre de vote du HUD, vote
## CONTINUER puis change pour ÉVACUER (de n'importe où, F1 / F2, passé par le
## serveur), voit le vote de l'hôte, puis reçoit la fin de partie
## « évacuation réussie » décidée par l'hôte quand tout le monde est dans la zone.

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
	var panel := game.hud.evac_panel
	var ok: bool = await until(func(): return door.is_open and panel.visible, 5.0, "porte ouverte chez le client")
	at.check(ok, "client : porte ouverte, cadre de vote %s" % str(panel.describe()))
	at.check(door.time_left > EvacRules.DURATION - 15.0, "client : compte à rebours reçu (%.0f s)" % door.time_left)
	at.check(panel.describe().rows.size() == 2 and panel.describe().rows[0].me, "client : deux lignes, la sienne d'abord")
	ok = await H.evac_vote(self, p, EvacRules.Vote.READY, 5.0)
	at.check(ok and int(door.votes.get(p.peer_id, 0)) == EvacRules.Vote.READY, "client : vote CONTINUER enregistré par l'hôte")
	ok = await H.evac_vote(self, p, EvacRules.Vote.LEAVE, 5.0)
	at.check(ok and int(door.votes.get(p.peer_id, 0)) == EvacRules.Vote.LEAVE, "client : l'autre touche change le vote (ÉVACUER)")
	# Cadre à jour dès l'état reçu : son choix en face de son nom (« (toi) »),
	# celui de l'hôte (EN ATTENTE, ou ÉVACUER s'il a déjà voté) ; repère de la porte.
	await frames(1)
	var rows: Array = panel.describe().rows
	if rows.size() < 2:
		at.fail("client : cadre de vote incomplet %s" % str(rows))
		return
	at.check(rows[0].vote == EvacRules.Vote.LEAVE and rows[0].name.ends_with(Lang.t("(toi)", "(you)"))
			and rows[1].vote != EvacRules.Vote.READY and not rows[1].me, "client : votes au HUD %s" % str(rows))
	at.check(game.hud.evac_marker.visible or GameState.state == GameState.State.GAME_OVER, "client : repère de la porte (ÉVACUER)")
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 30.0, "fin de partie")
	at.check(ok and game.last_result.evacuated, "client : évacuation réussie")
	if ok:
		at.check(game.last_result.round_reached == 2, "client : manche atteinte %d" % game.last_result.round_reached)
		at.check(game.hud._center_msg.text == Lang.t("ÉVACUATION RÉUSSIE", "EVACUATED"), "client : écran de fin « %s »" % game.hud._center_msg.text)
	await MpHelpers.finish(self)
