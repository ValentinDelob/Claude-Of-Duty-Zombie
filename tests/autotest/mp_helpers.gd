class_name MpHelpers
extends RefCounted
## Démarrage des tests multijoueur (hôte / client) jusqu'à la partie, et
## rendez-vous entre les deux processus.
## AUTOTEST_PORT_OFFSET décale les ports (plusieurs copies du dépôt en parallèle).
##
## Rendez-vous : jamais de délai fixe pour attendre l'autre jeu (il tourne à
## son propre rythme, surtout en temps accéléré). Chaque côté annonce une
## étape par un fichier (`signal_peer`) que l'autre attend (`wait_peer`), dans
## un dossier propre à la paire : tests/_out/mp_sync/<MP_SYNC_ID>, vidé par
## tools/mp_test.sh avant de lancer les deux jeux (hors mp_test.sh : dossier
## « <test>_<décalage> », vidé par l'hôte au démarrage).


## Tentatives de connexion du client (join_game) avant d'abandonner.
const JOIN_TRIES := 4


static func port_offset() -> int:
	return OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()


## Salon affiché dans l'écran JOUER du hub (Hub2LobbyView), null s'il n'est
## pas à l'écran (le salon n'est pas un écran à part : HUB_PLAN §9).
static func lobby_of(sc: AutotestScenario) -> Hub2LobbyView:
	var s := sc.tree().current_scene as MainMenu
	if s == null or s.current_name != "hub" or not (s.current is Hub2Screen):
		return null
	var hub := s.current as Hub2Screen
	if hub.current_id != "play":
		return null
	var p := hub.panels.get("play") as Hub2PlayPanel
	return p.lobby if p != null and p.view == Hub2PlayPanel.LOBBY and is_instance_valid(p.lobby) else null


## Hôte : HÉBERGER depuis l'écran JOUER du hub (vue COOP, port, nom), comme
## au clavier ; rend le salon affiché (null en cas d'échec).
static func host_from_hub(sc: AutotestScenario, port: int, nickname := "Hote") -> Hub2LobbyView:
	var menu := sc.tree().current_scene as MainMenu
	menu.show_screen("hub", {"screen": "play"})
	await sc.frames(3)
	var pp := (menu.current as Hub2Screen).panels.play as Hub2PlayPanel
	pp.coop_tab.pressed.emit()
	pp.port_edit.text = str(port)
	pp.name_edit.text = nickname
	pp.host_button.pressed.emit()
	await sc.frames(3)
	return lobby_of(sc)


## Écran du hub affiché ("" : pas au hub).
static func hub_screen(sc: AutotestScenario) -> String:
	var s := sc.tree().current_scene as MainMenu
	if s == null or not (s.current is Hub2Screen):
		return ""
	return (s.current as Hub2Screen).current_id


## Retour d'une partie multijoueur : le groupe revient sur le
## RÉCAPITULATIF ; CONTINUER (animation terminée d'abord) mène au salon
## (JOUER). Rend le récapitulatif vu (null : pas de récapitulatif ou pas de
## salon ensuite, l'échec est noté).
static func through_recap(sc: AutotestScenario, timeout := 40.0) -> Hub2RecapPanel:
	if not await sc.until(func(): return hub_screen(sc) == "recap", timeout, "récapitulatif au retour au salon"):
		return null
	var hub := (sc.tree().current_scene as MainMenu).current as Hub2Screen
	var rp := hub.panels.get("recap") as Hub2RecapPanel
	rp.finish()
	rp.continue_button.pressed.emit()
	if not await sc.until(func(): return lobby_of(sc) != null, 10.0, "CONTINUER : salon (JOUER)"):
		return null
	return rp


## Joueurs du salon en lignes « Nom NIV.n » (cartes de Hub2LobbyView).
static func player_lines(lobby: Hub2LobbyView) -> PackedStringArray:
	var out := PackedStringArray()
	for c in lobby.cards:
		out.append("%s NIV.%d" % [String(c.name), int(c.lvl)])
	return out


## « host » ou « client » (d'après le nom du scénario : mp_<test>_host / _client).
static func side() -> String:
	return "host" if Autotest.scenario_name.ends_with("_host") else "client"


static func _other() -> String:
	return "client" if side() == "host" else "host"


