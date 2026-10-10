extends AutotestScenario
## @rendu : a besoin du rendu (fenêtre hors écran).
## Contour noir en jeu (ScreenOutline, OPTIONS > VIDÉO > CONTOUR) sur BUNKER
## K-7 : zombies du jeu immobiles et zombies « patient » cubiques (2,5 cm,
## pose de repos), décor en cubes de 5 cm. Pour chaque vue, captures avec et
## sans contour ; vérifie que l'option affiche / masque la passe, que le trait
## noircit des pixels sur les vues chargées, et qu'il en noircit très peu sur
## une grande surface plane (pas de traits parasites).
## Captures : tests/_out/shots/outline_look_<vue>_on|off.png.

var H := AutotestHelpers
const PATIENT := "res://assets/models/zombies/zombie_voxel.glb"
## [nom, cellule du joueur, cellule visée, hauteur visée (m)]
const VIEWS := [
	["labo", Vector2i(35, 31), Vector2i(52, 18), 1.0],
	["patients", Vector2i(20, 9), Vector2i(46, 4), 1.0],
	["couloir", Vector2i(20, 23), Vector2i(32, 24), 1.0],
	["quai", Vector2i(20, 9), Vector2i(46, 4), 1.0],
	["generateur", Vector2i(55, 22), Vector2i(61, 28), 1.0],
]

var game: Game
var p: Player
var outline: ScreenOutline


func run() -> void:
	timeout_sec = 240
	var keep := Settings.outline
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	outline = game.world.get_node_or_null("ScreenOutline") as ScreenOutline
	at.check(outline != null, "passe de contour créée avec l'environnement de la carte")
	if outline == null:
		return
	at.check(ScreenOutline.supported(), "moteur Forward+ : profondeur disponible (%s)" % RenderingServer.get_current_rendering_method())
	Settings.outline = true
	Settings.changed.emit()
	at.check(outline.visible, "contour affiché (option activée)")
	Settings.outline = false
	Settings.changed.emit()
	at.check(not outline.visible, "contour masqué (option désactivée)")
	Settings.outline = true
	Settings.changed.emit()

	# Zombies du jeu immobiles devant le joueur, de 2 à 9 m, dans le labo.
	var from := MapData.cell_to_world(Vector2i(35, 31), 0.05)
	var dir := (MapData.cell_to_world(Vector2i(52, 18)) - from).normalized()
	for i in 8:
		var pos := from + dir * (2.0 + i) + Vector3(dir.z, 0, -dir.x) * (0.9 if i % 2 else -0.9)
		var zid: int = game.zombies.spawn(Vector3(pos.x, 0.0, pos.z), 0, 1000000)
		game.zombies.get_zombie(zid).speed_mult = 0.0
	# Émergence des zombies, et l'annonce « courant rétabli » s'efface.
	await seconds(maxf(Zombie.EMERGE_TIME + 0.5, 6.0))

	for v in VIEWS:
		await _view(v)
	# Grande surface plane : le sol du labo vu en plongée, sans rien devant.
	await H.clear_zombies(self)
	_clear_patients()
	p.teleport_to(MapData.cell_to_world(Vector2i(44, 30), 0.05))
	H.aim_at(p, MapData.cell_to_world(Vector2i(44, 26), 0.0))
	p.weapons.view.visible = false
	await seconds(0.6)
	var d := await _pair("sol")
	at.check(d < 0.01, "sol plan : %.2f %% de pixels noircis (aucun trait parasite)" % (d * 100.0))
	p.weapons.view.visible = true
	Settings.outline = keep
	Settings.changed.emit()


func _view(v: Array) -> void:
	_clear_patients()
	p.teleport_to(MapData.cell_to_world(v[1], 0.05))
	var target := MapData.cell_to_world(v[2], v[3])
	if v[0] == "patients":
		# Trois zombies « patient » cubiques à 1,6 / 2,4 / 3,5 m (face, 3/4, profil).
		var cam := p.camera.global_position
		var dir := (target - cam)
		dir.y = 0.0
		dir = dir.normalized()
		var side := Vector3(dir.z, 0, -dir.x)
		var dists := [1.6, 2.4, 3.5]
		var offs := [-0.55, 0.45, -0.2]
		var rots := [PI, PI * 0.75, PI * 0.5]
		for i in 3:
			var at_pos: Vector3 = cam + dir * dists[i] + side * offs[i]
			_patient(Vector3(at_pos.x, 0.0, at_pos.z), atan2(dir.x, dir.z) + rots[i])
		target = cam + dir * 2.4 + Vector3(0, -0.55, 0)
	H.aim_at(p, target)
	await seconds(0.8)
	var d := await _pair(v[0])
	at.check(d > 0.0008, "%s : le contour noircit %.2f %% des pixels" % [v[0], d * 100.0])


## Zombie « patient » cubique au repos (maillage seul, matériau des zombies).
func _patient(pos: Vector3, yaw: float) -> void:
	var m := ZombieGlb.load_model(PATIENT)
	if m.is_empty():
		at.fail("modèle %s introuvable" % PATIENT)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m.mesh
	mi.material_override = ZombieModel.material()
	mi.add_to_group("outline_look_patients")
	game.world.add_child(mi)
	mi.global_position = pos
	mi.rotation.y = yaw


func _clear_patients() -> void:
	for n in tree().get_nodes_in_group("outline_look_patients"):
		n.queue_free()


## Gros plan du centre (x2, sans filtrage), avec et sans contour côte à côte :
## le trait d'un pixel se juge pixel par pixel.
func _save_crops(view: String, on: Image, off: Image) -> void:
	var w := int(on.get_width() / 3.0)
	var h := int(on.get_height() / 3.0)
	var r := Rect2i(w, h, w, h)
	var sheet := Image.create(w * 4, h * 2, false, on.get_format())
	var a := on.get_region(r)
	var b := off.get_region(r)
	a.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	b.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	sheet.blit_rect(a, Rect2i(0, 0, w * 2, h * 2), Vector2i.ZERO)
	sheet.blit_rect(b, Rect2i(0, 0, w * 2, h * 2), Vector2i(w * 2, 0))
	var dir := ProjectSettings.globalize_path("res://tests/_out/shots")
	sheet.save_png("%s/outline_look_%s_zoom.png" % [dir, view])


## Captures avec puis sans contour ; renvoie la part des pixels nettement
## plus sombres avec le contour.
func _pair(view: String) -> float:
	var grain := Settings.film_grain
	Settings.film_grain = 0.0  # comparaison pixel à pixel sans le grain
	Settings.outline = true
	Settings.changed.emit()
	await frames(3)
	var on := at.get_viewport().get_texture().get_image()
	Settings.outline = false
	Settings.changed.emit()
	await frames(3)
	var off := at.get_viewport().get_texture().get_image()
	Settings.film_grain = grain
	Settings.outline = true
	Settings.changed.emit()
	await at.screenshot(view + "_on")
	Settings.outline = false
	Settings.changed.emit()
	await at.screenshot(view + "_off")
	Settings.outline = true
	Settings.changed.emit()
	if on == null or off == null or on.get_size() != off.get_size():
		return 0.0
	_save_crops(view, on, off)
	var dark := 0
	var n := 0
	for y in range(0, on.get_height(), 2):
		for x in range(0, on.get_width(), 2):
			n += 1
			if off.get_pixel(x, y).get_luminance() - on.get_pixel(x, y).get_luminance() > 0.08:
				dark += 1
	var frac := float(dark) / maxf(n, 1)
	print("[outline_look] %s : %.2f %% de pixels noircis" % [view, frac * 100.0])
	return frac
