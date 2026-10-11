extends TestCase
## Défi hebdomadaire (WeeklyChallenge, WeeklyRecord, GAME_CONCEPT §4.18) :
## semaines ISO, tirage déterministe par semaine, réserve weekly.json (fichier
## livré sans avertissement, entrées invalides écartées), application des
## modificateurs, récompense une fois par semaine, meilleur résultat,
## migration du profil (v2 -> v3), rapport de fin de partie.

var file := "user://profile_weekly_unittest_%d.json" % OS.get_process_id()
var _lang := ""


func before_each() -> void:
	_lang = Settings.language
	Settings.language = "fr"
	ProfileStore.reset(file)
	WeeklyChallenge.now_override = -1.0


func after_each() -> void:
	Settings.language = _lang
	ProfileStore.reset(file)
	WeeklyChallenge.now_override = -1.0


func _day(s: String) -> int:
	return HubData.parse_day(s)


## Défi construit à la main (modificateurs choisis).
func _challenge(mods: Dictionary) -> WeeklyChallenge:
	var c := WeeklyChallenge.new()
	c.year = 2026
	c.week = 41
	c.key = "2026-W41"
	c.map_id = "bunker_k7"
	c.goal_round = 10
	c.reward_xp = 400
	c.reward_samples = {"dog_fang": 4, "dog_fur": 3}
	for id in mods:
		c.modifiers.append({"id": id, "value": float(mods[id]), "title": {"fr": id, "en": id}, "text": {"fr": "", "en": ""}})
	return c


## Réserve valide minimale, modifiée par `over`.
func _pool_doc(over := {}) -> Dictionary:
	var d := {"format": "hub_weekly", "version": 1, "rules": {"goal_round": 8, "xp": 100, "min_modifiers": 1, "max_modifiers": 2},
		"reward": {"dog_fang": 2}, "maps": ["bunker_k7"],
		"modifiers": [
			{"id": "fast_zombies", "value": 0.2, "weight": 1, "title": {"fr": "A", "en": "A"}, "text": {"fr": "a {pct} %", "en": "a {pct}%"}},
			{"id": "late_start", "value": 6, "weight": 1, "title": {"fr": "B", "en": "B"}, "text": {"fr": "b {n}", "en": "b {n}"}},
		]}
	for k in over:
		d[k] = over[k]
	return d


# --------------------------------------------------------------------------
# Semaines ISO
# --------------------------------------------------------------------------

func test_iso_weeks() -> void:
	assert_eq(WeeklyChallenge.iso_week(_day("2026-10-11")), Vector2i(2026, 41), "dimanche 11/10/2026")
	assert_eq(WeeklyChallenge.iso_week(_day("2026-10-05")), Vector2i(2026, 41), "lundi")
	assert_eq(WeeklyChallenge.iso_week(_day("2026-10-12")), Vector2i(2026, 42), "lundi suivant")
	assert_eq(WeeklyChallenge.iso_week(_day("2021-01-03")), Vector2i(2020, 53), "début janvier dans l'année ISO d'avant")
	assert_eq(WeeklyChallenge.iso_week(_day("2024-12-30")), Vector2i(2025, 1), "fin décembre dans l'année ISO suivante")
	assert_eq(WeeklyChallenge.weeks_in(2020), 53)
	assert_eq(WeeklyChallenge.weeks_in(2025), 52)
	assert_eq(WeeklyChallenge.weeks_in(2026), 53)
	assert_eq(WeeklyChallenge.week_monday(2026, 41), _day("2026-10-05"))
	assert_eq(WeeklyChallenge.week_monday(2025, 1), _day("2024-12-30"))
	assert_eq(WeeklyChallenge.weekday(_day("2026-10-11")), 6, "dimanche = 6")


func test_keys() -> void:
	assert_eq(WeeklyChallenge.key_of(2026, 4), "2026-W04")
	assert_eq(WeeklyChallenge.parse_key("2026-W41"), Vector2i(2026, 41))
	assert_eq(WeeklyChallenge.parse_key("2026-W53"), Vector2i(2026, 53), "2026 a 53 semaines")
	for bad in ["2025-W53", "2026-W00", "2026-W1", "2026W41", "abcd-W01", "2026-W+1", "1999-W10", "", 42, null]:
		assert_eq(WeeklyChallenge.parse_key(bad), Vector2i.ZERO, "clé refusée : %s" % str(bad))


