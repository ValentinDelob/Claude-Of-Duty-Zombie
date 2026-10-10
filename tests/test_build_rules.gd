extends TestCase
## Station de construction (GAME_CONCEPT §4.11, §4.12) : prix et durée
## (BuildRules), recharge, recyclage, contrôle d'une demande de construction,
## liste de la station, armes rapportées au profil à l'évacuation
## (ProfileLoot), modèle en blocs sur la grille de 5 cm, objet de carte
## obligatoire (validateur, export, cartes livrées).

const PISTOL := WeaponDB.STARTING_WEAPON


func _w(id: String, lvl := 1, r := 0, parts: Array = [], uid := "") -> Dictionary:
	return GameWeapon.make(id, lvl, r, parts, uid)


# --------------------------------------------------------------------------
# Prix, durée, recharge, recyclage
# --------------------------------------------------------------------------

func test_prix() -> void:
	assert_eq(BuildRules.price(_w(PISTOL, 1, 0, [], BaseWeapons.UID_PREFIX + PISTOL)), 500, "arme de base niveau 1 commune")
	assert_eq(BuildRules.price(_w("mp40", 10, OwnedWeapon.Rarity.RARE)), 1760, "niveau 10 rare : 500 × 2,35 × 1,5")
	assert_eq(BuildRules.price(_w("mp40", 50, OwnedWeapon.Rarity.UNIQUE)), 16700, "niveau 50 unique : 500 × 8,35 × 4")
	assert_eq(BuildRules.price({}), 0)
	# Croît avec le niveau et avec la rareté.
	for r in 5:
		var last := 0
		for lvl in range(1, 51):
			var p := BuildRules.price(_w("mp40", lvl, r))
			assert_true(p > last, "rareté %d : niveau %d plus cher (%d > %d)" % [r, lvl, p, last])
			last = p
	for lvl in [1, 7, 30]:
		var last := 0
		for r in 5:
			var p := BuildRules.price(_w("mp40", lvl, r))
			assert_true(p > last, "niveau %d : rareté %d plus chère" % [lvl, r])
			last = p
	# Les pièces ne changent pas le prix (provisoire).
	assert_eq(BuildRules.price(_w("mp40", 5, 1, [{"id": "c", "level": 5, "mods": {"damage": 0.2}}])), BuildRules.price(_w("mp40", 5, 1)))
	var o := OwnedWeapon.create("mp40", 10, OwnedWeapon.Rarity.RARE)
	assert_eq(BuildRules.owned_price(o), 1760, "prix d'un exemplaire du profil")


func test_duree() -> void:
	assert_eq(BuildRules.rounds(500), 1)
	assert_eq(BuildRules.rounds(1490), 1)
	assert_eq(BuildRules.rounds(1500), 2)
	assert_eq(BuildRules.rounds(3990), 2)
	assert_eq(BuildRules.rounds(4000), 3)
	assert_eq(BuildRules.rounds(16700), 3, "jamais plus de 3 manches")
	# Prête à la fin de la manche en cours (+ durée − 1).
	assert_eq(BuildRules.ready_round(3, true, 500), 3, "1 manche, pendant la manche 3 : fin de la manche 3")
	assert_eq(BuildRules.ready_round(3, false, 500), 4, "entre les manches 3 et 4 : fin de la manche 4")
	assert_eq(BuildRules.ready_round(0, false, 500), 1, "avant la manche 1 : fin de la manche 1")
	assert_eq(BuildRules.ready_round(3, true, 2000), 4, "2 manches")
	assert_eq(BuildRules.ready_round(3, true, 5000), 5, "3 manches")
	assert_eq(BuildRules.rounds_text(1), Lang.t("1 manche", "1 round"))
	assert_eq(BuildRules.rounds_text(3), Lang.t("3 manches", "3 rounds"))


func test_recharge() -> void:
	var w := _w(PISTOL)
	assert_eq(BuildRules.refill_price(w), 150, "30 % de 500")
	assert_eq(BuildRules.refill_price(_w("mp40", 10, 1)), 530, "30 % de 1 760, arrondi à 10")
	assert_true(BuildRules.ammo_full(w), "arme neuve : pleine")
	w.mag = 0
	assert_false(BuildRules.ammo_full(w), "chargeur vide")
	GameWeapon.refill(w)
	w.reserve = 1
	assert_false(BuildRules.ammo_full(w), "réserve entamée")
	assert_true(BuildRules.ammo_full({}), "rien en main : rien à recharger")


