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
	await seconds(3.0)
	for i in 4:
		w.srv_tear()
		await seconds(0.3)
	at.check(w.planks() == 2, "4 planches arrachées côté serveur")
	var pts0 := cpd.points
	var ok: bool = await until(func(): return w.planks() == 6, 30.0, "réparation par le client")
	at.check(ok, "le client a reconstruit la fenêtre (validé par le serveur)")
	await seconds(0.3)
	at.check(cpd.points - pts0 == 40, "le serveur crédite le client : +%d (4 planches)" % (cpd.points - pts0))
	await seconds(1.0)
	var zid := game.zombies.spawn(MapData.cell_to_world(w.spawn_cells[0]), 0, 150)
	at.check(game.zombies.get_zombie(zid).state == Zombie.State.BARRIER, "zombie de fenêtre côté serveur")
	await seconds(6.0)
	game.zombies.despawn(zid)
	await seconds(2.0)
