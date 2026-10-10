extends AutotestScenario
## @rendu : PILOTE DE L'ARCHITECTURE CUBIQUE (docs/VOXEL_ARCHITECTURE_PLAN.md)
## en jeu : carte des murs en biais (tests/test_map_editor_diagonal.gd),
## octogone au sol carrelé d'hôpital et aux murs peints, losange en béton ;
## murs en biais rendus en escalier de cubes de 5 cm. Le joueur bute toujours
## sur le mur libre en biais (collision lisse). Mesure : images par seconde
## sur une vue fixe, triangles des murs en biais.
## @niveau perf : hors check (captures d'un ajout en cours).
## Captures : tests/_out/shots/voxel_archi_look_*.png.

const Diag := preload("res://tests/test_map_editor_diagonal.gd")

var off := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 180
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	var ed: MapEditor = tree().current_scene
	await frames(3)
	ed.new_map(true)
	var doc := Diag.diag_map()
	doc.pieces[0]["surface_sol"] = "tiles"
	doc.pieces[0]["surface_murs"] = "wall"
	doc.pieces[1]["surface_sol"] = "concrete"
	doc.pieces[1]["surface_murs"] = "concrete"
	# Comparaison : ARCHI_GRAIN=2 (marche de 10 cm), ARCHI_SHADE=0 (éclairage
	# de la face seule).
	if OS.get_environment("ARCHI_GRAIN") != "":
		MeshMapGeometry.step_grain = int(OS.get_environment("ARCHI_GRAIN"))
	if OS.get_environment("ARCHI_SHADE") != "":
		MeshMapGeometry.step_shade = float(OS.get_environment("ARCHI_SHADE"))
	ed.doc = doc
	ed.collab.reset_doc(ed.doc)
	ed.changed()
	await frames(2)
	if not ed.test_map():
		at.fail("TESTER refusé")
		return
	if not await until(func(): return Game.instance != null and Game.instance.local_player != null, 30.0, "partie lancée"):
		return
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
	at.check(tris > 0, "murs en biais en cubes : %d triangles" % tris)
	# Le joueur bute toujours sur le mur libre en biais.
	p.global_position = Vector3(off + 9.0, 0.05, off + 9.0)
	AutotestHelpers.aim_at(p, Vector3(off + 13.0, 1.6, off + 13.0))
	p.input.move = Vector2(0, 1)
	await seconds(1.6)
	p.input.move = Vector2.ZERO
	var pp := p.global_position
	at.check(pp.x + pp.z - 2.0 * off < 20.0 - 0.25, "le joueur bute sur le mur en biais (x + y = %.2f)" % (pp.x + pp.z - 2.0 * off))
	var views := [
		# [nom, position du joueur, point visé]
		["mur_libre", Vector2(7.6, 9.4), Vector3(10.0, 1.2, 10.0)],
		["mur_libre_pres", Vector2(8.6, 9.6), Vector3(10.1, 0.4, 10.1)],
		["octogone", Vector2(9.0, 13.0), Vector3(16.0, 1.0, 4.0)],
		["porte", Vector2(10.0, 15.0), Vector3(16.0, 1.3, 16.0)],
		["losange", Vector2(19.6, 18.4), Vector3(16.0, 1.3, 16.0)],
		["angle_losange", Vector2(19.6, 18.4), Vector3(22.0, 1.0, 18.0)],
	]
	for vw: Array in views:
		var at2: Vector2 = vw[1]
		var tg: Vector3 = vw[2]
		p.global_position = Vector3(off + at2.x, 0.05, off + at2.y)
		AutotestHelpers.aim_at(p, tg + Vector3(off, 0, off))
		await seconds(0.5)
		await at.screenshot(String(vw[0]))
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
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")