func test_time_left() -> void:
	var c := _challenge({})
	var monday := WeeklyChallenge.week_monday(2026, 41) * 86400.0
	assert_eq(c.seconds_left(monday), 7 * 86400, "semaine entière")
	assert_eq(c.seconds_left(monday + 6 * 86400 + 23 * 3600), 3600, "dernière heure")
	assert_eq(c.seconds_left(monday + 8 * 86400), 0, "semaine finie")
	assert_eq(WeeklyChallenge.remaining_text(3 * 86400 + 4 * 3600 + 59), "3 j 4 h")
	assert_eq(WeeklyChallenge.remaining_text(5 * 3600 + 12 * 60), "5 h 12 min")
	assert_eq(WeeklyChallenge.remaining_text(30), "1 min")
	Settings.language = "en"
	assert_eq(WeeklyChallenge.remaining_text(2 * 86400), "2 d 0 h")


# --------------------------------------------------------------------------
# Tirage déterministe
# --------------------------------------------------------------------------

func test_shipped_pool_loads_clean() -> void:
	WeeklyChallenge.clear_cache()
	var p := WeeklyChallenge.pool()
	assert_eq(p.warnings, PackedStringArray(), "weekly.json livré sans avertissement")
	assert_eq(p.modifiers.size(), WeeklyChallenge.MODS.size(), "tous les modificateurs du code dans la réserve")
	assert_true(p.maps.size() >= 1)
	for m in p.maps:
		assert_true(WeeklyChallenge.map_ok(m), "carte livrée avec porte d'évacuation et station : %s" % m)
	for m in p.modifiers:
		for lang in ["fr", "en"]:
			Settings.language = lang
			var t := WeeklyChallenge.mod_text(m)
			assert_false(t.contains("{"), "texte rempli : %s" % t)


func test_same_week_same_challenge() -> void:
	var a := WeeklyChallenge.for_week(2026, 41)
	var b := WeeklyChallenge.for_week(2026, 41)
	assert_true(a != null and b != null, "défi de la semaine 41")
	assert_eq(a.key, "2026-W41")
	assert_eq(a.map_id, b.map_id)
	assert_eq(a.match_seed, b.match_seed)
	assert_eq(JSON.stringify(a.modifiers), JSON.stringify(b.modifiers), "mêmes modificateurs")
	var c := WeeklyChallenge.from_key("2026-W41")
	assert_eq(JSON.stringify(c.modifiers), JSON.stringify(a.modifiers), "clé reçue de l'hôte : même défi")
	assert_eq(c.match_seed, a.match_seed)
	# Valeurs figées : un changement de l'algorithme change le défi de tout le
	# monde (à faire exprès, jamais par accident).
	assert_eq(WeeklyChallenge.fnv("2026-W41"), WeeklyChallenge.fnv("2026-W41"))
	assert_eq(WeeklyChallenge.fnv(""), 2166136261, "FNV-1a de base")
	assert_eq(WeeklyChallenge.fnv("a"), 0xE40C292C, "FNV-1a de « a »")
	# current() : la semaine de l'heure donnée.
	var at := (_day("2026-10-11") * 86400.0) + 3600.0
	assert_eq(WeeklyChallenge.current(at).key, "2026-W41")
	WeeklyChallenge.now_override = at
	assert_eq(WeeklyChallenge.current().key, "2026-W41", "heure imposée (tests)")


func test_weeks_vary_and_stay_valid() -> void:
	var combos := {}
	var seeds := {}
	var p := WeeklyChallenge.pool()
	for w in range(1, 54):
		var c := WeeklyChallenge.for_week(2026, w)
		assert_true(c != null, "semaine %d" % w)
		if c == null:
			continue
		assert_true(c.map_id in p.maps and WeeklyChallenge.map_ok(c.map_id), "carte valide")
		var n := c.modifiers.size()
		assert_true(n >= int(p.rules.min_modifiers) and n <= int(p.rules.max_modifiers), "nombre de modificateurs : %d" % n)
		var ids := []
		for m in c.modifiers:
			assert_false(m.id in ids, "sans doublon")
			ids.append(m.id)
		ids.sort()
		combos[str(ids)] = true
		seeds[c.match_seed] = true
	assert_true(combos.size() >= 5, "les semaines changent : %d combinaisons" % combos.size())
	assert_true(seeds.size() >= 50, "graines différentes")
	assert_eq(WeeklyChallenge.for_week(2025, 53), null, "semaine inexistante")


