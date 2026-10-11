extends TestCase
## Contrats d'HISTOIRE (GAME_CONCEPT §4.2 quater, docs/HUB_PLAN.md §5.7) :
## fichier livré sans avertissement, validation (entrées écartées une à une),
## progression dans l'ordre (une étape à la fois, niveau requis, remise :
## consommation exacte, objet = aperçu, XP, étape suivante, fin de
## chapitre, fin de l'histoire), état du profil (lecture tolérante),
## migration des profils v3 -> v4 ; durée de vie des contrats TEMPORAIRES
## (règle lifetime_days) ; textes du LABO (Hub2LabKit).

const FILE := "user://profile_story_unittest.json"

## Petite histoire de test : deux chapitres (2 + 1 étapes).
const MINI := {"format": "hub_story", "version": 1, "chapters": [
	{"id": "c1", "title": {"fr": "Un", "en": "One"}, "steps": [
		{"id": "a", "short": {"fr": "A", "en": "A"}, "title": {"fr": "Étape A", "en": "Step A"},
			"text": {"fr": "Texte A", "en": "Text A"}, "samples": {"dog_fang": 2}, "xp": 100,
			"reward": {"kind": "weapon", "weapon": "any", "rarity": "rare"}},
		{"id": "b", "short": {"fr": "B", "en": "B"}, "title": {"fr": "Étape B", "en": "Step B"},
			"text": {"fr": "Texte B", "en": "Text B"}, "samples": {"dog_fur": 1, "dog_collar": 1}, "xp": 200,
			"reward": {"kind": "part", "quality": "fine"}, "min_level": 3, "thanks": {"fr": "Merci B", "en": "Thanks B"}},
	]},
	{"id": "c2", "title": {"fr": "Deux", "en": "Two"}, "steps": [
		{"id": "c", "short": {"fr": "C", "en": "C"}, "title": {"fr": "Étape C", "en": "Step C"},
			"text": {"fr": "Texte C", "en": "Text C"}, "samples": {"brancard_strap": 1}, "xp": 0, "reward": {"kind": "none"}},
	]},
]}

var _saved_lang := ""


func before_each() -> void:
	_saved_lang = Settings.language
	Settings.language = "fr"
	ProfileStore.reset(FILE)
	StoryRules.data_override = null


func after_each() -> void:
	Settings.language = _saved_lang
	ProfileStore.reset(FILE)
	StoryRules.data_override = null
	HubContractsView.data_override = null
	HubContractsView.day_override = -1


func _mini() -> StoryData:
	return StoryData.from_text(JSON.stringify(MINI, "", false))


func _doc_with_step(step: Dictionary) -> String:
	var doc := MINI.duplicate(true)
	doc.chapters[0].steps.append(step)
	return JSON.stringify(doc, "", false)


# --- Fichier livré ---------------------------------------------------------------

func test_shipped_story_loads_without_warning() -> void:
	StoryData.clear_cache()
	var d := StoryData.shipped()
	assert_eq(d.warnings.size(), 0, "aucun avertissement : %s" % d.warnings)
	assert_eq(d.chapters.size(), 3, "3 chapitres (provisoire)")
	var counts := []
	for ch in d.chapters:
		counts.append(ch.steps.size())
	assert_eq(counts, [4, 5, 5], "étapes par chapitre")
	assert_eq(d.steps.size(), 14)
	assert_eq(d.steps[0].id, "ch1_fangs", "l'histoire commence par les crocs")
	# Niveaux requis croissants : l'histoire suit la progression.
	var lvl := 1
	for s in d.steps:
		assert_true(int(s.min_level) >= lvl, "niveau requis croissant (%s)" % s.id)
		lvl = int(s.min_level)
		for k in ["short", "title", "text", "lab", "ready", "thanks"]:
			assert_true(s[k].has("fr") and s[k].has("en"), "%s : %s FR et EN" % [s.id, k])
	# Maquette Contrats.dc.html : chapitre 2, étape 3 « Sangles en série ».
	var loc := d.locate("ch2_straps")
	assert_eq(int(loc.chapter_index), 1)
	assert_eq(int(loc.step_index), 2)
	assert_eq(int(loc.count), 5)
	assert_eq(HubData.text_of(loc.chapter.title), "Le service de nuit")
	assert_eq(d.step("ch2_straps").samples, {"brancard_strap": 3})
	assert_eq(HubData.text_of(d.step("ch2_charts").title), "Fiches patients")
	var shorts := []
	for s in loc.chapter.steps:
		shorts.append(HubData.text_of(s.short))
	assert_eq(shorts, ["Patient zéro", "Le chariot", "Sangles", "Fiches", "Nuit blanche"], "frise de la maquette")
	assert_true(StoryData.shipped() == d, "chargée une fois")


