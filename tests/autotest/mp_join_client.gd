extends AutotestScenario
## [MP] Client : adresse invalide, serveur injoignable (mauvais port),
## connexion réussie par l'écran REJOINDRE, puis perte de l'hôte.

var PORT := 17811 + MpHelpers.port_offset()


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	var menu: MainMenu = tree().current_scene
	menu.show_screen("multiplayer")
	menu.show_screen("join")
	await frames(3)
	var js := menu.current
	js._ip.text = "300.1.2.3"
	js._join()
	at.check(js._error.text.contains("invalide") and menu.current_name == "join", "adresse invalide refusée : %s" % js._error.text)

	# Mauvais port : personne n'écoute.
	js._ip.text = "127.0.0.1"
	js._port.text = "17899"
	js._join()
	await frames(2)
	at.check(menu.current_name == "connecting" and GameState.state == GameState.State.CONNECTING, "écran « Connexion au serveur... »")
	await seconds(0.5)
	await at.screenshot("connecting")
	var ok: bool = await until(func(): return menu.current_name == "message", Net.CONNECT_TIMEOUT_SEC + 4.0, "message d'erreur")
	if ok:
		var t: String = menu.current.get_child(0).get_child(0).text
		at.check(t in ["Connexion impossible", "Délai dépassé"], "erreur affichée : %s" % t)
		at.check(GameState.state == GameState.State.MAIN_MENU, "retour à MAIN_MENU")
		await at.screenshot("error")
		menu.current.back()
		await frames(3)
	at.check(menu.current_name == "join", "RETOUR ramène à l'écran REJOINDRE")

	# Bon port.
	js = menu.current
	js._ip.text = "127.0.0.1"
	js._port.text = str(PORT)
	js._name.text = "Client"
	js._join()
	ok = await until(func(): return menu.current_name == "lobby", 15.0, "salon")
	if not ok:
		return
	at.check(GameState.state == GameState.State.LOBBY, "connecté : salon, état LOBBY")
	at.check(Settings.last_ip == "127.0.0.1" and Settings.last_port == PORT, "adresse mémorisée")

	# L'hôte ferme : message de déconnexion.
	ok = await until(func(): return menu.current_name == "message", 15.0, "déconnexion détectée")
	if ok:
		var t2: String = menu.current.get_child(0).get_child(0).text
		at.check(t2 == "DÉCONNECTÉ", "message : %s" % t2)
		await at.screenshot("disconnected")
