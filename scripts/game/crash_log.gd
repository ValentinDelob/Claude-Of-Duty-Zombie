class_name CrashLog
extends RefCounted
## Journaux gardés et trace des plantages, pour le jeu ET le lanceur (copie
## identique dans launcher/scripts/crash_log.gd, vérifiée par
## tests/test_crash_log.gd ; docs/ARCHITECTURE.md « Journaux et plantages »).
##
## - Journal Godot (user://logs/godot.log, un fichier par lancement, vidé à
##   chaque ligne : application/run/flush_stdout_on_print) : gardé au moins
##   LOG_DAYS jours, total borné à LOG_MAX_BYTES (prune au démarrage).
## - Marqueur « session en cours » (session_en_cours_<pid>.json dans le dossier
##   des données) posé au démarrage, retiré à la fermeture normale. Encore là
##   au démarrage suivant (et son processus arrêté) : la session a planté, même
##   sans aucun message (violation d'accès) -> rapport dans crashes/ (journal
##   copié + résumé), gardé CRASH_DAYS jours.
## - Seulement pour le joueur (exe exporté) : jamais dans les tests ni les
##   agents (binaire de l'éditeur), qui ne touchent pas aux données du joueur.
## Aucun autoload, aucun texte traduit : fonctions pures sur des dossiers
## donnés (testables sur un dossier temporaire).

const LOG_DAYS := 14
const LOG_MAX_BYTES := 200 * 1024 * 1024
const CRASH_DIR := "crashes"
const CRASH_DAYS := 30
const CRASH_MAX_BYTES := 50 * 1024 * 1024
const MARKER_PREFIX := "session_en_cours_"
## Ligne écrite dans le journal au début de chaque session : retrouve le
## journal d'une session plantée (Godot renomme l'ancien au lancement suivant).
const SESSION_LINE := "[Session] début "
const TAIL_LINES := 60
## Extensions nettoyées (rien d'autre n'est jamais supprimé).
const PRUNED := ["log", "txt"]


## Session d'un joueur ? Exe exporté seulement : le binaire de l'éditeur
## (tests, agents, scénarios) n'écrit jamais dans les données du joueur.
static func player_session() -> bool:
	return OS.has_feature("template")


## Journal Godot par défaut de ce processus (chemin absolu) : user://logs
## dans l'exe exporté ; tests/_out/logs pour le binaire de l'éditeur
## (réglage debug/file_logging/log_path.editor). --log-file, que Godot retire
## des arguments visibles, le remplace sans que le jeu le sache.
static func log_path() -> String:
	var p := String(ProjectSettings.get_setting_with_override("debug/file_logging/log_path"))
	if p.is_relative_path():
		p = "res://" + p
	return ProjectSettings.globalize_path(p)


## Heure locale, en secondes (même repère que les noms de fichiers).
static func now_local() -> float:
	return float(Time.get_unix_time_from_datetime_string(Time.get_datetime_string_from_system()))


## Horodatage pour un nom de fichier (comme les journaux de Godot) :
## 2026-09-30T14.55.00.
static func stamp(unix_local := -1.0) -> String:
	var t := unix_local if unix_local >= 0.0 else now_local()
	return Time.get_datetime_string_from_unix_time(int(t)).replace(":", ".")


## Date d'un fichier : horodatage de son nom (godot2026-09-30T14.55.00.log,
## plantage_2026-09-30T14.55.00.txt), sinon date de modification (heure locale).
static func file_time(path: String) -> float:
	var re := RegEx.create_from_string("(\\d{4}-\\d{2}-\\d{2})T(\\d{2})[.:](\\d{2})[.:](\\d{2})")
	var m := re.search(path.get_file())
	if m != null:
		return float(Time.get_unix_time_from_datetime_string("%sT%s:%s:%s" % [m.get_string(1), m.get_string(2), m.get_string(3), m.get_string(4)]))
	var bias := float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0
	return float(FileAccess.get_modified_time(path)) + bias


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


## Nettoie `dir` (fichiers .log et .txt seulement) : supprime ceux de plus de
## `days` jours, puis les plus anciens tant que le total dépasse `max_bytes`.
## `keep` : noms jamais supprimés (journal en cours). Renvoie les supprimés.
static func prune(dir: String, days: float, max_bytes: int, now := -1.0, keep: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var removed := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return removed
	if now < 0.0:
		now = now_local()
	var files := []   # [date, nom, taille]
	var total := 0
	for f in DirAccess.get_files_at(dir):
		if not f.get_extension().to_lower() in PRUNED:
			continue
		var p := dir.path_join(f)
		var sz := _size(p)
		files.append([file_time(p), f, sz])
		total += sz
	files.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for e in files:
		if keep.has(String(e[1])):
			continue
		if now - float(e[0]) > days * 86400.0 or total > max_bytes:
			if DirAccess.remove_absolute(dir.path_join(String(e[1]))) == OK:
				total -= int(e[2])
				removed.append(String(e[1]))
	return removed


# ------------------------------------------------------------------ marqueur de session

static func marker_path(root: String, pid := -1) -> String:
	return root.path_join("%s%d.json" % [MARKER_PREFIX, pid if pid >= 0 else OS.get_process_id()])


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func _write_json(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "\t"))
		f.close()


