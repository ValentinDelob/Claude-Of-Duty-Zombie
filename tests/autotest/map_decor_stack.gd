extends AutotestScenario
## Décor posé sur un autre (format 12, docs/EDITOR_VIEWS.md § 7) de bout en
## bout : dans le vrai éditeur, des sacs de sable montés sur d'autres sacs de
## sable depuis la vue Avant (glissement vertical, aimanté sur le dessus du
## décor dessous), refus d'un décor bloquant laissé en l'air ; carte
## enregistrée au format 12 et relue ; TESTER : en jeu, le décor du dessus et
## sa collision (CollisionBox) sont à 0,9 m, un rayon tombé d'en haut s'arrête
## sur lui (1,8 m), le joueur est arrêté au sol par la pile.

const Objects := preload("res://tests/test_map_objects.gd")

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
	var doc := Objects.objects_map()
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	doc.objets.append({"id": "d1", "type": "prefab", "prefab": "sacs_sable", "etage": 0, "position": [5.0, 4.0], "rot": 0})
	doc.objets.append({"id": "d2", "type": "prefab", "prefab": "sacs_sable", "etage": 0, "position": [8.0, 4.0], "rot": 0})
	ed.new_map(true)
	ed._reset(doc)
	await frames(3)
	var pn: MapViewPane = ed.views.panes[1]
	var av: MapElevation = pn.view
	at.check(av.plane == "avant", "vue Avant sous la vue Dessus")
	av.zoom = 40.0
	av.origin = Vector2(40, av.size.y - 60)
	ed.canvas.set_snap_mode("libre")
	await frames(2)

	# Glisser d2 sur d1 dans la vue Avant : vers la gauche (x 8 -> 5), vers le
	# haut jusqu'au dessus des sacs (0,9 m, aimanté).
	ed.select("d2")
	await frames(1)
	var e := av.projected_of("d2")
	var a := Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	await _drag(av, a, a + Vector2(-3.0, -0.92))
	var d2 := ed.doc.find("d2")
	at.check(absf(float(d2.position[0]) - 5.0) < 0.02 and absf(MapVertical.decor_z(d2) - 0.9) < 0.005,
		"d2 posé sur d1 : x %.2f, z %.2f (aimant : dessus des sacs)" % [float(d2.position[0]), MapVertical.decor_z(d2)])
	at.check(ed.collab.history.undo_count(ed.collab.my_id) == 1, "un glissement = une annulation")
	# En l'air : refusé, il reste à sa dernière place valide.
	e = av.projected_of("d2")
	a = Vector2((float(e.u0) + float(e.u1)) * 0.5, (float(e.v0) + float(e.v1)) * 0.5)
	await _drag(av, a, a + Vector2(0.0, -0.6))
	at.check(absf(MapVertical.decor_z(ed.doc.find("d2")) - 0.9) < 0.005, "décor bloquant en l'air : refusé (z %.2f)" % MapVertical.decor_z(ed.doc.find("d2")))

	# Enregistrée au format 12, relue.
	at.check(ed.save(), "carte enregistrée")
	var dir := ed.map_dir
	var carte = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json")))
	at.check(carte is Dictionary and int(carte.get("format", 0)) == 12, "format 12")
	ed.new_map(true)
	ed.open_dir(dir)
	await frames(2)
	at.check(absf(MapVertical.decor_z(ed.doc.find("d2")) - 0.9) < 0.005, "relue : z = 0,9")

	# TESTER.
	if not ed.test_map():
		at.fail("TESTER refusé : %s" % str(ed.validator.errors().map(func(m): return m.fr) if ed.validator else []))
		return
	if not await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "partie lancée"):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await AutotestHelpers.clear_zombies(self)
	var off := MapGeom.WORLD_OFFSET
	var boxes := game.world.find_children("*", "CollisionBox", true, false).filter(func(b):
		return Vector2(b.global_position.x - (5.0 + off), b.global_position.z - (4.0 + off)).length() < 0.1)
	var ys: Array = boxes.map(func(b): return snappedf(b.global_position.y, 0.01))
	ys.sort()
	at.check(ys.size() == 2 and absf(float(ys[0]) - 0.45) < 0.02 and absf(float(ys[1]) - 1.35) < 0.02,
		"en jeu : deux collisions empilées, centres à 0,45 et 1,35 m (%s)" % str(ys))
	await frames(3)
	var space := (game.world as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(5.0 + off, 3.0, 4.0 + off), Vector3(5.0 + off, -1.0, 4.0 + off))
	var hit := space.intersect_ray(q)
	at.check(not hit.is_empty() and absf(float(hit.position.y) - 1.8) < 0.05, "un rayon tombé d'en haut s'arrête sur le décor du dessus (y %.2f)" % (float(hit.position.y) if not hit.is_empty() else -1.0))
	# Le joueur marche vers la pile : arrêté au sol.
	p.teleport_to(Vector3(5.0 + off, 0.05, 6.6 + off), 0.0)  # face au nord (-z)
	p.pitch = 0.0
	await seconds(0.3)
	p.input.move = Vector2(0, 1)
	await seconds(1.5)
	p.input.move = Vector2.ZERO
	at.check(p.global_position.z > 4.0 + 0.4 + off, "le joueur est arrêté par la pile (z = %.2f)" % (p.global_position.z - off))
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")
	_clean(root)


func _drag(v: MapElevation, a: Vector2, b: Vector2) -> void:
	_mouse(v, a, -1)
	_mouse(v, a, 1)
	for i in 6:
		_mouse(v, a.lerp(b, (i + 1) / 6.0), -1)
		await frames(1)
	_mouse(v, b, 0)
	await frames(1)


## Souris dans la vue : `press` -1 mouvement, 1 appui, 0 relâché.
func _mouse(v: MapElevation, m: Vector2, press: int) -> void:
	if press < 0:
		var mm := InputEventMouseMotion.new()
		mm.position = v.to_px(m)
		v._gui_input(mm)
		return
	var mb := InputEventMouseButton.new()
	mb.position = v.to_px(m)
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = press == 1
	v._gui_input(mb)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
