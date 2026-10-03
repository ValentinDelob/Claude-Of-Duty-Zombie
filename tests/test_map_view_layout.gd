extends TestCase
## Dispositions multi-fenêtres de l'éditeur de cartes (MapViewLayout,
## docs/EDITOR_VIEWS.md § 5) : six dispositions et leurs plans par défaut,
## tailles minimales des vues, mémorisation dans _editeur.cfg (disposition,
## plans, proportions, liaison, coupes, étages ; ni zoom ni centre), vues
## liées (zoom commun, centre commun sur l'axe partagé), agrandir la vue
## active (Ctrl+Espace), quatre vues (Ctrl+Alt+Q), 3D intégrée (une seule ;
## l'aperçu quitte son panneau flottant et y revient), coupe partagée,
## barre rapide ancrée, et sur une carte de 2000 objets en 4 vues : le
## mouvement de la souris ne redessine que la vue survolée.

const TMP := "res://tests/_out/test_map_view_layout"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")
	var cfg := EditorMap.maps_root().path_join("_editeur.cfg")
	if FileAccess.file_exists(cfg):
		DirAccess.remove_absolute(cfg)


func after_each() -> void:
	EditorMap.root_override = ""


func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed._reset(EditorMap.load_dir("res://assets/maps/draft_arena/"))
	await wait_frames(2)
	return ed


