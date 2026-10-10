extends TestCase
## Barème de l'XP (XpRules), relevé d'une partie, textes de l'écran de fin et
## calibrage (XpCalibration) : GAME_CONCEPT §4.15, docs/XP_RULES.md.
## Un nouveau mob : ajouter son type à XpRules.ENEMIES, puis la ligne de
## test_bareme (valeur attendue) ; test_categories vérifie sa fourchette.


func test_bareme() -> void:
	# Valeurs de référence (docs/XP_RULES.md §2) : changer l'une d'elles est
	# une décision de calibrage (relancer test_calibrage).
	var expected := {
		XpRules.WALKER: 4, XpRules.RUNNER: 4, XpRules.SPRINTER: 4, XpRules.CRAWLER: 4,
		XpRules.DOG: 12, XpRules.MINIBOSS_GENERIC: 60, XpRules.BOSS_GENERIC: 240,
	}
	assert_eq(XpRules.ENEMIES.size(), expected.size(), "chaque type du barème a sa valeur attendue ici")
	for t in expected:
		assert_eq(XpRules.base_xp(t), expected[t], "XP de base : %s" % t)
		assert_eq(XpRules.kill_xp(t, 1), expected[t], "manche 1 : XP de base (%s)" % t)
	assert_eq(XpRules.base_xp("inconnu"), 0)
	assert_eq(XpRules.kill_xp("inconnu", 10), 0)


func test_categories() -> void:
	for t in XpRules.ENEMIES:
		var e: Dictionary = XpRules.ENEMIES[t]
		assert_true(XpRules.CATEGORY_RANGE.has(e.category), "%s : catégorie connue" % t)
		var r: Array = XpRules.CATEGORY_RANGE[e.category]
		assert_true(int(e.xp) >= r[0] and int(e.xp) <= r[1], "%s : %d XP dans [%d, %d] (%s)" % [t, e.xp, r[0], r[1], e.category])
		assert_true(String(e.fr) != "" and String(e.en) != "", "%s : noms FR/EN" % t)
	# Les catégories s'échelonnent : commun < spécial < mini-boss < boss.
	var cats := [XpRules.COMMON, XpRules.SPECIAL, XpRules.MINIBOSS, XpRules.BOSS]
	for i in cats.size() - 1:
		assert_true(XpRules.CATEGORY_RANGE[cats[i]][1] <= XpRules.CATEGORY_RANGE[cats[i + 1]][0],
				"%s sous %s" % [cats[i], cats[i + 1]])
	assert_eq(XpRules.category_of(XpRules.DOG), XpRules.SPECIAL)
	assert_eq(XpRules.category_of(XpRules.CRAWLER), XpRules.COMMON)


func test_type_d_ennemi() -> void:
	assert_eq(XpRules.enemy_type(true, false, RoundRules.SPRINT), XpRules.DOG, "chien")
	assert_eq(XpRules.enemy_type(false, true, RoundRules.SPRINT), XpRules.CRAWLER, "rampant, quelle que soit sa vitesse d'origine")
	assert_eq(XpRules.enemy_type(false, false, RoundRules.WALK), XpRules.WALKER)
	assert_eq(XpRules.enemy_type(false, false, 1), XpRules.RUNNER, "trot compté coureur")
	assert_eq(XpRules.enemy_type(false, false, RoundRules.RUN), XpRules.RUNNER)
	assert_eq(XpRules.enemy_type(false, false, RoundRules.SPRINT), XpRules.SPRINTER)
	assert_eq(XpSystem.enemy_type_of(null), XpRules.WALKER, "corps déjà retiré : marcheur")


func test_bonus_de_manche() -> void:
	assert_near(XpRules.round_factor(1), 1.0, 1e-6)
	assert_near(XpRules.round_factor(0), 1.0, 1e-6, "manche 0 traitée comme la 1")
	assert_near(XpRules.round_factor(2), 1.15, 1e-6, "+15 % par manche")
	assert_near(XpRules.round_factor(10), 2.35, 1e-6)
	assert_near(XpRules.round_factor(28), XpRules.ROUND_BONUS_CAP, 1e-6, "plafond atteint à la manche 28")
	assert_near(XpRules.round_factor(500), XpRules.ROUND_BONUS_CAP, 1e-6, "plafonné")
	assert_eq(XpRules.kill_xp(XpRules.WALKER, 10), 9)
	assert_eq(XpRules.kill_xp(XpRules.WALKER, 20), 15)
	assert_eq(XpRules.kill_xp(XpRules.WALKER, 100), 20)
	assert_eq(XpRules.kill_xp(XpRules.DOG, 5), 19)
	# Toujours croissant (jamais moins en allant plus loin).
	for r in range(1, 60):
		assert_true(XpRules.kill_xp(XpRules.WALKER, r + 1) >= XpRules.kill_xp(XpRules.WALKER, r), "croissant manche %d" % r)


