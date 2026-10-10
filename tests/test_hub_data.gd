extends TestCase
## Données du hub (HubData, docs/HUB_PLAN.md §5.5) : fichiers livrés lus sans
## aucun avertissement, chaque refus d'entrée invalide (entrée écartée, le
## reste gardé), dates UTC, fichiers absents ou cassés, export des données.

const OK_EXCHANGES := "{\"format\": \"hub_exchanges\", \"version\": 1, \"exchanges\": []}"
const OK_CONTRACTS := "{\"format\": \"hub_contracts\", \"version\": 1, \"contracts\": []}"


## Contrat valide, modifié par `over` (valeur « __erase » : champ retiré).
func _contract(over := {}) -> Dictionary:
	var c := {
		"id": "ok_contract",
		"title": {"fr": "Titre", "en": "Title"},
		"text": {"fr": "Texte.", "en": "Text."},
		"samples": {"dog_fang": 2},
		"xp": 100,
		"reward": {"kind": "part", "quality": "fine"},
	}
	for k in over:
		if over[k] is String and over[k] == "__erase":
			c.erase(k)
		else:
			c[k] = over[k]
	return c


func _exchange(over := {}) -> Dictionary:
	var x := {
		"id": "ok_exchange",
		"title": {"fr": "Titre", "en": "Title"},
		"samples": {"dog_fur": 3},
		"reward": {"kind": "part", "mods": {"damage": 0.1}},
	}
	for k in over:
		if over[k] is String and over[k] == "__erase":
			x.erase(k)
		else:
			x[k] = over[k]
	return x


func _with_contracts(list: Array, rules: Variant = null) -> HubData:
	var doc := {"format": "hub_contracts", "version": 1, "contracts": list}
	if rules != null:
		doc.rules = rules
	return HubData.from_texts(JSON.stringify(doc), OK_EXCHANGES)


func _with_exchanges(list: Array) -> HubData:
	return HubData.from_texts(OK_CONTRACTS, JSON.stringify({"format": "hub_exchanges", "version": 1, "exchanges": list}))


## Le contrat `bad` est refusé (un avertissement) et le contrat valide gardé.
func _refused(bad: Dictionary, why: String) -> void:
	var d := _with_contracts([_contract(), bad])
	assert_eq(d.contracts.size(), 1, "contrat refusé : " + why)
	assert_eq(d.warnings.size(), 1, "un avertissement : %s (%s)" % [why, d.warnings])
	assert_true(d.has_contract("ok_contract"), "le contrat valide reste : " + why)


func _refused_exchange(bad: Dictionary, why: String) -> void:
	var d := _with_exchanges([_exchange(), bad])
	assert_eq(d.exchanges.size(), 1, "échange refusé : " + why)
	assert_eq(d.warnings.size(), 1, "un avertissement : %s (%s)" % [why, d.warnings])


# --------------------------------------------------------------------------
# Fichiers livrés
# --------------------------------------------------------------------------

func test_fichiers_livres_sans_avertissement() -> void:
	var d := HubData.load_files(HubData.CONTRACTS_PATH, HubData.EXCHANGES_PATH)
	assert_eq(d.warnings.size(), 0, "aucun avertissement : %s" % d.warnings)
	assert_eq(d.contracts.size(), 8, "8 contrats (§7.1)")
	assert_eq(d.exchanges.size(), 5, "5 échanges (§7.2)")
	assert_eq(d.rules, {"offers": 5, "active_max": 3, "replace_per_match": 1, "min_rounds_for_rotation": 1,
		"xp_level_factor": 0.02})
	var tuto := d.contract("first_sample")
	assert_true(tuto.tutorial and not tuto.repeatable and tuto.weight == 0.0, "contrat tuto")
	assert_eq(tuto.reward, {"kind": "weapon", "weapon": "any", "rarity": "common"})
	var lab := d.contract("lab_emergency")
	assert_eq(HubData.day_string(lab.starts), "2026-11-01")
	assert_eq(HubData.day_string(lab.ends), "2026-11-30")
	assert_eq(d.contract("great_harvest").after, PackedStringArray(["pack_analysis"]))
	assert_eq(d.contract("dog_fangs_small").max_level, PlayerProfile.MAX_LEVEL, "max_level par défaut")
	assert_eq(d.contract("dog_fangs_small").starts, -1, "sans date")
	assert_eq(d.exchange("pack_weapon").reward, {"kind": "weapon", "weapon": "mp5k", "rarity": "epic"})
	assert_eq(d.exchange("sharpened_fangs").reward.mods, {"damage": 0.12, "fire_rate": 0.1})
	assert_eq(d.exchange("fang_trim").limit, 0, "illimité par défaut")
	for c in d.contracts:
		for lang in ["fr", "en"]:
			assert_false(String(c.title[lang]).is_empty() or String(c.text[lang]).is_empty(), "%s : textes %s" % [c.id, lang])


