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