func test_recyclage_valeur() -> void:
	assert_eq(BuildRules.recycle_value(_w(PISTOL, 1, 0, [], BaseWeapons.UID_PREFIX + PISTOL)), 0, "arme de base : rien")
	assert_eq(BuildRules.recycle_value(_w("mp40", 1, 0, [], "w1")), 250, "50 % de 500")
	assert_eq(BuildRules.recycle_value(_w("mp40", 10, 1, [], "w1")), 880, "50 % de 1 760")
	assert_eq(BuildRules.recycle_value(_w("mp40", 3, 2)), 720, "arme ramassée (sans exemplaire) : 50 % de 1 430, arrondi à 10")
	var loaned := _w(PISTOL)
	loaned["loaned"] = true
	assert_eq(BuildRules.recycle_value(loaned), 0, "arme prêtée")


func test_recyclage_retire() -> void:
	var pd := PlayerData.new(1)
	pd.weapons = [_w(PISTOL), _w("mp40", 2, 0, [], "w1"), _w("m14", 3, 0, [], "w2")]
	pd.slot = 2
	pd.bag = [_w("mp40", 4, 1, [], "w3")]
	assert_eq(BuildRules.recycle_refusal(pd, 1, 1), "place vide")
	assert_eq(BuildRules.recycle_refusal(pd, 2, 0), "place vide", "rangée inconnue")
	var w := BuildRules.take(pd, 0, 0)
	assert_eq(String(w.id), PISTOL, "arme retirée rendue")
	assert_eq(pd.weapons.size(), 2)
	assert_eq(String(pd.current_weapon().uid), "w2", "l'arme tenue reste la même (emplacement décalé)")
	w = BuildRules.take(pd, 0, 1)
	assert_eq(String(w.uid), "w2")
	assert_eq(pd.slot, 0, "arme tenue recyclée : emplacement borné")
	w = BuildRules.take(pd, 1, 0)
	assert_eq(String(w.uid), "w3")
	assert_true(pd.bag.is_empty())
	assert_eq(BuildRules.recycle_refusal(pd, 0, 0), BuildRules.LAST_WEAPON, "dernière arme")
	assert_true(BuildRules.take(pd, 0, 0).is_empty() and pd.weapons.size() == 1, "dernière arme : rien retiré")
	pd.bag = [_w("m14", 1, 0, [], "w4")]
	w = BuildRules.take(pd, 0, 0)
	assert_true(pd.weapons.is_empty() and pd.slot == 0, "mains vides permises (une arme reste dans l'inventaire)")
	pd.weapons = [_w(PISTOL)]
	pd.weapons[0]["loaned"] = true
	assert_eq(BuildRules.recycle_refusal(pd, 0, 0), "arme prêtée")
	assert_true(BuildRules.take(pd, 0, 0).is_empty() and pd.weapons.size() == 1, "refus : rien retiré")
	pd.weapons[0].erase("loaned")
	pd.life = PlayerData.Life.DOWNED
	assert_eq(BuildRules.recycle_refusal(pd, 0, 0), "joueur à terre ou mort")