func test_autres_sources() -> void:
	assert_eq(XpRules.round_xp(1), 3)
	assert_eq(XpRules.round_xp(10), 30)
	assert_eq(XpRules.round_xp(0), 0)
	assert_eq(XpRules.wave_xp(WaveRules.SPECIAL, 5), 96)
	assert_eq(XpRules.wave_xp(WaveRules.BOSS, 15), roundi(240 * XpRules.round_factor(15)))
	assert_eq(XpRules.wave_xp("", 5), 0, "manche normale : pas de vague")
	assert_eq(XpRules.evac_bonus(1000), 250)
	assert_eq(XpRules.evac_bonus(-5), 0)


func test_releve_d_une_partie() -> void:
	var l := XpRules.new_ledger()
	assert_eq(XpRules.add_kill(l, XpRules.WALKER, 1), 4)
	assert_eq(XpRules.add_kill(l, XpRules.WALKER, 1), 4)
	assert_eq(XpRules.add_kill(l, XpRules.CRAWLER, 2), 5)
	assert_eq(XpRules.add_kill(l, "inconnu", 2), 0, "type inconnu ignoré")
	assert_eq(XpRules.add_round(l, 1), 3)
	assert_eq(XpRules.add_kill(l, XpRules.DOG, 5), 19)
	assert_eq(XpRules.add_round(l, 5) + XpRules.add_wave(l, WaveRules.SPECIAL, 5), 15 + 96)
	assert_eq(XpRules.kill_count(l), 4)
	assert_eq(int(l.kills[XpRules.WALKER]), 2)
	assert_eq(XpRules.kills_xp(l), 4 + 4 + 5 + 19)
	var sub := 32 + 3 + 15 + 96
	assert_eq(XpRules.subtotal(l), sub)
	assert_eq(XpRules.total(l), sub, "pas de bonus avant la fin")
	# Évacuation : bonus une seule fois, relevé clos.
	assert_eq(XpRules.close(l, true), roundi(sub * 0.25))
	assert_eq(XpRules.total(l), sub + roundi(sub * 0.25))
	assert_eq(XpRules.close(l, true), 0, "clos une seule fois")
	assert_eq(XpRules.add_kill(l, XpRules.WALKER, 1), 0, "plus rien après la clôture")
	assert_eq(XpRules.add_round(l, 6), 0)
	# Défaite : pas de bonus, l'XP reste.
	var d := XpRules.new_ledger()
	XpRules.add_kill(d, XpRules.SPRINTER, 12)
	assert_eq(XpRules.close(d, false), 0)
	assert_eq(XpRules.total(d), XpRules.kill_xp(XpRules.SPRINTER, 12), "défaite : XP gardée")


func test_releve_relu_du_reseau() -> void:
	var l := XpRules.new_ledger()
	XpRules.add_kill(l, XpRules.DOG, 5)
	XpRules.add_round(l, 5)
	XpRules.add_wave(l, WaveRules.SPECIAL, 5)
	XpRules.close(l, true)
	var back := XpRules.clean_ledger(l.duplicate(true))
	assert_eq(XpRules.total(back), XpRules.total(l), "aller-retour")
	assert_true(back.closed)
	var bad := XpRules.clean_ledger({"kills": {"x": 5, XpRules.DOG: -3, XpRules.WALKER: 1e30},
		"kill_xp": {XpRules.WALKER: "9"}, "rounds": NAN, "round_xp": -10, "waves": {"autre": 2},
		"wave_xp": INF, "evac_bonus": [1], "closed": "oui"})
	assert_false(bad.kills.has("x"), "type inconnu écarté")
	assert_eq(int(bad.kills[XpRules.DOG]), 0, "négatif borné")
	assert_eq(int(bad.kills[XpRules.WALKER]), XpRules.LEDGER_CAP, "énorme borné")
	assert_false(bad.kill_xp.has(XpRules.WALKER) and int(bad.kill_xp[XpRules.WALKER]) != 0, "texte refusé")
	assert_eq(XpRules.total(bad), 0)
	assert_false(bad.closed)
	assert_eq(XpRules.total(XpRules.clean_ledger(null)), 0)
	assert_eq(XpRules.total(XpRules.clean_ledger("Object(Node)")), 0)


