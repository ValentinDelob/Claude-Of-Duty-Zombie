extends AutotestScenario
## @rendu : POIGNÉES « + » de l'éditeur de cartes (MapVertex,
## docs/MAP_AUTHORING.md § 2, « Ajouter ou retirer un point ») : pièce
## polygonale choisie (un « + » au milieu de chaque côté, celui sous la souris
## plein), pièce rectangle choisie (« + » au quart et aux trois quarts des
## côtés, poignées de redimensionnement gardées), puis point ajouté en tirant
## un « + » et sommet survolé (cerclé : Suppr le supprime). Ajout en cours de
## développement : capture retirée une fois la fonction validée.
## Captures : tests/_out/shots/map_vertex_look_*.png.

var ed: MapEditor


func run() -> void:
	timeout_sec = 60
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var lang0 := String(Settings.language)
	Settings.language = "fr"
	tree().change_scene_to_file(MapEditor.SCENE)
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	await frames(3)
	ed.new_map(true)
	ed.canvas.set_snap_mode("grille")
	ed.add_object({"contour": [[4, 4], [12, 4], [12, 10], [8, 13], [4, 10]], "nom": "Polygone"}, 0)
	var poly_id := ed.selected
	ed.add_object({"contour": [[14, 4], [22, 4], [22, 10], [14, 10]], "nom": "Rectangle"}, 0)
	var rect_id := ed.selected
	await frames(2)
	ed.views.set_layout("1")
	await frames(2)
	var cv := ed.canvas
	cv.zoom = 38.0
	cv.origin = cv.size * 0.5 - Vector2(13, 8.5) * cv.zoom
	cv.mouse_inside = true
	# 1. Pièce polygonale : un « + » par côté, celui de l'est sous la souris.
	ed.select(poly_id)
	var plus := cv.plus_handles()
	at.check(plus.size() == 5, "polygone : 5 « + » (%d)" % plus.size())
	cv.mouse_m = Vector2(12, 7)
	cv._update_point_hint()
	cv.queue_redraw()
	await seconds(0.3)
	await at.screenshot("polygone")
	# 2. Pièce rectangle : « + » au quart et aux trois quarts.
	ed.select(rect_id)
	at.check(cv.plus_handles().size() == 8 and cv.handles().size() == 8, "rectangle : 8 « + » et 8 poignées")
	cv.mouse_m = Vector2(16, 4)
	cv._update_point_hint()
	cv.queue_redraw()
	await seconds(0.3)
	await at.screenshot("rectangle")
	# 3. « + » tiré vers le nord : la pièce rectangle devient un polygone ;
	# souris sur le nouveau sommet (cerclé).
	cv.mouse_m = Vector2(16, 4)
	cv._press(false)
	cv.mouse_m = Vector2(16, 2)
	cv._drag_update()
	cv._release()
	at.check(MapVertex.poly_of(ed.doc.find(rect_id)).size() == 5, "point ajouté")
	cv._update_point_hint()
	cv.queue_redraw()
	await seconds(0.3)
	await at.screenshot("point_ajoute")
	Settings.language = lang0
