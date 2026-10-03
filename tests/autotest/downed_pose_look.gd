extends AutotestScenario
## @rendu : a besoin du rendu (fenêtre hors écran).
## @niveau perf
## Hors check (captures à regarder, pas de mesure) : à lancer à la main,
##   sh tools/scenario.sh downed_pose_look
## Pose « à terre » (dernier recours BO1) des sept personnages, dans un
## studio construit hors de la carte : de face, de profil, de dos et de
## trois quarts ; chute et relevé image par image ; en pente (montée et
## descente), face à un mur, sur une marche ; vue 1re personne du joueur à
## terre (avec un coéquipier à terre devant lui) ; mort couché sur le dos.
## Les mesures (sol, appui, caméra) sont dans tests/test_downed_pose.gd.

var H := AutotestHelpers
var game: Game
var cam: Camera3D
var studio: Node3D
const O := Vector3(0, 60, 0)
const DT := 1.0 / 60.0


func run() -> void:
	timeout_sec = 240
	var p := await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	game.hud.visible = false
	_build_studio()
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 60.0
	game.add_child(cam)
	cam.make_current()

	# Les sept personnages assis, côte à côte (regard vers -Z).
	var models: Array[PlayerModel] = []
	for ch in CharacterDB.IDS.size():
		var m := _model(ch, O + Vector3((ch - 3) * 1.6, 0, 0), 0.0)
		models.append(m)
	await _animate(models, 90, true)
	_look(O + Vector3(0, 2.6, -8.5), O + Vector3(0, 0.3, -0.6))
	await at.screenshot("rangee_face")
	_look(O + Vector3(-6.5, 3.2, 4.0), O + Vector3(0, 0.3, -0.5))
	await at.screenshot("rangee_dos")
	for ch in models.size():
		var m := models[ch]
		for o in models:
			o.visible = o == m
		var c := m.global_position
		var id: String = CharacterDB.IDS[ch]
		for v in [["face", Vector3(0.0, 0.9, -2.6)], ["profil", Vector3(-2.6, 0.7, -0.6)], ["dos", Vector3(0.6, 1.3, 2.2)], ["34", Vector3(-1.8, 1.3, -1.9)]]:
			_look(c + v[1], c + Vector3(0, 0.4, -0.5))
			await at.screenshot("%s_%s" % [id, v[0]])
	# Visée : regard levé puis baissé (Callahan).
	for o in models:
		o.visible = o == models[0]
	for pitch in [0.6, -0.6]:
		await _animate([models[0]], 40, true, pitch)
		_look(models[0].global_position + Vector3(-2.6, 0.7, -0.6), models[0].global_position + Vector3(0, 0.5, -0.5))
		await at.screenshot("visee_%s" % ("haut" if pitch > 0.0 else "bas"))
	await _animate([models[0]], 30, true)
	# Chute et relevé (Mercer), de profil.
	var mercer := models[4]
	for o in models:
		o.visible = o == mercer
	await _animate([mercer], 90, false)
	_look(mercer.global_position + Vector3(-3.0, 1.0, -0.4), mercer.global_position + Vector3(0, 0.7, -0.4))
	for i in 6:
		await _animate([mercer], 6, true)
		await at.screenshot("chute_%d" % i)
	for i in 6:
		await _animate([mercer], 6, false)
		await at.screenshot("releve_%d" % i)
	for m in models:
		m.queue_free()

	# Pente (montée et descente), mur, marche.
	var slope_up := _model(0, O + Vector3(21.5, 0, 2.2), 0.0)
	var slope_down := _model(6, O + Vector3(21.5, 0, -2.2), PI)
	var wall := _model(4, O + Vector3(30, 0, 0), 0.0)
	var step := _model(5, O + Vector3(36, 0.2, 0.0), 0.0)
	for m in [slope_up, slope_down]:
		m.global_position.y = _floor_y(m.global_position)
	var lst: Array[PlayerModel] = [slope_up, slope_down, wall, step]
	await _animate(lst, 120, true)
	_look(O + Vector3(16.0, 2.4, 0.0), O + Vector3(21.5, 1.3, 0.0))
	await at.screenshot("pente_profil")
	_look(O + Vector3(21.5, 3.6, -6.0), O + Vector3(21.5, 1.6, -1.0))
	await at.screenshot("pente_face")
	_look(wall.global_position + Vector3(-2.6, 1.0, 0.2), wall.global_position + Vector3(0, 0.4, -0.3))
	await at.screenshot("mur_profil")
	_look(step.global_position + Vector3(-2.6, 1.0, -0.2), step.global_position + Vector3(0, 0.5, -0.4))
	await at.screenshot("marche_profil")
	for m in lst:
		m.queue_free()

	# Mort : couché sur le dos.
	var dead := _model(1, O + Vector3(0, 0, 6), 0.0)
	var arr: Array[PlayerModel] = [dead]
	await _animate(arr, 150, true, 0.0, true)
	_look(dead.global_position + Vector3(-2.6, 1.2, -0.3), dead.global_position + Vector3(0, 0.2, 0.0))
	await at.screenshot("mort_profil")
	dead.queue_free()

	# Vue 1re personne du joueur à terre, un coéquipier à terre devant lui.
	var mate := _model(5, O + Vector3(0.6, 0, -3.2), PI * 0.8)
	var mates: Array[PlayerModel] = [mate]
	await _animate(mates, 90, true)
	p.teleport_to(O + Vector3(0, 0.05, 0), 0.0)
	p.set_downed(true)
	p.camera.make_current()
	await seconds(1.2)
	at.check(absf(p.head.position.y - p.downed_eye()) < 0.05, "caméra à terre à la hauteur de la tête assise (%.2f m)" % p.head.position.y)
	await at.screenshot("vue_a_terre")
	p.set_downed(false)
	await seconds(0.8)
	await at.screenshot("vue_debout")
	mate.queue_free()


