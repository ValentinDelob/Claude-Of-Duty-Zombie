extends AutotestScenario
## @rendu : a besoin du rendu (captures de l'éditeur, fenêtre hors écran).
## ÉDITEUR DE CARTES : bouton du menu principal, puis une carte faite avec les
## vrais outils (événements de souris et de clavier envoyés à la vue) : trois
## pièces collées au glisser (murs mitoyens uniques), une porte refusée sur un
## mur extérieur puis posée sur le mur commun, des débris pris dans
## l'inventaire, des fenêtres, la boîte, une arme, un atout et le courant
## choisis dans l'inventaire (E), le départ ; vérification sans erreur,
## Ctrl+S, rechargement identique, suppression annulée par Ctrl+Z, archive
## .zip réimportée à l'identique. Captures : tests/_out/shots/map_editor_*.png.

var ed: MapEditor
var cv: MapCanvas


func run() -> void:
	timeout_sec = 120
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	var root := EditorMap.maps_root()
	_clean(root)
	await seconds(1.2)
	var b := _find_button(tree().current_scene, Lang.t("ÉDITEUR DE CARTES", "MAP EDITOR"))
	at.check(b != null, "bouton ÉDITEUR DE CARTES au menu principal")
	if b == null:
		return
	b.pressed.emit()
	if not await until(func(): return tree().current_scene is MapEditor, 6.0, "éditeur ouvert"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	await frames(4)
	at.check(ed.hotbar_ui.slots.size() == 9 and ed.current_item().id == "select", "barre rapide de 9 cases, Sélection en main")
	ed.new_map(true)
	ed.doc.carte.nom = {"fr": "ESSAI ÉDITEUR", "en": "EDITOR TEST"}
	await frames(2)
	cv.zoom = 26.0
	cv.origin = Vector2(40, 40)

	# Trois pièces collées, au glisser (touche 2 : Pièce rectangle).
	await key(KEY_2)
	at.check(ed.current_item().id == "piece_rect", "touche 2 : %s" % ed.current_item().id)
	await drag(Vector2(2, 2), Vector2(16, 12))
	await drag(Vector2(16, 2), Vector2(26, 12))
	await drag(Vector2(26, 4), Vector2(34, 10))
	at.check(ed.doc.pieces.size() == 3 and ed.doc.zones.size() == 3, "3 pièces, une zone chacune (%d, %d)" % [ed.doc.pieces.size(), ed.doc.zones.size()])
	await drag(Vector2(10, 6), Vector2(20, 9))
	at.check(ed.doc.pieces.size() == 3 and cv.refusal.contains(Lang.t("chevauche", "overlaps")), "pièce qui en recouvre une autre refusée : %s" % cv.refusal)
	var f: MapValidator.Floor = ed.raster().v.floors[0]
	at.check(f.at(Vector2i(32, 12)) == MapValidator.K.MUR and f.at(Vector2i(31, 12)) == MapValidator.K.SOL and f.at(Vector2i(33, 12)) == MapValidator.K.SOL,
		"bord commun de deux pièces : un seul mur de 0,5 m")

	# Porte : refusée sur un mur extérieur, posée sur le mur commun.
	await key(KEY_5)
	at.check(ed.current_item().id == "porte", "touche 5 : porte payante")
	await click(Vector2(2.1, 7))
	at.check(ed.doc.ouvertures.is_empty() and cv.refusal != "", "porte refusée sur un mur extérieur : « %s »" % cv.refusal)
	await click(Vector2(16.2, 7))
	var door: Dictionary = ed.doc.ouvertures[0] if not ed.doc.ouvertures.is_empty() else {}
	at.check(not door.is_empty() and int(door.prix) == 750, "porte posée sur le mur commun, 750 points (BO1)")
	# Débris pris dans l'inventaire (E), catégorie Ouvertures.
	await key(KEY_E)
	at.check(ed.inventory.visible, "E : inventaire ouvert")
	ed.inventory.show_category("ouvertures")
	await frames(2)
	await at.screenshot("inventaire")
	_pick("debris")
	at.check(not ed.inventory.visible and ed.current_item().id == "debris", "débris rangés dans la barre rapide (%s)" % ed.current_item().id)
	await click(Vector2(26.1, 7))
	at.check(ed.doc.ouvertures.size() == 2 and int(ed.doc.ouvertures[1].prix) == 1000, "débris entre les pièces 2 et 3 : 1000 points")

	# Fenêtres sur les murs extérieurs (touche 6).
	await key(KEY_6)
	for p in [Vector2(6, 1.8), Vector2(21, 1.8), Vector2(30, 3.8), Vector2(33.9, 7)]:
		await click(p)
	at.check(ed.doc.ouvertures.filter(func(o): return o.type == "fenetre").size() == 4, "4 fenêtres")
	await click(Vector2(16.1, 4))
	at.check(ed.doc.ouvertures.size() == 6 - 0 and cv.refusal != "", "fenêtre refusée sur un mur commun : « %s »" % cv.refusal)

	# Départ (8), boîtes (7), M14 (9).
	await key(KEY_8)
	await click(Vector2(11, 9))
	await key(KEY_7)
	for p in [Vector2(6, 11.3), Vector2(21, 11.3), Vector2(30, 9.4)]:
		await click(p)
	await key(KEY_9)
	await click(Vector2(13, 11.5))
	# Atout et courant pris dans l'inventaire.
	await key(KEY_4)
	await key(KEY_E)
	ed.inventory.show_category("atouts")
	_pick("atout:titan")
	await click(Vector2(33.4, 5.5))
	await key(KEY_E)
	ed.inventory.show_category("machines")
	_pick("courant")
	await click(Vector2(24.5, 2.5))
	var types := {}
	for o in ed.doc.objets:
		types[o.type] = types.get(o.type, 0) + 1
	at.check(types == {"depart": 1, "boite": 3, "arme": 1, "atout": 1, "courant": 1}, "objets posés : %s" % str(types))

	# Vérification : carte jouable.
	var v := ed.validate()
	at.check(v.ok(), "vérification : 0 erreur (%s)" % " | ".join(v.errors().map(func(m): return String(m.fr))))
	ed.panels.show_tab("check")
	ed.select("")
	cv.frame_all()
	await key(KEY_1)
	await frames(3)
	await at.screenshot("editeur")
	ed.panels.show_tab("zones")
	await frames(2)
	await at.screenshot("zones")

	# Ctrl+S, rechargement identique.
	await key(KEY_S, true)
	var dir := ed.map_dir
	at.check(dir != "" and EditorMap.is_map_dir(dir) and not ed.dirty, "Ctrl+S : enregistrée dans %s" % dir)
	for fname in EditorMap.FILES:
		at.check(FileAccess.file_exists(dir.path_join(fname)), "fichier %s" % fname)
	var saved := ed.doc.duplicate_map()
	ed.open_dir(dir)
	await frames(2)
	at.check(ed.doc.same_as(saved), "carte rechargée identique")

	# Suppression puis Ctrl+Z.
	var weapon: Dictionary = ed.doc.objets.filter(func(o): return o.type == "arme")[0]
	await click(MapRules.footprint_rect(weapon).get_center())
	at.check(ed.selected == String(weapon.id), "clic : arme choisie (%s)" % ed.selected)
	await key(KEY_DELETE)
	at.check(ed.doc.find(String(weapon.id)).is_empty(), "Suppr : arme supprimée")
	await key(KEY_Z, true)
	at.check(not ed.doc.find(String(weapon.id)).is_empty() and ed.doc.same_as(saved), "Ctrl+Z : arme revenue, carte identique")
	await key(KEY_Y, true)
	at.check(ed.doc.find(String(weapon.id)).is_empty(), "Ctrl+Y : suppression rétablie")
	await key(KEY_Z, true)

	# Archive .zip exportée puis réimportée.
	var zip := root.path_join("essai.zip")
	at.check(ed.export_zip(zip) and FileAccess.file_exists(zip), "archive exportée")
	at.check(ed.import_zip(zip) and ed.doc.same_as(saved), "archive réimportée identique")

	# Pièce polygone : clics successifs, clic sur le premier point pour fermer.
	await key(KEY_3)
	for p in [Vector2(2, 16), Vector2(12, 16), Vector2(12, 20), Vector2(7, 20), Vector2(7, 24), Vector2(2, 24), Vector2(2, 16)]:
		await click(p)
	var poly: Dictionary = ed.doc.pieces[-1]
	at.check(ed.doc.pieces.size() == 4 and poly.contour.size() == 6, "pièce polygone en L (%d sommets)" % poly.contour.size())
	# Copier / coller sous le curseur.
	await key(KEY_1)
	await click(Vector2(4, 22))
	await key(KEY_C, true)
	_motion(Vector2(22, 20))
	await key(KEY_V, true)
	at.check(ed.doc.pieces.size() == 5 and ed.doc.zones.size() == 5, "Ctrl+C / Ctrl+V : pièce collée avec sa propre zone")
	# Poignée : la pièce 3 s'agrandit, ses fenêtre et atout muraux deviennent invalides.
	var c3: Dictionary = ed.doc.pieces[2]
	await click(Vector2(30, 7))
	at.check(ed.selected == String(c3.id), "pièce 3 choisie")
	await drag(Vector2(34, 7), Vector2(36, 7))
	at.check(MapGeom.bbox(ed.doc.room_poly(ed.doc.find(String(c3.id)))).end.x == 36.0 and ed.invalid.size() >= 2,
		"poignée : pièce agrandie, éléments restés sur l'ancien mur signalés (%d)" % ed.invalid.size())
	await key(KEY_Z, true)
	at.check(ed.invalid.is_empty(), "Ctrl+Z : plus rien d'invalide")
	_clean(root)

	# Exemple livré : DRAFT ARENA, rez-de-chaussée et étage.
	ed.open_example("draft_arena")
	await frames(3)
	ed.panels.show_tab("zones")
	await frames(2)
	await at.screenshot("draft_arena")
	ed.set_floor(1)
	await frames(2)
	await at.screenshot("draft_arena_etage1")


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _find_button(n: Node, label: String) -> Button:
	for c in n.find_children("*", "Button", true, false):
		if c is MenuActionButton and (c as MenuActionButton).label == label:
			return c
	return null


## Clic sur une case de l'inventaire (catégorie affichée).
func _pick(item_id: String) -> void:
	for s in ed.inventory.cells:
		if s.item_id == item_id:
			s.clicked.emit(s)
			return
	at.fail("objet %s absent de l'inventaire" % item_id)


func _motion(m: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = cv.to_px(m)
	cv._gui_input(e)


func _button(m: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = cv.to_px(m)
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	cv._gui_input(e)


func click(m: Vector2) -> void:
	_motion(m)
	_button(m, true)
	_button(m, false)
	await frames(1)


func drag(a: Vector2, b: Vector2) -> void:
	_motion(a)
	_button(a, true)
	for i in 4:
		_motion(a.lerp(b, (i + 1) / 4.0))
		await frames(1)
	_button(b, false)
	await frames(1)


func key(code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.ctrl_pressed = ctrl
	e.pressed = true
	ed._input(e)
	var up := e.duplicate()
	up.pressed = false
	ed._input(up)
	await frames(1)
