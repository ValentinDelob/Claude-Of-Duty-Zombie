extends AutotestScenario
## @rendu : a besoin du rendu (captures de l'éditeur et du jeu, fenêtre hors écran).
## MURS EN BIAIS dans l'éditeur de cartes, avec les vrais outils (souris et
## clavier envoyés à la vue) : une pièce en octogone tracée au polygone
## (côtés aimantés à 0, 45 et 90°, clics volontairement imprécis), un
## losange tracé à la Pièce rectangle tournée de 45° (R) collé à un côté en
## biais de l'octogone (mur mitoyen unique), un mur libre en biais au milieu
## de l'octogone, un mur à angle libre (Alt) refusé puis annulé ; une porte
## refusée sur un mur extérieur en biais puis posée sur le bord commun en
## biais, deux fenêtres en biais, une arme et un atout contre des murs en
## biais, la boîte ; vérification sans erreur, Ctrl+S (format 3, clé angle),
## rechargement identique. Puis TESTER : murs obliques construits (pavés
## CollisionBox tournés), un rayon ne traverse pas le mur en biais, le joueur
## non plus ; des zombies entrent par la fenêtre en biais et rejoignent le
## joueur en contournant le mur libre en biais sans jamais le traverser, un
## rampant aussi. Captures : tests/_out/shots/map_editor_diagonal_*.png.

var ed: MapEditor
var cv: MapCanvas
var off := MapGeom.WORLD_OFFSET


