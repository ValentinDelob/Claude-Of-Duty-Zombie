extends AutotestScenario
## @temps-reel : transfert de carte cadencé par seconde réelle, reste en temps réel.
## [MP] Hôte : choisit une carte perso dans le salon AVANT l'arrivée de
## l'invité (il la reçoit en arrivant), DÉMARRER grisé pendant le
## téléchargement (lent, en morceaux de 1 Ko, pour la capture du salon), puis
## deux cartes piégées (morceau corrompu : empreinte fausse ; empreinte juste
## mais type d'objet interdit) : l'invité les refuse et la partie ne peut pas
## démarrer ; retour à la bonne carte : l'invité la reprend dans son cache
## sans la retélécharger ; la partie démarre, les deux joueurs sur la même carte.

var PORT := 17941 + MpHelpers.port_offset()


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _client_id() -> int:
	for pid in Net.players:
		if pid != 1:
			return pid
	return 0


func _client_state() -> Dictionary:
	return Net.map_share.states.get(_client_id(), {})


func run() -> void:
	timeout_sec = 150
	# Carte perso du joueur : DRAFT ARENA renommée, dans le dossier des cartes
	# du scénario (jamais celui du joueur) ; caches vidés.
	_rm(EditorMap.maps_root())
	_rm(CustomMapGuard.cache_root())
	var m := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m.carte["id"] = "arene_perso"
	m.carte["nom"] = {"fr": "ARÈNE PERSO", "en": "CUSTOM ARENA"}
	# Format 20 : carte d'avant (format 19) hors de la grille des cubes (plafond
	# de l'entrepôt à 6,81 m) : l'hôte la convertit et envoie le texte migré.
	m.find("p3")["plafond"] = 6.81
	at.check(m.save_dir(EditorMap.map_dir("arene_perso")) == OK, "carte perso enregistrée")
	var cpath := EditorMap.map_dir("arene_perso").path_join("carte.json")
	var ctext := FileAccess.get_file_as_string(cpath).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 19")
	var cf := FileAccess.open(cpath, FileAccess.WRITE)
	cf.store_string(ctext)
	cf.close()
	at.check(EditorMap.load_dir(EditorMap.map_dir("arene_perso")).cube_changes == 1, "carte d'avant : une valeur hors de la grille")
	var share := Net.map_share
	share.test_chunk_size = 1024
	share.test_chunks_per_sec = 1.2
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	var menu: MainMenu = tree().current_scene
	menu.show_screen("host")
	await frames(3)
	menu.current._port.text = str(PORT)
	menu.current._name.text = "Hote"
	MpHelpers._clear_sync()
	menu.current._create()
	await frames(3)
	var lobby = menu.current
	at.check(menu.current_name == "lobby", "salon de l'hôte")
	var idx: int = lobby.map_ids.find("perso:arene_perso")
	at.check(idx >= Game.MENU_MAPS.size(), "carte perso proposée dans le salon (%d)" % idx)
	# ► jusqu'à la carte perso (comme au clavier).
	while lobby.map_row.index() != idx:
		lobby.map_row.nudge(1)
	var sha: String = share.offer.get("sha", "")
	at.check(Net.lobby_map == EditorMapDef.SHARED_PREFIX + sha and CustomMapGuard.is_cached(sha), "carte annoncée « partage:%s », dans le cache de l'hôte" % sha.substr(0, 12))
	at.check(share.offer.chunks >= 3, "carte en %d morceaux" % share.offer.chunks)
	# Paquet envoyé : le texte migré (format 20, plafond au cube), canonique.
	if CustomMapGuard.is_cached(sha):
		var sent := EditorMap.load_dir(CustomMapGuard.cache_dir(sha))
		at.check(sent.format_read == EditorMap.FORMAT and sent.cube_changes == 0 and is_equal_approx(EditorMap.room_ceiling(sent.find("p3")), 6.8),
			"carte envoyée au format %d, sur la grille (plafond %s)" % [sent.format_read, EditorMap.room_ceiling(sent.find("p3"))])
	# Le fichier du joueur n'est pas réécrit par le salon.
	at.check(FileAccess.get_file_as_string(cpath).contains("\"format\": 19"), "carte du dossier non réécrite")
	at.check(not lobby._start.disabled, "seul dans le salon : DÉMARRER possible")
	# Carte choisie : l'invité peut arriver.
	MpHelpers.signal_peer("ecoute")
	# L'invité arrive : il reçoit la carte.
	if not await until(func(): return Net.players.size() == 2, 30.0, "arrivée de l'invité"):
		return
	if not await until(func(): return _client_state().get("etat") == "telechargement" and int(_client_state().get("pct", 0)) >= 40, 20.0, "téléchargement en cours"):
		return
	await frames(2)
	at.check(lobby._start.disabled and lobby._status.text != "", "DÉMARRER grisé pendant le téléchargement : « %s »" % lobby._status.text)
	at.check(not Net.start_match(Net.lobby_map) and not Net.match_started, "lancement refusé tant que l'invité n'a pas la carte")
	var line: String = lobby._list.get_child(1).text if lobby._list.get_child_count() > 1 else ""
	at.check(line.contains("%"), "état de l'invité dans le salon : « %s »" % line)
	await at.screenshot("salon")
	if not await until(func(): return _client_state().get("etat") == "prete", 30.0, "invité prêt"):
		return
	await frames(2)
	at.check(not lobby._start.disabled, "DÉMARRER possible quand tout le monde a la carte")
	at.check(share.sent_chunks == share.offer.chunks, "envoyée une fois (%d morceaux)" % share.sent_chunks)
	share.test_chunks_per_sec = 0.0
	await seconds(1.0)

	# 1. Morceau corrompu en route : empreinte fausse.
	var m2 := EditorMap.load_dir("res://assets/maps/draft_arena/")
	m2.carte["nom"] = {"fr": "CARTE ABÎMÉE", "en": "DAMAGED MAP"}
	var bad := CustomMapGuard.package_of(m2)
	share.test_corrupt_chunk = 1
	share.srv_offer_package(bad.bytes, m2.carte.nom)
	Net._cl_lobby_map.rpc(EditorMapDef.SHARED_PREFIX + String(bad.sha))
	if not await until(func(): return _client_state().get("etat") == "refusee", 20.0, "carte corrompue refusée"):
		return
	share.test_corrupt_chunk = -1
	at.check(_client_state().get("raison") == "hash", "raison : empreinte SHA-256 (%s)" % _client_state().get("raison"))
	at.check(not Net.start_match(Net.lobby_map) and not Net.match_started, "partie non démarrée (carte corrompue)")
	await frames(2)
	at.check(lobby._start.disabled, "DÉMARRER grisé : « %s »" % lobby._status.text)

	# 2. Empreinte juste mais contenu interdit (type d'objet inconnu, chemin).
	var texts := m.file_texts()
	var objets = JSON.parse_string(texts["objets.json"])
	objets.objets.append({"id": "../evil", "type": "script", "altitude": 0, "position": [5, 5], "source": "res://boot.gd"})
	texts["objets.json"] = EditorMap.dump(objets)
	var evil := CustomMapGuard.pack(texts)
	share.srv_offer_package(evil, {"fr": "PIÈGE", "en": "TRAP"})
	Net._cl_lobby_map.rpc(EditorMapDef.SHARED_PREFIX + CustomMapGuard.sha256_hex(evil))
	if not await until(func(): return _client_state().get("etat") == "refusee", 20.0, "carte piégée refusée"):
		return
	at.check(_client_state().get("raison") == "contenu", "raison : contenu refusé (%s)" % _client_state().get("raison"))
	at.check(not Net.start_match(Net.lobby_map) and not Net.match_started, "partie non démarrée (carte piégée)")

	# 3. Retour à la bonne carte : reprise du cache de l'invité, sans envoi.
	var before := share.sent_chunks
	at.check(lobby._apply_map("perso:arene_perso"), "carte perso annoncée à nouveau")
	at.check(share.offer.sha == sha, "même empreinte")
	if not await until(func(): return _client_state().get("etat") == "prete", 20.0, "invité prêt (cache)"):
		return
	at.check(share.sent_chunks == before, "carte reprise du cache de l'invité (aucun morceau envoyé)")
	await seconds(0.5)
	lobby._on_start()
	if not await until(func(): return Game.instance != null and Game.instance.players.size() == 2, 30.0, "les deux joueurs en jeu"):
		return
	at.check(Game.instance.map_def.id == EditorMapDef.SHARED_PREFIX + sha, "partie sur la carte perso (%s)" % Game.instance.map_def.id)
	at.check(Game.instance.map_def.display_name in ["ARÈNE PERSO", "CUSTOM ARENA"], "nom : %s" % Game.instance.map_def.display_name)
	at.check(GameState.state == GameState.State.PLAYING, "état PLAYING")
	Game.instance.rounds.paused = true
	await at.screenshot("ingame")
	await MpHelpers.finish(self)
