extends TestCase
## Règles des armes et des pièces au hub (HubGear, sans interface ; reprises
## des tests de l'ancien onglet ARSENAL) : filtres, raison d'un refus de
## montage, noms des pièces et ordre de leurs modificateurs, noms et familles
## des armes (jamais l'identifiant interne), tri des pièces, statistiques
## effectives avec les pièces.

var _saved := {}


func before_each() -> void:
	_saved["language"] = Settings.language
	Settings.language = "fr"


func after_each() -> void:
	for k in _saved:
		Settings.set(k, _saved[k])


## Profil de niveau 7 : FRELON épique niv. 7 (2 pièces) et sa version 2 rare
## niv. 5, SIROCCO rare 6, MAMBA légendaire 9 (verrouillée), CARNAGE commune
## 3, VIEILLE GARDE commune 4 ; 5 pièces en stock.
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 2140
	var w := OwnedWeapon.create("mp5k", 7, OwnedWeapon.Rarity.EPIC)
	w.parts.append(WeaponPart.create("part_damage", 6, {"damage": 0.15}))
	w.parts.append(WeaponPart.create("part_fire_rate", 5, {"fire_rate": 0.1, "accuracy": -0.06}))
	pr.add_weapon(w)
	pr.add_weapon(OwnedWeapon.create("mp5k", 5, OwnedWeapon.Rarity.RARE))
	pr.add_weapon(OwnedWeapon.create("m16", 6, OwnedWeapon.Rarity.RARE))
	pr.add_weapon(OwnedWeapon.create("python", 9, OwnedWeapon.Rarity.LEGENDARY))
	pr.add_weapon(OwnedWeapon.create("stakeout", 3, OwnedWeapon.Rarity.COMMON))
	pr.add_weapon(OwnedWeapon.create("m14", 4, OwnedWeapon.Rarity.COMMON))
	for p in [["damage", 9, 0.22], ["mag", 7, 0.2], ["accuracy", 6, 0.12], ["recoil", 4, 0.18], ["reload", 2, 0.07]]:
		pr.add_part(WeaponPart.create("part_" + p[0], p[1], {p[0]: p[2]}))
	pr.mark_all_seen()
	return pr


func test_filters() -> void:
	var pr := demo_profile()
	var bat: OwnedWeapon = BaseWeapons.all()[1]
	assert_true(HubGear.passes(bat, "melee", 7) and not HubGear.passes(bat, "firearm", 7), "batte : corps à corps")
	var mamba := pr.weapons[3]
	assert_false(HubGear.passes(mamba, "usable", pr.level()), "niveau 9 > 7 : pas utilisable")
	assert_true(HubGear.passes(mamba, "firearm", pr.level()))
	assert_true(HubGear.passes(mamba, "all", pr.level()))
	var usable := pr.weapons.filter(func(w): return HubGear.passes(w, "usable", pr.level()))
	assert_eq(usable.size(), 5, "UTILISABLES : 6 armes moins MAMBA")


func test_mount_refusal_reasons() -> void:
	var pr := demo_profile()
	var frelon := pr.weapons[0]
	var high := WeaponPart.create("part_damage", 9, {"damage": 0.2})
	assert_eq(HubGear.mount_refusal(frelon, high, 7), "NIVEAU 9 : AU-DESSUS DE L'ARME (7) ET DU VÔTRE (7)")
	assert_eq(HubGear.mount_refusal(pr.weapons[3], high, 7), "NIVEAU 9 : AU-DESSUS DU VÔTRE (7)")
	var mid := WeaponPart.create("part_mag", 6, {"mag": 0.2})
	assert_eq(HubGear.mount_refusal(pr.weapons[1], mid, 7), "NIVEAU 6 : AU-DESSUS DE L'ARME (5)")
	assert_eq(HubGear.mount_refusal(BaseWeapons.make(WeaponDB.STARTING_WEAPON), mid, 7), "ARME DE BASE")
	assert_eq(HubGear.mount_refusal(frelon, mid, 7), "", "montable : 6 ≤ 7 et ≤ 7, un emplacement libre")
	var full := OwnedWeapon.create("m14", 9, OwnedWeapon.Rarity.COMMON)
	full.parts.append(WeaponPart.create("part_damage", 1, {"damage": 0.1}))
	assert_eq(HubGear.mount_refusal(full, mid, 9), "AUCUN EMPLACEMENT LIBRE")
	assert_eq(HubGear.mount_refusal(null, mid, 9), "INTROUVABLE")
	assert_true(HubGear.mountable_anywhere(pr, mid), "la rallonge niv. 6 se monte sur le FRELON")
	assert_false(HubGear.mountable_anywhere(pr, high), "niv. 9 : au-dessus du joueur")
	Settings.language = "en"
	assert_eq(HubGear.mount_refusal(frelon, high, 7), "LEVEL 9: ABOVE THE WEAPON (7) AND YOURS (7)")