func test_validation_drops_bad_entries() -> void:
	var d := StoryData.from_text("")
	assert_eq(d.steps.size(), 0)
	assert_true(d.warnings.size() > 0, "fichier vide signalé")
	d = StoryData.from_text("{\"format\": \"hub_story\", \"version\": 9, \"chapters\": []}")
	assert_true(d.warnings.size() > 0, "version trop récente refusée")
	var bad_steps := [
		{"id": "x1", "short": {"fr": "x", "en": "x"}, "title": {"fr": "t"}, "text": {"fr": "t", "en": "t"},
			"samples": {"dog_fang": 1}, "xp": 1, "reward": {"kind": "none"}},  # titre sans EN
		{"id": "x2", "short": {"fr": "x", "en": "x"}, "title": {"fr": "t", "en": "t"}, "text": {"fr": "t", "en": "t"},
			"samples": {"griffe": 1}, "xp": 1, "reward": {"kind": "none"}},  # sorte inconnue
		{"id": "a", "short": {"fr": "x", "en": "x"}, "title": {"fr": "t", "en": "t"}, "text": {"fr": "t", "en": "t"},
			"samples": {"dog_fang": 1}, "xp": 1, "reward": {"kind": "none"}},  # identifiant en double
		{"id": "x3", "short": {"fr": "beaucoup trop long", "en": "x"}, "title": {"fr": "t", "en": "t"},
			"text": {"fr": "t", "en": "t"}, "samples": {"dog_fang": 1}, "xp": 1, "reward": {"kind": "none"}},  # libellé long
		{"id": "x4", "short": {"fr": "x", "en": "x"}, "title": {"fr": "t", "en": "t"}, "text": {"fr": "t", "en": "t"},
			"samples": {"dog_fang": 1}, "xp": 1, "reward": {"kind": "weapon", "weapon": "m1911", "rarity": "rare"}},  # arme de base
		{"id": "x5", "short": {"fr": "x", "en": "x"}, "title": {"fr": "t", "en": "t"}, "text": {"fr": "t", "en": "t"},
			"samples": {"dog_fang": 1}, "xp": 1, "reward": {"kind": "none"}, "min_level": 99},  # niveau hors bornes
		{"id": "x6", "short": {"fr": "x", "en": "x"}, "title": {"fr": "t", "en": "t"}, "text": {"fr": "t", "en": "t"},
			"samples": {"dog_fang": 1}, "xp": -5, "reward": {"kind": "none"}},  # XP négative
		{"id": "x7", "short": {"fr": "x", "en": "x"}, "title": {"fr": "t", "en": "t"}, "text": {"fr": "t", "en": "t"},
			"samples": {"dog_fang": 1}, "xp": 1, "reward": {"kind": "none"}, "lab": "pas un texte"},  # réplique invalide
	]
	for st in bad_steps:
		d = StoryData.from_text(_doc_with_step(st))
		assert_eq(d.steps.size(), 3, "entrée « %s » écartée" % st.id)
		assert_true(d.warnings.size() >= 1, "avertissement pour « %s »" % st.id)
	# Chapitre sans étape valide : écarté ; règle hors bornes : défaut.
	var doc := MINI.duplicate(true)
	doc.chapters.append({"id": "c3", "title": {"fr": "Vide", "en": "Empty"}, "steps": [3]})
	doc.rules = {"xp_level_factor": 7, "inconnue": 1}
	d = StoryData.from_text(JSON.stringify(doc, "", false))
	assert_eq(d.chapters.size(), 2, "chapitre vide écarté")
	assert_near(float(d.rules.xp_level_factor), 0.02, 1e-6, "règle hors bornes : défaut")
	assert_true(d.warnings.size() >= 3)
	# Fichier valide : aucun avertissement, ordre gardé.
	d = _mini()
	assert_eq(d.warnings.size(), 0, "%s" % d.warnings)
	assert_eq(d.steps.map(func(s): return s.id), ["a", "b", "c"])
	assert_eq(d.step("a").min_level, 1, "niveau requis par défaut")


# --- Progression -------------------------------------------------------------------

