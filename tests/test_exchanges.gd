extends TestCase
## Catalogue d'échanges (ExchangeRules, docs/HUB_PLAN.md §6) : objet précis au
## niveau du joueur, coût consommé exactement, pas d'XP, illimité sauf
## limite, niveau requis (visible mais grisé), dates, refus sans les
## échantillons, compteur enregistré dans le profil.

var file := "user://profile_exchanges_unittest_%d.json" % OS.get_process_id()
var day := HubData.parse_day("2026-10-11")
var data := HubData.load_files(HubData.CONTRACTS_PATH, HubData.EXCHANGES_PATH)


func before_each() -> void:
	ProfileStore.reset(file)


func after_each() -> void:
	ProfileStore.reset(file)


func _at_level(lvl: int) -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(lvl)
	return pr


func _custom(list: Array) -> HubData:
	var d := HubData.from_texts("{\"format\": \"hub_contracts\", \"version\": 1, \"contracts\": []}",
			JSON.stringify({"format": "hub_exchanges", "version": 1, "exchanges": list}))
	assert_eq(d.warnings.size(), 0, "%s" % d.warnings)
	return d


func test_echange_piece_precise() -> void:
	var pr := _at_level(4)
	pr.add_samples("dog_fang", 12)
	pr.add_samples("dog_fur", 3)
	pr.add_samples("dog_collar", 2)
	var xp_before := pr.xp
	var res := ExchangeRules.trade(pr, data, "fang_trim", day)
	assert_true(res.ok, "échange : %s" % res.reason)
	assert_eq(pr.sample_count("dog_fang"), 7, "12 − 5")
	assert_eq(pr.sample_count("dog_fur"), 0, "3 − 3")
	assert_eq(pr.sample_count("dog_collar"), 2, "autre sorte intacte")
	var p := pr.get_part(res.part_uid)
	assert_true(p != null, "pièce dans l'onglet des pièces")
	assert_eq(p.mods, {"damage": 0.15}, "modificateurs exacts")
	assert_eq(p.level, 4, "au niveau du joueur")
	assert_eq(p.part_id, "part_damage")
	assert_true(pr.is_new_part(p.uid), "pastille NOUVEAU")
	assert_eq(pr.xp, xp_before, "pas d'XP (D10)")
	assert_eq(ExchangeRules.count(pr, "fang_trim"), 1)
	# Illimité : un second échange, puis refus faute d'échantillons.
	pr.add_samples("dog_fur", 3)
	assert_true(ExchangeRules.trade(pr, data, "fang_trim", day).ok, "illimité")
	assert_eq(ExchangeRules.count(pr, "fang_trim"), 2)
	var r3 := ExchangeRules.trade(pr, data, "fang_trim", day)
	assert_eq(r3.reason, ExchangeRules.MISSING_SAMPLES)
	assert_eq(pr.sample_count("dog_fang"), 2, "refus : rien consommé")
	assert_eq(pr.parts.size(), 2, "refus : aucune pièce")
	assert_eq(ExchangeRules.count(pr, "fang_trim"), 2)


func test_echange_arme_precise() -> void:
	var pr := _at_level(9)
	for s in ["dog_fang", "dog_fur", "dog_collar"]:
		pr.add_samples(s, 10)
	var res := ExchangeRules.trade(pr, data, "pack_weapon", day)
	assert_true(res.ok, res.reason)
	var w := pr.get_weapon(res.weapon_uid)
	assert_eq(w.weapon_id, "mp5k")
	assert_eq(w.rarity, OwnedWeapon.Rarity.EPIC)
	assert_eq(w.level, 9, "au niveau du joueur")
	assert_true(pr.samples.is_empty(), "10 + 10 + 10 consommés")


func test_niveau_requis() -> void:
	var pr := _at_level(1)
	pr.add_samples("dog_collar", 10)
	pr.add_samples("dog_fur", 10)
	assert_eq(ExchangeRules.refusal(pr, data, "collar_strap", day), ExchangeRules.LEVEL)
	assert_false(ExchangeRules.trade(pr, data, "collar_strap", day).ok)
	assert_eq(pr.sample_count("dog_collar"), 10)
	var all := ExchangeRules.listed(pr, data, day)
	assert_eq(all.size(), 5, "niveau trop haut : visible (grisé)")
	var now := ExchangeRules.listed(pr, data, day, true)
	var ids := []
	for x in now:
		ids.append(x.id)
	assert_eq(ids, ["fur_padding"], "échangeables maintenant au niveau 1 avec ces échantillons")
	assert_eq(ExchangeRules.refusal_text(ExchangeRules.LEVEL, data.exchange("collar_strap")),
			Lang.t("NIV. 2 REQUIS", "LVL 2 REQUIRED"))
	pr = _at_level(2)
	pr.add_samples("dog_collar", 4)
	pr.add_samples("dog_fur", 2)
	assert_eq(ExchangeRules.refusal(pr, data, "collar_strap", day), "")
	assert_eq(ExchangeRules.refusal(pr, data, "inconnu", day), ExchangeRules.UNKNOWN)


func test_limite_et_dates() -> void:
	var d := _custom([
		{"id": "une_fois", "title": {"fr": "a", "en": "a"}, "samples": {"dog_fang": 1},
			"reward": {"kind": "part", "mods": {"reload": 0.2}}, "limit": 1},
		{"id": "novembre", "title": {"fr": "b", "en": "b"}, "samples": {"dog_fang": 1},
			"reward": {"kind": "part", "mods": {"mag": 0.1}}, "starts": "2026-11-01", "ends": "2026-11-30"},
	])
	var pr := PlayerProfile.new()
	pr.add_samples("dog_fang", 5)
	assert_true(ExchangeRules.trade(pr, d, "une_fois", day).ok)
	assert_eq(ExchangeRules.refusal(pr, d, "une_fois", day), ExchangeRules.LIMIT, "limite d'un échange")
	assert_eq(ExchangeRules.refusal(pr, d, "novembre", day), ExchangeRules.NOT_STARTED)
	assert_eq(ExchangeRules.refusal(pr, d, "novembre", HubData.parse_day("2026-11-30")), "")
	assert_eq(ExchangeRules.refusal(pr, d, "novembre", HubData.parse_day("2026-12-01")), ExchangeRules.ENDED)
	assert_eq(ExchangeRules.listed(pr, d, day).size(), 1, "échange temporaire caché hors de ses dates")
	assert_eq(ExchangeRules.listed(pr, d, HubData.parse_day("2026-11-15")).size(), 2)
	assert_eq(pr.sample_count("dog_fang"), 4)


func test_compteur_enregistre() -> void:
	var pr := PlayerProfile.new()
	pr.add_samples("dog_fur", 12)
	ExchangeRules.trade(pr, data, "fur_padding", day)
	ExchangeRules.trade(pr, data, "fur_padding", day)
	ProfileStore.save_profile(pr, file)
	var back := ProfileStore.load_profile(file)
	assert_eq(ExchangeRules.count(back, "fur_padding"), 2)
	assert_eq(back.parts.size(), 2)
	assert_eq(back.parts[0].mods, {"recoil": 0.2})
