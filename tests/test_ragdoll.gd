extends TestCase
## Ragdoll des zombies tués (ZombieRagdoll) : impulsion selon l'arme, départ
## depuis la pose courante, couches de collision, plafond de ragdolls
## simulés, figement, démembrement, qualité BASSE, nettoyage.

var _floor: StaticBody3D
var _zs: Array[Zombie] = []
var _next_id := 900
var _quality := 0


func before_each() -> void:
	ZombieRagdoll.debug_cap = 8
	_quality = Settings.quality
	_floor = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position.y = -0.5
	_floor.add_child(cs)
	host.add_child(_floor)


func after_each() -> void:
	ZombieRagdoll.debug_cap = -1
	Settings.quality = _quality
	for z in _zs:
		if is_instance_valid(z):
			z.free()
	_zs.clear()
	_floor.free()


func _zombie(pos: Vector3, yaw := 0.0) -> Zombie:
	var z := Zombie.new()
	z.setup(_next_id, _next_id * 37, 0, false)
	_next_id += 1
	z.yaw = yaw
	host.add_child(z)
	z.global_position = pos
	z.rotation.y = yaw
	z.state = Zombie.State.CHASE
	_zs.append(z)
	return z


## Point le plus bas et plus haut des corps simulés.
func _span(r: ZombieRagdoll) -> Vector2:
	var lo := INF
	var hi := -INF
	for pb: PhysicalBone3D in r.bodies.values():
		lo = minf(lo, pb.global_position.y)
		hi = maxf(hi, pb.global_position.y)
	return Vector2(lo, hi)


func test_impulse_by_weapon() -> void:
	var fwd := Vector3(0, 0, -1)
	var B := Combat.HitKind.BULLET
	var pistol := ZombieRagdoll.kill_impulse(B, "m1911", false, fwd)
	var rifle := ZombieRagdoll.kill_impulse(B, "m14", false, fwd)
	var shotgun := ZombieRagdoll.kill_impulse(B, "olympia", false, fwd)
	var sniper := ZombieRagdoll.kill_impulse(B, "l96a1", false, fwd)
	var head := ZombieRagdoll.kill_impulse(B, "m14", true, fwd)
	assert_true(pistol.length() < rifle.length() and rifle.length() < sniper.length(), "pistolet < fusil < précision")
	assert_true(shotgun.length() > rifle.length() and shotgun.y > 0.0, "fusil à pompe : fort, un peu soulevé")
	assert_true(head.length() > rifle.length(), "tir à la tête plus violent")
	assert_true(rifle.normalized().dot(fwd) > 0.99, "dans le sens du tir")
	# Couteau : horizontal ; explosion : soufflé vers le haut et loin du centre.
	var knife := ZombieRagdoll.kill_impulse(Combat.HitKind.MELEE, "", false, Vector3(1, 0, 0))
	assert_true(knife.x > 2.0 and knife.y < 1.0, "couteau : poussée horizontale")
	var boom := ZombieRagdoll.kill_impulse(Combat.HitKind.SPLASH, "", false, Vector3(0.6, -0.8, 0).normalized())
	assert_true(boom.y > 3.0 and boom.x > 4.0, "explosion : soufflé vers le haut, loin du centre (%s)" % boom)
	assert_true(boom.length() > shotgun.length(), "explosion plus forte qu'une balle")
	# Piège électrique, nuke : le corps s'effondre presque sur place.
	assert_true(ZombieRagdoll.kill_impulse(Combat.HitKind.TRAP, "", false, Vector3.UP).length() < 1.0, "piège : effondrement")
	assert_true(ZombieRagdoll.kill_impulse(Combat.HitKind.SPECIAL, "", false, fwd).length() < 2.0, "nuke : poussée légère")
	# Variation bornée et longueur plafonnée.
	var j := ZombieRagdoll.kill_impulse(B, "m14", false, fwd, 1.0)
	assert_true(j.length() > rifle.length() and j.length() < rifle.length() * 1.2, "variation du serveur bornée")
	for kind in [B, Combat.HitKind.MELEE, Combat.HitKind.SPLASH, Combat.HitKind.TRAP, Combat.HitKind.SPECIAL]:
		assert_true(ZombieRagdoll.kill_impulse(kind, "law", true, fwd * 50.0, 1.0).length() <= ZombieRagdoll.MAX_IMPULSE, "plafond (%d)" % kind)


