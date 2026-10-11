extends AutotestScenario
## [MP] Client : adresse invalide, serveur injoignable (mauvais port),
## connexion réussie par REJOINDRE (écran JOUER du hub, vue COOP), puis perte
## de l'hôte.

var PORT := 17811 + MpHelpers.port_offset()


func _join_text(pp: Hub2PlayPanel) -> String:
	return Hub2Ui.button_text(pp.join_button).text


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	var menu: MainMenu = tree().current_scene
	# Écran JOUER du hub, vue COOP (REJOINDRE sur place).
	menu.show_screen("hub", {"screen": "play"})
	await frames(3)
	var pp: Hub2PlayPanel = menu.current.panels.play
	pp.coop_tab.pressed.emit()
	await frames(1)
	pp.address_edit.text = "300.1.2.3"
	pp.join_button.pressed.emit()
	at.check(pp.status_label.text.contains(Lang.t("invalide", "Invalid")) and Net.mode == Net.Mode.NONE, "adresse invalide refusée : %s" % pp.status_label.text)

	# Mauvais port : personne n'écoute.
	pp.address_edit.text = "127.0.0.1:%d" % (17899 + MpHelpers.port_offset())
	pp.join_button.pressed.emit()
	await frames(2)
	at.check(Hub2PlayPanel.connecting() and GameState.state == GameState.State.CONNECTING and _join_text(pp) == "ANNULER",
			"« Connexion à … », bouton ANNULER")
	await seconds(0.5)
	var ok: bool = await until(func(): return GameState.state == GameState.State.MAIN_MENU and Net.mode == Net.Mode.NONE, Net.CONNECT_TIMEOUT_SEC + 4.0, "erreur de connexion")
	if ok:
		await frames(2)
		var t: String = pp.status_label.text
		at.check(t.contains("Connexion impossible") or t.contains("Délai dépassé"), "erreur affichée sur place : %s" % t)
		at.check(menu.current_name == "hub" and pp.view == Hub2PlayPanel.COOP and _join_text(pp) == "REJOINDRE", "toujours dans JOUER, REJOINDRE")

	# Bon port (l'hôte écoute).
	if not await MpHelpers.wait_peer(self, "ecoute", 40.0):
		return
	pp.address_edit.text = "127.0.0.1:%d" % PORT
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
	ok = await until(func(): return pp.view == Hub2PlayPanel.COOP and Net.mode == Net.Mode.NONE, 15.0, "déconnexion détectée")
	if ok:
		await frames(2)
		at.check(pp.status_label.text.begins_with("DÉCONNECTÉ"), "message : %s" % pp.status_label.text)
	await MpHelpers.finish(self)
