extends TestCase
## Choix du personnage (OPTIONS > JEU > PERSONNAGE) et distribution par
## l'hôte (CharacterDB.resolve_cast) : automatique, choix explicites, doublons,
## valeurs invalides venues du réseau ; tenues des cinquième, sixième et
## septième personnages (Mercer, Berg, Jojo) en vue FPS et vus par les
## autres ; libellés du sélecteur.


func _p(slot: int, choice: Variant = CharacterDB.AUTO) -> Dictionary:
	return {"name": "J%d" % slot, "slot": slot, "char": choice}


func _ids(cast: Dictionary) -> Dictionary:
	var out := {}
	for pid in cast:
		out[pid] = CharacterDB.IDS[cast[pid]]
	return out


func test_seven_characters() -> void:
	assert_eq(CharacterDB.IDS, ["callahan", "orlov", "arakawa", "weissmann", "mercer", "berg", "jojo"],
			"Mercer à l'index 4, Berg à l'index 5, Jojo à l'index 6")
	for id in CharacterDB.IDS:
		assert_true(CharacterDB.NAMES.has(id) and CharacterDB.NAMES_EN.has(id), "%s : nom FR et EN" % id)
		assert_true(CharacterDB.SHORT_NAMES.has(id), "%s : nom court" % id)
	assert_eq(CharacterDB.NAMES.mercer, "Sgt-chef Frank « Bulldog » Mercer")
	assert_eq(CharacterDB.NAMES_EN.mercer, "GySgt Frank \"Bulldog\" Mercer")
	assert_eq(CharacterDB.NAMES.berg, "Dr Ella Berg")
	assert_eq(CharacterDB.NAMES_EN.berg, "Dr Ella Berg")
	assert_eq(CharacterDB.clean_choice("berg"), "berg", "choix accepté")
	assert_eq(CharacterDB.NAMES.jojo, "Georges « Jojo la Magouille » Ferrand")
	assert_eq(CharacterDB.NAMES_EN.jojo, "Georges \"Jojo the Hustler\" Ferrand")
	assert_eq(CharacterDB.SHORT_NAMES.jojo, {"fr": "JOJO", "en": "JOJO"})
	assert_eq(CharacterDB.clean_choice("jojo"), "jojo", "choix accepté")


func test_auto_players_keep_the_slot_rotation() -> void:
	var players := {1: _p(0), 5: _p(1), 9: _p(2), 12: _p(3)}
	assert_eq(_ids(CharacterDB.resolve_cast(players, 0)), {1: "callahan", 5: "orlov", 9: "arakawa", 12: "weissmann"},
			"rotation 0 : comme avant (emplacement 0 = Callahan)")
	assert_eq(_ids(CharacterDB.resolve_cast(players, 2)), {1: "arakawa", 5: "weissmann", 9: "mercer", 12: "berg"},
			"rotation tirée par l'hôte, sur sept personnages")
	assert_eq(_ids(CharacterDB.resolve_cast(players, 3)), {1: "weissmann", 5: "mercer", 9: "berg", 12: "jojo"},
			"Jojo après Berg")
	assert_eq(_ids(CharacterDB.resolve_cast(players, 4)), {1: "mercer", 5: "berg", 9: "jojo", 12: "callahan"},
			"la rotation reboucle après Jojo")
	var solo := {1: _p(0)}
	for r in 7:
		assert_eq(CharacterDB.resolve_cast(solo, r)[1], r, "solo : rotation %d" % r)


func test_explicit_choices_are_honoured_and_autos_take_free_ones() -> void:
	# Le joueur 2 (emplacement 1) choisit Callahan : l'hôte en auto (emplacement
	# 0, rotation 0) devrait être Callahan, il prend le suivant libre.
	var players := {1: _p(0), 2: _p(1, "callahan"), 3: _p(2, "mercer"), 4: _p(3)}
	var c := _ids(CharacterDB.resolve_cast(players, 0))
	assert_eq(c[2], "callahan", "choix explicite respecté")
	assert_eq(c[3], "mercer", "choix explicite respecté")
	assert_eq(c[1], "orlov", "auto : premier libre après Callahan")
	assert_eq(c[4], "weissmann", "auto : son personnage (emplacement 3) est libre")
	var seen := {}
	for pid in c:
		assert_false(seen.has(c[pid]), "aucun doublon quand c'est possible")
		seen[c[pid]] = true


