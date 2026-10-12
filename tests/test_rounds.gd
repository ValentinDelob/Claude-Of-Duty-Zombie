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
	# PV linéaires (GAME_CONCEPT §4.3) : plus de +10 % après la manche 9.
	assert_eq(RoundRules.zombie_health(10), 1050)
	assert_eq(RoundRules.zombie_health(20), 2050)
	# 150 + 100 × 49 = 5 050 (GAME_CONCEPT cite 4 950 : coquille, la formule fait foi).
	assert_eq(RoundRules.zombie_health(50), 5050)


func test_limits() -> void:
	for r in range(1, 60):
		assert_eq(RoundRules.max_alive(r, 4), RoundRules.MAX_ALIVE)
		assert_true(RoundRules.spawn_interval(r, 4) >= RoundRules.SPAWN_DELAY_MIN)
	assert_eq(RoundRules.spawn_interval(1, 1), 2.0)
	assert_true(absf(RoundRules.spawn_interval(2, 1) - 1.9) < 0.001)


## Course progressive (demande du joueur) : part des coureurs 20 % à la
## manche 4, +20 % par manche, tous à partir de la 8 ; sprinteurs au
## calendrier de BO1 (dès la 5, tous à partir de la 9), jamais plus que les
## coureurs.
func test_progressive_running_curve() -> void:
	var share := {1: 0.0, 3: 0.0, 4: 0.2, 5: 0.4, 6: 0.6, 7: 0.8, 8: 1.0, 20: 1.0}
	for r in share:
		assert_near(RoundRules.run_share(r), share[r], 0.001, "part des coureurs manche %d" % r)
	var sprint := {3: 0.0, 4: 0.0, 5: 5.0 / 36.0, 6: 13.0 / 36.0, 7: 21.0 / 36.0, 8: 29.0 / 36.0, 9: 1.0, 30: 1.0}
	for r in sprint:
		assert_near(RoundRules.sprint_share(r), sprint[r], 0.001, "part des sprinteurs manche %d" % r)
	for r in range(1, 40):
		assert_true(RoundRules.sprint_share(r) <= RoundRules.run_share(r) + 1e-6, "sprinteurs <= coureurs (manche %d)" % r)
		assert_true(RoundRules.run_share(r + 1) >= RoundRules.run_share(r), "jamais moins de coureurs ensuite")
	assert_eq(RoundRules.speed_for_share(4, 0.19), RoundRules.RUN)
	assert_eq(RoundRules.speed_for_share(4, 0.21), RoundRules.WALK)
	assert_eq(RoundRules.speed_for_share(7, 0.99), RoundRules.WALK, "manche 7 : il reste des marcheurs")
	assert_eq(RoundRules.speed_for_share(8, 0.99), RoundRules.RUN, "manche 8 : plus aucun marcheur")
	assert_eq(RoundRules.speed_for_share(9, 0.99), RoundRules.SPRINT)


func test_speed_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var counts := {}
	for r in [4, 5, 6, 7]:
		var fast := 0
		for i in 2000:
			if RoundRules.pick_speed(r, rng) != RoundRules.WALK:
				fast += 1
		counts[r] = fast
		assert_near(fast / 2000.0, RoundRules.run_share(r), 0.05, "manche %d : %d/2000 coureurs" % [r, fast])
	assert_true(counts[4] < counts[5] and counts[5] < counts[6] and counts[6] < counts[7], "part croissante %s" % counts)
	for i in 300:
		assert_true(RoundRules.pick_speed(8, rng) != RoundRules.WALK, "manche 8 : tous courent")
		assert_eq(RoundRules.pick_speed(10, rng), RoundRules.SPRINT, "manche 10 : tous sprinteurs")
	# Même graine, mêmes vitesses (générateur de la partie, tiré par l'hôte).
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	for i in 100:
		assert_eq(RoundRules.pick_speed(5, a), RoundRules.pick_speed(5, b))


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
	assert_true(runners > 50 and runners < 150, "manche 4 : ~20 %% de coureurs (%d/500), surtout des marcheurs" % runners)
