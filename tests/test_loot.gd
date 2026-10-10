extends TestCase
## Butin des vagues spéciales (GAME_CONCEPT §4.7, LootRules, ProfileLoot,
## LootDrop) : bornes de niveau, distribution des raretés, pièces,
## échantillons, montage, butin rapporté au profil, rapport de fin, modèle
## cubique de l'arme au sol.

var file := "user://profile_loot_unittest_%d.json" % OS.get_process_id()


func before_each() -> void:
	ProfileStore.reset(file)


func after_each() -> void:
	ProfileStore.reset(file)


func _rng(seed_v := 1234) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


# --------------------------------------------------------------------------
# Armes
# --------------------------------------------------------------------------

func test_weapons_per_wave() -> void:
	assert_eq(LootRules.weapons_for_wave(WaveRules.SPECIAL), 1)
	assert_eq(LootRules.weapons_for_wave(WaveRules.BOSS), 2)
	assert_eq(LootRules.weapons_for_wave(""), 0)


func test_base_level_field() -> void:
	for id in WeaponDB.WEAPONS:
		assert_eq(WeaponDB.base_level(id), 1, "niveau de base par défaut : %s" % id)
	assert_eq(WeaponDB.base_level("inconnue"), 1)


func test_weapon_pool_excludes_base_weapons() -> void:
	var pool := LootRules.weapon_pool()
	assert_false(WeaponDB.STARTING_WEAPON in pool, "pistolet de départ exclu")
	assert_eq(pool.size(), WeaponDB.WEAPONS.size() - 1)
	for id in pool:
		assert_true(WeaponDB.exists(id))


func test_weapon_level_bounds() -> void:
	assert_eq(LootRules.weapon_level_range(10), Vector2i(4, 12))
	assert_eq(LootRules.weapon_level_range(1), Vector2i(1, 3), "au moins 1")
	assert_eq(LootRules.weapon_level_range(5, 8), Vector2i(8, 8), "jamais sous le niveau de base")
	assert_eq(LootRules.weapon_level_range(10, 7), Vector2i(7, 12))
	assert_eq(LootRules.weapon_level_range(60), Vector2i(50, 50), "plafond 50")
	assert_eq(LootRules.weapon_level_range(49), Vector2i(43, 50))
	var rng := _rng()
	for round_n in [1, 3, 10, 25, 49, 50, 80]:
		for base in [1, 7, 30]:
			var r := LootRules.weapon_level_range(round_n, base)
			var lo := 99
			var hi := 0
			for i in 400:
				var l := LootRules.roll_weapon_level(round_n, base, rng)
				lo = mini(lo, l)
				hi = maxi(hi, l)
			assert_true(lo >= r.x and hi <= r.y, "manche %d, base %d : %d..%d dans %s" % [round_n, base, lo, hi, r])
			assert_true(lo >= 1 and hi <= 50 and lo >= mini(base, 50))
	# Plage complète atteinte (manche 10 : 4 à 12).
	var seen := {}
	for i in 2000:
		seen[LootRules.roll_weapon_level(10, 1, rng)] = true
	assert_eq(seen.size(), 9, "niveaux 4 à 12 tous tirés")


func test_rarity_thresholds() -> void:
	assert_eq(LootRules.rarity_for(0.0), OwnedWeapon.Rarity.COMMON)
	assert_eq(LootRules.rarity_for(59.99), OwnedWeapon.Rarity.COMMON)
	assert_eq(LootRules.rarity_for(60.0), OwnedWeapon.Rarity.RARE)
	assert_eq(LootRules.rarity_for(79.99), OwnedWeapon.Rarity.RARE)
	assert_eq(LootRules.rarity_for(80.0), OwnedWeapon.Rarity.EPIC)
	assert_eq(LootRules.rarity_for(92.49), OwnedWeapon.Rarity.EPIC)
	assert_eq(LootRules.rarity_for(92.5), OwnedWeapon.Rarity.LEGENDARY)
	assert_eq(LootRules.rarity_for(97.5), OwnedWeapon.Rarity.UNIQUE)
	assert_eq(LootRules.rarity_for(99.999), OwnedWeapon.Rarity.UNIQUE)
	var total := 0.0
	for w in LootRules.RARITY_WEIGHTS:
		total += w
	assert_near(total, 100.0, 0.0001)


