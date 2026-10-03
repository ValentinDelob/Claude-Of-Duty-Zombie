extends AutotestScenario
## Bouton TESTER de l'éditeur de cartes sur DRAFT ARENA : l'exemple ouvert
## depuis assets/maps/draft_arena/, modifié (sa description), est vérifié et joué
## en solo TEL QU'IL EST, sans être enregistré (copie de travail
## « perso:_tester », géométrie construite par le jeu ; copie de récupération
## écrite avant) ; zombies des fenêtres, portes, boîtes à leur place ; la fin
## de la partie ramène dans l'éditeur, sur la même carte, toujours modifiée,
## avec son historique d'annulation (Ctrl+Z : plus d'étoile).

var ed: MapEditor


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var root := EditorMap.maps_root()
	_clean(root)
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.open_example("draft_arena")
	await frames(2)
	at.check(ed.example and ed.doc.pieces.size() == 5 and ed.doc.floor_count() == 2, "exemple DRAFT ARENA ouvert (5 pièces, 2 étages)")
	at.check(ed.invalid.is_empty(), "aucun élément invalide (%s)" % str(ed.invalid))
	# Une modification non enregistrée, jouée par TESTER.
	var c: Dictionary = (ed.doc.carte as Dictionary).duplicate(true)
	c["description"] = {"fr": "Version modifiée, non enregistrée", "en": "Edited, not saved"}
	ed.collab.submit_ops([{"op": "carte", "carte": c}], "description")
	at.check(ed.dirty, "carte modifiée (étoile)")
	var shown := ed.doc.display_name()
	var started := ed.test_map()
	at.check(started and ed.validator.ok(), "TESTER : carte vérifiée (0 erreur)")
	at.check(not EditorMap.is_map_dir(root.path_join("draft_arena")) and EditorMap.list_maps().is_empty(), "TESTER n'enregistre rien dans les cartes du joueur")
	at.check(EditorMap.is_map_dir(MapUnsaved.test_dir()) and EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie de travail jouée et copie de récupération, à part")
	if not started:
		return
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "partie lancée")
	if not ok:
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.combat.debug_invulnerable = true
	at.check(game.map_def is EditorMapDef and game.map_def.id == "perso:" + MapUnsaved.TEST_ID and game.map_def.display_name == shown,
		"partie sur la carte de l'éditeur telle qu'elle est (%s, %s)" % [game.map_def.id, game.map_def.display_name])
	var l := game.layout as MeshMapLayout
	at.check(l != null and l.glb_path == "" and l.zone_at(p.global_position) == "a", "géométrie construite par le jeu, joueur dans la zone de départ")
	at.check(game.barricades.windows.size() == 7, "7 fenêtres barricadées (%d)" % game.barricades.windows.size())
	var costs := {}
	for d: Door in game.doors.values():
		costs[d.door_id] = d.cost
	at.check(costs == {"1": 1000, "2": 1250, "3": 750}, "portes 1000, 1250 (débris), 750 (%s)" % str(costs))
	var box: MysteryBox = game.interact.get_obj("box")
	at.check(box != null and box.spots.size() == 3 and box.location == 1, "3 emplacements de boîte, départ dans le couloir")
	# Le sol tient le joueur : il ne tombe pas à travers la géométrie.
	await seconds(1.0)
	at.check(p.global_position.y > -0.5 and p.is_on_floor(), "joueur debout sur le sol construit (y = %.2f)" % p.global_position.y)
	var zok: bool = await until(func(): return game.zombies.alive_count() >= 1, 25.0, "zombies de la manche 1")
	at.check(zok, "des zombies apparaissent aux fenêtres")
	await at.screenshot("partie")
	# Fin de partie : retour dans l'éditeur, sur la même carte.
	Router.back_to_menu()
	if not await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur"):
		return
	ed = tree().current_scene
	await frames(3)
	at.check(ed.example and ed.map_dir == "" and ed.doc.pieces.size() == 5, "retour dans l'éditeur sur DRAFT ARENA (exemple, %s)" % ed.map_dir)
	at.check(ed.dirty and String(ed.doc.carte.get("description", {}).get("en", "")) == "Edited, not saved" and ed.collab.history.undo_count(ed.collab.my_id) == 1,
		"modification toujours là, non enregistrée, historique intact")
	at.check(not DirAccess.dir_exists_absolute(MapUnsaved.test_dir()), "copie de travail effacée au retour")
	ed.undo()
	at.check(not ed.dirty, "Ctrl+Z jusqu'à l'état d'origine : plus d'étoile")
	_clean(root)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
