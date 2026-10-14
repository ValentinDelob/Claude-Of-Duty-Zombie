extends AutotestScenario
## @rendu : a besoin du rendu (fenêtre hors écran).
## Style ILLUSTRÉ (prototype, IllustratedStyle ; OPTIONS > VIDÉO > STYLE) :
## les mêmes vues en CLASSIQUE puis en ILLUSTRÉ : laboratoire de BUNKER K-7,
## couloir, salle avec des zombies immobiles, fond du menu titre. Vérifie que
## le style remplace les shaders des matériaux inscrits et la passe de trait,
## que le retour en CLASSIQUE rend les shaders d'origine, et que l'encrage
## noircit les vues chargées sans couvrir un sol plan.
## Captures : tests/_out/shots/style_look_<vue>_classique|illustre.png et la
## planche de comparaison style_look_planche_<hauteur>.png (CLASSIQUE |
## ILLUSTRÉ | cible docs/art/gemini_target.webp), pour la revue humaine.
## STYLE_SHOT_RES=1920x1080 : captures à cette taille.

var H := AutotestHelpers
const TARGET := "res://docs/art/gemini_target.webp"
## [nom, cellule du joueur, cellule visée, hauteur visée (m)]
const VIEWS := [
	["labo", Vector2i(35, 31), Vector2i(52, 18), 1.0],
	["couloir", Vector2i(20, 23), Vector2i(32, 24), 1.0],
	["zombies", Vector2i(35, 31), Vector2i(47, 24), 1.0],
]

var game: Game
var p: Player
## vue -> [image classique, image illustrée]
var shots := {}


func run() -> void:
	timeout_sec = 300
	var res := OS.get_environment("STYLE_SHOT_RES")
	if res != "" and DisplayServer.get_name() != "headless":
		var r := res.split("x")
		if r.size() == 2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(Vector2i(int(r[0]), int(r[1])))
			await frames(3)
	var keep := Settings.art_style
	_set_style(Settings.ArtStyle.CLASSIC)
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
	await _check_switch()
	await seconds(6.0)  # l'annonce « courant rétabli » s'efface
	for v in VIEWS.slice(0, 2):
		await _view(v)
	# Zombies immobiles devant le joueur (vue « zombies »), de 2,5 à 7 m.
	var from := MapData.cell_to_world(VIEWS[2][1], 0.05)
	var dir := (MapData.cell_to_world(VIEWS[2][2]) - from).normalized()
	for i in 5:
		var pos := from + dir * (2.5 + i * 1.1) + Vector3(dir.z, 0, -dir.x) * (0.8 if i % 2 else -0.7)
		var zid: int = game.zombies.spawn(Vector3(pos.x, 0.0, pos.z), 0, 1000000)
		game.zombies.get_zombie(zid).speed_mult = 0.0
	await seconds(maxf(Zombie.EMERGE_TIME + 0.5, 6.0))
	# Figés, tournés vers le joueur (de face, comme sur la planche cible).
	for z: Zombie in game.zombies.alive:
		z.set_process(false)
		z.set_physics_process(false)
		var to := from - z.global_position
		z.rotation.y = atan2(to.x, to.z)
	await _view(VIEWS[2])
	# Sol plan vu en plongée : l'encrage n'y trace (presque) rien.
	await H.clear_zombies(self)
	p.teleport_to(MapData.cell_to_world(Vector2i(44, 30), 0.05))
	H.aim_at(p, MapData.cell_to_world(Vector2i(44, 26), 0.0))
	p.weapons.view.visible = false
	await seconds(0.6)
	_set_style(Settings.ArtStyle.ILLUSTRATED)
	await frames(4)
	await at.screenshot("sol_illustre")
	var flat := await _ink_fraction()
	at.check(flat < 0.06,"sol en plongée : %.2f %% de pixels encrés (pas de grille noire)" % (flat * 100.0))
	p.weapons.view.visible = true
	# Fond du menu titre.
	_set_style(Settings.ArtStyle.CLASSIC)
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 8.0, "menu principal")
	await seconds(2.5)
	await _pair("menu")
	_sheet()
	_set_style(keep)


func _set_style(st: int) -> void:
	Settings.art_style = st as Settings.ArtStyle
	Settings.changed.emit()


## Le style remplace les shaders des matériaux inscrits et de la passe de
## trait ; le retour en CLASSIQUE rend les shaders d'origine.
func _check_switch() -> void:
	var outline := game.world.get_node_or_null("ScreenOutline") as ScreenOutline
	at.check(outline != null and outline.material.shader == ScreenOutline.SHADER, "CLASSIQUE : contour d'origine")
	var surf := WorldLook.surface("floor") as ShaderMaterial
	var base := IllustratedStyle.base_shader(surf)
	at.check(surf.shader == base, "CLASSIQUE : shader d'origine des surfaces")
	at.check(IllustratedStyle.bound_count() > 5, "matériaux inscrits (%d)" % IllustratedStyle.bound_count())
	_set_style(Settings.ArtStyle.ILLUSTRATED)
	await frames(3)
	at.check(outline != null and outline.material.shader == ScreenOutline.ink_shader(false)
			and outline.material.next_pass == outline.ink_objects, "ILLUSTRÉ : encrage (architecture puis objets)")
	at.check(surf.shader != base and surf.shader.code.contains("cel_light.gdshaderinc"), "ILLUSTRÉ : surfaces en aplats")
	var zm := ZombieModel.material()
	at.check(zm.shader.code.contains("#define CEL_CHAR"), "ILLUSTRÉ : zombies en aplats (sorte personnage)")
	_set_style(Settings.ArtStyle.CLASSIC)
	await frames(3)
	at.check(surf.shader == base and outline.material.shader == ScreenOutline.SHADER, "retour en CLASSIQUE : shaders d'origine")


