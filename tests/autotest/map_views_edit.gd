extends AutotestScenario
## @rendu : captures de l'édition dans les élévations (docs/EDITOR_VIEWS.md,
## étape 3 ; écran 2 de la maquette) : DRAFT ARENA à 100 % d'interface, une
## torche murale tirée de 1,80 m vers le haut par sa flèche Z (cotes, écart,
## aimant du linteau, fantôme, champ Z du panneau), puis 2,40 m tapés (Tab) ;
## plafond de la salle des machines agrandi par le losange (règle vérifiée) ;
## étiquette du niveau 1 glissée ; champs X, Y, Z du panneau.
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec sh tools/scenario.sh map_views_edit.
## Captures : tests/_out/shots/map_views_edit_*.png.

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
	await frames(4)
	ed.canvas.fine_step = 0.1
	ed.canvas.set_snap_mode("fine")
	ed.push_undo()
	ed.doc.objets.append({"id": "fx1", "type": "effet", "effet": "torche", "altitude": 0, "position": [9.5, 4.5], "mur": "n", "hauteur": 1.8})
	ed.changed()
	ed.select("fx1")
	var low: MapViewPane = ed.views.panes[1]
	var av: MapElevation = low.view
	_frame(ed.canvas, 22.0, Vector2(12, 10.2))
	_frame(av, 22.0, Vector2(12, -3.3))
	av.set_cut([4.5, 17.0], "selection", "Entrepôt")
	ed.views.set_active_pane(low)
	await frames(3)
	# Flèche Z de la torche : glissée vers le haut (aimant du linteau, 2,35 m).
	var o := av.tools.anchor_px(av.projected_of("fx1"))
	var a := o + Vector2(0, -EditorUi.px(35))
	_motion(av, a)
	_button(av, a, true)
	for i in 8:
		_motion(av, a + Vector2(0, -0.55 * 22.0 * (i + 1) / 8.0))
		await frames(1)
	at.check(not av.tools.magnet.is_empty(), "aimant vertical actif : %s" % av.tools.magnet.get("label", "aucun"))
	await at.screenshot("torche_aimant")
	# Valeur tapée : +0,60 (2,40 m).
	for code in [KEY_TAB, KEY_0, KEY_PERIOD, KEY_6]:
		var k := InputEventKey.new()
		k.keycode = code
		k.pressed = true
		k.unicode = {KEY_0: 48, KEY_PERIOD: 46, KEY_6: 54}.get(code, 0)
		ed.views.handle_drag_key(k)
	await frames(2)
	await at.screenshot("torche_valeur")
	_button(av, a, false)
	await frames(2)
	at.check(absf(MapCatalog.effect_height(ed.doc.find("fx1")) - 2.4) < 0.001, "torche à 2,40 m (%.2f)" % MapCatalog.effect_height(ed.doc.find("fx1")))
	await at.screenshot("torche_posee")
	# Plafond de la salle des machines : losange tiré de 1 m.
	av.set_cut([21.5, 33.0], "selection", "Salle des machines")
	ed.select("p1")
	await frames(2)
	var top: Array = av.tools.handles(av.projected_of("p1")).filter(func(h): return h.id == "top")
	if top.is_empty():
		at.fail("pas de losange de plafond")
		return
	var t: Vector2 = top[0].p
	_motion(av, t)
	_button(av, t, true)
	for i in 6:
		_motion(av, t + Vector2(0, -22.0 * (i + 1) / 6.0))
		await frames(1)
	await at.screenshot("plafond")
	_button(av, t + Vector2(0, -22.0), false)
	await frames(2)
	at.check(absf(float(ed.doc.find("p1").get("plafond", 3.2)) - 4.2) < 0.001, "plafond 4,20 m")
	Settings.editor_ui_scale = Settings.EDITOR_UI_SCALE_DEFAULT
	_clean(EditorMap.maps_root())


func _frame(v: MapView, z: float, c: Vector2) -> void:
	var r := v._ruler()
	v.zoom = z
	v.origin = Vector2(r + (v.size.x - r) * 0.5, r + (v.size.y - r) * 0.5) - c * z
	v.queue_redraw()


func _motion(v: Control, px: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = px
	v._gui_input(e)


func _button(v: Control, px: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = px
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	v._gui_input(e)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