func test_resultat_de_partie_transporte_les_releves() -> void:
	var l := XpRules.new_ledger()
	XpRules.add_kill(l, XpRules.RUNNER, 7)
	XpRules.close(l, false)
	var r := MatchResult.new()
	r.xp_ledgers = {1: l, 1234: XpRules.new_ledger()}
	var back := MatchResult.from_dict(r.to_dict())
	assert_eq(back.xp_ledgers.size(), 2)
	assert_eq(XpRules.total(back.xp_ledgers[1]), XpRules.total(l))
	var many := {}
	for i in 100:
		many[i + 1] = l
	many["x"] = l
	var big := MatchResult.from_dict({"xp_ledgers": many})
	assert_eq(big.xp_ledgers.size(), MatchResult.MAX_LEDGERS, "nombre de relevés borné")
	assert_true(MatchResult.from_dict({"xp_ledgers": [1, 2]}).xp_ledgers.is_empty())


func test_textes_fr_en() -> void:
	var was: String = Settings.language
	var l := XpRules.new_ledger()
	XpRules.add_kill(l, XpRules.WALKER, 1)
	XpRules.add_kill(l, XpRules.WALKER, 1)
	XpRules.add_kill(l, XpRules.DOG, 5)
	XpRules.add_round(l, 1)
	XpRules.add_round(l, 5)
	XpRules.add_wave(l, WaveRules.SPECIAL, 5)
	XpRules.close(l, true)
	var r := MatchResult.new()
	r.xp_ledger = l
	r.xp = XpRules.total(l)
	r.level_before = 3
	r.level_after = 4
	r.profile_xp = PlayerProfile.xp_for_level(4) + 50
	Settings.language = "fr"
	assert_eq(XpRules.breakdown(l), PackedStringArray(["Marcheurs ×2 : +8 XP", "Chiens ×1 : +19 XP",
		"Manches survécues ×2 : +18 XP", "Vagues vaincues ×1 : +96 XP", "Bonus d'évacuation : +35 XP"]))
	assert_eq(r.xp_title(), "XP GAGNÉE : +176")
	assert_eq(r.xp_level_text(), "NIVEAU 3 → 4   NIVEAU SUPÉRIEUR !")
	assert_eq(r.xp_progress(), Vector2i(50, PlayerProfile.xp_to_next(4)))
	assert_eq(r.xp_progress_text(), "50 / %s XP vers le niveau 5" % XpSystem.group(PlayerProfile.xp_to_next(4)))
	assert_eq(XpSystem.counter_text(12450), "XP DE PARTIE 12 450")
	assert_eq(XpSystem.counter_text(0), "")
	assert_eq(XpSystem.pop_text(9), "+9 XP")
	r.level_after = 6
	assert_eq(r.xp_level_text(), "NIVEAU 3 → 6   +3 NIVEAUX !")
	r.level_before = 50
	r.level_after = 50
	r.profile_xp = PlayerProfile.xp_for_level(50) + 10
	assert_eq(r.xp_level_text(), "NIVEAU 50 (MAXIMUM) — l'XP continue d'être comptée")
	assert_eq(r.xp_progress_text(), "%s XP au total" % XpSystem.group(r.profile_xp))
	Settings.language = "en"
	assert_eq(XpRules.breakdown(l)[0], "Walkers ×2: +8 XP")
	assert_eq(r.xp_title(), "XP EARNED: +176")
	r.level_before = 1
	r.level_after = 2
	assert_eq(r.xp_level_text(), "LEVEL 1 → 2   LEVEL UP!")
	assert_eq(XpSystem.counter_text(30), "MATCH XP 30")
	Settings.language = was
	assert_eq(XpSystem.group(1234567), "1 234 567")
	assert_eq(XpSystem.group(999), "999")


## Simulation de calibrage (XpCalibration) : temps visés du concept (§4.15),
## à ±25 % (les hypothèses de jeu sont des moyennes à re-mesurer en jeu).
func test_calibrage() -> void:
	print(XpCalibration.report())
	for players in [1, 4]:
		var h := XpCalibration.hours_to_levels(players)
		for lvl in XpCalibration.TARGET_HOURS:
			var want: float = XpCalibration.TARGET_HOURS[lvl]
			var got: float = h[lvl]
			assert_true(absf(got / want - 1.0) <= XpCalibration.TOLERANCE,
					"%d joueur(s) : niveau %d en %.1f h (visé %.0f h)" % [players, lvl, got, want])
	# Survivre plus longtemps rapporte plus : XP par heure croissante avec la
	# manche d'évacuation.
	var prev := 0.0
	for e in [10, 15, 20, 25]:
		var m := XpCalibration.simulate_match(e)
		var rate: float = m.xp / m.sec
		assert_true(rate > prev, "XP/h croissante (évacuation manche %d)" % e)
		prev = rate
