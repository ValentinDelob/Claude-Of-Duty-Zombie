extends TestCase
## Armes de partie (GameWeapon, GAME_CONCEPT §4.9, §4.12, §4.13) : dégâts par
## niveau, modificateurs des pièces, règle de niveau, score et puissance,
## échanges entre la main et l'inventaire, armes de départ du profil.


func _pd(lvl := 1) -> PlayerData:
	var pd := PlayerData.new(1)
	pd.level = lvl
	pd.weapons = []
	return pd


func _part(lvl: int, mods: Dictionary) -> Dictionary:
	return {"id": "test_part", "level": lvl, "mods": mods}


# --------------------------------------------------------------------------
# Dégâts par niveau
# --------------------------------------------------------------------------

func test_damage_grows_ten_percent_of_base_per_level() -> void:
	assert_near(GameWeapon.damage_mult(1), 1.0)
	assert_near(GameWeapon.damage_mult(2), 1.1)
	assert_near(GameWeapon.damage_mult(11), 2.0, 0.0001, "niveau 11 : le double du niveau 1")
	assert_near(GameWeapon.damage_mult(50), 5.9)
	assert_near(GameWeapon.damage_mult(0), 1.0, 0.0001, "niveau borné à 1")
	var base := int(WeaponDB.stats("mp40").damage)
	assert_eq(int(GameWeapon.stats(GameWeapon.make("mp40", 1)).damage), base)
	assert_eq(int(GameWeapon.stats(GameWeapon.make("mp40", 11)).damage), base * 2)
	assert_eq(int(GameWeapon.stats(GameWeapon.make("mp40", 6)).damage), roundi(base * 1.5))


func test_level_one_without_parts_is_the_base_weapon() -> void:
	var w := GameWeapon.make("m14")
	assert_true(is_same(GameWeapon.stats(w), WeaponDB.stats("m14")), "mêmes statistiques que WeaponDB (même dictionnaire)")
	assert_eq(w.mag, WeaponDB.stats("m14").mag)
	assert_eq(w.reserve, WeaponDB.stats("m14").reserve)
	assert_eq(w.level, 1)
	assert_eq(w.rarity, OwnedWeapon.Rarity.COMMON)
	assert_eq(WeaponDB.new_instance("m14").level, 1, "new_instance : arme de partie niveau 1")


func test_level_scales_explosion_damage_too() -> void:
	var base := WeaponDB.stats("china_lake")
	var s := GameWeapon.stats(GameWeapon.make("china_lake", 3))
	assert_eq(int(s.splash_damage), roundi(float(base.splash_damage) * 1.2))
	assert_eq(int(s.rpm), int(base.rpm), "le niveau ne touche que les dégâts")


# --------------------------------------------------------------------------
# Modificateurs des pièces
# --------------------------------------------------------------------------

func test_part_modifiers() -> void:
	var base := WeaponDB.stats("mp40")
	var w := GameWeapon.make("mp40", 1, OwnedWeapon.Rarity.EPIC, [
		_part(1, {"damage": 0.25, "fire_rate": -0.05}),
		_part(1, {"reload": 0.2, "mag": 0.5}),
		_part(1, {"recoil": 1.0, "accuracy": 0.25, "reserve": -0.5}),
	])
	var s := GameWeapon.stats(w)
	assert_eq(int(s.damage), roundi(float(base.damage) * 1.25), "+25 % de dégâts")
	assert_eq(int(s.rpm), roundi(float(base.rpm) * 0.95), "−5 % de cadence")
	assert_near(float(s.reload), float(base.reload) / 1.2, 0.0001, "rechargement +20 % : durée ÷ 1,2")
	assert_eq(int(s.mag), roundi(float(base.mag) * 1.5), "chargeur +50 %")
	assert_eq(int(s.reserve), roundi(float(base.reserve) * 0.5), "réserve −50 %")
	assert_near(float(s.recoil), float(base.recoil) / 2.0, 0.0001, "recul +100 % : deux fois moins")
	assert_near(float(s.spread_hip), float(base.spread_hip) / 1.25, 0.0001, "précision +25 %")
	assert_eq(w.mag, s.mag, "munitions de départ selon les statistiques effectives")
	assert_eq(w.reserve, s.reserve)
	assert_eq(String(s.name), String(base.name), "le reste ne change pas")


