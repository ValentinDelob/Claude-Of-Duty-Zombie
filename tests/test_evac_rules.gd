extends TestCase
## Règles de la fenêtre d'évacuation (EvacRules, GAME_CONCEPT.md §4.5), résultat
## de partie (MatchResult) et porte d'évacuation exigée par le validateur.

const A := PlayerData.Life.ALIVE
const D := PlayerData.Life.DOWNED
const X := PlayerData.Life.DEAD
const LEAVE := EvacRules.Vote.LEAVE
const READY := EvacRules.Vote.READY


func test_vote_alterne() -> void:
	assert_eq(EvacRules.next_vote(EvacRules.Vote.NONE), LEAVE, "premier appui : partir")
	assert_eq(EvacRules.next_vote(LEAVE), READY)
	assert_eq(EvacRules.next_vote(READY), LEAVE)


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


func test_zone_de_la_porte() -> void:
	assert_true(EvacRules.in_zone_local(Vector3(0, 0, 1.0)), "devant la porte")
	assert_true(EvacRules.in_zone_local(Vector3(1.9, 0.1, 3.4)), "coin de la zone")
	assert_false(EvacRules.in_zone_local(Vector3(2.5, 0, 1.0)), "trop sur le côté")
	assert_false(EvacRules.in_zone_local(Vector3(0, 0, 4.0)), "trop loin")
	assert_false(EvacRules.in_zone_local(Vector3(0, 3.0, 1.0)), "à l'étage")
	assert_false(EvacRules.in_zone_local(Vector3(0, 0, -1.0)), "derrière le mur")


func test_affichage() -> void:
	var t := EvacRules.tally({1: LEAVE, 2: READY}, {1: A, 2: A, 3: X}, {1: true, 2: true})
	assert_eq(t, {"voters": 2, "leave": 1, "ready": 1, "in_zone": 2})
	assert_eq(EvacRules.clock_text(119.2), "2:00")
	assert_eq(EvacRules.clock_text(61.0), "1:01")
	assert_eq(EvacRules.clock_text(-3.0), "0:00")
	var s := EvacRules.status_text(90.0, t, LEAVE)
	assert_true(s.contains("1:30") and s.contains("1/2"), s)


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
static func small_map(with_door := true, behind_door := false) -> EditorMap:
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
