extends TestCase
## Page DÉTAILS du CODEX (CodexDetails) : chaque chiffre est lu dans les
## règles du jeu (dégâts, santé du joueur, PV relatifs, manches des vagues,
## XP, ferraille, échantillons, pièces, armes), textes FR / EN, point faible
## et conseil de codex.json, page verrouillée pour un ennemi inconnu.

var _lang := ""


func before_each() -> void:
	_lang = Settings.language
	Settings.language = "fr"
	CodexData.clear_cache()


func after_each() -> void:
	Settings.language = _lang
	CodexData.clear_cache()


func _card(id: String) -> Dictionary:
	for c in CodexData.default().cards():
		if c.id == id:
			return c
	return {}


func _section(page: Dictionary, id: String) -> Dictionary:
	for s in page.sections:
		if s.id == id:
			return s
	return {}


func _row(page: Dictionary, sec: String, id: String) -> Dictionary:
	for r in _section(page, sec).get("rows", []):
		if r.id == id:
			return r
	return {}


func test_unknown_is_locked() -> void:
	var page := CodexDetails.of(_card("nurse"), false, 0)
	assert_true(page.locked, "inconnue : verrouillée")
	assert_eq(page.sections.size(), 0, "aucun chiffre dévoilé")
	assert_eq(page.hint, CodexData.round_hint(int(_card("nurse").round)))
	assert_true(CodexDetails.of({}, true, 0).locked, "carte vide")


func test_codex_texts_load() -> void:
	var d := CodexData.default()
	assert_eq(d.warnings.size(), 0, "codex.json sans avertissement : %s" % ", ".join(d.warnings))
	for c in d.cards():
		assert_false((c.weak as Dictionary).is_empty(), "%s : point faible" % c.id)
		assert_false((c.tip as Dictionary).is_empty(), "%s : conseil" % c.id)
		for t in [c.weak, c.tip]:
			for lang in ["fr", "en"]:
				var s := String(t[lang])
				var digits := RegEx.create_from_string("[0-9]")
				assert_true(digits.search(s) == null, "%s : aucun chiffre écrit dans codex.json (%s)" % [c.id, s])
	var bad := CodexData.from_text(JSON.stringify({"format": "hub_codex", "version": 1, "enemies": [
		{"id": "walker", "name": {"fr": "a", "en": "a"}, "text": {"fr": "t", "en": "t"}, "round": 1, "weak": "x"}]}))
	assert_eq(bad.entries.size(), 1, "« weak » illisible : la fiche reste")
	assert_eq(bad.warnings.size(), 1, "avec un avertissement")
	assert_true((bad.entries[0].weak as Dictionary).is_empty())


func test_zombies_values_from_rules() -> void:
	var card := _card("zombies")
	var page := CodexDetails.of(card, true, 136)
	assert_false(page.locked)
	var ids := []
	for s in page.sections:
		ids.append(s.id)
	assert_eq(ids, [CodexDetails.ATTACKS, CodexDetails.TOUGH, CodexDetails.WHEN, CodexDetails.REWARDS, CodexDetails.LOOT,
		CodexDetails.WEAK, CodexDetails.TIP], "ordre des sections")
	var claw := _row(page, CodexDetails.ATTACKS, "claw")
	assert_eq(claw.value, "%d dégâts" % Combat.ZOMBIE_DAMAGE, "Combat.ZOMBIE_DAMAGE")
	assert_eq(claw.note, "%d coups et tu es à terre" % ceili(float(PlayerData.BASE_HEALTH) / Combat.ZOMBIE_DAMAGE))
	assert_eq(claw.tone, "bad")
	assert_eq(_row(page, CodexDetails.TOUGH, "hp").value, "%d PV" % RoundRules.zombie_health(1))
	assert_eq(_row(page, CodexDetails.TOUGH, "growth").value, "+%d PV" % (RoundRules.zombie_health(2) - RoundRules.zombie_health(1)))
	assert_eq(_row(page, CodexDetails.WHEN, "runners").value, "dès la manche %d" % RoundRules.RUNNERS_FROM_ROUND)
	assert_eq(_row(page, CodexDetails.REWARDS, "xp").value, CodexDetails.xp_text(card))
	assert_eq(_row(page, CodexDetails.REWARDS, "scrap_kill").value, str(PointsRules.KILL))
	assert_eq(_row(page, CodexDetails.REWARDS, "scrap_hit").value, str(PointsRules.HIT))
	assert_true(String(_row(page, CodexDetails.REWARDS, "scrap_hit").note).contains(str(PointsRules.HIT_CAP)))
	assert_eq(_row(page, CodexDetails.REWARDS, "kills").value, "136")
	assert_eq(_row(page, CodexDetails.LOOT, "none").value, "aucun", "zombies ordinaires : ni échantillon ni pièce")
	assert_true(_row(page, CodexDetails.LOOT, "part").is_empty())
	assert_eq(_section(page, CodexDetails.WEAK).text, "La tête : chaque arme y fait plus de dégâts.")


