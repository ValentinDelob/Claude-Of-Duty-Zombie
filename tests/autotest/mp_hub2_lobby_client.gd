extends AutotestScenario
## [MP] Invité, salon coop du hub v2 : rejoint depuis JOUER > COOP
## (adresse « IP:port »), voit le salon de l'hôte (« Salon de Hote »,
## « Tu as rejoint », deux cartes, son propre ping reçu de l'hôte), LANCER
## grisé ; partie lancée par l'hôte, fin -> RÉCAPITULATIF, CONTINUER ->
## JOUER (salon).

var PORT := 17830 + MpHelpers.port_offset()


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	Settings.hub_v2 = true
	var menu: MainMenu = tree().current_scene
	menu.show_screen("hub2", {"screen": "play"})
	await frames(3)
	var hub: Hub2Screen = menu.current
	var pp: Hub2PlayPanel = hub.panels.play
	pp.coop_tab.pressed.emit()
	if not await MpHelpers.wait_peer(self, "ecoute", 40.0):
		return
	pp.name_edit.text = "Client"
	pp.address_edit.text = "127.0.0.1:%d" % PORT
	pp.join_or_cancel()
	if not await until(func(): return pp.lobby != null, 15.0, "salon de l'invité (hub v2)"):
		return
	var lobby := pp.lobby
	at.check(not lobby.is_host and lobby.change_button == null and lobby.launch_button.disabled, "invité : ni CHANGER DE CARTE, LANCER grisé")
	await until(func(): return lobby.cards.size() == 2, 10.0, "deux joueurs")
	at.check(lobby.cards.size() == 2 and bool(lobby.cards[0].host), "hôte en premier")
	var me: Dictionary = lobby.cards[1]
	at.check(bool(me.me), "ma carte")
	if not await until(func(): return String(lobby.cards[1].ping).ends_with(" ms"), 15.0, "mon ping reçu de l'hôte"):
		return
	at.check(true, "ping reçu : %s" % lobby.cards[1].ping)
	await until(func(): return Net.lobby_map == "bunker_k7", 10.0, "carte annoncée")
	at.check(lobby.map_title.text == "Bunker K-7", "carte de l'hôte : %s" % lobby.map_title.text)
	MpHelpers.signal_peer("salon_vu")
	if not await until(func(): return Game.instance != null and Game.instance.players.size() == 2, 40.0, "partie lancée par l'hôte"):
		return
	if not await until(func(): return _hub2_screen() == "recap", 40.0, "récapitulatif au retour"):
		return
	at.check(Net.mode == Net.Mode.CLIENT and GameState.state == GameState.State.LOBBY, "toujours dans le groupe")
	hub = (tree().current_scene as MainMenu).current
	var rp: Hub2RecapPanel = hub.panels.recap
	at.check(rp.model.evacuated, "ÉVACUÉ")
	rp.finish()
	rp.continue_button.pressed.emit()
	at.check(hub.current_id == "play" and (hub.panels.play as Hub2PlayPanel).view == Hub2PlayPanel.LOBBY, "CONTINUER : salon")
	await MpHelpers.wait_peer(self, "retour_vu", 30.0)
	Settings.hub_v2 = false
	await MpHelpers.finish(self)


func _hub2_screen() -> String:
	var s := tree().current_scene
	if s is MainMenu and (s as MainMenu).current is Hub2Screen:
		return ((s as MainMenu).current as Hub2Screen).current_id
	return ""
