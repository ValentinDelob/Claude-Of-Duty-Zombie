extends AutotestScenario
## [MP] Client : vote ÉVACUER dans la zone, tombe à terre (cadre de vote :
## deux ÉVACUER ; à terre il vote encore, CONTINUER puis ÉVACUER), succombe ;
## l'équipe s'évacue avec lui : écran
## « évacuation réussie » et arme trouvée rapportée au profil, bien qu'il
## soit mort (armes mises de côté à terre).

const PORT := 17931

var H := AutotestHelpers


func _mp40_count() -> int:
	var n := 0
	for w in ProfileStore.load_profile().weapons:
		if w.weapon_id == "mp40":
			n += 1
	return n


func run() -> void:
	timeout_sec = 150
	ProfileStore.reset()
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var me := p.peer_id
	var lpd := game.session.local_data()
	var door := game.evac
	if door == null:
		at.fail("porte d'évacuation absente")
		return
	var before := _mp40_count()
	await until(func(): return lpd.weapons.any(func(w): return w.get("uid", "") == "loot:77"), 10.0, "arme trouvée reçue")
	p.teleport_to(door.global_position + door.global_basis.z * 1.6 - door.global_basis.x * 1.0 + Vector3.UP * 0.05)
	await frames(3)
	MpHelpers.signal_peer("place")
	if not await MpHelpers.wait_peer(self, "ouverte", 60.0):
		return
	await until(func(): return door.is_open, 5.0, "porte ouverte chez le client")
	var ok: bool = await H.evac_vote(self, p, EvacRules.Vote.LEAVE, 5.0)
	at.check(ok and int(door.votes.get(me, 0)) == EvacRules.Vote.LEAVE, "client : vote ÉVACUER enregistré")
	if not await MpHelpers.wait_peer(self, "a_terre", 30.0):
		return
	ok = await until(func(): return lpd.life == PlayerData.Life.DOWNED and int(door.votes.get(1, 0)) == EvacRules.Vote.LEAVE, 5.0, "à terre, vote de l'hôte")
	at.check(ok, "client : à terre pendant la fenêtre")
	at.check(lpd.saved_weapons.any(func(w): return w.get("uid", "") == "loot:77"), "client : arme trouvée mise de côté (reçue de l'hôte)")
	# Cadre : deux ÉVACUER (le sien, celui de l'hôte) ; à terre, il bloque.
	var panel := game.hud.evac_panel
	var both_leave := func():
		var rows: Array = panel.describe().rows
		return rows.size() == 2 and rows.all(func(r): return r.vote == EvacRules.Vote.LEAVE)
	ok = await until(both_leave, 5.0, "cadre à terre")
	at.check(ok, "client : cadre %s" % str(panel.describe().rows))
	# À terre, il vote encore (de n'importe où) : CONTINUER puis ÉVACUER.
	ok = await H.evac_vote(self, p, EvacRules.Vote.READY, 5.0)
	at.check(ok and int(door.votes.get(me, 0)) == EvacRules.Vote.READY, "client à terre : vote CONTINUER enregistré")
	ok = await H.evac_vote(self, p, EvacRules.Vote.LEAVE, 5.0)
	at.check(ok and int(door.votes.get(me, 0)) == EvacRules.Vote.LEAVE, "client à terre : revote ÉVACUER")
	MpHelpers.signal_peer("vu_a_terre")
	ok = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 15.0, "fin de partie")
	at.check(ok and game.last_result.evacuated, "client mort : évacué avec l'équipe")
	if ok:
		at.check(lpd.life == PlayerData.Life.DEAD, "client : mort (spectateur) à l'évacuation")
		var ids: Array = (game.last_result.loot.get("weapons", []) as Array).map(func(e): return e[0])
		at.check(ids.has("mp40"), "client : arme trouvée dans le rapport de fin (%s)" % str(ids))
		at.check(_mp40_count() == before + 1, "client : arme trouvée ajoutée à l'arsenal (%d -> %d)" % [before, _mp40_count()])
	await MpHelpers.finish(self)
	ProfileStore.reset()
