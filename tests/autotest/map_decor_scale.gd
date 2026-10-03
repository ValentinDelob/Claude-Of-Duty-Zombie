extends AutotestScenario
## Décor mis à l'échelle et incliné en jeu (format 14,
## docs/EDITOR_SCALE_ROTATE.md § 5.2) : carte de l'éditeur avec une pile de
## caisses × 1,5 et une poutre inclinée de 30° ; TESTER : un rayon tombé d'en
## haut s'arrête sur le dessus des caisses agrandies et sur la pente de la
## poutre, le joueur est arrêté par les caisses (là où des caisses × 1
## l'auraient laissé passer) et par la poutre, les zombies contournent la
## poutre (son emprise au sol projetée n'est jamais un passage).

const Objects := preload("res://tests/test_map_objects.gd")

var ed: MapEditor
var off := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 150
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
	# Salle A haute (6,80 m) : la poutre inclinée y tient.
	doc.pieces[0]["plafond"] = 6.8
	doc.find("s1")["position"] = [6.0, 7.5]
	doc.objets.append({"id": "d90", "type": "prefab", "prefab": "caisses", "etage": 0, "position": [11.0, 7.0], "echelle": [1.5, 1.5, 1.5]})
	doc.objets.append({"id": "d91", "type": "prefab", "prefab": "poutre", "etage": 0, "position": [5.0, 3.5], "incl": [0, 30]})
	ed.new_map(true)
	ed._reset(doc)
	await frames(3)
	var beam := ed.doc.find("d91")
	at.check(MapScale.check(ed.doc, ed.raster().v, ed.doc.find("d90")).ok, "caisses × 1,5 : pose valide")
	at.check(MapScale.check(ed.doc, ed.raster().v, beam).ok, "poutre inclinée de 30° : pose valide (%s)" % str(MapScale.check(ed.doc, ed.raster().v, beam)))
	at.check(ed.save(), "carte enregistrée")
	var dir := ed.map_dir
	ed.new_map(true)
	ed.open_dir(dir)
	await frames(2)
	at.check(MapScale.scale_of(ed.doc.find("d90")).is_equal_approx(Vector3.ONE * 1.5) and MapScale.is_tilted(ed.doc.find("d91")), "relue : échelle et inclinaison (%s, %s ; %s)" % [str(ed.doc.find("d90")), str(ed.doc.find("d91")), str(ed.doc.load_errors)])

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
	await frames(3)
	var space := (game.world as Node3D).get_world_3d().direct_space_state

	# Caisses × 1,5 : le dessus de leurs collisions monte d'autant.
	var top := 0.0
	for bx in MapPrefabLib.catalog_boxes("caisses"):
		top = maxf(top, float(bx.center[1]) + float(bx.size[1]) * 0.5)
	# Plus haut point touché sur l'emprise (la pile a des creux entre ses caisses).
	var hc := -1.0
	for i in 9:
		for j in 7:
			hc = maxf(hc, _ray_down(space, 9.3 + i * 0.42, 5.7 + j * 0.42))
	at.check(hc > top * 1.0 + 0.1 and hc < top * 1.5 + 0.05, "rayon sur les caisses agrandies : y %.2f (dessus × 1,5 : %.2f)" % [hc, top * 1.5])
	# Le joueur marche vers l'est : arrêté par la face ouest des caisses agrandies
	# (x 9,13 ; des caisses × 1 l'auraient arrêté plus loin, à 9,75).
	p.teleport_to(Vector3(6.5 + off, 0.05, 7.0 + off), -PI / 2)
	p.pitch = 0.0
	await seconds(0.3)
	p.input.move = Vector2(0, 1)
	await seconds(2.0)
	p.input.move = Vector2.ZERO
	var px := p.global_position.x - off
	at.check(px < 9.125 and px > 7.5, "joueur arrêté par les caisses agrandies (x = %.2f)" % px)

	# Poutre inclinée : le bout ouest est haut, le bout est au sol.
	var hi := _ray_down(space, 2.5, 3.5)
	var lo := _ray_down(space, 7.5, 3.5)
	at.check(hi > 1.9 and hi > lo + 1.5, "rayons sur la pente : %.2f à l'ouest, %.2f à l'est" % [hi, lo])
	# Le joueur marche vers le nord au bout bas : arrêté par la poutre.
	p.teleport_to(Vector3(7.5 + off, 0.05, 7.0 + off), 0.0)
	await seconds(0.3)
	p.input.move = Vector2(0, 1)
	await seconds(2.0)
	p.input.move = Vector2.ZERO
	var pz := p.global_position.z - off
	at.check(pz > 3.8, "joueur arrêté par la poutre inclinée (y = %.2f)" % pz)

	# Zombies : l'emprise projetée de la poutre n'est jamais un passage.
	var poly := MapScale.ground_poly(beam)
	var inner := Geometry2D.offset_polygon(poly, -0.15)
	var shrunk: PackedVector2Array = inner[0] if not inner.is_empty() else poly
	# Départ au nord du bout bas (x 7,5 : la poutre y touche presque le sol, rien
	# ne passe dessous ni dessus), joueur au sud.
	p.teleport_to(Vector3(7.5 + off, 0.05, 7.5 + off), 0.0)
	await seconds(0.2)
	var path: PackedVector3Array = game.nav.find_path(Vector3(7.5 + off, 0.0, 1.3 + off), Vector3(7.5 + off, 0.0, 7.5 + off))
	at.check(path.size() >= 2, "chemin du nord au sud de la poutre (%d points)" % path.size())
	var crossing := false
	for i in range(1, path.size()):
		for t in 11:
			var q := path[i - 1].lerp(path[i], t / 10.0)
			if Geometry2D.is_point_in_polygon(Vector2(q.x - off, q.z - off), shrunk):
				crossing = true
	at.check(not crossing, "le chemin contourne la poutre")
	# Le zombie (rayon 0,4 m) peut frôler le bord de l'emprise en suivant son
	# chemin : son centre ne s'y enfonce jamais de plus de 0,5 m.
	var deep := Geometry2D.offset_polygon(poly, -0.5)
	var inner_z: PackedVector2Array = deep[0] if not deep.is_empty() else shrunk
	var z := await AutotestHelpers.dummy_zombie(self, Vector3(7.5 + off, 0.0, 1.3 + off))
	z.speed_mult = 1.0
	var entered := [false]
	var watch := func() -> bool:
		if not is_instance_valid(z):
			return true
		var zp := Vector2(z.global_position.x - off, z.global_position.z - off)
		# Jamais sur la pente (pieds au-dessus du sol), jamais dans l'emprise.
		if (Geometry2D.is_point_in_polygon(zp, inner_z) or z.global_position.y > 0.4) and not entered[0]:
			entered[0] = true
			print("[map_decor_scale] zombie dans l'emprise en %s, y %.2f" % [str(zp), z.global_position.y])
		return zp.y > 5.0
	var passed := await until(watch, 30.0, "zombie passé au sud de la poutre")
	var zend := Vector2(z.global_position.x - off, z.global_position.z - off) if is_instance_valid(z) else Vector2.INF
	at.check(passed and not entered[0], "le zombie contourne la poutre sans jamais entrer dans son emprise (passé : %s, entré : %s, en %s)" % [passed, entered[0], str(zend)])
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")
	_clean(root)


## Hauteur (m) où un rayon vertical tombé de 6 m (sous le plafond) s'arrête au point (x, y) de la carte.
func _ray_down(space: PhysicsDirectSpaceState3D, x: float, y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x + off, 6.0, y + off), Vector3(x + off, -1.0, y + off))
	var hit := space.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else -1.0


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
