extends TestCase
## Contrats du scientifique (ContractRules, ContractState, HubRewards,
## MatchContracts ; docs/HUB_PLAN.md §5.2, §5.3) : rotation sans doublon,
## graine stable, tuto en premier, chaînes « after », non répétables,
## expiration des proposés et des actifs, remplacement de la plus ancienne,
## partie trop courte, remise (consommation exacte, refus, XP D9, récompense
## au niveau du joueur), 3 actifs au plus, objectif atteint en partie.

var file := "user://profile_contracts_unittest_%d.json" % OS.get_process_id()
var day := HubData.parse_day("2026-10-11")


func before_each() -> void:
	ProfileStore.reset(file)


func after_each() -> void:
	ProfileStore.reset(file)


## Catalogue de test : contrats {id: champs en plus} (titre, texte,
## échantillons, XP et récompense par défaut).
func _data(list: Dictionary, rules := {}) -> HubData:
	var cs := []
	for id in list:
		var c := {"id": id, "title": {"fr": "T " + id, "en": "T " + id}, "text": {"fr": "x", "en": "x"},
			"samples": {"dog_fang": 1}, "xp": 100, "reward": {"kind": "none"}}
		c.merge(list[id], true)
		cs.append(c)
	var doc := {"format": "hub_contracts", "version": 1, "contracts": cs}
	if not rules.is_empty():
		doc.rules = rules
	var d := HubData.from_texts(JSON.stringify(doc), "{\"format\": \"hub_exchanges\", \"version\": 1, \"exchanges\": []}")
	assert_eq(d.warnings.size(), 0, "catalogue de test valide : %s" % d.warnings)
	return d


## Catalogue de `n` contrats simples c0…c(n-1).
func _many(n: int) -> HubData:
	var list := {}
	for i in n:
		list["c%d" % i] = {}
	return _data(list)


func _state(s := 1234) -> ContractState:
	var st := ContractState.new()
	st.draw_seed = s
	return st


func _all_ids(st: ContractState) -> PackedStringArray:
	return st.offered_ids() + st.active_ids()


func _unique(ids: PackedStringArray) -> bool:
	var seen := {}
	for id in ids:
		if seen.has(id):
			return false
		seen[id] = true
	return true


# --------------------------------------------------------------------------
# Rotation
# --------------------------------------------------------------------------

func test_premier_remplissage_fichiers_livres() -> void:
	var data := HubData.load_files(HubData.CONTRACTS_PATH, HubData.EXCHANGES_PATH)
	var st := _state()
	var res := ContractRules.rotate(st, data, 1, day, false)
	assert_true(res.filled, "première ouverture : tableau rempli")
	assert_eq(st.rotation, 1)
	assert_eq(st.offered_ids(), PackedStringArray(["first_sample", "dog_fangs_small"]),
			"niveau 1 : le tuto en premier, puis le seul autre contrat éligible")
	# Niveau 3 : contrats des niveaux 2 et 3, mais pas pack_analysis (après first_sample).
	st = _state()
	ContractRules.rotate(st, data, 3, day, false)
	assert_eq(st.offers.size(), 4, "%s" % st.offered_ids())
	assert_eq(st.offers[0].id, "first_sample")
	assert_false(st.is_offered("pack_analysis"), "chaîne after non remplie")
	assert_false(st.is_offered("lab_emergency"), "contrat daté pas encore commencé")
	# Ouverture suivante du hub : purge seulement.
	var before := st.offered_ids()
	res = ContractRules.rotate(st, data, 3, day, false)
	assert_false(res.filled)
	assert_eq(st.offered_ids(), before)
	assert_eq(st.rotation, 1)


func test_rotation_sans_doublon() -> void:
	var data := _many(12)
	var st := _state()
	ContractRules.rotate(st, data, 1, day, false)
	assert_eq(st.offers.size(), 5)
	for i in 40:
		# Accepte de temps en temps, abandonne parfois, remet parfois.
		if i % 3 == 0 and not st.offers.is_empty():
			ContractRules.accept(st, data, st.offers[0].id, day)
		if i % 7 == 0 and not st.active.is_empty():
			ContractRules.abandon(st, st.active[0].id)
		ContractRules.rotate(st, data, 1, day, true)
		assert_true(_unique(_all_ids(st)), "aucun doublon (rotation %d) : %s" % [st.rotation, _all_ids(st)])
		assert_eq(st.offers.size(), 5, "5 propositions")
		assert_true(st.active.size() <= 3)


