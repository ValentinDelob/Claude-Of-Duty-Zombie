extends TestCase
## Règles de la fenêtre d'évacuation (EvacRules, GAME_CONCEPT.md §4.5), résultat
## de partie (MatchResult) et porte d'évacuation exigée par le validateur.

const A := PlayerData.Life.ALIVE
const D := PlayerData.Life.DOWNED
const X := PlayerData.Life.DEAD
const LEAVE := EvacRules.Vote.LEAVE
const READY := EvacRules.Vote.READY


func test_choix_de_vote() -> void:
	assert_true(EvacRules.is_choice(READY), "CONTINUER")
	assert_true(EvacRules.is_choice(LEAVE), "ÉVACUER")
	assert_false(EvacRules.is_choice(EvacRules.Vote.NONE), "EN ATTENTE ne se choisit pas")
	for bad in [7, -1, "1", 1.0, null, [2]]:
		assert_false(EvacRules.is_choice(bad), "valeur réseau refusée : %s" % str(bad))
	assert_eq(EvacRules.vote_text(READY), Lang.t("CONTINUER", "CONTINUE"))
	assert_eq(EvacRules.vote_text(LEAVE), Lang.t("ÉVACUER", "EVACUATE"))
	assert_eq(EvacRules.vote_text(EvacRules.Vote.NONE), Lang.t("EN ATTENTE", "WAITING"))


func test_appuis_de_vote() -> void:
	assert_eq(PlayerInput.pick_vote(true, false), READY, "F1 / croix gauche : CONTINUER")
	assert_eq(PlayerInput.pick_vote(false, true), LEAVE, "F2 / croix droite : ÉVACUER")
	assert_eq(PlayerInput.pick_vote(false, false), EvacRules.Vote.NONE, "aucun appui")
	assert_eq(PlayerInput.pick_vote(true, true), EvacRules.Vote.NONE, "les deux à la fois : ambigu, ignoré")


func test_lignes_du_cadre() -> void:
	# Joueur local (2) d'abord, puis l'ordre de l'équipe ; le mort (4) n'a pas
	# de ligne ; un vote illisible compte comme « en attente ».
	var rows := EvacRules.vote_rows({1: LEAVE, 3: READY, 5: 9}, {1: A, 2: D, 3: A, 4: X, 5: A}, 2, [1, 2, 3, 4])
	assert_eq(rows.map(func(r): return r.pid), [2, 1, 3, 5])
	assert_eq(rows.map(func(r): return r.vote), [EvacRules.Vote.NONE, LEAVE, READY, EvacRules.Vote.NONE])
	assert_eq(rows.map(func(r): return r.me), [true, false, false, false])
	assert_eq(EvacRules.vote_rows({}, {1: X}, 1, [1]), [], "local mort : spectateur, aucune ligne")
	assert_eq(EvacRules.vote_rows({}, {1: A}, 9, []).size(), 1, "joueur local inconnu : les votants seuls")
	assert_eq(EvacVotePanel.row_name("Valentin", true), "Valentin" + Lang.t(" (toi)", " (you)"))
	assert_eq(EvacVotePanel.row_name("Mehdi", false), "Mehdi")
	assert_eq(EvacVotePanel.vote_color(READY), Color("F5C542"), "CONTINUER jaune")
	assert_eq(EvacVotePanel.vote_color(LEAVE), Color("4FE3C1"), "ÉVACUER turquoise")
	assert_eq(EvacVotePanel.vote_color(EvacRules.Vote.NONE).a, 0.5, "EN ATTENTE gris")


