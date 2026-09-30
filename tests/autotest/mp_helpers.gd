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


static func port_offset() -> int:
	return OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()


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
	if not await sc.until(func(): return Net.players.size() >= 2, 40.0, "client connecté"):
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
	if not await sc.until(func(): return Net.players.size() >= 2 and GameState.state == GameState.State.LOBBY, 30.0, "salon rejoint"):
		return false
	signal_peer("salon")
	return await sc.until(func(): return Game.instance != null and Game.instance.players.size() >= 2 and Game.instance.local_player != null, 45.0, "partie rejointe")
