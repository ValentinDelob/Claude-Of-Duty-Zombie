extends TestCase
## HUD façon BO1 : invites, chiffres peints, transitions du compteur de manche.


func test_bo1_prompts() -> void:
	var saved := Settings.language
	Settings.language = "fr"
	_bo1_prompts_fr()
	Settings.language = "en"
	_bo1_prompts_en()
	Settings.language = saved


func _bo1_prompts_en() -> void:
	assert_eq(Hud.bo1_prompt("[F] Buy M14 [500]"), "Press F to buy M14 [Cost: 500]")
	assert_eq(Hud.bo1_prompt("[F] Crate [950]"), "Press F to open the crate [Cost: 950]")
	assert_eq(Hud.bo1_prompt("Hold [F] to rebuild the barrier"), "Hold F to rebuild the barrier")
	assert_eq(Hud.bo1_prompt("[F] Hold to revive Bob"), "Hold F to revive Bob")
	assert_eq(Hud.bo1_prompt("Power must be activated first"), "Power must be activated first")
	assert_eq(Hud.bo1_prompt("[F] Turn on the power"), "Press F to turn on the power")
	assert_eq(Hud.bo1_prompt("[F] Buy M14 [500]", "E"), "Press E to buy M14 [Cost: 500]")
	assert_eq(Hud.bo1_prompt("Hold [F] to rebuild the barrier", "MOUSE 3"), "Hold MOUSE 3 to rebuild the barrier")


func _bo1_prompts_fr() -> void:
	assert_eq(Hud.bo1_prompt(""), "")
	assert_eq(Hud.bo1_prompt("[F] Acheter M14 [500]"), "Appuyer sur F pour acheter M14 [Coût : 500]")
	assert_eq(Hud.bo1_prompt("[F] Caisse [950]"), "Appuyer sur F pour ouvrir la caisse [Coût : 950]")
	assert_eq(Hud.bo1_prompt("Maintenir [F] pour reconstruire la barricade"), "Maintenir F pour reconstruire la barricade")
	assert_eq(Hud.bo1_prompt("[F] Maintenir pour réanimer Bob"), "Maintenir F pour réanimer Bob")
	assert_eq(Hud.bo1_prompt("Le courant doit être rétabli"), "Le courant doit être rétabli")
	assert_eq(Hud.bo1_prompt("[F] Rétablir le courant"), "Appuyer sur F pour rétablir le courant")
	# Touche INTERAGIR réaffectée dans les options.
	assert_eq(Hud.bo1_prompt("[F] Acheter M14 [500]", "E"), "Appuyer sur E pour acheter M14 [Coût : 500]")
	assert_eq(Hud.bo1_prompt("Maintenir [F] pour reconstruire la barricade", "CLIC MOLETTE"), "Maintenir CLIC MOLETTE pour reconstruire la barricade")


func test_every_digit_is_painted() -> void:
	for d in 10:
		var strokes: Array = HudStyle.digit_strokes(d)
		assert_true(strokes.size() >= 1, "chiffre %d" % d)
		for s: PackedVector2Array in strokes:
			assert_true(s.size() >= 2, "trait du chiffre %d" % d)
			for p in s:
				assert_true(p.x > -0.1 and p.x < 0.8 and p.y > -0.1 and p.y < 1.1, "chiffre %d dans sa boîte (%s)" % [d, p])


func test_player_colors_bo1_order() -> void:
	# BO1 : joueur 1 blanc, 2 bleu, 3 jaune, 4 vert.
	var c := [HudStyle.player_color(0), HudStyle.player_color(1), HudStyle.player_color(2), HudStyle.player_color(3)]
	assert_true(c[0].s < 0.1, "blanc")
	assert_true(c[1].b > c[1].r and c[1].b > c[1].g, "bleu")
	assert_true(c[2].r > c[2].b and c[2].g > c[2].b, "jaune")
	assert_true(c[3].g > c[3].r and c[3].g > c[3].b, "vert")


func test_round_transition_white_to_red() -> void:
	var rc := RoundCounter.new()
	host.add_child(rc)
	rc.set_round(1, true)
	rc._process(0.05)
	assert_true(rc.whiteness > 0.5, "nouvelle manche : blanche (%.2f)" % rc.whiteness)
	for i in 100:
		rc._process(0.05)
	assert_eq(rc.mode, RoundCounter.Mode.IDLE, "fin de la transition")
	assert_near(rc.whiteness, 0.0, 0.001, "rouge sang")
	assert_true(rc.current_color().r > rc.current_color().g * 4.0, "couleur rouge")
	# Fin de manche : pulsation blanc <-> rouge.
	rc.set_round(1, false)
	var seen_white := false
	var seen_red := false
	for i in 40:
		rc._process(0.05)
		seen_white = seen_white or rc.whiteness > 0.9
		seen_red = seen_red or rc.whiteness < 0.1
	assert_true(seen_white and seen_red, "entracte : pulsation")
	# Manche suivante : l'ancienne s'efface puis la nouvelle apparaît.
	rc.set_round(2, true)
	rc._process(0.05)
	assert_eq(rc._shown, 1, "l'ancienne manche s'efface d'abord")
	for i in 20:
		rc._process(0.05)
	assert_eq(rc._shown, 2, "puis la nouvelle")
	rc.queue_free()
