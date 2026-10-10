extends AutotestScenario
## @rendu : a besoin du rendu (fenêtre hors écran).
## Animations du chien cubique (DogAnim) : une planche par animation, images
## clés côte à côte (k = 0 à 1), de profil et de trois quarts, sous un
## éclairage de revue (TEST ARENA) : galop, trot, apparition (jaillit
## accroupi), bond et morsure, mort (sur le flanc). Captures à faire valider
## (fonction en cours), puis retirées.

const FRAMES := 6
## [animation, écart entre images (m)]
const BOARDS := [["galop", 2.0], ["trot", 2.0], ["apparition", 2.0], ["bond", 2.2], ["mort", 2.0]]

var H := AutotestHelpers
var game: Game
var cam: Camera3D
var STAGE := Vector3.ZERO
var _nodes: Array[Node] = []
var _next := 65001


func run() -> void:
	timeout_sec = 200
	var p := await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	STAGE = Vector3(p.global_position.x, 0.0, p.global_position.z)
	p.teleport_to(STAGE + Vector3(0, 0.05, 14.0), 0.0)
	game.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 30.0
	cam.far = 80.0
	cam.cull_mask = ZombieModel.RENDER_LAYERS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cam.environment = env
	game.add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	game.add_child(sun)
	sun.look_at_from_position(STAGE + Vector3(2.0, 4.0, 6.0), STAGE)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	game.add_child(fill)
	fill.look_at_from_position(STAGE + Vector3(-3.0, 2.0, -4.0), STAGE)
	var floor_mi := _box(STAGE + Vector3(0, -0.01, 0), Vector3(40.0, 0.02, 12.0), Color(0.42, 0.42, 0.44))
	_nodes.erase(floor_mi)
	for b in BOARDS:
		await _board(b[0], b[1])
	floor_mi.queue_free()
	sun.queue_free()
	fill.queue_free()
	p.camera.make_current()
	cam.queue_free()


func _pose_for(anim: String, k: float) -> Dictionary:
	match anim:
		"galop":
			return DogAnim.pose(k * TAU, 1.0, 0.0)
		"trot":
			return DogAnim.pose(k * TAU, 0.45, 0.0)
		"apparition":
			return DogAnim.pose(0.6, 1.0, 0.0, -1.0, k)
		"bond":
			return DogAnim.pose(0.6, 1.0, 0.0, k)
		_:
			return DogAnim.pose(0.0, 0.0, 0.0, -1.0, -1.0, k * 1.6, 1.0)


func _board(anim: String, gap: float) -> void:
	var width := gap * (FRAMES - 1)
	for i in FRAMES:
		var k := float(i) / (FRAMES - 1)
		var d := Hellhound.new()
		d.setup(_next, i, 3, false)
		_next += 1
		game.zombies.add_child(d)
		d.set_process(false)
		d.set_physics_process(false)
		_nodes.append(d)
		# Profil : le chien regarde vers +X (droite de l'image).
		d.yaw = PI * 0.5
		d.rotation.y = PI * 0.5
		d.global_position = STAGE + Vector3((float(i) - (FRAMES - 1) * 0.5) * gap, 0, 0)
		d.skel.visible = true
		DogAnim.apply(d.skel, d.bones, _pose_for(anim, k))
	await seconds(0.25)
	var h := 0.5
	var dist := width + 1.8
	cam.look_at_from_position(STAGE + Vector3(0, h + 0.2, dist), STAGE + Vector3(0, h - 0.05, 0))
	await seconds(0.15)
	await at.screenshot("%s_profil" % anim)
	cam.look_at_from_position(STAGE + Vector3(width * 0.55 + 2.2, h + 1.0, dist * 0.7), STAGE + Vector3(width * 0.1, h - 0.1, 0))
	await seconds(0.15)
	await at.screenshot("%s_34" % anim)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await frames(2)


func _box(pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	bm.material = mat
	mi.mesh = bm
	mi.layers = ZombieModel.RENDER_LAYERS
	game.add_child(mi)
	mi.global_position = pos
	_nodes.append(mi)
	return mi