func test_start_from_current_pose() -> void:
	var z := _zombie(Vector3(0, 0, 0))
	# Sol déjà dans l'espace physique (en partie, la carte est là bien avant).
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	# Bras tendus vers l'avant (pose de marche) au moment de la mort.
	z.skel.set_bone_pose_rotation(z.bones.arm_l, Quaternion.from_euler(Vector3(-1.3, 0, 0)))
	z.skel.set_bone_pose_rotation(z.bones.forearm_l, Quaternion.from_euler(Vector3(-0.3, 0, 0)))
	var hand_before := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.forearm_l).origin
	z.die(Vector3(0, 0, -3.0), false)
	assert_true(z.ragdolled and is_instance_valid(z.ragdoll), "parti en ragdoll")
	assert_eq(z.ragdoll.bodies.size(), ZombieRagdoll.PARTS.size(), "11 parties simulées")
	assert_true(z.ragdoll.is_simulating_physics(), "simulation lancée")
	# Le corps de l'avant-bras part de l'avant-bras posé (pas de saut).
	var pb: PhysicalBone3D = z.ragdoll.bodies.forearm_l
	var bone_at := pb.global_transform * pb.body_offset.affine_inverse()
	assert_true(bone_at.origin.distance_to(hand_before) < 0.05, "départ de la pose courante (écart %.3f m)" % bone_at.origin.distance_to(hand_before))
	await wait_frames(3)
	var hand_now := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.forearm_l).origin
	assert_true(hand_now.distance_to(hand_before) < 0.15, "aucun saut à l'écran (%.3f m)" % hand_now.distance_to(hand_before))
	await wait_seconds(1.6)
	var r := z.ragdoll
	if is_instance_valid(r) and not r.frozen:
		var s := _span(r)
		assert_true(s.x > -0.05, "aucune partie sous le sol (%.3f)" % s.x)
		assert_true(s.y < 0.7, "corps tombé (plus haute partie à %.2f m)" % s.y)
	var hips := z.body_position()
	assert_true(hips.y > -0.05 and hips.y < 0.45, "bassin couché au sol (%.2f)" % hips.y)
	assert_true(Vector2(hips.x, hips.z).length() < 2.5, "corps pas envolé (%.2f m)" % Vector2(hips.x, hips.z).length())
	# Poussé vers -Z : il tombe de ce côté.
	assert_true(hips.z < 0.0, "tombé dans le sens du coup (z = %.2f)" % hips.z)


func test_collision_layers() -> void:
	var z := _zombie(Vector3(3, 0, 0))
	z.die(Vector3(0, 0, 2.0), false)
	assert_true(z.ragdolled)
	for pb: PhysicalBone3D in z.ragdoll.bodies.values():
		assert_eq(pb.collision_layer, ZombieRagdoll.LAYER, "couche ragdoll (%s)" % pb.bone_name)
		assert_eq(pb.collision_mask, 1, "ne heurte que le décor (%s)" % pb.bone_name)
	var L := ZombieRagdoll.LAYER
	# Ni joueurs, ni zombies, ni tirs, ni fenêtres ne voient cette couche.
	for mask in [1, 1 << 1, Zombie.BODY_LAYER, Zombie.HITBOX_LAYER, Barricade.BARRIER_LAYER, 1 << 5,
			1 | WeaponController.HITBOX_LAYER, 1 | (1 << 2) | Barricade.BARRIER_LAYER, Throwable.FLIGHT_MASK]:
		assert_eq(mask & L, 0, "masque %d sans la couche ragdoll" % mask)
	# Capsule et hitboxes du zombie mort coupées.
	assert_eq(z.collision_layer, 0)
	assert_eq(z.hit_body.collision_layer, 0)