func test_donnees_gardees() -> void:
	HubData.clear_cache()
	var a := HubData.default()
	assert_true(a == HubData.default(), "chargées une fois")
	HubData.clear_cache()
	assert_true(a != HubData.default(), "rechargées après clear_cache")


# --------------------------------------------------------------------------
# Refus (§5.5)
# --------------------------------------------------------------------------

func test_refus_identifiant() -> void:
	_refused(_contract({"id": "__erase"}), "identifiant manquant")
	_refused(_contract({"id": "Majuscule"}), "identifiant hors [a-z0-9_]")
	_refused(_contract({"id": "a".repeat(65)}), "identifiant trop long")
	_refused(_contract({"id": 12}), "identifiant non texte")
	_refused(_contract(), "identifiant en double")


func test_refus_textes() -> void:
	_refused(_contract({"id": "b", "title": {"fr": "Titre"}}), "titre sans anglais")
	_refused(_contract({"id": "b", "text": {"en": "Text"}}), "texte sans français")
	_refused(_contract({"id": "b", "title": "__erase"}), "titre absent")
	_refused(_contract({"id": "b", "text": {"fr": " ", "en": "x"}}), "texte vide")
	_refused(_contract({"id": "b", "thanks": {"fr": "Merci"}}), "remerciement sans anglais")
	_refused(_contract({"id": "b", "title": "Titre"}), "titre non bilingue")


func test_refus_echantillons() -> void:
	_refused(_contract({"id": "b", "samples": {"griffe": 3}}), "sorte inconnue")
	_refused(_contract({"id": "b", "samples": {"dog_fang": 0}}), "quantité 0")
	_refused(_contract({"id": "b", "samples": {"dog_fang": 1000}}), "quantité 1000")
	_refused(_contract({"id": "b", "samples": {"dog_fang": 2.5}}), "quantité non entière")
	_refused(_contract({"id": "b", "samples": {}}), "aucun échantillon")
	_refused(_contract({"id": "b", "samples": "__erase"}), "échantillons absents")
	var d := _with_contracts([_contract({"samples": {"dog_fang": 999, "dog_collar": 1}})])
	assert_eq(d.warnings.size(), 0, "bornes 1 et 999 permises")


func test_refus_recompense() -> void:
	_refused(_contract({"id": "b", "reward": {"kind": "weapon", "weapon": "inconnue", "rarity": "rare"}}), "arme inconnue")
	_refused(_contract({"id": "b", "reward": {"kind": "weapon", "weapon": WeaponDB.STARTING_WEAPON, "rarity": "rare"}}),
			"arme de base")
	_refused(_contract({"id": "b", "reward": {"kind": "weapon", "weapon": "any", "rarity": "mythique"}}), "rareté inconnue")
	_refused(_contract({"id": "b", "reward": {"kind": "part", "quality": "divine"}}), "qualité inconnue")
	_refused(_contract({"id": "b", "reward": {"kind": "or"}}), "sorte de récompense inconnue")
	_refused(_contract({"id": "b", "reward": "__erase"}), "récompense absente")
	var d := _with_contracts([_contract({"reward": {"kind": "none"}}),
		_contract({"id": "c", "reward": {"kind": "weapon", "weapon": "mp5k", "rarity": "unique"}}),
		_contract({"id": "e", "reward": {"kind": "part", "quality": "standard"}})])
	assert_eq(d.warnings.size(), 0, "récompenses valides : %s" % d.warnings)
	assert_eq(d.contracts.size(), 3)


