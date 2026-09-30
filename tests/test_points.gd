extends TestCase

func test_hit_and_kill_values() -> void:
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.BULLET), 10)
	assert_eq(PointsRules.for_damage(true, false, Combat.HitKind.BULLET), 50)
	assert_eq(PointsRules.for_damage(true, true, Combat.HitKind.BULLET), 100)
	assert_eq(PointsRules.for_damage(true, false, Combat.HitKind.MELEE), 130)
	assert_eq(PointsRules.for_damage(false, false, Combat.HitKind.MELEE), 10)
	assert_eq(PointsRules.for_damage(true, false, Combat.HitKind.TRAP), 0)


func test_session_spend() -> void:
	var s := Session.new()
	host.add_child(s)
	var pd := s.create(1)
	assert_eq(pd.points, PlayerData.STARTING_POINTS)
	assert_false(s.try_spend(1, 9999), "pas assez de points")
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