func _view(v: Array) -> void:
	p.teleport_to(MapData.cell_to_world(v[1], 0.05))
	H.aim_at(p, MapData.cell_to_world(v[2], v[3]))
	await seconds(0.8)
	var d := await _pair(v[0])
	at.check(d > 0.002, "%s : l'encrage noircit %.2f %% des pixels" % [v[0], d * 100.0])


## Captures CLASSIQUE puis ILLUSTRÉ ; renvoie la part de pixels nettement
## plus sombres en ILLUSTRÉ (encre), mesurée sans grain.
func _pair(view: String) -> float:
	var out := []
	for st in [Settings.ArtStyle.CLASSIC, Settings.ArtStyle.ILLUSTRATED]:
		_set_style(st)
		await frames(4)
		await at.screenshot("%s_%s" % [view, "illustre" if st == Settings.ArtStyle.ILLUSTRATED else "classique"])
		out.append(at.get_viewport().get_texture().get_image())
	shots[view] = out
	_save_zoom(view, out[0], out[1])
	_set_style(Settings.ArtStyle.CLASSIC)
	return await _ink_fraction()


## Part des pixels noircis par l'encre seule (même style d'éclairage, trait
## illustré ou rien) : sans grain, comparaison pixel à pixel.
func _ink_fraction() -> float:
	var grain := Settings.film_grain
	Settings.film_grain = 0.0
	_set_style(Settings.ArtStyle.ILLUSTRATED)
	var outline := _outline()
	await frames(3)
	var on := at.get_viewport().get_texture().get_image()
	if outline:
		outline.visible = false
	await frames(3)
	var off := at.get_viewport().get_texture().get_image()
	if outline:
		outline.visible = ScreenOutline.wanted()
	Settings.film_grain = grain
	_set_style(Settings.ArtStyle.CLASSIC)
	if on == null or off == null or on.get_size() != off.get_size():
		return 0.0
	var dark := 0
	var n := 0
	for y in range(0, on.get_height(), 2):
		for x in range(0, on.get_width(), 2):
			n += 1
			if off.get_pixel(x, y).get_luminance() - on.get_pixel(x, y).get_luminance() > 0.06:
				dark += 1
	return float(dark) / maxf(n, 1)


func _outline() -> ScreenOutline:
	if is_instance_valid(game) and game.world:
		return game.world.get_node_or_null("ScreenOutline") as ScreenOutline
	var root := tree().current_scene
	return root.find_child("ScreenOutline", true, false) as ScreenOutline if root else null


## Gros plan du centre (x2, sans filtrage), CLASSIQUE | ILLUSTRÉ : le trait
## se juge pixel par pixel.
func _save_zoom(view: String, a: Image, b: Image) -> void:
	if a == null or b == null:
		return
	var w := int(a.get_width() / 3.0)
	var h := int(a.get_height() / 3.0)
	var r := Rect2i(w, h, w, h)
	var sheet := Image.create(w * 4, h * 2, false, a.get_format())
	var ca := a.get_region(r)
	var cb := b.get_region(r)
	ca.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	cb.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	sheet.blit_rect(ca, Rect2i(0, 0, w * 2, h * 2), Vector2i.ZERO)
	sheet.blit_rect(cb, Rect2i(0, 0, w * 2, h * 2), Vector2i(w * 2, 0))
	var dir := ProjectSettings.globalize_path("res://tests/_out/shots")
	sheet.save_png("%s/style_look_%s_zoom_%d.png" % [dir, view, a.get_height()])


## Planche : une ligne par vue, CLASSIQUE | ILLUSTRÉ | cible.
func _sheet() -> void:
	if shots.is_empty():
		return
	var first: Image = shots.values()[0][0]
	var cw := 640
	var ch := int(round(cw * float(first.get_height()) / first.get_width()))
	var target := Image.load_from_file(ProjectSettings.globalize_path(TARGET)) if FileAccess.file_exists(TARGET) else null
	var sheet := Image.create(cw * 3 + 8, (ch + 4) * shots.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.08, 0.08, 0.08))
	var row := 0
	for view in shots:
		var imgs: Array = shots[view]
		for c in 3:
			var src: Image = target if c == 2 else imgs[c]
			if src == null:
				continue
			var im := src.duplicate() as Image
			im.convert(Image.FORMAT_RGB8)
			im.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i(c * (cw + 4), row * (ch + 4)))
		row += 1
	var dir := ProjectSettings.globalize_path("res://tests/_out/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/style_look_planche_%d.png" % [dir, first.get_height()]
	sheet.save_png(path)
	print("[autotest] planche : " + path)
