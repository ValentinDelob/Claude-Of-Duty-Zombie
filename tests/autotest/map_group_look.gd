extends AutotestScenario
## @rendu : SÉLECTION MULTIPLE et prefab depuis la sélection dans l'éditeur de
## cartes (MapGroup, MapContextMenu, docs/MAP_AUTHORING.md § 2), en français
## puis en anglais : groupe choisi (chaque élément surligné, cadre du groupe,
## poignée de rotation, liste des objets et panneau Propriétés « N éléments
## sélectionnés », vue Avant), rectangle de sélection (de droite à gauche :
## éléments touchés), menu du clic droit, boîte « Créer une prefab ». Carte en
## mémoire (rien d'écrit dans le dossier des cartes). Captures :
## tests/_out/shots/map_group_look_*.png.

const Free := preload("res://tests/test_map_decor_free.gd")

var ed: MapEditor


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var lang0 := String(Settings.language)
	for lang in ["fr", "en"]:
		Settings.language = lang
		tree().change_scene_to_file(MapEditor.SCENE)
		if not await until(func(): return tree().current_scene is MapEditor and tree().current_scene != ed, 6.0, "éditeur ouvert"):
			break
		ed = tree().current_scene
		await frames(3)
		ed.new_map(true)
		ed.doc = _map()
		ed.collab.reset_doc(ed.doc)
		ed.changed()
		ed.object_list.set_expanded(true, false)
		await frames(2)
		ed.views.frame_all()
		await frames(2)
		var cv := ed.canvas
		var ids := []
		for o in ed.doc.objets:
			if String(o.get("type", "")) == "prefab":
				ids.append(String(o.id))
		# 1. Groupe choisi : trois décors.
		ed.select_many(ids)
		await frames(3)
		at.check(ed.group.size() == 3, "groupe de 3 (%s)" % lang)
		at.check(cv.group_box().size != Vector2.ZERO, "cadre du groupe")
		await seconds(0.3)
		await at.screenshot("selection_" + lang)
		# 2. Rectangle de droite à gauche (éléments touchés), en cours.
		ed.select("")
		cv.drag = {"kind": "band", "start": Vector2(9.0, 7.5), "add": false, "click": ""}
		cv.mouse_m = Vector2(3.0, 3.5)
		cv.queue_redraw()
		await frames(2)
		at.check(cv._band_active() and cv.band_crossing_from(cv.drag.start), "rectangle de droite à gauche")
		await seconds(0.2)
		await at.screenshot("rectangle_" + lang)
		cv._release()
		await frames(2)
		at.check(ed.sel_ids().size() >= 3, "rectangle : %d éléments pris" % ed.sel_ids().size())
		# 3. Menu du clic droit sur le groupe.
		ed.select_many(ids)
		var p := cv.get_screen_position() + cv.to_px(Vector2(6.5, 5.5))
		var m := ed.open_context_menu(p, Vector2(6.5, 5.5), String(ids[0]))
		await frames(3)
		at.check(m.visible, "menu ouvert (%s)" % lang)
		await seconds(0.3)
		await at.screenshot("menu_" + lang)
		m.hide()
		# 4. Boîte « Créer une prefab » (la sélection a aussi une porte : exclue).
		ed.select_many(ids + ["o1"])
		var d := ed.prefab_tools.create_dialog_for(ed.sel_ids())
		await frames(3)
		at.check(d != null and d.visible, "boîte Créer une prefab (%s)" % lang)
		await seconds(0.3)
		await at.screenshot("prefab_" + lang)
		if d != null:
			d.queue_free()
		await frames(2)
	Settings.language = lang0


## Deux salles (DÉCOR LIBRE) et trois décors au sol dans la première.
static func _map() -> EditorMap:
	var doc := Free.two_rooms()
	Free._obj(doc, {"type": "prefab", "prefab": "caisses", "position": [4.0, 5.5], "rot": 0})
	Free._obj(doc, {"type": "prefab", "prefab": "sacs_sable", "position": [6.5, 5.5], "rot": 90})
	Free._obj(doc, {"type": "prefab", "prefab": "sacs_sable", "position": [8.5, 5.5], "rot": 90})
	for o in doc.objets:
		if String(o.type) == "depart":
			o["position"] = [12.0, 2.0]
	return doc