## Jamais la dernière arme (GAME_CONCEPT §4.12) : armes en main + inventaire,
## hors arme prêtée ; couteau et grenades ne comptent pas ; une arme en
## construction à la station non plus (pas dans PlayerData tant qu'elle n'est
## pas récupérée).
func test_recyclage_derniere_arme() -> void:
	var pd := PlayerData.new(1)
	pd.weapons = [_w(PISTOL, 1, 0, [], BaseWeapons.UID_PREFIX + PISTOL)]
	pd.grenades = 4
	assert_eq(BuildRules.weapon_count(pd), 1, "couteau et grenades ne comptent pas")
	assert_eq(BuildRules.recycle_refusal(pd, 0, 0), BuildRules.LAST_WEAPON, "arme de base seule en main")
	# Mains vides, une seule arme dans le sac.
	pd.weapons = []
	pd.bag = [_w("mp40", 2, 0, [], "w1")]
	assert_eq(BuildRules.recycle_refusal(pd, 1, 0), BuildRules.LAST_WEAPON, "seule arme dans l'inventaire")
	# Une arme en main et une dans le sac : l'une ou l'autre, pas les deux.
	pd.weapons = [_w(PISTOL)]
	assert_eq(BuildRules.weapon_count(pd), 2)
	assert_eq(BuildRules.recycle_refusal(pd, 1, 0), "")
	assert_eq(BuildRules.recycle_refusal(pd, 0, 0), "")
	assert_false(BuildRules.take(pd, 1, 0).is_empty())
	assert_eq(BuildRules.recycle_refusal(pd, 0, 0), BuildRules.LAST_WEAPON, "la seconde devient la dernière")
	# Une arme prêtée ne compte pas : l'arme du sac reste la dernière.
	var loaned := _w(PISTOL)
	loaned["loaned"] = true
	pd.weapons = [loaned]
	pd.bag = [_w("mp40", 2, 0, [], "w2")]
	assert_eq(BuildRules.weapon_count(pd), 1, "arme prêtée non comptée")
	assert_eq(BuildRules.recycle_refusal(pd, 1, 0), BuildRules.LAST_WEAPON)
	assert_eq(BuildRules.recycle_refusal(pd, 0, 0), "arme prêtée", "arme prêtée : refus d'origine")
	assert_true(BuildRules.recycle_refusal_text(BuildRules.LAST_WEAPON) != "", "message pour le joueur")
	assert_eq(BuildRules.recycle_refusal_text("arme prêtée"), "", "autres refus : pas de message")


# --------------------------------------------------------------------------
# Demande de construction
# --------------------------------------------------------------------------

func test_arme_demandee_relue() -> void:
	assert_true(BuildRules.clean_weapon(null).is_empty())
	assert_true(BuildRules.clean_weapon({"id": "inconnue"}).is_empty(), "arme inconnue")
	assert_true(BuildRules.clean_weapon({"id": KnifeDB.DEFAULT}).is_empty(), "arme de mêlée : pas constructible")
	assert_true(BuildRules.clean_weapon({"id": 12}).is_empty(), "mauvais type")
	var w := BuildRules.clean_weapon({"id": "mp40", "level": 999.0, "rarity": 9, "uid": "w7", "mag": 0, "reserve": 99999,
		"parts": [{"id": "a", "level": 3, "mods": {"damage": 0.1, "bidon": 3}}, {"id": "b", "level": 99}, "x",
			{"id": "c", "level": 2}, {"id": "d", "level": 2}, {"id": "e", "level": 2}, {"id": "f", "level": 2}]})
	assert_eq(int(w.level), PlayerProfile.MAX_LEVEL, "niveau borné")
	assert_eq(int(w.rarity), 4, "rareté bornée")
	assert_eq(String(w.uid), "w7", "exemplaire gardé")
	assert_eq((w.parts as Array).size(), 4, "pas plus de pièces que d'emplacements (unique : 4)")
	var s := GameWeapon.stats(w)
	assert_true(int(w.mag) == int(s.mag) and int(w.reserve) == int(s.reserve), "munitions pleines, jamais celles du client")
	var low := BuildRules.clean_weapon({"id": "mp40", "level": 2, "rarity": 1, "parts": [{"id": "a", "level": 3}, {"id": "b", "level": 2}]})
	assert_eq((low.parts as Array).size(), 1, "pièce de niveau supérieur à l'arme écartée")
	assert_eq(BuildRules.clean_weapon({"id": "mp40", "uid": "../x"}).uid, "", "identifiant d'exemplaire nettoyé")


func test_refus_de_construction() -> void:
	var pd := PlayerData.new(1)
	pd.level = 5
	var w := _w("mp40", 5)
	assert_eq(BuildRules.build_refusal(pd, w, false), BuildRules.OK)
	assert_eq(BuildRules.build_refusal(pd, _w("mp40", 6), false), BuildRules.LEVEL, "niveau trop élevé")
	assert_eq(BuildRules.build_refusal(pd, w, true), BuildRules.BUSY, "une construction à la fois")
	assert_eq(BuildRules.build_refusal(pd, {}, false), BuildRules.INVALID)
	assert_eq(BuildRules.build_refusal(null, w, false), BuildRules.INVALID)
	pd.life = PlayerData.Life.DOWNED
	assert_eq(BuildRules.build_refusal(pd, w, false), BuildRules.NOT_ALIVE)
	for code in [BuildRules.LEVEL, BuildRules.BUSY, BuildRules.INVALID]:
		assert_true(InteractionSystem.deny_text(code) != "", "message du refus « %s »" % code)
	assert_true(InteractionSystem.deny_text(InteractionSystem.BAG_FULL).length() > 5)
	assert_true(InteractionSystem.deny_text(InteractionSystem.AMMO_FULL).length() > 5)


