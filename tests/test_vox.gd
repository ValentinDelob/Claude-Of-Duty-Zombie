extends TestCase
## Personnages et répliques (docs/CHARACTERS.md) : textes complets dans les deux
## langues et fichiers son générés pour chacun.

const CATEGORIES_MIN := 60


func test_four_characters_with_complete_lines() -> void:
	assert_eq(CharacterDB.IDS.size(), 4, "quatre personnages")
	var cats: Array = CharacterDB.lines("callahan").keys()
	assert_true(cats.size() >= CATEGORIES_MIN, "%d catégories" % cats.size())
	for ch in CharacterDB.IDS:
		var lines := CharacterDB.lines(ch)
		for cat in cats:
			if cat == "tease_" + ch:
				continue
			assert_true(lines.has(cat), "%s : catégorie %s" % [ch, cat])
		assert_false(lines.has("tease_" + ch), "%s ne se taquine pas lui-même" % ch)
		for cat in lines:
			for v in lines[cat]:
				assert_true(String(v.get("fr", "")) != "" and String(v.get("en", "")) != "", "%s/%s : fr et en" % [ch, cat])


## Génération des voix en cours (tools/voices/make_voices.py) : les répliques
## sans fichier restent muettes en jeu. Ce test vérifie la couverture actuelle
## et qu'aucun fichier ne correspond à une réplique inexistante.
## TODO : remettre l'exigence « toutes les voix dans les deux langues » quand la
## génération est terminée (VOX_COMPLETE = true).
const VOX_COMPLETE := true


func test_voice_files_match_lines() -> void:
	var missing := 0
	var total := 0
	var per_lang := {}
	for lang in Settings.LANGUAGES:
		per_lang[lang] = 0
		for ch in CharacterDB.IDS:
			var lines := CharacterDB.lines(ch)
			for cat in lines:
				for i in (lines[cat] as Array).size():
					total += 1
					if ResourceLoader.exists(CharacterDB.vox_path(lang, ch, cat, i)):
						per_lang[lang] += 1
					else:
						missing += 1
	@warning_ignore("integer_division")
	print("[vox] voix générées : fr %d, en %d sur %d par langue" % [per_lang.fr, per_lang.en, total / 2])
	if VOX_COMPLETE:
		assert_eq(missing, 0, "toutes les voix dans les deux langues")
	else:
		assert_true(per_lang.fr > 0, "des voix françaises sont présentes")
	# Aucun fichier orphelin (catégorie ou variante inconnue).
	var orphans: Array = []
	for lang in Settings.LANGUAGES:
		for ch in CharacterDB.IDS:
			var dir: String = CharacterDB.VOX_DIR + lang + "/" + ch
			if not DirAccess.dir_exists_absolute(dir):
				continue
			for f in DirAccess.get_files_at(dir):
				if not f.ends_with(".ogg"):
					continue
				var base := f.get_basename()
				var cat := base.substr(0, base.rfind("_"))
				var i := int(base.substr(base.rfind("_") + 1))
				if i >= CharacterDB.variants(ch, cat):
					orphans.append(dir + "/" + f)
	assert_true(orphans.is_empty(), "fichiers sans réplique : %s" % [orphans.slice(0, 3)])


func test_slots_map_to_characters_with_the_cast_rotation() -> void:
	var before := Net.cast_offset
	Net.cast_offset = 0
	assert_eq(CharacterDB.IDS[CharacterDB.index_of_slot(0)], "callahan")
	assert_eq(CharacterDB.IDS[CharacterDB.index_of_slot(3)], "weissmann")
	Net.cast_offset = 2
	assert_eq(CharacterDB.IDS[CharacterDB.index_of_slot(0)], "arakawa", "rotation tirée par l'hôte")
	assert_eq(CharacterDB.IDS[CharacterDB.index_of_slot(3)], "orlov")
	Net.cast_offset = before


func test_box_categories() -> void:
	assert_eq(VoxSystem.box_category("ray"), "box_ray")
	assert_eq(VoxSystem.box_category("thunder"), "box_thunder")
	assert_eq(VoxSystem.box_category(ThrowableRules.MONKEY_ID), "box_monkey")
	assert_eq(VoxSystem.box_category("python"), "box_bad", "revolver : décevant")
	assert_eq(VoxSystem.box_category("hk21"), "box_lmg", "mitrailleuse")
	assert_eq(VoxSystem.box_category("spas12"), "box_shotgun", "fusil à pompe")
	assert_eq(VoxSystem.box_category("dragunov"), "box_sniper", "fusil de précision")
	assert_eq(VoxSystem.box_category("law"), "box_launcher", "lance-roquettes")
	assert_eq(VoxSystem.box_category("galil"), "box_good", "fusil d'assaut")
