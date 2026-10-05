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
	# Vues multiples (docs/EDITOR_VIEWS.md § 6.4) : le curseur de l'hôte, dans sa
	# vue Avant, arrive avec son plan et sa hauteur ; dessiné dans mon élévation.
	var host_cursor := func() -> bool:
		var pr: Dictionary = ed.collab.peers.get("1", {}).get("presence", {})
		return String(pr.get("vue", "")) == "avant" and absf(float(pr.get("z", -9.0)) - 2.0) < 0.05
	if await until(host_cursor, 20.0, "curseur de l'hôte dans la vue Avant, à 2 m"):
		var av := ed.views.panes[1].view as MapElevation
		av.redraw_overlay()
		await frames(2)
		at.check(ed.collab_view.cursors.has("1"), "curseur de l'hôte suivi dans les vues")
		MpHelpers.signal_peer("curseur_vu")

	# ---------------------------------------------------------------- 1er test
	if not await until(_in_game, 60.0, "invité entré seul dans la partie de test"):
		return
	var game := Game.instance
	at.check(game.local_player.peer_id != 1 and Net.mode == Net.Mode.CLIENT, "joueur local = invité de la partie")
	at.check(game.map_def.id.begins_with(EditorMapDef.SHARED_PREFIX) and CustomMapGuard.is_cached(game.map_def.id.trim_prefix(EditorMapDef.SHARED_PREFIX)),
		"carte de l'éditeur reçue et vérifiée (%s)" % game.map_def.id)
	at.check(game.barricades.windows.size() == 7, "géométrie de DRAFT ARENA (7 fenêtres)")
	# Format 14 : le décor mis à l'échelle par l'hôte, à son échelle chez l'invité.
	var scaled := (game.world as Node).find_children("echelle_test", "Node3D", true, false)
	at.check(not scaled.is_empty() and absf((scaled[0] as Node3D).transform.basis.x.length() - 2.0) < 0.01,
		"décor mis à l'échelle par l'hôte : × 2 chez l'invité (%s)" % (str((scaled[0] as Node3D).transform.basis.x.length()) if not scaled.is_empty() else "absent"))
	var pt := CollabPlaytest.current
	at.check(pt != null and pt.collab.get_parent() == pt and pt.collab.role == MapCollab.Role.GUEST, "session d'édition gardée pendant la partie")
	# Format 15 : achat à la boîte posée au sol (tournée de 45°), par l'avant.
	if not await MpHelpers.wait_peer(self, "boite_prete", 30.0):
		return
	var want := FileAccess.get_file_as_string(MpHelpers.sync_dir().path_join("arme.txt"))
	var box: MysteryBox = game.interact.get_obj("box")
	if not await until(func(): return bool(box.spots[box.location].get("floor", false)), 10.0, "boîte à son emplacement au sol chez l'invité"):
		return
	var p := game.local_player
	p.bot_controlled = true
	var front := box.global_transform.basis.z
	at.check(front.distance_to(Vector3(0, 0, 1).rotated(Vector3.UP, -deg_to_rad(45.0))) < 0.01, "boîte tournée de 45° chez l'invité")
	p.teleport_to(box.global_position + front * 1.3 + Vector3.UP * 0.05)
	await seconds(0.3)
	AutotestHelpers.aim_at(p, box.global_position + Vector3.UP * MysteryBox.SIGHT_HEIGHT)
	await until(func(): return game.interact.focused == box, 5.0, "invite de la boîte chez l'invité")
	p.input.interact_pressed = true
	if not await until(func(): return box.state == MysteryBox.State.READY and box.owner_pid == p.peer_id, 15.0, "arme prête pour l'invité"):
		return
	p.input.interact_pressed = true
	var pd := game.session.local_data()
	var got: bool = await until(func(): return pd.has_weapon(want) >= 0, 5.0, "arme prise")
	at.check(got, "invité : arme obtenue à la boîte au sol (%s)" % want)
	MpHelpers.signal_peer("boite_achetee")
	# Boîte sur la passerelle (étage 1) : dessous, à l'étage 0, pas d'invite ;
	# la demande envoyée quand même est refusée par l'hôte.
	if not await MpHelpers.wait_peer(self, "boite_haut", 20.0):
		return
	if not await until(func(): return (box.spots[box.location].pos as Vector3).y > 2.0, 10.0, "boîte sur la passerelle chez l'invité"):
		return
	var c := box.global_position
	p.teleport_to(Vector3(c.x, 0.05, c.z) - (box.spots[box.location].normal as Vector3) * 0.4)
	await seconds(0.6)
	AutotestHelpers.aim_at(p, box.interact_point())
	await frames(4)
	at.check(game.interact.focused != box, "invité sous la boîte : pas d'invite")
	game.interact.srv_interact.rpc_id(1, "box")
	await seconds(0.3)
	MpHelpers.signal_peer("tente_dessous")
	if not await MpHelpers.wait_peer(self, "en_jeu", 20.0):
		return
	pt.collab.submit_ops([{"op": "put", "coll": "objets", "el": {"id": "pendant_test", "type": "caisse", "altitude": 0, "position": [13.0, 10.0]}}], "caisse")
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