func test_graine_stable() -> void:
	var data := _many(12)
	var a := _state(42)
	var b := _state(42)
	var c := _state(43)
	var seq_a := []
	var seq_c := []
	for i in 6:
		ContractRules.rotate(a, data, 1, day, true)
		ContractRules.rotate(b, data, 1, day, true)
		ContractRules.rotate(c, data, 1, day, true)
		seq_a.append(a.offered_ids())
		seq_c.append(c.offered_ids())
	assert_eq(a.to_dict(), b.to_dict(), "même graine, même tableau")
	assert_true(seq_a != seq_c, "autre graine, autre tirage")
	# Recharger le profil ne change pas le tirage.
	var pr := PlayerProfile.new()
	pr.contracts = _state(42)
	var ref := _state(42)
	for i in 3:
		ContractRules.rotate(pr.contracts, data, 1, day, true)
		ContractRules.rotate(ref, data, 1, day, true)
		ProfileStore.save_profile(pr, file)
		pr = ProfileStore.load_profile(file)
	assert_eq(pr.contracts.to_dict(), ref.to_dict(), "tirage identique après rechargements")


func test_tutoriel_en_premier() -> void:
	var data := _data({"a": {"weight": 5}, "b": {}, "tuto": {"tutorial": true, "weight": 0, "repeatable": false}},
			{"offers": 2})
	for s in 20:
		var st := _state(s)
		ContractRules.rotate(st, data, 1, day, false)
		assert_eq(st.offers[0].id, "tuto", "tuto en premier (graine %d)" % s)
	var st := _state()
	ContractRules.rotate(st, data, 1, day, false)
	st.done["tuto"] = 1
	st.offers.clear()
	for i in 10:
		ContractRules.rotate(st, data, 1, day, true)
		assert_false(st.is_offered("tuto"), "tuto rempli : plus jamais proposé")
	# Un tuto répétable rempli n'est pas tiré au sort non plus.
	data = _data({"a": {}, "tuto": {"tutorial": true}})
	st = _state()
	st.done["tuto"] = 1
	ContractRules.rotate(st, data, 1, day, true)
	assert_eq(st.offered_ids(), PackedStringArray(["a"]))


func test_chaine_after_et_non_repetable() -> void:
	var data := _data({"base": {"repeatable": false}, "suite": {"after": ["base"]}})
	var st := _state()
	ContractRules.rotate(st, data, 1, day, false)
	assert_eq(st.offered_ids(), PackedStringArray(["base"]), "suite bloquée tant que base n'est pas remplie")
	assert_eq(ContractRules.accept(st, data, "base", day), "")
	st.done["base"] = 1
	st.remove_active("base")
	ContractRules.rotate(st, data, 1, day, true)
	assert_eq(st.offered_ids(), PackedStringArray(["suite"]), "base non répétable : plus proposée ; suite débloquée")
	# Répétable : revient après avoir été remplie.
	st.done["suite"] = 3
	st.offers.clear()
	ContractRules.rotate(st, data, 1, day, true)
	assert_true(st.is_offered("suite"), "contrat répétable proposé à nouveau")


func test_niveau_et_poids() -> void:
	var data := _data({"bas": {"max_level": 4}, "haut": {"min_level": 5}, "zero": {"weight": 0}})
	var st := _state()
	ContractRules.rotate(st, data, 4, day, false)
	assert_eq(st.offered_ids(), PackedStringArray(["bas"]), "niveau 4 ; poids 0 jamais tiré")
	st = _state()
	ContractRules.rotate(st, data, 5, day, false)
	assert_eq(st.offered_ids(), PackedStringArray(["haut"]))
	# Poids : un contrat de poids 9 sort en premier bien plus souvent.
	data = _data({"leger": {"weight": 1}, "lourd": {"weight": 9}}, {"offers": 1})
	var heavy := 0
	for s in 400:
		st = _state(s * 7919)
		ContractRules.rotate(st, data, 1, day, false)
		if st.offers[0].id == "lourd":
			heavy += 1
	assert_true(heavy > 320 and heavy < 395, "poids 9 contre 1 : %d / 400" % heavy)


