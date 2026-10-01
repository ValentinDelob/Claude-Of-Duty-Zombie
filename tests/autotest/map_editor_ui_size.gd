extends AutotestScenario
## @rendu : a besoin du rendu (captures de l'éditeur à plusieurs tailles, fenêtre hors écran).
## TAILLE DE L'INTERFACE DE L'ÉDITEUR (OPTIONS > JEU > INTERFACE, Ctrl + /
## Ctrl - / Ctrl 0) : DRAFT ARENA ouverte, liste des objets dépliée, à 80 %
## (défaut), 60 % et 150 % : barre du haut dans la largeur (sur deux lignes
## au besoin) sans contrôles qui se chevauchent, liste, plan et panneaux côte
## à côte dans la fenêtre, barre rapide, inventaire et aide « ? » dans la vue
## ou la fenêtre ; pastilles des participants de la collaboration dans la
## barre ; polices et panneaux à la bonne taille ; le zoom du plan ne
## change pas et le plan ne bouge pas à l'écran. Puis le bouton ⚙ : options
## ouvertes sur la taille de l'interface, ► l'agrandit en direct derrière le
## voile, Échap : retour à l'éditeur (les touches ne vont pas à l'éditeur).
## Captures : tests/_out/shots/map_editor_ui_size_*.png.

var ed: MapEditor
var cv: MapCanvas


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	_clean(EditorMap.maps_root())
	at.check(is_equal_approx(Settings.editor_ui_scale, Settings.EDITOR_UI_SCALE_DEFAULT), "taille par défaut : %d %%" % roundi(Settings.editor_ui_scale * 100.0))
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	await frames(3)
	ed.open_example("draft_arena")
	await frames(3)
	ed.object_list.set_expanded(true)
	cv.frame_all()
	ed.select(String(ed.doc.pieces[0].id))
	# Pastilles de la collaboration (deux invités, dont un sur un autre
	# étage, et Claude) : la barre passe à la ligne sans chevauchement.
	ed.collab.peers["2"] = {"id": "2", "name": "Bérénice", "color": MapCollab.COLORS[1], "kind": "human", "presence": {"cursor": [4.0, 4.0], "floor": 1}}
	ed.collab.peers["3"] = {"id": "3", "name": "Bob", "color": MapCollab.COLORS[2], "kind": "human", "presence": {}}
	ed.collab.peers["1:claude"] = {"id": "1:claude", "name": "Claude", "color": MapCollab.AGENT_COLOR, "kind": "agent", "presence": {}}
	ed.collab_ui.refresh()
	await frames(4)
	at.check(ed.collab_ui.pills.size() == 4, "quatre pastilles de participants (%d)" % ed.collab_ui.pills.size())
	var zoom0 := cv.zoom
	var spot := Vector2(10, 8)
	var screen0 := cv.global_position + cv.to_px(spot)

	for f in [0.8, 0.6, 1.5]:
		# Changement en direct, et vite (jamais toute l'interface prévenue
		# en boucle : un style réécrit prévient tous ceux qui l'utilisent).
		var t0 := Time.get_ticks_msec()
		Settings.editor_ui_scale = f
		await frames(2)
		var ms := Time.get_ticks_msec() - t0
		print("[ui] %d %% appliqué en %d ms" % [roundi(f * 100.0), ms])
		at.check(ms < 1500, "%d %% : appliqué en %d ms" % [roundi(f * 100.0), ms])
		await frames(2)
		var tag := "%d" % roundi(f * 100.0)
		at.check(is_equal_approx(ed.ui_scale, f), "%s %% : appliqué en direct" % tag)
		at.check(ed.theme.default_font_size == EditorUi.fs(EditorUi.BODY_FONT, f), "%s %% : texte de %d px" % [tag, ed.theme.default_font_size])
		var pw := ed.side_width(MapEditor.PANEL_W)
		at.check(absf(ed.panels.size.x - pw) < 2.0, "%s %% : panneaux de %d px (%d attendus)" % [tag, roundi(ed.panels.size.x), roundi(pw)])
		at.check(is_equal_approx(cv.zoom, zoom0), "%s %% : zoom du plan inchangé (%.1f)" % [tag, cv.zoom])
		var screen := cv.global_position + cv.to_px(spot)
		at.check(screen.distance_to(screen0) < 1.5, "%s %% : le plan ne bouge pas à l'écran (%.1f px)" % [tag, screen.distance_to(screen0)])
		_check_layout(tag)
		await at.screenshot("editeur_" + tag)
		# Inventaire et aide « ? » dans la vue / la fenêtre.
		ed.toggle_inventory()
		await frames(3)
		at.check(_inside(ed.inventory.get_global_rect(), cv.get_global_rect()), "%s %% : inventaire dans la vue %s / %s" % [tag, ed.inventory.get_global_rect(), cv.get_global_rect()])
		if f > 1.0:
			await at.screenshot("inventaire_" + tag)
		ed.toggle_inventory()
		ed._show_help()
		await frames(3)
		var dr := Rect2(Vector2(ed._dialog.position), Vector2(ed._dialog.size))
		at.check(_inside(dr, ed.get_viewport_rect()), "%s %% : aide « ? » dans la fenêtre %s" % [tag, dr])
		if f > 1.0:
			await at.screenshot("aide_" + tag)
		ed._dialog.hide()
		await frames(1)

	# Ctrl + / Ctrl - / Ctrl 0 : même réglage, bornes respectées.
	await ctrl_key(KEY_0)
	at.check(is_equal_approx(Settings.editor_ui_scale, 0.8) and is_equal_approx(ed.ui_scale, 0.8), "Ctrl 0 : taille par défaut (%.2f)" % Settings.editor_ui_scale)
	await ctrl_key(KEY_EQUAL)
	at.check(is_equal_approx(Settings.editor_ui_scale, 0.85), "Ctrl + : 85 %% (%.2f)" % Settings.editor_ui_scale)
	await ctrl_key(KEY_MINUS)
	await ctrl_key(KEY_KP_SUBTRACT)
	at.check(is_equal_approx(Settings.editor_ui_scale, 0.75), "Ctrl - ×2 : 75 %% (%.2f)" % Settings.editor_ui_scale)
	for i in 8:
		await ctrl_key(KEY_MINUS)
	at.check(is_equal_approx(Settings.editor_ui_scale, Settings.EDITOR_UI_SCALE_RANGE.x), "Ctrl - : jamais sous 60 %% (%.2f)" % Settings.editor_ui_scale)
	await ctrl_key(KEY_0)
	at.check(is_equal_approx(cv.zoom, zoom0), "raccourcis : zoom du plan inchangé")

	# Bouton ⚙ : options par-dessus l'éditeur, sur la taille de l'interface.
	var b := ed.top_bar.get_node("OptionsButton") as Button
	b.pressed.emit()
	await frames(4)
	at.check(ed.options_open() and ed.options.current != null, "⚙ : options ouvertes dans l'éditeur")
	if not ed.options_open():
		return
	var opt: Node = ed.options.current
	at.check(opt.tab == "game" and opt.rows.has("editor_ui_scale"), "onglet JEU, ligne TAILLE DE L'INTERFACE DE L'ÉDITEUR")
	await frames(2)
	var row: MenuOptionRow = opt.rows.editor_ui_scale
	at.check(row.has_focus(), "focus sur la taille de l'interface")
	at.check(EditorUi.skipped(ed.options, ed),
		"options hors de la mise à l'échelle de l'éditeur")
	await key(KEY_RIGHT)
	await key(KEY_RIGHT)
	at.check(is_equal_approx(Settings.editor_ui_scale, 0.9) and is_equal_approx(ed.ui_scale, 0.9), "► ► : 90 %%, appliqué derrière les options (%.2f)" % ed.ui_scale)
	await seconds(0.3)
	await at.screenshot("options")
	var sel0 := ed.selected
	await key(KEY_ESCAPE)
	await frames(3)
	at.check(not ed.options_open(), "Échap : retour à l'éditeur")
	at.check(ed.selected == sel0, "Échap des options : la sélection de l'éditeur reste")
	_check_layout("90")
	Settings.editor_ui_scale = Settings.EDITOR_UI_SCALE_DEFAULT
	await frames(3)
	await at.screenshot("defaut")
	_clean(EditorMap.maps_root())


