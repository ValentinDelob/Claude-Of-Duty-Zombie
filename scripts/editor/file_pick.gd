class_name FilePick
extends RefCounted
## CHOIX D'UN FICHIER DU DISQUE (éditeur de cartes) : l'explorateur du système
## hôte (Windows : l'Explorateur ; macOS : le Finder ; Linux : le portail du
## bureau) via DisplayServer.file_dialog_show. La fenêtre maison de Godot
## (FileDialog) n'est qu'un REPLI quand le système n'a pas de dialogue natif
## (FEATURE_NATIVE_DIALOG_FILE absente : --headless des tests, Linux sans
## portail).
##   - le dialogue natif est asynchrone : `on_pick` est appelé plus tard, sur
##     le fil principal, avec un chemin ABSOLU du système (jamais user://) ;
##     annulé : rien n'est appelé ;
##   - enregistrement : l'extension du filtre est ajoutée si le chemin rendu
##     n'en a pas ; ouverture : l'appelant garde ses contrôles (extension,
##     taille, contenu) sur le fichier choisi.
## Tests : `native_override` simule la présence (1) ou l'absence (0) du
## dialogue natif et `native_show` remplace l'appel au système : JAMAIS de
## vraie fenêtre de l'explorateur pendant les tests.

enum Mode { OPEN, SAVE }

## Tests : 1 = dialogue natif disponible, 0 = absent, -1 = demander au système.
static var native_override := -1
## Tests : remplace DisplayServer.file_dialog_show (mêmes arguments).
static var native_show := Callable()
## Dernière demande (tests) : title, mode, filters, dir, file, native.
static var last_request := {}


static func native_available() -> bool:
	if native_override >= 0:
		return native_override == 1
	return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)


## Demande un fichier. `filters` : « *.glb, *.gltf ; Libellé » (déjà traduit) ;
## `file` : nom proposé (enregistrement) ; `dir` : dossier de départ (vide :
## Documents). Rend la fenêtre de repli (FileDialog, enfant de `host`) ou null
## (dialogue natif).
static func pick(host: Node, title: String, mode: Mode, filters: PackedStringArray, on_pick: Callable,
		file := "", dir := "", ui_scale := 1.0) -> FileDialog:
	if dir == "":
		dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var native := native_available()
	last_request = {"title": title, "mode": mode, "filters": filters, "dir": dir, "file": file, "native": native}
	var done := func(path: String) -> void:
		if path != "" and on_pick.is_valid():
			on_pick.call(with_extension(path, filters) if mode == Mode.SAVE else path)
	if native:
		var dm := DisplayServer.FILE_DIALOG_MODE_SAVE_FILE if mode == Mode.SAVE else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
		# Rappel du système (status, chemins, filtre) : ramené sur le fil
		# principal (différé), annulation ou liste vide ignorées.
		var cb := func(status: bool, paths: PackedStringArray, _filter: int) -> void:
			if status and not paths.is_empty():
				done.call_deferred(String(paths[0]))
		var show := native_show if native_show.is_valid() else Callable(DisplayServer, "file_dialog_show")
		var err: Variant = show.call(title, dir, file, false, dm, filters, cb)
		if err is int and err != OK:
			push_warning("[FilePick] dialogue natif indisponible (%s) : fenêtre de repli" % error_string(err))
		else:
			return null
	# Repli : la fenêtre de Godot (contenu interne) ; seule sa taille suit l'interface.
	var fd := FileDialog.new()
	fd.use_native_dialog = false
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE if mode == Mode.SAVE else FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = filters
	fd.title = title
	fd.current_dir = dir
	if file != "":
		fd.current_file = file
	fd.set_meta(EditorUi.SKIP, true)
	var room := host.get_viewport().get_visible_rect().size if host.is_inside_tree() else Vector2(800, 520)
	fd.size = Vector2i((Vector2(760, 480) * ui_scale).min(room - Vector2(40, 40)))
	host.add_child(fd)
	fd.file_selected.connect(func(path: String):
		done.call(path)
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered()
	return fd


## Chemin d'enregistrement avec l'extension du premier filtre s'il n'a aucune
## des extensions des filtres (« carte » → « carte.zip »).
static func with_extension(path: String, filters: PackedStringArray) -> String:
	var exts := extensions(filters)
	if exts.is_empty() or path.get_extension().to_lower() in exts:
		return path
	return path + "." + exts[0]


## Extensions (minuscules, sans point) des filtres « *.a, *.b ; Libellé ».
static func extensions(filters: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for f in filters:
		for pat in f.get_slice(";", 0).split(","):
			var p := pat.strip_edges()
			if p.begins_with("*.") and p.length() > 2:
				out.append(p.substr(2).to_lower())
	return out