func test_sequential_progress_and_delivery() -> void:
	var d := _mini()
	var pr := PlayerProfile.new()
	assert_eq(StoryRules.current(pr, d).id, "a", "première étape")
	assert_eq(StoryRules.refusal(pr, d), StoryRules.MISSING_SAMPLES)
	assert_eq(StoryRules.step_state(pr, d.step("a"), d), StoryRules.CURRENT)
	assert_eq(StoryRules.step_state(pr, d.step("b"), d), StoryRules.LOCKED, "une seule étape à la fois")
	pr.add_samples("dog_fang", 5)
	pr.add_samples("dog_fur", 1)  # pour B : ne compte pas tant que A n'est pas remise
	assert_true(StoryRules.is_ready(pr, d))
	var preview := StoryRules.preview_item(pr, d.step("a"))
	assert_true(preview is OwnedWeapon, "aperçu : une arme")
	var xp_before := pr.xp
	var res := StoryRules.deliver(pr, d)
	assert_true(res.ok, "remise")
	assert_eq(pr.sample_count("dog_fang"), 3, "consommation exacte (5 − 2)")
	assert_eq(pr.sample_count("dog_fur"), 1, "rien d'autre consommé")
	assert_true(res.item is OwnedWeapon and pr.weapons.size() == 1, "arme reçue")
	var w: OwnedWeapon = res.item
	assert_eq([w.weapon_id, w.rarity, w.level], [(preview as OwnedWeapon).weapon_id, (preview as OwnedWeapon).rarity,
		(preview as OwnedWeapon).level], "l'objet remis est l'aperçu montré")
	assert_eq(int(w.rarity), OwnedWeapon.Rarity.RARE)
	assert_eq(pr.xp - xp_before, 100, "XP de base au niveau 1")
	assert_eq(res.next.id, "b", "étape suivante débloquée")
	assert_false(res.chapter_done)
	assert_true(pr.story.is_done("a"))
	assert_eq(StoryRules.step_state(pr, d.step("a"), d), StoryRules.DONE)
	# Étape B : niveau 3 requis.
	pr.add_samples("dog_collar", 1)
	assert_eq(StoryRules.refusal(pr, d), StoryRules.LEVEL, "niveau requis")
	assert_eq(StoryRules.refusal_text(StoryRules.LEVEL, d.step("b")), "NIV. 3 REQUIS")
	assert_false(StoryRules.deliver(pr, d).ok, "refusée sous le niveau")
	assert_eq(pr.sample_count("dog_fur"), 1, "rien consommé")
	pr.xp = PlayerProfile.xp_for_level(3)
	res = StoryRules.deliver(pr, d)
	assert_true(res.ok and res.item is WeaponPart, "pièce soignée")
	assert_eq((res.item as WeaponPart).level, 3, "au niveau du joueur")
	assert_eq(res.xp, StoryRules.xp_for(d.step("b"), 3, d), "XP au niveau actuel")
	assert_eq(res.xp, 210, "200 × 1,04 arrondi à 10")
	assert_eq(HubData.text_of(res.thanks), "Merci B")
	assert_true(res.chapter_done, "fin du chapitre 1")
	assert_eq(res.next.id, "c")
	pr.add_samples("brancard_strap", 1)
	res = StoryRules.deliver(pr, d)
	assert_true(res.ok and res.item == null and res.xp == 0, "récompense « none », sans XP")
	assert_true(res.next.is_empty() and res.chapter_done)
	assert_true(StoryRules.is_complete(pr, d), "histoire terminée")
	assert_eq(StoryRules.refusal(pr, d), StoryRules.COMPLETE)
	assert_false(StoryRules.deliver(pr, d).ok)


func test_file_changes_keep_progress() -> void:
	# Étapes remises inconnues gardées ; étape insérée avant : elle devient
	# l'étape en cours (première non remise).
	var pr := PlayerProfile.new()
	pr.story.mark_done("a")
	pr.story.mark_done("disparue")
	var d := _mini()
	assert_eq(StoryRules.current(pr, d).id, "b")
	var doc := MINI.duplicate(true)
	doc.chapters[0].steps.insert(0, {"id": "intro", "short": {"fr": "I", "en": "I"}, "title": {"fr": "I", "en": "I"},
		"text": {"fr": "I", "en": "I"}, "samples": {"dog_fang": 1}, "xp": 1, "reward": {"kind": "none"}})
	d = StoryData.from_text(JSON.stringify(doc, "", false))
	assert_eq(StoryRules.current(pr, d).id, "intro")
	assert_true(pr.story.is_done("disparue"))


