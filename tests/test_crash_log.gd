extends TestCase
## Journaux gardés et rapports de plantage (CrashLog, CrashGuard ;
## docs/ARCHITECTURE.md « Journaux et plantages »), sur un dossier temporaire
## de tests/_out : conservation par jours (13 jours gardés, 15 supprimés),
## taille totale bornée, plantage détecté (marqueur resté -> rapport avec le
## journal de la session), fermeture normale sans rapport, rapports gardés
## 30 jours ; les tests n'écrivent jamais dans les données du joueur (réglages
## des deux projets, tous les lancements de Godot de tools/ avec --log-file) ;
## copie du lanceur identique.

const TMP := "res://tests/_out/crash_log_test"
var root := ""
var logs := ""


func before_each() -> void:
	root = ProjectSettings.globalize_path(TMP)
	_rm(root)
	logs = root.path_join("logs")
	DirAccess.make_dir_recursive_absolute(logs)


func after_each() -> void:
	_rm(root)


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Journal sauvegardé par Godot il y a `days` jours (nom horodaté).
func _old_log(days: float, text := "x", now := -1.0) -> String:
	var t := (now if now >= 0.0 else CrashLog.now_local()) - days * 86400.0
	var p := logs.path_join("godot%s.log" % CrashLog.stamp(t))
	_write(p, text)
	return p


func _marker_id() -> String:
	var f := FileAccess.open(CrashLog.marker_path(root), FileAccess.READ)
	return String((JSON.parse_string(f.get_as_text()) as Dictionary).get("id", "")) if f != null else ""


# ------------------------------------------------------------------ conservation

func test_logs_kept_by_days_not_by_count() -> void:
	var now := CrashLog.now_local()
	var d13 := _old_log(13.0, "x", now)
	var d15 := _old_log(15.0, "x", now)
	var d40 := _old_log(40.0, "x", now)
	_write(logs.path_join("godot.log"), "en cours")
	_write(logs.path_join("reglages.cfg"), "autre")
	for i in 30:
		_old_log(i * 0.1, "x", now)   # beaucoup de lancements récents : tous gardés
	var removed := CrashLog.prune(logs, CrashLog.LOG_DAYS, CrashLog.LOG_MAX_BYTES, now, PackedStringArray(["godot.log"]))
	assert_eq(Array(removed).size(), 2, "seuls les journaux de plus de 14 jours supprimés (%s)" % str(removed))
	assert_true(FileAccess.file_exists(d13), "journal de 13 jours gardé")
	assert_false(FileAccess.file_exists(d15), "journal de 15 jours supprimé")
	assert_false(FileAccess.file_exists(d40), "journal de 40 jours supprimé")
	assert_true(FileAccess.file_exists(logs.path_join("godot.log")), "journal en cours jamais supprimé")
	assert_true(FileAccess.file_exists(logs.path_join("reglages.cfg")), "autres fichiers jamais touchés")
	assert_eq(DirAccess.get_files_at(logs).size(), 33, "30 journaux récents + 13 jours + en cours + autre")
	assert_true(int(ProjectSettings.get_setting("debug/file_logging/max_log_files")) >= 500,
		"Godot garde assez de journaux (%s) : c'est la date qui décide" % str(ProjectSettings.get_setting("debug/file_logging/max_log_files")))


func test_total_size_bounded() -> void:
	var now := CrashLog.now_local()
	var big := "x".repeat(1000)
	var files := []
	for h in [5, 4, 3, 2, 1]:
		files.append(_old_log(h / 24.0, big, now))
	_write(logs.path_join("godot.log"), big)
	# 6000 octets pour 2500 permis : les plus anciens partent jusqu'à passer dessous.
	var removed := CrashLog.prune(logs, CrashLog.LOG_DAYS, 2500, now, PackedStringArray(["godot.log"]))
	assert_eq(Array(removed).size(), 4, "4 plus anciens supprimés (%s)" % str(removed))
	assert_true(FileAccess.file_exists(files[4]), "le plus récent gardé")
	assert_false(FileAccess.file_exists(files[0]), "le plus ancien supprimé")
	assert_true(FileAccess.file_exists(logs.path_join("godot.log")), "journal en cours gardé")
	assert_eq(CrashLog.LOG_MAX_BYTES, 200 * 1024 * 1024, "limite du joueur : 200 Mo")


