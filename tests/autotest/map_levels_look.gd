extends AutotestScenario
## @rendu : interface des niveaux de l'éditeur de cartes (étape 5 de
## docs/LEVELS_PLAN.md), revue humaine, en français puis en anglais : barre
## des niveaux avec son menu ouvert (du plus haut au plus bas, « Autre
## altitude… ») ; plan du niveau 3,5 m de DRAFT ARENA (fantôme du
## rez-de-chaussée, vide de l'entrepôt hachuré autour de la passerelle) et
## d'une halle haute (mezzanine du dessus, à 7 m, en pointillés) ; onglet
## Niveaux. Cartes en mémoire (rien d'écrit dans le dossier des cartes).
## Captures : tests/_out/shots/map_levels_look_*.png.
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec sh tools/scenario.sh map_levels_look.

const Free := preload("res://tests/test_levels_free.gd")

var ed: MapEditor


func _show(doc: EditorMap) -> void:
	ed.new_map(true)
	ed.doc = doc
	ed.collab.reset_doc(ed.doc)
	ed.changed()
	await frames(2)


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var lang0 := String(Settings.language)
	for lang in ["fr", "en"]:
		Settings.language = lang
		tree().change_scene_to_file(MapEditor.SCENE)
		if not await until(func(): return tree().current_scene is MapEditor and tree().current_scene != ed, 6.0, "éditeur ouvert"):
			break
		ed = tree().current_scene
		await frames(3)
		# 1. DRAFT ARENA, niveau 3,5 m : fantôme du rez-de-chaussée, vide de
		# l'entrepôt (pièce haute) hachuré autour de la passerelle.
		await _show(EditorMap.load_dir("res://assets/maps/draft_arena/"))
		ed.ghost_below = true
		ed.dashed_above = false
		ed.set_floor(ed.doc.level_index(3.5))
		ed.views.toggle_maximized(ed.views.panes[0])
		await frames(2)
		ed.views.frame_all()
		await frames(3)
		at.check(ed.canvas.high_void_polys(ed.floor_k).size() == 1, "vide de l'entrepôt au niveau 3,5 m (%s)" % lang)
		await seconds(0.3)
		await at.screenshot("plan_fantome_" + lang)
		# 2. Halle haute, niveau 3,5 m : la mezzanine du dessus (7 m) en pointillés.
		await _show(Free.high_hall())
		ed.dashed_above = true
		ed.set_floor(1)
		await frames(2)
		ed.views.frame_all()
		await frames(3)
		await seconds(0.3)
		await at.screenshot("plan_pointilles_" + lang)
		ed.views.toggle_maximized(ed.views.panes[0])
		await frames(2)
		# 3. Barre des niveaux, menu ouvert.
		ed.panels.show_tab("floors")
		ed.floor_label.show_popup()
		await frames(3)
		at.check(ed.floor_label.get_popup().visible, "menu des niveaux ouvert (%s)" % lang)
		await seconds(0.3)
		await at.screenshot("barre_" + lang)
		ed.floor_label.get_popup().hide()
		await frames(2)
		# 4. Onglet Niveaux : le rez-de-chaussée choisi dans la liste (pas affiché).
		var list := ed.panels.find_child("LevelList", true, false) as ItemList
		for i in list.item_count:
			if int(list.get_item_metadata(i)) == 0:
				list.select(i)
				list.item_selected.emit(i)
		await frames(3)
		await seconds(0.2)
		await at.screenshot("onglet_" + lang)
	Settings.language = lang0
