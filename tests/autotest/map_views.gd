extends AutotestScenario
## @rendu : captures des vues multiples de l'éditeur (docs/EDITOR_VIEWS.md,
## étape 2 : élévations en lecture) : DRAFT ARENA à 100 % d'interface, deux
## vues empilées (Dessus au-dessus d'Avant, cadrées comme l'écran 2 de la
## maquette), une torche murale ajoutée (comme la maquette), puis Droite,
## Arrière, Gauche, Dessous, la coupe autour de l'entrepôt (K) et les étages
## montrés. Mesure du dessin d'une élévation sur DRAFT ARENA.
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec sh tools/scenario.sh map_views.
## Captures : tests/_out/shots/map_views_*.png.

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
	at.check(ed.views.layout_id == "2v" and ed.views.pane_count() == 2, "deux vues empilées au premier lancement (%s)" % ed.views.layout_id)
	var top: MapViewPane = ed.views.panes[0]
	var low: MapViewPane = ed.views.panes[1]
	at.check(top.view == ed.canvas and low.view is MapElevation and low.view.plane == "avant", "Dessus au-dessus d'Avant")
	at.check(ed.views.docked() and ed.hotbar_ui.global_position.y >= low.get_global_rect().end.y - 1.0, "barre rapide ancrée sous les vues")
	# Torche murale de la maquette (effet « torche », mur nord de l'entrepôt).
	ed.push_undo()
	ed.doc.objets.append({"id": "fx1", "type": "effet", "effet": "torche", "etage": 0, "position": [9.5, 4.5], "mur": "n", "hauteur": 2.4})
	ed.changed()
	ed.select("fx1")
	var av: MapElevation = low.view
	# Cadrage de l'écran 2 : zoom 22 px/m, x 12 au milieu, Dessus y 10,2, Avant z 3,3.
	_frame(ed.canvas, 22.0, Vector2(12, 10.2))
	_frame(av, 22.0, Vector2(12, -3.3))
	await frames(3)
	await at.screenshot("ecran2")
	# Boîtes : la torche à sa hauteur, l'entrepôt en double hauteur.
	var t := av.projected_of("fx1")
	at.check(not t.is_empty() and absf(float(t.it.z) - 2.4) < 0.01, "torche à 2,40 m (%s)" % t.get("it", {}).get("z", "?"))
	var p3 := av.projected_of("p3")
	at.check(not p3.is_empty() and absf(-float(p3.v0) - 6.8) < 0.01, "entrepôt en double hauteur jusqu'à 6,80 m (%.2f)" % -float(p3.get("v0", 0.0)))
	# Choix au clic dans l'élévation : la passerelle (étage 1).
	var at_px := av.to_px(Vector2(5.0, -5.0))
	_click(av, at_px)
	await frames(2)
	at.check(ed.selected == "p5" and ed.floor_k == 1, "clic en Avant : la passerelle, étage 1 (%s)" % ed.selected)
	await at.screenshot("passerelle")
	# Coupe autour de l'entrepôt (K).
	ed.select("p3")
	ed.views.set_active_pane(low)
	ed.toggle_cut()
	await frames(2)
	at.check(av.coupe.size() == 2 and absf(float(av.coupe[0]) - 4.5) < 0.01 and absf(float(av.coupe[1]) - 17.0) < 0.01, "K : coupe Y 4,5 → 17 (%s)" % [av.coupe])
	await at.screenshot("coupe")
	ed.toggle_cut()
	# Les autres plans.
	for pl in ["droite", "arriere", "gauche", "dessous"]:
		ed.views.set_pane_plane(low, pl)
		await frames(1)
		(low.view as MapElevation).frame_all()
		await frames(2)
		await at.screenshot(pl)
	ed.views.set_pane_plane(low, "avant")
	# Étages : l'étage courant seulement.
	av.header_menu_pressed("floors", 10 + MapElevation.Floors.ONLY)
	await frames(2)
	await at.screenshot("etage_courant")
	av.header_menu_pressed("floors", 10 + MapElevation.Floors.ALL)
	# Mesure : dessin d'une élévation (cache refait après une modification).
	var t0 := Time.get_ticks_usec()
	for i in 10:
		av.queue_redraw()
		await RenderingServer.frame_post_draw
	print("[views] 10 images en %d ms" % ((Time.get_ticks_usec() - t0) / 1000))
	Settings.editor_ui_scale = Settings.EDITOR_UI_SCALE_DEFAULT
	_clean(EditorMap.maps_root())


## Cadre une vue comme la maquette : zoom `z`, point `c` (uv) au milieu de la
## zone hors règles.
func _frame(v: MapView, z: float, c: Vector2) -> void:
	var r := v._ruler()
	v.zoom = z
	v.origin = Vector2(r + (v.size.x - r) * 0.5, r + (v.size.y - r) * 0.5) - c * z
	v.queue_redraw()


func _click(v: Control, px: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = px
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		v._gui_input(e)


func _clean(root: String) -> void:
	if DirAccess.dir_exists_absolute(root):
		EditorMap._remove_tree(root)
