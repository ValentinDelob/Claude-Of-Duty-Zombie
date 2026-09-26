extends TestCase
## Règles des manches de chiens de l'enfer (BO1, _zombiemode_dogs.gsc).


func test_first_dog_round_between_5_and_7() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := {}
	for i in 300:
		var r := DogRules.first_dog_round(rng)
		assert_true(r >= 5 and r <= 7, "première manche de chiens : %d" % r)
		seen[r] = true
	assert_eq(seen.size(), 3, "5, 6 et 7 sont tous possibles")


func test_next_dog_round_every_4_or_5() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seen := {}
	for i in 300:
		var gap := DogRules.next_dog_round(6, rng) - 6
		assert_true(gap == 4 or gap == 5, "écart %d" % gap)
		seen[gap] = true
	assert_eq(seen.size(), 2, "+4 et +5 sont tous deux tirés")


func test_dog_count() -> void:
	assert_eq(DogRules.dog_count(1, 1), 6, "solo, 1re manche de chiens")
	assert_eq(DogRules.dog_count(1, 2), 6, "solo, 2e")
	assert_eq(DogRules.dog_count(1, 3), 8, "solo, 3e : 8 par joueur")
	assert_eq(DogRules.dog_count(2, 1), 12)
	assert_eq(DogRules.dog_count(4, 1), 24)
	assert_eq(DogRules.dog_count(4, 5), 24, "plafond de 24")
	assert_eq(DogRules.dog_count(8, 1), 24, "plafond de 24")
	assert_eq(DogRules.dog_count(0, 1), 6, "au moins un joueur")


func test_max_alive_two_per_player() -> void:
	assert_eq(DogRules.max_alive(1), 2)
	assert_eq(DogRules.max_alive(3), 6)
	assert_eq(DogRules.max_alive(0), 2)


func test_dog_health() -> void:
	assert_eq(DogRules.dog_health(1), 400)
	assert_eq(DogRules.dog_health(2), 900)
	assert_eq(DogRules.dog_health(3), 1300)
	assert_eq(DogRules.dog_health(4), 1600)
	assert_eq(DogRules.dog_health(9), 1600, "plafond de 1600")


func test_spawn_wait() -> void:
	assert_near(DogRules.spawn_wait(1, 0, 6), 3.0)
	assert_near(DogRules.spawn_wait(1, 3, 6), 2.5)
	assert_near(DogRules.spawn_wait(2, 0, 6), 2.5)
	assert_near(DogRules.spawn_wait(3, 0, 8), 2.0)
	assert_near(DogRules.spawn_wait(7, 4, 8), 1.0)
	assert_true(DogRules.spawn_wait(4, 8, 8) > 0.0)


func test_favorite_enemy_is_least_hunted() -> void:
	assert_eq(DogRules.favorite_index([2, 0, 1]), 1)
	assert_eq(DogRules.favorite_index([1, 1]), 0, "égalité : le premier")
	assert_eq(DogRules.favorite_index([]), -1)


func test_hellhound_uses_zombie_channel() -> void:
	# Même encodage d'instantané que les zombies.
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	var d := Hellhound.new()
	d.setup(7, 3, 3, true)
	mgr.add_child(d)
	mgr.zombies[7] = d
	mgr.alive.append(d)
	d.global_position = Vector3(5.0, 0.0, 9.0)
	d.state = Zombie.State.CHASE
	var buf := mgr.build_snapshot()
	assert_eq(buf.size(), 2 + ZombieManager.BYTES_PER_ZOMBIE)
	assert_eq(buf.decode_u16(2), 7)
	assert_true(d.speed_mult * Zombie.SPEEDS[3] > 6.0, "course rapide")
	assert_true(d.hit_head != null and d.hit_body != null, "hitboxes")
	mgr.queue_free()
