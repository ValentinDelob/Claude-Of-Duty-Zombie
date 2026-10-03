extends TestCase
## Choix d'un fichier du disque dans l'éditeur (FilePick, docs/MAP_AUTHORING.md) :
## l'explorateur du système quand il existe (Exporter / Importer une archive,
## Importer un modèle de prefab), bons titres, modes, filtres, dossier et nom
## proposés ; chemin rendu traité (extension ajoutée à l'enregistrement),
## annulation sans effet ; repli sur la fenêtre de Godot sans dialogue natif.
## L'explorateur est SIMULÉ (FilePick.native_show) : jamais de vraie fenêtre.

const TMP := "res://tests/_out/test_file_pick"
const Prefabs := preload("res://tests/test_map_prefabs.gd")

## Appels au dialogue natif simulé : [titre, dossier, nom, cachés, mode, filtres, rappel].
var calls := []


func before_each() -> void:
	var tmp := ProjectSettings.globalize_path(TMP)
	if DirAccess.dir_exists_absolute(tmp):
		EditorMap._remove_tree(tmp)
	DirAccess.make_dir_recursive_absolute(tmp)
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")
	CustomMapGuard.cache_override = ProjectSettings.globalize_path(TMP + "/cache")
	calls = []
	FilePick.native_override = 1
	FilePick.native_show = func(title, dir, file, hidden, mode, filters, cb):
		calls.append([title, dir, file, hidden, mode, filters, cb])
		return OK


func after_each() -> void:
	FilePick.native_override = -1
	FilePick.native_show = Callable()
	FilePick.last_request = {}
	EditorMap.root_override = ""
	CustomMapGuard.cache_override = ""
	MapCatalog.set_map_prefabs({})


func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	return ed


func _file_dialogs(ed: Node) -> Array:
	return ed.get_children().filter(func(c): return c is FileDialog and not c.is_queued_for_deletion())


# ------------------------------------------------------------------ outils

func test_extensions_and_save_suffix() -> void:
	var f := PackedStringArray(["*.glb, *.gltf ; Modèle", "*.ZIP ; Archive"])
	assert_eq(FilePick.extensions(f), PackedStringArray(["glb", "gltf", "zip"]))
	var z := PackedStringArray(["*.zip ; Archive"])
	assert_eq(FilePick.with_extension("C:/Docs/carte", z), "C:/Docs/carte.zip", "extension ajoutée")
	assert_eq(FilePick.with_extension("C:/Docs/carte.ZIP", z), "C:/Docs/carte.ZIP", "déjà là : inchangé")
	assert_eq(FilePick.with_extension("C:/Docs/carte.v2", z), "C:/Docs/carte.v2.zip", "autre extension : .zip ajouté")
	FilePick.native_override = 0
	assert_false(FilePick.native_available(), "absence simulée")
	FilePick.native_override = -1
	assert_eq(FilePick.native_available(), DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE), "sinon : le système décide")


# ------------------------------------------------------------------ explorateur du système

func test_export_archive_uses_system_dialog() -> void:
	var ed := await _editor()
	ed._zip_dialog(true)
	assert_eq(calls.size(), 1, "explorateur du système ouvert")
	assert_true(_file_dialogs(ed).is_empty(), "pas de fenêtre de Godot")
	var c: Array = calls[0]
	assert_eq(String(c[0]), Lang.t("Exporter l'archive", "Export the archive"), "titre traduit")
	assert_eq(String(c[1]), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), "départ : Documents")
	assert_eq(String(c[2]), ed.doc.id() + ".zip", "nom proposé")
	assert_eq(int(c[4]), DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, "mode enregistrer")
	assert_eq(c[5], PackedStringArray(["*.zip ; " + Lang.t("Archive de carte", "Map archive")]), "filtre .zip")
	# Chemin absolu du système, sans extension : .zip ajouté, archive écrite
	# (rappel ramené sur le fil principal : une image plus tard).
	var out := ProjectSettings.globalize_path(TMP + "/sortie")
	(c[6] as Callable).call(true, PackedStringArray([out]), 0)
	await wait_frames(2)
	assert_true(FileAccess.file_exists(out + ".zip"), "archive exportée en .zip")
	ed.queue_free()
	await wait_frames(1)


