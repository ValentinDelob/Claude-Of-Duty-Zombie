extends TestCase
## Énergie du joueur (PlayerEnergy, GAME_CONCEPT §4.14) : dépense de course,
## recharge après délai, épuisement de 0 à 50, pénalités, bonus d'atout, bornes.

const DT := 1.0 / 60.0


## Avance de `s` secondes par images de DT.
func _run(e: PlayerEnergy, s: float, sprinting: bool) -> void:
	for i in roundi(s / DT):
		e.tick(DT, sprinting)


func test_valeurs_initiales() -> void:
	var e := PlayerEnergy.new()
	assert_eq(e.value, 100.0)
	assert_eq(e.max_value, 100.0)
	assert_false(e.exhausted)
	assert_eq(e.ratio(), 1.0)
	assert_true(e.can_start_sprint())
	assert_eq(e.jump_velocity_mult(), 1.0)
	assert_eq(e.melee_time_mult(), 1.0)


func test_course_vide_en_4_s() -> void:
	var e := PlayerEnergy.new()
	_run(e, 1.0, true)
	assert_near(e.value, 75.0, 0.01, "25 par seconde de course")
	assert_false(e.exhausted)
	_run(e, 3.05, true)
	assert_near(e.value, 0.0, 0.01, "vide après 4 s")
	assert_true(e.exhausted, "épuisé à 0")
	_run(e, 1.0, true)
	assert_eq(e.value, 0.0, "jamais sous 0")


func test_recharge_apres_delai() -> void:
	var e := PlayerEnergy.new()
	_run(e, 1.0, true)
	var v := e.value
	_run(e, 0.35, false)
	assert_near(e.value, v, 0.001, "rien pendant le délai de 0,4 s")
	_run(e, 0.05, false)
	_run(e, 0.5, false)
	assert_near(e.value, v + 20.0, 0.8, "40 par seconde après le délai")
	_run(e, 5.0, false)
	assert_eq(e.value, 100.0, "plafonnée au max")


func test_depense_relance_le_delai() -> void:
	var e := PlayerEnergy.new()
	e.spend(30.0)
	_run(e, 0.3, false)
	e.spend(10.0)
	_run(e, 0.3, false)
	assert_near(e.value, 60.0, 0.001, "chaque dépense repousse la recharge")


func test_plein_en_2_5_s() -> void:
	var e := PlayerEnergy.new()
	e.spend(60.0)  # pas épuisé : recharge normale
	_run(e, PlayerEnergy.REGEN_DELAY + 1.5, false)
	assert_near(e.value, 100.0, 0.8)


func test_epuisement_de_0_a_50() -> void:
	var e := PlayerEnergy.new()
	e.spend(100.0)
	assert_true(e.exhausted)
	assert_false(e.can_start_sprint(), "pas de course épuisé")
	assert_eq(e.jump_velocity_mult(), PlayerEnergy.EXHAUSTED_JUMP_MULT)
	assert_eq(e.melee_time_mult(), 2.0, "coups deux fois plus lents")
	# Recharge épuisé : 30 / s ; 50 atteint après 0,4 + 1,67 s.
	_run(e, PlayerEnergy.REGEN_DELAY + 1.0, false)
	assert_near(e.value, 30.0, 0.8, "recharge 25 % plus lente")
	assert_true(e.exhausted, "toujours épuisé sous 50")
	assert_false(e.can_start_sprint(), "pas de course sous 50 épuisé, même au-dessus du seuil de relance")
	_run(e, 0.6, false)
	assert_true(e.exhausted, "49 : encore épuisé")
	_run(e, 0.1, false)
	assert_false(e.exhausted, "fin de l'épuisement à 50")
	assert_true(e.value >= 50.0)
	assert_true(e.can_start_sprint())
	assert_eq(e.jump_velocity_mult(), 1.0)
	assert_eq(e.melee_time_mult(), 1.0)
	# Hors épuisement : recharge normale.
	var v := e.value
	_run(e, 0.5, false)
	assert_near(e.value, v + 20.0, 0.8, "40 / s une fois reposé")


func test_seuil_de_relance() -> void:
	var e := PlayerEnergy.new()
	e.spend(100.0 - PlayerEnergy.SPRINT_RESTART_MIN + 0.5)
	assert_false(e.exhausted)
	assert_false(e.can_start_sprint(), "moins de 12,5 : pas de départ")
	e.value = PlayerEnergy.SPRINT_RESTART_MIN
	assert_true(e.can_start_sprint(), "12,5 : départ possible")


func test_saut_et_couteau() -> void:
	var e := PlayerEnergy.new()
	e.spend(PlayerEnergy.JUMP_COST)
	assert_eq(e.value, 90.0, "10 par saut")
	e.spend(KnifeDB.energy_cost("knife"))
	assert_eq(e.value, 82.0, "couteau : 8")
	e.spend(KnifeDB.energy_cost("bowie"))
	assert_eq(e.value, 72.0, "couteau de chasse : 10")
	assert_eq(KnifeDB.energy_cost("inconnu"), 8.0, "id inconnu : couteau de départ")


func test_depense_plus_grande_que_le_reste() -> void:
	var e := PlayerEnergy.new()
	e.value = 4.0
	e.spend(PlayerEnergy.JUMP_COST)
	assert_eq(e.value, 0.0, "l'action se fait, l'énergie tombe à 0")
	assert_true(e.exhausted)
	e.spend(-5.0)
	e.spend(0.0)
	assert_eq(e.value, 0.0, "dépense nulle ou négative ignorée")
	assert_true(e.exhausted)


func test_bonus_max() -> void:
	var e := PlayerEnergy.new()
	e.set_bonus_max(4.0 * PlayerEnergy.SPRINT_COST)
	assert_eq(e.max_value, 200.0)
	assert_eq(e.value, 100.0, "le bonus ne remplit pas")
	assert_near(e.ratio(), 0.5, 0.0001)
	_run(e, 3.0, false)
	assert_near(e.value, 200.0, 0.001, "recharge jusqu'au nouveau max")
	_run(e, 8.05, true)
	assert_near(e.value, 0.0, 0.01, "8 s de course avec le bonus")
	e.value = 150.0
	e.set_bonus_max(0.0)
	assert_eq(e.max_value, 100.0)
	assert_eq(e.value, 100.0, "bonus retiré : énergie bornée au max")
	e.set_bonus_max(-50.0)
	assert_eq(e.max_value, 100.0, "bonus négatif ignoré")


func test_ratio_borne() -> void:
	var e := PlayerEnergy.new()
	e.spend(25.0)
	assert_near(e.ratio(), 0.75, 0.0001)
	e.spend(500.0)
	assert_eq(e.ratio(), 0.0)


func test_delta_nul() -> void:
	var e := PlayerEnergy.new()
	e.spend(50.0)
	e.tick(0.0, true)
	e.tick(-1.0, false)
	assert_eq(e.value, 50.0)
