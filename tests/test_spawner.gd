extends TestCase
## Recyclage des zombies égarés (Spawner) : table du temps passé loin des
## joueurs.


func _zombie(zid: int) -> Zombie:
	var z := Zombie.new()
	z.setup(zid, 0, 0, true)
	return z


## Un zombie tué loin des joueurs laissait son temps dans la table : elle
## grossissait toute la partie, et un futur zombie au même identifiant
## (recyclés après 65000) en héritait, recyclé trop tôt.
func test_far_time_forgets_zombies_no_longer_alive() -> void:
	var a := _zombie(3)
	var b := _zombie(8)
	var far := {3: 12.0, 8: 5.0, 42: 17.5}
	var alive: Array[Zombie] = [a, b]
	Spawner.prune_far_time(far, alive)
	assert_eq(far, {3: 12.0, 8: 5.0}, "zombie 42 disparu : oublié ; les vivants gardent leur temps")
	alive = [b]
	Spawner.prune_far_time(far, alive)
	assert_eq(far, {8: 5.0}, "zombie 3 tué : oublié")
	alive = []
	Spawner.prune_far_time(far, alive)
	assert_true(far.is_empty(), "plus aucun zombie : table vide")
	a.free()
	b.free()


## Filet de BO1 (round_spawn_failsafe) : 30 s sans bouger, 40 s pour un
## rampant (plus lent).
func test_failsafe_after_30_seconds_40_for_crawlers() -> void:
	assert_false(Spawner.failsafe_due(100.0, 129.0, false), "29 s : encore là")
	assert_true(Spawner.failsafe_due(100.0, 130.0, false), "30 s : retiré")
	assert_false(Spawner.failsafe_due(100.0, 135.0, true), "rampant à 35 s : encore là")
	assert_true(Spawner.failsafe_due(100.0, 140.0, true), "rampant à 40 s : retiré")


## Deux zombies apparus au même point se superposaient exactement (non
## solides pendant l'émergence) et restaient ensuite bloqués l'un dans
## l'autre toute la manche (soak BUNKER K-7) : un point occupé est sauté.
func test_spawn_point_occupied_by_a_zombie_on_it() -> void:
	var taken := PackedVector3Array([Vector3(48.5, 0.0, 10.5), Vector3(10.0, 3.5, 4.0)])
	assert_true(Spawner.occupied(Vector3(48.5, 0.0, 10.5), taken), "zombie pile sur le point")
	assert_true(Spawner.occupied(Vector3(48.9, 0.0, 10.2), taken), "zombie à 0,5 m : occupé")
	assert_false(Spawner.occupied(Vector3(49.5, 0.0, 10.5), taken), "zombie à 1 m : libre")
	assert_false(Spawner.occupied(Vector3(10.0, 0.0, 4.0), taken), "zombie à l'étage au-dessus : libre")
	assert_false(Spawner.occupied(Vector3(1.0, 0.0, 1.0), PackedVector3Array()), "aucun zombie : libre")


## Derrière une fenêtre, le zombie posté à la place du milieu se tient à
## 0,78 m du point d'apparition : avec 0,8 m il bloquait toute la file
## (une seule fenêtre : un zombie à la fois). Seul un zombie au contact bloque.
func test_window_spawn_clearance() -> void:
	var spawn := Vector3(26.7, 0.0, 17.25)
	var tear := Vector3(25.92, 0.0, 17.25)
	var taken := PackedVector3Array([tear])
	assert_true(Spawner.occupied(spawn, taken), "règle générale (0,8 m) : occupé")
	assert_false(Spawner.occupied(spawn, taken, Spawner.WINDOW_SPAWN_CLEARANCE), "fenêtre : zombie à sa place, point libre")
	assert_true(Spawner.occupied(spawn, PackedVector3Array([spawn + Vector3(0.3, 0, 0)]), Spawner.WINDOW_SPAWN_CLEARANCE), "fenêtre : zombie sur le point, occupé")
	assert_near(Spawner.WINDOW_SPAWN_CLEARANCE, 2.0 * Zombie.SHOULDER_RADIUS, 0.0001)
	assert_true(MapValidator.SPAWN_OUT - Barricade.TEAR_DIST > Spawner.WINDOW_SPAWN_CLEARANCE, "place du milieu hors du point d'apparition des cartes de l'éditeur")
