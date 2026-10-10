extends AutotestScenario
## [MP] Hôte : construction par un CLIENT à la station (GAME_CONCEPT §4.11).
## Le client construit une arme de SON arsenal (inconnu de l'hôte) : l'hôte
## valide tout (portée, niveau, ferraille, une seule à la fois) et fait foi ;
## l'état de la construction (en cours, manche de fin, prête) est répliqué ;
## le client récupère l'arme dans son inventaire de partie.

const PORT := 17915

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var st := game.station
	at.check(st != null, "hôte : station de construction")
	if st == null:
		return
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	var cpd := game.session.get_data(cid)
	var client: Player = game.players[cid]
	game.session.add_points(cid, 3000)
	# Le client se place lui-même devant la station.
	if not await MpHelpers.wait_peer(self, "place", 30.0):
		return
	await until(func(): return InteractionSystem.in_reach(client.srv_origin(), st.srv_point(), st.interact_range), 10.0, "client vu devant la station")
	MpHelpers.signal_peer("vu")

	# 1. Le client essaie une arme trop haute, puis lance la sienne.
	if not await MpHelpers.wait_peer(self, "lance", 30.0):
		return
	var ok: bool = await until(func(): return st.builds.has(cid), 5.0, "construction du client")
	at.check(ok, "hôte : construction du client acceptée")
	if not ok:
		return
	var w: Dictionary = st.builds[cid].w
	var price := BuildRules.price(w)
	at.check(String(w.id) == "mp40" and int(w.level) == 4 and String(w.uid) == "w1", "hôte : exemplaire de l'arsenal du client (%s niv. %d, %s)" % [w.id, w.level, w.uid])
	at.check(cpd.points == 3000 - price, "hôte : ferraille du client dépensée (%d)" % cpd.points)
	at.check(not bool(st.builds[cid].ready), "hôte : en construction")
	var n := int(st.builds[cid]["round"])
	MpHelpers.signal_peer("en_cours")

	# 2. Une seule à la fois (seconde demande du client refusée).
	if not await MpHelpers.wait_peer(self, "seconde", 30.0):
		return
	await seconds(0.5)
	at.check(cpd.points == 3000 - price and String(st.builds[cid].w.uid) == "w1", "hôte : seconde construction refusée")
	at.check(BuildRules.weapon_count(cpd) == 1, "hôte : dernière arme du client gardée (recyclage refusé)")

	# 3. Fin de la manche : prête.
	game.rounds.debug_jump_to(n)
	game.rounds._end_round()
	await until(func(): return bool(st.builds[cid].ready), 2.0, "prête")
	MpHelpers.signal_peer("prete")

	# 4. Récupération par le client ([F] à la station).
	ok = await until(func(): return not st.builds.has(cid), 30.0, "récupérée")
	at.check(ok and cpd.bag.size() == 1 and String(cpd.bag[0].uid) == "w1", "hôte : arme dans l'inventaire du client")
	MpHelpers.signal_peer("fin")
	await MpHelpers.finish(self)