func test_repere_de_la_porte() -> void:
	var view := Vector2(1280, 720)
	var half := Vector2(100, 50)
	var on := EvacDoorMarker.place(Vector2(718, 300), false, view, half)
	assert_true(on.on_screen and on.pos == Vector2(718, 300), "à l'écran : sur la porte")
	var right := EvacDoorMarker.place(Vector2(3000, 360), false, view, half)
	assert_false(right.on_screen)
	assert_eq(right.pos, Vector2(1180, 360), "à droite hors de l'écran : collé au bord droit")
	assert_true(right.dir.is_equal_approx(Vector2.RIGHT), "flèche vers la droite")
	var back := EvacDoorMarker.place(Vector2(400, 360), true, view, half)
	assert_false(back.on_screen, "derrière la caméra : jamais à l'écran")
	assert_eq(back.pos, Vector2(1180, 360), "derrière, à gauche du point projeté : bord opposé")
	var center_back := EvacDoorMarker.place(Vector2(640, 360), true, view, half)
	assert_eq(center_back.pos, Vector2(640, 670), "droit derrière : en bas de l'écran")
	assert_eq(EvacDoorMarker.bob(0.0), 0.0)
	assert_near(EvacDoorMarker.bob(EvacDoorMarker.BOB_PERIOD * 0.5), -EvacDoorMarker.BOB_PX, 0.001, "mi-course : 5 px plus haut")
	assert_near(EvacDoorMarker.bob(EvacDoorMarker.BOB_PERIOD), 0.0, 0.001)


func test_tous_prets_reprise() -> void:
	var life := {1: A, 2: A}
	assert_eq(EvacRules.decide({1: READY}, life, {}, 60.0), EvacRules.NONE, "un seul prêt : on attend")
	assert_eq(EvacRules.decide({1: READY, 2: READY}, life, {}, 60.0), EvacRules.RESUME, "tous prêts : reprise")
	assert_eq(EvacRules.decide({1: READY}, {1: A, 2: X}, {}, 60.0), EvacRules.RESUME, "un mort ne vote pas")


func test_evacuation_tous_a_la_porte() -> void:
	var life := {1: A, 2: A}
	var votes := {1: LEAVE, 2: LEAVE}
	assert_eq(EvacRules.decide(votes, life, {1: true, 2: false}, 60.0), EvacRules.NONE, "un joueur loin de la porte : on attend")
	assert_eq(EvacRules.decide(votes, life, {1: true, 2: true}, 60.0), EvacRules.EVACUATE, "tous à la porte et « partir » : évacuation")
	assert_eq(EvacRules.decide({1: LEAVE, 2: READY}, life, {1: true, 2: true}, 60.0), EvacRules.NONE, "un vote « prêt » : pas d'évacuation")
	assert_eq(EvacRules.decide(votes, {1: A, 2: D}, {1: true, 2: true}, 60.0), EvacRules.NONE, "un joueur à terre bloque l'évacuation")
	assert_eq(EvacRules.decide({1: LEAVE}, {1: A, 2: X}, {1: true}, 60.0), EvacRules.EVACUATE, "le mort part avec l'équipe")


func test_fin_du_temps() -> void:
	assert_eq(EvacRules.decide({1: LEAVE}, {1: A}, {1: false}, 0.0), EvacRules.RESUME, "2 min écoulées : la partie continue")
	assert_eq(EvacRules.decide({1: LEAVE}, {1: A}, {1: true}, 0.0), EvacRules.EVACUATE, "à la porte au dernier instant : évacuation")
	assert_eq(EvacRules.decide({}, {}, {}, 0.0), EvacRules.NONE, "aucun joueur : rien")
	assert_eq(EvacRules.DURATION, 120.0, "fenêtre de 2 minutes")


func test_joueur_parti_pendant_la_fenetre() -> void:
	var votes := {1: LEAVE, 2: READY, 3: LEAVE}
	# Le joueur 2 s'est déconnecté : il n'est plus dans `life`.
	var life := {1: A, 3: A}
	assert_eq(EvacRules.prune_votes(votes, life), {1: LEAVE, 3: LEAVE}, "vote de l'absent oublié")
	assert_eq(EvacRules.decide(votes, life, {1: true, 3: true}, 60.0), EvacRules.EVACUATE, "on n'attend jamais un absent")
	assert_eq(EvacRules.vote_rows(EvacRules.prune_votes(votes, life), life, 1, [1, 2, 3]).map(func(r): return r.pid), [1, 3],
			"cadre : plus de ligne pour l'absent")
	# Hôte seul restant.
	assert_eq(EvacRules.decide({1: LEAVE, 2: LEAVE}, {1: A}, {1: true}, 60.0), EvacRules.EVACUATE, "hôte seul : il part")
	assert_eq(EvacRules.decide({2: READY}, {1: A}, {1: true}, 60.0), EvacRules.NONE, "seul le vote de l'absent : on attend l'hôte")


