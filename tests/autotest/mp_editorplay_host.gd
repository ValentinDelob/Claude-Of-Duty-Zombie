extends AutotestScenario
## @temps-reel : délais réseau réels (connexion de 8 s, attente des invités) entre
## deux éditeurs qui, en temps simulé, n'avancent pas du tout au même rythme.
## [MP] TESTER À PLUSIEURS depuis l'éditeur de cartes (CollabPlaytest,
## docs/MAP_COLLAB.md § 5.3) — hôte. Deux jeux : l'hôte ouvre une session
## d'édition sur DRAFT ARENA, l'invité la rejoint. TESTER : les deux se
## retrouvent dans la même partie, sur la carte de l'éditeur (envoyée à
## l'invité et vérifiée), et la session d'édition reste ouverte pendant la
## partie (un changement de l'invité en pleine partie arrive chez l'hôte).
## Fin de partie : les deux reviennent dans l'éditeur, toujours dans la même
## session, sur la même carte, avec ce changement. Second test : l'hôte quitte
## en pleine partie, l'invité revient aussi dans l'éditeur, session intacte.

var PORT := 17995 + MpHelpers.port_offset()
var ed: MapEditor
## Boîte mystère posée au sol (format 15) : centre dans la salle des machines.
const BOX_AT := [7.0, 28.0]


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
	_rm(EditorMap.maps_root())
	_rm(CustomMapGuard.cache_root())
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	MpHelpers._clear_sync()
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.open_example("draft_arena")
	await frames(2)
	var hosted := ed.collab.host(PORT, "Hote") == OK
	at.check(hosted, "session d'édition ouverte sur le port %d" % PORT)
	if not hosted:
		return
	DirAccess.make_dir_recursive_absolute(MpHelpers.sync_dir())
	var f := FileAccess.open(MpHelpers.sync_dir().path_join("code.txt"), FileAccess.WRITE)
	f.store_string(ed.collab.session_code)
	f.close()
	MpHelpers.signal_peer("ecoute")
	if not await until(func(): return ed.collab.human_guests().size() == 1, 40.0, "invité dans la session"):
		return
	if not await MpHelpers.wait_peer(self, "rejoint", 20.0):
		return
	# Vues multiples (docs/EDITOR_VIEWS.md § 6.4) : mon curseur dans la vue Avant
	# (à 2 m) arrive chez l'invité avec son plan et sa hauteur.
	var av := ed.views.panes[1].view as MapElevation
	ed.show_cursor_view(av, Vector2(9.0, -2.0))
	if not await MpHelpers.wait_peer(self, "curseur_vu", 25.0):
		return
	at.check(true, "curseur de l'hôte reçu en élévation chez l'invité")
	ed.show_cursor(Vector2(9.0, 6.0))

	# Un changement de l'hôte avant le test : son historique doit survivre.
	# Format 14 : avec un décor mis à l'échelle (flaque × 2 en largeur et
	# profondeur), vu par l'invité en jeu ; une seule action.
	var avant_cid := String(ed.collab.submit_ops([{"op": "put", "coll": "objets", "el": {"id": "avant_test", "type": "caisse", "altitude": 0, "position": [12.0, 10.0]}},
		{"op": "put", "coll": "objets", "el": {"id": "echelle_test", "type": "prefab", "prefab": "flaque_eau", "altitude": 0, "position": [12.0, 8.0], "echelle": [2, 2, 1]}},
		# Format 15 : boîte posée au sol, tournée de 45°, dans la salle des machines.
		{"op": "put", "coll": "objets", "el": {"id": "boite_sol", "type": "boite", "altitude": 0, "position": BOX_AT, "rot": 45, "depart": false}}], "caisse").cid)

	# ---------------------------------------------------------------- 1er test : fin de partie
	at.check(ed.test_map(), "TESTER lancé (session avec un invité)")
	at.check(CollabPlaytest.current != null and Net.mode == Net.Mode.HOST and Net.port == PORT, "partie réseau ouverte sur le port de la session (%d)" % Net.port)
	at.check(Net.lobby_map.begins_with(EditorMapDef.SHARED_PREFIX), "carte de l'éditeur annoncée aux invités (%s)" % Net.lobby_map)
	at.check(tree().current_scene is MapEditor, "l'hôte attend l'invité dans l'éditeur")
	at.check(not ed.test_map(), "second TESTER refusé pendant la préparation")
	if not await until(_in_game, 45.0, "les deux joueurs dans la partie de test"):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var map_id := game.map_def.id
	at.check(map_id.begins_with(EditorMapDef.SHARED_PREFIX) and game.map_def is EditorMapDef, "partie sur la carte de l'éditeur (%s)" % map_id)
	at.check(game.barricades.windows.size() == 7, "géométrie de DRAFT ARENA (7 fenêtres : %d)" % game.barricades.windows.size())
	var pt := CollabPlaytest.current
	at.check(pt != null and pt.collab != null and pt.collab.get_parent() == pt, "session d'édition tenue hors de la scène pendant la partie")
	at.check(pt.collab.role == MapCollab.Role.HOST and pt.collab.human_guests().size() == 1, "session toujours ouverte, invité toujours là")
	# Format 15 : l'invité achète à la boîte posée au sol (amenée à son
	# emplacement, arme imposée par le serveur).
	var box: MysteryBox = game.interact.get_obj("box")
	var fi := -1
	for i in box.spots.size():
		if bool(box.spots[i].get("floor", false)):
			fi = i
	at.check(fi >= 0, "emplacement de boîte au sol en jeu")
	var guest := 0
	for pid in game.players:
		if int(pid) != 1:
			guest = int(pid)
	if fi >= 0 and guest != 0:
		box._move_to(fi)
		box.broadcast_state()
		var want := "galil" if WeaponDB.exists("galil") else String(WeaponDB.box_pool().keys()[0])
		box.force_result = want
		game.session.add_points(guest, 5000)
		var wf := FileAccess.open(MpHelpers.sync_dir().path_join("arme.txt"), FileAccess.WRITE)
		wf.store_string(want)
		wf.close()
		MpHelpers.signal_peer("boite_prete")
		if not await MpHelpers.wait_peer(self, "boite_achetee", 40.0):
			return
		var gpd := game.session.get_data(guest)
		at.check(box.state == MysteryBox.State.IDLE and gpd != null and gpd.has_weapon(want) >= 0, "serveur : l'invité a acheté à la boîte au sol (%s)" % want)
		# Boîte sur la passerelle (étage 1) : l'invité, dessous à l'étage 0,
		# envoie quand même la demande d'achat -> refusée par l'hôte.
		var up := -1
		for i in box.spots.size():
			if (box.spots[i].pos as Vector3).y > 2.0:
				up = i
		if up >= 0 and gpd != null:
			box._move_to(up)
			box.broadcast_state()
			var pts := gpd.points
			MpHelpers.signal_peer("boite_haut")
			if not await MpHelpers.wait_peer(self, "tente_dessous", 30.0):
				return
			await seconds(0.5)
			at.check(box.state == MysteryBox.State.IDLE and gpd.points == pts, "hôte : achat de l'invité sous la boîte refusé")
	MpHelpers.signal_peer("en_jeu")
	# Changement de l'invité en pleine partie : la session marche toujours.
	if not await until(func(): return not pt.collab.doc.find("pendant_test").is_empty(), 20.0, "changement de l'invité reçu pendant la partie"):
		return
	at.check(true, "changement de l'invité reçu pendant la partie (session jamais coupée)")
	# Fin de partie (comme si tous étaient tombés) : retour de tous dans l'éditeur.
	game._cl_game_over.rpc(0)
	if not await until(_back_in_editor, 30.0, "retour dans l'éditeur après la fin de partie"):
		return
	ed = tree().current_scene
	await frames(3)
	at.check(ed.collab.role == MapCollab.Role.HOST and ed.collab.get_parent() == ed and ed.collab.human_guests().size() == 1, "même session, invité toujours là")
	at.check(ed.example and ed.map_dir == "" and ed.doc.pieces.size() == 5, "même carte, jamais enregistrée par TESTER (%s)" % ed.map_dir)
	at.check(not ed.doc.find("pendant_test").is_empty(), "changement fait pendant la partie gardé")
	at.check(ed.status.text.contains("Partie terminée") or ed.status.text.contains("Game over"), "barre d'état : « %s »" % ed.status.text)
	at.check(Net.mode == Net.Mode.NONE and CollabPlaytest.current == null and Router.return_scene == "", "partie de test refermée proprement")
	at.check(ed.collab.history.undo_count("1") == 1 and not ed.collab.history.entry(avant_cid).is_empty(), "historique gardé (Ctrl+Z de l'hôte : %d)" % ed.collab.history.undo_count("1"))
	if not await MpHelpers.wait_peer(self, "retour", 30.0):
		return
	# La session continue : un changement de l'hôte arrive chez l'invité.
	ed.collab.submit_ops([{"op": "put", "coll": "objets", "el": {"id": "apres_test", "type": "caisse", "altitude": 0, "position": [14.0, 10.0]}}], "caisse")
	if not await MpHelpers.wait_peer(self, "recu", 20.0):
		return

	# ---------------------------------------------------------------- 2e test : l'hôte quitte
	at.check(ed.test_map(), "second TESTER lancé")
	if not await until(_in_game, 45.0, "second test : les deux joueurs en jeu"):
		return
	Game.instance.rounds.paused = true
	# Carte changée depuis (caisses) : nouveau paquet, reçu à nouveau par l'invité.
	at.check(Game.instance.map_def.id.begins_with(EditorMapDef.SHARED_PREFIX) and Game.instance.map_def.id != map_id,
		"carte modifiée renvoyée à l'invité (%s)" % Game.instance.map_def.id.substr(0, 20))
	if not await MpHelpers.wait_peer(self, "en_jeu2", 20.0):
		return
	Router.back_to_menu()
	if not await until(_back_in_editor, 20.0, "hôte de retour dans l'éditeur"):
		return
	ed = tree().current_scene
	await frames(3)
	at.check(ed.collab.role == MapCollab.Role.HOST and ed.collab.human_guests().size() == 1, "session toujours ouverte après le départ de l'hôte")
	at.check(not ed.doc.find("apres_test").is_empty(), "carte intacte")
	if not await MpHelpers.wait_peer(self, "retour2", 30.0):
		return
	await MpHelpers.finish(self)
	ed.collab.leave()
	_rm(EditorMap.maps_root())
