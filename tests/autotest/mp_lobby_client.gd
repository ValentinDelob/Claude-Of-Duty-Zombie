extends AutotestScenario
## [MP] Client : rejoint 127.0.0.1, voit le salon, attend le lancement.

var PORT := 17810 + MpHelpers.port_offset()


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	var menu: MainMenu = tree().current_scene
	if not await MpHelpers.wait_peer(self, "ecoute", 40.0):
		return
	GameState.set_state(GameState.State.CONNECTING)
	Net.join("127.0.0.1", PORT, "Client")
	var ok: bool = await until(func(): return menu.current_name == "lobby", 15.0, "salon client")
	if not ok:
		return
	at.check(GameState.state == GameState.State.LOBBY, "état LOBBY côté client")
	# La carte choisie par l'hôte (KINO) s'affiche dans le salon du client.
	ok = await until(func(): return Net.lobby_map == "kino" and menu.current._map_label.text.contains("KINO"), 15.0, "carte annoncée par l'hôte")
	if ok:
		at.check(true, "carte de l'hôte affichée : %s" % menu.current._map_label.text)
	await at.screenshot("lobby")
	MpHelpers.signal_peer("carte_vue")
	ok = await until(func(): return Game.instance != null and Game.instance.players.size() == 2, 40.0, "partie lancée par l'hôte")
	if not ok:
		return
	at.check(Game.instance.local_player.peer_id != 1, "joueur local = client")
	at.check(Game.instance.map_def.id == "kino", "même carte que l'hôte (KINO)")
	# Une seconde de partie avant la capture (et sans erreur de script).
	await seconds(1.0)
	await at.screenshot("ingame")
	await MpHelpers.finish(self)
