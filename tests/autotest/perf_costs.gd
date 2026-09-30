extends AutotestScenario
## Coût GPU de chaque poste de rendu, mesuré en A/B alterné sur la même vue
## (méthode de docs/ARCHITECTURE.md, « Rendu et performances ») :
##   1. BUNKER K-7, laboratoire, 24 zombies au contact (ombres redessinées) ;
##   2. KINO, la scène vue depuis l'allée centrale de la salle, sans zombie.
## Pour chaque poste, on le coupe seul et on mesure le temps GPU moyen du
## viewport (RenderingServer.viewport_get_measured_render_time_gpu) et le
## nombre de draw calls ; les modes sont alternés plusieurs fois pour
## résister au bruit. Scénario de mesure (pas de check de perf) :
##   sh tools/perf.sh perf_costs          (QUALITY=low|medium|high)

var H := AutotestHelpers
var game: Game
var p: Player
var env: Environment
var post: FilmPost
const REPS := 4
const PLAIN_SURFACE := preload("res://tests/autotest/perf_plain_surface.gdshader")
const SAMPLES := 24


func run() -> void:
	timeout_sec = 280
	await _bunker_pass()
	if p == null:
		return
	Router.back_to_menu()
	await seconds(1.0)
	await _kino_pass()


func _start(map_id: String) -> bool:
	p = await H.start_solo_game(self, map_id)
	if p == null:
		return false
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	env = (game.world.get_node("WorldEnvironment") as WorldEnvironment).environment
	post = game.world.get_node("FilmPost")
	return true


func _bunker_pass() -> void:
	if not await _start("bunker_k7"):
		return
	if game.barricades:
		for b in game.barricades.windows:
			b.srv_set_mask(0)
	# Labo : la horde rejoint le joueur (comme zombie_stress, « au contact »).
	p.teleport_to(MapData.cell_to_world(Vector2i(38, 24), 0.05))
	H.aim_at(p, MapData.cell_to_world(Vector2i(52, 18), 1.2))
	var spots: Array = game.map_data.markers.get("Z", [])
	for i in 24:
		var c: Vector2i = spots[(i * 7) % spots.size()]
		game.zombies.spawn(MapData.cell_to_world(c), i % 4, 1000000)
	await until(func():
		var near := 0
		for z: Zombie in game.zombies.alive:
			if z.global_position.distance_to(p.global_position) < 9.0:
				near += 1
		return near >= 18, 25.0, "horde au contact")
	# Vue vers la horde (la moitié environ à l'écran).
	var c := Vector3.ZERO
	for z: Zombie in game.zombies.alive:
		c += z.global_position
	c /= maxf(game.zombies.alive.size(), 1)
	H.aim_at(p, c + Vector3(0, 1.0, 0))
	await seconds(1.0)
	await at.screenshot("horde")
	await _ab("labo+24", _modes(true))


func _kino_pass() -> void:
	if not await _start("kino"):
		return
	# Allée centrale de la salle de théâtre, vers la scène (ruines, fauteuils,
	# écran, tour du téléporteur et lustres : la vue la plus chargée).
	p.teleport_to(Vector3(75.0, 0.35, 66.0))
	H.aim_at(p, Vector3(75.0, 3.0, 41.0))
	await seconds(2.0)
	await at.screenshot("scene")
	await _ab("kino scene", _modes(false))


