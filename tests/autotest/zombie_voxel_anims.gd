extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## Animations du zombie cubique (ZombieAnim, rampant de ZombieGibs) : une
## planche par animation, images clés côte à côte (k = 0 à 1), de profil et de
## trois quarts, sous un éclairage de revue (TEST ARENA) : marche, course,
## sprint, sortie du sol, arrachage de planches (planche figurée), pause de
## folie, passage de fenêtre (allège figurée), attaque, attaque à travers les
## planches, rampant, morts. Captures à faire valider (fonction en cours), puis
## retirées. Marionnettes posées par tests/zombie_anim_samples.gd.

const Samples := preload("res://tests/zombie_anim_samples.gd")
const FRAMES := 6
## Centre de la scène (point de départ du joueur), fixé au lancement.
var STAGE := Vector3.ZERO
## [animation, écart entre images (m), décor : "" / "fenetre" / "planche" / "sol"]
const BOARDS := [
	["marche", 1.15, ""], ["course", 1.25, ""], ["sprint", 1.35, ""],
	["sortie_du_sol", 1.2, "sol"], ["arrachage", 1.3, "planche"], ["folie", 1.3, "planche"],
	["passage_fenetre", 2.6, "fenetre"], ["attaque", 1.3, ""], ["attaque_fenetre", 1.3, "planche"],
	["rampant", 1.6, ""], ["chute_rampant", 1.6, ""],
	["mort_bascule", 2.0, ""], ["mort_genoux", 2.0, ""], ["mort_vrille", 2.0, ""], ["mort_raide", 2.0, ""],
]

var H := AutotestHelpers
var game: Game
var cam: Camera3D
var _nodes: Array[Node] = []
var _next := 64001
var _only: Array = []


func run() -> void:
	timeout_sec = 300
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--anims="):
			_only = a.trim_prefix("--anims=").split(",")
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
	cam.fov = 32.0
	cam.far = 80.0
	# Seulement les zombies (couche 2) et le décor de revue : les murs de la
	# carte ne masquent pas la planche.
	cam.cull_mask = ZombieModel.RENDER_LAYERS
	# Environnement de revue propre à la caméra (ni brume ni étalonnage de
	# la carte) : fond gris, lumière ambiante douce.
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
	# Éclairage de revue (le quai est sombre) : lumière de face, en hauteur.
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.shadow_enabled = false
	game.add_child(sun)
	sun.look_at_from_position(STAGE + Vector3(2.0, 4.0, 6.0), STAGE)
	# Sol de revue (la carte n'est pas rendue) : gris moyen.
	_box(STAGE + Vector3(0, -0.01, 0), Vector3(40.0, 0.02, 12.0), Color(0.42, 0.42, 0.44))
	var floor_node: Node = _nodes.pop_back()
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	game.add_child(fill)
	fill.look_at_from_position(STAGE + Vector3(-3.0, 2.0, -4.0), STAGE)
	for b in BOARDS:
		if not _only.is_empty() and not b[0] in _only:
			continue
		await _board(b[0], b[1], b[2])
	floor_node.queue_free()
	fill.queue_free()
	p.camera.make_current()
	cam.queue_free()


func _board(anim: String, gap: float, prop: String) -> void:
	var width := gap * (FRAMES - 1)
	var zs: Array[Zombie] = []
	for i in FRAMES:
		var k := float(i) / (FRAMES - 1)
		var x := (float(i) - (FRAMES - 1) * 0.5) * gap
		var base := STAGE + Vector3(x, 0, 0)
		var z: Zombie = Samples.make(game.zombies, anim, 7, _next)
		_next += 1
		_nodes.append(z)
		zs.append(z)
		# Profil : le zombie regarde vers +X (vers la droite de l'image).
		z.yaw = PI * 0.5
		z.rotation.y = PI * 0.5
		var pos := base
		if prop == "fenetre":
			# Même trajet que Zombie._vault : de dehors (TEAR_DIST) à dedans.
			var e := ease(k, -1.6)
			pos = base + Vector3(lerpf(-Barricade.TEAR_DIST, Barricade.INSIDE_DIST, e), 0, 0)
			_box(base + Vector3(0, Barricade.SILL_TOP * 0.5, 0), Vector3(0.3, Barricade.SILL_TOP, 0.9), Color(0.35, 0.33, 0.3))
		elif prop == "planche":
			# Planche du haut à arracher, devant le zombie (Barricade.PLANK_Z).
			var d := Barricade.TEAR_DIST + Barricade.PLANK_Z
			_box(base + Vector3(d + 0.15, Barricade.SILL_TOP * 0.5, 0), Vector3(0.3, Barricade.SILL_TOP, 1.0), Color(0.35, 0.33, 0.3))
			# Arrachage : planche en place avant TEAR_RIP, puis dans les mains.
			if anim != "arrachage" or k < BarricadeRules.TEAR_RIP:
				_box(base + Vector3(d + 0.02, 1.55, 0), Vector3(0.045, 0.17, 1.0), Color(0.45, 0.32, 0.2))
		elif prop == "sol":
			# Trou de sortie (repère du niveau du sol).
			_box(base + Vector3(0.25, 0.005, 0), Vector3(0.9, 0.01, 0.7), Color(0.12, 0.09, 0.07))
		z.global_position = pos
		Samples.pose(z, anim, k)
		if anim == "arrachage" and k >= BarricadeRules.TEAR_RIP:
			var hl := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.forearm_l) * Vector3(0, -0.45, 0)
			var hr := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.forearm_r) * Vector3(0, -0.45, 0)
			_box((hl + hr) * 0.5, Vector3(0.17, 0.045, 1.0), Color(0.45, 0.32, 0.2))
	await seconds(0.25)
	# Profil.
	var h := 0.75 if anim.begins_with("mort") or anim.contains("rampant") else 1.0
	var dist := width + (3.4 if prop == "fenetre" else 1.6)
	cam.look_at_from_position(STAGE + Vector3(0, h + 0.25, dist), STAGE + Vector3(0, h - 0.05, 0))
	await seconds(0.15)
	await at.screenshot("%s_profil" % anim)
	# Trois quarts avant (côté visage).
	cam.look_at_from_position(STAGE + Vector3(width * 0.55 + 2.2, h + 0.9, dist * 0.75), STAGE + Vector3(width * 0.1, h - 0.1, 0))
	await seconds(0.15)
	await at.screenshot("%s_34" % anim)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await frames(2)


func _box(pos: Vector3, size: Vector3, col: Color) -> void:
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