func test_dog_pack_values() -> void:
	var page := CodexDetails.of(_card("dog"), true, 54)
	assert_eq(_row(page, CodexDetails.ATTACKS, "bite").value, "%d dégâts" % DogRules.BITE_DAMAGE)
	assert_eq(_row(page, CodexDetails.ATTACKS, "burst").value, "%d dégâts" % DogRules.EXPLODE_DAMAGE)
	assert_eq(_row(page, CodexDetails.TOUGH, "hp").value, "moins qu’un zombie",
			"%d PV contre %d" % [DogRules.dog_health(1), RoundRules.zombie_health(int(_card("dog").round))])
	# Manches : rotation par défaut de WaveRules.
	var sched := WaveRules.default_schedule()
	var boss := WaveRules.has_boss(sched)
	var r1 := WaveRules.next_special_of(sched, WaveRules.MEUTE, 0, boss)
	var r2 := WaveRules.next_special_of(sched, WaveRules.MEUTE, r1, boss)
	var r3 := WaveRules.next_special_of(sched, WaveRules.MEUTE, r2, boss)
	assert_eq(_row(page, CodexDetails.WHEN, "wave").value, "manches %d, %d, %d…" % [r1, r2, r3])
	assert_eq(r1, int(_card("dog").round), "première meute = manche de codex.json")
	assert_eq(_row(page, CodexDetails.WHEN, "pack").value, "%d chiens par joueur" % DogRules.PER_PLAYER_EARLY)
	# Butin : échantillons (LootRules.SAMPLE_CHANCE), pièce, arme.
	var fang := _row(page, CodexDetails.LOOT, "sample_dog_fang")
	assert_eq(fang.sample, "dog_fang")
	assert_eq(fang.value, SampleCatalog.percent(LootRules.SAMPLE_CHANCE))
	assert_eq(_row(page, CodexDetails.LOOT, "part").value, CodexDetails.pct(LootRules.PART_CHANCE))
	var w := _row(page, CodexDetails.LOOT, "weapon")
	assert_eq(w.value, "%d par joueur" % LootRules.WEAPONS_SPECIAL)
	var top: float = LootRules.RARITY_WEIGHTS[3] + LootRules.RARITY_WEIGHTS[4]
	assert_true(String(w.note).ends_with(CodexDetails.pct(top / 100.0)), "légendaire ou mieux : %s" % w.note)


