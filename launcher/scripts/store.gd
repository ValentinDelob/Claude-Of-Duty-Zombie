extends RefCounted
## Versions installées et réglages du lanceur.
## Jeux : %LOCALAPPDATA%\CallOfClaudeZombie\versions\<version>\CallOfClaudeZombie.exe
## (dossier et nom de fichier de l'ancien nom du jeu, gardés pour ne pas
## retélécharger les versions déjà installées)
## (comme les versions du lanceur de Minecraft, une copie par version).

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


static func exe_path(tag: String) -> String:
	return versions_dir() + "/" + tag + "/" + EXE_NAME


static func is_installed(tag: String) -> bool:
	return FileAccess.file_exists(exe_path(tag))


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


## Emplacement de téléchargement : un fichier partiel renommé à la fin.
static func part_path(tag: String) -> String:
	return versions_dir() + "/" + tag + "/" + EXE_NAME + ".part"


static func prepare_dir(tag: String) -> void:
	DirAccess.make_dir_recursive_absolute(versions_dir() + "/" + tag)


## Termine un téléchargement : le fichier partiel devient l'exécutable.
static func finish_download(tag: String) -> bool:
	var part := part_path(tag)
	if not FileAccess.file_exists(part):
		return false
	if FileAccess.file_exists(exe_path(tag)):
		DirAccess.remove_absolute(exe_path(tag))
	return DirAccess.rename_absolute(part, exe_path(tag)) == OK


static func remove(tag: String) -> void:
	var dir := versions_dir() + "/" + tag
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)


static func load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	var lang := "fr" if OS.get_locale_language() == "fr" else "en"
	if cfg.load(SETTINGS) != OK:
		return {"language": lang, "selected": "latest"}
	return {"language": cfg.get_value("launcher", "language", lang),
		"selected": cfg.get_value("launcher", "selected", "latest")}


static func save_settings(s: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("launcher", "language", s.get("language", "fr"))
	cfg.set_value("launcher", "selected", s.get("selected", "latest"))
	cfg.save(SETTINGS)
