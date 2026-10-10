extends TestCase
## Emplacement de grenade (ThrowableRules) : grenades et PELUCHE LEURRE,
## dotation (2 au départ, +2 par manche, 4 au plus), mèche, dégâts de zone,
## rebonds, objets de la caisse au hasard (GAME_CONCEPT §4.12 bis).


func test_frag_reserve_per_round() -> void:
	var pd := PlayerData.new()
	assert_eq(pd.grenades, 2, "2 grenades au départ")
	assert_eq(pd.throwable, ThrowableRules.Kind.FRAG, "l'emplacement contient des grenades")
	assert_eq(ThrowableRules.frags_after_round(2), 4, "+2 à la manche suivante")
	assert_eq(ThrowableRules.frags_after_round(3), 4, "plafonné à 4")
	assert_eq(ThrowableRules.frags_after_round(4), 4, "déjà plein")
	assert_eq(ThrowableRules.frags_after_round(0), 2, "vide : +2")
	var g := 0
	for r in 5:
		g = ThrowableRules.frags_after_round(g)
	assert_eq(g, ThrowableRules.FRAG_MAX, "jamais plus de 4")


func test_slot_rules() -> void:
	assert_eq(ThrowableRules.SLOT_MAX, 4, "maximum porté : celui des grenades")
	assert_eq(ThrowableRules.FRAG_MAX, ThrowableRules.SLOT_MAX)
	assert_true(ThrowableRules.gets_free_frags(ThrowableRules.Kind.FRAG, 1), "grenades : dotation")
	assert_true(ThrowableRules.gets_free_frags(ThrowableRules.Kind.DECOY, 0), "vide : dotation")
	assert_false(ThrowableRules.gets_free_frags(ThrowableRules.Kind.DECOY, 2), "peluches : pas de grenades ajoutées")
	# Répliqués avec les statistiques du joueur.
	var pd := PlayerData.new()
	pd.throwable = ThrowableRules.Kind.DECOY
	pd.grenades = 3
	var copy := PlayerData.new()
	copy.apply_stats(pd.stats_dict())
	assert_eq(copy.throwable, ThrowableRules.Kind.DECOY)
	assert_eq(copy.grenades, 3)


func test_crate_items() -> void:
	var ids := []
	for it: Dictionary in ThrowableRules.CRATE_ITEMS:
		ids.append(it.id)
		assert_true(ThrowableRules.NAMES.has(int(it.kind)), "%s : sorte connue" % it.id)
		assert_true(float(it.weight) > 0.0, "%s : poids" % it.id)
	assert_eq(ids, ["frag", "decoy"], "grenade et peluche leurre")
	assert_true(ThrowableRules.crate_item("arme").is_empty(), "jamais une arme")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var count := {}
	for i in 2000:
		var id := ThrowableRules.pick_crate_item(rng)
		count[id] = count.get(id, 0) + 1
	assert_eq(count.size(), 2, "seulement des objets de la liste (%s)" % str(count))
	assert_true(count.get("frag", 0) > 800 and count.get("decoy", 0) > 800, "poids égaux (%s)" % str(count))
	assert_eq(MysteryBox.item_name("decoy"), ThrowableRules.kind_name(ThrowableRules.Kind.DECOY))


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
	assert_true(ThrowableRules.splash(ThrowableRules.DECOY_DAMAGE, ThrowableRules.DECOY_RADIUS, 2.0) > RoundRules.zombie_health(40),
		"la peluche leurre tue à toute manche")


func test_throw_and_bounce() -> void:
	var v := ThrowableRules.throw_velocity(ThrowableRules.Kind.FRAG, Vector3(0, 0, -2))
	assert_near(v.z, -ThrowableRules.FRAG_SPEED, 0.001, "direction de visée normalisée")
	assert_true(v.y > 0.0, "lancer en cloche")
	var m := ThrowableRules.throw_velocity(ThrowableRules.Kind.DECOY, Vector3.FORWARD)
	assert_true(m.length() < v.length(), "la peluche part moins vite")
	# Rebond sur un sol : la vitesse verticale s'inverse et s'amortit.
	var b := ThrowableRules.bounce(Vector3(4, -6, 0), Vector3.UP)
	assert_true(b.y > 0.0 and b.y < 6.0, "rebond amorti (%s)" % b)
	assert_true(b.x > 0.0 and b.x < 4.0, "glissement freiné")
	# Contre un mur.
	var w := ThrowableRules.bounce(Vector3(0, 0, -10), Vector3(0, 0, 1))
	assert_true(w.z > 0.0 and w.z < 10.0, "renvoyé par le mur")
	# S'éloignant déjà de la surface : inchangé.
	assert_eq(ThrowableRules.bounce(Vector3(0, 3, 0), Vector3.UP), Vector3(0, 3, 0))


func test_decoy_model() -> void:
	var m := Throwable.build_model(ThrowableRules.Kind.DECOY, false)
	assert_eq(String(m.name), "Decoy")
	assert_eq(m.get_child_count(), 1, "ours en peluche réduit")
	m.free()