func test_part_names_and_mod_order() -> void:
	var p := WeaponPart.create("part_fire_rate", 5, {"fire_rate": 0.1, "accuracy": -0.06})
	assert_eq(HubGear.part_name(p), "Ressort")
	assert_eq(HubGear.first_mod(p), "fire_rate", "modificateur de l'identifiant")
	assert_eq(HubGear.ordered_mods(p).keys(), ["fire_rate", "accuracy"], "le principal d'abord")
	var q := WeaponPart.create("part_x", 3, {"accuracy": 0.05, "damage": 0.2})
	assert_eq(HubGear.first_mod(q), "damage", "sinon le plus grand bonus")
	assert_eq(HubGear.part_name(q), "Renfort")
	Settings.language = "en"
	assert_eq(HubGear.part_name(p), "Spring")


func test_part_sort() -> void:
	var pr := demo_profile()
	var parts := pr.parts.duplicate()
	parts.sort_custom(func(a, b): return HubGear.part_before(a, b, "level"))
	var levels := parts.map(func(p): return p.level)
	assert_eq(levels, [9, 7, 6, 4, 2], "niveau décroissant")
	parts.sort_custom(func(a, b): return HubGear.part_before(a, b, "mod"))
	var mods := parts.map(func(p): return HubGear.first_mod(p))
	var order := mods.map(func(m): return LootRules.PART_MODS.find(m))
	var sorted := order.duplicate()
	sorted.sort()
	assert_eq(order, sorted, "par modificateur (LootRules.PART_MODS) : %s" % str(mods))


## Noms et familles des armes au hub : noms originaux (jamais l'identifiant
## interne), familles de WeaponDB.FAMILIES, la batte arme de corps à corps.
func test_weapon_names_and_families() -> void:
	for lang in ["fr", "en"]:
		Settings.language = lang
		for id in WeaponDB.WEAPONS:
			var n := HubGear.weapon_name(id)
			assert_eq(n, WeaponDB.display_name(id), "%s : nom du jeu" % id)
			assert_true(n.to_lower() != String(id).to_lower() or id == "bat", "%s : jamais l'identifiant interne" % id)
			var cls := String(WeaponDB.stats(id).get("class", ""))
			assert_eq(HubGear.weapon_class(id).to_upper(), WeaponDB.family_name(id).to_upper(), "%s : famille %s" % [id, cls])
	Settings.language = "fr"
	for cls in WeaponDB.CLASSES:
		assert_true(HubGear.CLASS_NAMES.has(cls), "famille %s nommée" % cls)
	assert_eq(HubGear.weapon_name("bat"), "BATTE")
	assert_eq(HubGear.weapon_class("bat"), "Corps à corps")
	assert_eq(HubGear.weapon_name("pas_une_arme"), "?")
	assert_true(HubGear.is_melee("bat") and not HubGear.is_melee(WeaponDB.STARTING_WEAPON))


func test_effective_stats_with_parts() -> void:
	var w := OwnedWeapon.create("mp5k", 1, OwnedWeapon.Rarity.EPIC)
	var plain := HubGear.fire_stats(w)
	assert_eq(int(plain.damage), int(WeaponDB.stats("mp5k").damage), "niveau 1 sans pièce : dégâts de base")
	w.parts.append(WeaponPart.create("part_damage", 1, {"damage": 0.5}))
	w.parts.append(WeaponPart.create("part_accuracy", 1, {"accuracy": -0.5}))
	var eff := HubGear.fire_stats(w)
	var raw := HubGear.fire_stats(w, false)
	assert_eq(roundi(eff.damage), roundi(WeaponDB.stats("mp5k").damage * 1.5), "dégâts effectifs (GameWeapon.stats)")
	assert_eq(roundi(raw.damage), roundi(WeaponDB.stats("mp5k").damage), "sans les pièces")
	assert_true(HubGear.accuracy(eff) < HubGear.accuracy(raw), "malus de précision : précision affichée plus basse")
	assert_eq(HubGear.accuracy({"spread_hip": 0.0}), 100)
	assert_eq(HubGear.accuracy({"spread_hip": 50.0}), 0, "bornée à 0")
