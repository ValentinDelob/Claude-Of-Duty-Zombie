extends AutotestScenario
## [MP] Soak, côté client (voir mp_soak_host.gd) : joue les manches 1 à 3 en
## abattant les marionnettes, quitte par le menu pause, puis essaie de
## revenir dans la partie en cours : refus lisible, retour au menu.

const PORT := 17845
const Soak := preload("res://tests/autotest/long_soak.gd")


func run() -> void:
	timeout_sec = 400
	var log := Soak.SoakLogger.new()
	OS.add_logger(log)
	if not await MpHelpers.join_game(self, PORT):
		OS.remove_logger(log)
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var t := 0.0
	var bad := 0
	while not MpHelpers.peer_reached("manche3") and t < 330.0:
		var z := nearest_visible(game, p)
		if z:
			AutotestHelpers.aim_at(p, z.head_position())
			p.input.fire = Soak.trigger(p, pd)
		else:
			p.input.fire = false
		# Invariants vus par le client (valeurs répliquées).
		if pd.points < 0 or not is_finite(p.global_position.x) or not is_finite(p.global_position.z):
			bad += 1
		for w: Dictionary in pd.weapons:
			var s := WeaponDB.stats(w.id, w.pap)
			if int(w.mag) > int(s.mag) or int(w.reserve) > int(s.reserve):
				bad += 1
		await seconds(0.1)
		t += 0.1
	p.input.fire = false
	at.check(MpHelpers.peer_reached("manche3"), "manches 1 à 3 jouées à deux (%.0f s)" % t)
	at.check(pd.kills > 0, "zombies abattus par le client (%d, %d points)" % [pd.kills, pd.points])
	at.check(bad == 0, "points, munitions et position toujours valides côté client (%d écarts)" % bad)
	# Départ par le menu pause.
	game.hud.pause_menu.open()
	await seconds(0.3)  # menu ouvert, la partie continue
	game.hud.pause_menu._leave()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu" and Game.instance == null, 10.0, "retour au menu")
	at.check(Net.mode == Net.Mode.NONE, "session fermée côté client")
	MpHelpers.signal_peer("depart")
	if not await MpHelpers.wait_peer(self, "parti_vu", 60.0):
		OS.remove_logger(log)
		return
	# Retour dans la partie en cours : refusé (BO1 : pas d'arrivée en cours).
	var errors: Array = []
	Net.connection_error.connect(func(title: String, msg: String): errors.append([title, msg]))
	GameState.set_state(GameState.State.CONNECTING)
	Net.join("127.0.0.1", PORT + MpHelpers.port_offset(), "Client")
	await until(func(): return not errors.is_empty(), 20.0, "refus du serveur")
	var msg: String = errors[0][1] if not errors.is_empty() else ""
	at.check(msg == Lang.t("La partie a déjà commencé.", "The game has already started."), "retour refusé, message dans la langue du joueur : « %s »" % msg)
	await until(func(): return GameState.state == GameState.State.MAIN_MENU and Net.mode == Net.Mode.NONE, 10.0, "retour à l'écran d'accueil")
	at.check(Game.instance == null and GameState.state == GameState.State.MAIN_MENU, "reste au menu, sans partie (%s)" % GameState.State.keys()[GameState.state])
	MpHelpers.signal_peer("refus_vu")
	await frames(2)
	OS.remove_logger(log)
	var errs := log.snapshot()
	for l in errs.slice(0, 20):
		print("[soak] journal : " + l)
	at.check(errs.is_empty(), "aucune erreur ni avertissement du moteur chez le client (%d)" % errs.size())
	await MpHelpers.finish(self)


func nearest_visible(game: Game, p: Player) -> Zombie:
	var best: Zombie = null
	var best_d := 40.0
	var space := p.get_world_3d().direct_space_state
	for z: Zombie in game.zombies.alive:
		if z.state == Zombie.State.EMERGE:
			continue
		var d := z.global_position.distance_to(p.global_position)
		if d < best_d:
			var q := PhysicsRayQueryParameters3D.create(p.eye_position(), z.head_position(), 1)
			if space.intersect_ray(q).is_empty():
				best = z
				best_d = d
	return best
