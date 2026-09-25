class_name Warmup
extends Node3D
## Préchauffage des shaders pendant l'écran de chargement.
##
## Affiche une fois chaque type de matériau (zombie, armes normales et
## améliorées, particules, décalques, sang...) devant une caméra temporaire
## qui balaie la salle de départ : les pipelines sont compilés AVANT que le
## joueur ne prenne la main, sans saccade en début de partie.

const FRAMES := 24

var _cam: Camera3D


static func run(game: Game, at: Vector3) -> void:
	var w := Warmup.new()
	w.name = "Warmup"
	game.world.add_child(w)
	w.global_position = at
	await w._run(game)
	w.queue_free()


func _run(game: Game) -> void:
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.6, 0)
	_cam.far = 60.0
	add_child(_cam)
	_cam.make_current()
	var stage := Node3D.new()
	stage.position = Vector3(0, 1.2, -2.0)
	_cam.add_child(stage)
	# Zombie (matériau personnage, skinning, émission des yeux, dissolution).
	var z := ZombieModel.build(12345)
	z.position = Vector3(-0.8, -1.2, -1.0)
	stage.add_child(z)
	(z.get_node("Mesh") as MeshInstance3D).set_instance_shader_parameter("dissolve", 0.3)
	# Armes (vue FPS et monde, normales et améliorées).
	var x := -1.0
	for id in WeaponDB.WEAPONS:
		var model: String = WeaponDB.WEAPONS[id].model
		for pap in [false, true]:
			var m := WeaponModels.build(model, true, pap)
			m.position = Vector3(x, 0.2 if pap else -0.2, 0)
			stage.add_child(m)
		var mw := WeaponModels.build(model, false)
		mw.position = Vector3(x, 0.5, 0)
		stage.add_child(mw)
		x += 0.3
	# Matériaux créés à l'apparition des joueurs.
	var body := PlayerModel.new()
	body.build(Color.RED)
	body.position = Vector3(1.0, -1.2, -0.5)
	stage.add_child(body)
	body.set_weapon("assault", false)
	# Effets.
	var fx := game.fx_root
	var p := stage.global_position
	fx.impact(p, Vector3.BACK, false)
	fx.blood_hit(p, Vector3.FORWARD, 1.0)
	fx.dirt_burst(p + Vector3.DOWN * 1.2)
	fx.tracer(p + Vector3.LEFT, p + Vector3.RIGHT)
	fx.muzzle_flash(p)
	for i in FRAMES:
		rotation.y = TAU * float(i) / FRAMES
		await get_tree().process_frame
