extends TestCase
## Démembrement et rampants (ZombieGibs) : règles BO1 de zombie_should_gib.

const B := Combat.HitKind.BULLET
const S := Combat.HitKind.SPLASH


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 4
	return r


func after_each() -> void:
	ZombieGibs.debug_chance = -1.0


func test_eligibility() -> void:
	# Moins de 10 % des PV d'avant le coup : rien.
	assert_false(ZombieGibs.eligible(B, "smg", 14, 150))
	assert_true(ZombieGibs.eligible(B, "smg", 15, 150))
	# Ni couteau, ni piège, ni coup spécial, ni pistol.
	assert_false(ZombieGibs.eligible(Combat.HitKind.MELEE, "", 150, 150))
	assert_false(ZombieGibs.eligible(Combat.HitKind.TRAP, "", 5000, 150))
	assert_false(ZombieGibs.eligible(Combat.HitKind.SPECIAL, "", 5000, 150))
	assert_false(ZombieGibs.eligible(B, "pistol", 150, 150))
	# Les explosions d'une arme de poing (M1911 amélioré) arrachent.
	assert_true(ZombieGibs.eligible(S, "pistol", 900, 150))
	# Manches hautes : le même coup ne suffit plus.
	assert_false(ZombieGibs.eligible(B, "rifle", 110, 2000))


func test_bullet_limbs() -> void:
	var r := _rng()
	# Tir au bras : l'avant-bras tombe, mort ou vif.
	assert_eq(ZombieGibs.decide(B, "smg", 70, 150, false, false, ZombieGibs.ARM_L, 0, r), ZombieGibs.ARM_L)
	assert_eq(ZombieGibs.decide(B, "smg", 200, 150, true, false, ZombieGibs.ARM_R, 0, r), ZombieGibs.ARM_R)
	# Déjà arraché : rien de nouveau.
	assert_eq(ZombieGibs.decide(B, "smg", 70, 150, false, false, ZombieGibs.ARM_L, ZombieGibs.ARM_L, r), 0)
	# Torse : rien ; tête : la tête éclate à la mort, pas de bit.
	assert_eq(ZombieGibs.decide(B, "rifle", 150, 150, true, false, ZombieGibs.TORSO, 0, r), 0)
	assert_eq(ZombieGibs.decide(B, "rifle", 400, 150, true, true, ZombieGibs.ARM_L, 0, r), 0)
	# Jambes mortel : le corps perd ses jambes.
	assert_eq(ZombieGibs.decide(B, "rifle", 200, 150, true, false, ZombieGibs.LEGS, 0, r), ZombieGibs.LEGS)
	# Jambes non mortel : « parfois » un rampant (chance forcée pour le test).
	ZombieGibs.debug_chance = 1.0
	assert_eq(ZombieGibs.decide(B, "rifle", 100, 150, false, false, ZombieGibs.LEGS, 0, r), ZombieGibs.LEGS)
	ZombieGibs.debug_chance = 0.0
	assert_eq(ZombieGibs.decide(B, "rifle", 100, 150, false, false, ZombieGibs.LEGS, 0, r), 0)


func test_bullet_crawler_rate() -> void:
	var r := _rng()
	var n := 0
	for i in 2000:
		if ZombieGibs.decide(B, "rifle", 100, 150, false, false, ZombieGibs.LEGS, 0, r) == ZombieGibs.LEGS:
			n += 1
	assert_near(n / 2000.0, ZombieGibs.CRAWL_BULLET_CHANCE, 0.04, "taux de rampants au tir")


func test_splash() -> void:
	var r := _rng()
	# Explosion non mortelle : rampant la plupart du temps.
	var crawl := 0
	for i in 1000:
		if ZombieGibs.decide(S, "", 500, 950, false, false, ZombieGibs.TORSO, 0, r) & ZombieGibs.LEGS:
			crawl += 1
	assert_near(crawl / 1000.0, ZombieGibs.CRAWL_SPLASH_CHANCE, 0.05, "taux de rampants à l'explosion")
	# Explosion mortelle : toujours au moins un membre.
	for i in 200:
		assert_true(ZombieGibs.decide(S, "", 1000, 150, true, false, ZombieGibs.TORSO, 0, r) != 0)
	# Rampant déjà sans jambes : pas de nouveau bit jambes.
	ZombieGibs.debug_chance = 1.0
	assert_eq(ZombieGibs.decide(S, "", 500, 950, false, false, ZombieGibs.TORSO, ZombieGibs.LEGS, r) & ZombieGibs.LEGS, 0)


func test_crawl_speed() -> void:
	assert_near(ZombieGibs.crawl_speed(0.0), 0.0)
	assert_near(ZombieGibs.crawl_speed(ZombieGibs.CRAWL_FALL_TIME), 0.0)
	assert_near(ZombieGibs.crawl_speed(5.0), ZombieGibs.CRAWL_SPEED)
	assert_true(ZombieGibs.CRAWL_SPEED < Zombie.SPEEDS[0], "plus lent qu'un marcheur")


## Membre touché calculé sur le squelette posé.
func test_limb_at() -> void:
	var z := Zombie.new()
	z.setup(9, 7, 0, true)
	host.add_child(z)
	z.global_position = Vector3(10, 0, 10)
	z.state = Zombie.State.IDLE  # debout (pas en train de sortir du sol)
	await wait_frames(2)
	var fore := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.forearm_l)
	assert_eq(ZombieGibs.limb_at(z, fore.origin), ZombieGibs.ARM_L)
	var fore_r := z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.forearm_r)
	assert_eq(ZombieGibs.limb_at(z, fore_r.origin), ZombieGibs.ARM_R)
	assert_eq(ZombieGibs.limb_at(z, Vector3(10, 0.45, 10.1)), ZombieGibs.LEGS)
	assert_eq(ZombieGibs.limb_at(z, Vector3(10, 1.2, 10.2)), ZombieGibs.TORSO)
	z.queue_free()


## Morceau arraché : mesh non skinné non vide.
func test_limb_mesh() -> void:
	var m := ZombieModel.limb_mesh(123, ["thigh_l", "shin_l"])
	assert_true(m.get_surface_count() == 1)
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	assert_true(verts.size() > 100, "jambe arrondie (%d sommets)" % verts.size())
	assert_true(arr[Mesh.ARRAY_BONES] == null, "pas de poids d'os")
	# Seulement la jambe (repère de la hanche) : ni torse, ni bras, ni tête.
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	assert_true(box.position.y > -1.0 and box.end.y < 0.2 and box.size.x < 0.3, "morceau limité à la jambe %s" % box)