func test_modifiers_add_up_and_combine_with_level() -> void:
	var base := float(WeaponDB.stats("mp40").damage)
	var w := GameWeapon.make("mp40", 5, OwnedWeapon.Rarity.RARE, [_part(3, {"damage": 0.25}), _part(4, {"damage": 0.1})])
	assert_eq(int(GameWeapon.stats(w).damage), roundi(base * 1.4 * 1.35), "niveau × (1 + somme des bonus)")
	var totals := GameWeapon.mod_totals(w.parts)
	assert_near(float(totals.damage), 0.35)


func test_modifier_floor_and_unknown_names() -> void:
	var base := WeaponDB.stats("mp40")
	var w := GameWeapon.make("mp40", 1, 0, [_part(1, {"fire_rate": -5.0, "jump": 3.0, "rate": 0.0})])
	var s := GameWeapon.stats(w)
	assert_eq(int(s.rpm), roundi(float(base.rpm) * GameWeapon.MIN_FACTOR), "malus plafonné : jamais 0")
	assert_false(GameWeapon.mod_totals(w.parts).has("jump"), "statistique inconnue ignorée")
	var tiny := GameWeapon.make("law", 1, 0, [_part(1, {"mag": -0.9})])
	assert_eq(int(GameWeapon.stats(tiny).mag), 1, "chargeur d'au moins un coup")
	var alias := GameWeapon.make("mp40", 1, 0, [_part(1, {"rate": 0.5})])
	assert_eq(int(GameWeapon.stats(alias).rpm), roundi(float(base.rpm) * 1.5), "« rate » = cadence")


func test_stats_are_cached_and_read_only() -> void:
	var a := GameWeapon.make("mp40", 7)
	var b := GameWeapon.make("mp40", 7)
	assert_true(is_same(GameWeapon.stats(a), GameWeapon.stats(b)), "même arme, même niveau : même entrée de cache")
	assert_true(GameWeapon.stats(a).is_read_only())


func test_fire_interval_and_falloff_follow_parts() -> void:
	var w := GameWeapon.make("mp40", 1, 0, [_part(1, {"fire_rate": 1.0})])
	assert_near(GameWeapon.fire_interval(w), WeaponDB.fire_interval("mp40") / 2.0, 0.0005)
	var r := float(WeaponDB.stats("mp40").range)
	assert_near(GameWeapon.falloff(w, r * 2.0), 0.5)
	assert_near(GameWeapon.falloff(w, r), 1.0)


# --------------------------------------------------------------------------
# Profil <-> partie
# --------------------------------------------------------------------------

func test_owned_weapon_round_trip() -> void:
	var o := OwnedWeapon.create("m14", 12, OwnedWeapon.Rarity.LEGENDARY)
	o.uid = "w7"
	var p := WeaponPart.create("canon", 10, {"damage": 0.2})
	p.uid = "p3"
	o.parts.append(p)
	var w := GameWeapon.from_owned(o)
	assert_eq(w.id, "m14")
	assert_eq(w.uid, "w7")
	assert_eq(w.level, 12)
	assert_eq(w.rarity, OwnedWeapon.Rarity.LEGENDARY)
	assert_eq(w.parts.size(), 1)
	assert_eq(GameWeapon.score(w), o.score(), "même score que l'exemplaire du profil")
	assert_eq(GameWeapon.visual_effect(w), "legendary", "point d'accroche de l'effet légendaire")
	var back := GameWeapon.to_owned(w)
	assert_eq(back.weapon_id, "m14")
	assert_eq(back.level, 12)
	assert_eq(back.rarity, OwnedWeapon.Rarity.LEGENDARY)
	assert_eq(back.parts[0].mods, {"damage": 0.2})
	assert_eq(GameWeapon.visual_effect(GameWeapon.make("m14")), "", "commune : aucun effet")