func test_liste_de_la_station() -> void:
	var pr := PlayerProfile.new()
	var a := OwnedWeapon.create("mp40", 4, OwnedWeapon.Rarity.RARE)
	pr.add_weapon(a)
	pr.add_weapon(OwnedWeapon.create(KnifeDB.DEFAULT, 2))
	var b := OwnedWeapon.create("m14", 9, OwnedWeapon.Rarity.EPIC)
	pr.add_weapon(b)
	var list := BuildRules.catalog(pr)
	var uids := list.map(func(o): return o.uid)
	assert_eq(uids, [BaseWeapons.UID_PREFIX + PISTOL, a.uid, b.uid], "armes de base (à feu) puis arsenal, sans arme de mêlée")
	assert_eq(BuildRules.catalog(null).size(), 1, "sans profil : armes de base")
	assert_true(StationPanel.row_info(b, 5).contains(Lang.t("NIVEAU 9 REQUIS", "LEVEL 9 REQUIRED")), "niveau requis affiché")
	assert_false(StationPanel.row_info(a, 5).contains(Lang.t("REQUIS", "REQUIRED")), "constructible")
	assert_true(StationPanel.row_info(a, 5).contains("SCORE 4"), "score affiché")


# --------------------------------------------------------------------------
# Évacuation : armes rapportées au profil (ProfileLoot)
# --------------------------------------------------------------------------

func test_evacuation_met_a_jour_la_version() -> void:
	var pr := PlayerProfile.new()
	var built := OwnedWeapon.create("mp40", 3, OwnedWeapon.Rarity.RARE)
	var uid := pr.add_weapon(built)
	var other := OwnedWeapon.create("m14", 5)
	var uid2 := pr.add_weapon(other)
	# Exemplaire construit puis amélioré en partie : niveau et pièce.
	var up := GameWeapon.from_owned(built)
	up.level = 4
	up.parts = [{"id": "canon", "uid": "lootp:1", "level": 4, "mods": {"damage": 0.2}}]
	var same := GameWeapon.from_owned(other)
	var found := _w("m14", 7, OwnedWeapon.Rarity.EPIC, [], "loot:1")
	var base_plain := _w(PISTOL, 1, 0, [], BaseWeapons.UID_PREFIX + PISTOL)
	var base_up := _w(PISTOL, 2, 0, [], BaseWeapons.UID_PREFIX + PISTOL)
	var loaned := _w(PISTOL)
	loaned["loaned"] = true
	var out := ProfileLoot.apply_to(pr, {"weapons": [up, same, found, base_plain, base_up, loaned, {}, {"id": "inconnue"}]})
	assert_eq(out.updated, 1, "version construite et améliorée mise à jour, exemplaire intact : rien")
	assert_eq(out.weapons, 2, "arme ramassée et arme de base améliorée ajoutées")
	var v := pr.get_weapon(uid)
	assert_true(v.level == 4 and v.parts.size() == 1 and v.parts[0].part_id == "canon", "même version, améliorée (niveau et pièce)")
	assert_true(v.parts[0].uid.begins_with("p"), "pièce : identifiant du profil")
	assert_eq(pr.get_weapon(uid2).level, 5, "exemplaire inchangé : version inchangée")
	assert_eq(pr.weapons.size(), 4, "2 versions + 2 armes ajoutées")
	assert_true(pr.weapons.any(func(o): return o.weapon_id == "m14" and o.level == 7), "arme ramassée")
	assert_true(pr.weapons.any(func(o): return o.weapon_id == PISTOL and o.level == 2 and not o.uid.begins_with(BaseWeapons.UID_PREFIX)), "arme de base améliorée : nouvelle version")
	# Deux exemplaires d'une même version : le second, différent, devient une nouvelle version.
	var c1 := GameWeapon.from_owned(pr.get_weapon(uid2))
	c1.level = 6
	var c2 := GameWeapon.from_owned(pr.get_weapon(uid2))
	c2.level = 8
	out = ProfileLoot.apply_to(pr, {"weapons": [c1, c2]})
	assert_eq(out.updated, 1)
	assert_eq(out.weapons, 1, "rien n'est remplacé en silence")
	assert_eq(pr.get_weapon(uid2).level, 6)


