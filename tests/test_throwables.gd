extends TestCase
## Grenades et SINGE-TAMBOUR (ThrowableRules) : réserve BO1 (2 au départ,
## +2 par manche, 4 au plus), mèche, dégâts de zone, rebonds, boîte mystère.


func test_frag_reserve_per_round() -> void:
	var pd := PlayerData.new()
	assert_eq(pd.grenades, 2, "2 grenades au départ")
	assert_eq(ThrowableRules.frags_after_round(2), 4, "+2 à la manche suivante")
	assert_eq(ThrowableRules.frags_after_round(3), 4, "plafonné à 4")
	assert_eq(ThrowableRules.frags_after_round(4), 4, "déjà plein")
	assert_eq(ThrowableRules.frags_after_round(0), 2, "vide : +2")
	var g := 0
	for r in 5:
		g = ThrowableRules.frags_after_round(g)
	assert_eq(g, ThrowableRules.FRAG_MAX, "jamais plus de 4")


func test_wall_buy_rules() -> void:
	assert_eq(ThrowableRules.FRAG_WALL_COST, 250, "250 points au mur (Kino)")
	assert_true(ThrowableRules.can_buy_frags(0))
	assert_true(ThrowableRules.can_buy_frags(3))
	assert_false(ThrowableRules.can_buy_frags(4), "réserve pleine : rien à acheter")


func test_monkey_reserve() -> void:
	var pd := PlayerData.new()
	assert_false(pd.has_monkeys, "pas de singe au départ")
	assert_eq(pd.monkeys, 0)
	assert_eq(ThrowableRules.MONKEY_MAX, 3, "3 singes (boîte, MUNITIONS MAX)")
	# Répliqués avec les statistiques du joueur.
	pd.grenades = 1
	pd.monkeys = 2
	pd.has_monkeys = true
	var copy := PlayerData.new()
	copy.apply_stats(pd.stats_dict())
	assert_eq(copy.grenades, 1)
	assert_eq(copy.monkeys, 2)
	assert_true(copy.has_monkeys)


func test_fuse_and_splash() -> void:
	assert_near(ThrowableRules.fuse_left(10.0, 10.0), 4.0, 0.001, "mèche de 4 s au dégoupillage")
	assert_near(ThrowableRules.fuse_left(10.0, 13.0), 1.0, 0.001, "cuite 3 s : 1 s restante")
	assert_true(ThrowableRules.fuse_left(10.0, 14.1) < 0.0, "trop cuite : explose dans la main")
	var r := ThrowableRules.FRAG_RADIUS
	var dmg := ThrowableRules.FRAG_DAMAGE
	assert_eq(ThrowableRules.splash(dmg, r, 0.0), dmg, "plein centre")
	@warning_ignore("integer_division")
	assert_eq(ThrowableRules.splash(dmg, r, r), dmg / 2, "moitié au bord")
	assert_eq(ThrowableRules.splash(dmg, r, r + 0.1), 0, "rien au-delà")
	# Tue en un coup un zombie proche jusqu'à la manche 10 (BO1 : ~10-11).
	assert_true(ThrowableRules.splash(dmg, r, 1.0) >= RoundRules.zombie_health(11), "manche 11 tuée à 1 m")
	assert_true(ThrowableRules.splash(dmg, r, 1.0) < RoundRules.zombie_health(13), "plus à la manche 13")
	# Dégâts au lanceur réduits : jamais mortels depuis la pleine santé.
	assert_true(ThrowableRules.FRAG_SELF_DAMAGE < PlayerData.BASE_HEALTH, "dégâts à soi réduits")
	assert_true(ThrowableRules.splash(ThrowableRules.MONKEY_DAMAGE, ThrowableRules.MONKEY_RADIUS, 2.0) > RoundRules.zombie_health(40),
		"le singe tue à toute manche")


func test_throw_and_bounce() -> void:
	var v := ThrowableRules.throw_velocity(ThrowableRules.Kind.FRAG, Vector3(0, 0, -2))
	assert_near(v.z, -ThrowableRules.FRAG_SPEED, 0.001, "direction de visée normalisée")
	assert_true(v.y > 0.0, "lancer en cloche")
	var m := ThrowableRules.throw_velocity(ThrowableRules.Kind.MONKEY, Vector3.FORWARD)
	assert_true(m.length() < v.length(), "le singe part moins vite")
	# Rebond sur un sol : la vitesse verticale s'inverse et s'amortit.
	var b := ThrowableRules.bounce(Vector3(4, -6, 0), Vector3.UP)
	assert_true(b.y > 0.0 and b.y < 6.0, "rebond amorti (%s)" % b)
	assert_true(b.x > 0.0 and b.x < 4.0, "glissement freiné")
	# Contre un mur.
	var w := ThrowableRules.bounce(Vector3(0, 0, -10), Vector3(0, 0, 1))
	assert_true(w.z > 0.0 and w.z < 10.0, "renvoyé par le mur")
	# S'éloignant déjà de la surface : inchangé.
	assert_eq(ThrowableRules.bounce(Vector3(0, 3, 0), Vector3.UP), Vector3(0, 3, 0))


func test_monkey_in_box() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pd := PlayerData.new()
	pd.weapons = [WeaponDB.new_instance("m1911")]
	var got := 0
	for i in 2000:
		if MysteryBox.pick_weapon(pd, rng) == ThrowableRules.MONKEY_ID:
			got += 1
	assert_true(got > 20, "le singe sort de la boîte (%d / 2000)" % got)
	pd.has_monkeys = true
	var again := 0
	for i in 500:
		if MysteryBox.pick_weapon(pd, rng) == ThrowableRules.MONKEY_ID:
			again += 1
	assert_eq(again, 0, "jamais si on en a déjà")
