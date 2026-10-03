extends AutotestScenario
## @rendu : boîtes de l'enregistrement explicite de l'éditeur de cartes
## (MapUnsaved, docs/MAP_AUTHORING.md § 6), en français puis en anglais :
## « Modifications non enregistrées » (Enregistrer / Quitter sans enregistrer /
## Annuler) au retour au menu avec une carte modifiée, puis la proposition de
## récupération après un « plantage » (Récupérer / Ignorer). Dossier des
## cartes de test (jamais celles du joueur). Captures :
## tests/_out/shots/map_unsaved_look_*.png.

var ed: MapEditor


func run() -> void:
	timeout_sec = 60
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var root := EditorMap.maps_root()
	_clean(root)
	var dir := EditorMap.map_dir("entrepot")
	EditorMap.blank("entrepot", "ENTREPÔT", "WAREHOUSE").save_dir(dir)
	var lang0 := String(Settings.language)
	for lang in ["fr", "en"]:
		Settings.language = lang
		tree().change_scene_to_file(MapEditor.SCENE)
		if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
			break
		ed = tree().current_scene
		await frames(3)
		ed.open_dir(dir)
		ed.add_object({"contour": [[2, 2], [12, 2], [12, 9], [2, 9]]}, 0)
		await frames(2)
		at.check(ed.title_label.text.contains(" *"), "étoile au titre (%s)" % ed.title_label.text)
		var d := ed.quit_to_menu()
		at.check(d != null and d.visible, "retour au menu : confirmation (%s)" % lang)
		await seconds(0.3)
		await at.screenshot("confirmation_" + lang)
		if d != null:
			d.get_cancel_button().pressed.emit()
		await frames(2)
		at.check(tree().current_scene == ed, "Annuler : on reste dans l'éditeur")
		# « Plantage » : copie de récupération, éditeur remplacé sans rien demander.
		ed.write_recovery()
		tree().change_scene_to_file(MapEditor.SCENE)
		if not await until(func(): return tree().current_scene is MapEditor and tree().current_scene != ed, 6.0, "éditeur relancé"):
			break
		ed = tree().current_scene
		await frames(3)
		var r: ConfirmationDialog = ed.get_node_or_null("RecoveryDialog")
		at.check(r != null and r.visible, "récupération proposée (%s)" % lang)
		await seconds(0.3)
		await at.screenshot("recuperation_" + lang)
		if r != null:
			r.custom_action.emit(&"ignore")
		await frames(2)
	Settings.language = lang0
	_clean(root)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
