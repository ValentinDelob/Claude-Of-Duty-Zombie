extends AutotestScenario
## @temps-reel : reste en temps réel (mélange de minuteurs réseau réels et de temps de jeu, à revoir : docs/TESTING_PLAN.md).
## [MP] Hôte : crée la partie depuis le menu, attend le client dans le salon,
## lance la partie, vérifie que les deux joueurs sont en jeu.

var PORT := 17810 + MpHelpers.port_offset()


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	var menu: MainMenu = tree().current_scene
	menu.show_screen("host")
	await frames(3)
	var host_screen := menu.current
	host_screen._port.text = str(PORT)
	host_screen._name.text = "Hote"
	host_screen._create()
	await frames(3)
	at.check(Net.mode == Net.Mode.HOST and GameState.state == GameState.State.LOBBY, "partie hébergée, état LOBBY")
	at.check(menu.current_name == "lobby", "écran du salon")
	var ok: bool = await until(func(): return Net.players.size() == 2, 30.0, "arrivée du client")
	if not ok:
		return
	await seconds(0.5)
	var lobby := menu.current
	var names := []
	for l in lobby._list.get_children():
		names.append(l.text)
	at.check(names.size() == Net.max_players and names[0].contains("Hote") and names[1].contains("Client"), "liste du salon : %s" % ", ".join(names))
	# Choix de la carte par l'hôte : ► passe de BUNKER K-7 à KINO.
	at.check(lobby.map_row != null and lobby.map_id == "bunker_k7", "carte par défaut : %s" % lobby.map_id)
	lobby.map_row.nudge(1)
	await seconds(0.5)
	at.check(lobby.map_id == "kino" and Net.lobby_map == "kino" and Settings.last_map == "kino", "carte KINO choisie et annoncée (%s)" % Net.lobby_map)
	await at.screenshot("lobby")
	# Le client confirme l'affichage de la carte avant le lancement.
	await seconds(1.5)
	lobby._on_start()
	ok = await until(func(): return Game.instance != null and Game.instance.players.size() == 2, 20.0, "les deux joueurs en jeu")
	if not ok:
		return
	at.check(Game.instance.local_player.peer_id == 1, "joueur local = hôte")
	at.check(Game.instance.map_def.id == "kino", "partie lancée sur KINO")
	at.check(GameState.state == GameState.State.PLAYING, "état PLAYING")
	Game.instance.rounds.paused = true
	await seconds(4.0)
	await at.screenshot("ingame")
