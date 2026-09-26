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
	# Géométrie des armes et des mains calculée en tâche de fond (sans
	# rallonger le chargement) : pas de saccade au premier changement d'arme.
	WeaponModels.precompute_async(Net.player_slot(multiplayer.get_unique_id()))
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
	# Chien de l'enfer (matériau à yeux rouges) et boule de foudre.
	var dog := HellhoundModel.build(1)
	dog.position = Vector3(0.6, -1.2, -1.0)
	stage.add_child(dog)
	var bolt := DogLightning.new()
	bolt.duration = 0.5
	bolt.silent = true
	bolt.position = Vector3(0.3, -1.2, -1.5)
	stage.add_child(bolt)
	# Armes (vue FPS et monde, normales et améliorées).
	# Un petit cube par matériau et variante suffit (même shader pour toutes
	# les armes) : inutile de construire les ~30 modèles de l'arsenal.
	var x := -1.0
	var cube := WeaponModels.warmup_mesh()
	for key in WeaponModels.MATERIALS:
		var k := 0
		for variant in [[true, false], [true, true], [false, false], [false, true]]:
			var mi := MeshInstance3D.new()
			mi.mesh = cube
			mi.material_override = WeaponModels.material(key, variant[0], variant[1])
			mi.position = Vector3(x, -0.2 + k * 0.12, 0)
			stage.add_child(mi)
			k += 1
		x += 0.16
	# Matériaux créés à l'apparition des joueurs.
	var body := PlayerModel.new()
	body.build(Color.RED)
	body.position = Vector3(1.0, -1.2, -0.5)
	stage.add_child(body)
	body.set_weapon("m16", false)
	# Bonus (modèles et halo).
	var px := -0.9
	for type in PowerupRules.ALL:
		var pm := PowerupModels.build(type)
		pm.position = Vector3(px, -0.7, 0.3)
		pm.add_child(PowerupModels.halo(0.6))
		stage.add_child(pm)
		px += 0.36
	# Matériaux propres au décor de la carte, hors de la salle de départ
	# (écran de cinéma, faisceau du projecteur...).
	var qx := -0.9
	for mat: Material in game.props.warmup_materials:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.2, 0.2)
		q.mesh = qm
		q.material_override = mat
		q.position = Vector3(qx, 0.8, 0.2)
		stage.add_child(q)
		qx += 0.25
	# Effets.
	var fx := game.fx_root
	var p := stage.global_position
	fx.impact(p, Vector3.BACK, false)
	fx.blood_hit(p, Vector3.FORWARD, 1.0)
	fx.dirt_burst(p + Vector3.DOWN * 1.2)
	fx.tracer(p + Vector3.LEFT, p + Vector3.RIGHT)
	fx.muzzle_flash(p, Vector3.FORWARD)
	fx.impact(p, Vector3.BACK, false, "metal")
	fx.impact(p, Vector3.BACK, false, "wood")
	fx.eject_shell(p, Vector3.UP, "rifle")
	fx.eject_shell(p, Vector3.UP, "shotgun")
	ProjectileFx.launch(fx, p + Vector3.LEFT, p + Vector3.RIGHT, 8.0, "rocket", false)
	ProjectileFx.launch(fx, p + Vector3.LEFT, p + Vector3.RIGHT, 8.0, "grenade", true)
	for i in FRAMES:
		rotation.y = TAU * float(i) / FRAMES
		await get_tree().process_frame