func test_pool_rejects_invalid_entries() -> void:
	var ok := WeeklyChallenge.parse_pool(JSON.stringify(_pool_doc()))
	assert_eq(ok.warnings, PackedStringArray(), "réserve valide : %s" % ok.warnings)
	assert_eq(ok.modifiers.size(), 2)
	assert_eq(int(ok.rules.goal_round), 8)
	var mods: Array = _pool_doc().modifiers
	var cases := [
		[{"id": "flying_zombies", "title": {"fr": "x", "en": "x"}, "text": {"fr": "x", "en": "x"}}, "inconnu"],
		[{"id": "tough_zombies", "value": 5.0, "title": {"fr": "x", "en": "x"}, "text": {"fr": "x", "en": "x"}}, "valeur hors bornes"],
		[{"id": "tough_zombies", "title": {"fr": "x"}, "text": {"fr": "x", "en": "x"}}, "sans anglais"],
		[{"id": "tough_zombies", "weight": -1, "title": {"fr": "x", "en": "x"}, "text": {"fr": "x", "en": "x"}}, "poids négatif"],
		[mods[0], "doublon"],
	]
	for cs in cases:
		var list := mods.duplicate()
		list.append(cs[0])
		var p := WeeklyChallenge.parse_pool(JSON.stringify(_pool_doc({"modifiers": list})))
		assert_eq(p.modifiers.size(), 2, "modificateur écarté : %s" % cs[1])
		assert_eq(p.warnings.size(), 1, "un avertissement : %s" % cs[1])
	var bad := WeeklyChallenge.parse_pool(JSON.stringify(_pool_doc({"maps": ["bunker_k7", "nowhere", 3],
		"reward": {"dog_fang": 2, "unicorn": 1, "dog_fur": 0}, "rules": {"goal_round": 0, "xp": 50}})))
	assert_eq(bad.maps, PackedStringArray(["bunker_k7"]), "cartes inconnues écartées")
	assert_eq(bad.reward, {"dog_fang": 2}, "récompenses invalides écartées")
	assert_eq(int(bad.rules.goal_round), WeeklyChallenge.DEFAULT_RULES.goal_round, "règle invalide : valeur par défaut")
	assert_eq(int(bad.rules.xp), 50)
	assert_eq(bad.warnings.size(), 5, "%s" % bad.warnings)
	for t in ["", "{", "{\"format\": \"hub_contracts\", \"version\": 1}", "{\"format\": \"hub_weekly\", \"version\": 9}"]:
		var p := WeeklyChallenge.parse_pool(t)
		assert_eq(p.modifiers.size(), 0)
		assert_eq(p.warnings.size(), 1, "fichier refusé : %s" % t)
	# Aucune carte valide : pas de défi.
	var none := WeeklyChallenge.parse_pool(JSON.stringify(_pool_doc({"maps": ["test_arena"]})))
	assert_eq(WeeklyChallenge.for_week(2026, 41, none), null, "carte de test refusée (pas une carte du jeu)")
	var small := WeeklyChallenge.for_week(2026, 41, ok)
	assert_eq(small.goal_round, 8)
	assert_eq(small.reward_samples, {"dog_fang": 2})


# --------------------------------------------------------------------------
# Modificateurs
# --------------------------------------------------------------------------

func test_modifiers_application() -> void:
	var plain := _challenge({})
	assert_near(plain.zombie_speed_mult(), 1.0)
	assert_eq(plain.zombie_health(1050), 1050)
	assert_eq(plain.start_round(), 1)
	assert_true(plain.has_station())
	var w := GameWeapon.make("galil", 7, 3, [], "loot:5")
	assert_eq(plain.loot_weapon(w), w, "butin inchangé")
	var c := _challenge({"fast_zombies": 0.15, "tough_zombies": 0.25, "late_start": 6, "common_loot": 0, "no_station": 0})
	assert_near(c.zombie_speed_mult(), 1.15)
	assert_eq(c.zombie_health(1000), 1250)
	assert_eq(c.zombie_health(150), 188)
	assert_eq(c.start_round(), 6)
	assert_false(c.has_station())
	var lw := c.loot_weapon(w)
	assert_eq(GameWeapon.rarity_of(lw), 0, "butin commun")
	assert_eq(GameWeapon.level_of(lw), 7, "niveau gardé")
	assert_eq(String(lw.uid), "loot:5")
	assert_eq(WeeklyChallenge.starting_ids(), BaseWeapons.default_selection(), "armes de base pour tous")
	var hands := Session.starting_hands(WeeklyChallenge.starting_ids())
	assert_eq(hands.size(), 2)
	for h in hands:
		assert_true(WeeklyChallenge.build_allowed(h), "arme de départ constructible")
	assert_false(WeeklyChallenge.build_allowed(GameWeapon.make("galil", 1, 0)), "arme de l'arsenal refusée")
	assert_false(WeeklyChallenge.build_allowed(GameWeapon.make(WeaponDB.STARTING_WEAPON, 5, 0)), "arme de base améliorée refusée")
	assert_false(WeeklyChallenge.build_allowed(GameWeapon.make(WeaponDB.STARTING_WEAPON, 1, 2)), "rareté refusée")
	assert_false(WeeklyChallenge.build_allowed({}))
	assert_true(c.goal_reached(10, true))
	assert_true(c.goal_reached(15, true))
	assert_false(c.goal_reached(9, true), "trop tôt")
	assert_false(c.goal_reached(20, false), "sans évacuation")


