extends AutotestScenario
## Bouton TESTER de l'éditeur de cartes sur DRAFT ARENA : l'exemple ouvert
## depuis assets/maps/draft_arena/ est vérifié, copié dans le dossier des
## cartes du joueur et joué en solo (« perso:draft_arena », géométrie construite
## par le jeu) ; zombies des fenêtres, portes, boîtes à leur place ; la fin de
## la partie ramène dans l'éditeur, sur la même carte.

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
	var started := ed.test_map()
	at.check(started and ed.validator.ok(), "TESTER : carte vérifiée (0 erreur)")
	at.check(EditorMap.is_map_dir(root.path_join("draft_arena")), "copie enregistrée dans le dossier des cartes du joueur")
	if not started:
		return
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "partie lancée")
	if not ok:
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.combat.debug_invulnerable = true
	at.check(game.map_def is EditorMapDef and game.map_def.id == "perso:draft_arena", "partie sur la carte de l'éditeur (%s)" % game.map_def.id)
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
	at.check(ed.map_dir.get_file() == "draft_arena" and not ed.example and ed.doc.pieces.size() == 5, "retour dans l'éditeur sur DRAFT ARENA (%s)" % ed.map_dir)
	_clean(root)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