func test_rarity_distribution() -> void:
	var rng := _rng(77)
	var n := 200000
	var counts := [0, 0, 0, 0, 0]
	for i in n:
		counts[LootRules.roll_rarity(rng)] += 1
	for r in 5:
		var pct: float = 100.0 * counts[r] / n
		assert_near(pct, LootRules.RARITY_WEIGHTS[r], 0.4, "rareté %d : %.2f %%" % [r, pct])


func test_roll_weapon_is_a_game_weapon() -> void:
	var rng := _rng(5)
	for i in 50:
		var w := LootRules.roll_weapon(10, rng, "loot:%d" % i)
		assert_true(WeaponDB.exists(w.id) and not BaseWeapons.is_base(w.id))
		assert_eq(w.uid, "loot:%d" % i)
		assert_true(w.level >= 4 and w.level <= 12)
		assert_true(w.parts.is_empty())
		assert_eq(int(w.mag), int(GameWeapon.stats(w).mag), "chargeur plein")


# --------------------------------------------------------------------------
# Pièces
# --------------------------------------------------------------------------

func test_part_level_bounds() -> void:
	assert_eq(LootRules.part_level_range(1), Vector2i(1, 1))
	assert_eq(LootRules.part_level_range(8), Vector2i(1, 8))
	assert_eq(LootRules.part_level_range(25), Vector2i(15, 25))
	assert_eq(LootRules.part_level_range(50), Vector2i(40, 50))
	var rng := _rng(9)
	for lvl in [1, 8, 25, 50]:
		var r := LootRules.part_level_range(lvl)
		for i in 300:
			var p := LootRules.roll_part(lvl, rng)
			assert_true(p.level >= r.x and p.level <= r.y, "pièce niveau %d pour joueur %d" % [p.level, lvl])


func test_part_modifiers() -> void:
	var rng := _rng(11)
	var two := 0
	var malus := 0
	var n := 4000
	for i in n:
		var p := LootRules.roll_part(10, rng, "lootp:%d" % i)
		var mods: Dictionary = p.mods
		assert_true(mods.size() == 1 or mods.size() == 2)
		var first: String = mods.keys()[0]
		assert_true(float(mods[first]) > 0.0, "premier modificateur : bonus")
		assert_eq(p.id, "part_" + first)
		for k in mods:
			assert_true(GameWeapon.MODS.has(k), "modificateur connu : %s" % k)
			var a := absf(float(mods[k]))
			assert_true(a >= 0.05 - 1e-6 and a <= 0.25 + 1e-6, "valeur 5 à 25 %% : %s" % a)
			if float(mods[k]) < 0.0:
				malus += 1
		if mods.size() == 2:
			two += 1
	assert_near(float(two) / n, LootRules.PART_SECOND_CHANCE, 0.03, "second modificateur")
	assert_near(float(malus) / n, LootRules.PART_SECOND_CHANCE * LootRules.PART_MALUS_CHANCE, 0.03, "malus")
	assert_true(malus < n / 2, "majorité de bonus")


func test_part_chance() -> void:
	var rng := _rng(13)
	var n := 100000
	var got := 0
	for i in n:
		if LootRules.part_drops(rng):
			got += 1
	assert_near(float(got) / n, 0.05, 0.004)
	assert_true(LootRules.part_drops(rng, 1.0))
	assert_false(LootRules.part_drops(rng, 0.0))


func test_mount_rule_and_mount() -> void:
	var w := GameWeapon.make("mp40", 5, OwnedWeapon.Rarity.COMMON, [], "loot:1")
	var p := {"id": "part_mag", "uid": "lootp:2", "level": 5, "mods": {"mag": 0.2}}
	assert_eq(LootRules.mount_refusal(w, p, 4), "player_level")
	assert_eq(LootRules.mount_refusal(w, {"id": "x", "level": 6, "mods": {}}, 10), "weapon_level")
	assert_eq(LootRules.mount_refusal(w, p, 5), "")
	w.mag = 10
	LootRules.mount(w, p)
	assert_eq(w.parts.size(), 1)
	assert_eq(GameWeapon.score(w), 10)
	assert_eq(int(w.mag), 10, "munitions en cours gardées")
	assert_eq(int(GameWeapon.stats(w).mag), 38, "chargeur +20 %")
	assert_eq(LootRules.mount_refusal(w, {"id": "y", "level": 1, "mods": {}}, 5), "no_slot", "commune : 1 emplacement")
	var loaned := WeaponDB.new_instance("m1911")
	loaned["loaned"] = true
	assert_eq(LootRules.mount_refusal(loaned, {"id": "y", "level": 1, "mods": {}}, 5), "invalid")


