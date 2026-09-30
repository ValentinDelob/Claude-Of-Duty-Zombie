extends TestCase
## Textes du jeu en français ET en anglais (Lang, règle du projet).
##
## * Chaque Lang.t("fr", "en") du code a ses deux textes, les mêmes
##   paramètres (%d, %s...) et pas d'anglais laissé en français.
## * Chaque table {"fr": ..., "en": ...} a ses deux textes.
## * Les tables de textes du jeu (atouts, bonus, armes, dossier de combat,
##   tableau des scores, générique, cartes) existent dans les deux langues.
## * Balayage : aucun texte français en dur affecté à un texte affiché
##   (.text =, invites [F], bandeaux, boutons...). Liste d'exceptions : ALLOW.

const ROOTS := ["res://scripts"]
## Accents du français (un texte anglais n'en a pas).
const FR_ACCENTS := "éèêëàâùûüçôîïœÉÈÊÀÂÙÛÇÔÎŒ"
## Mots qui trahissent un texte français (sans accent).
const FR_WORDS := ["le", "la", "les", "des", "du", "une", "pour", "et", "pas", "de", "avec", "sur", "est",
	"vous", "votre", "vos", "partie", "joueur", "joueurs", "manche", "manches", "retour", "acheter", "ouvrir",
	"courant", "maintenir", "appuyer", "carte", "aucun", "aucune", "plus", "dans", "sans", "ou", "au", "aux",
	"munitions", "rechargement", "chargement", "connexion", "adresse", "invalide", "annuler", "quitter",
	"rejoindre", "choisissez", "survivant", "zombies abattus"]
## Affectations et appels qui montrent un texte au joueur.
const DISPLAY_PATTERNS := [
	"\\.text\\s*[+]?=\\s*\"", "tooltip_text\\s*=\\s*\"", "placeholder_text\\s*=\\s*\"",
	"show_banner\\(\\s*\"", "flash_message\\(\\s*\"", "show_center\\(\\s*\"", "show_message\\(\\s*\"",
	"show_game_over_table\\(\\s*\"", "set_status\\(\\s*\"", "\\btitle\\(\\s*\"", "\\bbutton\\(\\s*\"",
	"\\btext\\(\\s*\"", "(Ui|Hud|Menu)Style\\.(label|title|button)\\(\\s*\"", "_button\\(\\s*\"",
	"connection_error\\.emit\\(\\s*\"", "session_ended\\.emit\\(\\s*\"", "back_to_menu\\(\\s*\"",
	"return\\s+\"\\[F\\]", "return\\s+\"Maintenir", "deny\\(\\s*pid\\s*,\\s*\"",
]
## Lignes où ces motifs sont permis : pas un texte affiché ou déjà bilingue
## (fichier -> fragments de ligne).
const ALLOW := {
	# Rapport de plantage : texte « français / English » sur la même ligne.
	"res://scripts/game/crash_log.gd": ["/ Session start", "/ Last update", "/ Detected at next start", "/ Last screen", "/ Last log lines"],
}


func _gd_files() -> PackedStringArray:
	var out := PackedStringArray()
	for r in ROOTS:
		_walk(r, out)
	return out


func _walk(dir: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), out)


static func looks_french(s: String) -> bool:
	for c in FR_ACCENTS:
		if s.contains(c):
			return true
	var words := s.to_lower()
	for sep in [".", ",", ":", ";", "!", "?", "(", ")", "[", "]", "«", "»", "—", "-", "'", "\n", "%d", "%s"]:
		words = words.replace(sep, " ")
	var list := words.split(" ", false)
	for w in FR_WORDS:
		if " " in w:
			if (" " + " ".join(list) + " ").contains(" " + w + " "):
				return true
		elif w in list:
			return true
	return false


static func placeholders(s: String) -> PackedStringArray:
	var re := RegEx.create_from_string("%[-+0-9.*]*[sdifxXc%]")
	var out := PackedStringArray()
	for m in re.search_all(s):
		out.append(m.get_string())
	return out


const STR := "\"((?:[^\"\\\\]|\\\\.)*)\""