func test_import_archive_and_cancel() -> void:
	var ed := await _editor()
	var src := EditorMap.blank("venue", "VENUE", "CAME")
	var zip := ProjectSettings.globalize_path(TMP + "/venue.zip")
	assert_eq(src.export_zip(zip), OK)
	# Annulé : rien ne change.
	ed._zip_dialog(false)
	assert_eq(int(calls[0][4]), DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "mode ouvrir")
	assert_eq(String(calls[0][2]), "", "ouvrir : pas de nom proposé")
	var before := ed.doc.id()
	(calls[0][6] as Callable).call(false, PackedStringArray(), 0)
	await wait_frames(2)
	assert_eq(ed.doc.id(), before, "annulé : carte inchangée")
	# Choisi : l'archive repasse par import_zip.
	ed._zip_dialog(false)
	assert_eq(calls.size(), 2)
	(calls[1][6] as Callable).call(true, PackedStringArray([zip]), 0)
	await wait_frames(2)
	assert_eq(ed.doc.id(), "venue", "archive importée")
	assert_true(ed.dirty, "à enregistrer")
	ed.queue_free()
	await wait_frames(1)


func test_import_model_uses_system_dialog() -> void:
	var ed := await _editor()
	var src := ProjectSettings.globalize_path(TMP + "/src/statue.glb")
	Prefabs._write(src, Prefabs.box_glb(Vector3(1, 1, 1)))
	ed.prefab_tools.import_dialog()
	assert_eq(calls.size(), 1, "explorateur du système ouvert")
	assert_true(_file_dialogs(ed).is_empty(), "pas de fenêtre de Godot")
	var c: Array = calls[0]
	assert_eq(String(c[0]), Lang.t("Importer un modèle (prefab de la carte)", "Import a model (map prefab)"))
	assert_eq(int(c[4]), DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "mode ouvrir")
	assert_eq(c[5], PackedStringArray(["*.glb, *.gltf ; " + Lang.t("Modèle 3D glTF", "glTF 3D model")]), "filtre glTF")
	# Annulé : rien d'importé.
	(c[6] as Callable).call(false, PackedStringArray(), 0)
	await wait_frames(2)
	assert_true(ed.doc.models.is_empty(), "annulé : aucun modèle")
	# Choisi : importé (contrôles de MapPrefabLib.read_import).
	ed.prefab_tools.import_dialog()
	(calls[1][6] as Callable).call(true, PackedStringArray([src]), 0)
	await wait_frames(2)
	assert_eq(ed.doc.models.size(), 1, "modèle importé")
	# Un autre fichier choisi malgré le filtre : refusé après coup.
	var txt := ProjectSettings.globalize_path(TMP + "/src/note.txt")
	Prefabs._write(txt, "x".to_utf8_buffer())
	ed.prefab_tools.import_dialog()
	(calls[2][6] as Callable).call(true, PackedStringArray([txt]), 0)
	await wait_frames(2)
	assert_eq(ed.doc.models.size(), 1, "extension refusée")
	assert_true(ed._status_error, "raison affichée")
	ed.queue_free()
	await wait_frames(1)


func test_native_failure_falls_back() -> void:
	FilePick.native_show = func(_t, _d, _f, _h, _m, _fl, _cb): return ERR_UNAVAILABLE
	var ed := await _editor()
	ed._zip_dialog(true)
	assert_eq(_file_dialogs(ed).size(), 1, "échec du système : fenêtre de Godot")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ repli

func test_fallback_without_native_dialog() -> void:
	FilePick.native_override = 0
	var ed := await _editor()
	ed._zip_dialog(true)
	assert_true(calls.is_empty(), "pas d'appel au système")
	var fds := _file_dialogs(ed)
	assert_eq(fds.size(), 1, "fenêtre de Godot")
	var fd: FileDialog = fds[0]
	assert_false(fd.use_native_dialog)
	assert_eq(fd.file_mode, FileDialog.FILE_MODE_SAVE_FILE)
	assert_eq(fd.access, FileDialog.ACCESS_FILESYSTEM)
	assert_eq(fd.current_file, ed.doc.id() + ".zip")
	var out := ProjectSettings.globalize_path(TMP + "/repli.zip")
	fd.file_selected.emit(out)
	await wait_frames(1)
	assert_true(FileAccess.file_exists(out), "archive exportée")
	assert_true(_file_dialogs(ed).is_empty(), "fenêtre libérée")
	# Modèle : même repli, annulation qui libère la fenêtre.
	ed.prefab_tools.import_dialog()
	fds = _file_dialogs(ed)
	assert_eq(fds.size(), 1)
	assert_eq((fds[0] as FileDialog).file_mode, FileDialog.FILE_MODE_OPEN_FILE)
	assert_eq((fds[0] as FileDialog).filters, PackedStringArray(["*.glb, *.gltf ; " + Lang.t("Modèle 3D glTF", "glTF 3D model")]))
	(fds[0] as FileDialog).canceled.emit()
	await wait_frames(1)
	assert_true(_file_dialogs(ed).is_empty(), "annulé : fenêtre libérée")
	assert_true(ed.doc.models.is_empty(), "rien d'importé")
	ed.queue_free()
	await wait_frames(1)