static func sync_dir() -> String:
	var id := OS.get_environment("MP_SYNC_ID")
	if id == "":
		var test := Autotest.scenario_name.trim_prefix("mp_").trim_suffix("_host").trim_suffix("_client")
		id = "%s_%d" % [test, port_offset()]
	return ProjectSettings.globalize_path("res://tests/_out/mp_sync").path_join(id)


## Vide le dossier de rendez-vous (hôte lancé à la main, sans mp_test.sh).
static func _clear_sync() -> void:
	if OS.get_environment("MP_SYNC_ID") != "":
		return
	var d := sync_dir()
	if DirAccess.dir_exists_absolute(d):
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))


## Annonce à l'autre jeu que l'étape `step` est atteinte.
static func signal_peer(step: String) -> void:
	var d := sync_dir()
	DirAccess.make_dir_recursive_absolute(d)
	var f := FileAccess.open(d.path_join("%s_%s" % [side(), step]), FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_ticks_msec()))
		f.close()


## L'autre jeu a-t-il annoncé l'étape `step` ?
static func peer_reached(step: String) -> bool:
	return FileAccess.file_exists(sync_dir().path_join("%s_%s" % [_other(), step]))


## Attend que l'autre jeu annonce l'étape `step` (échec après `limit` s).
static func wait_peer(sc: AutotestScenario, step: String, limit: float) -> bool:
	return await sc.until(func(): return peer_reached(step), limit, "l'autre jeu (%s) : étape « %s »" % [_other(), step])


## Fin du test : annonce la fin puis attend celle de l'autre jeu, pour
## qu'aucun des deux ne quitte (et ne coupe la connexion) pendant que l'autre
## vérifie encore quelque chose. Remplace les longues attentes finales.
static func finish(sc: AutotestScenario, limit := 60.0) -> void:
	signal_peer("fin")
	await wait_peer(sc, "fin", limit)


static func host_game(sc: AutotestScenario, port: int, map_id := "test_arena") -> bool:
	await sc.until(func(): return sc.tree().current_scene != null and sc.tree().current_scene.name == "MainMenu", 5.0, "menu")
	_clear_sync()
	if Net.host(port + port_offset(), 4, "Hote") != OK:
		sc.at.fail("impossible d'héberger sur le port %d" % (port + port_offset()))
		return false
	GameState.set_state(GameState.State.LOBBY)
	signal_peer("ecoute")
	if not await sc.until(func(): return Net.players.size() >= 2, 60.0, "client connecté"):
		return false
	# Le client a reçu la liste des joueurs (salon prêt) avant le lancement.
	if not await wait_peer(sc, "salon", 20.0):
		return false
	Net.start_match(map_id)
	return await sc.until(func(): return Game.instance != null and Game.instance.players.size() >= 2 and Game.instance.local_player != null, 25.0, "partie lancée")


static func join_game(sc: AutotestScenario, port: int) -> bool:
	await sc.until(func(): return sc.tree().current_scene != null and sc.tree().current_scene.name == "MainMenu", 5.0, "menu")
	# L'hôte écoute (au lieu d'un délai fixe) : sinon la connexion attendrait
	# son délai d'expiration.
	if not await wait_peer(sc, "ecoute", 40.0):
		return false
	GameState.set_state(GameState.State.CONNECTING)
	Net.join("127.0.0.1", port + port_offset(), "Client")
	# Tentative abandonnée (délai dépassé : machine très chargée, hôte figé
	# plusieurs secondes) : on recommence, comme un joueur qui réessaie.
	var tries := [1]
	var joined := func() -> bool:
		if Net.players.size() >= 2 and GameState.state == GameState.State.LOBBY:
			return true
		if Net.mode == Net.Mode.NONE and tries[0] < JOIN_TRIES:
			tries[0] += 1
			print("[autotest] connexion abandonnée, nouvelle tentative (%d/%d)" % [tries[0], JOIN_TRIES])
			GameState.set_state(GameState.State.CONNECTING)
			Net.join("127.0.0.1", port + port_offset(), "Client")
		return false
	if not await sc.until(joined, 45.0, "salon rejoint"):
		return false
	signal_peer("salon")
	return await sc.until(func(): return Game.instance != null and Game.instance.players.size() >= 2 and Game.instance.local_player != null, 45.0, "partie rejointe")
