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
	# Ancien test : « manche 1 : surtout des marcheurs » (> 280/400, tirage de
	# BO1). Règle demandée par le joueur : que des marcheurs aux manches 1 à 3.
	var walkers := 0
	for i in 400:
		if RoundRules.pick_speed(1, rng) == RoundRules.WALK:
			walkers += 1
	assert_eq(walkers, 400, "manche 1 : que des marcheurs (%d/400)" % walkers)
	for i in 50:
		assert_true(RoundRules.pick_speed(5, rng) != RoundRules.WALK, "manche 5 : plus de marcheurs")
		assert_eq(RoundRules.pick_speed(10, rng), RoundRules.SPRINT, "manche 10 : tous sprinteurs")


## Demande du joueur : on ne court qu'à partir de la manche 4.
func test_walkers_only_until_round_3_runners_from_round_4() -> void:
	assert_eq(RoundRules.RUNNERS_FROM_ROUND, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for r in [1, 2, 3]:
		for i in 500:
			assert_eq(RoundRules.pick_speed(r, rng), RoundRules.WALK, "manche %d : marcheurs seulement" % r)
	var runners := 0
	for i in 500:
		if RoundRules.pick_speed(4, rng) != RoundRules.WALK:
			runners += 1
	assert_true(runners > 0 and runners < 500, "manche 4 : des coureurs apparaissent (%d/500), quelques marcheurs restent" % runners)
