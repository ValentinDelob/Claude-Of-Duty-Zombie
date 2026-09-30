extends TestCase
## Corrections de robustesse (docs/REFACTORING_PLAN.md § 3) testables sans
## partie : cas limites qui faisaient planter ou tromper le serveur.


func test_spawn_for_slot_without_spawn_points() -> void:
	var none: Array[Vector3] = []
	assert_eq(Game.spawn_for_slot(none, 0), Game.FALLBACK_SPAWN, "carte sans point d'apparition : repli, pas de division par zéro")
	assert_eq(Game.spawn_for_slot(none, 3), Game.FALLBACK_SPAWN)


func test_spawn_for_slot_wraps_and_never_negative() -> void:
	var two: Array[Vector3] = [Vector3(1, 0, 0), Vector3(2, 0, 0)]
	assert_eq(Game.spawn_for_slot(two, 0), Vector3(1, 0, 0))
	assert_eq(Game.spawn_for_slot(two, 1), Vector3(2, 0, 0))
	assert_eq(Game.spawn_for_slot(two, 3), Vector3(2, 0, 0), "places au-delà du nombre de points : partagées")
	assert_eq(Game.spawn_for_slot(two, -1), Vector3(2, 0, 0), "place négative : modulo positif")