func run() -> void:
	timeout_sec = 240
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var root := EditorMap.maps_root()
	_clean(root)
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	await frames(3)
	ed.new_map(true)
	ed.doc.carte.nom = {"fr": "MURS EN BIAIS", "en": "DIAGONAL WALLS"}
	await frames(2)
	cv.zoom = 26.0
	cv.origin = Vector2(60, 50)

	# Octogone au polygone (touche 3) : clics imprécis, côtés aimantés à 45°.
	await key(KEY_3)
	at.check(ed.current_item().id == "piece_poly", "touche 3 : pièce polygone")
	for pt in [Vector2(6, 2), Vector2(14.3, 2.4), Vector2(18.2, 6.3), Vector2(17.7, 14.2), Vector2(14.3, 17.8), Vector2(5.8, 18.3), Vector2(2.2, 13.9), Vector2(1.8, 6.2)]:
		_motion(pt)
		await frames(1)
		if pt == Vector2(18.2, 6.3):
			at.check(cv.trace_end().is_equal_approx(Vector2(18, 6)), "côté aimanté à 45° : (18, 6) (%s)" % cv.trace_end())
			await at.screenshot("trace_45")
		_button(pt, true)
		_button(pt, false)
		await frames(1)
	await click(Vector2(6.1, 2.1))
	var octo: Dictionary = ed.doc.pieces[0] if not ed.doc.pieces.is_empty() else {}
	at.check(not octo.is_empty() and MapGeom.poly(octo.contour) == PackedVector2Array([Vector2(6, 2), Vector2(14, 2), Vector2(18, 6), Vector2(18, 14), Vector2(14, 18), Vector2(6, 18), Vector2(2, 14), Vector2(2, 6)]),
		"octogone tracé, sommets aimantés : %s" % str(octo.get("contour", [])))

	# Losange : Pièce rectangle (2) tournée de 45° (R), collé au côté en biais.
	await key(KEY_2)
	await key(KEY_R)
	at.check(ed.place_rot == 45, "R : pièce rectangle tournée de 45°")
	await drag(Vector2(14, 18), Vector2(22, 18))
	var dia: Dictionary = ed.doc.pieces[1] if ed.doc.pieces.size() > 1 else {}
	at.check(not dia.is_empty() and MapGeom.bbox(MapGeom.poly(dia.contour)) == Rect2(14, 14, 8, 8), "losange posé à 45° : %s" % str(dia.get("contour", [])))
	var shared := MapRules.shared_edges(ed.doc, 0)
	at.check(shared.size() == 1 and not MapGeom.is_axis_seg(shared[0].a, shared[0].b), "bord commun en biais entre l'octogone et le losange")
	var v0 := ed.raster().v
	var common: Array = v0.oblique_walls[0].filter(func(w): return w.pos != "" and w.neg != "")
	at.check(common.size() == 1, "un seul mur mitoyen en biais (%d)" % common.size())

	# Mur libre en biais (touche 4) au milieu de l'octogone ; un mur à angle libre (Alt).
	await key(KEY_4)
	await drag(Vector2(8, 12), Vector2(12.3, 7.8))
	var wall: Dictionary = ed.doc.objets.filter(func(o): return o.type == "mur")[0] if ed.doc.objets.any(func(o): return o.type == "mur") else {}
	at.check(not wall.is_empty() and MapGeom.v2(wall.b).is_equal_approx(Vector2(12, 8)), "mur libre aimanté à 45° : %s" % str(wall.get("b", [])))
	cv.free_angle = true
	await drag(Vector2(4, 9), Vector2(7, 10))
	cv.free_angle = false
	var free_wall: Array = ed.doc.objets.filter(func(o): return o.type == "mur" and MapGeom.v2(o.b).is_equal_approx(Vector2(7, 10)))
	at.check(free_wall.size() == 1, "Alt : mur à angle libre (%s)" % str(free_wall))
	await key(KEY_Z, true)
	at.check(ed.doc.objets.filter(func(o): return o.type == "mur").size() == 1, "Ctrl+Z : mur à angle libre retiré")

	# Porte : refusée sur un mur extérieur en biais, posée sur le bord commun.
	await key(KEY_5)
	await click(Vector2(3.9, 4.2))
	at.check(ed.doc.ouvertures.is_empty() and cv.refusal != "", "porte refusée sur un mur extérieur en biais : « %s »" % cv.refusal)
	await click(Vector2(16.2, 16.1))
	var door: Dictionary = ed.doc.ouvertures[0] if not ed.doc.ouvertures.is_empty() else {}
	at.check(not door.is_empty() and MapGeom.v2(door.position).is_equal_approx(Vector2(16, 16)), "porte posée sur le bord commun en biais : %s" % str(door.get("position", [])))
	# Fenêtres en biais (6) : une par zone ; refusée sur le bord commun.
	await key(KEY_6)
	await click(Vector2(16.4, 15.3))
	at.check(ed.doc.ouvertures.size() == 1 and cv.refusal != "", "fenêtre refusée sur le mur commun : « %s »" % cv.refusal)
	for p in [Vector2(3.6, 3.7), Vector2(20.4, 20.2)]:
		await click(p)
	at.check(ed.doc.ouvertures.filter(func(o): return o.type == "fenetre").size() == 2, "2 fenêtres en biais")

	# Départ (8), boîte (7) contre un mur droit, M14 (9) contre un mur en biais.
	await key(KEY_8)
	await click(Vector2(14.5, 12))
	await key(KEY_7)
	await click(Vector2(10, 2.6))
	await key(KEY_9)
	await click(Vector2(15.6, 4.3))
	var arm: Array = ed.doc.objets.filter(func(o): return o.type == "arme")
	at.check(arm.size() == 1 and MapGeom.item_oblique(arm[0]), "M14 contre un mur en biais (angle %s)" % str(arm[0].get("angle", "?") if not arm.is_empty() else "?"))
	# Atout pris dans l'inventaire, contre un côté en biais du losange.
	await key(KEY_E)
	ed.inventory.show_category("atouts")
	_pick("atout:titan")
	await click(Vector2(20.3, 16.4))
	var perk: Array = ed.doc.objets.filter(func(o): return o.type == "atout")
	at.check(perk.size() == 1 and MapGeom.item_oblique(perk[0]) and absf(float(perk[0].angle) - 45.0) < 0.01, "atout contre un mur en biais, face vers l'intérieur (%s)" % str(perk))

	# Vérification, capture de l'éditeur.
	var v := ed.validate()
	at.check(v.ok(), "vérification : 0 erreur (%s)" % " | ".join(v.errors().map(func(m): return String(m.fr))))
	at.check(v.doors.size() == 1 and v.doors[0].has("oblique") and v.windows.size() == 2 and v.windows.all(func(w): return w.has("oblique")),
		"porte et fenêtres en biais reconnues par le validateur")
	# Textures du losange : brique et parquet (le mur mitoyen montre de chaque
	# côté la texture de sa pièce).
	# (Ctrl+Z a remplacé les pièces par des copies : on relit le losange.)
	dia = ed.doc.pieces[1]
	dia["surface_murs"] = "brick"
	dia["surface_sol"] = "parquet"
	ed.changed()
	ed.panels.show_tab("check")
	ed.select("")
	cv.frame_all()
	# Un côté de polygone en cours de tracé : longueur et angle affichés.
	await key(KEY_3)
	await click(Vector2(23, 7))
	_motion(Vector2(27.3, 2.8))
	await frames(3)
	at.check(cv.trace_end().is_equal_approx(Vector2(27, 3)), "tracé en cours aimanté à 45° (%s)" % cv.trace_end())
	await at.screenshot("editeur")
	await key(KEY_ESCAPE)
	await key(KEY_1)
	at.check(cv.poly_pts.is_empty() and ed.doc.pieces.size() == 2, "Échap : tracé annulé")

	# Ctrl+S : format 3, clé angle ; rechargement identique.
	await key(KEY_S, true)
	var dir := ed.map_dir
	var carte = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json")))
	at.check(carte is Dictionary and int(carte.format) == EditorMap.FORMAT and EditorMap.FORMAT == 3, "Ctrl+S : enregistrée au format 3")
	at.check(FileAccess.get_file_as_string(dir.path_join("objets.json")).contains("\"angle\":45"), "clé angle dans objets.json")
	var saved := ed.doc.duplicate_map()
	ed.open_dir(dir)
	await frames(2)
	at.check(ed.doc.same_as(saved), "carte rechargée identique")

	# En jeu : TESTER.
	if not ed.test_map():
		at.fail("TESTER refusé")
		return
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 30.0, "partie lancée")
	if not ok:
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.combat.debug_invulnerable = true
	var boxes := game.world.find_children("Biais_*", "CollisionBox", true, false)
	at.check(boxes.size() >= 8, "murs en biais : %d pavés CollisionBox tournés" % boxes.size())
	at.check(boxes.any(func(b): return absf(fposmod((b as Node3D).rotation.y, PI * 0.5) - PI * 0.25) < 0.01), "pavés tournés de 45°")
	await seconds(1.0)
	# Un rayon (balle) ne passe pas à travers le mur libre en biais.
	var space := game.world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(off + 8.0, 1.2, off + 8.0), Vector3(off + 12.0, 1.2, off + 12.0), 1)
	var hit := space.intersect_ray(q)
	# Face du mur (x + y = 20 dans l'éditeur, demi-épaisseur 0,25 m) : x + y = 20 - 0,25·√2.
	at.check(not hit.is_empty() and absf(hit.position.x + hit.position.z - 2.0 * off - (20.0 - MapGeom.WALL_HALF * sqrt(2.0))) < 0.1
		and hit.collider is CollisionBox, "un rayon s'arrête sur la face du mur en biais (%s)" % str(hit.get("position", "rien")))
	# Le joueur ne le traverse pas : il avance vers le mur et reste de son côté.
	p.global_position = Vector3(off + 9.0, 0.05, off + 9.0)
	AutotestHelpers.aim_at(p, Vector3(off + 13.0, 1.6, off + 13.0))
	p.input.move = Vector2(0, 1)
	await seconds(1.6)
	p.input.move = Vector2.ZERO
	var pp := p.global_position
	at.check(pp.x + pp.z - 2.0 * off < 20.0 - 0.25, "le joueur bute sur le mur en biais (x + y = %.2f < 19,75)" % (pp.x + pp.z - 2.0 * off))
	# Joueur derrière le mur libre en biais, face à la fenêtre ; zombies de la manche 1.
	p.global_position = Vector3(off + 12.5, 0.05, off + 12.5)
	AutotestHelpers.aim_at(p, Vector3(off + 4.0, 1.2, off + 4.0))
	var win: Barricade = null
	for b: Barricade in game.barricades.windows:
		if b.zone == "a":
			win = b
	at.check(win != null and absf(win.rotation.y - PI * 0.25) < 0.01, "fenêtre barricadée en biais (%.2f rad)" % (win.rotation.y if win else 0.0))
	# Vue sur la fenêtre barricadée dans le mur en biais.
	game.rounds.paused = true
	p.global_position = Vector3(off + 12.0, 0.05, off + 5.5)
	AutotestHelpers.aim_at(p, Vector3(off + 4.0, 1.4, off + 4.0))
	await seconds(0.5)
	await at.screenshot("fenetre")
	game.rounds.paused = false
	p.global_position = Vector3(off + 12.5, 0.05, off + 12.5)
	AutotestHelpers.aim_at(p, Vector3(off + 4.0, 1.2, off + 4.0))
	if win:
		win.srv_set_mask(0)
	var crossed := [false]
	var inside := {}
	var check := func() -> void:
		for z: Zombie in game.zombies.zombies.values():
			if not z.is_alive():
				continue
			var e := Vector2(z.global_position.x - off, z.global_position.z - off)
			var d := MapGeom.dist_to_segment(e, Vector2(8, 12), Vector2(12, 8))
			if d < MapGeom.WALL_HALF + 0.05:
				crossed[0] = true
			if e.x + e.y > 9.0:
				inside[z.id] = true
	var t0 := Time.get_ticks_msec()
	var reached := false
	var crawler_done := false
	while Time.get_ticks_msec() - t0 < 70000:
		await tree().physics_frame
		check.call()
		for z: Zombie in game.zombies.zombies.values():
			if not z.is_alive():
				continue
			if not crawler_done and inside.has(z.id) and z.state == Zombie.State.CHASE:
				ZombieGibs.become_crawler(z)
				crawler_done = true
			if Vector2(z.global_position.x - p.global_position.x, z.global_position.z - p.global_position.z).length() < 1.6:
				reached = true
		if reached and inside.size() >= 2:
			break
	at.check(inside.size() >= 1, "des zombies entrent par la fenêtre en biais (%d)" % inside.size())
	at.check(reached, "un zombie rejoint le joueur en contournant le mur en biais")
	at.check(not crossed[0], "aucun zombie ne traverse le mur en biais")
	at.check(crawler_done, "un rampant suit aussi le joueur")
	await seconds(0.3)
	AutotestHelpers.aim_at(p, Vector3(off + 8.0, 1.0, off + 8.5))
	await frames(4)
	await at.screenshot("en_jeu")
	# Porte en biais vue des deux côtés : plâtre dans l'octogone, brique dans le
	# losange ; angle du losange (raccord des deux murs en biais).
	await AutotestHelpers.clear_zombies(self)
	game.rounds.paused = true
	p.global_position = Vector3(off + 10.0, 0.05, off + 15.0)
	AutotestHelpers.aim_at(p, Vector3(off + 16.0, 1.3, off + 16.0))
	await seconds(0.4)
	await at.screenshot("porte")
	p.global_position = Vector3(off + 19.6, 0.05, off + 18.4)
	AutotestHelpers.aim_at(p, Vector3(off + 16.0, 1.3, off + 16.0))
	await seconds(0.4)
	await at.screenshot("losange")
	AutotestHelpers.aim_at(p, Vector3(off + 22.0, 1.0, off + 18.0))
	await seconds(0.3)
	await at.screenshot("angle")
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")
	_clean(EditorMap.maps_root())


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _pick(item_id: String) -> void:
	for s in ed.inventory.cells:
		if s.item_id == item_id:
			s.clicked.emit(s)
			return
	at.fail("objet %s absent de l'inventaire" % item_id)


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


func key(code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.ctrl_pressed = ctrl
	e.pressed = true
	ed._input(e)
	var up := e.duplicate()
	up.pressed = false
	ed._input(up)
	await frames(1)
