extends AutotestScenario
## [MP] Hôte : XP de partie comptée ici pour chaque joueur (docs/XP_RULES.md).
## Élimination : au seul tueur (marcheur pour l'hôte, sprinteur pour le
## client) ; manche survécue : à chaque joueur non mort (le client, mort à la
## manche 2, ne la gagne pas) ; fin de partie : relevés clos et envoyés à
## tous, XP du client calculée ici et reçue par lui.

const PORT := 17925

var H := AutotestHelpers


func _end_round(game: Game) -> bool:
	await H.clear_zombies(self)
	var n := game.rounds.round_n
	game.rounds.to_spawn = 0
	game.rounds.paused = false
	var ok: bool = await until(func(): return game.rounds.phase == RoundManager.Phase.INTERMISSION, 3.0, "fin de la manche %d" % n)
	game.rounds.paused = true
	return ok


func run() -> void:
	timeout_sec = 150
	ProfileStore.reset()
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	game.map_def.waves = WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}})
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	var xp := game.xp
	var zm := game.zombies
	var front := game.local_player.global_position + Vector3(0, 0, -4)
	game.rounds.debug_jump_to(1)

	# 1. Une élimination chacun : au seul tueur.
	var a := zm.spawn(front, RoundRules.WALK, 150)
	var b := zm.spawn(front + Vector3(1.5, 0, 0), RoundRules.SPRINT, 150)
	await H.emerged(self, [zm.get_zombie(a), zm.get_zombie(b)])
	game.combat.damage_zombie(a, 99999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
	game.combat.damage_zombie(b, 99999, cid, false, Vector3.FORWARD, Combat.HitKind.BULLET)
	var lh: Dictionary = xp.ledger(1)
	var lc: Dictionary = xp.ledger(cid)
	at.check(lh.kills == {XpRules.WALKER: 1} and lc.kills == {XpRules.SPRINTER: 1},
			"élimination au seul tueur (hôte %s, client %s)" % [lh.kills, lc.kills])

	# 2. Fin de la manche 1 : manche survécue pour les deux.
	if not await _end_round(game):
		return
	at.check(int(lh.rounds) == 1 and int(lc.rounds) == 1, "manche 1 : comptée pour les deux joueurs")
	MpHelpers.signal_peer("round1")
	if not await MpHelpers.wait_peer(self, "client_saw_round1", 30.0):
		return

	# 3. Manche 2 : le client meurt, la manche n'est comptée que pour l'hôte.
	game.rounds.debug_jump_to(2)
	game.kill_player(cid)
	await until(func(): return game.session.get_data(cid).life == PlayerData.Life.DEAD, 3.0, "client mort")
	if not await _end_round(game):
		return
	at.check(int(lh.rounds) == 2 and int(lc.rounds) == 1, "manche 2 : rien pour le joueur mort (hôte %d, client %d)" % [lh.rounds, lc.rounds])

	# 4. Fin de partie : relevés clos, envoyés à tous.
	var want_client := XpRules.kill_xp(XpRules.SPRINTER, 1) + XpRules.round_xp(1)
	at.check(XpRules.total(lc) == want_client, "XP du client calculée ici : %d" % XpRules.total(lc))
	game.srv_end_match(false)
	var ok: bool = await until(func(): return game.last_result != null, 5.0, "fin de partie")
	if ok:
		var r := game.last_result
		at.check(r.xp_ledgers.has(cid) and XpRules.total(r.xp_ledgers[cid]) == want_client, "relevé du client dans le résultat")
		at.check(r.xp == XpRules.kill_xp(XpRules.WALKER, 1) + XpRules.round_xp(1) + XpRules.round_xp(2), "XP de l'hôte : %d" % r.xp)
		at.check(ProfileStore.load_profile().xp == r.xp, "profil de l'hôte : %d XP" % ProfileStore.load_profile().xp)
	MpHelpers.signal_peer("ended")
	await MpHelpers.finish(self)
	ProfileStore.reset()
