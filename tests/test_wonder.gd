extends TestCase
## TONNERRE-7 (Thundergun de BO1) : statistiques, Pack-a-Punch, rareté et
## unicité dans la boîte, sélection du cône de l'onde de choc, projection.

const O := Vector3(0, 1.6, 0)
const FWD := Vector3(0, 0, -1)


func test_stats_bo1() -> void:
	var s := WeaponDB.stats("thunder")
	assert_eq(s.name, "TONNERRE-7")
	assert_eq(int(s.mag), 2, "2 coups par chargeur")
	assert_eq(int(s.reserve), 12, "réserve 12")
	assert_true(float(s.reload) >= 3.0, "rechargement long (%.1f s)" % s.reload)
	assert_near(float(s.blast_range), 20.0, 0.01)
	assert_near(float(s.blast_angle), 60.0, 0.01)
	assert_true(WeaponDB.is_unique("thunder"), "arme merveille unique")
	assert_false(WeaponDB.is_unique("ray"))
	assert_false(s.has("splash_radius") or s.has("self_damage"), "aucun dégât aux joueurs")
	assert_true(ResourceLoader.exists("res://assets/audio/thunder_fire.wav"))
	assert_true(ResourceLoader.exists("res://assets/audio/thunder_charge.wav"))
	assert_true(ResourceLoader.exists("res://assets/audio/zombie_fling.wav"))


func test_pack_a_punch() -> void:
	var s := WeaponDB.stats("thunder", true)
	assert_eq(s.name, "OURAGAN-77")
	assert_eq(int(s.mag), 4, "4 coups améliorée")
	assert_eq(int(s.reserve), 24, "réserve 24 améliorée")
	assert_true(s.has("blast_range"))


func test_box_rarity_and_uniqueness() -> void:
	var pool := WeaponDB.box_pool()
	assert_true(pool.has("thunder") and pool.thunder < pool.galil, "rare dans la boîte")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pd := PlayerData.new()
	pd.weapons = [WeaponDB.new_instance("m1911")]
	var seen := 0
	for i in 3000:
		if MysteryBox.pick_weapon(pd, rng) == "thunder":
			seen += 1
	assert_true(seen > 0, "tiré parfois (%d / 3000)" % seen)
	# Un autre joueur l'a déjà : plus jamais proposé.
	var again := 0
	for i in 3000:
		if MysteryBox.pick_weapon(pd, rng, {"thunder": true}) == "thunder":
			again += 1
	assert_eq(again, 0, "une seule à la fois dans la partie")


## Le propriétaire du TONNERRE-7 est à terre : l'arme est mise de côté
## (saved_weapons) mais reste à lui ; la boîte ne doit pas en donner une autre.
func test_unique_wonder_held_while_owner_downed() -> void:
	var owner := PlayerData.new(1)
	owner.saved_weapons = [WeaponDB.new_instance("m1911"), WeaponDB.new_instance("thunder")]
	owner.weapons = [WeaponDB.new_instance("m1911")]
	var other := PlayerData.new(2)
	other.weapons = [WeaponDB.new_instance("m1911")]
	var taken := MysteryBox.wonders_held([owner, other])
	assert_true(taken.has("thunder"), "arme mise de côté comptée")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 3000:
		if MysteryBox.pick_weapon(other, rng, taken) == "thunder":
			assert_true(false, "second TONNERRE-7 tiré")
			return


func test_cone_selection() -> void:
	var feet := func(x: float, z: float) -> Vector3: return Vector3(x, 0, z)
	# Devant, à diverses distances.
	assert_true(ThunderBlast.in_cone(O, FWD, feet.call(0.0, -5.0), 20.0, 60.0), "devant à 5 m")
	assert_true(ThunderBlast.in_cone(O, FWD, feet.call(0.0, -19.0), 20.0, 60.0), "devant à 19 m")
	assert_false(ThunderBlast.in_cone(O, FWD, feet.call(0.0, -21.0), 20.0, 60.0), "hors portée à 21 m")
	# Bord du cône : 25° dedans, 40° dehors.
	var a_in := deg_to_rad(25.0)
	var a_out := deg_to_rad(40.0)
	assert_true(ThunderBlast.in_cone(O, FWD, feet.call(sin(a_in) * 10.0, -cos(a_in) * 10.0), 20.0, 60.0), "25° : dans le cône")
	assert_false(ThunderBlast.in_cone(O, FWD, feet.call(sin(a_out) * 10.0, -cos(a_out) * 10.0), 20.0, 60.0), "40° : hors du cône")
	# Derrière et sur le côté.
	assert_false(ThunderBlast.in_cone(O, FWD, feet.call(0.0, 3.0), 20.0, 60.0), "derrière")
	assert_false(ThunderBlast.in_cone(O, FWD, feet.call(4.0, 0.0), 20.0, 60.0), "sur le côté")
	# Au contact, même si le buste est sous l'axe de visée.
	assert_true(ThunderBlast.in_cone(O, FWD, feet.call(0.2, -0.7), 20.0, 60.0), "au contact")
	assert_false(ThunderBlast.in_cone(O, FWD, feet.call(0.0, 0.7), 20.0, 60.0), "au contact mais derrière")
	# Sélection groupée.
	var positions := [feet.call(0, -3), feet.call(1, -8), feet.call(0, 4), feet.call(-2, -15), feet.call(12, -2)]
	var sel := ThunderBlast.select(O, FWD, positions, 20.0, 60.0)
	assert_eq(sel, [0, 1, 3] as Array[int], "sélection du cône")


func test_fling_velocity() -> void:
	var near := ThunderBlast.fling_velocity(O, FWD, Vector3(0, 0, -2), 20.0)
	var far := ThunderBlast.fling_velocity(O, FWD, Vector3(0, 0, -18), 20.0)
	assert_true(near.z < -10.0 and near.y > 3.0, "projeté vers l'arrière et vers le haut : %s" % near)
	assert_true(Vector2(near.x, near.z).length() > Vector2(far.x, far.z).length(), "plus violent de près")
	assert_true(far.z < 0.0 and far.y > 0.0, "au loin aussi : %s" % far)
	var side := ThunderBlast.fling_velocity(O, FWD, Vector3(3, 0, -5), 20.0)
	assert_true(side.x > 0.0, "zombie à droite projeté vers la droite")
	for j in [-1.0, 0.0, 1.0]:
		var v := ThunderBlast.fling_velocity(O, FWD, Vector3(0, 0, -6), 20.0, j)
		assert_true(v.z < -5.0, "variation bornée (%s)" % v)
