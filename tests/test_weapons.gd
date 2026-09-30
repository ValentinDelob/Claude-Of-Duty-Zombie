extends TestCase
## Table d'armes (arsenal BO1) : champs requis, prix, Pack-a-Punch, boîte
## mystère, modèles procéduraux.

const WALL := {"olympia": 500, "m14": 500, "mp5k": 1000, "mpl": 1000, "pm63": 1000, "mp40": 1000,
	"ak74u": 1200, "m16": 1200, "stakeout": 1500}
const BOX := ["cz75", "python", "spectre", "galil", "famas", "commando", "aug", "g11", "fnfal", "hk21",
	"rpk", "spas12", "hs10", "dragunov", "l96a1", "china_lake", "law", "ray", "thunder"]


func test_every_weapon_has_required_fields() -> void:
	for id in WeaponDB.WEAPONS:
		for pap in [false, true]:
			var s := WeaponDB.stats(id, pap)
			for k in WeaponDB.REQUIRED:
				assert_true(s.has(k), "%s (pap %s) : champ %s" % [id, pap, k])
			assert_true(int(s.mag) > 0 and int(s.reserve) >= int(s.mag), "%s : chargeur/réserve" % id)
			assert_true(int(s.damage) > 0 and int(s.rpm) > 0 and float(s.reload) > 0.0, "%s : dégâts/cadence" % id)
			assert_true(WeaponDB.CLASSES.has(s["class"]), "%s : famille connue" % id)
			assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % s.sound), "%s : son %s" % [id, s.sound])
			if s.has("cycle"):
				assert_true(ResourceLoader.exists("res://assets/audio/%s.wav" % s.cycle), "%s : son du mécanisme" % id)
		assert_true(WeaponDB.WEAPONS[id].has("pap"), "%s : valeurs Pack-a-Punch" % id)


func test_starting_weapon_bo1() -> void:
	var s := WeaponDB.stats(WeaponDB.STARTING_WEAPON)
	assert_eq(WeaponDB.STARTING_WEAPON, "m1911")
	assert_eq(int(s.mag), 8)
	assert_eq(int(s.reserve), 80)
	# Manche 1 (150 PV) : environ un chargeur au corps, un coup de couteau.
	var shots := ceili(150.0 / float(s.damage))
	assert_true(shots >= 5 and shots <= 8, "M1911 : %d balles au corps en manche 1" % shots)
	assert_true(WeaponDB.MELEE_DAMAGE >= 150, "couteau : un coup en manche 1")


func test_wall_prices_and_ammo() -> void:
	for id in WALL:
		assert_eq(WeaponDB.wall_cost(id), WALL[id], "prix mural %s" % id)
		assert_eq(WeaponDB.ammo_cost(id, false), WALL[id] / 2, "munitions %s" % id)
		assert_eq(WeaponDB.ammo_cost(id, true), 4500, "munitions améliorées %s" % id)
	for id in BOX:
		assert_eq(WeaponDB.wall_cost(id), 0, "%s ne s'achète pas au mur" % id)


func test_pap_upgrades() -> void:
	var names := {}
	for id in WeaponDB.WEAPONS:
		var b := WeaponDB.stats(id)
		var u := WeaponDB.stats(id, true)
		assert_true(u.name != b.name, "%s : nom amélioré" % id)
		assert_false(names.has(u.name), "%s : nom amélioré unique" % id)
		names[u.name] = true
		var better: bool = int(u.damage) >= int(b.damage) * 2 or float(u.get("splash_damage", 0)) >= float(b.get("splash_damage", 0)) * 1.5
		assert_true(better, "%s : dégâts améliorés (%d -> %d)" % [id, b.damage, u.damage])
		# Exception BO1 : le M1911 amélioré tire 6 balles explosives (6 / 50).
		if id != "m1911":
			assert_true(int(u.mag) >= int(b.mag) and int(u.reserve) >= int(b.reserve), "%s : munitions améliorées" % id)
	# M1911 amélioré : balles explosives, 6 coups.
	var mp := WeaponDB.stats("m1911", true)
	assert_eq(int(mp.mag), 6)
	assert_true(mp.has("splash_radius") and mp.has("projectile_speed") and mp.has("self_damage"), "M1911 amélioré explosif")
	assert_true(WeaponDB.stats("olympia", true).has("burn_dps"), "Olympia améliorée incendiaire")
	assert_false(WeaponDB.stats("m1911").has("splash_radius"), "M1911 de base : balles normales")