# --------------------------------------------------------------------------
# Score, puissance, règle de niveau
# --------------------------------------------------------------------------

func test_score_and_power() -> void:
	# Exemple du concept : légendaire niveau 25, pièces 22 + 25 + 19 + 24 -> 115.
	var leg := GameWeapon.make("m14", 25, OwnedWeapon.Rarity.LEGENDARY,
		[_part(22, {}), _part(25, {}), _part(19, {}), _part(24, {})])
	assert_eq(GameWeapon.score(leg), 115)
	var pd := _pd(30)
	pd.weapons = [leg, GameWeapon.make("mp40", 4), GameWeapon.make("m1911")]
	pd.bag = [GameWeapon.make("python", 30)]
	assert_eq(pd.power(), 115 + 4 + 1, "puissance : les trois armes en main, pas l'inventaire")
	assert_eq(GameWeapon.power([]), 0)
	assert_eq(GameWeapon.score({}), 0)


func test_level_rule() -> void:
	assert_true(GameWeapon.can_equip(GameWeapon.make("mp40", 5), 5))
	assert_false(GameWeapon.can_equip(GameWeapon.make("mp40", 6), 5), "niveau de l'arme > niveau du joueur")
	assert_false(GameWeapon.can_equip({}, 50))


# --------------------------------------------------------------------------
# Échanges main <-> inventaire
# --------------------------------------------------------------------------

func test_swap_hand_and_bag() -> void:
	var pd := _pd(10)
	var m1911 := GameWeapon.make("m1911")
	var mp40 := GameWeapon.make("mp40", 3)
	mp40.mag = 7
	var m14 := GameWeapon.make("m14", 2)
	pd.weapons = [m1911, mp40]
	pd.slot = 1
	pd.bag = [m14]
	assert_eq(GameWeapon.swap(pd, 1, 0), "")
	assert_eq(pd.weapons[1].id, "m14", "l'arme de l'inventaire passe en main")
	assert_eq(pd.bag[0].id, "mp40", "l'arme en main va dans l'inventaire")
	assert_eq(pd.bag[0].mag, 7, "munitions gardées")
	assert_eq(pd.slot, 1, "l'emplacement tenu garde son numéro")


func test_swap_into_empty_places() -> void:
	var pd := _pd(10)
	pd.weapons = [GameWeapon.make("m1911")]
	pd.bag = [GameWeapon.make("mp40"), GameWeapon.make("m14")]
	# Place en main vide : l'arme de l'inventaire y passe, sans échange.
	assert_eq(GameWeapon.swap(pd, 2, 1), "")
	assert_eq(pd.weapons.size(), 2)
	assert_eq(pd.weapons[1].id, "m14", "emplacements sans trou")
	assert_eq(pd.bag.size(), 1)
	# Place d'inventaire vide : l'arme en main y est rangée.
	pd.slot = 1
	assert_eq(GameWeapon.swap(pd, 0, 3), "")
	assert_eq(pd.weapons.size(), 1)
	assert_eq(pd.weapons[0].id, "m14")
	assert_eq(pd.slot, 0, "l'arme tenue reste la même (décalée)")
	assert_eq(pd.bag.size(), 2)
	assert_eq(pd.bag[1].id, "m1911")