## [nom, fonction(on: bool)] : on = false coupe le poste.
func _modes(zombies: bool) -> Array:
	var m := []
	m.append(["brume volumétrique", func(on: bool): env.volumetric_fog_enabled = on and RenderQuality.current().volumetric_fog])
	m.append(["post-traitement", func(on: bool): post.visible = on])
	m.append(["glow", func(on: bool): env.glow_enabled = on and RenderQuality.current().glow])
	m.append(["étalonnage (LUT)", func(on: bool): env.adjustment_enabled = on])
	m.append(["ombres des lampes", func(on: bool):
		for l: OmniLight3D in tree().get_nodes_in_group(RenderQuality.LAMP_GROUP):
			l.shadow_enabled = on and RenderQuality.lamp_has_shadow(int(l.get_meta("lamp_index", 0)), RenderQuality.current())])
	m.append(["lampes (toutes)", func(on: bool):
		for l: OmniLight3D in tree().get_nodes_in_group(RenderQuality.LAMP_GROUP):
			l.visible = on])
	m.append(["arme FPS + mains", func(on: bool): p.weapons.view.visible = on])
	m.append(["HUD", func(on: bool): game.hud.visible = on])
	m.append(["décalques", func(on: bool):
		for d: Decal in tree().get_nodes_in_group(RenderQuality.DECAL_GROUP):
			d.visible = on])
	m.append(["vignette de blessure (HUD)", func(on: bool): game.hud._vignette.visible = on])
	m.append(["surface.gdshader (vs couleur unie)", func(on: bool):
		for key in WorldLook.SURFACES:
			(WorldLook.surface(key) as ShaderMaterial).shader = WorldLook.surface_shader(key) if on else PLAIN_SURFACE])
	# Variantes (« off » = variante moins chère) : gain de chacune.
	var q := RenderQuality.current()
	m.append(["~ ombres omni cube -> paraboloïde", func(on: bool):
		for l: OmniLight3D in tree().get_nodes_in_group(RenderQuality.LAMP_GROUP):
			l.omni_shadow_mode = OmniLight3D.SHADOW_CUBE if on else OmniLight3D.SHADOW_DUAL_PARABOLOID])
	m.append(["~ atlas d'ombres -> moitié", func(on: bool):
		at.get_viewport().positional_shadow_atlas_size = q.shadow_atlas if on else q.shadow_atlas / 2])
	m.append(["~ filtre d'ombre -> dur", func(on: bool):
		RenderingServer.positional_soft_shadow_filter_set_quality(q.shadow_filter if on else RenderingServer.SHADOW_QUALITY_HARD)])
	m.append(["~ brume -> 48x48x32", func(on: bool):
		RenderingServer.environment_set_volumetric_fog_volume_size(q.fog_volume[0] if on else 48, q.fog_volume[1] if on else 32)])
	m.append(["~ brume sans filtre", func(on: bool):
		RenderingServer.environment_set_volumetric_fog_filter_active(on)])
	m.append(["~ brume : portée 32 -> 20 m", func(on: bool):
		env.volumetric_fog_length = 32.0 if on else 20.0])
	var lambert := Shader.new()
	lambert.code = WorldLook.SURFACE.code.replace("render_mode cull_back;", "render_mode cull_back, diffuse_lambert;")
	m.append(["~ surfaces : diffus Lambert", func(on: bool):
		for key in WorldLook.SURFACES:
			(WorldLook.surface(key) as ShaderMaterial).shader = WorldLook.surface_shader(key) if on else lambert])
	var flat := Shader.new()
	flat.code = WorldLook.SURFACE.code.replace("float noise2(vec2 p) {", "float noise2(vec2 p) {\n\treturn 0.5;")
	m.append(["~ surfaces : bruit gratuit (borne)", func(on: bool):
		for key in WorldLook.SURFACES:
			(WorldLook.surface(key) as ShaderMaterial).shader = WorldLook.surface_shader(key) if on else flat])
	var nospec := Shader.new()
	nospec.code = WorldLook.SURFACE.code.replace("render_mode cull_back;", "render_mode cull_back, specular_disabled;")
	m.append(["~ surfaces sans spéculaire", func(on: bool):
		for key in WorldLook.SURFACES:
			(WorldLook.surface(key) as ShaderMaterial).shader = WorldLook.surface_shader(key) if on else nospec])
	var lnospec := Shader.new()
	lnospec.code = WorldLook.SURFACE.code.replace("render_mode cull_back;", "render_mode cull_back, diffuse_lambert, specular_disabled;")
	m.append(["~ surfaces : Lambert sans spéculaire", func(on: bool):
		for key in WorldLook.SURFACES:
			(WorldLook.surface(key) as ShaderMaterial).shader = WorldLook.surface_shader(key) if on else lnospec])
	m.append(["~ lampes : spéculaire coupé", func(on: bool):
		for l: OmniLight3D in tree().get_nodes_in_group(RenderQuality.LAMP_GROUP):
			l.light_specular = 0.5 if on else 0.0])
	m.append(["~ glow sans le niveau 6", func(on: bool):
		env.set_glow_level(5, WorldLook.GLOW_LEVELS[5] if on else 0.0)])
	m.append(["~ glow sans les niveaux 2 et 6", func(on: bool):
		env.set_glow_level(1, WorldLook.GLOW_LEVELS[1] if on else 0.0)
		env.set_glow_level(5, WorldLook.GLOW_LEVELS[5] if on else 0.0)])
	m.append(["~ post-traitement sans lecture d'écran", func(on: bool):
		post.material.shader = FilmPost.SHADER if on else FilmPost.SHADER_LOW])
	m.append(["~ lampes : portée x0,85", func(on: bool):
		for l: OmniLight3D in tree().get_nodes_in_group(RenderQuality.LAMP_GROUP):
			if not l.has_meta("range0"):
				l.set_meta("range0", l.omni_range)
			l.omni_range = float(l.get_meta("range0")) * (1.0 if on else 0.85)])
	if RenderQuality.current().ssao:
		m.append(["SSAO", func(on: bool): env.ssao_enabled = on])
	if at.get_viewport().msaa_3d != Viewport.MSAA_DISABLED:
		m.append(["MSAA", func(on: bool): at.get_viewport().msaa_3d = RenderQuality.current().msaa if on else Viewport.MSAA_DISABLED])
	if zombies:
		m.append(["zombies (tout)", func(on: bool):
			for z: Zombie in game.zombies.alive:
				z.skel.visible = on])
		m.append(["ombres des zombies (préréglage)", func(on: bool):
			ZombieShadows.debug_count = -1 if on else 0
			ZombieShadows.update(game.zombies.alive, p.camera.global_position, RenderQuality.current())])
		# Négatif : surcoût d'ombres sur les 24 zombies (avant la limitation).
		m.append(["~ ombres limitées (vs 24 zombies)", func(on: bool):
			ZombieShadows.debug_count = -1 if on else 24
			ZombieShadows.update(game.zombies.alive, p.camera.global_position, RenderQuality.current())])
		var plain := StandardMaterial3D.new()
		plain.vertex_color_use_as_albedo = true
		m.append(["zombie.gdshader (vs matériau simple)", func(on: bool):
			for z: Zombie in game.zombies.alive:
				@warning_ignore("incompatible_ternary")
				z.mesh.material_override = ZombieModel.material() if on else plain])
		var zflat := ShaderMaterial.new()
		zflat.shader = Shader.new()
		zflat.shader.code = "shader_type spatial;\nrender_mode cull_back;\n#include \"res://assets/shaders/zombie_body.gdshaderinc\"\n".replace("#include", "#define FLAT_NOISE\n#include")
		m.append(["~ zombies : bruit gratuit (borne)", func(on: bool):
			for z: Zombie in game.zombies.alive:
				z.mesh.material_override = ZombieModel.material() if on else zflat])
		m.append(["animation des zombies (figés)", func(on: bool):
			for z: Zombie in game.zombies.alive:
				z.set_process(on)
				z.set_physics_process(on)])
	return m


