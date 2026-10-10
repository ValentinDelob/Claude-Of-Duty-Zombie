extends TestCase
## HUD propre au jeu : invites d'action, police et chiffres en cubes,
## transitions du compteur de manche, couleurs des joueurs.


func test_action_prompts() -> void:
	var saved := Settings.language
	Settings.language = "fr"
	_action_prompts_fr()
	Settings.language = "en"
	_action_prompts_en()
	Settings.language = saved


func _action_prompts_en() -> void:
	assert_eq(Hud.action_prompt("[F] Buy M14 [500]"), "Press F to buy M14 · 500 scrap")
	assert_eq(Hud.action_prompt("[F] Crate [950]"), "Press F to open the crate · 950 scrap")
	assert_eq(Hud.action_prompt("Hold [F] to rebuild the barrier"), "Hold F to rebuild the barrier")
	assert_eq(Hud.action_prompt("[F] Hold to revive Bob"), "Hold F to revive Bob")
	assert_eq(Hud.action_prompt("Power must be activated first"), "Power must be activated first")
	assert_eq(Hud.action_prompt("[F] Turn on the power"), "Press F to turn on the power")
	assert_eq(Hud.action_prompt("[F] Buy M14 [500]", "E"), "Press E to buy M14 · 500 scrap")
	assert_eq(Hud.action_prompt("Hold [F] to rebuild the barrier", "MOUSE 3"), "Hold MOUSE 3 to rebuild the barrier")


func _action_prompts_fr() -> void:
	assert_eq(Hud.action_prompt(""), "")
	assert_eq(Hud.action_prompt("[F] Acheter M14 [500]"), "Appuyer sur F pour acheter M14 · 500 ferraille")
	assert_eq(Hud.action_prompt("[F] Caisse [950]"), "Appuyer sur F pour ouvrir la caisse · 950 ferraille")
	assert_eq(Hud.action_prompt("Maintenir [F] pour reconstruire la barricade"), "Maintenir F pour reconstruire la barricade")
	assert_eq(Hud.action_prompt("[F] Maintenir pour réanimer Bob"), "Maintenir F pour réanimer Bob")
	assert_eq(Hud.action_prompt("Le courant doit être rétabli"), "Le courant doit être rétabli")
	assert_eq(Hud.action_prompt("[F] Rétablir le courant"), "Appuyer sur F pour rétablir le courant")
	# Touche INTERAGIR réaffectée dans les options.
	assert_eq(Hud.action_prompt("[F] Acheter M14 [500]", "E"), "Appuyer sur E pour acheter M14 · 500 ferraille")
	assert_eq(Hud.action_prompt("Maintenir [F] pour reconstruire la barricade", "CLIC MOLETTE"), "Maintenir CLIC MOLETTE pour reconstruire la barricade")


func test_cube_glyphs() -> void:
	# Chiffres : 7 rangées de lettre pleines, même largeur partout.
	for d in 10:
		var g := CubeFont.glyph(str(d))
		assert_eq(g.size(), CubeFont.ACCENT_ROWS + CubeFont.CAP_ROWS + CubeFont.DESC_ROWS, "chiffre %d : rangées" % d)
		var cubes := 0
		for r in g:
			assert_eq(r.length(), 5, "chiffre %d : largeur" % d)
			cubes += r.count("#")
		assert_true(cubes >= 7, "chiffre %d : dessiné (%d cubes)" % [d, cubes])
	# Accents au-dessus, cédille dessous, minuscules = capitales.
	var e_acute := CubeFont.glyph("É")
	assert_true(e_acute[0].contains("#") and e_acute[1].contains("#"), "accent aigu sur 2 rangées")
	assert_false(e_acute[2].contains("#"), "accent détaché de la lettre")
	assert_eq(e_acute.slice(CubeFont.ACCENT_ROWS), CubeFont.glyph("E").slice(CubeFont.ACCENT_ROWS), "É : la lettre E")
	var cedilla := CubeFont.glyph("Ç")
	assert_true(cedilla[cedilla.size() - 1].contains("#"), "cédille")
	assert_eq(CubeFont.glyph("a"), CubeFont.glyph("A"), "minuscules")
	assert_eq(CubeFont.glyph("€").size(), 0, "caractère absent : police de repli")
	# Tous les textes des grands titres s'écrivent en cubes.
	for t in ["LA MEUTE APPROCHE", "THE PACK IS COMING", "LA HORDE L'EMPORTE", "THE HORDE WINS",
			"ÉVACUATION RÉUSSIE", "EVACUATED", "À TERRE", "DOWNED", "VOUS ÊTES MORT", "BUNKER K-7", "SCORES"]:
		for ch in t:
			assert_true(CubeFont.glyph(ch).size() > 0, "« %s » : caractère « %s »" % [t, ch])


func test_cube_font_builds() -> void:
	var f := CubeFont.font()
	assert_true(f != null and f.fixed_size == CubeFont.FIXED_SIZE, "police en cubes")
	assert_true(f.has_char("A".unicode_at(0)) and f.has_char("É".unicode_at(0)) and f.has_char("7".unicode_at(0)), "glyphes présents")
	var w := f.get_string_size("ABC", HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
	assert_true(w > 100.0 and w < 400.0, "largeur d'un texte à 72 px (%.0f)" % w)
	assert_true(CubeFont.font() == f, "police générée une seule fois")


func test_player_colors_distinct() -> void:
	# Quatre couleurs bien distinctes (teintes éloignées), aucune grise.
	for i in 4:
		var a := HudStyle.player_color(i)
		assert_true(a.s > 0.4, "joueur %d : couleur saturée" % (i + 1))
		for j in range(i + 1, 4):
			var b := HudStyle.player_color(j)
			var dh := absf(a.h - b.h)
			assert_true(minf(dh, 1.0 - dh) > 0.08, "joueurs %d et %d : teintes distinctes" % [i + 1, j + 1])


func test_round_transition() -> void:
	var rc := RoundCounter.new()
	host.add_child(rc)
	rc.set_round(1, true)
	rc._process(0.05)
	assert_true(rc.heat > 0.5, "nouvelle manche : cubes chauffés à blanc (%.2f)" % rc.heat)
	for i in 100:
		rc._process(0.05)
	assert_eq(rc.mode, RoundCounter.Mode.IDLE, "fin de la transition")
	assert_near(rc.heat, 0.0, 0.001, "refroidi")
	var c := rc.current_color()
	assert_true(c.g > c.r * 1.5 and c.g > 0.8, "couleur menthe, pas de rouge (%s)" % c)
	# Fin de manche : pulsation menthe <-> blanc.
	rc.set_round(1, false)
	var seen_white := false
	var seen_mint := false
	for i in 40:
		rc._process(0.05)
		seen_white = seen_white or rc.heat > 0.9
		seen_mint = seen_mint or rc.heat < 0.1
	assert_true(seen_white and seen_mint, "entracte : pulsation")
	# Manche suivante : l'ancienne tombe puis la nouvelle se construit.
	rc.set_round(2, true)
	rc._process(0.05)
	assert_eq(rc._shown, 1, "l'ancienne manche tombe d'abord")
	for i in 20:
		rc._process(0.05)
	assert_eq(rc._shown, 2, "puis la nouvelle")
	# Vague spéciale : orange d'alarme une fois la transition finie.
	for i in 100:
		rc._process(0.05)
	rc.set_special(true)
	rc._process(0.3)
	var s := rc.current_color()
	assert_true(s.r > s.g and s.r > s.b and s.r > 0.5, "vague spéciale : orange d'alarme (%s)" % s)
	rc.queue_free()
