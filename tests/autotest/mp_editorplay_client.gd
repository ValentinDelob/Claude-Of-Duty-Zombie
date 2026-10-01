extends AutotestScenario
## [MP] TESTER À PLUSIEURS depuis l'éditeur de cartes — invité (voir
## mp_editorplay_host) : rejoint la session d'édition de l'hôte ; quand
## l'hôte appuie sur TESTER, il entre seul dans la même partie (carte reçue et
## vérifiée), fait un changement de carte en pleine partie (la session tient),
## revient dans l'éditeur à la fin, toujours invité de la même session ; au
## second test, l'hôte quitte en pleine partie : retour dans l'éditeur avec un
## message clair, session intacte.

var PORT := 17995 + MpHelpers.port_offset()
var ed: MapEditor


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _in_game() -> bool:
	return Game.instance != null and Game.instance.players.size() == 2 and Game.instance.local_player != null


func _back_in_editor() -> bool:
	return tree().current_scene is MapEditor and (tree().current_scene as MapEditor).collab != null


func run() -> void:
	timeout_sec = 240
	_rm(CustomMapGuard.cache_root())
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	if not await MpHelpers.wait_peer(self, "ecoute", 40.0):
		return
	var code := FileAccess.get_file_as_string(MpHelpers.sync_dir().path_join("code.txt"))
	ed.collab.join("127.0.0.1", PORT, code, "Invite")
	if not await until(func(): return ed.collab.role == MapCollab.Role.GUEST and not ed.collab._joining and ed.doc.pieces.size() == 5, 20.0, "session de l'hôte rejointe"):
		return
	MpHelpers.signal_peer("rejoint")

	# ---------------------------------------------------------------- 1er test
	if not await until(_in_game, 60.0, "invité entré seul dans la partie de test"):
		return
	var game := Game.instance
	at.check(game.local_player.peer_id != 1 and Net.mode == Net.Mode.CLIENT, "joueur local = invité de la partie")
	at.check(game.map_def.id.begins_with(EditorMapDef.SHARED_PREFIX) and CustomMapGuard.is_cached(game.map_def.id.trim_prefix(EditorMapDef.SHARED_PREFIX)),
		"carte de l'éditeur reçue et vérifiée (%s)" % game.map_def.id)
	at.check(game.barricades.windows.size() == 7, "géométrie de DRAFT ARENA (7 fenêtres)")
	var pt := CollabPlaytest.current
	at.check(pt != null and pt.collab.get_parent() == pt and pt.collab.role == MapCollab.Role.GUEST, "session d'édition gardée pendant la partie")
	if not await MpHelpers.wait_peer(self, "en_jeu", 20.0):
		return
	pt.collab.submit_ops([{"op": "put", "coll": "objets", "el": {"id": "pendant_test", "type": "caisse", "etage": 0, "position": [13.0, 10.0]}}], "caisse")
	if not await until(_back_in_editor, 40.0, "retour dans l'éditeur après la fin de partie"):
		return
	ed = tree().current_scene
	await frames(3)
	at.check(ed.collab.role == MapCollab.Role.GUEST and ed.collab.get_parent() == ed and ed.collab.peers.size() == 2, "toujours invité de la même session")
	at.check(not ed.doc.find("pendant_test").is_empty() and not ed.doc.find("avant_test").is_empty() and ed.doc.pieces.size() == 5, "même carte, changements gardés")
	at.check(ed.collab.pending.is_empty() and ed.collab.history.undo_count(ed.collab.my_id) == 1, "changement fait en partie confirmé par l'hôte, annulable")
	at.check(ed.status.text.contains("Partie terminée") or ed.status.text.contains("Game over"), "barre d'état : « %s »" % ed.status.text)
	at.check(Net.mode == Net.Mode.NONE and CollabPlaytest.current == null and Router.return_scene == "", "partie de test refermée proprement")
	MpHelpers.signal_peer("retour")
	if not await until(func(): return not ed.doc.find("apres_test").is_empty(), 20.0, "changement de l'hôte reçu après le retour"):
		return
	MpHelpers.signal_peer("recu")

	# ---------------------------------------------------------------- 2e test : l'hôte quitte
	if not await until(_in_game, 60.0, "second test rejoint"):
		return
	MpHelpers.signal_peer("en_jeu2")
	if not await until(_back_in_editor, 30.0, "retour dans l'éditeur quand l'hôte quitte"):
		return
	ed = tree().current_scene
	await frames(3)
	at.check(ed.collab.role == MapCollab.Role.GUEST and ed.collab.peers.size() == 2, "toujours invité de la même session")
	at.check(ed.status.text.contains("l'hôte a quitté") or ed.status.text.contains("host left"), "barre d'état : « %s »" % ed.status.text)
	at.check(Net.mode == Net.Mode.NONE and CollabPlaytest.current == null, "partie refermée")
	MpHelpers.signal_peer("retour2")
	await MpHelpers.finish(self)
