extends TestCase

## Ferraille (GAME_CONCEPT §4.8) : 10 par touche de balle ou de couteau,
## montant fixe par élimination quel que soit le coup ; un piège ne rapporte
## rien.
func test_hit_and_kill_values() -> void:
	assert_eq(PointsRules.KILL, 50)
	assert_eq(PointsRules.HIT, 10)
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.BULLET), 10, "touche de balle")
	assert_eq(PointsRules.for_damage(false, true, Combat.HitKind.BULLET), 10, "touche à la tête : pas de bonus")
	assert_eq(PointsRules.for_damage(true, false, Combat.HitKind.BULLET), 50, "le coup qui tue : élimination seule")
	assert_eq(PointsRules.for_damage(true, true, Combat.HitKind.BULLET), 50, "pas de bonus de tête")
	assert_eq(PointsRules.for_damage(true, false, Combat.HitKind.MELEE), 50, "pas de bonus de couteau")
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.MELEE), 10, "coup de couteau : une touche")
	assert_eq(PointsRules.for_damage(true, false, Combat.HitKind.SPLASH), 50)
	assert_eq(PointsRules.for_damage(true, false, Combat.HitKind.TRAP), 0)


## Touches qui ne rapportent rien : explosions, brûlure / effets spéciaux,
## pièges ; plafond de touches payées par zombie.
func test_hit_exclusions_and_cap() -> void:
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.SPLASH), 0, "explosion : rien")
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.SPECIAL), 0, "brûlure, téléporteur : rien")
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.TRAP), 0, "piège : rien")
	assert_eq(PointsRules.HIT_CAP, 10)
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.BULLET, PointsRules.HIT_CAP - 1), 10, "dernière touche payée")
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.BULLET, PointsRules.HIT_CAP), 0, "plafond atteint")
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.MELEE, 50), 0, "plafond : couteau aussi")
	assert_eq(PointsRules.for_damage(true, false, Combat.HitKind.BULLET, 99), 50, "l'élimination paie toujours")
	# Gain total plafonné pour un zombie aux PV énormes : 10 touches + l'élimination.
	var total := 0
	for i in 200:
		total += PointsRules.for_damage(false, false, Combat.HitKind.BULLET, i)
	total += PointsRules.for_damage(true, false, Combat.HitKind.BULLET, 200)
	assert_eq(total, PointsRules.HIT * PointsRules.HIT_CAP + PointsRules.KILL)


func test_session_spend() -> void:
	var s := Session.new()
	host.add_child(s)
	var pd := s.create(1)
	assert_eq(PlayerData.STARTING_POINTS, 0, "chacun part de 0 ferraille")
	assert_eq(pd.points, PlayerData.STARTING_POINTS)
	assert_false(s.try_spend(1, 1), "pas assez de ferraille")
	s.add_points(1, 500)
	assert_false(s.try_spend(1, 9999), "pas assez de ferraille")
	assert_eq(pd.points, 500)
	assert_true(s.try_spend(1, 500))
	assert_eq(pd.points, 0)
	s.add_points(1, 60)
	assert_eq(pd.points, 60)
	s.queue_free()


## Pénalités de BO1 (player_reduce_points) : 5 % à terre, 10 % aux autres
## quand un joueur succombe, arrondis à la dizaine supérieure.
func test_down_and_bleed_out_penalties() -> void:
	assert_eq(PointsRules.round_up_to_ten(0), 0)
	assert_eq(PointsRules.round_up_to_ten(41), 50)
	assert_eq(PointsRules.round_up_to_ten(50), 50)
	assert_eq(PointsRules.downed_loss(500), 30, "5 % de 500 = 25 -> 30")
	assert_eq(PointsRules.downed_loss(10000), 500)
	assert_eq(PointsRules.downed_loss(0), 0)
	assert_eq(PointsRules.downed_loss(5), 0, "5 % de 5 = 0")
	assert_eq(PointsRules.downed_loss(30), 10, "jamais plus que ce qu'on a (int(1.5) = 1 -> 10)")
	assert_eq(PointsRules.no_revive_loss(2345), 240, "10 % de 2345 = 234 -> 240")