func test_state_roundtrip_and_tolerant_read() -> void:
	var st := StoryState.new()
	st.mark_done("ch1_fangs")
	st.mark_done("ch1_fangs")
	st.mark_done("ch1_fur")
	assert_eq(Array(st.done), ["ch1_fangs", "ch1_fur"], "sans doublon, dans l'ordre")
	var back := StoryState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	assert_eq(back.to_dict(), st.to_dict(), "aller-retour JSON")
	var dropped := [0]
	var bad := StoryState.from_dict({"done": ["ok_1", "", 7, "ok_1", "Pas Bon"]}, dropped)
	assert_eq(Array(bad.done), ["ok_1"])
	assert_eq(dropped[0], 4, "entrées illisibles comptées")
	dropped = [0]
	assert_eq(StoryState.from_dict(null, dropped).done.size(), 0, "section absente : début")
	assert_eq(dropped[0], 0)
	assert_eq(StoryState.from_dict("x", dropped).done.size(), 0)
	assert_eq(dropped[0], 1)


func test_profile_migration_v3_to_v4() -> void:
	assert_eq(ProfileStore.VERSION, 4)
	# Profil v3 (avant l'histoire) ; une clé « story » écrite à la main est
	# ignorée (elle n'existait pas dans ce format).
	var v3 := {"format": "profile", "version": 3, "profile": {"xp": 500, "samples": {"dog_fang": 4},
		"story": {"done": ["ch1_fangs", "ch1_fur"]}, "weekly": {}}}
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(v3))
	f.close()
	var pr := ProfileStore.load_profile(FILE)
	assert_eq(ProfileStore.last_status, "ok")
	assert_eq(pr.xp, 500, "rien de perdu")
	assert_eq(pr.sample_count("dog_fang"), 4)
	assert_eq(pr.story.done.size(), 0, "histoire au début après migration")
	pr.story.mark_done("ch1_fangs")
	ProfileStore.save_profile(pr, FILE)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	assert_eq(int(doc.version), 4, "réécrit en version 4")
	assert_eq(doc.profile.story, {"done": ["ch1_fangs"]})
	assert_eq(Array(ProfileStore.load_profile(FILE).story.done), ["ch1_fangs"], "relu")
	# Un fichier plus récent que le jeu est refusé (jamais écrasé en silence).
	assert_false(ProfileStore.parse_text(JSON.stringify({"format": "profile", "version": 5, "profile": {}})).ok)


# --- Contrats temporaires : durée de vie --------------------------------------------

func _contracts_data(life: int) -> HubData:
	var doc := {"format": "hub_contracts", "version": 1, "rules": {"offers": 2, "lifetime_days": life}, "contracts": [
		{"id": "k1", "title": {"fr": "K1", "en": "K1"}, "text": {"fr": "t", "en": "t"}, "samples": {"dog_fang": 1}, "xp": 10,
			"reward": {"kind": "none"}},
		{"id": "k2", "title": {"fr": "K2", "en": "K2"}, "text": {"fr": "t", "en": "t"}, "samples": {"dog_fur": 1}, "xp": 10,
			"reward": {"kind": "none"}, "ends": "2026-11-20"},
	]}
	return HubData.from_texts(JSON.stringify(doc, "", false), "{\"format\": \"hub_exchanges\", \"version\": 1, \"exchanges\": []}")