func test_refus_niveaux_xp_poids() -> void:
	_refused(_contract({"id": "b", "min_level": 10, "max_level": 5}), "min_level > max_level")
	_refused(_contract({"id": "b", "min_level": 0}), "niveau 0")
	_refused(_contract({"id": "b", "max_level": 51}), "niveau 51")
	_refused(_contract({"id": "b", "xp": -5}), "XP négative")
	_refused(_contract({"id": "b", "xp": "__erase"}), "XP absente")
	_refused(_contract({"id": "b", "weight": -1}), "poids négatif")
	_refused(_contract({"id": "b", "repeatable": "oui"}), "répétable non booléen")


func test_refus_dates() -> void:
	_refused(_contract({"id": "b", "ends": "30/11/2026"}), "date au mauvais format")
	_refused(_contract({"id": "b", "ends": "2026-02-30"}), "date inexistante")
	_refused(_contract({"id": "b", "starts": "2026-13-01"}), "mois 13")
	_refused(_contract({"id": "b", "starts": 20261101}), "date non texte")
	_refused(_contract({"id": "b", "starts": "2026-12-01", "ends": "2026-11-01"}), "début après la fin")
	var d := _with_contracts([_contract({"starts": "2026-11-01", "ends": "2026-11-01"}),
		_contract({"id": "n", "starts": null, "ends": null})])
	assert_eq(d.warnings.size(), 0, "dates nulles ou d'un seul jour permises")


func test_refus_after() -> void:
	_refused(_contract({"id": "b", "after": ["inconnu"]}), "after vers un contrat inconnu")
	_refused(_contract({"id": "b", "after": ["b"]}), "after vers lui-même")
	_refused(_contract({"id": "b", "after": "ok_contract"}), "after non liste")
	# Chaîne : « c » dépend de « b », lui-même refusé : les deux sont écartés.
	var d := _with_contracts([_contract(), _contract({"id": "b", "after": ["zzz"]}), _contract({"id": "c", "after": ["b"]})])
	assert_eq(d.contracts.size(), 1, "chaîne vers un contrat écarté")
	assert_eq(d.warnings.size(), 2, "%s" % d.warnings)
	# Ordre du fichier sans importance : « after » vers un contrat plus loin.
	d = _with_contracts([_contract({"id": "late", "after": ["ok_contract"]}), _contract()])
	assert_eq(d.warnings.size(), 0)


func test_refus_echanges() -> void:
	_refused_exchange(_exchange({"id": "b", "reward": {"kind": "part", "mods": {"vitesse": 0.1}}}), "modificateur inconnu")
	_refused_exchange(_exchange({"id": "b", "reward": {"kind": "part", "mods": {"damage": 0.8}}}), "modificateur > 0,5")
	_refused_exchange(_exchange({"id": "b", "reward": {"kind": "part", "mods": {"damage": 0.0}}}), "modificateur nul")
	_refused_exchange(_exchange({"id": "b", "reward": {"kind": "part", "mods": {}}}), "pièce sans modificateur")
	_refused_exchange(_exchange({"id": "b", "reward": {"kind": "part", "quality": "fine"}}), "qualité au lieu d'une pièce précise")
	_refused_exchange(_exchange({"id": "b", "reward": {"kind": "weapon", "weapon": "any", "rarity": "rare"}}), "arme non précise")
	_refused_exchange(_exchange({"id": "b", "reward": {"kind": "none"}}), "échange sans objet")
	_refused_exchange(_exchange({"id": "b", "limit": -1}), "limite négative")
	_refused_exchange(_exchange({"id": "b", "samples": {"dog_fur": 1000}}), "quantité hors bornes")
	_refused_exchange(_exchange({"id": "b", "title": {"en": "x"}}), "titre sans français")
	_refused_exchange(_exchange(), "identifiant en double")
	var d := _with_exchanges([_exchange({"reward": {"kind": "part", "mods": {"recoil": -0.5, "mag": 0.01}}})])
	assert_eq(d.warnings.size(), 0, "malus et bornes ±0,01 à ±0,5 permis")


