extends AutotestScenario
## [MP] Invité : rejoint un salon dont l'hôte a choisi une carte perso, la
## télécharge automatiquement (vérifiée puis mise en cache sous son hash),
## refuse les deux cartes piégées sans les charger ni quitter le salon, reprend
## la bonne carte dans son cache, puis joue sur la même carte que l'hôte.

var PORT := 17941 + MpHelpers.port_offset()


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func run() -> void:
	timeout_sec = 150
	_rm(CustomMapGuard.cache_root())
	var share := Net.map_share
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	var menu: MainMenu = tree().current_scene
	await seconds(3.0)
	GameState.set_state(GameState.State.CONNECTING)
	Net.join("127.0.0.1", PORT, "Client")
	if not await until(func(): return menu.current_name == "lobby", 15.0, "salon de l'invité"):
		return
	if not await until(func(): return share.local_state == "telechargement", 15.0, "téléchargement automatique"):
		return
	var lobby = menu.current
	var sha: String = share.offer.sha
	at.check(Net.lobby_map == EditorMapDef.SHARED_PREFIX + sha or Net.lobby_map == "", "carte du salon : %s" % Net.lobby_map)
	at.check(not CustomMapGuard.is_cached(sha), "pas encore en cache")
	await until(func(): return lobby._map_label.text.contains("ARÈNE PERSO") or lobby._map_label.text.contains("CUSTOM ARENA"), 5.0, "nom de la carte affiché")
	at.check(lobby._map_info.text.contains("Ko") or lobby._map_info.text.contains("KB"), "taille affichée : « %s »" % lobby._map_info.text.replace("\n", " / "))
	at.check(lobby._preview.texture == null, "pas d'aperçu avant la vérification")
	await seconds(1.0)
	await at.screenshot("telechargement")
	if not await until(func(): return share.local_state == "prete", 40.0, "carte reçue et vérifiée"):
		return
	at.check(CustomMapGuard.is_cached(sha) and DirAccess.dir_exists_absolute(CustomMapGuard.cache_root().path_join(sha)), "carte en cache sous son empreinte")
	at.check(lobby._preview.texture != null, "aperçu dessiné depuis la carte vérifiée")
	await at.screenshot("prete")

	# Cartes piégées : refusées, jamais en cache, on reste dans le salon.
	var seen := [sha]
	for want in ["hash", "contenu"]:
		if not await until(func(): return share.local_state == "refusee" and not String(share.offer.get("sha", "")) in seen, 20.0, "carte piégée (%s) refusée" % want):
			return
		var bad: String = share.offer.sha
		seen.append(bad)
		at.check(share.local_reason.contains(CustomMapGuard.reason_text(want)), "raison claire : « %s »" % share.local_reason.replace("\n", " / "))
		at.check(not CustomMapGuard.is_cached(bad), "carte refusée jamais enregistrée")
		at.check(menu.current_name == "lobby" and GameState.state == GameState.State.LOBBY and Game.instance == null, "toujours dans le salon")
		await frames(2)
		at.check(lobby._status.text != "" and lobby._preview.texture == null, "message dans le salon : « %s »" % lobby._status.text.replace("\n", " / "))

	# La bonne carte revient : reprise du cache.
	if not await until(func(): return share.offer.get("sha", "") == sha and share.local_state == "prete", 20.0, "carte reprise du cache"):
		return
	if not await until(func(): return Game.instance != null and Game.instance.players.size() == 2, 40.0, "partie lancée par l'hôte"):
		return
	at.check(Game.instance.local_player.peer_id != 1, "joueur local = invité")
	at.check(Game.instance.map_def.id == EditorMapDef.SHARED_PREFIX + sha, "même carte que l'hôte (%s)" % Game.instance.map_def.id)
	await seconds(3.0)
	await at.screenshot("ingame")
