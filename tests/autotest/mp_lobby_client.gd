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
	var ok: bool = await until(func(): return MpHelpers.lobby_of(self) != null, 15.0, "salon client (écran JOUER du hub)")
	if not ok:
		return
	at.check(GameState.state == GameState.State.LOBBY and menu.current.current_id == "play", "état LOBBY côté client, écran JOUER")
	var lobby := MpHelpers.lobby_of(self)
	at.check(not lobby.is_host and lobby.change_button == null and lobby.launch_button.disabled, "invité : ni CHANGER DE CARTE ni LANCER")
	# La carte de l'hôte (BUNKER K-7) s'affiche dans le salon du client.
	ok = await until(func(): return Net.lobby_map == "bunker_k7" and lobby.map_title.text.to_upper().contains("BUNKER K-7"), 15.0, "carte annoncée par l'hôte")
	if ok:
		at.check(true, "carte de l'hôte affichée : %s" % lobby.map_title.text)
	ok = await until(func(): return lobby.cards.size() == 2 and String(lobby.cards[0].name) == "Hote", 5.0, "hôte dans la liste")
	at.check(ok, "liste du salon de l'invité : %s" % ", ".join(MpHelpers.player_lines(lobby)))
	await at.screenshot("lobby")
	MpHelpers.signal_peer("carte_vue")
	ok = await until(func(): return Game.instance != null and Game.instance.players.size() == 2, 40.0, "partie lancée par l'hôte")
	if not ok:
		return
	at.check(Game.instance.local_player.peer_id != 1, "joueur local = client")
	at.check(Game.instance.map_def.id == "bunker_k7", "même carte que l'hôte (BUNKER K-7)")
	# Une seconde de partie avant la capture (et sans erreur de script).
	await seconds(1.0)
	await at.screenshot("ingame")
	await MpHelpers.finish(self)