func test_remplacement_plus_ancienne() -> void:
	var data := _many(12)
	var st := _state()
	ContractRules.rotate(st, data, 1, day, false)
	var first: String = st.offers[0].id
	# Les 5 propositions sont arrivées ensemble ; on en vieillit une.
	st.offers[2].since = 0
	var oldest: String = st.offers[2].id
	var res := ContractRules.rotate(st, data, 1, day, true)
	assert_eq(res.removed, [oldest], "la plus ancienne retirée")
	assert_false(st.is_offered(oldest), "pas retirée et retirée au même tirage")
	assert_eq(res.added.size(), 1, "une case remplie")
	assert_eq(st.offers.size(), 5)
	assert_true(st.is_offered(first), "les autres restent")
	assert_eq(st.offers[4].since, 2, "nouvelle proposition datée de la rotation 2")
	# Proposition acceptée : case vide jusqu'à la partie suivante.
	assert_eq(ContractRules.accept(st, data, first, day), "")
	assert_eq(st.offers.size(), 4)
	ContractRules.rotate(st, data, 1, day, false)
	assert_eq(st.offers.size(), 4, "ouverture du hub : la case reste vide")
	ContractRules.rotate(st, data, 1, day, true)
	assert_eq(st.offers.size(), 5, "après une partie : remplie")
	assert_false(st.is_offered(first), "un contrat actif n'est pas proposé")


func test_tableau_incomplet() -> void:
	var data := _many(3)
	var st := _state()
	ContractRules.rotate(st, data, 1, day, false)
	assert_eq(st.offers.size(), 3, "pas assez de contrats : tableau incomplet")
	ContractRules.rotate(st, data, 1, day, true)
	assert_eq(st.offers.size(), 2, "la retirée ne revient pas tout de suite")


func test_expiration() -> void:
	var data := _data({"date": {"starts": "2026-10-01", "ends": "2026-10-31", "repeatable": false},
		"date2": {"ends": "2026-10-31"}, "perm": {}})
	var pr := PlayerProfile.new()
	var st := pr.contracts
	ContractRules.rotate(st, data, 1, day, false)
	assert_eq(st.offers.size(), 3)
	assert_eq(ContractRules.accept(st, data, "date", day), "")
	assert_eq(ContractRules.days_left(data.contract("date"), day), 21, "encore 21 jours (11 au 31 compris)")
	assert_eq(ContractRules.days_left(data.contract("perm"), day), -1)
	pr.add_samples("dog_fang", 5)
	# Dernier jour : encore là.
	var last := HubData.parse_day("2026-10-31")
	ContractRules.purge(st, data, last)
	assert_true(st.is_active("date") and st.is_offered("date2"), "valable jusqu'à la fin du dernier jour")
	# Lendemain : supprimé des actifs et des propositions, signalé une fois.
	var res := ContractRules.rotate(st, data, 1, last + 1, false)
	assert_false(st.is_active("date"), "actif expiré supprimé")
	assert_false(st.is_offered("date2"), "proposition expirée supprimée")
	assert_eq(res.expired.size(), 2)
	assert_true(st.is_offered("perm"))
	assert_eq(st.take_expired(), PackedStringArray(["date"]), "seul l'actif est signalé")
	assert_eq(st.take_expired(), PackedStringArray(), "une seule fois")
	assert_eq(pr.sample_count("dog_fang"), 5, "aucun échantillon touché")
	# Pas encore commencé : jamais proposé.
	st = _state()
	ContractRules.rotate(st, data, 1, HubData.parse_day("2026-09-30"), false)
	assert_false(st.is_offered("date"))
	# Remise et acceptation refusées une fois expiré.
	st = _state()
	ContractRules.rotate(st, data, 1, day, false)
	assert_eq(ContractRules.accept(st, data, "date", last + 1), ContractRules.EXPIRED)


func test_contrat_disparu_du_fichier() -> void:
	var st := _state()
	st.offers.append({"id": "ancien", "since": 0})
	st.active.append({"id": "renomme", "accepted": 0})
	st.rotation = 1
	var res := ContractRules.purge(st, _many(2), day)
	assert_eq(res.unknown, ["ancien", "renomme"])
	assert_true(st.offers.is_empty() and st.active.is_empty(), "retirés du profil")
	assert_true(st.expired_unseen.is_empty(), "pas signalés comme expirés")


