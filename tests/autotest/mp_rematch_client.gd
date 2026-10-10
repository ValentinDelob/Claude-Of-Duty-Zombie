extends AutotestScenario
## [MP] Invité : deux parties d'affilée avec le même hôte. Après chaque
## GAME OVER, retour au SALON (pas au menu principal), toujours connecté avec
## le même identifiant de pair, carte perso de l'hôte reprise du cache, choix
## de personnage gardé ; la seconde partie repart d'un état neuf.

var PORT := 17821 + MpHelpers.port_offset()


func _in_lobby() -> bool:
	var s := tree().current_scene
	return s is MainMenu and (s as MainMenu).current_name == "lobby" and GameState.state == GameState.State.LOBBY


func _in_game() -> bool:
	return Game.instance != null and Game.instance.players.size() == 2 and Game.instance.local_player != null \
		and GameState.state == GameState.State.PLAYING


func _check_lobby(n: int, my_id: int, ids: Array) -> void:
	at.check(Net.mode == Net.Mode.CLIENT and Net.local_id() == my_id, "retour %d : toujours connecté, même pair (%d)" % [n, Net.local_id()])
	var keys := Net.players.keys()
	keys.sort()
	at.check(keys == ids, "retour %d : même groupe (%s)" % [n, str(keys)])
	at.check(Net.multiplayer.multiplayer_peer is ENetMultiplayerPeer and Array(Net.multiplayer.get_peers()) == [1], "retour %d : connexion ENet gardée" % n)
	var lobby = tree().current_scene.current
	at.check(not lobby.is_host and Game.instance == null and Net.cast.is_empty() and Net.current_map == "", "retour %d : salon de l'invité, partie oubliée" % n)
	at.check(Net.lobby_map.begins_with(EditorMapDef.SHARED_PREFIX), "retour %d : carte du salon gardée (%s)" % [n, Net.lobby_map.substr(0, 20)])


func run() -> void:
	timeout_sec = 200
	# Choix de personnage de l'invité (pas « auto ») : gardé d'une partie à l'autre.
	Settings.character = "orlov"
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	if not await MpHelpers.wait_peer(self, "ecoute", 40.0):
		return
	GameState.set_state(GameState.State.CONNECTING)
	Net.join("127.0.0.1", PORT, "Client")
	if not await until(_in_lobby, 30.0, "salon rejoint"):
		return
	if not await until(func(): return Net.map_share.local_state == "prete", 40.0, "carte perso de l'hôte reçue"):
		return
	var my_id := Net.local_id()
	var ids := Net.players.keys()
	ids.sort()
	MpHelpers.signal_peer("salon")
	for n in [1, 2]:
		if not await until(_in_game, 60.0, "partie %d rejointe" % n):
			return
		var game := Game.instance
		var pd := game.session.local_data()
		at.check(Net.local_id() == my_id and pd.points == PlayerData.STARTING_POINTS and pd.grenades == ThrowableRules.FRAG_START,
			"partie %d : même pair, état neuf (%d points)" % [n, pd.points])
		at.check(game.map_def.id == Net.lobby_map and CustomMapGuard.is_cached(game.map_def.id.trim_prefix(EditorMapDef.SHARED_PREFIX)),
			"partie %d : carte perso du cache" % n)
		at.check(Net.cast.get(my_id, -1) == CharacterDB.IDS.find("orlov"), "partie %d : personnage choisi (%s)" % [n, str(Net.cast.get(my_id))])
		MpHelpers.signal_peer("en_jeu%d" % n)
		if not await until(func(): return GameState.state == GameState.State.GAME_OVER, 40.0, "GAME OVER %d" % n):
			return
		if not await until(_in_lobby, Game.GAME_OVER_DELAY + 15.0, "retour au salon après la partie %d" % n):
			return
		_check_lobby(n, my_id, ids)
		if not await until(func(): return Net.map_share.local_state == "prete", 20.0, "carte toujours prête au salon"):
			return
		if n == 1:
			await seconds(1.0)
			await at.screenshot("lobby_after_game")
		MpHelpers.signal_peer("salon%d" % n)
		if n == 1 and not await MpHelpers.wait_peer(self, "salon1", 30.0):
			return
	await MpHelpers.finish(self)