func test_special_mechanics() -> void:
	assert_eq(int(WeaponDB.stats("m16").get("burst", 0)), 3, "M16 : rafale de 3")
	assert_eq(int(WeaponDB.stats("g11").get("burst", 0)), 3, "G11 : rafale de 3")
	for id in ["china_lake", "law"]:
		var s := WeaponDB.stats(id)
		assert_true(s.has("splash_radius") and s.has("projectile_speed") and s.has("self_damage"), "%s : projectile explosif" % id)
		@warning_ignore("integer_division")
		assert_true(int(s.self_damage) < int(s.splash_damage) / 5, "%s : dégâts à soi réduits" % id)
	assert_near(WeaponDB.projectile_delay("law", false, Vector3.ZERO, Vector3(0, 0, -45)), 1.0, 0.001, "roquette à 45 m/s")
	assert_eq(WeaponDB.projectile_delay("m14", false, Vector3.ZERO, Vector3(0, 0, -45)), 0.0, "balle instantanée")
	# Vitesse de déplacement : pistolets/PM rapides, mitrailleuses lentes.
	assert_true(WeaponDB.stats("m1911").move_mult > WeaponDB.stats("m16").move_mult)
	assert_true(WeaponDB.stats("mp5k").move_mult > WeaponDB.stats("hk21").move_mult)
	assert_true(WeaponDB.stats("rpk").move_mult < 0.9)
	assert_eq(String(WeaponDB.stats("olympia").reload_kind), "break")
	assert_eq(String(WeaponDB.stats("stakeout").reload_kind), "shells")
	# Rechargement cartouche par cartouche : un son par cartouche + la pompe.
	var steps := WeaponController.reload_sounds(WeaponDB.stats("stakeout"), {"mag": 3})
	assert_eq(steps.size(), 4, "3 cartouches + pompe")


func test_box_pool() -> void:
	var pool := WeaponDB.box_pool()
	for id in BOX:
		assert_true(pool.has(id), "%s dans la boîte" % id)
	assert_false(pool.has("m1911"), "pas d'arme de départ dans la boîte")
	for id in WALL:
		assert_false(pool.has(id), "pas d'arme murale %s dans la boîte" % id)
	assert_true(pool.ray < pool.galil, "CLAUDE-RAY plus rare")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pd := PlayerData.new()
	pd.weapons = [WeaponDB.new_instance("m1911"), WeaponDB.new_instance("galil")]
	var count := {}
	for i in 3000:
		var id := MysteryBox.pick_weapon(pd, rng)
		count[id] = count.get(id, 0) + 1
	assert_false(count.has("galil"), "jamais une arme déjà possédée")
	assert_false(count.has("m1911"))
	assert_true(count.get("ray", 0) > 0 and count.ray < count.get("hk21", 0), "tirage pondéré (rayon %d, HK21 %d)" % [count.get("ray", 0), count.get("hk21", 0)])


func test_models_and_anchors() -> void:
	for id in WeaponDB.WEAPONS:
		var mid: String = WeaponDB.stats(id).model
		assert_true(WeaponModels.SPECS.has(mid), "%s : modèle défini" % id)
		var sp := WeaponModels.spec(mid)
		assert_true(sp.parts.size() >= 5, "%s : au moins 5 pièces" % id)
		for a in ["muzzle", "sight", "grip", "support"]:
			assert_true(sp.anchors.has(a), "%s : point %s" % [id, a])
		assert_true(sp.anchors.muzzle.z < -0.15, "%s : bouche du canon devant" % id)
		# Pièces fusionnées : un maillage par matériau (quelques appels de dessin).
		var mats := {}
		for part in sp.parts:
			mats[part[3]] = true
		var m := WeaponModels.build(mid, false)
		assert_eq(m.get_child_count(), mats.size(), "%s : un maillage par matériau" % id)
		m.free()
		# Vue FPS : un nœud par groupe mobile, chargeur amovible s'il existe.
		var vm := WeaponModels.build(mid, true)
		assert_true(vm.get_node_or_null("body") != null, "%s : carcasse FPS" % id)
		for part in sp.parts:
			if part.size() > 5 and part[5] != "":
				assert_true(vm.get_node_or_null(String(part[5])) != null, "%s : groupe %s" % [id, part[5]])
		vm.free()
	# Silhouettes distinctes : les armes longues sont plus longues que les pistolets.
	assert_true(WeaponModels.anchor("m1911", "muzzle").z > WeaponModels.anchor("m14", "muzzle").z)
	assert_true(WeaponModels.anchor("mp5k", "muzzle").z > WeaponModels.anchor("l96a1", "muzzle").z)