func test_crash_reports_kept_30_days() -> void:
	var crashes := root.path_join(CrashLog.CRASH_DIR)
	DirAccess.make_dir_recursive_absolute(crashes)
	var now := CrashLog.now_local()
	var d29 := crashes.path_join("plantage_%s.txt" % CrashLog.stamp(now - 29 * 86400.0))
	var d31 := crashes.path_join("plantage_%s.txt" % CrashLog.stamp(now - 31 * 86400.0))
	var d31l := crashes.path_join("plantage_%s.log" % CrashLog.stamp(now - 31 * 86400.0))
	for p in [d29, d31, d31l]:
		_write(p, "rapport")
	CrashLog.begin_session(root, logs.path_join("godot.log"), {"version": "test"})
	CrashLog.end_session(root)
	assert_true(FileAccess.file_exists(d29), "rapport de 29 jours gardé")
	assert_false(FileAccess.file_exists(d31) or FileAccess.file_exists(d31l), "rapport de 31 jours supprimé (résumé et journal)")


# ------------------------------------------------------------------ plantages

func test_crash_detected_and_reported() -> void:
	var cur := logs.path_join("godot.log")
	var first := CrashLog.begin_session(root, cur, {"programme": "Test", "version": "9.9.1", "ecran": "démarrage"})
	assert_true(first.is_empty(), "premier lancement : aucun plantage")
	assert_true(FileAccess.file_exists(CrashLog.marker_path(root)), "marqueur « session en cours » posé")
	CrashLog.update_marker(root, "ecran", "MapEditor")
	CrashLog.update_marker(root, "contexte", "aperçu 3D ouvert")
	var id := _marker_id()
	assert_true(id != "", "marqueur : identifiant de session")
	# Plantage (violation d'accès : aucun message) ; au lancement suivant,
	# Godot a renommé le journal de la session plantée et en ouvre un neuf.
	var lines := PackedStringArray(["Godot Engine v4.7.2", CrashLog.SESSION_LINE + id + " (version 9.9.1)"])
	for i in 100:
		lines.append("ligne %d" % i)
	lines.append("[Apercu3D] calcul lancé : 2 pièces")
	var crashed := _old_log(0.001, "\n".join(lines))
	_old_log(0.002, "autre session sans rapport")
	_write(cur, "nouvelle session")
	var reports := CrashLog.begin_session(root, cur, {"programme": "Test", "version": "9.9.2", "ecran": "démarrage"})
	assert_eq(reports.size(), 1, "plantage détecté : un rapport")
	if reports.size() != 1:
		return
	var txt := FileAccess.get_file_as_string(reports[0])
	assert_true(reports[0].begins_with(root.path_join(CrashLog.CRASH_DIR)), "rapport dans crashes/ (%s)" % reports[0])
	for s in ["9.9.1", "MapEditor", "aperçu 3D ouvert", "[Apercu3D] calcul lancé : 2 pièces", "ligne 99"]:
		assert_true(txt.contains(s), "rapport : %s" % s)
	assert_false(txt.contains("ligne 10\n"), "rapport : seulement les dernières lignes")
	var copy := reports[0].get_basename() + ".log"
	assert_true(FileAccess.file_exists(copy), "journal de la session plantée copié")
	assert_eq(FileAccess.get_file_as_string(copy), FileAccess.get_file_as_string(crashed), "copie du bon journal (celui de la session)")
	assert_true(_marker_id() != id and _marker_id() != "", "nouveau marqueur pour la nouvelle session")
	CrashLog.end_session(root)


func test_normal_exit_leaves_nothing() -> void:
	var cur := logs.path_join("godot.log")
	CrashLog.begin_session(root, cur, {"version": "1"})
	CrashLog.end_session(root)
	assert_false(FileAccess.file_exists(CrashLog.marker_path(root)), "fermeture normale : marqueur retiré")
	var reports := CrashLog.begin_session(root, cur, {"version": "1"})
	assert_true(reports.is_empty(), "fermeture normale : aucun rapport au lancement suivant")
	assert_false(DirAccess.dir_exists_absolute(root.path_join(CrashLog.CRASH_DIR)) and not DirAccess.get_files_at(root.path_join(CrashLog.CRASH_DIR)).is_empty(),
		"dossier des rapports vide")
	CrashLog.end_session(root)


