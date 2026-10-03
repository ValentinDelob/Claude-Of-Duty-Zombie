extends AutotestScenario
## @rendu : captures des dispositions (docs/EDITOR_VIEWS.md, étape 5 ;
## écrans 1, 3 et 4 de la maquette) : DRAFT ARENA, quatre vues (Dessus, 3D
## intégrée, Avant, Droite) la passerelle choisie ; « 3 : 1 + 2 » avec la
## coupe autour de la salle des machines ; menu Disposition ouvert sur
## « 2 côte à côte » ; puis quatre vues à 60, 80 et 150 % d'interface
## (barre du haut, en-têtes, barre rapide ancrée, ViewCube à l'échelle).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec sh tools/scenario.sh map_views_layout.
## Captures : tests/_out/shots/map_views_layout_*.png.

var ed: MapEditor


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	_clean(EditorMap.maps_root())
	Settings.editor_ui_scale = 1.0
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.open_example("draft_arena")
	await frames(3)
	var lay := ed.views
	# Fenêtre de test sans focus : l'aperçu 3D rend quand même.
	ed.preview.pause_unfocused = false
	# Écran 1 : quatre vues, la passerelle choisie.
	lay.set_layout("4")
	await frames(3)
	ed.select("p5")
	lay.frame_all()
	await seconds(1.5)
	at.check(lay.panes[1].view is MapView3D and ed.preview.pane_host != null, "3D intégrée dans la fenêtre en haut à droite")
	# Barre du haut sur une ligne à 100 % (maquette) ; zoom de chaque vue
	# qui cadre la carte (pas celui de la vue Dessus en quart d'écran).
	var bh := (ed.top_bar.get_child(0) as Control).size.y
	at.check(ed.top_bar.size.y < bh * 1.5, "barre du haut sur une ligne (%d px)" % roundi(ed.top_bar.size.y))
	at.check(not ed.preview.visible and not ed.preview.detached, "aperçu flottant caché (3D dans la disposition)")
	await at.screenshot("quatre_vues")
	# Écran 3 : 3 (1 + 2), Avant à gauche, coupe autour de la salle des machines.
	lay.set_layout("3a")
	lay.set_pane_plane(lay.panes[0], "avant")
	lay.set_pane_plane(lay.panes[1], "dessus")
	await frames(2)
	ed.select("p1")
	(lay.panes[0].view as MapElevation).cut_around_selection()
	lay.frame_all()
	await frames(3)
	await at.screenshot("trois_vues_coupe")
	# Écran 4 : menu Disposition sur « 2 côte à côte ».
	lay.set_layout("2h")
	await frames(2)
	ed.select("")
	lay.frame_all()
	ed.layout_button.pressed.emit()
	await frames(3)
	at.check(lay.menu_open(), "menu Disposition ouvert")
	await at.screenshot("menu")
	lay._menu_ui.hide()
	# Quatre vues à 60, 80 et 150 %.
	lay.set_layout("4")
	ed.select("p5")
	for f in [0.6, 0.8, 1.5]:
		Settings.editor_ui_scale = f
		await frames(3)
		lay.frame_all()
		await seconds(0.5)
		var ok := true
		for pn in lay.panes:
			if pn.size.x < 50.0 or pn.size.y < 50.0:
				ok = false
		at.check(ok, "%d %% : quatre fenêtres visibles" % roundi(f * 100.0))
		at.check(Rect2(lay.global_position, lay.size).grow(0.5).encloses(ed.hotbar_ui.get_global_rect()), "%d %% : barre rapide dans la zone des vues" % roundi(f * 100.0))
		await at.screenshot("quatre_vues_%d" % roundi(f * 100.0))
	Settings.editor_ui_scale = Settings.EDITOR_UI_SCALE_DEFAULT
	lay.set_layout("2v")
	_clean(EditorMap.maps_root())


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