func test_duplicate_explicit_choices_allowed() -> void:
	var players := {1: _p(0, "mercer"), 2: _p(1, "mercer"), 3: _p(2)}
	var c := _ids(CharacterDB.resolve_cast(players, 4))
	assert_eq(c[1], "mercer")
	assert_eq(c[2], "mercer", "deux joueurs peuvent choisir le même")
	assert_true(c[3] != "mercer", "l'auto évite les personnages pris (%s)" % c[3])


func test_more_players_than_characters() -> void:
	var players := {}
	for i in 8:
		players[i + 1] = _p(i)
	var cast := CharacterDB.resolve_cast(players, 0)
	assert_eq(cast.size(), 8)
	for i in 7:
		assert_eq(cast[i + 1], i, "les sept premiers : tous différents")
	for i in range(7, 8):
		assert_eq(cast[i + 1], posmod(i, 7), "au-delà : personnage de l'emplacement")


func test_invalid_choices_become_auto() -> void:
	for bad in ["zorg", "", "../orlov", "MERCER", null, 3, 2.0, ["orlov"], {"id": "orlov"}, &"x"]:
		assert_eq(CharacterDB.clean_choice(bad), CharacterDB.AUTO, "refusé : %s" % str(bad))
	for id in CharacterDB.IDS:
		assert_eq(CharacterDB.clean_choice(id), id)
	# Entrées malformées du registre : traitées comme « auto », sans erreur.
	var players := {1: _p(0, "zorg"), 2: {"slot": "x"}, 3: "pas un dictionnaire"}
	var cast := CharacterDB.resolve_cast(players, 0)
	assert_eq(cast.size(), 3)
	for pid in cast:
		assert_true(cast[pid] >= 0 and cast[pid] < CharacterDB.IDS.size())


func test_clean_cast_from_network() -> void:
	var ok := {1: 0, 7: 4, 9: 5, 11: 6}
	assert_eq(CharacterDB.clean_cast(ok), ok)
	assert_eq(CharacterDB.clean_cast(3), {}, "ancien format (rotation) : vide")
	assert_eq(CharacterDB.clean_cast(null), {})
	var dirty := {1: 7, 2: -1, 3: "mercer", "4": 1, -5: 1, 0: 1, 6: 2.0, 8: 3}
	assert_eq(CharacterDB.clean_cast(dirty), {8: 3}, "index hors bornes, types inattendus ignorés")
	var big := {}
	for i in 50:
		big[i + 1] = i % 7
	assert_eq(CharacterDB.clean_cast(big).size(), Net.MAX_SUPPORTED_PLAYERS, "8 joueurs au plus")


func test_index_of_uses_the_cast_then_the_slot() -> void:
	var saved_cast := Net.cast
	var saved_players := Net.players
	Net.players = {1: {"name": "A", "slot": 0}, 2: {"name": "B", "slot": 3}}
	Net.cast = {1: 4}
	assert_eq(CharacterDB.id_of(1), "mercer", "distribution de la partie")
	assert_eq(CharacterDB.id_of(2), "weissmann", "hors distribution : emplacement")
	Net.cast = saved_cast
	Net.players = saved_players


func test_host_cast_reads_its_own_setting() -> void:
	var saved_players := Net.players
	var saved_char := Settings.character
	Net.players = {1: {"name": "Hote", "slot": 0}, 2: {"name": "Invite", "slot": 1, "char": "callahan"}}
	Settings.character = "mercer"
	var c := _ids(Net.srv_resolve_cast(0))
	assert_eq(c, {1: "mercer", 2: "callahan"})
	Settings.character = CharacterDB.AUTO
	c = _ids(Net.srv_resolve_cast(0))
	assert_eq(c[1], "orlov", "hôte en auto : Callahan est pris")
	Settings.character = saved_char
	Net.players = saved_players


func test_missing_lines_file_is_silent() -> void:
	assert_eq(CharacterDB.lines("personne_inconnu"), {}, "fichier absent : aucune réplique")
	assert_eq(CharacterDB.variants("personne_inconnu", "round_start"), 0)
	assert_eq(CharacterDB.text("fr", "personne_inconnu", "round_start", 0), "")