func _model(ch: int, pos: Vector3, yaw: float) -> PlayerModel:
	var m := PlayerModel.new()
	m.build(ScorePanel.slot_color(ch % 4), ch)
	studio.add_child(m)
	m.global_position = pos
	m.rotation.y = yaw
	m.set_weapon("m1911", false)
	return m


func _animate(ms: Array, n: int, downed: bool, pitch := 0.0, dead := false) -> void:
	for i in n:
		for m: PlayerModel in ms:
			m.animate(DT, 0.0, pitch, 0, downed, dead)
		await tree().physics_frame


func _look(from: Vector3, to: Vector3) -> void:
	cam.global_position = from
	cam.look_at(to)


func _floor_y(pos: Vector3) -> float:
	var space := studio.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 3.0, 1))
	return hit.position.y if not hit.is_empty() else pos.y


## Studio hors carte : sol, rampe à 15°, mur, marche, éclairage neutre.
func _build_studio() -> void:
	studio = Node3D.new()
	studio.name = "DownedStudio"
	game.add_child(studio)
	_box(O + Vector3(15, -0.1, 0), Vector3(50, 0.2, 20), Basis.IDENTITY, Color(0.35, 0.33, 0.3))
	# Rampe (montée vers -Z), sous les deux premiers modèles.
	_box(O + Vector3(21.5, 1.25, 0.0), Vector3(5, 0.2, 9), Basis(Vector3.RIGHT, deg_to_rad(15.0)), Color(0.4, 0.36, 0.3))
	# Mur à 0,9 m devant Mercer.
	_box(O + Vector3(30, 1.0, -0.9 - 0.1), Vector3(3, 2.0, 0.2), Basis.IDENTITY, Color(0.45, 0.42, 0.38))
	# Marche de 20 cm sous Berg, puis la suivante à 0,8 m devant elle.
	_box(O + Vector3(36, 0.1, 0.0), Vector3(3, 0.2, 1.6), Basis.IDENTITY, Color(0.4, 0.38, 0.35))
	_box(O + Vector3(36, 0.2, -1.6), Vector3(3, 0.4, 1.6), Basis.IDENTITY, Color(0.4, 0.38, 0.35))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	studio.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = O + Vector3(0, 4, -4)
	fill.omni_range = 30.0
	fill.light_energy = 1.0
	studio.add_child(fill)


func _box(center: Vector3, size: Vector3, basis: Basis, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	studio.add_child(body)
	body.global_transform = Transform3D(basis, center)
