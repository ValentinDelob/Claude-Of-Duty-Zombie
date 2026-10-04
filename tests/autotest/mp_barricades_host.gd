extends AutotestScenario
## [MP] Hôte : arrache 4 planches d'une fenêtre (diffusion fiable), vérifie
## que la réparation du CLIENT est validée ici (refusée à 1,5 m de la
## barrière, acceptée collé à elle, +10 par planche), puis fait
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
	var client: Player = game.players[client_id]
	# Portée vérifiée par l'hôte : le client, à 1,5 m de la barrière, force
	# une demande de réparation (son invite n'apparaît pas) ; refusée ici.
	if not await MpHelpers.wait_peer(self, "loin_fenetre", 20.0):
		return
	var far := w.global_position + w.inward * (w.barrier_face() + 1.5)
	if not await until(func(): return Vector2(client.srv_origin().x - far.x, client.srv_origin().z - far.z).length() < 0.3, 5.0, "client vu loin de la fenêtre"):
		return
	MpHelpers.signal_peer("vu_loin_fenetre")
	if not await MpHelpers.wait_peer(self, "demande_loin", 20.0):
		return
	await seconds(1.2)  # plus qu'un intervalle de réparation
	at.check(w.planks() == 2 and not w.is_repairing(client_id), "à 1,5 m : réparation du client refusée par l'hôte (%d planches)" % w.planks())
	MpHelpers.signal_peer("refus_loin")
	# Le client avance vers la fenêtre et appuie dès son invite : la demande
	# part avant que l'hôte ne reçoive sa position (en retard), elle doit
	# quand même être acceptée (marge de latence, renvoi tant que [F] tenu).
	if not await MpHelpers.wait_peer(self, "devant_fenetre", 20.0):
		return
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
