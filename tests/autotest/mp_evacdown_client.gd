extends AutotestScenario
## [MP] Client : vote « partir » dans la zone, tombe à terre (le bandeau le
## compte hors de la porte), succombe ; l'équipe s'évacue avec lui : écran
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
	H.aim_at(p, door.interact_point())
	await until(func(): return game.interact.focused == door, 3.0, "client : porte visée")
	p.input.interact_pressed = true
	var ok: bool = await until(func(): return int(door.votes.get(me, 0)) == EvacRules.Vote.LEAVE, 5.0, "vote reçu en retour")
	at.check(ok, "client : vote « partir » enregistré")
	if not await MpHelpers.wait_peer(self, "a_terre", 30.0):
		return
	ok = await until(func(): return lpd.life == PlayerData.Life.DOWNED and int(door.votes.get(1, 0)) == EvacRules.Vote.LEAVE, 5.0, "à terre, vote de l'hôte")
	at.check(ok, "client : à terre pendant la fenêtre")
	at.check(lpd.saved_weapons.any(func(w): return w.get("uid", "") == "loot:77"), "client : arme trouvée mise de côté (reçue de l'hôte)")
	# Bandeau : deux « partir », mais seul l'hôte (debout) compte à la porte.
	var want := Lang.t("Partir 2/2", "Leave 2/2")
	var zone := Lang.t("À la porte 1/2", "At the door 1/2")
	ok = await until(func(): return game.hud.evac_status().contains(want) and game.hud.evac_status().contains(zone), 5.0, "bandeau à terre")
	at.check(ok, "client : bandeau « %s »" % game.hud.evac_status())
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