# --------------------------------------------------------------------------
# Récompense et meilleur résultat
# --------------------------------------------------------------------------

func test_reward_once_per_week() -> void:
	var c := _challenge({})
	var pr := PlayerProfile.new()
	var r := c.apply_to(pr, 7, true)
	assert_false(r.goal or r.rewarded, "objectif manqué")
	assert_eq(pr.xp, 0)
	assert_eq(pr.weekly.entry("2026-W41"), {"best": 7, "evac": 7, "runs": 1, "rewarded": false})
	r = c.apply_to(pr, 12, true)
	assert_true(r.goal and r.rewarded, "objectif atteint : récompense")
	assert_true(r.new_best)
	assert_eq(r.xp, 400, "XP au niveau 1")
	assert_eq(pr.xp, 400)
	assert_eq(pr.sample_count("dog_fang"), 4)
	assert_eq(pr.sample_count("dog_fur"), 3)
	r = c.apply_to(pr, 14, true)
	assert_true(r.goal and not r.rewarded, "une seule fois par semaine")
	assert_eq(pr.xp, 400)
	assert_eq(pr.sample_count("dog_fang"), 4)
	r = c.apply_to(pr, 9, false)
	assert_false(r.new_best, "moins bien")
	assert_eq(pr.weekly.entry("2026-W41"), {"best": 14, "evac": 14, "runs": 4, "rewarded": true})
	# Semaine suivante : nouvelle récompense, XP selon le niveau.
	var next := _challenge({})
	next.week = 42
	next.key = "2026-W42"
	pr.xp = PlayerProfile.xp_for_level(11)
	r = next.apply_to(pr, 10, true)
	assert_true(r.rewarded, "nouvelle semaine")
	assert_eq(r.xp, HubRewards.contract_xp(400, 11))
	assert_eq(pr.sample_count("dog_fang"), 8)
	# Enregistré sur le profil du disque.
	ProfileStore.save_profile(PlayerProfile.new(), file)
	var res := c.apply_result(10, true, file)
	assert_true(res.rewarded)
	assert_eq(res.total_xp, 400)
	var back := ProfileStore.load_profile(file)
	assert_true(back.weekly.is_rewarded("2026-W41"))
	assert_false(c.apply_result(11, true, file).rewarded, "relu du disque : déjà donnée")


func test_best_text_and_prune() -> void:
	var c := _challenge({})
	var pr := PlayerProfile.new()
	assert_eq(c.best_text(pr), "pas encore tenté")
	pr.weekly.record("2026-W41", 8, false)
	assert_eq(c.best_text(pr), "manche 8")
	pr.weekly.record("2026-W41", 6, true)
	assert_eq(c.best_text(pr), "manche 8, évacuation à la manche 6")
	assert_false(pr.weekly.record("bad", 3, true), "clé illisible ignorée")
	assert_false(pr.weekly.played("bad"))
	for w in range(1, 20):
		pr.weekly.record(WeeklyChallenge.key_of(2025, w), w, false)
	assert_eq(pr.weekly.weeks.size(), WeeklyRecord.KEEP_WEEKS, "anciennes semaines oubliées")
	assert_true(pr.weekly.played("2026-W41"), "la plus récente reste")
	assert_false(pr.weekly.played("2025-W01"))