func test_partie_trop_courte() -> void:
	var data := _many(12)
	var pr := PlayerProfile.new()
	pr.contracts = _state()
	ContractRules.rotate(pr.contracts, data, 1, day, false)
	ProfileStore.save_profile(pr, file)
	var before := ProfileStore.load_profile(file).contracts.to_dict()
	var res := MatchContracts.after_match(0, file, data, day)
	assert_false(res.rotated, "aucune manche survécue : pas de rotation")
	assert_eq(ProfileStore.load_profile(file).contracts.to_dict(), before, "tableau inchangé")
	res = MatchContracts.after_match(1, file, data, day)
	assert_true(res.rotated)
	var after := ProfileStore.load_profile(file).contracts
	assert_eq(after.rotation, 2, "une manche survécue : rotation")
	assert_eq(after.offers.size(), 5)
	# Rapport de partie : manches survécues.
	var r := MatchResult.new()
	r.round_reached = 1
	assert_eq(MatchContracts.rounds_survived(r), 0, "mort à la manche 1")
	r.round_reached = 4
	assert_eq(MatchContracts.rounds_survived(r), 3)
	r.round_reached = 1
	r.xp_ledger = {"rounds": 1}
	assert_eq(MatchContracts.rounds_survived(r), 1, "relevé d'XP du joueur")
	assert_eq(MatchContracts.rounds_survived(null), 0)


func test_premiere_partie_profil_neuf() -> void:
	# Aucun fichier : la première partie remplit le tableau et l'enregistre.
	var data := HubData.load_files(HubData.CONTRACTS_PATH, HubData.EXCHANGES_PATH)
	var res := MatchContracts.after_match(3, file, data, day)
	assert_true(res.rotated)
	var pr := ProfileStore.load_profile(file)
	assert_eq(pr.contracts.offered_ids(), PackedStringArray(["first_sample", "dog_fangs_small"]))
	assert_eq(pr.contracts.rotation, 1)


# --------------------------------------------------------------------------
# Accepter, remettre
# --------------------------------------------------------------------------

func test_trois_actifs_au_plus() -> void:
	var data := _many(12)
	var st := _state()
	ContractRules.rotate(st, data, 1, day, false)
	for i in 3:
		assert_eq(ContractRules.accept(st, data, st.offers[0].id, day), "")
	assert_eq(st.active.size(), 3)
	var fourth: String = st.offers[0].id
	assert_eq(ContractRules.accept(st, data, fourth, day), ContractRules.ACTIVE_FULL)
	assert_true(st.is_offered(fourth) and st.active.size() == 3, "refus : rien ne change")
	assert_eq(ContractRules.accept(st, data, "c99", day), ContractRules.UNKNOWN)
	assert_eq(ContractRules.accept(st, data, st.active[0].id, day), ContractRules.NOT_OFFERED)
	assert_eq(ContractRules.refusal_text(ContractRules.ACTIVE_FULL, 3),
			Lang.t("3 CONTRATS ACTIFS AU MAXIMUM", "3 ACTIVE CONTRACTS AT MOST"))
	assert_true(ContractRules.abandon(st, st.active[0].id), "abandon")
	assert_eq(st.active.size(), 2)
	assert_false(ContractRules.abandon(st, "c99"))
	assert_eq(ContractRules.accept(st, data, fourth, day), "", "une case libérée")


func test_remise_consomme_exactement() -> void:
	var data := _data({"griffes": {"samples": {"dog_fang": 50, "dog_fur": 2}, "xp": 1000,
		"thanks": {"fr": "Merci", "en": "Thanks"}}})
	var pr := PlayerProfile.new()
	pr.add_samples("dog_fang", 200)
	pr.add_samples("dog_fur", 2)
	pr.add_samples("dog_collar", 7)
	ContractRules.rotate(pr.contracts, data, 1, day, false)
	assert_eq(ContractRules.deliver_refusal(pr, data, "griffes", day), ContractRules.NOT_ACTIVE, "pas encore accepté")
	ContractRules.accept(pr.contracts, data, "griffes", day)
	var res := ContractRules.deliver(pr, data, "griffes", day)
	assert_true(res.ok, "remise : %s" % res.reason)
	assert_eq(pr.sample_count("dog_fang"), 150, "200 − 50 = 150")
	assert_eq(pr.sample_count("dog_fur"), 0)
	assert_false(pr.samples.has("dog_fur"), "sorte épuisée retirée")
	assert_eq(pr.sample_count("dog_collar"), 7, "autre sorte intacte")
	assert_eq(res.xp, 1000)
	assert_eq(pr.xp, 1000)
	assert_eq(res.level_before, 1)
	assert_eq(res.level_after, pr.level())
	assert_true(res.levels >= 1)
	assert_eq(res.thanks, {"fr": "Merci", "en": "Thanks"})
	assert_eq(pr.contracts.done_count("griffes"), 1, "remise comptée")
	assert_false(pr.contracts.is_active("griffes"), "case libérée")
	assert_eq(ContractRules.deliver(pr, data, "griffes", day).reason, ContractRules.NOT_ACTIVE, "pas deux fois")