func test_a_terre_mort_reanime() -> void:
	var votes := {1: LEAVE, 2: LEAVE}
	var zone := {1: true, 2: true}
	assert_eq(EvacRules.decide(votes, {1: A, 2: D}, zone, 60.0), EvacRules.NONE, "à terre dans la zone : on attend")
	assert_eq(EvacRules.decide(votes, {1: A, 2: A}, zone, 60.0), EvacRules.EVACUATE, "réanimé : l'équipe part")
	assert_eq(EvacRules.decide(votes, {1: A, 2: X}, {1: true}, 60.0), EvacRules.EVACUATE, "mort (spectateur) : l'équipe part avec lui")
	assert_eq(EvacRules.decide({1: READY, 2: LEAVE}, {1: A, 2: X}, {}, 60.0), EvacRules.RESUME, "vote d'un mort ignoré")
	assert_eq(EvacRules.decide({}, {1: X, 2: X}, {}, 60.0), EvacRules.NONE, "aucun votant : rien")
	assert_eq(EvacRules.voters({1: A, 2: D, 3: X}), [1, 2], "votants : debout et à terre")


func test_votes_qui_changent_et_sortie_de_zone() -> void:
	var life := {1: A, 2: A}
	assert_eq(EvacRules.decide({1: LEAVE, 2: LEAVE}, life, {1: true, 2: false}, 60.0), EvacRules.NONE, "sorti de la zone après avoir voté : on attend")
	assert_eq(EvacRules.decide({1: READY, 2: LEAVE}, life, {1: true, 2: true}, 60.0), EvacRules.NONE, "vote changé en CONTINUER : ni départ ni reprise")
	assert_eq(EvacRules.decide({1: READY, 2: READY}, life, {1: true, 2: true}, 60.0), EvacRules.RESUME, "l'autre aussi passe à CONTINUER : reprise")


func test_fin_du_temps_au_moment_du_vote() -> void:
	var life := {1: A, 2: A}
	assert_eq(EvacRules.decide({1: LEAVE, 2: LEAVE}, life, {1: true, 2: true}, 0.0), EvacRules.EVACUATE, "temps écoulé, équipe prête : évacuation d'abord")
	assert_eq(EvacRules.decide({1: LEAVE, 2: LEAVE}, {1: A, 2: D}, {1: true, 2: true}, 0.0), EvacRules.RESUME, "temps écoulé, un joueur à terre : la partie continue")
	assert_eq(EvacRules.decide({1: READY, 2: READY}, life, {}, -0.5), EvacRules.RESUME, "temps négatif : reprise")


func test_zone_de_la_porte() -> void:
	assert_true(EvacRules.in_zone_local(Vector3(0, 0, 1.0)), "devant la porte")
	assert_true(EvacRules.in_zone_local(Vector3(1.9, 0.1, 3.4)), "coin de la zone")
	assert_false(EvacRules.in_zone_local(Vector3(2.5, 0, 1.0)), "trop sur le côté")
	assert_false(EvacRules.in_zone_local(Vector3(0, 0, 4.0)), "trop loin")
	assert_false(EvacRules.in_zone_local(Vector3(0, 3.0, 1.0)), "à l'étage")
	assert_false(EvacRules.in_zone_local(Vector3(0, 0, -1.0)), "derrière le mur")


func test_affichage() -> void:
	assert_eq(EvacRules.clock_text(119.2), "2:00")
	assert_eq(EvacRules.clock_text(102.0), "1:42", "temps de la maquette")
	assert_eq(EvacRules.clock_text(61.0), "1:01")
	assert_eq(EvacRules.clock_text(-3.0), "0:00")


