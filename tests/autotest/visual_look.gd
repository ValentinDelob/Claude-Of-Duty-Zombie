extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## @parts 3 : partie 0 = BUNKER K-7, partie 1 = KINO, partie 2 = HUD (sur KINO).
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
## KINO (carte en maillage) : [nom, position au sol (m), point visé (m)].
const KINO_VIEWS := [
	["hall", Vector3(75.0, 2.03, 108.0), Vector3(75.0, 4.0, 92.0)],
	["foyer", Vector3(112.0, 0.0, 51.0), Vector3(110.0, 3.5, 66.0)],
	["loges", Vector3(104.0, 0.0, 46.0), Vector3(110.0, 1.2, 32.0)],
	["ruelle", Vector3(37.0, 0.0, 84.0), Vector3(35.0, 1.5, 55.0)],
	["arriere_salle", Vector3(40.0, 4.45, 48.0), Vector3(33.0, 5.5, 33.0)],
	["theatre", Vector3(75.0, 0.3, 66.0), Vector3(75.0, 3.0, 41.0)],
	["scene", Vector3(75.0, 0.0, 44.0), Vector3(75.0, 3.0, 78.0)],
	["projection", Vector3(76.5, 8.13, 78.35), Vector3(75.15, 9.14, 84.37)],
]
## Luminance moyenne minimale d'une vue courant rétabli (sRGB, 0..1) : en
## dessous, l'image redevient « trop sombre » (retour de l'utilisateur).
const MIN_LUM_POWERED := 0.05

var game: Game
var p: Player
var worst_fps := 10000.0