func test_swap_refusals() -> void:
	var pd := _pd(4)
	pd.weapons = [GameWeapon.make("m1911")]
	pd.bag = [GameWeapon.make("mp40", 5)]
	assert_eq(GameWeapon.swap(pd, 0, 0), "niveau trop élevé", "arme de niveau 5 pour un joueur niveau 4")
	assert_eq(pd.weapons[0].id, "m1911", "rien n'a bougé")
	assert_eq(pd.bag[0].id, "mp40")
	assert_eq(GameWeapon.swap(pd, 1, 2), "places vides")
	assert_eq(GameWeapon.swap(pd, 3, 0), "place invalide")
	assert_eq(GameWeapon.swap(pd, 0, 4), "place invalide")
	assert_eq(GameWeapon.swap(pd, -1, 0), "place invalide")
	pd.level = 5
	pd.life = PlayerData.Life.DOWNED
	assert_eq(GameWeapon.swap(pd, 0, 0), "joueur à terre ou mort")
	pd.life = PlayerData.Life.ALIVE
	assert_eq(GameWeapon.swap(pd, 0, 0), "", "niveau atteint : l'arme s'équipe")
	# Ranger une arme trop haute pour soi reste permis (on la garde).
	pd.level = 1
	assert_eq(GameWeapon.swap(pd, 0, 0), "", "l'arme de niveau 5 retourne dans l'inventaire")
	assert_eq(pd.bag[0].level, 5)


func test_keep_high_level_weapon_in_bag() -> void:
	var pd := _pd(1)
	pd.weapons = [GameWeapon.make("mp40", 8)]
	pd.bag = []
	assert_eq(GameWeapon.swap(pd, 0, 0), "", "une arme trop haute se range dans l'inventaire")
	assert_eq(pd.bag[0].level, 8)
	assert_true(pd.weapons.is_empty())


func test_bag_capacity() -> void:
	var pd := _pd()
	for i in GameWeapon.BAG:
		assert_true(GameWeapon.add_to_bag(pd, GameWeapon.make("mp40")))
	assert_false(GameWeapon.add_to_bag(pd, GameWeapon.make("mp40")), "4 places")
	assert_false(GameWeapon.add_to_bag(_pd(), {}))
	# Inventaire plein : l'échange reste possible, pas le rangement seul.
	pd.weapons = [GameWeapon.make("m1911")]
	assert_eq(GameWeapon.swap(pd, 0, 3), "")
	assert_eq(pd.bag.size(), GameWeapon.BAG)


func test_inventory_is_replicated() -> void:
	var pd := _pd(7)
	pd.weapons = [GameWeapon.make("mp40", 3)]
	pd.bag = [GameWeapon.make("m14", 2, OwnedWeapon.Rarity.RARE, [_part(2, {"damage": 0.1})])]
	var copy := PlayerData.new(1)
	copy.apply_inventory(pd.inventory_dict())
	copy.apply_stats(pd.stats_dict())
	assert_eq(copy.bag.size(), 1)
	assert_eq(copy.bag[0].rarity, OwnedWeapon.Rarity.RARE)
	assert_eq(copy.weapons[0].level, 3)
	assert_eq(copy.level, 7, "niveau du joueur répliqué")
	assert_eq(copy.power(), pd.power())
	pd.bag[0].level = 9
	assert_eq(copy.bag[0].level, 2, "copie profonde")


# --------------------------------------------------------------------------
# Armes de départ
# --------------------------------------------------------------------------

func test_starting_hands_from_profile_selection() -> void:
	var hands := Session.starting_hands(PackedStringArray([WeaponDB.STARTING_WEAPON, KnifeDB.DEFAULT]))
	assert_eq(hands.size(), 1, "le couteau reste l'attaque de mêlée, sans emplacement")
	assert_eq(hands[0].id, WeaponDB.STARTING_WEAPON)
	assert_eq(hands[0].level, 1)
	assert_eq(hands[0].rarity, OwnedWeapon.Rarity.COMMON)
	assert_eq(hands[0].uid, BaseWeapons.UID_PREFIX + WeaponDB.STARTING_WEAPON)
	assert_true(Session.starting_hands(PackedStringArray([KnifeDB.DEFAULT])).is_empty(), "emplacements non choisis : vides")
	assert_true(Session.starting_hands(PackedStringArray(["mp40"])).is_empty(), "armes de base seulement")