func _ab_shots() -> bool:
	return OS.get_cmdline_user_args().has("--ab-shots") or OS.get_cmdline_args().has("--ab-shots")


## Moyenne sur SAMPLES images : (GPU ms, CPU de rendu ms, draw calls).
func _avg(rid: RID) -> Vector3:
	var acc := Vector3.ZERO
	for i in SAMPLES:
		await frames(1)
		acc += Vector3(RenderingServer.viewport_get_measured_render_time_gpu(rid),
				RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return acc / SAMPLES


## Mesures appariées : référence juste avant chaque poste coupé (résiste à
## la dérive de charge), REPS fois.
func _ab(view: String, modes: Array) -> void:
	var rid := at.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var base_all := Vector3.ZERO
	var n_base := 0
	var deltas := {}
	for rep in REPS:
		for m in modes:
			await frames(4)
			var b := await _avg(rid)
			(m[1] as Callable).call(false)
			await frames(6)
			var r := await _avg(rid)
			# `-- --autotest=perf_costs --ab-shots` : captures des variantes (comparaison visuelle).
			if rep == 0 and String(m[0]).begins_with("~") and _ab_shots():
				await at.screenshot("%s_%s" % [view.validate_filename(), String(m[0]).validate_filename()])
			(m[1] as Callable).call(true)
			if rep == 0 and m == modes[0] and _ab_shots():
				await at.screenshot("%s_reference" % view.validate_filename())
			deltas[m[0]] = deltas.get(m[0], Vector3.ZERO) + (b - r)
			base_all += b
			n_base += 1
	var base := base_all / maxf(n_base, 1)
	print("[cost] %s (%s) : GPU %.2f ms (%.0f fps GPU), CPU rendu %.2f ms, draw calls %.0f" % [view, RenderQuality.current().name, base.x, 1000.0 / maxf(base.x, 0.01), base.y, base.z])
	for m in modes:
		var d: Vector3 = deltas[m[0]] / REPS
		print("[cost]   %-38s GPU %+.2f ms, CPU %+.2f ms (draw calls %+.0f)" % [m[0], d.x, d.y, d.z])
	at.begin_perf()
	await seconds(2.0)
	at.end_perf(view)