func test_remise_refusee_sans_echantillons() -> void:
	var data := _data({"k": {"samples": {"dog_fang": 4, "dog_collar": 1}, "xp": 500}})
	var pr := PlayerProfile.new()
	pr.add_samples("dog_fang", 4)
	ContractRules.rotate(pr.contracts, data, 1, day, false)
	ContractRules.accept(pr.contracts, data, "k", day)
	var res := ContractRules.deliver(pr, data, "k", day)
	assert_false(res.ok)
	assert_eq(res.reason, ContractRules.MISSING_SAMPLES)
	assert_eq(pr.sample_count("dog_fang"), 4, "rien consommé")
	assert_eq(pr.xp, 0, "pas d'XP")
	assert_true(pr.contracts.is_active("k"), "toujours actif")
	assert_eq(pr.contracts.done_count("k"), 0)
	assert_eq(ContractRules.progress(data.contract("k"), pr.samples), {"dog_fang": [4, 4], "dog_collar": [0, 1]})
	pr.add_samples("dog_fang", 10)
	assert_eq(ContractRules.progress(data.contract("k"), pr.samples).dog_fang, [4, 4], "progression bornée")
	assert_false(ContractRules.covered(data.contract("k"), pr.samples))
	pr.add_samples("dog_collar", 1)
	assert_true(ContractRules.covered(data.contract("k"), pr.samples))
	# Expiré entre-temps : refusé.
	data = _data({"k": {"ends": "2026-10-11"}})
	pr = PlayerProfile.new()
	pr.add_samples("dog_fang", 1)
	ContractRules.rotate(pr.contracts, data, 1, day, false)
	ContractRules.accept(pr.contracts, data, "k", day)
	assert_eq(ContractRules.deliver(pr, data, "k", day + 1).reason, ContractRules.EXPIRED)
	assert_eq(pr.sample_count("dog_fang"), 1)


func test_xp_selon_niveau() -> void:
	assert_eq(HubRewards.contract_xp(1200, 1), 1200)
	assert_eq(HubRewards.contract_xp(1200, 50), 2380, "1200 × 1,98 = 2376 -> 2380")
	assert_eq(HubRewards.contract_xp(150, 10), 180, "150 × 1,18 = 177 -> 180")
	assert_eq(HubRewards.contract_xp(1650, 2), 1680, "1650 × 1,02 = 1683 -> 1680")
	assert_eq(HubRewards.contract_xp(1000, 11, 0.05), 1500, "facteur des règles")
	assert_eq(HubRewards.contract_xp(0, 30), 0)
	assert_eq(HubRewards.contract_xp(1200, 99), 2380, "niveau borné à 50")
	var data := HubData.load_files(HubData.CONTRACTS_PATH, HubData.EXCHANGES_PATH)
	assert_eq(ContractRules.xp_for(data, data.contract("great_harvest"), 10), 3890, "3300 × 1,18 = 3894")
	# Remise au niveau 10 : XP calculée au niveau du joueur.
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(10)
	pr.add_samples("dog_fang", 4)
	var d2 := _data({"k": {"samples": {"dog_fang": 4}, "xp": 1200}})
	ContractRules.rotate(pr.contracts, d2, 10, day, false)
	ContractRules.accept(pr.contracts, d2, "k", day)
	var res := ContractRules.deliver(pr, d2, "k", day)
	assert_eq(res.xp, 1420, "1200 × 1,18 = 1416 -> 1420")
	assert_eq(pr.xp, PlayerProfile.xp_for_level(10) + 1420)


