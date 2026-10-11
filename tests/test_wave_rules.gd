extends TestCase
## Schéma des vagues spéciales et de boss (WaveRules, GAME_CONCEPT.md §4.4) et
## sa place dans le format 18 des cartes de l'éditeur (carte.json « vagues »).


func test_defaut_toutes_les_5_manches() -> void:
	var s := WaveRules.default_schedule()
	var specials := []
	for n in range(1, 31):
		if WaveRules.wave_kind(s, n) == WaveRules.SPECIAL:
			specials.append(n)
	assert_eq(specials, [5, 10, 15, 20, 25, 30], "vagues spéciales par défaut (sans boss défini)")
	assert_eq(WaveRules.wave_kind(s, 4), "", "manche 4 : normale")


func test_boss_sans_boss_ne_fait_rien() -> void:
	var s := WaveRules.default_schedule()
	assert_eq(WaveRules.wave_kind(s, 15, false), WaveRules.SPECIAL, "manche 15 sans boss : vague spéciale")
	assert_eq(WaveRules.wave_kind(s, 15, true), WaveRules.BOSS, "manche 15 avec un boss : vague de boss")
	assert_eq(WaveRules.wave_kind(s, 30, true), WaveRules.BOSS)
	assert_eq(WaveRules.wave_kind(s, 20, true), WaveRules.SPECIAL, "manche 20 : pas de boss prévu")
	var only_boss := WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}})
	assert_eq(WaveRules.wave_kind(only_boss, 15, false), "", "boss sans boss défini et sans spéciale : manche normale")


func test_schema_configurable() -> void:
	var s := WaveRules.parse({"speciale": {"premiere": 3, "intervalle": 4}, "boss": {"premiere": 0, "intervalle": 0}})
	var specials := []
	for n in range(1, 16):
		if WaveRules.wave_kind(s, n, true) != "":
			specials.append(n)
	assert_eq(specials, [3, 7, 11, 15], "première à 3 puis toutes les 4 ; boss jamais")
	var once := WaveRules.parse({"speciale": {"premiere": 6, "intervalle": 0}})
	assert_true(WaveRules.scheduled(once.speciale, 6) and not WaveRules.scheduled(once.speciale, 12), "intervalle 0 : une seule")


func test_prochaine_vague() -> void:
	var s := WaveRules.default_schedule()
	assert_eq(WaveRules.next_after(s, WaveRules.SPECIAL, 0), 5)
	assert_eq(WaveRules.next_after(s, WaveRules.SPECIAL, 5), 10)
	assert_eq(WaveRules.next_after(s, WaveRules.SPECIAL, 7), 10)
	assert_eq(WaveRules.next_after(s, WaveRules.BOSS, 15), 30)
	var never := WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 5}})
	assert_eq(WaveRules.next_after(never, WaveRules.SPECIAL, 0), 0, "premiere 0 : jamais")


func test_lecture_tolerante() -> void:
	assert_eq(WaveRules.parse(null), WaveRules.DEFAULT, "absent : défaut")
	assert_eq(WaveRules.parse("x"), WaveRules.DEFAULT)
	var s := WaveRules.parse({"speciale": {"premiere": "5", "intervalle": -3}, "boss": {"premiere": 99999}})
	assert_eq(s.speciale.premiere, 5, "texte ignoré : défaut")
	assert_eq(s.speciale.intervalle, 0, "borné à 0")
	assert_eq(s.boss.premiere, WaveRules.ROUND_MAX, "borné au maximum")
	assert_true(WaveRules.is_default({}), "vide : défaut")


