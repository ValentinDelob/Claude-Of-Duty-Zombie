extends TestCase
## Enregistrement EXPLICITE de l'éditeur de cartes (MapUnsaved,
## docs/MAP_AUTHORING.md § 6) : le dossier de la carte n'est écrit que par
## Enregistrer ; étoile « * » exacte (annulation jusqu'à l'état enregistré,
## Claude, autres participants) ; confirmation Enregistrer / Quitter sans
## enregistrer / Annuler à chaque façon de perdre des modifications ; copie de
## récupération (jamais dans la carte) proposée après un « plantage » ; TESTER
## en solo : session (carte, historique) gardée pendant la partie ;
## collaboration : l'hôte enregistre, l'invité n'a rien à confirmer.
## Dossier de test (EditorMap.root_override) : jamais les cartes du joueur.
## Ports 17760+ (décalés par AUTOTEST_PORT_OFFSET).

const TMP := "res://tests/_out/test_map_unsaved"
const BASE := 17760
const ROOM := {"contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}

var calls := []


func before_each() -> void:
	var tmp := ProjectSettings.globalize_path(TMP)
	if DirAccess.dir_exists_absolute(tmp):
		EditorMap._remove_tree(tmp)
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")
	DirAccess.make_dir_recursive_absolute(EditorMap.root_override)
	calls = []
	FilePick.native_override = 1
	FilePick.native_show = func(title, dir, file, hidden, mode, filters, cb):
		calls.append([title, dir, file, hidden, mode, filters, cb])
		return OK


func after_each() -> void:
	MapEditor.drop_test_keep()
	FilePick.native_override = -1
	FilePick.native_show = Callable()
	FilePick.last_request = {}
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


func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	return ed


func _free(ed: MapEditor) -> void:
	if is_instance_valid(ed):
		ed.queue_free()
	await wait_frames(1)


## Contenu et dates des fichiers d'un dossier de carte.
func _files(dir: String) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(dir):
		out[f] = [FileAccess.get_file_as_string(dir.path_join(f)), FileAccess.get_modified_time(dir.path_join(f))]
	return out


func _star(ed: MapEditor) -> bool:
	return ed.title_label.text.contains(" *")


func _caisse(id: String, x := 12.0) -> Array:
	return [{"op": "put", "coll": "objets", "el": {"id": id, "type": "caisse", "etage": 0, "position": [x, 5.0]}}]


func _press(d: ConfirmationDialog, choice: String) -> void:
	match choice:
		"save":
			d.get_ok_button().pressed.emit()
		"discard":
			(d.get_meta("discard") as Button).pressed.emit()
		_:
			d.get_cancel_button().pressed.emit()


# ------------------------------------------------------------------ jamais d'écriture sans Enregistrer

func test_edits_never_write_the_map_until_save() -> void:
	var dir := _saved("ma_carte")
	var ed := await _editor()
	ed.open_dir(dir)
	var before := _files(dir)
	assert_false(ed.dirty, "ouverte : rien à enregistrer")
	assert_false(_star(ed), "pas d'étoile : %s" % ed.title_label.text)
	# Une série de modifications, annulations, rétablissements.
	ed.add_object(ROOM, 0)
	ed.add_object({"contour": [[12, 2], [18, 2], [18, 8], [12, 8]]}, 0)
	ed.undo()
	ed.redo()
	ed.collab.submit_ops(_caisse("c1"), "caisse")
	assert_true(ed.dirty and _star(ed), "modifiée : étoile (%s)" % ed.title_label.text)
	# Minuterie de récupération : copie à part, jamais dans la carte.
	ed._recovery_t = MapEditor.RECOVERY_EVERY
	ed._process(0.0)
	assert_true(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie de récupération écrite")
	assert_eq(String(MapUnsaved.read_meta(MapUnsaved.recovery_dir()).get("source", "")), dir, "copie : dossier d'origine noté")
	# Claude (MCP) : la carte est modifiée, pas enregistrée.
	var link := MapAgentLink.new()
	link.collab = ed.collab
	link.editor = ed
	var r := link.cmd_apply({"ops": _caisse("c2", 14.0), "label": "Caisse de Claude"})
	assert_false(r.has("error"), "apply de Claude : %s" % str(r))
	assert_false(ed.doc.find("c2").is_empty(), "élément de Claude sur la carte")
	assert_true(ed.dirty and bool(link._status().get("dirty", false)), "Claude : carte modifiée (aussi pour editor_status)")
	link.free()
	await wait_frames(2)
	assert_eq(_files(dir), before, "dossier de la carte jamais touché sans Enregistrer")
	# Enregistrer : seul moment où la carte est écrite ; la copie disparaît.
	assert_true(ed.save(), "Ctrl+S")
	assert_false(ed.dirty or _star(ed), "enregistrée : plus d'étoile")
	assert_true(FileAccess.get_file_as_string(dir.path_join("objets.json")).contains("c2"), "la carte enregistrée contient le travail")
	assert_false(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie de récupération effacée après l'enregistrement")
	await _free(ed)


func test_star_follows_undo_back_to_saved_state() -> void:
	var dir := _saved("etoile")
	var ed := await _editor()
	ed.open_dir(dir)
	var p := ed.add_object(ROOM, 0)
	assert_true(_star(ed), "pièce posée : étoile")
	ed.undo()
	assert_false(ed.dirty or _star(ed), "annulée jusqu'à l'état enregistré : plus d'étoile (%s)" % ed.title_label.text)
	ed.redo()
	assert_true(ed.dirty and _star(ed), "rétablie : étoile")
	assert_true(ed.save())
	assert_false(_star(ed), "enregistrée")
	ed.delete_element(String(ed.doc.pieces[0].id) if not ed.doc.pieces.is_empty() else String(p.get("id", "")))
	assert_true(ed.dirty, "supprimée : étoile")
	ed.undo()
	assert_false(ed.dirty, "suppression annulée (élément remis, ordre indifférent) : plus d'étoile")
	# Changement d'un autre participant (ici : le Claude de la session).
	ed.collab.submit_ops(_caisse("autre"), "caisse", ed.collab.my_id + ":claude")
	assert_true(ed.dirty and _star(ed), "changement d'un autre : étoile")
	# Archive importée, carte supprimée : à enregistrer quoi qu'il arrive.
	ed.dirty = true
	assert_true(ed.dirty)
	ed.dirty = false
	assert_false(ed.dirty, "état courant pris comme enregistré")
	await _free(ed)


# ------------------------------------------------------------------ confirmation à chaque sortie

func test_every_way_out_asks_first() -> void:
	var dir := _saved("sorties")
	var other := _saved("autre_carte")
	var ed := await _editor()
	ed.open_dir(other)
	ed.open_dir(dir)
	ed.add_object(ROOM, 0)
	assert_true(ed.needs_save_prompt())
	var zip := ProjectSettings.globalize_path(TMP + "/venue.zip")
	assert_eq(EditorMap.blank("venue", "VENUE", "CAME").export_zip(zip), OK)
	var ways := {
		"retour au menu": func(): ed.quit_to_menu(),
		"fermer la fenêtre": func(): ed._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST),
		"nouvelle carte": func(): ed.new_map(),
		"carte récente": func():
			ed._fill_recent()
			ed._recent_menu.index_pressed.emit(1),
		"Ouvrir…": func():
			var d := ed.open_dialog()
			var list: ItemList = d.get_meta("list")
			list.select(list.item_count - 1)
			d.get_ok_button().pressed.emit(),
		"importer une archive": func():
			ed._zip_dialog(false)
			(calls[-1][6] as Callable).call(true, PackedStringArray([zip]), 0),
		"rejoindre une session": func(): ed.collab_ui.join_dialog(),
	}
	for what in ways:
		(ways[what] as Callable).call()
		await wait_frames(2)
		var d := ed._unsaved_dialog
		assert_true(d != null and d.visible, "%s : boîte « non enregistrée »" % what)
		if d == null:
			continue
		assert_eq(d.get_ok_button().text, Lang.t("Enregistrer", "Save"), "%s : Enregistrer" % what)
		assert_eq((d.get_meta("discard") as Button).text, Lang.t("Quitter sans enregistrer", "Quit without saving"))
		assert_eq(d.get_cancel_button().text, Lang.t("Annuler", "Cancel"))
		assert_true(d.dialog_text.contains("SORTIES"), "nom de la carte dans le message")
		_press(d, "cancel")
		await wait_frames(2)
		assert_true(ed._unsaved_dialog == null, "%s : Annuler ferme la boîte" % what)
		assert_eq(ed.map_dir, dir, "%s annulé : même carte" % what)
		assert_eq(ed.doc.pieces.size(), 1, "%s annulé : modifications gardées" % what)
		assert_true(ed.dirty and ed.collab.role == MapCollab.Role.SOLO, "%s annulé : toujours à enregistrer, seul" % what)
	# Pas de fenêtre « Rejoindre » ouverte par l'annulation.
	assert_true(ed.get_children().filter(func(c): return c is ConfirmationDialog and c.visible).is_empty(), "aucune autre fenêtre ouverte")
	# Échap = Annuler (dialog_close_on_escape), Entrée = Enregistrer (focus).
	var d2 := ed.confirm_unsaved("tester", func(): pass)
	await wait_frames(2)
	assert_true(d2.dialog_close_on_escape, "Échap ferme (Annuler)")
	assert_true(d2.get_ok_button().has_focus(), "Entrée : Enregistrer (bouton choisi)")
	_press(d2, "cancel")
	await wait_frames(1)
	await _free(ed)


func test_choices_save_discard_cancel() -> void:
	var dir := _saved("choix")
	var other := _saved("suivante")
	var ed := await _editor()
	ed.open_dir(dir)
	ed.add_object(ROOM, 0)
	assert_true(ed.write_recovery(), "copie de récupération")
	var done := {"n": 0}
	var proceed := func(): done.n += 1
	# Annuler : rien.
	_press(ed.confirm_unsaved("x", proceed), "cancel")
	await wait_frames(1)
	assert_eq(done.n, 0, "Annuler : l'action n'a pas lieu")
	# Enregistrer : la carte est écrite, puis l'action a lieu.
	_press(ed.confirm_unsaved("x", proceed), "save")
	await wait_frames(1)
	assert_eq(done.n, 1, "Enregistrer : l'action a lieu")
	assert_true(FileAccess.get_file_as_string(dir.path_join("pieces.json")).contains("contour"), "carte enregistrée")
	assert_false(ed.dirty)
	assert_true(ed.confirm_unsaved("x", proceed) == null and done.n == 2, "rien à enregistrer : pas de boîte, l'action a lieu")
	# Quitter sans enregistrer : action, carte non écrite, copie effacée.
	ed.add_object({"contour": [[12, 2], [18, 2], [18, 8], [12, 8]]}, 0)
	ed.write_recovery()
	var on_disk := _files(dir)
	_press(ed.confirm_unsaved("x", func(): ed.open_dir(other)), "discard")
	await wait_frames(1)
	assert_eq(ed.map_dir, other, "Quitter sans enregistrer : l'autre carte est ouverte")
	assert_eq(_files(dir), on_disk, "rien d'écrit")
	assert_false(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie de récupération effacée")
	# (Enregistrement en échec : `proceed` seulement si save() réussit ; non
	# simulé ici, l'échec d'écriture affiche une erreur du moteur que
	# tools/check.sh compte comme un échec.)
	# Carte jamais enregistrée : Enregistrer sous, et l'action n'a pas lieu.
	ed.new_map(true)
	ed.add_object(ROOM, 0)
	_press(ed.confirm_unsaved("x", proceed), "save")
	await wait_frames(1)
	assert_eq(done.n, 2, "jamais enregistrée : l'action n'a pas lieu")
	var save_as: Array = ed.get_children().filter(func(c): return c is ConfirmationDialog and c.title == Lang.t("Enregistrer sous", "Save as"))
	assert_eq(save_as.size(), 1, "Enregistrer sous ouvert")
	assert_false(EditorMap.is_map_dir(EditorMap.map_dir("nouvelle_carte")), "rien d'écrit sans nom")
	for c in save_as:
		c.queue_free()
	await _free(ed)


# ------------------------------------------------------------------ récupération après un plantage

func test_recovery_after_a_crash() -> void:
	var dir := _saved("plantee")
	var ed := await _editor()
	ed.open_dir(dir)
	ed.add_object(ROOM, 0)
	ed.write_recovery()
	var on_disk := _files(dir)
	# « Plantage » : l'éditeur disparaît sans rien demander ni effacer.
	ed.free()
	assert_true(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie restée")
	var ed2 := await _editor()
	var d: ConfirmationDialog = ed2.get_node_or_null("RecoveryDialog")
	assert_true(d != null and d.visible, "récupération proposée au lancement")
	if d == null:
		await _free(ed2)
		return
	assert_true(d.dialog_text.contains("PLANTEE"), "nom de la carte : %s" % d.dialog_text)
	assert_true(d.dialog_text.contains(str(Time.get_date_dict_from_system().year)), "date de la copie")
	assert_eq(d.get_ok_button().text, Lang.t("Récupérer", "Recover"))
	assert_true(d.find_children("Ignore", "Button", true, false).size() == 1, "bouton Ignorer")
	assert_false(d.get_cancel_button().visible, "Échap / croix : jamais « Ignorer »")
	# Pendant la question, la copie n'est ni écrasée ni effacée.
	ed2.add_object(ROOM, 0)
	assert_false(ed2.write_recovery(), "copie en attente : pas d'écriture")
	d.get_ok_button().pressed.emit()
	await wait_frames(2)
	assert_eq(ed2.map_dir, dir, "récupérée dans son dossier d'origine")
	assert_eq(ed2.doc.pieces.size(), 1, "travail non enregistré retrouvé")
	assert_true(ed2.dirty and _star(ed2), "récupérée : à enregistrer")
	assert_eq(_files(dir), on_disk, "la carte n'est pas écrite par la récupération")
	assert_true(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie gardée jusqu'à l'enregistrement")
	assert_true(ed2.save())
	assert_false(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "enregistrée : copie effacée")
	await _free(ed2)


func test_recovery_ignored_or_closed() -> void:
	var dir := _saved("ignoree")
	# Ancienne sauvegarde automatique (versions d'avant) : proposée elle aussi.
	var m := EditorMap.load_dir(dir)
	m.pieces.append({"id": "p1", "etage": 0, "contour": [[2, 2], [10, 2], [10, 8], [2, 8]], "zone": "z1"})
	assert_eq(m.save_dir(MapUnsaved.legacy_dir()), OK)
	var f := FileAccess.open(MapUnsaved.legacy_dir().path_join("meta.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"source": dir, "name": "IGNOREE", "time": int(Time.get_unix_time_from_system())}))
	f.close()
	var ed := await _editor()
	ed.open_dir(dir)   # carte récente (comme au lancement)
	var d: ConfirmationDialog = ed.get_node_or_null("RecoveryDialog")
	assert_true(d != null, "ancienne copie proposée")
	if d != null:
		d.custom_action.emit(&"ignore")
		await wait_frames(1)
	assert_false(EditorMap.is_map_dir(MapUnsaved.legacy_dir()) or EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "Ignorer : copie effacée")
	assert_eq(ed.doc.pieces.size(), 0, "carte du disque")
	await _free(ed)
	# Fermée par Échap ou la croix : rien n'est perdu (récupérée).
	assert_eq(MapUnsaved.write_recovery(m, dir, false), OK)
	var ed2 := await _editor()
	var d2: ConfirmationDialog = ed2.get_node_or_null("RecoveryDialog")
	assert_true(d2 != null)
	if d2 != null:
		d2.canceled.emit()
		await wait_frames(1)
	assert_eq(ed2.doc.pieces.size(), 1, "Échap : copie récupérée, jamais effacée")
	# Quitter sans enregistrer : la copie part.
	_press(ed2.confirm_unsaved("x", func(): pass), "discard")
	await wait_frames(1)
	assert_false(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "Quitter sans enregistrer : copie effacée")
	await _free(ed2)
	# Sortie sans modification : aucune copie à proposer ensuite.
	var ed3 := await _editor()
	assert_true(ed3.get_node_or_null("RecoveryDialog") == null, "rien à récupérer")
	await _free(ed3)


# ------------------------------------------------------------------ TESTER en solo

func test_play_test_keeps_the_session_and_does_not_save() -> void:
	var dir := _saved("testee")
	var ed := await _editor()
	ed.open_dir(dir)
	ed.add_object(ROOM, 0)
	ed.collab.submit_ops(_caisse("c1"), "caisse")
	var on_disk := _files(dir)
	var c := ed.collab
	# Ce que fait TESTER au lancement de la partie (sans la lancer ici).
	ed._keep_for_test()
	assert_true(c.get_parent() == null, "session sortie de l'éditeur")
	ed.queue_free()
	await wait_frames(1)
	var ed2 := await _editor()
	assert_true(ed2.collab == c and c.get_parent() == ed2, "session reprise au retour")
	assert_eq(ed2.map_dir, dir, "même carte")
	assert_eq(ed2.doc.pieces.size(), 1, "modifications gardées")
	assert_true(ed2.dirty and _star(ed2), "toujours à enregistrer")
	assert_eq(c.history.undo_count(c.my_id), 2, "historique d'annulation intact")
	assert_eq(_files(dir), on_disk, "TESTER n'a rien écrit dans la carte")
	ed2.undo()
	ed2.undo()
	assert_false(ed2.dirty, "annulé jusqu'à l'état enregistré : plus d'étoile")
	await _free(ed2)


# ------------------------------------------------------------------ collaboration

func test_host_saves_guest_has_nothing_to_confirm() -> void:
	var dir := _saved("partagee")
	var ed := await _editor()
	ed.open_dir(dir)
	assert_eq(ed.collab.host(_port(0), "Alice"), OK, "hôte à l'écoute")
	var g := MapCollab.new(EditorMap.blank())
	host.add_child(g)
	g.join("127.0.0.1", _port(0), ed.collab.session_code, "Bob")
	assert_true(await _until(func(): return g.role == MapCollab.Role.GUEST and not g._joining), "invité accueilli")
	var on_disk := _files(dir)
	# Changement de l'invité : l'hôte voit l'étoile, rien n'est écrit.
	g.submit_ops(_caisse("de_bob"), "caisse")
	assert_true(await _until(func(): return not ed.doc.find("de_bob").is_empty()), "changement de l'invité reçu")
	assert_true(ed.dirty and _star(ed) and ed.needs_save_prompt(), "hôte : carte modifiée, à confirmer")
	assert_eq(_files(dir), on_disk, "rien d'écrit chez l'hôte")
	assert_true(ed.save(), "l'hôte enregistre")
	assert_false(ed.dirty)
	g.leave()
	g.queue_free()
	# Éditeur invité : la carte de l'hôte n'est pas la sienne.
	var h := MapCollab.new(EditorMap.blank("chez_alice", "ALICE", "ALICE"))
	host.add_child(h)
	assert_eq(h.host(_port(1), "Alice"), OK)
	var ed2 := await _editor()
	ed2.new_map(true)
	ed2.add_object(ROOM, 0)
	# Rejoindre une session : la carte d'ici serait remplacée : confirmation.
	ed2.collab_ui.join_dialog()
	await wait_frames(1)
	assert_true(ed2._unsaved_dialog != null, "rejoindre : confirmation d'abord")
	_press(ed2._unsaved_dialog, "discard")
	await wait_frames(1)
	var join_d: Array = ed2.collab_ui.get_children().filter(func(c): return c is ConfirmationDialog) + ed2.get_children().filter(func(c): return c is ConfirmationDialog and c.visible)
	assert_true(join_d.size() >= 1, "puis la fenêtre Rejoindre")
	for jd in join_d:
		jd.queue_free()
	ed2.collab.join("127.0.0.1", _port(1), h.session_code, "Bob")
	assert_true(await _until(func(): return ed2.collab.role == MapCollab.Role.GUEST and not ed2.collab._joining), "invité")
	assert_eq(ed2.doc.id(), "chez_alice")
	assert_false(ed2.dirty, "carte de l'hôte reçue : pas d'étoile")
	h.submit_ops(_caisse("d_alice"), "caisse")
	assert_true(await _until(func(): return not ed2.doc.find("d_alice").is_empty()), "changement de l'hôte reçu")
	assert_true(ed2.dirty, "invité : la carte de la session a changé depuis l'enregistrement de l'hôte")
	assert_false(ed2.needs_save_prompt(), "invité : jamais de confirmation (pas sa carte)")
	var ran := {"ok": false}
	assert_true(ed2.confirm_unsaved("x", func(): ran.ok = true) == null and ran.ok, "invité : l'action a lieu sans boîte")
	assert_false(ed2.write_recovery(), "invité : pas de copie de récupération")
	assert_false(ed2.save(), "invité : n'écrit pas la carte de l'hôte")
	h.notify_saved()
	assert_true(await _until(func(): return not ed2.dirty), "l'hôte enregistre : plus d'étoile chez l'invité")
	# L'invité part : la copie gardée n'est pas « à lui » : rien à confirmer.
	h.submit_ops(_caisse("d_alice2", 16.0), "caisse")
	assert_true(await _until(func(): return not ed2.doc.find("d_alice2").is_empty()))
	ed2.collab.leave()
	await wait_frames(1)
	assert_false(ed2.dirty or ed2.needs_save_prompt(), "invité parti : rien à confirmer")
	assert_eq(ed2.map_dir, "", "pas de dossier")
	h.leave()
	h.queue_free()
	await _free(ed2)
	ed.collab.leave()
	await _free(ed)


# ------------------------------------------------------------------ revue : cas limites

func test_save_as_never_overwrites_silently() -> void:
	var taken := _saved("nouvelle_carte")
	var before := _files(taken)
	var ed := await _editor()
	ed.new_map(true)
	ed.add_object(ROOM, 0)
	# Nom proposé : libre (le dossier « nouvelle_carte » existe déjà).
	var d := ed.save_as_dialog()
	var name_edit: LineEdit = d.get_meta("name")
	assert_eq(name_edit.text, "nouvelle_carte_2", "nom libre proposé")
	d.hide()
	d.queue_free()
	# Nom d'une carte existante : confirmation d'écrasement, rien d'écrit avant.
	var c := ed.request_save_as("nouvelle_carte")
	assert_true(c != null and c.dialog_text.contains("nouvelle_carte"), "« existe déjà. La remplacer ? »")
	assert_eq(_files(taken), before, "rien d'écrasé sans réponse")
	assert_true(ed.dirty)
	c.get_cancel_button().pressed.emit()
	await wait_frames(1)
	assert_eq(_files(taken), before, "Non : rien d'écrasé")
	c = ed.request_save_as("nouvelle_carte")
	c.get_ok_button().pressed.emit()
	await wait_frames(1)
	assert_false(ed.dirty, "Oui : remplacée")
	assert_true(FileAccess.get_file_as_string(taken.path_join("pieces.json")).contains("contour"))
	# Sa propre carte : ni question, ni autre nom proposé.
	var d2 := ed.save_as_dialog()
	assert_eq((d2.get_meta("name") as LineEdit).text, "nouvelle_carte", "sa propre carte : son nom")
	d2.hide()
	d2.queue_free()
	ed.add_object({"contour": [[12, 2], [18, 2], [18, 8], [12, 8]]}, 0)
	assert_true(ed.request_save_as("nouvelle_carte") == null and not ed.dirty, "sa propre carte : enregistrée sans question")
	await _free(ed)


func test_failed_join_keeps_the_own_map() -> void:
	var dir := _saved("la_mienne")
	var ed := await _editor()
	ed.open_dir(dir)
	ed.add_object(ROOM, 0)
	assert_true(ed.write_recovery())
	# Personne n'écoute sur ce port : tentative ratée (GUEST puis seul).
	ed.collab.join("127.0.0.1", _port(5), "ABCD", "Bob")
	assert_true(await _until(func(): return ed.collab.role == MapCollab.Role.SOLO, 8.0), "tentative échouée")
	await wait_frames(1)
	assert_eq(ed.map_dir, dir, "dossier gardé")
	assert_true(ed.dirty and ed.needs_save_prompt(), "toujours à enregistrer, avec confirmation")
	assert_true(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "copie de récupération gardée")
	await _free(ed)


func test_stale_recovery_dropped() -> void:
	var dir := _saved("perimee")
	var other := _saved("autre")
	var ed := await _editor()
	ed.open_dir(dir)
	ed.add_object(ROOM, 0)
	assert_true(ed.write_recovery())
	ed.undo()
	assert_false(ed.dirty)
	assert_false(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "annulé jusqu'à l'état enregistré : copie effacée")
	ed.redo()
	assert_true(ed.write_recovery())
	assert_true(ed.save())
	ed.add_object({"contour": [[12, 2], [18, 2], [18, 8], [12, 8]]}, 0)
	ed.write_recovery()
	_press(ed.confirm_unsaved("x", func(): ed.open_dir(other)), "discard")
	await wait_frames(1)
	assert_false(EditorMap.is_map_dir(MapUnsaved.recovery_dir()), "autre carte ouverte : copie effacée")
	await _free(ed)


func test_reopened_prompt_runs_the_latest_action() -> void:
	var dir := _saved("rappel")
	var ed := await _editor()
	ed.open_dir(dir)
	ed.add_object(ROOM, 0)
	var ran := []
	var d1 := ed.confirm_unsaved("ouvrir", func(): ran.append("ouvrir"))
	var d2 := ed.confirm_unsaved("quitter", func(): ran.append("quitter"))
	assert_true(d1 == d2, "une seule boîte")
	assert_true(d2.dialog_text.contains("quitter"), "texte de la dernière action")
	_press(d2, "discard")
	await wait_frames(1)
	assert_eq(ran, ["quitter"], "Quitter sans enregistrer : la dernière action demandée")
	await _free(ed)


func test_signature_and_recovery_source_checks() -> void:
	var a := EditorMap.blank("sig")
	var b := EditorMap.blank("sig")
	a.models["m1"] = "AAAA"
	b.models["m1"] = "BBBB"
	assert_true(MapUnsaved.signature(a) != MapUnsaved.signature(b), "modèles de même taille, contenus différents : empreintes différentes")
	b.models["m1"] = "AAAA"
	assert_eq(MapUnsaved.signature(a), MapUnsaved.signature(b))
	assert_true(MapUnsaved.source_ok(EditorMap.map_dir("ok")))
	for bad in ["", "C:/Windows/System32", EditorMap.maps_root(), EditorMap.maps_root().path_join("_tester"),
			EditorMap.maps_root().path_join("ok/sous"), EditorMap.maps_root().path_join("../dehors"), EditorMap.maps_root().path_join("Pas Bon")]:
		assert_false(MapUnsaved.source_ok(bad), "dossier d'origine refusé : %s" % bad)
	# Copie dont le meta.json pointe hors du dossier des cartes : récupérée
	# non enregistrée (jamais d'écriture ailleurs).
	var outside := ProjectSettings.globalize_path(TMP + "/ailleurs")
	var m := EditorMap.blank("piege", "PIÈGE", "TRAP")
	assert_eq(MapUnsaved.write_recovery(m, outside, false), OK)
	var ed := await _editor()
	var d: ConfirmationDialog = ed.get_node_or_null("RecoveryDialog")
	assert_true(d != null)
	if d != null:
		d.get_ok_button().pressed.emit()
		await wait_frames(1)
	assert_eq(ed.map_dir, "", "dossier d'origine refusé : non enregistrée")
	assert_true(ed.dirty, "à enregistrer")
	_press(ed.confirm_unsaved("x", func(): pass), "discard")
	await _free(ed)