func test_lang_t_calls_have_both_languages() -> void:
	var re := RegEx.create_from_string("Lang\\.t\\(\\s*" + STR + "\\s*,\\s*" + STR + "\\s*\\)")
	var calls := 0
	for path in _gd_files():
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			calls += 1
			var fr := m.get_string(1)
			var en := m.get_string(2)
			var where := "%s : Lang.t(\"%s\", \"%s\")" % [path.get_file(), fr.left(40), en.left(40)]
			assert_true(fr.strip_edges() != "" and en.strip_edges() != "", "texte vide : " + where)
			assert_eq(placeholders(fr), placeholders(en), "paramètres différents : " + where)
			for c in FR_ACCENTS:
				if en.contains(c):
					failures.append("anglais avec un accent français : " + where)
					break
	assert_true(calls > 300, "appels Lang.t trouvés : %d" % calls)


func test_fr_en_tables_have_both_languages() -> void:
	var pair := RegEx.create_from_string("\"fr\"\\s*:\\s*" + STR + "\\s*,\\s*\"en\"\\s*:\\s*" + STR)
	var fr_only := RegEx.create_from_string("\"fr\"\\s*:\\s*\"")
	for path in _gd_files():
		var src := FileAccess.get_file_as_string(path)
		var pairs := pair.search_all(src)
		for m in pairs:
			var fr := m.get_string(1)
			var en := m.get_string(2)
			# {"fr": "", "en": ""} : texte vide par défaut (description de carte).
			assert_eq(fr.strip_edges() == "", en.strip_edges() == "", "%s : texte manquant dans {\"fr\": \"%s\", \"en\": \"%s\"}" % [path.get_file(), fr.left(30), en.left(30)])
			assert_eq(placeholders(fr), placeholders(en), "%s : paramètres différents (%s)" % [path.get_file(), fr.left(30)])
		for m in fr_only.search_all(src):
			var rest := src.substr(m.get_end(), 300)
			assert_true(rest.contains("\"en\""), "%s : texte \"fr\" sans \"en\" juste après (%s)" % [path.get_file(), rest.left(40)])


func test_game_text_tables() -> void:
	for id in PerkDB.PERKS:
		var d: Dictionary = PerkDB.PERKS[id].desc
		assert_true(String(d.get("fr", "")) != "" and String(d.get("en", "")) != "", "atout %s : effet FR et EN" % id)
	for type in PowerupRules.ALL:
		var n: Variant = PowerupRules.NAMES.get(type)
		assert_true(n is Dictionary and String(n.fr) != "" and String(n.en) != "", "bonus %s : nom FR et EN" % type)
	assert_true(String(ThrowableRules.MONKEY_NAME.en) != "", "singe : nom anglais")
	for f in CareerStats.FIELDS:
		assert_eq(f.size(), 3, "dossier de combat %s : libellés FR et EN" % f[0])
	for c in Scoreboard.COLUMNS:
		assert_eq(c.size(), 2, "tableau des scores : en-tête FR et EN")
	var credits: GDScript = load("res://scripts/ui/screens/credits_screen.gd")
	for l: Array in credits.get_script_constant_map()["LINES"]:
		if l[0] in ["role", "p"]:
			assert_eq(l.size(), 3, "générique : « %s » en anglais" % String(l[1]).left(30))
	# Armes : tout nom français a sa version anglaise.
	var names := []
	for id in WeaponDB.WEAPONS:
		var w: Dictionary = WeaponDB.WEAPONS[id]
		names.append(String(w.get("name", "")))
		names.append(String(w.get("pap_name", "")))
	for id in KnifeDB.KNIVES:
		names.append(String(KnifeDB.KNIVES[id].name))
	for n: String in names:
		if n != "" and (looks_french(n) or n in ["TONNERRE-7", "OURAGAN-77", "FAUCHEUSE", "COUTEAU"]):
			assert_true(WeaponDB.EN_NAMES.has(n), "arme « %s » : nom anglais (WeaponDB.EN_NAMES)" % n)


