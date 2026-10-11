extends TestCase
## Style propre au jeu des menus et des étiquettes 3D (GAME_CONCEPT.md §6) :
## nom du jeu en un seul endroit, logo en cubes, plus de police pochoir ni de
## rouge sang, crédits exacts, police en cubes des Label3D.


func test_game_name_single_source() -> void:
	assert_eq(String(ProjectSettings.get_setting("application/config/name")), GameName.NAME,
			"project.godot suit GameName.NAME (renommer les deux ensemble)")
	assert_eq(GameName.display(), GameName.NAME.to_upper())
	assert_true(GameName.words().size() >= 1)


func test_logo_layout() -> void:
	var logo := MenuLogo.new()
	logo._layout(GameName.words())
	assert_true(logo.lines.size() >= 1 and logo.lines.size() <= 3, "1 à 3 lignes (%d)" % logo.lines.size())
	assert_true(logo.custom_minimum_size.x <= MenuLogo.WIDTH + 0.5, "largeur tenue")
	# Un nom d'un, deux ou cinq mots se place seul (nom définitif à venir).
	logo._layout(PackedStringArray(["APOCALYPSE"]))
	assert_eq(logo.lines.size(), 1, "un mot : une ligne")
	logo._layout(PackedStringArray(["ZOMBIE", "APOCALYPSE"]))
	assert_eq(logo.lines.size(), 2, "deux mots : deux lignes")
	logo._layout(PackedStringArray(["LA", "NUIT", "DU", "GRAND", "LABORATOIRE"]))
	assert_eq(logo.lines.size(), 3, "cinq mots : trois lignes")
	assert_eq(String(logo.lines[1].text), "NUIT DU GRAND", "mots du milieu en petit")
	for l: Dictionary in logo.lines:
		assert_true(MenuLogo.text_cubes(l.text) * float(l.cube) <= MenuLogo.WIDTH, "« %s » tient dans le logo" % l.text)
	logo.free()


func test_no_stencil_nor_blood() -> void:
	for kind in ["title", "impact", "body"]:
		var f := UiStyle.font(kind) as SystemFont
		assert_false("Stencil" in f.font_names, "police « %s » sans pochoir" % kind)
	var src := FileAccess.get_file_as_string("res://scripts/ui/ui_style.gd")
	assert_false(src.contains("BLOOD"), "plus de rouge sang dans UiStyle")
	var t := MenuStyle.title("OPTIONS")
	assert_true(t.get_theme_font("font") == CubeFont.font(), "titres en police en cubes")
	t.free()


func test_credits_name_and_facts() -> void:
	var saved := Settings.language
	var credits: GDScript = load("res://scripts/ui/screens/credits_screen.gd")
	var lines: Array = credits.get_script_constant_map()["LINES"]
	for lang in ["fr", "en"]:
		Settings.language = lang
		var all := ""
		for l: Array in lines:
			all += String(credits.call("line_text", l)) + "\n"
		assert_true(all.contains(GameName.display()), "nom du jeu (%s)" % lang)
		for bad in ["enfer", "hellhound", "announcer", "annonces", "aucune image", "No external images", "Polices système de la machine"]:
			assert_false(all.contains(bad), "crédits (%s) : plus de « %s »" % [lang, bad])
		for who in ["Callahan", "Orlov", "Arakawa", "Weissmann", "Mercer", "Berg", "Jojo"]:
			assert_true(all.contains(who), "voix : %s (%s)" % [who, lang])
	Settings.language = saved


func test_label3d_cube_font() -> void:
	var l := Label3D.new()
	l.font = UiStyle.font("impact")
	l.font_size = 40
	l.outline_size = 10
	Tag3D.style(l)
	assert_true(l.font == CubeFont.font(), "police en cubes")
	assert_eq(l.font_size, roundi(40 * Tag3D.SIZE_GAIN), "taille relevée")
	assert_true(l.outline_size <= Tag3D.FALLBACK_OUTLINE, "contour fin (repli)")
	Tag3D.style(l)
	assert_eq(l.font_size, roundi(40 * Tag3D.SIZE_GAIN), "une seule fois")
	var keep := Label3D.new()
	keep.set_meta("tag3d_keep", true)
	keep.font_size = 30
	Tag3D.style(keep)
	assert_true(keep.font == null and keep.font_size == 30, "méta tag3d_keep : laissée telle quelle")
	assert_true(CubeFont.glyph("✚").size() > 0, "croix médicale en cubes (« ✚ À TERRE »)")
	l.free()
	keep.free()
