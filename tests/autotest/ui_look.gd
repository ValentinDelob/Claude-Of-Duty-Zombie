extends AutotestScenario
## @rendu : style propre au jeu des menus, du ciel et des étiquettes 3D
## (GAME_CONCEPT.md §6, docs/ART_DIRECTION.md « Menus », « Ciel »,
## « Étiquettes 3D »). Captures (revue humaine pendant la refonte) :
##   menu titre (fond 3D cubique, logo en cubes), crédits, options (JEU et
##   GRAPHISMES), puis une petite scène à ciel ouvert : ciel de jour (nuages
##   en cubes), de nuit (étoiles en pixels carrés, lune en pixel art), et les
##   étiquettes 3D du jeu (nom d'un coéquipier, « À TERRE », butin au sol,
##   panneaux du piège électrique et du poste central).
## Vérifications logiques : logo en cubes (nom du jeu de GameName), ciel
## cubique (shader et mode), police en cubes sur chaque Label3D.

var menu: MainMenu


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(func(): return menu.current_name == "main" and menu.current.get("logo") != null, 5.0, "écran titre")
	await seconds(2.8)  # sortie du noir
	var logo = menu.current.get("logo")
	var lines = logo.get("lines") if logo else null
	at.check(lines is Array and not lines.is_empty(), "logo en lignes de cubes")
	await at.screenshot("main")
	# Le zombie qui passe au fond.
	menu.backdrop.force_figure(true)
	await seconds(1.0)
	await at.screenshot("main_zombie")
	menu.backdrop.force_figure(false)
	menu.show_screen("credits")
	await seconds(4.0)
	await at.screenshot("credits")
	menu.show_screen("options")
	await seconds(1.4)
	await at.screenshot("options_game")
	menu.current.call("_select_tab", "graphics", false)
	await seconds(0.6)
	await at.screenshot("options_graphics")
	await _sky_and_tags()


## Petite scène à ciel ouvert, construite ici (sans partie) : sol et murets
## en cubes, ciel de la carte, étiquettes 3D.
func _sky_and_tags() -> void:
	var stage := Node3D.new()
	stage.name = "UiLookStage"
	tree().root.add_child(stage)
	menu.queue_free()
	await frames(2)
	WorldLook.setup_environment(stage, {"sky": {"type": "jour", "luminosite": 1.0}})
	var env := (stage.get_node("WorldEnvironment") as WorldEnvironment).environment
	_build_ground(stage)
	var cam := Camera3D.new()
	cam.fov = 75.0
	stage.add_child(cam)
	cam.position = Vector3(0, 1.7, 6)
	cam.look_at(Vector3(0, 4.2, -6))
	cam.current = true
	var sm := env.sky.sky_material if env.sky else null
	at.check(sm is ShaderMaterial and (sm as ShaderMaterial).shader.resource_path.ends_with("cube_sky.gdshader"), "ciel de jour cubique")
	await seconds(1.2)
	await at.screenshot("sky_day")
	WorldLook.apply_sky(env, {"type": "nuit", "luminosite": 1.0})
	await seconds(1.0)
	cam.look_at(Vector3(-3.6, 5.2, -6))
	await seconds(0.3)
	await at.screenshot("sky_night")
	# Étiquettes 3D, réglées comme dans le jeu (Player, LootDrop,
	# ElectricTrap, Mainframe) : la police en cubes est posée par Tag3D.
	cam.position = Vector3(0, 1.6, 4.2)
	cam.look_at(Vector3(0, 1.3, 0))
	var tags: Array[Label3D] = []
	var name_tag := _tag(stage, "CLAUDE", 40, 0.0035, 10, HudStyle.player_color(1), Vector3(-1.4, 2.15, 0), true, UiStyle.font("impact"))
	tags.append(name_tag)
	var down := _tag(stage, Lang.t("✚ À TERRE", "✚ DOWNED"), 48, 0.004, 12, Color(1.0, 0.25, 0.15), Vector3(1.5, 1.2, 0), true, UiStyle.font("impact"))
	tags.append(down)
	var wid := String(WeaponDB.WEAPONS.keys()[0])
	var loot := _tag(stage, LootDrop.label_text({"id": wid, "level": 7, "rarity": 2}, "Claude"), 40, 0.004, 10,
			GameWeapon.rarity_color(2), Vector3(0.2, 0.9, 0.8), true)
	tags.append(loot)
	tags.append(_tag(stage, "DANGER\n950", 40, 0.004, 0, Color(0.85, 0.7, 0.2), Vector3(-2.6, 1.6, -0.9), false, UiStyle.font("title")))
	tags.append(_tag(stage, Lang.t("POSTE CENTRAL", "MAINFRAME"), 44, 0.004, 0, Color(0.85, 0.7, 0.35), Vector3(2.4, 2.2, -1.2), false, UiStyle.font("title")))
	await frames(2)
	for t in tags:
		at.check(t.font == CubeFont.font(), "étiquette « %s » : police en cubes" % t.text.get_slice("\n", 0))
	await seconds(0.6)
	await at.screenshot("tags")
	stage.queue_free()


func _tag(parent: Node3D, text: String, fs: int, px: float, outline: int, col: Color, pos: Vector3, billboard: bool, font: Font = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	if font:
		l.font = font
	l.font_size = fs
	l.pixel_size = px
	l.outline_size = outline
	l.modulate = col
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


## Sol carrelé et deux murets (cubes de 5 cm, textures pixel art du jeu).
func _build_ground(parent: Node3D) -> void:
	var specs := [
		["tiles", Vector3(16, 0.2, 16), Vector3(0, -0.1, 0)],
		["wall_lab", Vector3(0.4, 2.4, 10), Vector3(-4.2, 1.2, -1)],
		["wall_concrete", Vector3(6, 1.2, 0.4), Vector3(1.0, 0.6, -3.0)],
		["steel", Vector3(0.6, 0.6, 0.6), Vector3(2.6, 0.3, 0.6)],
	]
	for s in specs:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = s[1]
		mi.mesh = b
		mi.material_override = WorldLook.surface(s[0])
		mi.position = s[2]
		parent.add_child(mi)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, 1.5)
	lamp.omni_range = 9.0
	lamp.light_energy = 1.4
	parent.add_child(lamp)
