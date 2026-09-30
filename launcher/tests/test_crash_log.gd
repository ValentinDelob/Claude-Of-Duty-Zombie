extends RefCounted
## Journaux et rapports de plantage du lanceur (scripts/crash_log.gd), appelés
## par test_launcher.gd (seul point d'entrée) : tout se passe dans un dossier
## temporaire de tests/_out, supprimé à la fin ; jamais dans le dossier du
## joueur (user://). Conservation par jours (14 jours de journaux, 30 jours de
## rapports), taille bornée, marqueur « session en cours » posé, mis à jour et
## retiré, session plantée détectée au lancement suivant (rapport avec son
## journal), rapports jamais écrasés.

const CrashLog := preload("res://scripts/crash_log.gd")
## Un dossier par processus : deux exécutions simultanées (check en parallèle
## d'un essai à la main) ne se marchent pas dessus.
var TMP := "res://tests/_out/launcher_crash_test_%d" % OS.get_process_id()

## Numéro de processus qui ne tourne pas (session précédente arrêtée).
const DEAD_PID := 999999937

var t   # test_launcher.gd (check)
var root := ""
var logs := ""


func run(tester) -> void:
	t = tester
	root = ProjectSettings.globalize_path(TMP)
	logs = root.path_join("logs")
	_reset()
	_player_data()
	_reset()
	_stamps()
	_reset()
	_prune_by_days()
	_reset()
	_prune_by_size()
	_reset()
	_markers()
	_reset()
	_stale_markers()
	_reset()
	_crash_detected()
	_reset()
	_crash_without_log()
	_reset()
	_reports_never_overwritten()
	_reset()
	_find_log()
	_reset()
	_crash_reports_kept_30_days()
	_rm(root)
	t.check(not DirAccess.dir_exists_absolute(root), "crash_log : dossier temporaire supprimé")


func _reset() -> void:
	_rm(root)
	DirAccess.make_dir_recursive_absolute(logs)


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


