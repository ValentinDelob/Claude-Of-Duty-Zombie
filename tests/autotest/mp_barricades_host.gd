extends AutotestScenario
## [MP] Hôte : arrache 4 planches d'une fenêtre (diffusion fiable), vérifie
## que la réparation du CLIENT est validée ici (+10 par planche), puis fait
## apparaître un zombie derrière la fenêtre.

const PORT := 17820


func run() -> void:
	timeout_sec = 110
	if not await MpHelpers.host_game(self, PORT, "bunker_k7"):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var cpd := game.session.get_data(client_id)
	var w: Barricade = null
	for b in game.barricades.windows:
		if b.cell == Vector2i(6, 31):
			w = b
	at.check(w != null, "fenêtre sud de la salle de garde")
	if w == null:
		return
	# Le client a construit ses fenêtres.
	if not await MpHelpers.wait_peer(self, "fenetres", 20.0):
		return
	for i in 4:
		w.srv_tear()
		await seconds(0.3)  # cadence d'arrachage d'un zombie
	at.check(w.planks() == 2, "4 planches arrachées côté serveur")
	var pts0 := cpd.points
	# Le client se téléporte devant la fenêtre : il ne répare qu'une fois que
	# le serveur le voit à cet endroit (sinon « trop loin », position répliquée
	# avec le délai d'interpolation réseau).
	if not await MpHelpers.wait_peer(self, "devant_fenetre", 20.0):
		return
	var client: Player = game.players[client_id]
	var spot := w.global_position + w.inward * 1.25
	if not await until(func(): return Vector2(client.global_position.x - spot.x, client.global_position.z - spot.z).length() < 0.3, 5.0, "client vu devant la fenêtre"):
		return
	MpHelpers.signal_peer("vu_devant_fenetre")
	var ok: bool = await until(func(): return w.planks() == 6, 30.0, "réparation par le client")
	at.check(ok, "le client a reconstruit la fenêtre (validé par le serveur)")
	await until(func(): return cpd.points - pts0 >= 40, 2.0, "points de réparation")
	at.check(cpd.points - pts0 == 40, "le serveur crédite le client : +%d (4 planches)" % (cpd.points - pts0))
	# Le client s'est reculé pour regarder la fenêtre.
	if not await MpHelpers.wait_peer(self, "recule", 20.0):
		return
	var zid := game.zombies.spawn(MapData.cell_to_world(w.spawn_cells[0]), 0, 150)
	at.check(game.zombies.get_zombie(zid).state == Zombie.State.BARRIER, "zombie de fenêtre côté serveur")
	# Le zombie arrache des planches jusqu'à ce que le client l'ait vu.
	await MpHelpers.wait_peer(self, "arrachage_vu", 30.0)
	game.zombies.despawn(zid)
	await MpHelpers.finish(self)