func run() -> void:
	timeout_sec = 420
	# `-- --autotest=visual_look --hud` : seulement le HUD (itérations rapides).
	# En parties (check.sh) : une carte par partie, le HUD dans la dernière.
	var split := parts() > 1
	if OS.get_cmdline_user_args().has("--hud") or (split and owns(2)):
		p = await H.start_solo_game(self, "kino")
		if p == null:
			return
		game = Game.instance
		game.combat.debug_invulnerable = true
		game.rounds.paused = true
		await H.clear_zombies(self)
		(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
		await seconds(3.0)
		await _hud_pass()
		return
	var mi := -1
	for map_id in ["bunker_k7", "kino"]:
		mi += 1
		if split and not owns(mi):
			continue
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
	if map_id == "kino" and parts() == 1:
		await _hud_pass()


## HUD façon BO1 en situation (KINO, courant rétabli) : manches 3 et 12 et
## leurs transitions, points qui s'envolent, atouts, grenades et singes,
## invite d'achat, tableau des scores, dégâts, à terre, fin de partie.
func _hud_pass() -> void:
	var hud := game.hud
	var pd := game.session.local_data()
	var rc := hud.round_counter()
	_place(KINO_VIEWS[0])
	# Manche 3 : bâtons, apparition blanche puis rouge sang.
	game.rounds.debug_jump_to(3)
	await H.clear_zombies(self)
	await seconds(0.9)
	at.check(rc._shown == 3 and rc.whiteness > 0.4, "manche 3 : apparition en blanc (%.2f)" % rc.whiteness)
	await at.screenshot("hud_manche3_blanc")
	await until(func(): return rc.mode == RoundCounter.Mode.IDLE, 6.0, "fin de la transition")
	await H.clear_zombies(self)
	at.check(is_zero_approx(rc.whiteness), "manche 3 : rouge sang")
	# Atouts, grenades, singes.
	for perk in ["titan", "rapid", "twin", "lazarus"]:
		game.perks.srv_grant(1, perk)
	pd.has_monkeys = true
	pd.monkeys = 3
	await seconds(3.0)
	at.check(hud._perk_icons.perks.size() == 4, "4 icônes d'atouts")
	await at.screenshot("hud_manche3_atouts")
	# Points qui s'envolent (+10 à chaque balle, -dépense).
	for i in 5:
		game.session.add_points(1, 10)
		await seconds(0.07)
	game.session.add_points(1, 50)
	game.session.add_points(1, -500)
	await seconds(0.2)
	await at.screenshot("hud_points")
	# Invite d'achat face à la M14 du hall.
	var m14: WallBuy = game.interact.get_obj("wallbuy_R")
	p.teleport_to(m14.interact_point() + Vector3(0, -1.0, 0) - (m14.global_position - m14.interact_point()).normalized() * 1.2)
	H.aim_at(p, m14.global_position)
	await seconds(0.4)
	at.check(hud._prompt_view.text.begins_with("Appuyer sur F pour acheter") and hud._prompt_view.text.contains("[Coût : 500]"),
			"invite BO1 : « %s »" % hud._prompt_view.text)
	await at.screenshot("hud_invite")
	# Tableau des scores [Tab].
	Input.action_press("scoreboard")
	await frames(3)
	await at.screenshot("hud_tableau")
	Input.action_release("scoreboard")
	# Manche 12 : chiffres peints.
	_place(KINO_VIEWS[5])
	game.rounds.debug_jump_to(12)
	await H.clear_zombies(self)
	await seconds(0.9)
	await at.screenshot("hud_manche12_blanc")
	await until(func(): return rc.mode == RoundCounter.Mode.IDLE, 6.0, "fin de la transition")
	await H.clear_zombies(self)
	await at.screenshot("hud_manche12")
	# Fin de manche : pulsation blanc <-> rouge.
	hud.round_changed(12, false)
	await seconds(OUTRO_SHOT)
	at.check(rc.mode == RoundCounter.Mode.OUTRO, "fin de manche : le compteur pulse")
	await at.screenshot("hud_fin_manche")
	hud.round_changed(13, true)
	await seconds(4.5)
	await H.clear_zombies(self)
	# Dégâts : voile rouge et sang aux bords.
	game.combat.debug_invulnerable = false
	game.combat.damage_player(1, 190, p.global_position + Vector3(2, 1, 0))
	await seconds(0.12)
	await at.screenshot("hud_degats")
	# À terre (LAZARUS) : vision floue.
	game.combat.damage_player(1, 400, p.global_position + Vector3(2, 1, 0))
	await seconds(1.2)
	at.check(pd.life == PlayerData.Life.DOWNED and hud._downed.amount() > 0.9, "à terre : vision floue (%.2f)" % hud._downed.amount())
	await at.screenshot("hud_a_terre")
	await until(func(): return pd.life == PlayerData.Life.ALIVE, DownedSystem.SOLO_SELF_REVIVE + 3.0, "réanimation")
	await seconds(1.0)
	at.check(hud._downed.amount() < 0.05 and not hud._downed.blur.visible, "réanimé : vision nette")
	# Fin de partie.
	game.combat.damage_player(1, 400, p.global_position)
	await until(func(): return GameState.state == GameState.State.GAME_OVER, 3.0, "GAME OVER")
	await seconds(2.0)
	at.check(hud._center_msg.text == "GAME OVER" and hud._center_sub.text.begins_with("Vous avez survécu %d manches" % game.rounds.round_n),
			"fin de partie : %s / %s" % [hud._center_msg.text, hud._center_sub.text])
	await at.screenshot("hud_game_over")


const OUTRO_SHOT := 0.1


## Chaque préréglage règle la brume et la variante du post-traitement.
func _check_qualities(env: Environment, post: FilmPost) -> void:
	var initial := Settings.quality
	_place(BUNKER_VIEWS[0] if game.map_def.id == "bunker_k7" else KINO_VIEWS[0])
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
	_place(v)
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


## Place le joueur pour une vue : cellules de la grille (BUNKER K-7) ou
## positions en mètres (KINO, carte en maillage à plusieurs niveaux).
func _place(v: Array) -> void:
	if v[1] is Vector2i:
		p.teleport_to(MapData.cell_to_world(v[1], 0.05))
		H.aim_at(p, MapData.cell_to_world(v[2], 1.2))
	else:
		p.teleport_to(v[1] + Vector3.UP * 0.05)
		H.aim_at(p, v[2])


## Vue d'une zone : perf, capture, luminance moyenne de la partie 3D.
func _view(v: Array, tag: String) -> float:
	_place(v)
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
