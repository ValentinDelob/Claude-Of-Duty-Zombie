extends TestCase
## Encodage / décodage des instantanés de zombies.

func test_snapshot_roundtrip() -> void:
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	var z := Zombie.new()
	z.setup(42, 7, 2, true)
	mgr.add_child(z)
	mgr.zombies[42] = z
	z.global_position = Vector3(12.34, -0.5, 56.78)
	z.yaw = 1.5
	z.state = Zombie.State.CHASE
	var buf := mgr.build_snapshot()
	assert_eq(buf.size(), 2 + ZombieManager.BYTES_PER_ZOMBIE)

	# Côté client : une marionnette reçoit l'instantané.
	var mgr2 := ZombieManager.new()
	host.add_child(mgr2)
	var z2 := Zombie.new()
	z2.setup(42, 7, 0, false)
	mgr2.add_child(z2)
	mgr2.zombies[42] = z2
	mgr2.apply_snapshot(buf)
	assert_eq(z2._snapshots.size(), 1)
	var snap: Array = z2._snapshots[0]
	assert_true(snap[1].distance_to(Vector3(12.34, -0.5, 56.78)) < 0.02, "position %s" % snap[1])
	assert_near(snap[2], 1.5, 0.03, "yaw")
	var code: int = snap[3]
	assert_eq(code & 7, Zombie.State.CHASE)
	assert_eq((code >> 3) & 3, 2)
	mgr.queue_free()
	mgr2.queue_free()


func test_truncated_snapshot_ignored() -> void:
	var mgr := ZombieManager.new()
	var buf := PackedByteArray([5, 0, 1, 2])
	mgr.apply_snapshot(buf)  # ne doit pas planter
	assert_true(true)
	mgr.free()