func test_resultat_de_partie() -> void:
	var r := MatchResult.new()
	r.evacuated = true
	r.round_reached = 10
	r.duration_sec = 754.4
	r.kills = 321
	var back := MatchResult.from_dict(r.to_dict())
	assert_true(back.evacuated, "issue gardée")
	assert_eq(back.round_reached, 10)
	assert_eq(back.kills, 321)
	assert_near(back.duration_sec, 754.4, 0.01)
	assert_eq(MatchResult.time_text(754.4), "12:34")
	assert_eq(MatchResult.time_text(3725.0), "1:02:05")
	assert_true(back.details().contains("10") and back.details().contains("12:34"), back.details())
	var bad := MatchResult.from_dict({"evacuated": "oui", "round": NAN, "duration": INF, "loot": 3, "inconnu": 1})
	assert_false(bad.evacuated, "valeur illisible : défaut")
	assert_eq(bad.round_reached, 0)
	assert_eq(bad.duration_sec, 0.0)
	assert_eq(bad.loot, {})
	assert_eq(MatchResult.from_dict(null).evacuated, false)
	assert_true(r.to_dict().has("loot") and r.to_dict().has("xp"), "place prévue pour le butin et l'XP")


## Carte de l'éditeur minimale : une pièce, une fenêtre, un départ, une boîte.
## Format 19 : avec la station de construction (obligatoire) contre le mur
## nord de la salle de départ, sauf `with_station` faux.
static func small_map(with_door := true, behind_door := false, with_station := true) -> EditorMap:
	var m := EditorMap.blank("evac_t")
	m.zones = [{"id": "z1", "nom": {"fr": "A", "en": "A"}}, {"id": "z2", "nom": {"fr": "B", "en": "B"}}]
	m.depart = "z1"
	m.pieces = [{"id": "p1", "zone": "z1", "contour": [[0, 0], [10, 0], [10, 8], [0, 8]], "altitude": 0},
		{"id": "p2", "zone": "z2", "contour": [[10, 0], [18, 0], [18, 8], [10, 8]], "altitude": 0}]
	m.ouvertures = [{"id": "o1", "type": "fenetre", "position": [5, 0], "altitude": 0},
		{"id": "o2", "type": "fenetre", "position": [14, 0], "altitude": 0},
		{"id": "o3", "type": "porte", "position": [10, 4], "largeur": 2, "prix": 750, "altitude": 0}]
	m.objets = [{"id": "s1", "type": "depart", "position": [3, 5], "altitude": 0},
		{"id": "b1", "type": "boite", "position": [5, 8], "mur": "s", "depart": true, "altitude": 0}]
	if with_door:
		# Mur ouest de la salle de départ, ou mur est de la salle derrière la porte payante.
		m.objets.append({"id": "e1", "type": "evacuation", "position": [18, 4] if behind_door else [0, 4],
			"mur": "e" if behind_door else "o", "altitude": 0})
	if with_station:
		m.objets.append({"id": "t1", "type": "station", "position": [8, 0], "mur": "n", "altitude": 0})
	return m


func _errors(m: EditorMap) -> Array:
	var v := MapRaster.build(m).v
	v.analyze()
	return v.errors().map(func(e): return String(e.fr))


func test_validateur_exige_la_porte() -> void:
	var ok := _errors(small_map(true))
	assert_true(ok.is_empty(), "carte avec porte d'évacuation acceptée : %s" % str(ok))
	var none := _errors(small_map(false))
	assert_true(none.any(func(e: String): return e.contains("aucune porte d'évacuation")), "carte sans porte refusée : %s" % str(none))
	var far := _errors(small_map(true, true))
	assert_true(far.any(func(e: String): return e.contains("inaccessible depuis le départ")), "porte derrière une porte payante refusée : %s" % str(far))


func test_export_vers_le_jeu() -> void:
	var d := EditorMapDef.from_map(small_map(true))
	assert_true(d.is_valid(), "carte jouable")
	var mk := d.create_layout().evac_door()
	assert_true(mk != null, "porte d'évacuation transmise au jeu")
	if mk:
		assert_true(mk.wall.x < -0.9, "contre le mur ouest (%s)" % str(mk.wall))