func test_temporary_contracts_expire() -> void:
	var day := HubData.parse_day("2026-11-18")
	var d := _contracts_data(7)
	assert_eq(d.warnings.size(), 0, "%s" % d.warnings)
	assert_eq(int(d.rules.lifetime_days), 7)
	var st := ContractState.new()
	ContractRules.rotate(st, d, 1, day, false)
	assert_eq(st.offers.size(), 2)
	for o in st.offers:
		assert_eq(ContractState.until_of(o), day + 6, "dernier jour : aujourd'hui + 6")
	# Fin effective : la plus proche de « ends » et de la durée de vie.
	assert_eq(ContractRules.deadline(d.contract("k2"), st.offer_entry("k2")), HubData.parse_day("2026-11-20"))
	assert_eq(ContractRules.accept(st, d, "k1", day), "")
	assert_eq(ContractState.until_of(st.active_entry("k1")), day + 6, "gardée à l'acceptation")
	var back := ContractState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	assert_eq(back.to_dict(), st.to_dict(), "aller-retour avec « until »")
	ContractRules.purge(st, d, day + 6)
	assert_true(st.is_active("k1"), "encore là le dernier jour")
	ContractRules.purge(st, d, day + 7)
	assert_false(st.is_active("k1"), "expiré le lendemain")
	assert_eq(Array(st.expired_unseen), ["k1"], "signalé au LABO")
	# Règle à 0 (défaut) : pas de limite propre, format inchangé.
	var st2 := ContractState.new()
	ContractRules.rotate(st2, _contracts_data(0), 1, day, false)
	assert_false(st2.offers[0].has("until"), "sans durée de vie : rien d'ajouté")
	assert_false(JSON.stringify(st2.to_dict()).contains("until"))
	# Entrée « until » illisible : écartée de l'entrée et comptée.
	var dropped := [0]
	var st3 := ContractState.from_dict({"seed": 1, "rotation": 1, "offers": [{"id": "k1", "since": 1, "until": "demain"}]}, dropped)
	assert_eq(ContractState.until_of(st3.offers[0]), -1)
	assert_eq(dropped[0], 1)


# --- Textes du LABO (Hub2LabKit) ------------------------------------------------------

func test_lab_texts() -> void:
	StoryRules.data_override = _mini()
	HubContractsView.data_override = _contracts_data(7)
	HubContractsView.day_override = HubData.parse_day("2026-11-18")
	var pr := PlayerProfile.new()
	assert_eq(Hub2LabKit.lab_line(pr, PackedStringArray(), {}), "Ah, un volontaire ! Ne touchez à rien, surtout pas au bocal qui bouge.",
			"nouveau venu")
	pr.xp = 50
	assert_eq(Hub2LabKit.lab_line(pr, PackedStringArray(), {}), "Vous revoilà, entier en plus. Je note ça dans le registre des miracles.",
			"étape sans réplique propre : accueil")
	pr.add_samples("dog_fang", 2)
	assert_eq(Hub2LabKit.ready_total(pr), 1, "étape prête")
	assert_true(Hub2LabKit.lab_line(pr, PackedStringArray(), {}).begins_with("L’étape est terminée"), "étape prête : réplique")
	assert_true(Hub2LabKit.lab_line(pr, PackedStringArray(["Vieux contrat"]), {}).begins_with("Trop tard pour « Vieux contrat »"),
			"contrat expiré d'abord")
	assert_eq(Hub2LabKit.story_line(pr), "Histoire · chapitre 1, étape 1 sur 2")
	for id in ["a", "b", "c"]:
		pr.story.mark_done(id)
	assert_eq(Hub2LabKit.story_line(pr), "Histoire terminée · la suite bientôt")
	assert_eq(Hub2LabKit.time_left(2), "encore 2 j")
	assert_eq(Hub2LabKit.time_left(0), "dernier jour")
	assert_eq(Hub2LabKit.time_left(-1), "")
	assert_eq(Hub2LabKit.offer_time(4), "4 j")
	assert_eq(Hub2LabKit.cost_line({"dog_collar": 3, "dog_fur": 4}), "3 colliers · 4 touffes", "demande (maquette)")
	assert_eq(Hub2LabKit.reward_words({"kind": "weapon", "weapon": "any", "rarity": "rare"}), "arme rare")
	assert_eq(Hub2LabKit.reward_words({"kind": "part", "quality": "fine"}), "pièce soignée")
	assert_eq(Hub2LabKit.quality_of_mods({"reload": 0.2}), "fine")
	assert_eq(Hub2LabKit.quality_of_mods({"accuracy": 0.2, "damage": 0.05}), "fine", "Mire étiquetée : soignée")
	assert_eq(Hub2LabKit.quality_of_mods({"fire_rate": 0.15, "mag": 0.1}), "superior", "Cordes tendues : d'exception")
	assert_eq(Hub2LabKit.mods_line({"accuracy": 0.2, "damage": 0.05}), "+20 % précision · +5 % dégâts")
	assert_eq(Hub2LabKit.full_name("brancard_strap"), "Sangle de cuir")
	Settings.language = "en"
	assert_eq(Hub2LabKit.full_name("brancard_bracelet"), "ID bracelet")
	assert_eq(Hub2LabKit.time_left(2), "2 d left")
	assert_eq(Hub2LabKit.cost_line({"dog_fang": 1}), "1 fang")
