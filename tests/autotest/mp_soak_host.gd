extends "res://tests/autotest/long_soak.gd"
## @niveau long
## [MP] Soak hôte + client (hors check.sh ; MP="soak" sh tools/check.sh ou
## sh tools/mp_test.sh soak) sur BUNKER K-7 : les deux bots jouent les
## manches 1 à 3 en abattant les zombies (tirs du client validés ici), le
## client quitte en pleine partie (menu pause), l'hôte continue seul
## (manches recalculées pour 1 joueur), le client essaie de revenir : refusé
## proprement (« La partie a déjà commencé », comme BO1 : pas d'arrivée en
## cours de partie), puis l'hôte joue jusqu'à la manche 5. Invariants du soak
## (long_soak.gd) pour l'hôte, points et munitions des deux joueurs, aucune
## erreur ni avertissement du moteur.

const PORT := 17845
var _rejected: Array = []


func run() -> void:
	timeout_sec = 400
	_log = SoakLogger.new()
	OS.add_logger(_log)
	if not await MpHelpers.host_game(self, PORT, "bunker_k7"):
		OS.remove_logger(_log)
		return
	game = Game.instance
	p = game.local_player
	p.bot_controlled = true
	pd = game.session.local_data()
	map_id = "bunker_k7"
	game.combat.debug_invulnerable = true
	Net.peer_rejected.connect(func(pid: int, reason: String): _rejected.append([pid, reason]))
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	await play_until(func(): return game.rounds.round_n >= 3, 300.0, "manche 3 à deux")
	var cpd := game.session.get_data(cid)
	at.check(cpd != null and cpd.kills > 0, "le client a abattu des zombies (%d, %d points)" % [cpd.kills if cpd else -1, cpd.points if cpd else -1])
	at.check(game.rounds.player_count() == 2, "manches calculées pour 2 joueurs")
	# Départ du client en pleine manche.
	MpHelpers.signal_peer("manche3")
	await play_until(func(): return game.players.size() == 1, 60.0, "départ du client")
	at.check(game.players.size() == 1 and game.session.data.size() == 1, "joueur parti retiré (joueurs %d, données %d)" % [game.players.size(), game.session.data.size()])
	at.check(GameState.state in [GameState.State.PLAYING, GameState.State.ROUND_END], "la partie continue pour l'hôte (%s)" % GameState.State.keys()[GameState.state])
	MpHelpers.signal_peer("parti_vu")
	# Il essaie de revenir : refusé.
	await play_until(func(): return MpHelpers.peer_reached("refus_vu"), 60.0, "tentative de retour du client")
	at.check(not _rejected.is_empty() and String(_rejected[0][1]).contains("déjà commencé"), "retour en cours de partie refusé : %s" % str(_rejected))
	at.check(game.players.size() == 1, "toujours seul en jeu")
	var r0 := game.rounds.round_n
	await play_until(func(): return game.rounds.round_n >= maxi(r0 + 2, 5), 300.0, "manches suivantes en solo")
	at.check(game.rounds.player_count() == 1, "manches recalculées pour 1 joueur")
	p.input.fire = false
	for kind: String in _reports:
		print("[soak] écart « %s » vu %d fois" % [kind, _reports[kind]])
	await frames(2)
	OS.remove_logger(_log)
	var errs := _log.snapshot()
	for l in errs.slice(0, 20):
		print("[soak] journal : " + l)
	at.check(errs.is_empty(), "aucune erreur ni avertissement du moteur chez l'hôte (%d)" % errs.size())
	await MpHelpers.finish(self)


## Combat du bot jusqu'à `cond` (au plus `limit` s de jeu).
func play_until(cond: Callable, limit: float, what: String) -> bool:
	var t := 0.0
	while not cond.call():
		if t > limit:
			at.fail("attente trop longue : " + what)
			return false
		if GameState.state == GameState.State.GAME_OVER:
			at.fail("GAME OVER inattendu (%s)" % what)
			return false
		await fight_tick()
		check_team()
		t += 0.1
	return true


## Invariants des AUTRES joueurs (données du serveur).
func check_team() -> void:
	for pid: int in game.session.data:
		if pid == 1:
			continue
		var d := game.session.get_data(pid)
		# Réserve du bot client entretenue (plus d'achat de munitions).
		var cw := d.current_weapon()
		if not cw.is_empty() and int(cw.reserve) < 30 and d.life == PlayerData.Life.ALIVE:
			WeaponDB.refill(d, d.slot)
			game.session.sync_inventory(pid)
		if d.points < 0:
			report("points_client", "points négatifs du joueur %d : %d" % [pid, d.points])
		for w: Dictionary in d.weapons:
			var s := WeaponDB.stats(w.id, w.pap)
			if int(w.mag) > int(s.mag) or int(w.reserve) > int(s.reserve):
				report("munitions_client", "munitions hors bornes du joueur %d, %s : %d/%d" % [pid, w.id, w.mag, w.reserve])
		var pl: Player = game.players.get(pid)
		if pl and not is_finite3(pl.global_position):
			report("nan_client", "position non finie du joueur %d" % pid)
