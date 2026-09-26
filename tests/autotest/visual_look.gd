extends AutotestScenario
## Direction artistique BO1 (docs/ART_DIRECTION.md) : étalonnage (table 3D),
## brume volumétrique, grain / vignettage / aberration (FilmPost) selon la
## qualité et l'option GRAIN DE FILM ; captures de chaque zone des deux cartes
## (courant coupé puis rétabli, manche de chiens) avec mesure de la
## luminance moyenne (« sombre mais lisible ») et des performances.

var H := AutotestHelpers
## [nom, cellule, cellule visée]
const BUNKER_VIEWS := [
	["garde", Vector2i(9, 29), Vector2i(9, 17)],
	["dortoir", Vector2i(15, 13), Vector2i(3, 3)],
	["couloir", Vector2i(20, 23), Vector2i(32, 24)],
	["labo", Vector2i(35, 31), Vector2i(52, 18)],
	["generateur", Vector2i(55, 22), Vector2i(61, 28)],
	["quai", Vector2i(20, 9), Vector2i(46, 4)],
	["rituel", Vector2i(53, 8), Vector2i(57, 3)],
]
const KINO_VIEWS := [
	["hall", Vector2i(33, 41), Vector2i(33, 28)],
	["foyer", Vector2i(49, 41), Vector2i(68, 30)],
	["loges", Vector2i(12, 31), Vector2i(4, 19)],
	["machines", Vector2i(18, 8), Vector2i(10, 2)],
	["allee", Vector2i(54, 10), Vector2i(69, 3)],
	["theatre", Vector2i(36, 20), Vector2i(36, 3)],
	["scene", Vector2i(36, 6), Vector2i(36, 19)],
	["cabine", Vector2i(39, 25), Vector2i(29, 23)],
]
## Luminance moyenne minimale d'une vue courant rétabli (sRGB, 0..1) : en
## dessous, l'image redevient « trop sombre » (retour de l'utilisateur).
const MIN_LUM_POWERED := 0.05

var game: Game
var p: Player
var worst_fps := 10000.0


func run() -> void:
	timeout_sec = 300
	for map_id in ["bunker_k7", "kino"]:
		await _map_pass(map_id)
		if p == null:
			return
		Router.back_to_menu()
		await seconds(1.0)


