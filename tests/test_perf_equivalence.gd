extends TestCase
## Optimisations CPU (docs/REFACTORING_PLAN.md §5, R2 à R9) : chaque fonction
## réécrite donne EXACTEMENT le résultat de l'ancienne logique (recopiée ici
## comme référence) sur des entrées tirées au hasard.


# --------------------------------------------------------------------------
# Monde physique de test : sol, marches et murs (couche 1)
# --------------------------------------------------------------------------

func _box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = center


## Sol de 24 x 24 m, une estrade, deux marches et un mur percé d'une porte.
func _world() -> Node3D:
	var w := Node3D.new()
	host.add_child(w)
	_box(w, Vector3(0, -0.25, 0), Vector3(24, 0.5, 24))
	_box(w, Vector3(5, 0.25, 5), Vector3(4, 0.5, 4))
	_box(w, Vector3(-5, 0.1, 4), Vector3(2, 0.2, 2))
	_box(w, Vector3(-5, 0.2, 6), Vector3(2, 0.4, 2))
	_box(w, Vector3(-3, 1.25, 0), Vector3(8, 2.5, 0.3))
	_box(w, Vector3(6, 1.25, 0), Vector3(6, 2.5, 0.3))
	return w


func _physics_frames(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


func _ray_y(w: Node3D, from: Vector3, to: Vector3, fallback: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else fallback


# --------------------------------------------------------------------------
# R2 : _follow_floor (requête de rayon gardée par zombie)
# --------------------------------------------------------------------------

func test_follow_floor_matches_fresh_ray() -> void:
	var w := _world()
	var z := Zombie.new()
	z.setup(1, 3, 0, true)
	w.add_child(z)
	z.set_physics_process(false)
	await _physics_frames(2)
	seed(11)
	var diffs := 0
	for i in 300:
		var start := Vector3(randf_range(-9, 9), randf_range(-0.2, 0.6), randf_range(-9, 9))
		z.global_position = start
		z.velocity = Vector3(randf_range(-2, 2), 0, 1.0)
		var want := _ray_y(w, start + Vector3.UP * 0.9, start + Vector3.DOWN * 1.1, start.y)
		z._follow_floor()
		if z.global_position.y != want:
			diffs += 1
	assert_eq(diffs, 0, "sol suivi identique à un rayon neuf")
	# Immobile : rien ne bouge.
	z.global_position = Vector3(5, 3, 5)
	z.velocity = Vector3.ZERO
	z._follow_floor()
	assert_eq(z.global_position.y, 3.0)
	w.queue_free()