func test_evacuation_enregistre() -> void:
	var path := "user://test_profile_loot.json"
	ProfileStore.reset(path)
	var pr := PlayerProfile.new()
	var uid := pr.add_weapon(OwnedWeapon.create("mp40", 2))
	ProfileStore.save_profile(pr, path)
	var w := GameWeapon.from_owned(pr.get_weapon(uid))
	var out := ProfileLoot.apply_evacuation({"weapons": [w]}, path)
	assert_eq(out.updated + out.weapons, 0, "rien de changé")
	w.rarity = OwnedWeapon.Rarity.EPIC
	out = ProfileLoot.apply_evacuation({"weapons": [w]}, path)
	assert_eq(out.updated, 1)
	assert_eq(ProfileStore.load_profile(path).get_weapon(uid).rarity, OwnedWeapon.Rarity.EPIC, "profil enregistré")
	ProfileStore.reset(path)



# --------------------------------------------------------------------------
# Modèle et objet de carte
# --------------------------------------------------------------------------

func test_modele_cubique() -> void:
	var root := Node3D.new()
	var parts := BuildStation.build_model(root)
	assert_true(parts.lamp is MeshInstance3D and parts.screen is MeshInstance3D)
	var r := VoxelCheck.check_scene(root)
	assert_true(r.ok, "modèle sur la grille de 5 cm : %s" % r.fr)
	root.free()


func test_validateur_exige_la_station() -> void:
	var EVAC := preload("res://tests/test_evac_rules.gd")
	var errs := func(m: EditorMap) -> Array:
		var v := MapRaster.build(m).v
		v.analyze()
		return v.errors().map(func(e): return String(e.fr))
	var ok: Array = errs.call(EVAC.small_map(true, false, true))
	assert_true(ok.is_empty(), "carte avec station acceptée : %s" % str(ok))
	var none: Array = errs.call(EVAC.small_map(true, false, false))
	assert_true(none.any(func(e: String): return e.contains("aucune station de construction")), "carte sans station refusée : %s" % str(none))
	var two := EVAC.small_map(true, false, true)
	two.objets.append({"id": "t2", "type": "station", "position": [16.5, 0], "mur": "n", "altitude": 0})
	var e2: Array = errs.call(two)
	assert_true(e2.any(func(e: String): return e.contains("Station de construction") and e.contains("un seul")), "deux stations refusées : %s" % str(e2))
	# Export vers le jeu.
	var d := EditorMapDef.from_map(EVAC.small_map(true, false, true))
	var mk := d.create_layout().build_station()
	assert_true(mk != null, "station transmise au jeu")
	if mk:
		assert_true(mk.wall.z < -0.9, "contre le mur nord (%s)" % str(mk.wall))
	assert_true(EditorMapDef.from_map(EVAC.small_map(true, false, false)).create_layout().build_station() == null, "carte ancienne sans station : aucune")
	# MapTestKit pose la station avec la vraie règle de pose.
	var m := EVAC.small_map(true, false, false)
	MapTestKit.add_station(m)
	assert_true(m.objets.any(func(o): return o.type == "station"), "station posée par MapTestKit")
	assert_true((errs.call(m) as Array).is_empty(), "carte complétée valide : %s" % str(errs.call(m)))


func test_cartes_livrees() -> void:
	for id in Game.MAP_SCRIPTS:
		var def := Game.make_map_def(id)
		var mk := def.create_layout().build_station()
		assert_true(mk != null, "%s : station de construction" % id)
	var grid := Game.make_map_def("test_arena").create_layout()
	assert_eq(grid.build_station().block, "station", "carte grille : établi retiré de la navigation")
	assert_true(EditorMap.FORMAT >= 19, "format 19 : station de construction")
	var draft := EditorMap.load_dir("res://assets/maps/draft_arena/")
	var v := MapRaster.build(draft).v
	v.analyze()
	assert_true(v.errors().is_empty(), "DRAFT ARENA valide : %s" % str(v.errors().map(func(e): return e.fr)))
