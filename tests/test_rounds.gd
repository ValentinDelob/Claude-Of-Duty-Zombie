extends TestCase

func test_zombie_count_matches_black_ops() -> void:
	# Valeurs de référence BO1 en solo.
	var solo := {1: 6, 2: 8, 3: 13, 4: 18, 5: 24, 6: 27, 7: 28, 8: 28, 9: 29, 10: 33, 15: 44, 20: 60}
	for r in solo:
		assert_eq(RoundRules.zombie_count(r, 1), solo[r], "solo manche %d" % r)
	assert_eq(RoundRules.zombie_count(1, 4), 10, "4 joueurs manche 1")
	assert_eq(RoundRules.zombie_count(5, 4), 37, "4 joueurs manche 5")
	var prev := 0
	for r in range(1, 40):
		var c := RoundRules.zombie_count(r, 2)
		assert_true(c >= prev, "croissant (manche %d)" % r)
		prev = c


func test_health_formula() -> void:
	assert_eq(RoundRules.zombie_health(1), 150)
	assert_eq(RoundRules.zombie_health(2), 250)
	assert_eq(RoundRules.zombie_health(9), 950)
	assert_eq(RoundRules.zombie_health(10), 1045)
	assert_true(RoundRules.zombie_health(20) > 2500)


func test_limits() -> void:
	for r in range(1, 60):
		assert_eq(RoundRules.max_alive(r, 4), RoundRules.MAX_ALIVE)
		assert_true(RoundRules.spawn_interval(r, 4) >= RoundRules.SPAWN_DELAY_MIN)
	assert_eq(RoundRules.spawn_interval(1, 1), 2.0)
	assert_true(absf(RoundRules.spawn_interval(2, 1) - 1.9) < 0.001)


func test_speed_distribution() -> void:
	assert_eq(RoundRules.speed_for_roll(35), RoundRules.WALK)
	assert_eq(RoundRules.speed_for_roll(36), RoundRules.RUN)
	assert_eq(RoundRules.speed_for_roll(71), RoundRules.SPRINT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var walkers := 0
	for i in 400:
		if RoundRules.pick_speed(1, rng) == RoundRules.WALK:
			walkers += 1
	assert_true(walkers > 280, "manche 1 : surtout des marcheurs (%d/400)" % walkers)
	for i in 50:
		assert_true(RoundRules.pick_speed(5, rng) != RoundRules.WALK, "manche 5 : plus de marcheurs")
		assert_eq(RoundRules.pick_speed(10, rng), RoundRules.SPRINT, "manche 10 : tous sprinteurs")