func test_carte_format_18() -> void:
	assert_true(EditorMap.FORMAT >= 18, "format 18 et plus")
	var m := EditorMap.blank()
	assert_false(m.carte.has("vagues"), "carte neuve : schéma par défaut, non écrit")
	EditorMap.set_waves(m.carte, WaveRules.SPECIAL, 4, 6)
	assert_eq(EditorMap.waves_of(m.carte).speciale, {"premiere": 4, "intervalle": 6})
	var texts := m.file_texts()
	assert_true(String(texts["carte.json"]).contains("\"vagues\""), "écrit quand il change")
	assert_true(String(texts["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT), "écrit au format courant")
	var back := EditorMap.from_texts(texts)
	assert_eq(EditorMap.waves_of(back.carte).speciale.premiere, 4, "relu")
	EditorMap.set_waves(back.carte, WaveRules.SPECIAL, 5, 5)
	assert_false(back.carte.has("vagues"), "retour au défaut : clé retirée")
	# Ancienne carte (format 17) : lue telle quelle, schéma par défaut.
	var old := m.file_texts()
	old["carte.json"] = String(old["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 17")
	var o := EditorMap.from_texts(old)
	assert_true(o.load_errors.is_empty(), "format 17 lu sans erreur")
	# Contrôle des cartes reçues : clé admise, valeurs bornées.
	var bad := m.file_texts()
	bad["carte.json"] = String(bad["carte.json"]).replace("\"premiere\":4", "\"premiere\":-1")
	assert_true(String(bad["carte.json"]).contains("\"premiere\":-1"), "remplacement fait")
	assert_false(CustomMapGuard.check_texts(bad).ok, "première manche négative refusée")
	assert_true(CustomMapGuard.check_texts(m.file_texts()).ok, "schéma valide accepté : %s" % str(CustomMapGuard.check_texts(m.file_texts()).get("reasons")))


func test_carte_integree_par_defaut() -> void:
	for id in ["bunker_k7", "test_arena", "test_levels", "draft_arena"]:
		var d := Game.make_map_def(id)
		assert_true(WaveRules.is_default(d.waves), "%s : schéma par défaut" % id)
		assert_eq(d.boss, "", "%s : aucun boss" % id)


## Format 21 : plusieurs types de vagues spéciales, en rotation.
func test_rotation_types() -> void:
	var s := WaveRules.default_schedule()
	assert_eq(WaveRules.special_types(s), ["meute", "brancardier"], "défaut : tous les types")
	assert_eq(WaveRules.special_rank(s, 15), 3, "15 : 3e vague spéciale")
	assert_eq(WaveRules.special_rank(s, 14), 0, "14 : manche normale")
	assert_eq(WaveRules.special_type_at(s, 5), "meute")
	assert_eq(WaveRules.special_type_at(s, 10), "brancardier")
	assert_eq(WaveRules.special_type_at(s, 15), "meute")
	# Avec un boss : la manche 15 est une vague de boss, elle ne compte pas.
	assert_eq(WaveRules.special_type_at(s, 15, true), "", "15 : vague de boss")
	assert_eq(WaveRules.special_type_at(s, 20, true), "meute", "20 : 3e vague spéciale (la 15 est de boss)")
	# Un seul type autorisé : toujours lui.
	var only := WaveRules.parse({"types_speciaux": ["brancardier"]})
	assert_eq(WaveRules.special_type_at(only, 5), "brancardier")
	assert_eq(WaveRules.special_type_at(only, 10), "brancardier")
	assert_eq(WaveRules.next_special_of(only, WaveRules.MEUTE, 0), 0, "meute interdite : jamais")
	assert_eq(WaveRules.next_special_of(only, WaveRules.BRANCARDIER, 5), 10)
	# Lecture tolérante : inconnus écartés, doublons fusionnés, ordre canonique, vide : tous.
	assert_eq(WaveRules.parse_types(["x", "brancardier", "meute", "meute"]), ["meute", "brancardier"])
	assert_eq(WaveRules.parse_types([]), ["meute", "brancardier"], "liste vide : tous")
	assert_eq(WaveRules.parse_types("meute"), ["meute", "brancardier"], "illisible : tous")
	# Une seule vague spéciale (intervalle 0).
	var once := WaveRules.parse({"speciale": {"premiere": 7, "intervalle": 0}})
	assert_eq(WaveRules.special_type_at(once, 7), "meute")
	assert_eq(WaveRules.next_special_of(once, WaveRules.BRANCARDIER, 0), 0, "une seule vague : jamais le 2e type")


func test_carte_format_21() -> void:
	assert_true(EditorMap.FORMAT >= 21, "format 21 et plus")
	var m := EditorMap.blank()
	EditorMap.set_special_types(m.carte, ["brancardier"])
	assert_eq(WaveRules.special_types(EditorMap.waves_of(m.carte)), ["brancardier"])
	var texts := m.file_texts()
	assert_true(String(texts["carte.json"]).contains("\"types_speciaux\""), "écrit quand il change")
	assert_true(CustomMapGuard.check_texts(texts).ok, "carte reçue acceptée : %s" % str(CustomMapGuard.check_texts(texts).get("reasons")))
	var back := EditorMap.from_texts(texts)
	assert_eq(WaveRules.special_types(EditorMap.waves_of(back.carte)), ["brancardier"], "relu")
	EditorMap.set_special_types(back.carte, ["meute", "brancardier"])
	assert_false(back.carte.has("vagues"), "tous les types : retour au défaut, clé retirée")
	# Première manche changée, types par défaut : la liste n'est pas écrite.
	EditorMap.set_waves(back.carte, WaveRules.SPECIAL, 4, 6)
	assert_false((back.carte.vagues as Dictionary).has(WaveRules.TYPES_KEY), "types par défaut non écrits")
	# Type inconnu dans une carte reçue : refusé.
	var bad := m.file_texts()
	bad["carte.json"] = String(bad["carte.json"]).replace("\"brancardier\"", "\"chirurgien\"")
	assert_true(String(bad["carte.json"]).contains("chirurgien"), "remplacement fait")
	assert_false(CustomMapGuard.check_texts(bad).ok, "type inconnu refusé")
	# Ancienne carte (format 20) : lue telle quelle, tous les types.
	var old := EditorMap.blank().file_texts()
	old["carte.json"] = String(old["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": 20")
	var o := EditorMap.from_texts(old)
	assert_true(o.load_errors.is_empty(), "format 20 lu sans erreur")
	assert_eq(WaveRules.special_types(EditorMap.waves_of(o.carte)), ["meute", "brancardier"])