func test_apply_loadout_on_server() -> void:
	var s := Session.new()
	host.add_child(s)
	var pd := s.create(5)
	s.loadouts[5] = {"level": 12, "ids": PackedStringArray([WeaponDB.STARTING_WEAPON])}
	pd.bag = [GameWeapon.make("mp40")]
	s.apply_loadout(5)
	assert_eq(pd.level, 12)
	assert_eq(pd.weapons.size(), 1)
	assert_eq(pd.weapons[0].uid, "base:" + WeaponDB.STARTING_WEAPON)
	assert_true(pd.bag.is_empty(), "inventaire vide au départ")
	var other := s.create(6)
	s.apply_loadout(6)
	assert_eq(other.weapons[0].id, WeaponDB.STARTING_WEAPON, "rien d'annoncé : arme de départ par défaut")
	assert_eq(other.level, 1)
	s.queue_free()


# --------------------------------------------------------------------------
# Réapparition et à terre : l'inventaire de partie reste
# --------------------------------------------------------------------------

func test_respawn_keeps_bag_and_versions() -> void:
	var pd := _pd(5)
	var a := GameWeapon.make("mp40", 2)
	a.uid = "w1"
	var b := GameWeapon.make("mp40", 4)
	b.uid = "w2"
	pd.bag = [GameWeapon.make("m14", 3)]
	pd.saved_weapons = [a, b]
	var used: Dictionary = b.duplicate(true)
	used.mag = 1
	pd.weapons = [used]
	pd.life = PlayerData.Life.DEAD
	MatchRules.respawn(pd)
	assert_eq(pd.weapons.size(), 2)
	assert_eq(pd.weapons[0].mag, a.mag, "l'autre version n'est pas touchée")
	assert_eq(pd.weapons[1].mag, 1, "la version utilisée à terre revient avec ses munitions")
	assert_eq(pd.bag.size(), 1, "inventaire gardé")
	assert_eq(pd.bag[0].id, "m14")


func test_downed_with_empty_hands_returns_the_loaned_pistol() -> void:
	var pd := _pd(5)
	pd.weapons = []
	pd.bag = [GameWeapon.make("mp40")]
	pd.saved_weapons = pd.weapons.duplicate(true)
	pd.weapons = [DownedSystem.last_stand_weapon(pd.saved_weapons)]
	assert_true(pd.weapons[0].get("loaned", false), "pistolet prêté à terre")
	MatchRules.restore_saved_weapons(pd)
	assert_true(pd.weapons.is_empty(), "pistolet prêté repris")
	assert_eq(pd.bag.size(), 1)


# --------------------------------------------------------------------------
# Textes
# --------------------------------------------------------------------------

func test_texts_fr_en() -> void:
	var w := GameWeapon.make("mp40", 3, OwnedWeapon.Rarity.EPIC, [_part(2, {})])
	var was: String = Settings.language
	Settings.language = "fr"
	assert_eq(Hud.weapon_info_text(w), "NIV. 3 · ÉPIQUE · SCORE 5")
	assert_eq(InventoryPanel.slot_info(w, 2), "NIV. 3 · ÉPIQUE · SCORE 5 · NIVEAU 3 REQUIS")
	Settings.language = "en"
	assert_eq(Hud.weapon_info_text(w), "LVL 3 · EPIC · SCORE 5")
	assert_eq(InventoryPanel.slot_info(w, 3), "LVL 3 · EPIC · SCORE 5")
	Settings.language = was
	for r in GameWeapon.RARITY_NAMES:
		assert_eq(r.size(), 2, "rareté : nom FR et EN")
	assert_eq(GameWeapon.RARITY_COLORS.size(), OwnedWeapon.RARITY_KEYS.size())
