extends RefCounted
## Versions installées et réglages du lanceur.
## Jeux : %LOCALAPPDATA%\CallOfClaudeZombie\versions\<version>\CallOfClaudeZombie.exe
## (dossier et nom de fichier de l'ancien nom du jeu, gardés pour ne pas
## retélécharger les versions déjà installées)
## (comme les versions du lanceur de Minecraft, une copie par version).
##
## Un numéro de version devient un nom de dossier : seuls les numéros sûrs
## (Releases.is_safe_tag : « v0.1.116 ») sont acceptés, jamais « .. ».

const Releases := preload("res://scripts/releases.gd")

const EXE_NAME := "CallOfClaudeZombie.exe"
const SETTINGS := "user://launcher.cfg"

## Dossier des versions (modifiable par les tests).
static var root := ""
## Fichier des réglages (modifiable par les tests : jamais celui du joueur).
static var settings_path := ""


static func settings_file() -> String:
	return settings_path if settings_path != "" else SETTINGS


static func versions_dir() -> String:
	if root != "":
		return root
	var base := OS.get_environment("LOCALAPPDATA")
	if base == "":
		return ProjectSettings.globalize_path("user://versions")
	return base.replace("\\", "/") + "/CallOfClaudeZombie/versions"


## Chemin de l'exécutable d'une version ("" si le numéro n'est pas sûr).
static func exe_path(tag: String) -> String:
	if not Releases.is_safe_tag(tag):
		return ""
	return versions_dir() + "/" + tag + "/" + EXE_NAME


static func is_installed(tag: String) -> bool:
	var p := exe_path(tag)
	return p != "" and FileAccess.file_exists(p)


## Versions présentes sur le disque (utile hors ligne).
static func installed() -> Array:
	var out: Array = []
	var dir := versions_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for d in DirAccess.get_directories_at(dir):
		if is_installed(d):
			out.append(d)
	return out


## Emplacement de téléchargement : un fichier partiel renommé à la fin,
## seulement après vérification (jamais exécuté avant).
static func part_path(tag: String) -> String:
	var p := exe_path(tag)
	return p + ".part" if p != "" else ""


static func prepare_dir(tag: String) -> void:
	if Releases.is_safe_tag(tag):
		DirAccess.make_dir_recursive_absolute(versions_dir() + "/" + tag)


## Vrai si le fichier a exactement la taille `size` (si > 0) et la somme
## SHA-256 `sha256` (si non vide, en hexadécimal).
static func verify_file(path: String, sha256: String, size := 0) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var len := f.get_length()
	f.close()
	if len == 0 or (size > 0 and len != size):
		return false
	return sha256 == "" or FileAccess.get_sha256(path).to_lower() == sha256.to_lower()


## Termine un téléchargement : le fichier partiel devient l'exécutable.
static func finish_download(tag: String) -> bool:
	var part := part_path(tag)
	if part == "" or not FileAccess.file_exists(part):
		return false
	if FileAccess.file_exists(exe_path(tag)):
		DirAccess.remove_absolute(exe_path(tag))
	return DirAccess.rename_absolute(part, exe_path(tag)) == OK


static func remove(tag: String) -> void:
	if not Releases.is_safe_tag(tag):
		return
	var dir := versions_dir() + "/" + tag
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)


static func load_settings() -> Dictionary:
	var lang := "fr" if OS.get_locale_language() == "fr" else "en"
	var out := {"language": lang, "selected": "latest", "channel": Releases.STABLE, "selected_snapshot": "latest"}
	var f := FileAccess.open(settings_file(), FileAccess.READ)
	if f == null or f.get_length() > 65536:
		return out
	var text := f.get_as_text()
	# ConfigFile décode des objets et charge des ressources (« Object(...) »,
	# « Resource(...) ») : un fichier contenant un constructeur est ignoré.
	if has_constructor(text):
		push_warning("[launcher] réglages ignorés : contenu suspect")
		return out
	var cfg := ConfigFile.new()
	if cfg.parse(text) != OK:
		return out
	var l: Variant = cfg.get_value("launcher", "language", lang)
	var s: Variant = cfg.get_value("launcher", "selected", "latest")
	out.language = l if l is String and l in ["fr", "en"] else lang
	out.selected = s if s is String and (s == "latest" or Releases.is_safe_tag(s)) else "latest"
	# Canal (stable / snapshot) et version choisie dans chaque canal : mémorisés.
	var c: Variant = cfg.get_value("launcher", "channel", Releases.STABLE)
	var ss: Variant = cfg.get_value("launcher", "selected_snapshot", "latest")
	out.channel = c if c is String and c in [Releases.STABLE, Releases.SNAPSHOT] else Releases.STABLE
	out.selected_snapshot = ss if ss is String and (ss == "latest" or Releases.is_safe_tag(ss)) else "latest"
	return out