func test_brancardier_nurse_surgeon() -> void:
	var br := CodexDetails.of(_card("brancardier"), true, 7)
	assert_eq(_row(br, CodexDetails.ATTACKS, "charge").value, "%d dégâts" % BrancardRules.CHARGE_DAMAGE)
	assert_eq(_row(br, CodexDetails.ATTACKS, "smash").value, "%d dégâts" % BrancardRules.SMASH_DAMAGE)
	assert_eq(_row(br, CodexDetails.TOUGH, "hp").value, "comme %d zombies" % roundi(BrancardRules.HP_FACTOR), "Encaisse comme 10 zombies")
	assert_true(String(_row(br, CodexDetails.TOUGH, "hp").note).contains(CodexDetails.pct(BrancardRules.HP_GROWTH)))
	assert_eq(_row(br, CodexDetails.WEAK, "stun").value, "sonné " + CodexDetails.secs(BrancardRules.STUN_TIME))
	assert_eq(_row(br, CodexDetails.WHEN, "escort").value, "%d zombies par joueur" % BrancardRules.ESCORT_PER_PLAYER)
	var nu := CodexDetails.of(_card("nurse"), true, 0)
	assert_eq(_row(nu, CodexDetails.ATTACKS, "scream").value, "%d dégâts" % NurseRules.SCREAM_DAMAGE)
	assert_true(String(_row(nu, CodexDetails.ATTACKS, "scream").note).contains(CodexDetails.secs(NurseRules.DAZE_TIME_MAX)))
	assert_eq(_row(nu, CodexDetails.ATTACKS, "stab").value, "%d dégâts" % NurseRules.STAB_DAMAGE)
	assert_eq(_row(nu, CodexDetails.TOUGH, "hp").value, "comme %d zombies" % roundi(NurseRules.HP_FACTOR))
	var su := CodexDetails.of(_card("surgeon"), true, 1)
	assert_eq(_row(su, CodexDetails.ATTACKS, "slash").value, "%d × %d dégâts" % [SurgeonRules.SLASH_HITS, SurgeonRules.SLASH_DAMAGE])
	assert_eq(_row(su, CodexDetails.ATTACKS, "throw").value, "%d dégâts chacun" % SurgeonRules.THROW_DAMAGE)
	assert_eq(_row(su, CodexDetails.ATTACKS, "shock").value, "%d dégâts" % SurgeonRules.SHOCK_DAMAGE)
	assert_eq(_row(su, CodexDetails.TOUGH, "hp").value, "comme %d zombies" % roundi(SurgeonRules.HP_FACTOR))
	assert_eq(_row(su, CodexDetails.TOUGH, "players").value, "+" + CodexDetails.pct(SurgeonRules.PLAYER_HP))
	var b1 := WaveRules.next_boss_of(WaveRules.default_schedule(), WaveRules.CHIRURGIEN, 0)
	assert_true(String(_row(su, CodexDetails.WHEN, "wave").value).begins_with("manches %d, " % b1))
	assert_eq(_row(su, CodexDetails.WHEN, "wave").label, "Vague de boss")
	assert_eq(_row(su, CodexDetails.LOOT, "sample_surgeon_heart").value, SampleCatalog.percent(LootRules.BOSS_SAMPLE_CHANCE))
	assert_eq(_row(su, CodexDetails.LOOT, "weapon").value, "%d par joueur" % LootRules.WEAPONS_BOSS)
	assert_eq(_row(su, CodexDetails.REWARDS, "xp").value, str(XpRules.base_xp(XpRules.SURGEON)))


func test_english() -> void:
	Settings.language = "en"
	var page := CodexDetails.of(_card("brancardier"), true, 1200)
	assert_eq(_section(page, CodexDetails.ATTACKS).title, "WHAT IT DOES TO YOU")
	assert_eq(_row(page, CodexDetails.ATTACKS, "charge").value, "%d damage" % BrancardRules.CHARGE_DAMAGE)
	assert_eq(_row(page, CodexDetails.TOUGH, "hp").value, "like %d zombies" % roundi(BrancardRules.HP_FACTOR))
	assert_eq(_row(page, CodexDetails.REWARDS, "kills").value, "1,200")
	assert_eq(_section(page, CodexDetails.TIP).text, "When he scrapes the floor, stand in front of a wall and sidestep at the last moment.")
	assert_eq(CodexDetails.of(_card("nurse"), false, 0).hint, "May appear from round %d" % int(_card("nurse").round))


func test_number_formats() -> void:
	assert_eq(CodexDetails.pct(0.05), "5" + String.chr(0xA0) + "%")
	assert_eq(CodexDetails.pct(0.075), "7,5" + String.chr(0xA0) + "%")
	assert_eq(CodexDetails.secs(1.2), "1,2" + String.chr(0xA0) + "s")
	assert_eq(CodexDetails.hits_to_down(PlayerData.BASE_HEALTH * 2), 1)
	assert_eq(CodexDetails.hits_note(PlayerData.BASE_HEALTH), "un seul coup et tu es à terre")
	assert_eq(CodexDetails.as_zombies(0.5), "moins qu’un zombie")
	assert_eq(CodexDetails.as_zombies(1.0), "comme un zombie")
	Settings.language = "en"
	assert_eq(CodexDetails.pct(0.075), "7.5%")
	assert_eq(CodexDetails.secs(3.0), "3 s")