func test_recompense_au_niveau_du_joueur() -> void:
	var data := _data({"arme": {"reward": {"kind": "weapon", "weapon": "any", "rarity": "rare"}},
		"piece": {"reward": {"kind": "part", "quality": "fine"}},
		"nommee": {"reward": {"kind": "weapon", "weapon": "mp5k", "rarity": "epic"}}})
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7)
	pr.add_samples("dog_fang", 3)
	ContractRules.rotate(pr.contracts, data, 7, day, false)
	for id in ["arme", "piece", "nommee"]:
		assert_eq(ContractRules.accept(pr.contracts, data, id, day), "")
	var r1 := ContractRules.deliver(pr, data, "arme", day)
	assert_true(r1.ok and r1.weapon_uid != "", "arme rangée dans l'arsenal")
	var w := pr.get_weapon(r1.weapon_uid)
	assert_eq(w.level, 7, "arme au niveau du joueur (avant l'XP du contrat)")
	assert_eq(w.rarity, OwnedWeapon.Rarity.RARE, "rareté fixée")
	assert_true(w.parts.is_empty(), "aucune pièce")
	assert_true(w.weapon_id in LootRules.weapon_pool(), "arme du butin, pas une arme de base : %s" % w.weapon_id)
	assert_true(pr.is_new_weapon(w.uid), "pastille NOUVEAU")
	var r2 := ContractRules.deliver(pr, data, "piece", day)
	var p := pr.get_part(r2.part_uid)
	assert_true(p != null, "pièce dans l'onglet des pièces")
	assert_eq(p.level, 7, "pièce au niveau du joueur")
	assert_eq(r2.level_before, 7)
	var r3 := ContractRules.deliver(pr, data, "nommee", day)
	assert_eq(pr.get_weapon(r3.weapon_uid).weapon_id, "mp5k")
	assert_eq(pr.get_weapon(r3.weapon_uid).rarity, OwnedWeapon.Rarity.EPIC)


func test_pieces_par_qualite() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 200:
		var fine := HubRewards.make_part("fine", 12, rng)
		assert_eq(fine.level, 12)
		assert_eq(fine.mods.size(), 2, "soignée : deux modificateurs")
		for k in fine.mods:
			assert_true(GameWeapon.MODS.has(k), "nom connu : %s" % k)
			assert_true(fine.mods[k] >= 0.1 - 1e-6 and fine.mods[k] <= 0.25 + 1e-6, "soignée : bonus 10 à 25 %% (%s)" % fine.mods)
		assert_eq(fine.part_id, "part_" + String(fine.mods.keys()[0]))
		var sup := HubRewards.make_part("superior", 12, rng)
		assert_eq(sup.mods.size(), 2)
		for k in sup.mods:
			assert_true(sup.mods[k] >= 0.18 - 1e-6 and sup.mods[k] <= 0.25 + 1e-6, "d'exception : 18 à 25 %% (%s)" % sup.mods)
		var std := HubRewards.make_part("standard", 12, rng)
		assert_eq(std.level, 12, "ordinaire : tirage du butin, niveau du joueur")
		assert_true(std.mods.size() >= 1 and std.mods.size() <= 2)
	# Armes « any » : niveau de base respecté, arme précise au moins à son niveau de base.
	assert_false(HubRewards.weapon_choices(1).is_empty())
	for id in HubRewards.weapon_choices(1):
		assert_true(WeaponDB.base_level(id) <= 1 and not BaseWeapons.is_base(id))
	var w := HubRewards.make_weapon({"weapon": "mp5k", "rarity": "legendary"}, 3, rng)
	assert_eq(w.level, maxi(3, WeaponDB.base_level("mp5k")))
	assert_eq(w.rarity, OwnedWeapon.Rarity.LEGENDARY)
	assert_eq(HubRewards.make_item({"kind": "none"}, 3, rng), null)


func test_textes_des_recompenses() -> void:
	var was: String = Settings.language
	Settings.language = "fr"
	assert_eq(HubRewards.describe({"kind": "weapon", "weapon": "any", "rarity": "rare"}, 7), "ARME RARE NIV. 7")
	assert_eq(HubRewards.describe({"kind": "part", "quality": "fine"}, 7), "PIÈCE SOIGNÉE NIV. 7")
	assert_eq(HubRewards.describe({"kind": "part", "mods": {"damage": 0.15}}, 2), "PIÈCE NIV. 2 : +15 % dégâts")
	Settings.language = "en"
	assert_eq(HubRewards.describe({"kind": "weapon", "weapon": "any", "rarity": "rare"}, 7), "RARE WEAPON LVL 7")
	assert_eq(HubRewards.describe({"kind": "part", "quality": "superior"}, 7), "SUPERIOR PART LVL 7")
	assert_eq(HubRewards.describe({"kind": "none"}, 7), "")
	Settings.language = was