## Vrai si le texte contient « identifiant( » hors des chaînes et des
## commentaires : les réglages du lanceur ne contiennent que du texte.
static func has_constructor(text: String) -> bool:
	var code := ""
	var in_str := false
	var escaped := false
	var comment := false
	for c in text:
		if comment:
			comment = c != "\n"
		elif in_str:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_str = false
		elif c == "\"":
			in_str = true
			code += " "
		elif c == ";" or c == "#":
			comment = true
		else:
			code += c
	return RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*\\s*\\(").search(code) != null


static func save_settings(s: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("launcher", "language", s.get("language", "fr"))
	cfg.set_value("launcher", "selected", s.get("selected", "latest"))
	cfg.set_value("launcher", "channel", s.get("channel", Releases.STABLE))
	cfg.set_value("launcher", "selected_snapshot", s.get("selected_snapshot", "latest"))
	var err := cfg.save(settings_file())
	if err != OK:
		push_warning("[Lanceur] réglages non enregistrés (%s)" % error_string(err))


# --------------------------------------------------------------------------
# Versions en paquets (docs/RELEASE.md § 3)
#   <dossier>/engines/<godot>/engine.exe   moteur, une fois par version de Godot
#   <dossier>/store/<sha256>.pck           paquets vérifiés, partagés
#   <dossier>/versions/<tag>/              copie du moteur (EXE_NAME), du core
#                                          (PACK_NAME : chargé tout seul par le
#                                          moteur, même nom) et manifest.json
# --------------------------------------------------------------------------

const PACK_NAME := "CallOfClaudeZombie.pck"
const MANIFEST_NAME := "manifest.json"


static func data_dir() -> String:
	return versions_dir().get_base_dir()


static func store_dir() -> String:
	return data_dir() + "/store"


static func engines_dir() -> String:
	return data_dir() + "/engines"


## Fichier rangé par sa somme SHA-256 ("" si la somme ou l'extension est invalide).
static func stored_path(sha: String, ext: String) -> String:
	if not Releases.is_sha256(sha) or not ext in ["pck", "exe"]:
		return ""
	return store_dir() + "/" + sha + "." + ext


## Moteur d'une version de Godot (« 4.7.2 »), "" si le numéro est suspect.
static func engine_path(godot: String) -> String:
	if RegEx.create_from_string("^[0-9]{1,2}\\.[0-9]{1,2}(\\.[0-9]{1,2})?\\z").search(godot) == null:
		return ""
	return engines_dir() + "/" + godot + "/engine.exe"


## Fichiers à télécharger pour installer la version du manifeste `m`
## (Releases.parse_manifest) : [{url, path, sha256, size}], sans ceux déjà
## présents et intacts (même somme) : une mise à jour ne télécharge que ce qui
## a changé. Toutes les langues des répliques sont prises (le jeu change de
## langue sans repasser par le lanceur).
static func missing_files(m: Dictionary) -> Array:
	var out: Array = []
	var e: Dictionary = m.get("engine", {})
	var ep := engine_path(String(e.get("godot", "")))
	if ep == "":
		return []
	if not verify_file(ep, String(e.sha256), int(e.size)):
		out.append({"url": e.url, "path": ep, "sha256": e.sha256, "size": e.size})
	for p: Dictionary in m.get("packs", []):
		var sp := stored_path(String(p.sha256), "pck")
		if sp == "":
			return []
		if not verify_file(sp, String(p.sha256), int(p.size)):
			out.append({"url": p.url, "path": sp, "sha256": p.sha256, "size": p.size})
	return out


## Installe la version `tag` à partir des fichiers déjà vérifiés (moteur et
## paquets présents : missing_files vide). Copies locales, l'exécutable en
## DERNIER : is_installed() n'est vrai que pour une installation complète.
static func install_manifest(tag: String, m: Dictionary, manifest_text: String) -> bool:
	if not Releases.is_safe_tag(tag) or not missing_files(m).is_empty():
		return false
	prepare_dir(tag)
	var dir := versions_dir() + "/" + tag
	var main_pack := ""
	for p: Dictionary in m.packs:
		if p.main:
			main_pack = stored_path(String(p.sha256), "pck")
	if main_pack == "" or DirAccess.copy_absolute(main_pack, dir + "/" + PACK_NAME) != OK:
		return false
	var f := FileAccess.open(dir + "/" + MANIFEST_NAME, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(manifest_text)
	f.close()
	var exe_part := dir + "/" + EXE_NAME + ".part"
	if DirAccess.copy_absolute(engine_path(String(m.engine.godot)), exe_part) != OK:
		return false
	if FileAccess.file_exists(exe_path(tag)):
		DirAccess.remove_absolute(exe_path(tag))
	return DirAccess.rename_absolute(exe_part, exe_path(tag)) == OK


## Arguments de lancement d'une version en paquets : les paquets autres que
## le core (répliques), montés par l'autoload Packs du jeu. [] pour une
## version à exécutable complet (ancien format) ou si rien n'est à monter.
static func launch_args(tag: String) -> PackedStringArray:
	if not Releases.is_safe_tag(tag):
		return PackedStringArray()
	var path := versions_dir() + "/" + tag + "/" + MANIFEST_NAME
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var m := Releases.parse_manifest(FileAccess.get_file_as_string(path), tag)
	var packs := PackedStringArray()
	for p: Dictionary in m.get("packs", []):
		var sp := stored_path(String(p.sha256), "pck")
		if not p.main and sp != "" and FileAccess.file_exists(sp):
			packs.append(sp)
	if packs.is_empty():
		return PackedStringArray()
	return PackedStringArray(["--", "--packs=" + ",".join(packs)])


## Supprime du stock les paquets qu'aucune version installée n'utilise plus
## (après la suppression d'une version). Moteurs gardés (peu nombreux).
static func prune_store() -> int:
	var keep := {}
	for tag: String in installed():
		var path := versions_dir() + "/" + tag + "/" + MANIFEST_NAME
		if FileAccess.file_exists(path):
			var m := Releases.parse_manifest(FileAccess.get_file_as_string(path), tag)
			for p: Dictionary in m.get("packs", []):
				keep[String(p.sha256) + ".pck"] = true
	var removed := 0
	if DirAccess.dir_exists_absolute(store_dir()):
		for f in DirAccess.get_files_at(store_dir()):
			if not keep.has(f):
				DirAccess.remove_absolute(store_dir() + "/" + f)
				removed += 1
	return removed


# --------------------------------------------------------------------------
# Auto-mise à jour du lanceur, avec retour arrière
# --------------------------------------------------------------------------

## Fichier posé par le NOUVEAU lanceur quand il a bien démarré (--updated) :
## sans lui, le script de mise à jour remet l'ancien lanceur.
const UPDATE_OK := "user://launcher_update.ok"
## Journal des mises à jour du lanceur (gardé, complété à chaque fois).
const UPDATE_LOG := "user://logs/launcher_update.log"
## Attente du démarrage du nouveau lanceur (secondes, par pas de 2 s).
const UPDATE_WAIT_STEPS := 45


## Script .bat de remplacement (un exécutable ouvert ne peut pas être
## écrasé : il tourne après la fermeture du lanceur) :
##   1. attend que l'ancien lanceur libère son fichier (2 min au plus) ;
##   2. le garde en « .bak », met le nouveau à sa place et le démarre (--updated) ;
##   3. attend que le nouveau signale son démarrage (UPDATE_OK, 90 s) ;
##   4. sinon : nouveau arrêté et mis de côté (« .echec »), ancien remis et
##      relancé (--update-failed) ; chaque étape est notée dans le journal.
## Chemins Windows ; « % » doublé (spécial dans un .bat).
static func update_script(current: String, fresh: String, ok_marker: String, log_file: String) -> String:
	var lines := [
		"@echo off",
		"setlocal",
		"set \"CUR={CUR}\"",
		"set \"NEW={NEW}\"",
		"set \"BAK={CUR}.bak\"",
		"set \"OK={OK}\"",
		"set \"LOG={LOG}\"",
		"echo [%date% %time%] mise a jour du lanceur : debut>>\"%LOG%\"",
		"del \"%OK%\" 2>nul",
		"set /a n=0",
		":free",
		"move /y \"%CUR%\" \"%BAK%\" >nul 2>&1 && goto moved",
		"set /a n+=1",
		"if %n% geq 60 goto busy",
		"ping 127.0.0.1 -n 3 >nul",
		"goto free",
		":moved",
		"move /y \"%NEW%\" \"%CUR%\" >nul 2>&1 || goto restore",
		"echo [%date% %time%] nouveau lanceur en place, demarrage>>\"%LOG%\"",
		"start \"\" \"%CUR%\" --updated",
		"set /a n=0",
		":wait",
		"ping 127.0.0.1 -n 3 >nul",
		"if exist \"%OK%\" goto done",
		"set /a n+=1",
		"if %n% lss {STEPS} goto wait",
		"echo [%date% %time%] le nouveau lanceur n'a pas demarre : retour a l'ancien>>\"%LOG%\"",
		"taskkill /f /im \"{EXE}\" >nul 2>&1",
		"ping 127.0.0.1 -n 3 >nul",
		":restore",
		"move /y \"%CUR%\" \"%NEW%.echec\" >nul 2>&1",
		"move /y \"%BAK%\" \"%CUR%\" >nul 2>&1",
		"echo [%date% %time%] ancien lanceur remis>>\"%LOG%\"",
		"start \"\" \"%CUR%\" --update-failed",
		"goto end",
		":busy",
		"echo [%date% %time%] ancien lanceur toujours ouvert : mise a jour abandonnee>>\"%LOG%\"",
		"goto end",
		":done",
		"del \"%BAK%\" 2>nul",
		"echo [%date% %time%] mise a jour reussie>>\"%LOG%\"",
		":end",
		"del \"%~f0\"",
	]
	var win := func(p: String) -> String: return p.replace("/", "\\").replace("%", "%%")
	var text := "\r\n".join(PackedStringArray(lines)) + "\r\n"
	return text.replace("{CUR}", win.call(current)).replace("{NEW}", win.call(fresh)) \
		.replace("{OK}", win.call(ok_marker)).replace("{LOG}", win.call(log_file)) \
		.replace("{EXE}", win.call(current.get_file())).replace("{STEPS}", str(UPDATE_WAIT_STEPS))
