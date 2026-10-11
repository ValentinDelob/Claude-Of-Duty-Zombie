extends AutotestScenario
## [MP] Hôte, salon coop du hub v2 (PartieCoop.dc.html) : héberge depuis
## JOUER > COOP, voit l'invité arriver (carte de joueur : niveau, armes de
## départ, PRÊT, ping mesuré et diffusé dans le registre), « 2 joueurs prêts
## sur 2 », lance ; fin de partie (évacuation) -> retour du groupe sur le
## RÉCAPITULATIF, CONTINUER -> JOUER (salon toujours ouvert), LANCER de
## nouveau possible quand l'invité est revenu.

var PORT := 17830 + MpHelpers.port_offset()


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	MpHelpers._clear_sync()
	Settings.hub_v2 = true
	var menu: MainMenu = tree().current_scene
	menu.show_screen("hub2", {"screen": "play"})
	await frames(3)
	var hub: Hub2Screen = menu.current
	var pp: Hub2PlayPanel = hub.panels.play
	pp.coop_tab.pressed.emit()
	pp.port_edit.text = str(PORT)
	pp.name_edit.text = "Hote"
	pp.host_lobby()
	await frames(3)
	at.check(Net.mode == Net.Mode.HOST and pp.view == Hub2PlayPanel.LOBBY, "salon hébergé (hub v2)")
	var lobby := pp.lobby
	if lobby == null:
		return
	MpHelpers.signal_peer("ecoute")
	if not await until(func(): return lobby.cards.size() == 2, 30.0, "invité dans le salon"):
		return
	at.check(String(lobby.cards[1].name) == "Client" and int(lobby.cards[1].lvl) >= 1, "carte de l'invité : %s" % str(lobby.cards[1]))
	# Ping de l'invité mesuré par l'hôte (registre) et affiché.
	var pinged := await until(func(): return Net.players.get(lobby.cards[1].pid, {}).has("ping"), 15.0, "ping de l'invité")
	at.check(pinged, "ping relevé : %s" % str(Net.players.get(lobby.cards[1].pid, {}).get("ping", "?")))
	await until(func(): return String(lobby.cards[1].ping).ends_with(" ms"), 5.0, "ping affiché")
	at.check(String(lobby.cards[1].ping).ends_with(" ms"), "carte : « Niveau N · %s »" % lobby.cards[1].ping)
	await until(func(): return lobby.launch_sub.text == "2 joueurs prêts sur 2", 10.0, "deux joueurs prêts")
	at.check(lobby.launch_sub.text == "2 joueurs prêts sur 2", "LANCER : %s" % lobby.launch_sub.text)
	at.check(not lobby.launch_button.disabled, "LANCER possible")
	if not await MpHelpers.wait_peer(self, "salon_vu", 20.0):
		return
	lobby.launch_button.pressed.emit()
	if not await until(func(): return Game.instance != null and Game.instance.players.size() == 2, 25.0, "les deux joueurs en jeu"):
		return
	Game.instance.rounds.paused = true
	await seconds(1.0)
	Game.instance.srv_end_match(true)
	# Retour du groupe au salon : récapitulatif d'abord.
	if not await until(func(): return _hub2_screen() == "recap", 40.0, "récapitulatif au retour"):
		return
	at.check(Net.mode == Net.Mode.HOST and GameState.state == GameState.State.LOBBY, "salon toujours ouvert")
	hub = (tree().current_scene as MainMenu).current
	var rp: Hub2RecapPanel = hub.panels.recap
	rp.finish()
	rp.continue_button.pressed.emit()
	at.check(hub.current_id == "play", "CONTINUER en coop : JOUER (salon)")
	pp = hub.panels.play
	if not await until(func(): return pp.lobby != null and not pp.lobby.launch_button.disabled, 30.0, "invité revenu : LANCER possible"):
		return
	at.check(pp.lobby.launch_sub.text == "2 joueurs prêts sur 2", "après la partie : %s" % pp.lobby.launch_sub.text)
	MpHelpers.signal_peer("retour_vu")
	Settings.hub_v2 = false
	await MpHelpers.finish(self)


func _hub2_screen() -> String:
	var s := tree().current_scene
	if s is MainMenu and (s as MainMenu).current is Hub2Screen:
		return ((s as MainMenu).current as Hub2Screen).current_id
	return ""