func test_fichiers_casses() -> void:
	var d := HubData.from_texts("", "")
	assert_eq(d.contracts.size() + d.exchanges.size(), 0)
	assert_eq(d.warnings.size(), 2, "fichiers absents signalés")
	d = HubData.from_texts("{\"format\": \"hub_contracts\", ", "[]")
	assert_eq(d.warnings.size(), 2, "JSON cassé, mauvais format")
	d = HubData.from_texts("{\"format\": \"hub_contracts\", \"version\": 2, \"contracts\": []}", OK_EXCHANGES)
	assert_eq(d.warnings.size(), 1, "version plus récente refusée")
	d = HubData.from_texts("{\"format\": \"hub_contracts\", \"version\": 1, \"contracts\": [3, \"x\"]}", OK_EXCHANGES)
	assert_eq(d.warnings.size(), 2, "entrées non objets")
	d = HubData.load_files("res://absent_contracts.json", "res://absent_exchanges.json")
	assert_eq(d.warnings.size(), 2)
	assert_eq(d.rules, HubData.DEFAULT_RULES, "règles par défaut")


func test_regles() -> void:
	var d := _with_contracts([], {"offers": 4, "active_max": 2, "xp_level_factor": 0.05})
	assert_eq(d.warnings.size(), 0)
	assert_eq(d.rules.offers, 4)
	assert_eq(d.rules.active_max, 2)
	assert_eq(d.rules.xp_level_factor, 0.05)
	assert_eq(d.rules.replace_per_match, 1, "règle absente : défaut")
	d = _with_contracts([], {"offers": 0, "active_max": 2.5, "bidule": 1})
	assert_eq(d.warnings.size(), 3, "hors bornes, non entier, inconnue : %s" % d.warnings)
	assert_eq(d.rules, HubData.DEFAULT_RULES)


func test_dates() -> void:
	assert_eq(HubData.parse_day("1970-01-01"), 0)
	assert_eq(HubData.parse_day("1970-01-02"), 1)
	assert_eq(HubData.parse_day("2026-11-30") - HubData.parse_day("2026-11-01"), 29)
	assert_eq(HubData.parse_day("2024-02-29") - HubData.parse_day("2024-02-28"), 1, "année bissextile")
	for bad in ["2025-02-29", "2026-04-31", "2026-1-01", "26-11-01", "2026/11/01", "", "abcd-ef-gh", "+026-11-01", null, 3]:
		assert_eq(HubData.parse_day(bad), -1, "date refusée : %s" % str(bad))
	assert_eq(HubData.day_string(HubData.parse_day("2026-11-30")), "2026-11-30")
	var now := Time.get_date_string_from_system(true)
	assert_eq(HubData.day_string(HubData.today()), now, "aujourd'hui en UTC")


func test_textes_bilingues() -> void:
	var t := {"fr": "Bonjour", "en": "Hello"}
	var was: String = Settings.language
	Settings.language = "fr"
	assert_eq(HubData.text_of(t), "Bonjour")
	assert_eq(HubData.quality_name("superior"), "D'EXCEPTION")
	Settings.language = "en"
	assert_eq(HubData.text_of(t), "Hello")
	assert_eq(HubData.quality_name("fine"), "FINE")
	Settings.language = was
	assert_eq(HubData.text_of(null), "")


# --------------------------------------------------------------------------
# Export (§5.5)
# --------------------------------------------------------------------------

func test_donnees_exportees() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var presets := 0
	for s in cfg.get_sections():
		if s.begins_with("preset.") and not s.ends_with(".options"):
			presets += 1
			var inc := String(cfg.get_value(s, "include_filter", ""))
			assert_true("assets/data/*" in inc.split(", "), "%s : assets/data/* exporté (%s)" % [s, inc])
			var exc := String(cfg.get_value(s, "exclude_filter", ""))
			assert_false("assets/data" in exc, "%s : données non exclues" % s)
	assert_true(presets >= 2, "préréglages d'export lus")
	# Vérification du paquet : chaque fichier de données doit y être.
	var want := (load("res://tools/pack_check.gd") as GDScript).call("data_files", "res://assets/data") as PackedStringArray
	assert_true(HubData.CONTRACTS_PATH in want and HubData.EXCHANGES_PATH in want, "pack_check exige les données : %s" % want)