func _key(ed: MapEditor, code: Key, ctrl := false, alt := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.alt_pressed = alt
	ed._input(e)


func test_layouts_and_default_planes() -> void:
	var ed := await _editor()
	var lay := ed.views
	assert_eq(lay.layout_id, "2v", "premier lancement : 2 vues empilées")
	assert_eq([lay.panes[0].plane(), lay.panes[1].plane()], ["dessus", "avant"])
	for id in MapViewLayout.ORDER:
		lay.set_layout(id)
		await wait_frames(1)
		assert_eq(lay.pane_count(), (MapViewLayout.LAYOUTS[id] as Array).size(), "disposition %s" % id)
		var planes := lay.panes.map(func(p): return p.plane())
		assert_eq(planes, MapViewLayout.LAYOUTS[id], "plans par défaut de %s" % id)
		assert_eq(planes.filter(func(p): return p == "dessus").size(), 1, "%s : une seule vue Dessus" % id)
		assert_true(lay.docked() == (lay.pane_count() > 1), "barre rapide ancrée dès 2 vues")
		# Fenêtres côte à côte sans se chevaucher, dans la zone des vues.
		var area := lay.views_rect().grow(0.5)
		for i in lay.panes.size():
			var r := Rect2(lay.panes[i].position, lay.panes[i].size)
			assert_true(area.encloses(r), "%s : fenêtre %d dans la zone" % [id, i])
			for j in range(i + 1, lay.panes.size()):
				assert_false(r.grow(-1.0).intersects(Rect2(lay.panes[j].position, lay.panes[j].size).grow(-1.0)), "%s : %d et %d ne se chevauchent pas" % [id, i, j])
	# Ctrl+Alt+Q : quatre vues, dont la 3D.
	lay.set_layout("1")
	_key(ed, KEY_Q, true, true)
	await wait_frames(1)
	assert_eq(lay.layout_id, "4")
	assert_eq(lay.panes[1].plane(), "3d", "4 vues : la 3D en haut à droite")
	assert_true(ed.preview.pane_host != null and ed.preview.content.get_parent() == lay.panes[1].view, "l'aperçu est dans la fenêtre")
	assert_false(ed.preview.visible, "le panneau flottant est caché")
	lay.set_layout("2v")
	await wait_frames(1)
	assert_true(ed.preview.pane_host == null and ed.preview.content.get_parent().name == "Outer", "l'aperçu revient dans son panneau flottant")
	ed.queue_free()
	await wait_frames(1)


func test_minimum_view_size_and_equal_split() -> void:
	var ed := await _editor()
	var lay := ed.views
	lay.set_ratio("y", 0.02)
	var mn := minf(EditorUi.px(MapViewLayout.MIN_VIEW.y), floorf((lay.views_rect().size.y - MapViewLayout.SPLIT) * 0.5))
	assert_true(lay.panes[0].size.y >= mn - 0.5, "vue du haut : au moins %d px (%d)" % [mn, lay.panes[0].size.y])
	lay.set_ratio("y", 0.98)
	assert_true(lay.panes[1].size.y >= mn - 0.5, "vue du bas : au moins %d px" % mn)
	lay.set_ratio("y", 0.5)
	assert_near(lay.panes[0].size.y, lay.panes[1].size.y, 1.0, "partage égal")
	ed.queue_free()
	await wait_frames(1)


func test_layout_is_remembered_without_zoom() -> void:
	var ed := await _editor()
	var lay := ed.views
	lay.set_layout("3a")
	lay.set_ratio("x", 0.6)
	lay.set_linked(false)
	var ev: MapElevation = lay.panes[1].view
	ev.set_cut([4.5, 17.0], "perso")
	ev.floors_mode = MapElevation.Floors.ONLY
	lay.set_pane_plane(lay.panes[2], "gauche")
	lay.save_prefs()
	ed.queue_free()
	await wait_frames(1)
	var st: Dictionary = MapEditor.pref(MapViewLayout.PREF_KEY, {})
	assert_eq(String(st.disposition), "3a")
	assert_false(st.has("zoom") or st.has("origin"), "ni zoom ni centre mémorisés")
	var ed2 := await _editor()
	var l2 := ed2.views
	assert_eq(l2.layout_id, "3a", "disposition relue")
	assert_eq(l2.panes.map(func(p): return p.plane()), ["dessus", "avant", "gauche"], "plans relus")
	assert_near(l2.rx, 0.6, 0.001)
	assert_false(l2.linked, "liaison relue")
	var e2: MapElevation = l2.panes[1].view
	assert_eq(e2.coupe, [4.5, 17.0], "coupe relue")
	assert_eq(e2.floors_mode, MapElevation.Floors.ONLY, "étages relus")
	ed2.queue_free()
	await wait_frames(1)


func test_linked_views_share_zoom_and_axis() -> void:
	var ed := await _editor()
	var lay := ed.views
	lay.set_layout("3a")
	await wait_frames(2)
	var top := ed.canvas
	var av: MapElevation = lay.panes[1].view
	var dr: MapElevation = lay.panes[2].view
	assert_true(lay.linked, "vues liées par défaut")
	lay.set_active_pane(lay.panes[0])
	# Zoom (D7 révisé) : chaque vue garde son cadrage, un zoom s'applique aux
	# autres dans la même proportion.
	var zt0 := top.zoom
	var za0 := av.zoom
	var zd0 := dr.zoom
	top._zoom_at(top.size * 0.5, 1.5)
	top.origin.x += 40.0
	await wait_frames(2)
	var f := top.zoom / zt0
	assert_near(av.zoom, za0 * f, 0.0001, "zoom lié (même proportion)")
	assert_near(dr.zoom, zd0 * f, 0.0001)
	var cx := MapView.point_of("dessus", top.to_m(top.size * 0.5), 0.0).x
	assert_near(MapView.point_of("avant", av.to_m(av.size * 0.5), 0.0).x, cx, 0.01, "Dessus et Avant : même centre en X")
	var cy := MapView.point_of("dessus", top.to_m(top.size * 0.5), 0.0).y
	assert_near(MapView.point_of("droite", dr.to_m(dr.size * 0.5), 0.0).y, cy, 0.01, "Dessus et Droite : même centre en Y")
	# Avant bouge en Z : Droite suit (même Z), Dessus ne change pas en Y.
	lay.set_active_pane(lay.panes[1])
	av.origin.y += 60.0
	await wait_frames(2)
	assert_near(MapView.point_of("droite", dr.to_m(dr.size * 0.5), 0.0).z, MapView.point_of("avant", av.to_m(av.size * 0.5), 0.0).z, 0.01, "Avant et Droite : même centre en Z")
	assert_near(MapView.point_of("dessus", top.to_m(top.size * 0.5), 0.0).y, cy, 0.01)
	# Déliées : chacune libre.
	lay.set_linked(false)
	var z0 := av.zoom
	top._zoom_at(top.size * 0.5, 2.0)
	await wait_frames(2)
	assert_near(av.zoom, z0, 0.0001, "vues libres")
	ed.queue_free()
	await wait_frames(1)


func test_maximize_and_shared_cut() -> void:
	var ed := await _editor()
	var lay := ed.views
	lay.set_active_pane(lay.panes[1])
	_key(ed, KEY_SPACE, true)
	await wait_frames(1)
	assert_true(lay.maximized == lay.panes[1] and not lay.panes[0].visible, "Ctrl+Espace : la vue active agrandie")
	assert_true(lay.panes[1].size.is_equal_approx(lay.views_rect().size), "à toute la zone des vues")
	_key(ed, KEY_SPACE, true)
	await wait_frames(1)
	assert_true(lay.maximized == null and lay.panes[0].visible, "une seconde fois : retour")
	# Coupe partagée : Avant et Arrière (même direction).
	lay.set_layout("3a")
	lay.set_pane_plane(lay.panes[2], "arriere")
	lay.set_shared_cut(true)
	var a: MapElevation = lay.panes[1].view
	var b: MapElevation = lay.panes[2].view
	a.set_cut([4.5, 17.0], "perso")
	assert_eq(b.coupe, [4.5, 17.0], "coupe partagée entre Avant et Arrière")
	ed.queue_free()
	await wait_frames(1)


func test_four_views_on_a_big_map_redraw_only_the_hovered_one() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	var doc := EditorMap.blank("grande", "GRANDE", "BIG")
	for row in 2:
		for col in 25:
			var x0 := 2.0 + col * 6.0
			var y0 := 4.0 + row * 6.0
			var z := doc.add_zone("S", "R")
			doc.pieces.append({"id": doc.new_id("p"), "nom": "S", "etage": 0, "zone": String(z.id),
				"contour": [[x0, y0], [x0 + 6, y0], [x0 + 6, y0 + 6], [x0, y0 + 6]]})
	for i in 2000:
		@warning_ignore("integer_division")
		doc.objets.append({"id": doc.new_id("q"), "type": "apparition", "etage": 0, "position": [3.0 + (i % 148), 5.0 + (i / 148) * 0.8]})
	ed._reset(doc)
	ed.views.set_layout("4")
	ed.views.set_pane_plane(ed.views.panes[1], "gauche")
	await wait_frames(4)
	var elevs: Array = ed.views.elevations()
	assert_eq(elevs.size(), 3)
	var draws := elevs.map(func(e): return (e as MapElevation).content_draws)
	var canvas_draws := [0]
	ed.canvas.draw.connect(func(): canvas_draws[0] += 1)
	var t0 := Time.get_ticks_usec()
	var hovered: MapElevation = elevs[0]
	for i in 20:
		var mm := InputEventMouseMotion.new()
		mm.position = Vector2(100 + i * 7, 120)
		hovered._gui_input(mm)
		await wait_frames(1)
	var per_frame := (Time.get_ticks_usec() - t0) / 20000.0
	print("    4 vues, 2000 objets : %.1f ms par mouvement de souris" % per_frame)
	for i in elevs.size():
		assert_eq((elevs[i] as MapElevation).content_draws, draws[i], "contenu de la vue %d pas redessiné" % i)
	assert_eq(canvas_draws[0], 0, "la vue Dessus n'est pas redessinée")
	ed.queue_free()
	await wait_frames(1)
