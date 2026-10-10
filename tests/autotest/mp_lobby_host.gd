extends AutotestScenario
## [MP] Hôte : crée la partie depuis le menu, attend le client dans le salon,
## lance la partie, vérifie que les deux joueurs sont en jeu.

var PORT := 17810 + MpHelpers.port_offset()


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	MpHelpers._clear_sync()
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
	MpHelpers.signal_peer("ecoute")
	var ok: bool = await until(func(): return Net.players.size() == 2, 30.0, "arrivée du client")
	if not ok:
		return
	var lobby := menu.current
	var names := []
	var read_names := func():
		names.clear()
		for l in lobby._list.get_children():
			names.append(l.text)
		return names.size() == Net.max_players and names[0].contains("Hote") and names[1].contains("Client")
	await until(read_names, 3.0, "client dans la liste du salon")
	at.check(read_names.call(), "liste du salon : %s" % ", ".join(names))
	# Carte de l'hôte : BUNKER K-7 (seule carte du jeu depuis le retrait de
	# KINO), annoncée au client.
	at.check(lobby.map_row != null and lobby.map_id == "bunker_k7", "carte par défaut : %s" % lobby.map_id)
	await until(func(): return Net.lobby_map == "bunker_k7", 3.0, "carte BUNKER K-7 annoncée")
	at.check(Net.lobby_map == "bunker_k7", "carte BUNKER K-7 annoncée (%s)" % Net.lobby_map)
	await at.screenshot("lobby")
	# Le client confirme l'affichage de la carte avant le lancement.
	if not await MpHelpers.wait_peer(self, "carte_vue", 20.0):
		return
	lobby._on_start()
	ok = await until(func(): return Game.instance != null and Game.instance.players.size() == 2, 20.0, "les deux joueurs en jeu")
	if not ok:
		return
	at.check(Game.instance.local_player.peer_id == 1, "joueur local = hôte")
	at.check(Game.instance.map_def.id == "bunker_k7", "partie lancée sur BUNKER K-7")
	at.check(GameState.state == GameState.State.PLAYING, "état PLAYING")
	Game.instance.rounds.paused = true
	await at.screenshot("ingame")
	await MpHelpers.finish(self)