func test_crash_without_log_still_reported() -> void:
	var cur := logs.path_join("godot.log")
	CrashLog.begin_session(root, cur, {"version": "2", "ecran": "Game"})
	var reports := CrashLog.begin_session(root, cur, {"version": "2"})
	assert_eq(reports.size(), 1, "plantage détecté même sans journal")
	if reports.size() == 1:
		var txt := FileAccess.get_file_as_string(reports[0])
		assert_true(txt.contains("introuvable") and txt.contains("Game"), "rapport : journal introuvable, dernier écran")
	CrashLog.end_session(root)


func test_notice_is_bilingual() -> void:
	@warning_ignore("static_called_on_instance")
	var s := CrashGuard.notice_text("C:/x/crashes/plantage.txt")
	assert_true(s.contains("C:\\x\\crashes\\plantage.txt"), "message : chemin du rapport (à la Windows)")
	var l0 := String(Settings.language)
	Settings.language = "en"
	@warning_ignore("static_called_on_instance")
	var en := CrashGuard.notice_text("r")
	Settings.language = "fr"
	@warning_ignore("static_called_on_instance")
	var fr := CrashGuard.notice_text("r")
	Settings.language = l0
	assert_true(en.contains("report") and fr.contains("rapport"), "message en anglais et en français")


# ------------------------------------------------------------------ données du joueur

func test_tests_never_write_player_data() -> void:
	var player := OS.get_user_data_dir()
	assert_false(CrashLog.player_session(), "binaire de l'éditeur : pas une session de joueur")
	assert_false(CrashGuard.active, "marqueur de plantage inactif dans les tests")
	assert_false(FileAccess.file_exists(CrashLog.marker_path(player)), "aucun marqueur de ce test dans les données du joueur")
	assert_false(CrashLog.log_path().begins_with(player), "journal par défaut des tests hors du dossier du joueur (%s)" % CrashLog.log_path())
	assert_true(CrashLog.log_path().contains("/tests/_out/logs/"), "journal par défaut des tests : tests/_out/logs")


func test_log_settings_of_both_projects() -> void:
	for p in ["res://project.godot", "res://launcher/project.godot"]:
		var c := ConfigFile.new()
		assert_eq(c.load(p), OK, "%s lisible" % p)
		assert_true(bool(c.get_value("application", "run/flush_stdout_on_print", false)), "%s : journal vidé à chaque ligne (exe exporté)" % p)
		assert_true(bool(c.get_value("debug", "file_logging/enable_file_logging", false)), "%s : journal toujours écrit" % p)
		assert_eq(String(c.get_value("debug", "file_logging/log_path", "")), "user://logs/godot.log", "%s : journal du joueur dans user://logs" % p)
		assert_true(String(c.get_value("debug", "file_logging/log_path.editor", "")).begins_with("res://tests/_out/logs/"),
			"%s : binaire de l'éditeur (tests) hors du dossier du joueur" % p)
		assert_true(int(c.get_value("debug", "file_logging/max_log_files", 0)) >= 500, "%s : assez de journaux gardés" % p)
	assert_eq(FileAccess.get_file_as_string("res://launcher/scripts/crash_log.gd"), FileAccess.get_file_as_string("res://scripts/game/crash_log.gd"),
		"launcher/scripts/crash_log.gd : copie identique de scripts/game/crash_log.gd")


## Chaque lancement de Godot des outils écrit son journal à part (--log-file) :
## jamais dans le dossier du joueur, même quand le réglage change.
func test_tools_pass_log_file() -> void:
	var checked := 0
	for f in DirAccess.get_files_at("res://tools"):
		if not f.ends_with(".sh"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string("res://tools/" + f).split("\n"):
			var s := line.strip_edges()
			if s.begins_with("#") or s.begins_with("GODOT="):
				continue
			if s.contains("\"$GODOT\"") or s.contains("${GODOT:-godot}"):
				n += 1
				checked += 1
				assert_true(s.contains("--log-file"), "tools/%s ligne %d : --log-file (%s)" % [f, n, s.left(80)])
	assert_true(checked >= 15, "lancements de Godot vérifiés (%d)" % checked)
