extends AutotestScenario
## @rendu : ARCHITECTURE CUBIQUE (docs/VOXEL_ARCHITECTURE_PLAN.md, pilote et
## lot B) en jeu : murs en biais, raccords, murs courbes, piliers tournés,
## cours tournées et cadres des portes et fenêtres en biais rendus en escalier
## de cubes de 5 cm (marches de 10 cm). Cartes : murs en biais
## (tests/test_map_editor_diagonal.gd : octogone au sol carrelé d'hôpital et
## aux murs peints, losange en béton), salle ronde (pilier tourné, mur courbe,
## fenêtres sur le mur rond, tests/test_map_editor_freeform.gd), murs libres
## (mur courbe de 4 segments, tests/test_map_editor_walls.gd) et DRAFT ARENA
## (aucun mur en biais : rien ne doit changer). Le joueur bute toujours sur le
## mur libre en biais (collision lisse). Mesure : images par seconde sur une
## vue fixe, triangles des murs en escalier.
## @niveau perf : hors check (captures d'un ajout en cours).
## Captures : tests/_out/shots/voxel_archi_look_*.png.

const Diag := preload("res://tests/test_map_editor_diagonal.gd")
const Free := preload("res://tests/test_map_editor_freeform.gd")
const Walls := preload("res://tests/test_map_editor_walls.gd")

var off := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 420
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	# Comparaison : ARCHI_GRAIN=1 (marche de 5 cm), ARCHI_SHADE=0 (éclairage
	# de la face seule).
	if OS.get_environment("ARCHI_GRAIN") != "":
		MeshMapGeometry.step_grain = int(OS.get_environment("ARCHI_GRAIN"))
	if OS.get_environment("ARCHI_SHADE") != "":
		MeshMapGeometry.step_shade = float(OS.get_environment("ARCHI_SHADE"))
	var diag := Diag.diag_map()
	diag.pieces[0]["surface_sol"] = "tiles"
	diag.pieces[0]["surface_murs"] = "wall"
	diag.pieces[1]["surface_sol"] = "concrete"
	diag.pieces[1]["surface_murs"] = "concrete"
	var round := Free.round_map()
	round.pieces[0]["surface_sol"] = "tiles"
	round.pieces[0]["surface_murs"] = "wall"
	var maps := [
		# [nom, carte, vues [nom, position du joueur, point visé]]
		["biais", diag, [
			["mur_libre", Vector2(7.6, 9.4), Vector3(10.0, 1.2, 10.0)],
			["mur_libre_pres", Vector2(8.6, 9.6), Vector3(10.1, 0.4, 10.1)],
			["octogone", Vector2(9.0, 13.0), Vector3(16.0, 1.0, 4.0)],
			["porte", Vector2(10.0, 15.0), Vector3(16.0, 1.3, 16.0)],
			["porte_pres", Vector2(14.3, 14.3), Vector3(15.6, 1.2, 16.6)],
			["fenetre", Vector2(6.2, 6.2), Vector3(3.8, 1.5, 3.8)],
			["fenetre_pres", Vector2(5.0, 5.4), Vector3(3.4, 1.4, 4.4)],
			["losange", Vector2(19.6, 18.4), Vector3(16.0, 1.3, 16.0)],
			["angle_losange", Vector2(19.6, 18.4), Vector3(22.0, 1.0, 18.0)],
		]],
		["ronde", round, [
			["mur_courbe", Vector2(16.0, 15.0), Vector3(16.0, 1.2, 9.0)],
			["mur_courbe_bout", Vector2(13.0, 12.5), Vector3(9.5, 1.0, 13.6)],
			["pilier", Vector2(13.0, 15.5), Vector3(10.0, 1.2, 18.0)],
			["salle_ronde", Vector2(20.0, 20.0), Vector3(6.0, 1.5, 12.0)],
			["fenetre_ronde", Vector2(9.5, 9.5), Vector3(6.6, 1.5, 6.6)],
		]],
		["murs_libres", Walls.free_walls_map(), [
			["courbe", Vector2(8.0, 14.5), Vector3(8.0, 1.0, 11.0)],
			["biais", Vector2(15.0, 11.0), Vector3(18.0, 1.2, 8.0)],
		]],
		["draft", EditorMap.load_dir("res://assets/maps/draft_arena/"), [
			["depart", Vector2.INF, Vector3.INF],
		]],
	]
	for m: Array in maps:
		if not await _visit(m[0], m[1], m[2]):
			return


## Ouvre la carte dans l'éditeur, la teste, prend les vues, revient.
func _visit(map_name: String, doc: EditorMap, views: Array) -> bool:
	var ed: MapEditor = tree().current_scene
	await frames(3)
	ed.new_map(true)
	ed.doc = doc
	ed.collab.reset_doc(ed.doc)
	ed.changed()
	await frames(2)
	if not ed.test_map():
		at.fail("%s : TESTER refusé" % map_name)
		return false
	if not await until(func(): return Game.instance != null and Game.instance.local_player != null, 30.0, "partie lancée (%s)" % map_name):
		return false
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await seconds(1.0)
	await AutotestHelpers.clear_zombies(self)
	var tris := 0
	for mi: MeshInstance3D in game.world.find_children("*__biais", "MeshInstance3D", true, false):
		tris += mi.mesh.get_faces().size() / 3
	var wall_tris := 0
	for mi: MeshInstance3D in game.world.find_children("*__wall", "MeshInstance3D", true, false):
		wall_tris += mi.mesh.get_faces().size() / 3
	print("[voxel_archi_look] %s : %d triangles de murs en biais, %d de murs en chemin" % [map_name, tris, wall_tris])
	if map_name == "biais":
		at.check(tris > 0, "murs en biais en cubes : %d triangles" % tris)
		# Le joueur bute toujours sur le mur libre en biais.
		p.global_position = Vector3(off + 9.0, 0.05, off + 9.0)
		AutotestHelpers.aim_at(p, Vector3(off + 13.0, 1.6, off + 13.0))
		p.input.move = Vector2(0, 1)
		await seconds(1.6)
		p.input.move = Vector2.ZERO
		var pp := p.global_position
		at.check(pp.x + pp.z - 2.0 * off < 20.0 - 0.25, "le joueur bute sur le mur en biais (x + y = %.2f)" % (pp.x + pp.z - 2.0 * off))
	var start := p.global_position
	for vw: Array in views:
		var at2: Vector2 = vw[1]
		var tg: Vector3 = vw[2]
		if at2 == Vector2.INF:
			p.global_position = start
		else:
			p.global_position = Vector3(off + at2.x, 0.05, off + at2.y)
			AutotestHelpers.aim_at(p, tg + Vector3(off, 0, off))
		await seconds(0.5)
		await at.screenshot("%s_%s" % [map_name, String(vw[0])])
	if map_name == "biais":
		# Images par seconde sur la vue de l'octogone (fenêtre réduite, hors écran).
		p.global_position = Vector3(off + 9.0, 0.05, off + 13.0)
		AutotestHelpers.aim_at(p, Vector3(off + 16.0, 1.0, off + 4.0))
		await seconds(1.0)
		var t0 := Time.get_ticks_msec()
		var f0 := Engine.get_frames_drawn()
		await seconds(3.0)
		var dt := (Time.get_ticks_msec() - t0) / 1000.0
		print("[voxel_archi_look] %d triangles de murs en biais, %.1f images/s (%s)" % [tris, (Engine.get_frames_drawn() - f0) / maxf(dt, 0.001), RenderingServer.get_video_adapter_name()])
	Router.back_to_menu()
	return await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur (%s)" % map_name)
