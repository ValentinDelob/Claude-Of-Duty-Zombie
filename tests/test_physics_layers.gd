extends TestCase
## Couches physiques du jeu (ARCHITECTURE.md, « Couches physiques ») : chaque
## usage a sa couche, aucune n'est partagée par erreur (ex. le rayon genou de
## MeshNav qui touchait les ragdolls quand LOW_LAYER valait la couche 7).


func _layers() -> Dictionary:
	return {
		"monde": 1,
		"joueurs": 1 << 1,
		"zombies": Zombie.BODY_LAYER,
		"hitboxes": Zombie.HITBOX_LAYER,
		"fenêtres": Barricade.BARRIER_LAYER,
		"ragdolls": ZombieRagdoll.LAYER,
		"obstacles bas": MeshNav.LOW_LAYER,
	}


func test_one_bit_each_and_distinct() -> void:
	var seen := {}
	var L := _layers()
	for name: String in L:
		var bit: int = L[name]
		assert_true(bit > 0 and (bit & (bit - 1)) == 0, "%s : un seul bit (%d)" % [name, bit])
		assert_false(seen.has(bit), "%s partage la couche de %s" % [name, seen.get(bit, "")])
		seen[bit] = name
	assert_eq(WeaponController.HITBOX_LAYER, Zombie.HITBOX_LAYER, "une seule couche de hitboxes")


func test_low_ray_ignores_ragdolls_and_actors() -> void:
	var low := MeshNav.LOW_LAYER
	for other in [ZombieRagdoll.LAYER, 1 << 1, Zombie.BODY_LAYER, Zombie.HITBOX_LAYER]:
		assert_eq(low & other, 0, "rayon genou sans la couche %d" % other)
	# Les corps qui tombent ne heurtent que le décor : jamais l'obstacle bas.
	assert_eq(ZombieRagdoll.LAYER & (1 | Barricade.BARRIER_LAYER), 0, "ragdolls hors de la ligne de vue")
