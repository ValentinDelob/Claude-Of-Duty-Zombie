extends AutotestScenario
## [MP] Client : mort -> spectateur de l'hôte ; réapparition -> sa propre vue ;
## l'hôte quitte -> retour au menu avec « Connexion perdue avec l'hôte ».

const PORT := 17815


func run() -> void:
	timeout_sec = 100
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var pd := game.session.local_data()
	await until(func(): return pd.life == PlayerData.Life.DEAD, 20.0, "mort")
	var host: Player = game.players.get(1)
	await until(func(): return game.spectating == host and host.camera.current, 3.0, "vue de l'hôte")
	at.check(game.spectating == host and host.camera.current, "spectateur : vue de l'hôte")
	at.check(game.hud._spectate_label.text.begins_with(Lang.t("SPECTATEUR", "SPECTATING")), "HUD : %s" % game.hud._spectate_label.text)
	await at.screenshot("spectating")
	MpHelpers.signal_peer("spectateur")
	await until(func(): return pd.life == PlayerData.Life.ALIVE, 15.0, "réapparition")
	await until(func(): return game.spectating == null and game.local_player.camera.current, 2.0, "retour à sa vue")
	at.check(game.spectating == null and game.local_player.camera.current, "de retour dans sa propre vue")
	MpHelpers.signal_peer("revenu")
	var ok: bool = await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 20.0, "retour au menu")
	if ok:
		await frames(5)
		var menu: MainMenu = tree().current_scene
		at.check(menu.current_name == "message", "écran de message")
		var body: String = menu.current.get_child(0).get_child(1).text if menu.current_name == "message" else ""
		at.check(body.contains(Lang.t("Connexion perdue", "Connection to the host lost")), "message : %s" % body)
		await at.screenshot("host_lost")
	await MpHelpers.finish(self)