func _map_pass(map_id: String) -> void:
	worst_fps = 10000.0
	p = await H.start_solo_game(self, map_id)
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	var env: Environment = (game.world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var post: FilmPost = game.world.get_node("FilmPost")
	at.check(env.adjustment_enabled and env.adjustment_color_correction is ImageTexture3D, "étalonnage BO1 : table 3D (%d³)" % WorldLook.LUT_SIZE)
	at.check(post != null and post.layer < game.hud.layer, "post-traitement sous le HUD (couche %d < %d)" % [post.layer, game.hud.layer])
	await _check_qualities(env, post)
	await _check_grain_option(post)

	var views: Array = KINO_VIEWS if map_id == "kino" else BUNKER_VIEWS
	# Courant coupé : deux vues (éclairage de secours).
	for v in views.slice(0, 2):
		await _view(v, "off")
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await seconds(4.0)
	var lums := []
	for v in views:
		lums.append(await _view(v, "on"))
	var dark := 0
	for l in lums:
		if l < MIN_LUM_POWERED:
			dark += 1
	at.check(dark <= 1, "courant rétabli : %d vue(s) sous la luminance %.2f (%s)" % [dark, MIN_LUM_POWERED, lums])
	await _cost_ab(env, post, views[3])

	# Manche de chiens : brouillard épais, brume volumétrique x3.
	var base_vd := env.volumetric_fog_density
	game.rounds.dogs._set_fog(1.0)
	at.check(env.volumetric_fog_density > base_vd * 2.5, "manche de chiens : brume volumétrique épaissie (%.3f -> %.3f)" % [base_vd, env.volumetric_fog_density])
	await _view(views[0], "chiens")
	game.rounds.dogs._set_fog(0.0)
	at.check(is_equal_approx(env.volumetric_fog_density, base_vd), "fin de la manche de chiens : brume normale")
	at.check_perf(worst_fps, 150.0, "pire vue %s (MEDIUM, post-traitement BO1)" % map_id)


## Chaque préréglage règle la brume et la variante du post-traitement.
func _check_qualities(env: Environment, post: FilmPost) -> void:
	var initial := Settings.quality
	p.teleport_to(MapData.cell_to_world((BUNKER_VIEWS[0] if game.map_def.id == "bunker_k7" else KINO_VIEWS[0])[1], 0.05))
	H.aim_at(p, MapData.cell_to_world((BUNKER_VIEWS[0] if game.map_def.id == "bunker_k7" else KINO_VIEWS[0])[2], 1.2))
	for q in [Settings.Quality.LOW, Settings.Quality.HIGH, Settings.Quality.MEDIUM]:
		var preset := RenderQuality.preset(q)
		Settings.quality = q
		Settings.changed.emit()
		await seconds(0.5)
		at.check(env.volumetric_fog_enabled == preset.volumetric_fog, "%s : brume volumétrique %s" % [preset.name, env.volumetric_fog_enabled])
		var want := FilmPost.SHADER if preset.post_screen else FilmPost.SHADER_LOW
		at.check(post.material.shader == want, "%s : post-traitement %s" % [preset.name, "lecture d'écran" if preset.post_screen else "multiplicatif"])
		at.begin_perf()
		await seconds(1.0)
		at.end_perf("qualité " + preset.name)
		await at.screenshot("q_" + preset.name)
	Settings.quality = initial
	Settings.changed.emit()
	await seconds(0.3)


## Coût GPU des effets BO1 (brume volumétrique, post-traitement), mesuré en
## alternance sur la même vue pour résister à la charge des autres jeux :
## temps GPU moyen du viewport avec / sans chaque effet.
func _cost_ab(env: Environment, post: FilmPost, v: Array) -> void:
	p.teleport_to(MapData.cell_to_world(v[1], 0.05))
	H.aim_at(p, MapData.cell_to_world(v[2], 1.2))
	await seconds(0.5)
	var rid := at.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var sums := {"base": 0.0, "brume": 0.0, "post": 0.0}
	for rep in 4:
		for mode in sums.keys():
			env.volumetric_fog_enabled = mode == "brume"
			post.visible = mode == "post"
			await frames(6)
			var acc := 0.0
			for i in 20:
				await frames(1)
				acc += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			sums[mode] += acc / 20.0
	env.volumetric_fog_enabled = RenderQuality.current().volumetric_fog
	post.visible = true
	var base: float = sums.base / 4.0
	var extra: float = (sums.brume + sums.post) / 4.0 - 2.0 * base
	print("[look] coût GPU %s : base %.2f ms, brume volumétrique +%.2f ms, post-traitement +%.2f ms" % [v[0], base, sums.brume / 4.0 - base, sums.post / 4.0 - base])
	# Budget : ~1 ms ici (GTX 1070, 720p) ≈ 2 à 3 ms sur GTX 1050 en 1080p.
	at.check(extra < 1.0, "coût GPU de la brume et du post-traitement : %.2f ms < 1 ms" % extra)


## OPTIONS > GRAIN DE FILM : 0 = désactivé, 1 = maximum.
func _check_grain_option(post: FilmPost) -> void:
	var initial := Settings.film_grain
	Settings.film_grain = 0.0
	Settings.changed.emit()
	await frames(2)
	at.check(is_zero_approx(float(post.material.get_shader_parameter("grain"))), "grain désactivé à 0")
	await at.screenshot("grain_0")
	Settings.film_grain = 1.0
	Settings.changed.emit()
	await frames(2)
	at.check(is_equal_approx(float(post.material.get_shader_parameter("grain")), FilmPost.GRAIN_MAX), "grain maximal à 100 %")
	await at.screenshot("grain_100")
	Settings.film_grain = initial
	Settings.changed.emit()


## Vue d'une zone : perf, capture, luminance moyenne de la partie 3D.
func _view(v: Array, tag: String) -> float:
	p.teleport_to(MapData.cell_to_world(v[1], 0.05))
	H.aim_at(p, MapData.cell_to_world(v[2], 1.2))
	await seconds(0.8)
	at.begin_perf()
	await seconds(0.8)
	worst_fps = minf(worst_fps, at.end_perf("%s %s" % [v[0], tag]))
	await at.screenshot("%s_%s_%s" % [game.map_def.id, v[0], tag])
	var l := mean_luminance(at.get_viewport().get_texture().get_image())
	print("[look] %s %s : luminance moyenne %.3f" % [v[0], tag, l])
	return l


## Luminance moyenne (sRGB) de l'image, sans la bande basse du HUD.
static func mean_luminance(img: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, int(img.get_height() * 0.78), 6):
		for x in range(0, img.get_width(), 6):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return sum / maxf(n, 1)
