extends TestCase

func test_zombie_count_progression() -> void:
	assert_eq(RoundRules.zombie_count(1, 1), 6)
	assert_eq(RoundRules.zombie_count(5, 1), 24)
	assert_true(RoundRules.zombie_count(10, 1) > RoundRules.zombie_count(9, 1))
	assert_eq(RoundRules.zombie_count(1, 4), 15, "x2.5 à 4 joueurs")
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
		assert_true(RoundRules.max_alive(r, 4) <= RoundRules.MAX_ALIVE)
		assert_true(RoundRules.spawn_interval(r, 4) >= 0.35)


func test_speed_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 50:
		assert_eq(RoundRules.pick_speed(1, rng), 0, "manche 1 : marcheurs uniquement")
	var fast := 0
	for i in 200:
		if RoundRules.pick_speed(15, rng) >= 2:
			fast += 1
	assert_true(fast > 120, "manche 15 : majorité de coureurs (%d/200)" % fast)
