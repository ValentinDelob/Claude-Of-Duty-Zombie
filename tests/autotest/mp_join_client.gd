extends AutotestScenario
## [MP] Client : adresse invalide, serveur injoignable (mauvais port),
## connexion réussie par l'écran REJOINDRE, puis perte de l'hôte.

var PORT := 17811 + MpHelpers.port_offset()


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	var menu: MainMenu = tree().current_scene
	# Onglet PARTIE du hub, vue COOP (REJOINDRE sur place, lot E).
	menu.show_screen("hub", {"tab": "play"})
	await frames(3)
	var pp: HubPlayPanel = menu.current.panels.play
	pp.coop_button.pressed.emit()
	pp.ip_edit.text = "300.1.2.3"
	pp.join_button.pressed.emit()
	at.check(pp.status_label.text.contains(Lang.t("invalide", "Invalid")) and Net.mode == Net.Mode.NONE, "adresse invalide refusée : %s" % pp.status_label.text)

	# Mauvais port : personne n'écoute.
	pp.ip_edit.text = "127.0.0.1"
	pp.join_port_edit.text = str(17899 + MpHelpers.port_offset())
	pp.join_button.pressed.emit()
	await frames(2)
	at.check(HubPlayPanel.connecting() and GameState.state == GameState.State.CONNECTING and pp.join_button.label == "ANNULER",
			"« Connexion à … », bouton ANNULER")
	await seconds(0.5)
	await at.screenshot("connecting")
	var ok: bool = await until(func(): return GameState.state == GameState.State.MAIN_MENU and Net.mode == Net.Mode.NONE, Net.CONNECT_TIMEOUT_SEC + 4.0, "erreur de connexion")
	if ok:
		await frames(2)
		var t: String = pp.status_label.text
		at.check(t.begins_with("Connexion impossible") or t.begins_with("Délai dépassé"), "erreur affichée sur place : %s" % t)
		at.check(menu.current_name == "hub" and pp.view == HubPlayPanel.COOP and pp.join_button.label == "REJOINDRE", "toujours dans l'onglet PARTIE, REJOINDRE")
		await at.screenshot("error")

	# Bon port (l'hôte écoute).
	if not await MpHelpers.wait_peer(self, "ecoute", 40.0):
		return
	pp.ip_edit.text = "127.0.0.1"
	pp.join_port_edit.text = str(PORT)
	pp.name_edit.text = "Client"
	# L'hôte se fige 3 s (temps réel) dès qu'il voit ce signal : la connexion
	# doit aboutir quand même (délai de connexion compté aussi en temps réel).
	MpHelpers.signal_peer("bon_port")
	pp.join_button.pressed.emit()
	ok = await until(func(): return MpHelpers.lobby_of(self) != null, 15.0, "salon")
	if not ok:
		return
	at.check(GameState.state == GameState.State.LOBBY, "connecté : salon, état LOBBY")
	at.check(Settings.last_ip == "127.0.0.1" and Settings.last_port == PORT, "adresse mémorisée")
	MpHelpers.signal_peer("salon_vu")

	# L'hôte ferme : message de déconnexion sur place, vue COOP.
	ok = await until(func(): return pp.view == HubPlayPanel.COOP and Net.mode == Net.Mode.NONE, 15.0, "déconnexion détectée")
	if ok:
		await frames(2)
		at.check(pp.status_label.text.begins_with("DÉCONNECTÉ"), "message : %s" % pp.status_label.text)
		await at.screenshot("disconnected")
	await MpHelpers.finish(self)