## Aucun contrôle coupé ni superposé : barre du haut, liste, plan, panneaux,
## barre rapide.
func _check_layout(tag: String) -> void:
	var vp := ed.get_viewport_rect()
	var bar := ed.top_bar
	at.check(bar.get_global_rect().end.x <= vp.end.x + 0.5, "%s %% : barre du haut dans la largeur (%d px)" % [tag, roundi(bar.get_global_rect().end.x)])
	var rects := []
	for c in bar.get_children():
		if c is Control and (c as Control).visible:
			var r := (c as Control).get_global_rect()
			at.check(r.position.x >= -0.5 and r.end.x <= vp.end.x + 0.5 and r.size.x >= 1.0, "%s %% : %s dans la barre (%s)" % [tag, c.name, r])
			rects.append([c.name, r])
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i][1] as Rect2).grow(-1.0).intersects((rects[j][1] as Rect2).grow(-1.0)):
				overlaps += 1
				print("[ui] chevauchement %s / %s" % [rects[i][0], rects[j][0]])
	at.check(overlaps == 0, "%s %% : aucun contrôle de la barre ne se chevauche" % tag)
	# Propriétés : aucune ligne plus large que le panneau (pas de défilement horizontal).
	var props := ed.panels._props
	at.check(props.get_combined_minimum_size().x <= (props.get_parent() as Control).size.x + 0.5,
		"%s %% : les propriétés tiennent dans la largeur du panneau (%d / %d px)" % [tag, roundi(props.get_combined_minimum_size().x), roundi((props.get_parent() as Control).size.x)])
	var lr := ed.object_list.get_global_rect()
	var cr := cv.get_global_rect()
	var pr := ed.panels.get_global_rect()
	at.check(lr.end.x <= cr.position.x + 0.5 and cr.end.x <= pr.position.x + 0.5 and pr.end.x <= vp.end.x + 0.5 and cr.size.x > 150.0,
		"%s %% : liste | plan | panneaux côte à côte (%d, %d, %d px)" % [tag, roundi(lr.size.x), roundi(cr.size.x), roundi(pr.size.x)])
	at.check(pr.end.y <= vp.end.y + 0.5 and lr.end.y <= vp.end.y + 0.5, "%s %% : panneaux dans la hauteur" % tag)
	at.check(_inside(ed.hotbar_ui.get_global_rect(), cr), "%s %% : barre rapide dans la vue (%s)" % [tag, ed.hotbar_ui.get_global_rect()])
	at.check(bar.get_global_rect().end.y <= cr.position.y + 0.5, "%s %% : la barre du haut ne recouvre pas le plan" % tag)


func _inside(r: Rect2, outer: Rect2) -> bool:
	return outer.grow(0.5).encloses(r)


func ctrl_key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.ctrl_pressed = true
	e.pressed = true
	ed._input(e)
	await frames(3)


## Touche envoyée à toute la fenêtre (comme au clavier).
func key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