## Mains FPS : celles du joueur de baseball (personnage unique, GAME_CONCEPT
## §3), en cubes de 2,5 cm, quelle que soit la place du joueur.
func test_baseball_view_hands() -> void:
	assert_eq(ViewHands.STYLES.size(), 1, "une seule tenue : le joueur de baseball")
	for piece_name in ViewHands.PIECES:
		var arr := ViewHands.piece_arrays(0, piece_name)
		assert_false(arr.is_empty(), "%s : pièce du modèle des mains" % piece_name)
	# Gants (cuir) sur les poings, manche (tissu) sur l'avant-bras.
	assert_true(ViewHands.piece_arrays(0, "grip").has("leather"), "gant de batteur")
	var fore := ViewHands.piece_arrays(0, "forearm")
	assert_true(fore.has("cloth") and fore.has("leather"), "avant-bras : manche et manchette du gant")
	# Même tenue pour toutes les places (index de tenue accepté, ramené à 0).
	assert_eq(ViewHands.piece(5, "grip").keys(), ViewHands.piece(0, "grip").keys())
	# Avant-bras de 3 × 3 cubes (7,5 cm) au poignet.
	var lo := INF
	var hi := -INF
	for v in fore.cloth[0] as PackedVector3Array:
		if v.z < -0.2:
			lo = minf(lo, v.x)
			hi = maxf(hi, v.x)
	assert_near(hi - lo, 0.075, 0.002, "avant-bras de 3 cubes de large")


func test_jojo_player_model_is_bigger() -> void:
	var m := PlayerModel.new()
	host.add_child(m)
	m.build(Color.RED, 6)
	assert_near(m.skel.scale.y, PlayerModel.JOJO_SCALE, 0.001, "plus grand")
	assert_true(PlayerModel.JOJO_SCALE > 1.05 and PlayerModel.JOJO_SCALE < 1.15)
	m.free()


func test_berg_player_model_is_smaller() -> void:
	var m := PlayerModel.new()
	host.add_child(m)
	m.build(Color.RED, 5)
	assert_near(m.skel.scale.y, PlayerModel.BERG_SCALE, 0.001, "plus petite")
	assert_true(PlayerModel.BERG_SCALE > 0.85 and PlayerModel.BERG_SCALE < 0.97)
	m.free()
	var o := PlayerModel.new()
	host.add_child(o)
	o.build(Color.RED, 0)
	assert_near(o.skel.scale.y, 1.0, 0.001, "Callahan à l'échelle normale")
	o.free()


func test_mercer_player_model() -> void:
	assert_eq(PlayerModel.OUTFITS.size(), CharacterDB.IDS.size(), "une apparence par personnage")
	for i in CharacterDB.IDS.size():
		var m := PlayerModel.new()
		host.add_child(m)
		m.build(Color.RED, i)
		assert_true(m.skel != null and m.bones.size() > 10, "modèle %s construit" % CharacterDB.IDS[i])
		m.free()


func test_options_character_selector() -> void:
	var screen: GDScript = load("res://scripts/ui/screens/options_screen.gd")
	var saved_lang := Settings.language
	for lang in Settings.LANGUAGES:
		Settings.language = lang
		var choices: PackedStringArray = screen.character_choices()
		assert_eq(choices.size(), CharacterDB.IDS.size() + 1, "automatique + sept personnages")
		assert_eq(choices[0], "AUTOMATIQUE" if lang == "fr" else "AUTOMATIC")
		assert_eq(choices[5], "SGT-CHEF MERCER" if lang == "fr" else "GYSGT MERCER")
		assert_eq(choices[6], "DR BERG")
		assert_eq(choices[7], "JOJO")
		# Chaque nom tient entre les flèches du sélecteur (MenuOptionRow._draw).
		var w := MenuOptionRow.GAUGE_W + 88.0 - MenuOptionRow.ARROW_W * 0.5
		for c in choices:
			var tw := UiStyle.font("impact").get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			assert_true(tw <= w, "« %s » tient dans le sélecteur (%d / %d px)" % [c, tw, w])
	Settings.language = saved_lang
	assert_eq(screen.character_choice_index(CharacterDB.AUTO), 0)
	assert_eq(screen.character_choice_index("mercer"), 5)
	assert_eq(screen.character_choice_index("berg"), 6)
	assert_eq(screen.character_choice_index("jojo"), 7)
	assert_eq(screen.character_choice_index("zorg"), 0)
	for i in 8:
		assert_eq(screen.character_choice_index(screen.character_of_choice_index(i)), i, "aller-retour %d" % i)
	assert_eq(screen.character_of_choice_index(99), CharacterDB.AUTO)