func test_profile_migration_v2_to_v3() -> void:
	# Profil enregistré par la version précédente (format 2), avec une clé
	# « weekly » étrangère à ce format (fichier modifié) : ignorée.
	var v2 := {"format": "profile", "version": 2, "profile": {"xp": 900, "samples": {"dog_fang": 3},
		"weekly": {"2026-W41": {"best": 99, "rewarded": true}}}}
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_string(JSON.stringify(v2))
	f.close()
	var pr := ProfileStore.load_profile(file)
	assert_eq(ProfileStore.last_status, "ok")
	assert_eq(pr.xp, 900)
	assert_true(pr.weekly.weeks.is_empty(), "aucun défi joué après migration")
	pr.weekly.record("2026-W41", 11, true)
	pr.weekly.mark_rewarded("2026-W41")
	ProfileStore.save_profile(pr, file)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	assert_eq(int(doc.version), ProfileStore.VERSION, "réécrit dans la version courante")
	assert_eq(doc.profile.weekly, {"2026-W41": {"best": 11.0, "evac": 11.0, "runs": 1.0, "rewarded": true}})
	var back := ProfileStore.load_profile(file)
	assert_eq(back.to_dict(), pr.to_dict(), "v3 identique après rechargement")
	# Entrées illisibles écartées (copie du fichier gardée), le reste lu.
	var v3 := {"format": "profile", "version": 3, "profile": {"weekly": {"2026-W41": {"best": 4, "evac": "x", "rewarded": 1},
		"2026-W99": {"best": 1}, "oops": 3, "2026-W40": "x"}}}
	var dropped := [0]
	var w := WeeklyRecord.from_dict(v3.profile.weekly, dropped)
	assert_eq(dropped[0], 3, "trois entrées écartées")
	assert_eq(w.entry("2026-W41"), {"best": 4, "evac": 0, "runs": 0, "rewarded": false}, "valeurs illisibles : défaut")
	var d2 := [0]
	assert_true(WeeklyRecord.from_dict("x", d2).weeks.is_empty())
	assert_eq(d2[0], 1)


# --------------------------------------------------------------------------
# Textes
# --------------------------------------------------------------------------

func test_texts() -> void:
	var c := _challenge({"fast_zombies": 0.15})
	c.modifiers[0].title = {"fr": "Horde pressée", "en": "Hasty Horde"}
	c.modifiers[0].text = {"fr": "Zombies {pct} % plus rapides.", "en": "Zombies {pct}% faster."}
	assert_eq(WeeklyChallenge.mod_text(c.modifiers[0]), "Zombies 15 % plus rapides.")
	assert_eq(c.goal_text(), "Évacuez à la manche 10 ou plus")
	assert_eq(c.week_label(), "S41")
	assert_eq(c.reward_text(1), "+400 XP · 4 %s, 3 %s" % [LootRules.sample_name("dog_fang").to_lower(), LootRules.sample_name("dog_fur").to_lower()])
	Settings.language = "en"
	assert_eq(WeeklyChallenge.mod_text(c.modifiers[0]), "Zombies 15% faster.")
	assert_eq(c.goal_text(), "Evacuate at round 10 or later")
	assert_eq(c.week_label(), "W41")


func test_match_report() -> void:
	var r := MatchResult.new()
	r.xp = 120
	r.loot = {"kept": false, "weapons": [["galil", 5, 1]], "parts": 0, "samples": {},
		"challenge": {"week": 41, "goal": true, "goal_round": 10, "rewarded": true, "xp": 400, "samples": {"dog_fang": 4}, "new_best": true}}
	var t := r.loot_text()
	assert_true(t.begins_with("DÉFI S41 RÉUSSI : +400 XP, 4 "), t)
	assert_true(t.contains("nouveau record") and t.contains("butin du défi non gardé") and t.ends_with("+120 XP"), t)
	r.loot.challenge = {"week": 41, "goal": false, "goal_round": 10}
	assert_true(r.loot_text().begins_with("DÉFI S41 : objectif manqué (évacuez à la manche 10 ou plus)"), r.loot_text())
	r.loot.challenge = {"week": 41, "goal": true, "rewarded": false}
	assert_true(r.loot_text().contains("récompense déjà reçue"), r.loot_text())
	Settings.language = "en"
	r.loot.challenge = {"week": 41, "goal": false, "goal_round": 10}
	assert_true(r.loot_text().begins_with("W41 CHALLENGE: goal missed"), r.loot_text())