func test_cap_and_eviction() -> void:
	ZombieRagdoll.debug_cap = 2
	var a := _zombie(Vector3(-4, 0, 4))
	var b := _zombie(Vector3(0, 0, 4))
	var c := _zombie(Vector3(4, 0, 4))
	a.die(Vector3(0, 0, 2), false)
	b.die(Vector3(0, 0, 2), false)
	c.die(Vector3(0, 0, 2), false)
	assert_true(a.ragdolled and b.ragdolled, "deux ragdolls")
	# Les deux viennent de partir : le troisième tombe à l'ancienne.
	assert_false(c.ragdolled, "plafond atteint : chute procédurale")
	assert_eq(ZombieRagdoll.active_count(), 2)
	await wait_seconds(ZombieRagdoll.EVICT_AGE + 0.2)
	var d := _zombie(Vector3(8, 0, 4))
	d.die(Vector3(0, 0, 2), false)
	assert_true(d.ragdolled, "le plus ancien est figé pour faire place")
	assert_true(ZombieRagdoll.active_count() <= 2, "jamais plus que le plafond (%d)" % ZombieRagdoll.active_count())
	assert_true(not is_instance_valid(a.ragdoll) or a.ragdoll.frozen, "le plus ancien (a) est figé")


func test_freeze_keeps_pose() -> void:
	var z := _zombie(Vector3(-6, 0, -4))
	z.die(Vector3(2.5, 0, 0), false)
	var r := z.ragdoll
	var t := 0.0
	while is_instance_valid(r) and not r.frozen and t < ZombieRagdoll.MAX_SIM_TIME + 0.5:
		await host.get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	assert_true(t <= ZombieRagdoll.MAX_SIM_TIME + 0.1, "figé au plus tard après %.1f s (%.2f s)" % [ZombieRagdoll.MAX_SIM_TIME, t])
	await wait_frames(3)
	assert_true(z.skel.get_node_or_null("Ragdoll") == null, "corps physiques retirés")
	assert_eq(ZombieRagdoll.active_count(), 0)
	# La pose recopiée garde le corps couché au même endroit.
	var hips := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.hips).origin
	assert_true(hips.distance_to(z.ragdoll_rest) < 0.25, "pose figée = dernière pose simulée (%.3f m)" % hips.distance_to(z.ragdoll_rest))
	assert_true(hips.y < 0.45, "figé couché (%.2f)" % hips.y)
	# Le corps reste immobile ensuite (plus aucune écriture d'os).
	await wait_frames(5)
	var hips2 := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.hips).origin
	assert_true(hips2.distance_to(hips) < 0.001, "immobile après figement")


func test_headshot_and_gibs() -> void:
	var z := _zombie(Vector3(6, 0, -4))
	ZombieGibs.apply(z, ZombieGibs.LEGS | ZombieGibs.ARM_L, Vector3.FORWARD, true)
	z.die(Vector3(0, 0, -3), true)
	assert_true(z.ragdolled)
	var bodies := z.ragdoll.bodies
	assert_true(bodies.has("neck") and bodies.has("spine") and bodies.has("arm_r"), "buste, cou, bras restant")
	for bone in ["thigh_l", "shin_l", "thigh_r", "shin_r", "forearm_l"]:
		assert_false(bodies.has(bone), "membre arraché sans corps (%s)" % bone)
	await wait_frames(10)
	assert_true(z.skel.get_bone_pose_scale(z.bones.head).x < 0.01, "tête éclatée le reste")


func test_low_quality_and_cleanup() -> void:
	ZombieRagdoll.debug_cap = -1
	Settings.quality = Settings.Quality.LOW
	assert_eq(ZombieRagdoll.cap(), 0)
	var z := _zombie(Vector3(0, 0, 8))
	z.die(Vector3(0, 0, 2), false)
	assert_false(z.ragdolled, "BASSE : chute procédurale")
	Settings.quality = Settings.Quality.MEDIUM
	assert_true(ZombieRagdoll.cap() > 0)
	var f := _zombie(Vector3(2, 0, 8))
	f.die_flung(Vector3(0, 4, 12))
	assert_true(f.ragdolled and f.is_flung(), "TONNERRE-7 : ragdoll projeté")
	assert_true(f.get_node_or_null("Fling") == null, "pas de vol procédural en plus")
	await wait_seconds(0.3)
	assert_true(f.body_position().z > 2.0, "corps soufflé (%.2f m)" % f.body_position().z)
	# Zombie libéré (fin de dissolution, fin de manche) : le ragdoll avec lui.
	f.free()
	assert_eq(ZombieRagdoll.active_count(), 0)
