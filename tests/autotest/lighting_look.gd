extends AutotestScenario
## @rendu : éclairage, ombres, ambiance et réponse des matières (refonte
## graphique d'après docs/art/gemini_target.webp, docs/ART_DIRECTION.md
## « Lumière et ambiance »). Captures (revue humaine pendant la refonte) :
##   fond 3D du menu (couloir du labo), BUNKER K-7 courant rétabli (labo avec
##   zombies figés, couloir des cellules sombre, salle de garde, générateur,
##   quai), le labo dans chaque préréglage de qualité, une vue de test_levels
##   (carte en maillage de l'éditeur).
## `-- --tag=avant` : préfixe des captures (comparaison avant / après).
## Vérifications : chaque vue courant rétabli reste lisible (luminance
## moyenne), les zombies se détachent du fond (yeux lumineux).

var H := AutotestHelpers
## [nom, cellule du joueur, cellule visée, hauteur visée (m)]
const VIEWS := [
	["labo", Vector2i(35, 31), Vector2i(52, 18), 1.0],
	["couloir", Vector2i(20, 23), Vector2i(32, 24), 1.0],
	["garde", Vector2i(9, 29), Vector2i(9, 17), 1.0],
	["generateur", Vector2i(55, 22), Vector2i(61, 28), 1.0],
	["quai", Vector2i(20, 9), Vector2i(46, 4), 1.0],
]
const MIN_LUM := 0.05

var game: Game
var p: Player
var tag := "apres"


func run() -> void:
	timeout_sec = 300
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	# Fond 3D du menu.
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var menu: MainMenu = tree().current_scene
	await seconds(3.0)
	await _shot("menu")
	menu.backdrop.force_figure(true)
	await seconds(1.0)
	await _shot("menu_zombie")
	menu.backdrop.force_figure(false)

	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	p.teleport_to(MapData.cell_to_world(VIEWS[1][1], 0.05))
	H.aim_at(p, MapData.cell_to_world(VIEWS[1][2], 1.0))
	await seconds(1.0)
	await _shot("couloir_coupe")
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	# Zombies figés dans le labo (2 à 8 m), émergence comprise.
	var from := MapData.cell_to_world(Vector2i(35, 31), 0.05)
	var dir := (MapData.cell_to_world(Vector2i(52, 18)) - from).normalized()
	for i in 4:
		var pos := from + dir * (2.5 + i * 1.8) + Vector3(dir.z, 0, -dir.x) * (0.9 if i % 2 else -0.9)
		var zid: int = game.zombies.spawn(Vector3(pos.x, 0.0, pos.z), 0, 1000000)
		game.zombies.get_zombie(zid).speed_mult = 0.0
	await seconds(maxf(Zombie.EMERGE_TIME + 0.5, 6.0))
	for v in VIEWS:
		var l := await _view(v)
		at.check(l >= MIN_LUM, "%s : lisible (luminance %.3f >= %.2f)" % [v[0], l, MIN_LUM])
	# Le labo dans chaque préréglage.
	var initial := Settings.quality
	for q in [Settings.Quality.LOW, Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
		Settings.quality = q
		Settings.changed.emit()
		await _view(VIEWS[0], "_" + RenderQuality.preset(q).name)
	Settings.quality = initial
	Settings.changed.emit()
	await H.clear_zombies(self)
	Router.back_to_menu()
	await seconds(1.0)
	# Carte en maillage (éditeur) : test_levels.
	p = await H.start_solo_game(self, "test_levels")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	if game.interact.get_obj("power"):
		(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	p.teleport_to(Vector3(10.8, 0.05, 21.3))
	H.aim_at(p, Vector3(22.0, 1.0, 12.0))
	await seconds(6.0)  # l'annonce « courant rétabli » s'efface
	await _shot("test_levels")


func _view(v: Array, suffix := "") -> float:
	p.teleport_to(MapData.cell_to_world(v[1], 0.05))
	H.aim_at(p, MapData.cell_to_world(v[2], v[3]))
	await seconds(1.2)
	at.begin_perf()
	await seconds(0.6)
	at.end_perf("%s%s" % [v[0], suffix])
	await _shot(v[0] + suffix)
	var img := at.get_viewport().get_texture().get_image()
	var sum := 0.0
	var n := 0
	for y in range(0, int(img.get_height() * 0.78), 6):
		for x in range(0, img.get_width(), 6):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	var l := sum / maxf(n, 1)
	print("[look] %s%s : luminance moyenne %.3f" % [v[0], suffix, l])
	return l


func _shot(n: String) -> void:
	await at.screenshot("%s_%s" % [tag, n])
