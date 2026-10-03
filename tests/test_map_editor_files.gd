extends TestCase
## Fichiers de l'éditeur de cartes (docs/MAP_AUTHORING.md) : suppression d'une
## carte du joueur (dossier des cartes seulement, jamais un exemple ni un
## chemin hors du dossier), carte ouverte supprimée gardée en mémoire ; en
## session, Ouvrir / Enregistrer réservés à l'hôte (docs/MAP_COLLAB.md § 7).
## Ports 17820+ (décalés par AUTOTEST_PORT_OFFSET).

const TMP := "res://tests/_out/test_map_editor_files"
const BASE := 17820


func before_each() -> void:
	var tmp := ProjectSettings.globalize_path(TMP)
	if DirAccess.dir_exists_absolute(tmp):
		EditorMap._remove_tree(tmp)
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")
	DirAccess.make_dir_recursive_absolute(EditorMap.root_override)


func after_each() -> void:
	EditorMap.root_override = ""


func _port(i: int) -> int:
	return BASE + i + OS.get_environment("AUTOTEST_PORT_OFFSET").to_int()


func _until(cond: Callable, limit := 5.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > limit * 1000.0:
			return false
		await host.get_tree().process_frame
	return true


func _saved(id: String) -> String:
	var dir := EditorMap.map_dir(id)
	var m := EditorMap.blank(id, id.to_upper(), id.to_upper())
	assert_eq(m.save_dir(dir), OK, "carte %s enregistrée" % id)
	return dir


# ------------------------------------------------------------------ suppression

func test_delete_map_inside_the_maps_folder() -> void:
	var dir := _saved("a_effacer")
	# Sous-dossier en plus (fichiers ajoutés à la carte) : supprimé aussi.
	DirAccess.make_dir_recursive_absolute(dir.path_join("extra"))
	var f := FileAccess.open(dir.path_join("extra/note.txt"), FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var keep := _saved("a_garder")
	assert_true(EditorMap.list_maps().any(func(m): return m.id == "a_effacer"), "listée avant")
	assert_true(EditorMap.delete_map(dir), "supprimée")
	assert_false(DirAccess.dir_exists_absolute(dir), "dossier parti")
	assert_false(EditorMap.list_maps().any(func(m): return m.id == "a_effacer"), "plus listée")
	assert_true(EditorMap.is_map_dir(keep), "l'autre carte reste")
	assert_false(EditorMap.delete_map(dir), "déjà supprimée : refus")


func test_delete_map_refuses_outside_paths_and_examples() -> void:
	var root := EditorMap.maps_root()
	# Carte rangée hors du dossier des cartes : jamais touchée.
	var outside := ProjectSettings.globalize_path(TMP + "/ailleurs/carte_dehors")
	assert_eq(EditorMap.blank("carte_dehors").save_dir(outside), OK)
	assert_false(EditorMap.delete_map(outside), "hors du dossier des cartes : refus")
	assert_true(EditorMap.is_map_dir(outside), "carte hors du dossier intacte")
	var inside := _saved("dedans")
	assert_false(EditorMap.delete_map(root.path_join("dedans/../dedans")), "« .. » : refus")
	assert_false(EditorMap.delete_map(root.path_join("../ailleurs/carte_dehors")), "« .. » vers l'extérieur : refus")
	assert_false(EditorMap.delete_map(root), "le dossier des cartes lui-même : refus")
	assert_false(EditorMap.delete_map(""), "chemin vide : refus")
	assert_true(EditorMap.is_map_dir(inside), "carte du joueur intacte")
	# Sous-dossier d'une carte (pas un enfant direct du dossier des cartes).
	DirAccess.make_dir_recursive_absolute(inside.path_join("sous"))
	assert_eq(EditorMap.blank("sous").save_dir(inside.path_join("sous")), OK)
	assert_false(EditorMap.delete_map(inside.path_join("sous")), "pas un enfant direct : refus")
	# Exemples livrés, dossiers internes (_autosave), dossier sans carte.
	for ex in EditorMap.EXAMPLES.values():
		assert_false(EditorMap.delete_map(String(ex)), "exemple livré : refus")
		assert_true(EditorMap.is_map_dir(String(ex)), "exemple intact")
	assert_eq(EditorMap.blank().save_dir(root.path_join("_autosave")), OK)
	assert_false(EditorMap.delete_map(root.path_join("_autosave")), "dossier interne : refus")
	DirAccess.make_dir_recursive_absolute(root.path_join("pas_une_carte"))
	assert_false(EditorMap.delete_map(root.path_join("pas_une_carte")), "pas une carte : refus")
	assert_true(DirAccess.dir_exists_absolute(root.path_join("pas_une_carte")))


func test_deleting_the_open_map_keeps_it_unsaved() -> void:
	var dir := _saved("ouverte")
	var other := _saved("autre")
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.open_dir(dir)
	assert_eq(ed.map_dir, dir)
	ed.add_object({"contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}, 0)
	ed.write_recovery()
	assert_true(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie de récupération écrite")
	# Fenêtre Ouvrir : Supprimer grisé sur un exemple, actif sur une carte.
	var d := ed.open_dialog()
	var list: ItemList = d.get_meta("list")
	var del: Button = d.get_meta("delete")
	assert_true(list != null and del != null, "liste et bouton Supprimer")
	assert_eq(list.item_count, EditorMap.EXAMPLES.size() + 2, "exemples + cartes du joueur")
	list.select(0)
	list.item_selected.emit(0)
	assert_true(del.disabled, "exemple : Supprimer grisé")
	list.select(list.item_count - 1)
	list.item_selected.emit(list.item_count - 1)
	assert_false(del.disabled, "carte du joueur : Supprimer actif")
	d.queue_free()
	assert_true(ed.delete_map(dir), "carte ouverte supprimée")
	assert_false(DirAccess.dir_exists_absolute(dir))
	assert_eq(ed.map_dir, "", "plus de dossier : Enregistrer en redemande un")
	assert_true(ed.dirty, "non enregistrée")
	assert_eq(ed.doc.pieces.size(), 1, "carte gardée en mémoire")
	assert_false(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie de récupération effacée")
	assert_true(EditorMap.is_map_dir(other), "l'autre carte reste")
	assert_false(ed.delete_map(EditorMap.EXAMPLES.values()[0]), "exemple : refus")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ session : hôte seulement

func test_guest_cannot_open_or_save() -> void:
	var dir := _saved("de_l_invite")
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.open_dir(dir)
	var fm := ed.file_menu.get_popup()
	ed.update_file_menu()
	for id in MapEditor.HOST_ONLY_FILE_IDS:
		assert_false(fm.is_item_disabled(fm.get_item_index(id)), "seul : Fichier %d actif" % id)
	var h := MapCollab.new(EditorMap.blank("session", "SESSION", "SESSION"))
	host.add_child(h)
	assert_eq(h.host(_port(0), "Alice"), OK, "hôte à l'écoute")
	ed.collab.join("127.0.0.1", _port(0), h.session_code, "Bob")
	assert_true(await _until(func(): return ed.collab.role == MapCollab.Role.GUEST and not ed.collab._joining), "invité accueilli")
	assert_eq(ed.doc.id(), "session", "carte de l'hôte reçue")
	assert_eq(ed.map_dir, "", "invité : pas de dossier")
	# Menu Fichier : grisé, avec une bulle ; Options et Retour restent.
	for id in MapEditor.HOST_ONLY_FILE_IDS:
		var i := fm.get_item_index(id)
		assert_true(fm.is_item_disabled(i), "invité : Fichier %d grisé" % id)
		assert_true(fm.get_item_tooltip(i) != "", "bulle « réservé à l'hôte »")
	assert_false(fm.is_item_disabled(fm.get_item_index(8)), "Options toujours là")
	assert_false(fm.is_item_disabled(fm.get_item_index(7)), "Retour au menu toujours là")
	# Actions (et raccourcis, qui les appellent) refusées, message clair.
	ed.dirty = true
	assert_false(ed.save(), "Ctrl+S refusé")
	assert_true(ed.status.text.contains("hôte") or ed.status.text.contains("Host"), "message : %s" % ed.status.text)
	assert_false(ed.save_as("vol"), "Enregistrer sous refusé")
	assert_false(EditorMap.is_map_dir(EditorMap.map_dir("vol")), "rien d'écrit")
	assert_true(ed.open_dialog() == null, "Ctrl+O refusé")
	ed.open_dir(dir)
	assert_eq(ed.doc.id(), "session", "ouvrir une carte : refusé, toujours la carte de la session")
	ed.new_map(true)
	assert_eq(ed.doc.id(), "session", "Ctrl+N refusé")
	assert_false(ed.import_zip(TMP + "/rien.zip"), "import refusé")
	assert_false(ed.export_zip(ProjectSettings.globalize_path(TMP + "/sortie.zip")), "export refusé")
	assert_false(FileAccess.file_exists(ProjectSettings.globalize_path(TMP + "/sortie.zip")))
	assert_false(ed.delete_map(dir), "suppression refusée")
	assert_true(EditorMap.is_map_dir(dir))
	assert_eq(ed.collab.role, MapCollab.Role.GUEST, "toujours dans la session")
	ed.write_recovery()
	assert_false(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "invité : pas de copie de récupération")
	# Raccourci clavier : Ctrl+S passe par save() (refusé).
	var ev := InputEventKey.new()
	ev.keycode = KEY_S
	ev.ctrl_pressed = true
	ev.pressed = true
	ed._input(ev)
	assert_false(EditorMap.is_map_dir(EditorMap.map_dir("session")), "Ctrl+S : rien d'écrit")
	# Session quittée : tout redevient possible.
	ed.collab.leave()
	await wait_frames(1)
	for id in MapEditor.HOST_ONLY_FILE_IDS:
		assert_false(fm.is_item_disabled(fm.get_item_index(id)), "session quittée : Fichier %d actif" % id)
	assert_true(ed.save(), "seul : Enregistrer de nouveau possible")
	assert_true(EditorMap.is_map_dir(EditorMap.map_dir("session")))
	h.leave()
	h.queue_free()
	ed.queue_free()
	await wait_frames(1)


func test_host_keeps_its_map_id() -> void:
	var host_doc := EditorMap.blank("chez_l_hote", "HÔTE", "HOST")
	var c := (host_doc.carte as Dictionary).duplicate(true)
	c["id"] = "vol_du_dossier"
	c["nom"] = {"fr": "RENOMMÉE", "en": "RENAMED"}
	var ops := MapCollab.host_only_guard(host_doc, [{"op": "carte", "carte": c}])
	assert_eq(String(ops[0].carte.id), "chez_l_hote", "l'identifiant (dossier) reste celui de l'hôte")
	assert_eq(String(ops[0].carte.nom.fr), "RENOMMÉE", "le reste du changement passe")