func _json(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## Journal sauvegardé par Godot il y a `days` jours (nom horodaté).
func _old_log(days: float, text := "x", now := -1.0) -> String:
	var tm := (now if now >= 0.0 else CrashLog.now_local()) - days * 86400.0
	var p := logs.path_join("godot%s.log" % CrashLog.stamp(tm))
	_write(p, text)
	return p


# ------------------------------------------------------------------ données du joueur

func _player_data() -> void:
	var player := OS.get_user_data_dir()
	t.check(not CrashLog.player_session(), "crash_log : binaire de l'éditeur, pas une session de joueur (main.gd n'écrit aucun marqueur)")
	t.check(not CrashLog.log_path().begins_with(player) and CrashLog.log_path().contains("/tests/_out/logs/"),
		"crash_log : journal des tests dans tests/_out/logs, hors du dossier du joueur (%s)" % CrashLog.log_path())
	t.check(not root.begins_with(player), "crash_log : dossier de test hors du dossier du joueur")
	t.check(CrashLog.LOG_DAYS >= 14 and CrashLog.CRASH_DAYS >= 30, "crash_log : journaux gardés %d jours, rapports %d jours" % [CrashLog.LOG_DAYS, CrashLog.CRASH_DAYS])
	t.check(int(ProjectSettings.get_setting("debug/file_logging/max_log_files")) >= 500,
		"crash_log : Godot garde assez de journaux (%s), c'est la date qui décide" % str(ProjectSettings.get_setting("debug/file_logging/max_log_files")))
	var game := FileAccess.get_file_as_string("res://../scripts/game/crash_log.gd")
	if game != "":
		t.check(game == FileAccess.get_file_as_string("res://scripts/crash_log.gd"), "crash_log : copie identique à celle du jeu")


# ------------------------------------------------------------------ horodatage

func _stamps() -> void:
	var now := CrashLog.now_local()
	var s := CrashLog.stamp(now)
	t.check(RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}T\\d{2}\\.\\d{2}\\.\\d{2}$").search(s) != null, "crash_log : horodatage sans « : » (%s)" % s)
	t.check(CrashLog.stamp(0.0) == "1970-01-01T00.00.00", "crash_log : horodatage d'une date donnée")
	t.check(absf(CrashLog.file_time("x/godot%s.log" % s) - floorf(now)) < 1.0, "crash_log : date lue dans le nom d'un journal")
	t.check(CrashLog.file_time("plantage_2026-09-30T14.55.00_2.txt") == float(Time.get_unix_time_from_datetime_string("2026-09-30T14:55:00")),
		"crash_log : date lue dans le nom d'un rapport")
	var plain := logs.path_join("sans_date.log")
	_write(plain, "x")
	t.check(absf(CrashLog.file_time(plain) - now) < 600.0, "crash_log : sans date dans le nom, date de modification (heure locale)")
	t.check(CrashLog._size(plain) == 1 and CrashLog._size(logs.path_join("absent.log")) == 0, "crash_log : taille d'un fichier (0 si absent)")


# ------------------------------------------------------------------ conservation

func _prune_by_days() -> void:
	var now := CrashLog.now_local()
	var d13 := _old_log(13.0, "x", now)
	var d15 := _old_log(15.0, "x", now)
	var d40 := _old_log(40.0, "x", now)
	var old_txt := logs.path_join("note_%s.txt" % CrashLog.stamp(now - 20 * 86400.0))
	var old_cfg := logs.path_join("reglages_%s.cfg" % CrashLog.stamp(now - 60 * 86400.0))
	var old_kept := logs.path_join("godot%s.log" % CrashLog.stamp(now - 90 * 86400.0))
	for p in [old_txt, old_cfg, old_kept]:
		_write(p, "x")
	_write(logs.path_join("godot.log"), "en cours")
	for i in 20:
		_old_log(i * 0.1, "x", now)   # beaucoup de lancements récents : tous gardés
	var removed := CrashLog.prune(logs, CrashLog.LOG_DAYS, CrashLog.LOG_MAX_BYTES, now, PackedStringArray(["godot.log", old_kept.get_file()]))
	t.check(removed.size() == 3, "prune : seuls les journaux de plus de 14 jours supprimés %s" % [removed])
	t.check(FileAccess.file_exists(d13), "prune : journal de 13 jours gardé")
	t.check(not FileAccess.file_exists(d15) and not FileAccess.file_exists(d40) and not FileAccess.file_exists(old_txt), "prune : journaux de 15, 20 (.txt) et 40 jours supprimés")
	t.check(FileAccess.file_exists(old_cfg), "prune : autres extensions jamais touchées")
	t.check(FileAccess.file_exists(old_kept) and FileAccess.file_exists(logs.path_join("godot.log")), "prune : fichiers protégés (journal en cours) jamais supprimés")
	t.check(DirAccess.get_files_at(logs).size() == 24, "prune : 20 journaux récents + 13 jours + protégés + autre (%d)" % DirAccess.get_files_at(logs).size())
	t.check(CrashLog.prune(root.path_join("absent"), 1, 1).is_empty(), "prune : dossier absent, rien à faire")
	# Sans date imposée : maintenant.
	t.check(CrashLog.prune(logs, CrashLog.LOG_DAYS, CrashLog.LOG_MAX_BYTES, -1.0, PackedStringArray(["godot.log", old_kept.get_file()])).is_empty(), "prune : second passage, rien de plus supprimé")


func _prune_by_size() -> void:
	var now := CrashLog.now_local()
	var big := "x".repeat(1000)
	var files := []
	for h in [5, 4, 3, 2, 1]:
		files.append(_old_log(h / 24.0, big, now))
	_write(logs.path_join("godot.log"), big)
	# 6000 octets pour 2500 permis : les plus anciens partent jusqu'à passer dessous.
	var removed := CrashLog.prune(logs, CrashLog.LOG_DAYS, 2500, now, PackedStringArray(["godot.log"]))
	t.check(removed.size() == 4, "prune : taille bornée, 4 plus anciens supprimés %s" % [removed])
	t.check(FileAccess.file_exists(files[4]) and not FileAccess.file_exists(files[0]), "prune : le plus récent gardé, le plus ancien supprimé")
	t.check(FileAccess.file_exists(logs.path_join("godot.log")), "prune : journal en cours gardé même au-delà de la limite")


# ------------------------------------------------------------------ marqueur

func _markers() -> void:
	t.check(CrashLog.marker_path(root, 123) == root.path_join("session_en_cours_123.json"), "marqueur : nom d'après le processus")
	t.check(CrashLog.marker_path(root) == CrashLog.marker_path(root, OS.get_process_id()), "marqueur : processus courant par défaut")
	CrashLog.update_marker(root, "ecran", "Versions")
	t.check(not FileAccess.file_exists(CrashLog.marker_path(root)), "marqueur : mise à jour sans session, aucun fichier créé")
	var cur := logs.path_join("godot.log")
	var first := CrashLog.begin_session(root, cur, {"programme": "Lanceur", "version": "4", "ecran": "démarrage"})
	t.check(first.is_empty(), "session : premier lancement, aucun plantage")
	var m := _json(CrashLog.marker_path(root))
	t.check(String(m.get("id", "")).begins_with(str(OS.get_process_id()) + "-") and m.get("version") == "4" and m.get("programme") == "Lanceur"
		and m.get("journal") == cur and String(m.get("debut", "")) != "", "session : marqueur posé (id, version, début, journal) %s" % [m])
	CrashLog.update_marker(root, "ecran", "Versions")
	CrashLog.update_marker(root, "contexte", "téléchargement v0.1.5")
	var m2 := _json(CrashLog.marker_path(root))
	t.check(m2.get("ecran") == "Versions" and m2.get("contexte") == "téléchargement v0.1.5" and m2.has("maj") and m2.get("id") == m.get("id"),
		"session : écran et contexte notés dans le marqueur")
	CrashLog.end_session(root)
	t.check(not FileAccess.file_exists(CrashLog.marker_path(root)), "session : fermeture normale, marqueur retiré")
	CrashLog.end_session(root)
	t.check(CrashLog.begin_session(root, cur, {"version": "4"}).is_empty(), "session : après une fermeture normale, aucun rapport")
	t.check(not DirAccess.dir_exists_absolute(root.path_join(CrashLog.CRASH_DIR)) or DirAccess.get_files_at(root.path_join(CrashLog.CRASH_DIR)).is_empty(),
		"session : dossier des rapports vide")
	CrashLog.end_session(root)
	t.check(CrashLog._read_json(root.path_join("absent.json")).is_empty(), "marqueur : fichier absent lu comme vide")
	_write(root.path_join("liste.json"), "[1, 2]")
	t.check(CrashLog._read_json(root.path_join("liste.json")).is_empty(), "marqueur : contenu qui n'est pas un objet lu comme vide")


func _stale_markers() -> void:
	t.check(CrashLog.stale_markers(root.path_join("absent")).is_empty(), "marqueurs restés : dossier absent")
	CrashLog._write_json(CrashLog.marker_path(root, DEAD_PID), {"id": "%d-1" % DEAD_PID})
	_write(root.path_join(CrashLog.MARKER_PREFIX + "abc.json"), "[]")
	_write(root.path_join(CrashLog.MARKER_PREFIX + "7.txt"), "{}")
	_write(root.path_join("autre_%d.json" % DEAD_PID), "{}")
	var st := CrashLog.stale_markers(root)
	var names := st.map(func(e): return String(e[0]).get_file())
	names.sort()
	t.check(names == [CrashLog.MARKER_PREFIX + "%d.json" % DEAD_PID, CrashLog.MARKER_PREFIX + "abc.json"],
		"marqueurs restés : processus arrêté ou numéro illisible, autres fichiers ignorés %s" % [names])
	var dead := st.filter(func(e): return String(e[0]).get_file() == CrashLog.MARKER_PREFIX + "%d.json" % DEAD_PID)
	t.check(dead.size() == 1 and dead[0][1].get("id") == "%d-1" % DEAD_PID, "marqueurs restés : contenu lu")


# ------------------------------------------------------------------ plantages

func _crash_detected() -> void:
	var cur := logs.path_join("godot.log")
	var id := "%d-0badf00d" % DEAD_PID
	# Session précédente plantée (violation d'accès : aucun message) : son
	# marqueur est resté ; Godot a renommé son journal au lancement suivant.
	CrashLog._write_json(CrashLog.marker_path(root, DEAD_PID), {"id": id, "programme": "Lanceur", "version": "3",
		"debut": "2026-09-30T10:00:00", "maj": "2026-09-30T10:05:00", "ecran": "Versions", "contexte": "téléchargement v0.1.4", "journal": "ancien"})
	var lines := PackedStringArray(["Godot Engine v4.7.2", CrashLog.SESSION_LINE + id + " (version 3)"])
	for i in 100:
		lines.append("ligne %d" % i)
	lines.append("[Lanceur] téléchargement de v0.1.4")
	var crashed := _old_log(0.001, "\n".join(lines))
	_old_log(0.002, CrashLog.SESSION_LINE + "autre-session")
	_write(cur, "nouvelle session")
	var reports := CrashLog.begin_session(root, cur, {"programme": "Lanceur", "version": "4"})
	t.check(reports.size() == 1, "plantage : session précédente détectée au lancement suivant (%d rapport)" % reports.size())
	if reports.size() != 1:
		CrashLog.end_session(root)
		return
	t.check(reports[0].begins_with(root.path_join(CrashLog.CRASH_DIR) + "/plantage_") and reports[0].ends_with(".txt"), "plantage : rapport dans crashes/ (%s)" % reports[0])
	var txt := FileAccess.get_file_as_string(reports[0])
	var missing := ["Lanceur", "Version : 3", "Versions", "téléchargement v0.1.4", "2026-09-30T10:05:00", "[Lanceur] téléchargement de v0.1.4", "ligne 99",
		"Crash report", "Rapport de plantage"].filter(func(s): return not txt.contains(s))
	t.check(missing.is_empty(), "plantage : rapport complet, en français et en anglais (manque %s)" % [missing])
	t.check(not txt.contains("ligne 10\n"), "plantage : seulement les %d dernières lignes du journal" % CrashLog.TAIL_LINES)
	var copy := reports[0].get_basename() + ".log"
	t.check(FileAccess.file_exists(copy) and FileAccess.get_file_as_string(copy) == FileAccess.get_file_as_string(crashed),
		"plantage : journal de la session plantée copié (le bon)")
	t.check(FileAccess.file_exists(crashed), "plantage : journal d'origine gardé")
	t.check(not FileAccess.file_exists(CrashLog.marker_path(root, DEAD_PID)), "plantage : ancien marqueur retiré (un seul rapport)")
	t.check(String(_json(CrashLog.marker_path(root)).get("id", "")) not in ["", id], "plantage : nouveau marqueur pour la nouvelle session")
	t.check(CrashLog.begin_session(root, cur, {"version": "4"}).size() == 1, "plantage : lancement suivant sans fermeture, nouveau rapport")
	t.check(DirAccess.get_files_at(root.path_join(CrashLog.CRASH_DIR)).size() >= 3, "plantage : rapports précédents gardés")
	CrashLog.end_session(root)


func _crash_without_log() -> void:
	var cur := logs.path_join("godot.log")
	CrashLog._write_json(CrashLog.marker_path(root, DEAD_PID), {"id": "%d-1" % DEAD_PID, "version": "2", "ecran": "Notes", "journal": "C:/x/godot.log"})
	var reports := CrashLog.begin_session(root, cur, {"version": "2"})
	t.check(reports.size() == 1, "plantage sans journal : quand même un rapport")
	if reports.size() == 1:
		var txt := FileAccess.get_file_as_string(reports[0])
		t.check(txt.contains("introuvable") and txt.contains("C:/x/godot.log") and txt.contains("Notes"), "plantage sans journal : journal introuvable, dernier écran")
		t.check(not FileAccess.file_exists(reports[0].get_basename() + ".log"), "plantage sans journal : aucune copie")
	CrashLog.end_session(root)
	# Marqueur abîmé (pas un objet) : rapport avec des « ? ». (Pas de JSON invalide :
	# JSON.parse_string écrit « ERROR: » dans le journal, refusé par tools/check.sh.)
	_write(CrashLog.marker_path(root, DEAD_PID), "[\"abîmé\"]")
	var r2 := CrashLog.begin_session(root, cur, {"version": "2"})
	t.check(r2.size() == 1 and FileAccess.get_file_as_string(r2[0]).contains("Version : ?"), "plantage, marqueur illisible : rapport quand même")
	CrashLog.end_session(root)


func _reports_never_overwritten() -> void:
	var cur := logs.path_join("godot.log")
	var paths := {}
	for i in 3:
		var p := CrashLog.write_report(root, {"id": "", "version": str(i)}, cur)
		paths[p] = true
		t.check(FileAccess.get_file_as_string(p).contains("Version : %d" % i), "rapport %d écrit" % i)
	t.check(paths.size() == 3, "rapports du même instant : noms différents, aucun écrasé %s" % [paths.keys().map(func(p): return String(p).get_file())])


func _find_log() -> void:
	var cur := logs.path_join("godot.log")
	var a := _old_log(0.01, "début\n" + CrashLog.SESSION_LINE + "s1 (version 1)\nfin")
	var b := _old_log(0.02, CrashLog.SESSION_LINE + "s1 (version 1)")
	_old_log(0.03, CrashLog.SESSION_LINE + "s2 (version 1)")
	_write(cur, CrashLog.SESSION_LINE + "s3 (version 1)")
	t.check(CrashLog.find_log(logs, "s1", cur) == a and b != a, "journal de session : le plus récent qui la contient")
	t.check(CrashLog.find_log(logs, "s2", cur).get_file().begins_with("godot2"), "journal de session : autre session")
	t.check(CrashLog.find_log(logs, "s3", cur) == "", "journal de session : journal en cours exclu")
	t.check(CrashLog.find_log(logs, "", cur) == "" and CrashLog.find_log(logs, "s9", cur) == "", "journal de session : identifiant vide ou inconnu")
	t.check(CrashLog.find_log(root.path_join("absent"), "s1") == "", "journal de session : dossier absent")


func _crash_reports_kept_30_days() -> void:
	var crashes := root.path_join(CrashLog.CRASH_DIR)
	DirAccess.make_dir_recursive_absolute(crashes)
	var now := CrashLog.now_local()
	var d29 := crashes.path_join("plantage_%s.txt" % CrashLog.stamp(now - 29 * 86400.0))
	var d31 := crashes.path_join("plantage_%s.txt" % CrashLog.stamp(now - 31 * 86400.0))
	var d31l := crashes.path_join("plantage_%s.log" % CrashLog.stamp(now - 31 * 86400.0))
	for p in [d29, d31, d31l]:
		_write(p, "rapport")
	var l13 := _old_log(13.0)
	var l15 := _old_log(15.0)
	CrashLog.begin_session(root, logs.path_join("godot.log"), {"version": "test"})
	CrashLog.end_session(root)
	t.check(FileAccess.file_exists(d29) and not FileAccess.file_exists(d31) and not FileAccess.file_exists(d31l),
		"démarrage : rapports de 29 jours gardés, de 31 jours supprimés")
	t.check(FileAccess.file_exists(l13) and not FileAccess.file_exists(l15), "démarrage : journaux de 13 jours gardés, de 15 jours supprimés")
