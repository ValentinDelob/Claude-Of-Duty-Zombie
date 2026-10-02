extends TestCase
## Personnages et répliques (docs/CHARACTERS.md) : textes complets dans les deux
## langues et fichiers son générés pour chacun.

const CATEGORIES_MIN := 60


func test_seven_characters_with_complete_lines() -> void:
	assert_eq(CharacterDB.IDS.size(), 7, "sept personnages (les quatre de Kino, Mercer, Berg et Jojo)")
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
const CAST_JSON := "res://tools/voices/cast.json"


## Personnages marqués `"pending_audio": true` dans tools/voices/cast.json :
## voix pas encore générées (personnage tout juste écrit), dispensés de
## l'exigence « toutes les voix » ; la marque est retirée une fois générées.
static func pending_audio() -> Array:
	var out := []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAST_JSON))
	var chars: Variant = data.get("characters", {}) if data is Dictionary else {}
	if chars is Dictionary:
		for ch in chars:
			if chars[ch] is Dictionary and chars[ch].get("pending_audio", false) == true:
				out.append(ch)
	return out


func test_pending_audio_marks_are_known_characters() -> void:
	assert_true(FileAccess.file_exists(CAST_JSON), "cast.json lisible")
	for ch in pending_audio():
		assert_true(ch in CharacterDB.IDS, "personnage en attente de voix inconnu : %s" % ch)


func test_voice_files_match_lines() -> void:
	var pending := pending_audio()
	var missing := 0
	var total := 0
	var per_lang := {}
	for lang in Settings.LANGUAGES:
		per_lang[lang] = 0
		for ch in CharacterDB.IDS:
			if ch in pending:
				continue
			var lines := CharacterDB.lines(ch)
			for cat in lines:
				for i in (lines[cat] as Array).size():
					total += 1
					if ResourceLoader.exists(CharacterDB.vox_path(lang, ch, cat, i)):
						per_lang[lang] += 1
					else:
						missing += 1
	@warning_ignore("integer_division")
	print("[vox] voix générées : fr %d, en %d sur %d par langue (en attente : %s)" % [per_lang.fr, per_lang.en, total / 2, pending])
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
