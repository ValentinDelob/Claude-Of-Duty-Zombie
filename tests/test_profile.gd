extends TestCase
## Profil du joueur (PlayerProfile, OwnedWeapon, WeaponPart, BaseWeapons,
## ProfileStore, MatchXp) : courbe d'XP, plafonds, arsenal, pièces,
## échantillons, score, emplacements, montage, sauvegarde et fichiers abîmés.

## Fichier propre à ce processus (les tests ne touchent jamais au vrai profil).
var file := "user://profile_unittest_%d.json" % OS.get_process_id()


func before_each() -> void:
	ProfileStore.reset(file)


func after_each() -> void:
	ProfileStore.reset(file)


func _write(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


## Fichiers mis de côté à côté de `file` (« .corrupt-… », « .invalid-… »).
func _aside(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	for n in DirAccess.get_files_at("user://"):
		if n.begins_with(file.get_file() + "." + kind + "-"):
			out.append(n)
	return out


# --------------------------------------------------------------------------
# XP et niveau
# --------------------------------------------------------------------------

func test_courbe_xp() -> void:
	assert_eq(PlayerProfile.xp_to_next(1), 100, "niveau 1 → 2 : 100 XP")
	assert_eq(PlayerProfile.xp_to_next(10), roundi(100.0 * pow(10.0, 1.8)))
	assert_true(absi(PlayerProfile.xp_to_next(10) - 6310) <= 1, "≈ 6 300 au niveau 10")
	assert_true(absi(PlayerProfile.xp_to_next(49) - 110000) < 1000, "≈ 110 000 au niveau 49 (%d)" % PlayerProfile.xp_to_next(49))
	assert_eq(PlayerProfile.xp_for_level(1), 0)
	assert_eq(PlayerProfile.xp_for_level(2), 100)
	assert_eq(PlayerProfile.xp_for_level(3), 100 + PlayerProfile.xp_to_next(2))
	for l in range(2, PlayerProfile.MAX_LEVEL + 1):
		assert_eq(PlayerProfile.xp_for_level(l) - PlayerProfile.xp_for_level(l - 1), PlayerProfile.xp_to_next(l - 1))
	assert_eq(PlayerProfile.level_for_xp(0), 1)
	assert_eq(PlayerProfile.level_for_xp(99), 1)
	assert_eq(PlayerProfile.level_for_xp(100), 2)
	assert_eq(PlayerProfile.level_for_xp(PlayerProfile.xp_for_level(10) - 1), 9)
	assert_eq(PlayerProfile.level_for_xp(PlayerProfile.xp_for_level(10)), 10)


func test_ajout_xp_et_niveaux() -> void:
	var pr := PlayerProfile.new()
	assert_eq(pr.level(), 1)
	assert_eq(pr.xp_to_next_level(), 100)
	assert_eq(pr.add_xp(0), 0, "XP nulle ignorée")
	assert_eq(pr.add_xp(-50), 0, "XP négative ignorée")
	assert_eq(pr.xp, 0)
	assert_eq(pr.add_xp(60), 0)
	assert_eq(pr.xp_in_level(), 60)
	assert_eq(pr.xp_to_next_level(), 40)
	assert_eq(pr.add_xp(40 + PlayerProfile.xp_to_next(2)), 2, "deux niveaux d'un coup")
	assert_eq(pr.level(), 3)
	assert_eq(pr.xp_in_level(), 0)


func test_niveau_max_xp_continue() -> void:
	var pr := PlayerProfile.new()
	var cap := PlayerProfile.xp_for_level(PlayerProfile.MAX_LEVEL)
	assert_eq(pr.add_xp(cap - 1), PlayerProfile.MAX_LEVEL - 2)
	assert_eq(pr.level(), PlayerProfile.MAX_LEVEL - 1)
	assert_eq(pr.add_xp(1), 1)
	assert_eq(pr.level(), 50)
	assert_true(pr.is_max_level())
	assert_eq(pr.add_xp(5000), 0, "plus de niveau au-delà de 50")
	assert_eq(pr.level(), 50)
	assert_eq(pr.xp, cap + 5000, "l'XP continue d'être comptée")
	assert_eq(pr.xp_in_level(), 5000)
	assert_eq(pr.xp_to_next_level(), 0)
	pr.add_xp(PlayerProfile.VALUE_CAP)
	pr.add_xp(PlayerProfile.VALUE_CAP)
	assert_eq(pr.xp, PlayerProfile.VALUE_CAP, "plafond technique, pas de débordement")


# --------------------------------------------------------------------------
# Armes possédées : score, emplacements, montage
# --------------------------------------------------------------------------

func test_emplacements_selon_rarete() -> void:
	assert_eq(OwnedWeapon.slots_for(OwnedWeapon.Rarity.COMMON), 1)
	assert_eq(OwnedWeapon.slots_for(OwnedWeapon.Rarity.RARE), 2)
	assert_eq(OwnedWeapon.slots_for(OwnedWeapon.Rarity.EPIC), 3)
	assert_eq(OwnedWeapon.slots_for(OwnedWeapon.Rarity.LEGENDARY), 4)
	assert_eq(OwnedWeapon.slots_for(OwnedWeapon.Rarity.UNIQUE), 4)
	var w := OwnedWeapon.create("galil", 10, OwnedWeapon.Rarity.RARE)
	assert_eq(w.slot_count(), 2)
	assert_true(w.mount(WeaponPart.create("a", 5), 10))
	assert_true(w.mount(WeaponPart.create("b", 5), 10))
	assert_eq(w.free_slots(), 0)
	assert_false(w.mount(WeaponPart.create("c", 5), 10), "plus d'emplacement libre")


func test_score() -> void:
	# Exemple du concept : légendaire niveau 25, pièces 22 + 25 + 19 + 24 → 115.
	var w := OwnedWeapon.create("aug", 25, OwnedWeapon.Rarity.LEGENDARY)
	assert_eq(w.score(), 25, "sans pièce : le niveau")
	for l in [22, 25, 19, 24]:
		assert_true(w.mount(WeaponPart.create("x", l), 30))
	assert_eq(w.score(), 115)


func test_regle_de_montage() -> void:
	var w := OwnedWeapon.create("mp40", 10, OwnedWeapon.Rarity.EPIC)
	assert_false(w.can_mount(WeaponPart.create("a", 11), 50), "pièce plus haute que l'arme")
	assert_false(w.can_mount(WeaponPart.create("a", 8), 7), "pièce plus haute que le joueur")
	assert_true(w.can_mount(WeaponPart.create("a", 10), 10), "égalités acceptées")
	assert_false(w.can_mount(null, 50))
	var p := WeaponPart.create("a", 3)
	p.uid = "p1"
	assert_true(w.mount(p, 10))
	assert_false(w.mount(p, 10), "même pièce deux fois")
	assert_eq(w.unmount("p1"), p)
	assert_eq(w.unmount("p1"), null)
	assert_eq(w.parts.size(), 0)


func test_niveaux_bornes() -> void:
	assert_eq(OwnedWeapon.create("x", 0).level, 1)
	assert_eq(OwnedWeapon.create("x", 99).level, PlayerProfile.MAX_LEVEL)
	assert_eq(WeaponPart.create("x", -3).level, 1)
	var m := WeaponPart.clean_mods({"damage": 0.25, "rate": -0.05, "bad": "x", 3: 1.0, "inf": INF})
	assert_eq(m, {"damage": 0.25, "rate": -0.05})


# --------------------------------------------------------------------------
# Profil : arsenal, pièces, échantillons
# --------------------------------------------------------------------------

func test_arsenal_illimite_et_versions() -> void:
	var pr := PlayerProfile.new()
	var uids := {}
	for i in 300:
		var uid := pr.add_weapon(OwnedWeapon.create("galil", 1 + i % 50))
		assert_true(uid != "" and not uids.has(uid), "identifiant unique")
		uids[uid] = true
	assert_eq(pr.weapons.size(), 300, "aucune limite")
	assert_eq(pr.versions_of("galil").size(), 300, "plusieurs versions coexistent")
	assert_eq(pr.add_weapon(null), "")
	assert_eq(pr.add_weapon(OwnedWeapon.create("")), "", "arme sans identifiant refusée")


func test_ajout_retrait_arme() -> void:
	var pr := PlayerProfile.new()
	var w := OwnedWeapon.create("galil", 4)
	var uid := pr.add_weapon(w)
	assert_eq(pr.add_weapon(w), uid, "le même objet n'est pas rangé deux fois")
	var copy := OwnedWeapon.create("galil", 4)
	copy.uid = uid
	assert_true(pr.add_weapon(copy) != uid, "identifiant déjà pris : nouvel identifiant")
	assert_eq(pr.get_weapon(uid), w)
	assert_true(pr.is_recyclable(uid))
	assert_eq(pr.remove_weapon(uid), w)
	assert_eq(pr.remove_weapon(uid), null)
	assert_eq(pr.get_weapon(uid), null)
	assert_eq(pr.weapons.size(), 1)


func test_utilisation_selon_niveau() -> void:
	var pr := PlayerProfile.new()
	var w := OwnedWeapon.create("m14", 5)
	pr.add_weapon(w)
	assert_false(pr.can_use(w), "arme gardée pour plus tard")
	pr.add_xp(PlayerProfile.xp_for_level(5))
	assert_true(pr.can_use(w))


func test_pieces_onglet_et_montage() -> void:
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(10))
	var wuid := pr.add_weapon(OwnedWeapon.create("galil", 8, OwnedWeapon.Rarity.RARE))
	var ok_uid := pr.add_part(WeaponPart.create("canon", 8, {"damage": 0.25}))
	var high_uid := pr.add_part(WeaponPart.create("crosse", 9))
	assert_eq(pr.parts.size(), 2)
	assert_eq(pr.add_part(null), "")
	assert_false(pr.mount_part(wuid, high_uid), "pièce 9 sur arme 8 refusée")
	assert_eq(pr.parts.size(), 2, "pièce refusée restée dans l'onglet")
	assert_true(pr.mount_part(wuid, ok_uid))
	assert_eq(pr.parts.size(), 1, "pièce montée sortie de l'onglet")
	assert_eq(pr.get_weapon(wuid).score(), 16)
	assert_false(pr.mount_part(wuid, ok_uid), "déjà montée")
	assert_false(pr.mount_part("w999", high_uid), "arme inconnue")
	assert_false(pr.mount_part("base:m1911", high_uid), "pas de pièce sur une arme de base")
	assert_true(pr.unmount_part(wuid, ok_uid))
	assert_eq(pr.parts.size(), 1, "pièce retirée détruite, pas rangée")
	assert_eq(pr.get_part(ok_uid), null)
	assert_eq(pr.remove_part(high_uid).part_id, "crosse")
	assert_eq(pr.parts.size(), 0)
	# Niveau du joueur : pièce 8 sur arme 8 refusée à un joueur niveau 5.
	var low := PlayerProfile.new()
	low.add_xp(PlayerProfile.xp_for_level(5))
	var w2 := low.add_weapon(OwnedWeapon.create("galil", 8))
	var p2 := low.add_part(WeaponPart.create("canon", 8))
	assert_false(low.mount_part(w2, p2), "joueur sous le niveau de la pièce")


func test_echantillons() -> void:
	var pr := PlayerProfile.new()
	assert_eq(pr.sample_count("griffe"), 0)
	assert_eq(pr.add_samples("griffe", 200), 200)
	assert_eq(pr.add_samples("griffe", 0), 200)
	assert_eq(pr.add_samples("griffe", -5), 200)
	assert_eq(pr.add_samples("", 5), 0, "type vide refusé")
	pr.add_samples("croc", 5)
	pr.add_samples("poils", 3)
	# Contrat : seule la quantité demandée est consommée (§4.2).
	assert_true(pr.consume_samples({"griffe": 50}))
	assert_eq(pr.sample_count("griffe"), 150)
	# Tout ou rien.
	assert_false(pr.consume_samples({"croc": 5, "poils": 4}))
	assert_eq(pr.sample_count("croc"), 5, "rien retiré s'il en manque")
	assert_true(pr.consume_samples({"croc": 5, "poils": 3}))
	assert_false(pr.samples.has("croc"), "quantité nulle effacée")
	assert_false(pr.has_samples({"griffe": -1}), "quantité négative refusée")
	assert_true(pr.remove_samples("griffe", 150))
	assert_false(pr.remove_samples("griffe", 1))
	pr.add_samples("croc", PlayerProfile.VALUE_CAP)
	pr.add_samples("croc", PlayerProfile.VALUE_CAP)
	assert_eq(pr.sample_count("croc"), PlayerProfile.VALUE_CAP, "pas de débordement")


# --------------------------------------------------------------------------
# Armes de base et de départ
# --------------------------------------------------------------------------

func test_armes_de_base() -> void:
	var ids := BaseWeapons.ids()
	assert_eq(ids.size(), 2, "pistolet et couteau (provisoire)")
	assert_true(WeaponDB.exists(ids[0]), "pistolet de départ du jeu")
	assert_true(KnifeDB.KNIVES.has(ids[1]), "couteau en attendant la batte")
	for w in BaseWeapons.all():
		assert_eq(w.level, 1)
		assert_eq(w.rarity, OwnedWeapon.Rarity.COMMON)
		assert_eq(w.parts.size(), 0)
		assert_true(w.uid.begins_with(BaseWeapons.UID_PREFIX))
	assert_eq(BaseWeapons.make("galil"), null)
	var pr := PlayerProfile.new()
	var buid := BaseWeapons.UID_PREFIX + ids[0]
	assert_true(pr.get_weapon(buid) != null, "toujours disponible")
	assert_false(pr.is_recyclable(buid), "non recyclable")
	assert_eq(pr.remove_weapon(buid), null)
	# Arme de base améliorée ramenée : nouvel exemplaire, la base reste.
	var up := BaseWeapons.make(ids[0])
	up.level = 3
	var nuid := pr.add_weapon(up)
	assert_true(nuid != buid and not nuid.begins_with(BaseWeapons.UID_PREFIX))
	assert_true(pr.get_weapon(buid) != null)


func test_selection_de_depart() -> void:
	var pr := PlayerProfile.new()
	assert_true(BaseWeapons.selection_ok(pr.starting_weapons), "défaut valide")
	assert_eq(pr.starting_loadout().size(), pr.starting_weapons.size())
	var ids := BaseWeapons.ids()
	assert_true(pr.set_starting_weapons([ids[1]]))
	assert_eq(pr.starting_weapons, PackedStringArray([ids[1]]))
	assert_false(pr.set_starting_weapons([]), "au moins une arme")
	assert_false(pr.set_starting_weapons([ids[0], ids[0]]), "doublon")
	assert_false(pr.set_starting_weapons(["galil"]), "pas une arme de base")
	assert_false(pr.set_starting_weapons([ids[0], ids[1], ids[0], ids[1]]), "plus de 3")
	assert_false(pr.set_starting_weapons("m1911"))
	assert_eq(pr.starting_weapons, PackedStringArray([ids[1]]), "inchangée après un refus")
	assert_eq(BaseWeapons.clean_selection(["x", 3]), BaseWeapons.default_selection())


# --------------------------------------------------------------------------
# Sauvegarde
# --------------------------------------------------------------------------

func _sample_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.add_xp(12345)
	var w := OwnedWeapon.create("galil", 7, OwnedWeapon.Rarity.UNIQUE)
	pr.add_weapon(w)
	pr.add_weapon(OwnedWeapon.create("galil", 2))
	pr.add_part(WeaponPart.create("canon", 6, {"damage": 0.25, "rate": -0.05}))
	pr.mount_part(w.uid, pr.parts[0].uid)
	pr.add_part(WeaponPart.create("viseur", 4))
	pr.add_samples("griffe", 42)
	pr.set_starting_weapons([BaseWeapons.ids()[1]])
	return pr


func test_sauvegarde_et_rechargement() -> void:
	var pr := _sample_profile()
	assert_eq(ProfileStore.save_profile(pr, file), OK)
	var back := ProfileStore.load_profile(file)
	assert_eq(ProfileStore.last_status, "ok")
	assert_eq(back.to_dict(), pr.to_dict(), "profil identique après rechargement")
	assert_eq(back.xp, 12345)
	assert_eq(back.weapons[0].rarity, OwnedWeapon.Rarity.UNIQUE)
	assert_eq(back.weapons[0].parts[0].mods, {"damage": 0.25, "rate": -0.05})
	assert_eq(back.weapons[0].score(), 13)
	# Identifiants jamais réutilisés après rechargement.
	var nuid := back.add_weapon(OwnedWeapon.create("galil"))
	for w in pr.weapons:
		assert_true(w.uid != nuid)
	assert_false(FileAccess.file_exists(file + ".tmp"), "pas de fichier temporaire restant")


func test_profil_absent() -> void:
	var pr := ProfileStore.load_profile(file)
	assert_eq(ProfileStore.last_status, "new")
	assert_eq(pr.xp, 0)
	assert_eq(pr.level(), 1)


func test_copie_de_secours() -> void:
	var pr := _sample_profile()
	ProfileStore.save_profile(pr, file)
	assert_false(FileAccess.file_exists(file + ".bak"), "pas de copie au premier enregistrement")
	pr.add_xp(1000)
	ProfileStore.save_profile(pr, file)
	assert_true(FileAccess.file_exists(file + ".bak"), "ancien fichier gardé en copie")
	assert_true(ProfileStore.read_file(file + ".bak").profile.xp == 12345)
	# Fichier principal abîmé : copie de secours lue, fichier abîmé mis de côté.
	_write(file, "{\"format\": \"profile\", \"version\": 1, \"profile\": {\"xp\": 13")
	var back := ProfileStore.load_profile(file)
	assert_eq(ProfileStore.last_status, "backup")
	assert_eq(back.xp, 12345)
	assert_eq(_aside("corrupt").size(), 1, "fichier abîmé gardé")
	assert_false(FileAccess.file_exists(file))
	# Enregistrement suivant : la copie de secours n'est pas écrasée par du vide.
	assert_eq(ProfileStore.save_profile(back, file), OK)
	assert_eq(ProfileStore.read_file(file + ".bak").profile.xp, 12345)
	assert_eq(ProfileStore.load_profile(file).xp, 12345)


func test_fichier_corrompu_sans_copie() -> void:
	for text in ["", "pas du json", "[1, 2]", "{\"format\": \"autre\", \"version\": 1, \"profile\": {}}",
			"{\"format\": \"profile\", \"profile\": {}}",
			"{\"format\": \"profile\", \"version\": 1, \"profile\": 3}"]:
		ProfileStore.reset(file)
		_write(file, text)
		var pr := ProfileStore.load_profile(file)
		assert_eq(ProfileStore.last_status, "reset", "« %s »" % text)
		assert_eq(pr.xp, 0)
		assert_eq(_aside("corrupt").size(), 1, "fichier gardé : « %s »" % text)
	# Le fichier mis de côté n'est jamais écrasé par l'enregistrement suivant.
	ProfileStore.save_profile(PlayerProfile.new(), file)
	assert_eq(_read("user://" + _aside("corrupt")[0]), "{\"format\": \"profile\", \"version\": 1, \"profile\": 3}")


func test_version_plus_recente() -> void:
	_write(file, JSON.stringify({"format": "profile", "version": ProfileStore.VERSION + 1, "profile": {"xp": 500}}))
	var pr := ProfileStore.load_profile(file)
	assert_eq(ProfileStore.last_status, "reset")
	assert_eq(pr.xp, 0)
	assert_eq(_aside("corrupt").size(), 1, "fichier d'une version plus récente gardé")


func test_entrees_illisibles_ecartees() -> void:
	var doc := {"format": "profile", "version": 1, "profile": {
		"xp": 250.0, "next_uid": 3,
		"starting_weapons": ["galil"],
		"samples": {"griffe": 7.0, "croc": -2, "": 5, "poils": "x"},
		"weapons": [
			{"uid": "w1", "id": "galil", "level": 99, "rarity": "rare", "parts": [
				{"uid": "p2", "id": "a", "level": 3, "mods": {"damage": 0.1}},
				{"uid": "p3", "id": "b", "level": 3},
				{"uid": "p4", "id": "c", "level": 3}]},
			{"uid": "w1", "id": "galil", "level": 2, "rarity": "common"},
			{"id": "galil", "level": 2, "rarity": "mythique"},
			"texte",
			{"uid": "w9", "id": "", "rarity": "common"}],
		"parts": [{"uid": "p2", "id": "d", "level": 1}, {"level": 2}, 7],
	}}
	_write(file, JSON.stringify(doc))
	var pr := ProfileStore.load_profile(file)
	assert_eq(ProfileStore.last_status, "ok")
	assert_eq(pr.xp, 250)
	assert_eq(pr.starting_weapons, BaseWeapons.default_selection(), "sélection invalide : défaut")
	assert_eq(pr.samples, {"griffe": 7})
	assert_eq(pr.weapons.size(), 2)
	assert_eq(pr.weapons[0].level, PlayerProfile.MAX_LEVEL, "niveau borné")
	assert_eq(pr.weapons[0].parts.size(), 2, "pas plus de pièces que d'emplacements")
	assert_true(pr.weapons[1].uid != "w1", "identifiant en double remplacé")
	assert_eq(pr.parts.size(), 1)
	assert_true(pr.parts[0].uid != "p2", "identifiant de pièce en double remplacé")
	var uids := {}
	for w in pr.weapons:
		uids[w.uid] = true
		for p in w.parts:
			uids[p.uid] = true
	for p in pr.parts:
		uids[p.uid] = true
	assert_eq(uids.size(), 5, "tous les identifiants distincts")
	assert_eq(_aside("invalid").size(), 1, "copie du fichier d'origine gardée")
	assert_true(FileAccess.file_exists(file), "fichier lisible laissé en place")


func test_securite_pas_d_objet() -> void:
	# Un fichier JSON ne peut pas décoder d'objet : le texte reste du texte.
	_write(file, "{\"format\": \"profile\", \"version\": 1, \"profile\": {\"xp\": \"Object(Node)\"," \
			+ " \"weapons\": [{\"id\": \"Resource(\\\"res://x.gd\\\")\", \"rarity\": \"common\"}]}}")
	var pr := ProfileStore.load_profile(file)
	assert_eq(pr.xp, 0)
	assert_eq(pr.weapons.size(), 0, "identifiant invalide écarté")


# --------------------------------------------------------------------------
# XP de partie
# --------------------------------------------------------------------------

func test_xp_de_partie() -> void:
	assert_eq(MatchXp.match_xp(0, 0), 0)
	assert_eq(MatchXp.match_xp(150, 11), 150 * MatchXp.XP_PER_KILL + 11 * MatchXp.XP_PER_ROUND)
	assert_eq(MatchXp.match_xp(-3, -1), 0)
	var r := MatchXp.apply_match_xp(8, 1, file)
	assert_eq(r.xp, 8 * MatchXp.XP_PER_KILL + MatchXp.XP_PER_ROUND)
	assert_eq(r.level_before, 1)
	assert_eq(r.level_after, PlayerProfile.level_for_xp(r.xp))
	assert_eq(ProfileStore.load_profile(file).xp, r.xp, "XP enregistrée")
	MatchXp.apply_match_xp(2, 0, file)
	assert_eq(ProfileStore.load_profile(file).xp, r.xp + 2 * MatchXp.XP_PER_KILL, "XP cumulée")
	# Calibrage provisoire (§4.15 : niveau 10 vers 3 h) : une partie type de
	# 20 min rapporte entre 5 % et 20 % de l'XP du niveau 10.
	var game := MatchXp.match_xp(150, 11)
	var lvl10 := PlayerProfile.xp_for_level(10)
	assert_true(game * 5 <= lvl10 and game * 20 >= lvl10, "partie %d XP, niveau 10 à %d XP" % [game, lvl10])