# --------------------------------------------------------------------------
# Échantillons
# --------------------------------------------------------------------------

func test_dog_samples() -> void:
	var kinds: Array = LootRules.SAMPLES["dogs"]
	assert_eq(kinds.size(), 3, "chiens : croc, touffe de poils, collier")
	for s in kinds:
		assert_true(ProfileValues.id_ok(s[0]))
		assert_eq(s.size(), 3, "noms FR / EN")
	var rng := _rng(21)
	var counts := {}
	var n := 50000
	for i in n:
		for s in LootRules.roll_samples("dogs", rng):
			counts[s] = int(counts.get(s, 0)) + 1
	for s in kinds:
		assert_near(float(counts.get(s[0], 0)) / n, 0.2, 0.01, "%s : 20 %% par zombie" % s[0])
	assert_true(LootRules.roll_samples("inconnu", rng).is_empty())
	assert_eq(LootRules.roll_samples("dogs", rng, 1.0).size(), 3)


func test_texts_fr_en() -> void:
	var was: String = Settings.language
	Settings.language = "fr"
	assert_eq(LootRules.sample_name("dog_fang"), "CROC")
	assert_eq(LootRules.mods_text({"damage": 0.12, "recoil": -0.05}), "+12 % dégâts, −5 % recul")
	assert_eq(LootSystem.counter_text({"dog_fur": 1, "dog_fang": 2}, 1), "CROC 2 · TOUFFE DE POILS 1 · PIÈCES 1")
	assert_eq(LootSystem.msg_text(LootSystem.MSG_BAG_FULL, ""), "Inventaire plein : libérez une place")
	assert_eq(LootDrop.label_text(GameWeapon.make("mp40", 7, 2), "Bob"), "MP40\nNIV. 7 · ÉPIQUE\nBob")
	Settings.language = "en"
	assert_eq(LootRules.sample_name("dog_collar"), "COLLAR")
	assert_eq(LootRules.mods_text({"fire_rate": 0.25}), "+25 % fire rate")
	assert_eq(LootSystem.counter_text({}, 0), "")
	assert_eq(LootSystem.msg_text(LootSystem.MSG_NOT_YOURS, "Ann"), "This loot belongs to Ann")
	assert_eq(LootSystem.msg_text(LootSystem.MSG_MOUNT_REFUSED, "no_slot"), "No free part slot")
	Settings.language = was


# --------------------------------------------------------------------------
# Butin rapporté au profil (§4.6, §4.12)
# --------------------------------------------------------------------------

func _pd() -> PlayerData:
	var pd := PlayerData.new(1)
	var base := GameWeapon.from_owned(BaseWeapons.make(WeaponDB.STARTING_WEAPON))
	var loaned := WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)
	loaned["loaned"] = true
	pd.weapons = [base, GameWeapon.make("mp40", 9, OwnedWeapon.Rarity.RARE,
		[{"id": "part_damage", "uid": "lootp:3", "level": 2, "mods": {"damage": 0.1}}], "loot:1"), loaned]
	pd.bag = [GameWeapon.make("m14", 40, OwnedWeapon.Rarity.UNIQUE, [], "loot:2")]
	return pd


func test_carried_keeps_found_weapons_only() -> void:
	var loot := ProfileLoot.carried(_pd(), [{"id": "part_mag", "uid": "lootp:4", "level": 3, "mods": {"mag": 0.1}}],
		{"dog_fang": 2, "dog_fur": 0})
	assert_eq(loot.weapons.size(), 2, "pistolet de base intact et pistolet prêté exclus")
	assert_eq(loot.weapons[0].id, "mp40")
	assert_eq(loot.weapons[1].id, "m14", "arme de l'inventaire gardée (même de niveau trop élevé)")
	assert_eq(loot.parts.size(), 1)
	assert_eq(loot.samples, {"dog_fang": 2})
	# Arme de base améliorée : rapportée (nouvelle version).
	var upgraded := GameWeapon.from_owned(BaseWeapons.make(WeaponDB.STARTING_WEAPON))
	LootRules.mount(upgraded, {"id": "part_reload", "uid": "lootp:9", "level": 1, "mods": {"reload": 0.1}})
	assert_true(ProfileLoot.keeps_weapon(upgraded))
	assert_false(ProfileLoot.carried(null, [], {}).weapons.size() > 0)