func test_texts_follow_language_setting() -> void:
	var saved := Settings.language
	Settings.language = "fr"
	var fr := [Hud.bo1_prompt("[F] Acheter M14 [500]"), PerkDB.desc("titan"), PowerupRules.display_name(PowerupRules.MAX_AMMO),
		WeaponDB.display_name("m14", true), InteractionSystem.deny_text(InteractionSystem.NO_POINTS), Game.survived_text(3),
		Interactable.need_power_text(), Scoreboard.columns()[0], Game.make_map_def("kino").zone_display_name("a")]
	Settings.language = "en"
	var en := [Hud.bo1_prompt("[F] Buy M14 [500]"), PerkDB.desc("titan"), PowerupRules.display_name(PowerupRules.MAX_AMMO),
		WeaponDB.display_name("m14", true), InteractionSystem.deny_text(InteractionSystem.NO_POINTS), Game.survived_text(3),
		Interactable.need_power_text(), Scoreboard.columns()[0], Game.make_map_def("kino").zone_display_name("a")]
	Settings.language = saved
	assert_eq(fr, ["Appuyer sur F pour acheter M14 [Coût : 500]", "Santé maximale 250", "MUNITIONS MAX !", "M14 VIEILLE GARDE",
		"Pas assez de points", "VOUS AVEZ SURVÉCU 3 MANCHES", "Le courant doit être rétabli", "JOUEUR", "Hall d'entrée"])
	assert_eq(en, ["Press F to buy M14 [Cost: 500]", "Max health 250", "MAX AMMO!", "M14 OLD GUARD",
		"Not enough points", "YOU SURVIVED 3 ROUNDS", "Power must be activated first", "PLAYER", "Lobby"])


func test_lang_pick() -> void:
	var saved := Settings.language
	Settings.language = "en"
	assert_eq(Lang.pick({"fr": "Porte", "en": "Door"}), "Door")
	assert_eq(Lang.pick({"fr": "Porte"}), "Porte", "anglais absent : français")
	assert_eq(Lang.pick("NOM"), "NOM", "simple chaîne rendue telle quelle")
	assert_eq(Lang.pick(null, "?"), "?")
	Settings.language = "fr"
	assert_eq(Lang.pick({"fr": "Porte", "en": "Door"}), "Porte")
	Settings.language = saved


## Balayage : pas de texte français en dur montré au joueur. Un texte à
## afficher passe par Lang.t / Lang.pick (ou s'ajoute à ALLOW s'il n'est
## pas affiché, ou déjà bilingue).
func test_no_french_literal_in_displayed_text() -> void:
	var patterns := []
	for p: String in DISPLAY_PATTERNS:
		patterns.append(RegEx.create_from_string(p + "((?:[^\"\\\\]|\\\\.)*)\""))
	var skip := RegEx.create_from_string("^\\s*#|\\bprint(err|_rich)?\\(|push_(warning|error)\\(|CrashGuard\\.context|assert\\(")
	var found := []
	for path in _gd_files():
		var allowed: Array = ALLOW.get(path, [])
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line := lines[i]
			if skip.search(line):
				continue
			var ok := false
			for a: String in allowed:
				if line.contains(a):
					ok = true
			if ok:
				continue
			for re: RegEx in patterns:
				for m in re.search_all(line):
					var s := m.get_string(m.get_group_count())
					if looks_french(s):
						found.append("%s:%d : \"%s\"" % [path.trim_prefix("res://"), i + 1, s.left(60)])
	assert_true(found.is_empty(), "textes français en dur (utiliser Lang.t) :\n           " + "\n           ".join(found))


func test_looks_french_heuristic() -> void:
	assert_true(looks_french("Pas assez de points"))
	assert_true(looks_french("RÉANIMÉ"))
	assert_true(looks_french("PLUS DE MUNITIONS"))
	assert_false(looks_french("GAME OVER"))
	assert_false(looks_french("Press %s to reload"))
	assert_false(looks_french("OPTIONS"))
	assert_false(looks_french("PACK-A-PUNCH\n5000"))