# --------------------------------------------------------------------------
# Échantillons partagés, objectif atteint en partie (D13)
# --------------------------------------------------------------------------

func test_progression_partagee() -> void:
	var data := _data({"a": {"samples": {"dog_fang": 3}}, "b": {"samples": {"dog_fang": 2, "dog_fur": 1}},
		"c": {"samples": {"dog_collar": 1}}})
	var st := _state()
	ContractRules.rotate(st, data, 1, day, false)
	for id in ["a", "b", "c"]:
		ContractRules.accept(st, data, id, day)
	assert_eq(ContractRules.shared_with(st, data, "a"), PackedStringArray(["b"]))
	assert_eq(ContractRules.shared_with(st, data, "c"), PackedStringArray())


func test_objectif_atteint_en_partie() -> void:
	var data := _data({"a": {"samples": {"dog_fang": 3}}, "b": {"samples": {"dog_fur": 2}},
		"date": {"samples": {"dog_fang": 1}, "ends": "2026-10-11"}})
	var pr := PlayerProfile.new()
	pr.add_samples("dog_fang", 2)
	ContractRules.rotate(pr.contracts, data, 1, day, false)
	for id in ["a", "b", "date"]:
		ContractRules.accept(pr.contracts, data, id, day)
	assert_eq(ContractRules.goals_met(pr, data, {}, day), PackedStringArray(["date"]), "début de partie : déjà couvert")
	assert_eq(ContractRules.goals_met(pr, data, {"dog_fang": 1}, day), PackedStringArray(["a", "date"]),
			"profil 2 + partie 1 = 3 crocs")
	assert_eq(ContractRules.goals_met(pr, data, {"dog_fang": 1}, day + 1), PackedStringArray(["a"]), "contrat expiré ignoré")
	assert_true(ContractRules.goal_met(data.contract("b"), {"dog_fur": 1}, {"dog_fur": 1}))
	assert_false(ContractRules.goal_met(data.contract("b"), {}, {"dog_fur": 1}))
	assert_eq(pr.sample_count("dog_fang"), 2, "fonction pure : rien d'ajouté")
	var was: String = Settings.language
	Settings.language = "fr"
	assert_eq(ContractRules.goal_message(data.contract("a")),
			"CONTRAT « T a » : OBJECTIF ATTEINT — évacuez pour garder vos échantillons")
	Settings.language = "en"
	assert_true(ContractRules.goal_message(data.contract("a")).begins_with("CONTRACT \"T a\": GOAL REACHED"))
	Settings.language = was


# --------------------------------------------------------------------------
# État dans le profil
# --------------------------------------------------------------------------

func test_etat_lu_et_ecrit() -> void:
	var st := _state(918273)
	st.rotation = 12
	st.offers.append({"id": "dog_fur_coat", "since": 11})
	st.active.append({"id": "dog_fangs_small", "accepted": 9})
	st.done = {"first_sample": 1, "dog_fangs_small": 2}
	st.expired_unseen.append("lab_emergency")
	var back := ContractState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	assert_eq(back.to_dict(), st.to_dict(), "aller-retour JSON")
	assert_eq(back.done_total(), 3)
	# Entrées illisibles écartées et comptées.
	var dropped := [0]
	var bad := ContractState.from_dict({"seed": "x", "rotation": 3,
		"offers": [{"id": "a", "since": 99}, {"id": "a"}, {"id": ""}, 7, {"id": "b", "since": 1}],
		"active": [{"id": "b", "accepted": 1}],
		"done": {"a": 2, "b": -1, "": 1}, "expired_unseen": ["x", 3]}, dropped)
	assert_eq(bad.offered_ids(), PackedStringArray(["a"]), "doublons, vides et déjà actifs écartés")
	assert_eq(bad.offers[0].since, 3, "« since » borné à la rotation")
	assert_eq(bad.active_ids(), PackedStringArray(["b"]))
	assert_eq(bad.done, {"a": 2})
	assert_eq(bad.expired_unseen, PackedStringArray(["x"]))
	assert_eq(dropped[0], 8, "entrées écartées comptées (%d)" % dropped[0])
	assert_true(bad.draw_seed >= 0, "graine illisible : nouvelle graine")
	dropped = [0]
	var fresh := ContractState.from_dict(null, dropped)
	assert_eq(dropped[0], 0, "section absente : état neuf sans erreur")
	assert_eq(fresh.rotation, 0)