func test_apply_evacuation_enriches_profile() -> void:
	var pr := PlayerProfile.new()
	pr.add_samples("dog_fang", 1)
	ProfileStore.save_profile(pr, file)
	var loot := ProfileLoot.carried(_pd(), [{"id": "part_mag", "uid": "lootp:4", "level": 3, "mods": {"mag": 0.1}}],
		{"dog_fang": 2, "dog_collar": 1})
	var out := ProfileLoot.apply_evacuation(loot, file)
	assert_eq(out, {"weapons": 2, "updated": 0, "parts": 1, "samples": 3})
	var back := ProfileStore.load_profile(file)
	assert_eq(back.weapons.size(), 2)
	var mp := back.versions_of("mp40")
	assert_eq(mp.size(), 1)
	assert_eq(mp[0].level, 9)
	assert_eq(mp[0].rarity, OwnedWeapon.Rarity.RARE)
	assert_eq(mp[0].parts.size(), 1, "pièce montée en partie gardée sur l'arme")
	assert_true(mp[0].uid.begins_with("w") and mp[0].parts[0].uid.begins_with("p"), "identifiants du profil")
	assert_eq(back.versions_of("m14")[0].level, 40)
	assert_eq(back.parts.size(), 1)
	assert_eq(back.parts[0].mods, {"mag": 0.1})
	assert_eq(back.sample_count("dog_fang"), 3, "échantillons ajoutés aux anciens")
	assert_eq(back.sample_count("dog_collar"), 1)


func test_arsenal_version_is_updated() -> void:
	var pr := PlayerProfile.new()
	var uid := pr.add_weapon(OwnedWeapon.create("galil", 4, OwnedWeapon.Rarity.RARE))
	var w := GameWeapon.from_owned(pr.get_weapon(uid))
	LootRules.mount(w, {"id": "part_damage", "uid": "lootp:1", "level": 2, "mods": {"damage": 0.2}})
	var pd := PlayerData.new(1)
	pd.weapons = [w]
	var out := ProfileLoot.apply_to(pr, ProfileLoot.carried(pd, [], {}))
	assert_eq(out.updated, 1)
	assert_eq(pr.weapons.size(), 1, "même version, pas de doublon")
	assert_eq(pr.get_weapon(uid).parts.size(), 1)


func test_report_and_match_result_text() -> void:
	var loot := ProfileLoot.carried(_pd(), [{"id": "p", "level": 1, "mods": {}}], {"dog_fang": 2})
	var rep := ProfileLoot.report(loot, true)
	assert_eq(rep.weapons.size(), 2)
	assert_eq(rep.parts, 1)
	var r := MatchResult.new()
	r.evacuated = true
	r.loot = rep
	r.xp = 120
	var back := MatchResult.from_dict(r.to_dict())
	var was: String = Settings.language
	Settings.language = "fr"
	assert_eq(back.loot_text(), "BUTIN GARDÉ : MP40 (niv. 9, rare), M14 (niv. 40, unique), 1 pièce(s), 2 croc · +120 XP")
	back.loot = ProfileLoot.report(loot, false)
	assert_true(back.loot_text().begins_with("BUTIN PERDU : "))
	assert_true(back.loot_text().ends_with("seule l'XP est gardée (+120 XP)"))
	Settings.language = "en"
	assert_true(back.loot_text().begins_with("LOOT LOST: MP40 (lvl 9, rare)"))
	back.loot = ProfileLoot.report(ProfileLoot.carried(null, [], {}), true)
	assert_eq(back.loot_text(), "No loot brought back · +120 XP")
	Settings.language = was
	var empty := MatchResult.new()
	assert_eq(empty.loot_text(), "")


# --------------------------------------------------------------------------
# Arme au sol
# --------------------------------------------------------------------------

func test_drop_model_is_cubic() -> void:
	var root := Node3D.new()
	for r in 5:
		for c in root.get_children():
			root.remove_child(c)
			c.free()
		LootDrop.build_model(root, r, r)
		var rep := VoxelCheck.check_scene(root)
		assert_true(rep.ok, "modèle en cubes de 5 cm : %s" % rep.get("fr", ""))
	root.free()


func test_drop_prompt_owner_only() -> void:
	var d := LootDrop.new()
	d.setup(3, 7, GameWeapon.make("mp40", 4, 1), Vector3.ZERO, null)
	assert_eq(d.interact_id, "loot_3")
	assert_true(d.prompt(7) != "", "invite du propriétaire")
	assert_eq(d.prompt(8), "", "aucune invite pour un autre joueur")
	d.free()
