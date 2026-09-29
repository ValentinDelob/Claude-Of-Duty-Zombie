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
	var out := {"language": lang, "selected": "latest"}
	var f := FileAccess.open(SETTINGS, FileAccess.READ)
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
	var l = cfg.get_value("launcher", "language", lang)
	var s = cfg.get_value("launcher", "selected", "latest")
	out.language = l if l is String and l in ["fr", "en"] else lang
	out.selected = s if s is String and (s == "latest" or Releases.is_safe_tag(s)) else "latest"
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
	cfg.save(SETTINGS)
