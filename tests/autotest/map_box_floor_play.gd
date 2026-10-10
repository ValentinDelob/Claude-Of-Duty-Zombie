extends AutotestScenario
## Caisse au hasard posée au sol (format 15, docs/MAP_OBJECTS.md § 15) de
## bout en bout, sans rendu : dans le vrai éditeur, l'outil Caisse pose une
## caisse au milieu d'une salle (aimantée au mur quand on s'en approche),
## tournée de 45° ; la caisse murale de la carte d'essai est retirée (une
## seule par carte) ; TESTER : caisse au centre et à l'orientation de
## l'éditeur ; achat par l'avant, couvercle ouvert, objet pris ; invite
## aussi derrière et sur le côté ; le joueur est arrêté par la caisse et un
## zombie la contourne sans la traverser.

const DecorFree := preload("res://tests/test_map_decor_free.gd")
const OFF := MapGeom.WORLD_OFFSET
## Centre de la boîte au sol dans l'éditeur (salle A : 0..14 × 0..10).
const CENTER := Vector2(5.0, 5.0)

var ed: MapEditor
var cv: MapCanvas
var p: Player
var game: Game


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
	# Deux salles ; la boîte de départ est contre le mur sud de la salle B.
	ed.new_map(true)
	ed._reset(DecorFree.two_rooms())
	await frames(2)
	cv.zoom = 26.0
	cv.origin = Vector2(40, 40)
	cv.set_snap_mode("libre")

	# Outil Boîte : R la pivote en main ; posée au milieu de la salle A.
	ed.set_hotbar(6, "boite")
	await key(KEY_R)
	at.check(ed.place_rot == 90, "R : boîte tenue tournée de 90° (%d)" % ed.place_rot)
	await key(KEY_R)
	await key(KEY_R)
	await key(KEY_R)
	await click(CENTER)
	var floor_boxes := _boxes().filter(func(o): return not o.has("mur"))
	at.check(floor_boxes.size() == 1, "boîte posée au sol (%d) %s" % [floor_boxes.size(), cv.refusal])
	if floor_boxes.size() != 1:
		return
	var fb: Dictionary = floor_boxes[0]
	at.check(MapGeom.v2(fb.position) == CENTER and MapGeom.rot_of(fb) == 0, "au milieu de la salle, droite (%s, %d°)" % [str(fb.position), MapGeom.rot_of(fb)])
	# Près du mur nord : aimantée au mur, face à la salle ; retirée ensuite.
	await click(Vector2(10.0, 0.9))
	var on_wall := _boxes().filter(func(o): return String(o.get("mur", "")) == "n")
	at.check(on_wall.size() == 1 and not on_wall[0].has("rot"), "près du mur : collée au mur nord, sans rotation propre")
	if on_wall.size() == 1:
		ed.delete_element(String(on_wall[0].id))
	ed.select_mouse()
	# Tournée de 45° (anneau ou champ Angle : MapTransform.apply).
	ed.select(String(fb.id))
	ed.push_undo()
	var rr := MapTransform.apply(ed.doc, fb.duplicate(true), [], MapTransform.pivot(ed.doc, fb), 45.0, ed.doc.snapshot())
	ed.changed()
	fb = ed.doc.find(String(fb.id))
	at.check(rr.ok and MapGeom.rot_of(fb) == 45, "tournée de 45° (%s)" % MapRules.why(rr))
	# Une seule caisse par carte : celle du mur de la salle B est retirée.
	for o in _boxes():
		if o.has("mur"):
			ed.delete_element(String(o.id))
	at.check(_boxes().size() == 1, "une seule caisse au hasard")

	# TESTER.
	if not ed.test_map():
		at.fail("TESTER refusé : %s" % str(ed.validator.errors().map(func(m): return m.fr) if ed.validator else []))
		return
	if not await until(func(): return Game.instance != null and Game.instance.local_player != null, 20.0, "partie lancée"):
		return
	game = Game.instance
	p = game.local_player
	p.bot_controlled = true
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await AutotestHelpers.clear_zombies(self)
	for d: Door in game.doors.values():
		d.srv_open()
	await seconds(0.5)  # collisions des portes ouvertes coupées
	var box: MysteryBox = game.interact.get_obj("box")
	at.check(box != null and bool(box.spot.get("floor", false)), "caisse construite, au sol")
	if box == null:
		return
	var center := Vector3(CENTER.x + OFF, 0.0, CENTER.y + OFF)
	var front := Vector3(0, 0, 1).rotated(Vector3.UP, -deg_to_rad(45.0))
	var side := front.cross(Vector3.UP)
	game.session.add_points(p.peer_id, 20000)
	at.check(box.global_position.distance_to(center) < 0.01, "posée au centre de l'éditeur (%s)" % (box.global_position - Vector3(OFF, 0, OFF)))
	at.check(box.global_transform.basis.z.distance_to(front) < 0.01, "avant tourné de 45° comme dans l'éditeur")

	# Achat par l'avant : invite, couvercle ouvert, objet pris.
	await _face(box, front, 1.3)
	at.check(game.interact.focused == box, "invite de la caisse depuis l'avant")
	var pd := game.session.local_data()
	box.force_result = "frag"
	var before := pd.points
	p.input.interact_pressed = true
	if not await until(func(): return box.state == MysteryBox.State.ROLLING, 3.0, "achat : défilement"):
		return
	at.check(pd.points == before - MysteryBox.COST, "950 points payés")
	await seconds(1.0)
	at.check(box._lid.rotation.x < -1.0, "couvercle ouvert (%.2f rad)" % box._lid.rotation.x)
	if not await until(func(): return box.state == MysteryBox.State.READY, 8.0, "objet prêt"):
		return
	at.check(box.item == "frag" and game.interact.focused == box and box.prompt(p.peer_id) != "", "invite « Prendre »")
	p.input.interact_pressed = true
	at.check(await until(func(): return box.state == MysteryBox.State.IDLE, 3.0, "objet pris"), "caisse refermée après la prise")

	# Invite de tous les côtés (tout autour du coffre).
	await _face(box, -front, 1.2)
	at.check(game.interact.focused == box, "invite depuis l'arrière")
	await _face(box, side, 1.6)
	at.check(game.interact.focused == box, "invite depuis le côté")

	# Collision : le joueur marche droit sur la boîte depuis l'avant.
	p.teleport_to(center + front * 2.5 + Vector3.UP * 0.05, atan2(front.x, front.z))
	p.pitch = 0.0
	await seconds(0.3)
	p.input.move = Vector2(0, 1)
	await seconds(1.5)
	p.input.move = Vector2.ZERO
	var along := (p.global_position - center).dot(front)
	at.check(along > MysteryBox.BODY_SIZE.z * 0.5 + 0.2, "le joueur est arrêté par la boîte (%.2f m de son centre)" % along)

	# Zombie de l'autre côté : il contourne la boîte (navmesh) sans la traverser.
	p.teleport_to(center - front * 3.0 + Vector3.UP * 0.05, 0.0)
	await seconds(0.3)
	var z := game.zombies.get_zombie(game.zombies.spawn(center + front * 3.0, RoundRules.RUN, 100000))
	await AutotestHelpers.emerged(self, [z])
	var inside := [false]
	var ok: bool = await until(func():
		var q := z.global_position - center
		if absf(q.dot(front)) < MysteryBox.BODY_SIZE.z * 0.5 - 0.05 and absf(q.dot(side)) < MysteryBox.BODY_SIZE.x * 0.5 - 0.05:
			inside[0] = true
		return z.global_position.distance_to(p.global_position) < 2.0, 20.0, "zombie arrivé au joueur")
	at.check(ok and not inside[0], "le zombie contourne la boîte et atteint le joueur (jamais dedans ; zombie en %s, joueur en %s)" % [z.global_position - Vector3(OFF, 0, OFF), p.global_position - Vector3(OFF, 0, OFF)])
	Router.back_to_menu()
	await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur")
	_clean(root)


func _boxes() -> Array:
	return ed.doc.objets.filter(func(o): return String(o.get("type", "")) == "boite")


## Joueur posé à `dist` m du centre de la boîte dans la direction `dir`, qui la
## regarde (au-dessus du couvercle).
func _face(box: MysteryBox, dir: Vector3, dist: float) -> void:
	var c := box.global_position
	p.teleport_to(c + dir.normalized() * dist + Vector3.UP * 0.05)
	await seconds(0.3)
	AutotestHelpers.aim_at(p, c + Vector3.UP * MysteryBox.SIGHT_HEIGHT)
	await frames(3)


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