## Marqueurs laissés par des sessions arrêtées sans fermeture normale (leur
## processus ne tourne plus : un second jeu ouvert en même temps n'est pas un
## plantage). [[chemin, contenu]]
static func stale_markers(root: String) -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(root):
		return out
	for f in DirAccess.get_files_at(root):
		if not (f.begins_with(MARKER_PREFIX) and f.ends_with(".json")):
			continue
		var pid := f.trim_prefix(MARKER_PREFIX).trim_suffix(".json").to_int()
		if pid != OS.get_process_id() and pid > 0 and OS.is_process_running(pid):
			continue
		out.append([root.path_join(f), _read_json(root.path_join(f))])
	return out


## Début d'une session : rapport pour chaque session précédente plantée
## (marqueur resté), nettoyage des journaux et des rapports, nouveau marqueur
## (`info` : version, écran...), puis la ligne de session dans le journal.
## Renvoie les rapports créés (chemins absolus).
static func begin_session(root: String, log_file: String, info: Dictionary) -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(root)
	var reports := PackedStringArray()
	for e in stale_markers(root):
		reports.append(write_report(root, e[1], log_file))
		DirAccess.remove_absolute(String(e[0]))
	prune(log_file.get_base_dir(), LOG_DAYS, LOG_MAX_BYTES, -1.0, PackedStringArray([log_file.get_file()]))
	prune(root.path_join(CRASH_DIR), CRASH_DAYS, CRASH_MAX_BYTES)
	var m := info.duplicate()
	m["id"] = "%d-%08x" % [OS.get_process_id(), randi()]
	m["debut"] = Time.get_datetime_string_from_system()
	m["journal"] = log_file
	_write_json(marker_path(root), m)
	print("%s%s (version %s, journal %s)" % [SESSION_LINE, m.id, str(m.get("version", "?")), log_file])
	return reports


## Note l'écran (ou le contexte) courant dans le marqueur : il figurera dans le
## rapport si la session plante.
static func update_marker(root: String, key: String, value: String) -> void:
	var p := marker_path(root)
	var m := _read_json(p)
	if m.is_empty():
		return
	m[key] = value
	m["maj"] = Time.get_datetime_string_from_system()
	_write_json(p, m)


## Fermeture normale : marqueur retiré (aucun rapport au prochain démarrage).
static func end_session(root: String) -> void:
	var p := marker_path(root)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


# ------------------------------------------------------------------ rapport

## Journal de la session `id` : le plus récent des journaux du dossier (hors
## journal en cours) qui contient sa ligne de session ("" : introuvable).
static func find_log(dir: String, id: String, current := "") -> String:
	if id == "" or not DirAccess.dir_exists_absolute(dir):
		return ""
	var files := []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() == "log" and f != current.get_file():
			files.append([file_time(dir.path_join(f)), f])
	files.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for e in files.slice(0, 30):
		var p := dir.path_join(String(e[1]))
		var fa := FileAccess.open(p, FileAccess.READ)
		if fa != null and fa.get_buffer(mini(fa.get_length(), 65536)).get_string_from_utf8().contains(SESSION_LINE + id):
			return p
	return ""


## Rapport d'une session plantée (marqueur `m`) : son journal copié dans
## crashes/ et un résumé (version, heures, dernier écran, dernières lignes).
## Renvoie le chemin du résumé.
static func write_report(root: String, m: Dictionary, current_log: String) -> String:
	var dir := root.path_join(CRASH_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var base := "plantage_" + stamp()
	var n := 1
	while FileAccess.file_exists(dir.path_join(base + ".txt")):
		n += 1
		base = "plantage_%s_%d" % [stamp(), n]
	var src := find_log(current_log.get_base_dir(), String(m.get("id", "")), current_log)
	var tail := PackedStringArray()
	var copied := ""
	if src != "":
		copied = base + ".log"
		DirAccess.copy_absolute(src, dir.path_join(copied))
		var lines := FileAccess.get_file_as_string(src).split("\n")
		tail = lines.slice(maxi(0, lines.size() - TAIL_LINES))
	var txt := PackedStringArray([
		"Rapport de plantage / Crash report",
		"La session précédente ne s'est pas fermée normalement (plantage, fermeture forcée ou coupure).",
		"The previous session did not close normally (crash, forced close or power loss).",
		"",
		"Programme / Program : %s" % str(m.get("programme", "?")),
		"Version : %s" % str(m.get("version", "?")),
		"Début de la session / Session start : %s" % str(m.get("debut", "?")),
		"Dernière mise à jour / Last update : %s" % str(m.get("maj", m.get("debut", "?"))),
		"Détecté au lancement suivant / Detected at next start : %s" % Time.get_datetime_string_from_system(),
		"Dernier écran / Last screen : %s" % str(m.get("ecran", "?")),
		"Dernier contexte / Last context : %s" % str(m.get("contexte", "-")),
		"Journal de la session / Session log : %s" % (copied if copied != "" else "introuvable / not found (%s)" % str(m.get("journal", "?"))),
		"",
		"--- Dernières lignes du journal / Last log lines ---",
	])
	txt.append_array(tail)
	var f := FileAccess.open(dir.path_join(base + ".txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(txt) + "\n")
		f.close()
	return dir.path_join(base + ".txt")
