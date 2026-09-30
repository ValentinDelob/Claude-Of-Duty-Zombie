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
