extends AutotestScenario
## Objets du format 5 de l'éditeur de bout en bout (docs/MAP_OBJECTS.md) :
## dans le vrai éditeur, touche V sur une porte et des débris, barrière
## invisible tracée à la souris (polygone, format 9) ; carte
## enregistrée, rouverte depuis le disque (tout est relu, barrière montrée par
## l'aperçu 3D de l'éditeur), puis TESTER : bons modèles en jeu, barrière
## sans rien de visible, qui arrête le joueur et que les zombies contournent.

const Objects := preload("res://tests/test_map_objects.gd")

var ed: MapEditor
var cv: MapCanvas


func run() -> void:
	timeout_sec = 150
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var root := EditorMap.maps_root()
	_clean(root)
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	await frames(3)
	# Carte d'essai (3 salles) sans variante ni barrière : on les pose ici.
	var doc := Objects.objects_map()
	for o: Dictionary in doc.ouvertures + doc.objets:
		o.erase("variante")
	doc.objets = doc.objets.filter(func(o): return o.type != "bloc_invisible")
	ed.new_map(true)
	ed._reset(doc)
	await frames(2)
	cv.zoom = 26.0
	cv.origin = Vector2(40, 40)

	# Touche V sur l'objet choisi : porte, débris.
	for c: Array in [["o1", "bois"], ["o4", "gravats"]]:
		ed.select(c[0])
		await key(KEY_V)
		at.check(MapCatalog.variant_of(ed.doc.find(c[0])) == c[1], "V sur %s : %s (%s)" % [c[0], c[1], MapCatalog.variant_of(ed.doc.find(c[0]))])

	# Barrière invisible tracée à la souris en polygone (format 9) : un clic
	# par sommet, fermée en recliquant le premier.
	ed.set_hotbar(8, "bloc_invisible")
	cv.set_snap_mode("grille")
	var corners := [Vector2(16, 3), Vector2(17, 3), Vector2(17, 8), Vector2(16, 8)]
	for c: Vector2 in corners + [corners[0]]:
		await click(c)
	var clips: Array = ed.doc.objets.filter(func(o): return o.type == "bloc_invisible")
	at.check(clips.size() == 1, "barrière invisible posée (%d) %s" % [clips.size(), cv.refusal])
	if clips.size() != 1:
		return
	var rect := MapGeom.poly(clips[0].get("sommets", []))
	at.check(rect == PackedVector2Array(corners), "barrière de 1 m sur 5 m à sa place (%s)" % str(rect))
	ed.select_mouse()

	# Enregistrée puis rouverte depuis le disque.
	at.check(ed.save(), "carte enregistrée")
	var dir := ed.map_dir
	var carte = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json")))
	at.check(carte is Dictionary and int(carte.get("format", 0)) == EditorMap.FORMAT and EditorMap.FORMAT >= 5, "fichier au format courant, 5 et plus (%s)" % str(carte.get("format", "?") if carte is Dictionary else "?"))
	at.check(FileAccess.get_file_as_string(dir.path_join("objets.json")).contains("bloc_invisible"), "barrière écrite dans objets.json")
	ed.new_map(true)
	ed.open_dir(dir)
	await frames(2)
	at.check(MapCatalog.variant_of(ed.doc.find("o1")) == "bois" and MapCatalog.variant_of(ed.doc.find("o4")) == "gravats",
		"relue : porte en bois, éboulement de béton")
	var back: Array = ed.doc.objets.filter(func(o): return o.type == "bloc_invisible")
	at.check(back.size() == 1 and MapGeom.poly(back[0].get("sommets", [])) == rect, "relue : barrière invisible")
	# Visible dans l'éditeur : pavé de l'aperçu 3D (mêmes données que le jeu).
	var pv := Node3D.new()
	tree().root.add_child(pv)
	MapPreviewBuilder.new(EditorMapDef.from_map(ed.doc, "perso:" + dir.get_file()).layout_data).build_decor(pv)
	at.check(pv.find_children("ClipView_*", "MeshInstance3D", true, false).size() == 1, "barrière montrée dans l'aperçu 3D de l'éditeur")
	pv.queue_free()

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
	var looks := {}
	for d: Door in game.doors.values():
		looks[d.variant if d.variant != "" else "blindee"] = true
	at.check(looks.has("bois") and looks.has("gravats"), "en jeu : porte en bois et éboulement de béton (%s)" % str(looks.keys()))
	for d: Door in game.doors.values():
		d.srv_open()
	var off := MapGeom.WORLD_OFFSET
	var center := Vector3(16.5 + off, 0.0, 5.5 + off)
	var boxes := game.world.find_children("*", "CollisionBox", true, false).filter(func(b): return Vector2(b.global_position.x - center.x, b.global_position.z - center.z).length() < 0.05)
	at.check(boxes.size() == 1 and (boxes[0] as CollisionBox).collision_layer == Barricade.BARRIER_LAYER, "en jeu : une CollisionBox sur la couche BARRIER")
	if boxes.size() == 1:
		at.check(boxes[0].find_children("*", "VisualInstance3D", true, false).is_empty(), "en jeu : rien de visible dans la barrière")
	at.check(game.world.find_children("ClipView*", "", true, false).is_empty(), "en jeu : pas de pavé de l'aperçu")
	await seconds(0.5)  # collisions des portes ouvertes coupées

	# Le joueur marche droit dessus : arrêté.
	p.teleport_to(Vector3(14.8 + off, 0.05, 5.5 + off), -PI * 0.5)  # face à l'est (+x)
	p.pitch = 0.0
	await seconds(0.3)
	p.input.move = Vector2(0, 1)
	await seconds(2.0)  # marche mesurée : il aurait traversé
	p.input.move = Vector2.ZERO
	at.check(p.global_position.x < 16.0 + off - 0.2, "le joueur est arrêté par la barrière (x = %.2f, bord à 16)" % (p.global_position.x - off))

	# Un zombie à l'ouest, le joueur à l'est : il contourne, sans la traverser.
	p.teleport_to(Vector3(19.0 + off, 0.05, 5.5 + off), PI * 0.5)
	await seconds(0.3)
	var z := game.zombies.get_zombie(game.zombies.spawn(Vector3(14.8 + off, 0.0, 5.5 + off), RoundRules.RUN, 100000))
	await AutotestHelpers.emerged(self, [z])
	var bar := Rect2(16.0 + off, 3.0 + off, 1.0, 5.0).grow(-0.05)
	var crossed := [false]
	var ok: bool = await until(func():
		if bar.has_point(Vector2(z.global_position.x, z.global_position.z)):
			crossed[0] = true
		return z.global_position.distance_to(p.global_position) < 2.0, 20.0, "zombie arrivé au joueur")
	at.check(ok and not crossed[0], "le zombie contourne la barrière et atteint le joueur (jamais dedans)")
	# Retour dans l'éditeur, carte d'essai effacée.
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")
	_clean(root)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _motion(m: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = cv.to_px(m)
	cv._gui_input(e)


func _button(m: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = cv.to_px(m)
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	cv._gui_input(e)


func click(m: Vector2) -> void:
	_motion(m)
	_button(m, true)
	_button(m, false)
	await frames(1)


func drag(a: Vector2, b: Vector2) -> void:
	_motion(a)
	_button(a, true)
	for i in 4:
		_motion(a.lerp(b, (i + 1) / 4.0))
		await frames(1)
	_button(b, false)
	await frames(1)


func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	ed._input(e)
	var up := e.duplicate()
	up.pressed = false
	ed._input(up)
	await frames(1)
