extends AutotestScenario
## ÉDITEUR DE CARTES : bouton du menu principal, puis une carte faite avec les
## vrais outils (événements de souris et de clavier envoyés à la vue) : trois
## pièces collées au glisser (murs mitoyens uniques), une porte refusée sur un
## mur extérieur puis posée sur le mur commun, des débris pris dans
## l'inventaire, des fenêtres, la caisse au hasard, le courant choisi dans
## l'inventaire (E), le départ ; vérification sans erreur,
## Ctrl+S, rechargement identique, suppression annulée par Ctrl+Z, archive
## .zip réimportée à l'identique. Puis une salle décorée : prefabs pris dans
## l'inventaire (gravats, bureau, sacs de sable pivotés avec R, fauteuils),
## refus d'un décor sur un autre et dans un mur, luminaires (lampe sur le
## bureau, suspension recolorée, applique, brasero, néon, bougies), textures
## des pièces (brique / parquet / bois, plâtre vert / carrelage), onglet
## « Objets sur la carte » (L) avec survol dans les deux sens et page 2, puis
## TESTER : la pièce en jeu. Captures : tests/_out/shots/map_editor_*.png.

var ed: MapEditor
var cv: MapCanvas


func run() -> void:
	timeout_sec = 240
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
	at.check(ed.hotbar_ui.slots.size() == 9 and ed.mouse_active() and ed.hot_index == MapEditor.MOUSE, "barre rapide de 9 cases, souris en main")
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
	# Pièce tracée sur deux autres : confirmation de la découpe (MapCarve) ;
	# Annuler ne crée rien.
	await drag(Vector2(10, 6), Vector2(20, 9))
	var cd: ConfirmationDialog = ed.carve_dialog
	at.check(cd != null and cd.visible and ed.doc.pieces.size() == 3, "pièce qui en recouvre d'autres : confirmation de la découpe")
	if cd != null:
		cd.get_cancel_button().pressed.emit()
	await frames(2)
	at.check(ed.doc.pieces.size() == 3 and ed.doc.zones.size() == 3, "découpe annulée : rien de créé")
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

	# Départ (8), caisse au hasard (7, une seule par carte).
	await key(KEY_8)
	await click(Vector2(11, 9))
	await key(KEY_7)
	await click(Vector2(6, 11.3))
	# Courant pris dans l'inventaire, contre le mur est de la pièce 3.
	await key(KEY_4)
	await key(KEY_E)
	ed.inventory.show_category("machines")
	_pick("courant")
	await click(Vector2(33.4, 5.5))
	# Porte d'évacuation (obligatoire, format 18) contre le mur ouest du départ.
	await key(KEY_E)
	ed.inventory.show_category("joueurs")
	_pick("evacuation")
	await click(Vector2(2.3, 7))
	# Station de construction (obligatoire, format 19) contre le mur nord.
	await key(KEY_E)
	ed.inventory.show_category("joueurs")
	_pick("station")
	await click(Vector2(11, 2.3))
	var types := {}
	for o in ed.doc.objets:
		types[o.type] = types.get(o.type, 0) + 1
	at.check(types == {"depart": 1, "boite": 1, "courant": 1, "evacuation": 1, "station": 1}, "objets posés : %s" % str(types))

	# Vérification : carte jouable.
	var v := ed.validate()
	at.check(v.ok(), "vérification : 0 erreur (%s)" % " | ".join(v.errors().map(func(m): return String(m.fr))))
	ed.panels.show_tab("check")
	ed.select("")
	cv.frame_all()
	await key(KEY_QUOTELEFT)
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
	var weapon: Dictionary = ed.doc.objets.filter(func(o): return o.type == "courant")[0]
	await click(MapRules.footprint_rect(weapon).get_center())
	at.check(ed.selected == String(weapon.id), "clic : interrupteur choisi (%s)" % ed.selected)
	await key(KEY_DELETE)
	at.check(ed.doc.find(String(weapon.id)).is_empty(), "Suppr : interrupteur supprimé")
	await key(KEY_Z, true)
	at.check(not ed.doc.find(String(weapon.id)).is_empty() and ed.doc.same_as(saved), "Ctrl+Z : interrupteur revenu, carte identique")
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
	await key(KEY_QUOTELEFT)
	# La pièce posée est déjà choisie : un reclic la désélectionnerait.
	ed.select("")
	await click(Vector2(4, 22))
	at.check(ed.selected == String(poly.id), "clic : pièce polygone choisie")
	await key(KEY_C, true)
	_motion(Vector2(22, 20))
	await key(KEY_V, true)
	at.check(ed.doc.pieces.size() == 5 and ed.doc.zones.size() == 5, "Ctrl+C / Ctrl+V : pièce collée avec sa propre zone")
	# Poignée : la pièce 3 s'agrandit, sa fenêtre et son interrupteur muraux deviennent invalides.
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

	await _decor_and_textures()


## Décor, luminaires, textures, liste des objets, puis la carte jouée.
func _decor_and_textures() -> void:
	ed.new_map(true)
	ed.doc.carte.nom = {"fr": "SALLE DÉCORÉE", "en": "DECORATED HALL"}
	ed.object_list.set_expanded(false, false)
	await frames(2)
	cv.zoom = 30.0
	cv.origin = Vector2(40, 40)
	# Deux pièces, une porte, des fenêtres, le départ, la boîte.
	await key(KEY_2)
	await drag(Vector2(2, 2), Vector2(18, 14))
	await drag(Vector2(18, 2), Vector2(28, 14))
	await key(KEY_5)
	await click(Vector2(18.2, 8))
	await key(KEY_6)
	for p in [Vector2(8, 1.8), Vector2(23, 1.8), Vector2(27.9, 10)]:
		await click(p)
	await key(KEY_8)
	await click(Vector2(13, 11))
	await key(KEY_7)
	await click(Vector2(6, 13.3))
	await key(KEY_E)
	ed.inventory.show_category("joueurs")
	_pick("evacuation")
	await click(Vector2(2.3, 8))
	at.check(ed.doc.objets.any(func(o): return o.type == "evacuation"), "porte d'évacuation posée (%s)" % cv.refusal)
	await key(KEY_E)
	ed.inventory.show_category("joueurs")
	_pick("station")
	await click(Vector2(13, 2.3))
	at.check(ed.doc.objets.any(func(o): return o.type == "station"), "station de construction posée (%s)" % cv.refusal)
	at.check(ed.doc.pieces.size() == 2 and ed.doc.ouvertures.size() == 4, "deux pièces, une porte, trois fenêtres")
	# Décor pris dans l'inventaire (catégorie Décor et obstacles).
	await key(KEY_E)
	ed.inventory.show_category("prefabs")
	await frames(2)
	await at.screenshot("inventaire_decor")
	at.check(ed.inventory.cells.size() >= MapCatalog.PREFABS.size(), "inventaire : %d décors" % ed.inventory.cells.size())
	_pick("prefab:gravats")
	await click(Vector2(24, 9.5))
	await key(KEY_E)
	ed.inventory.show_category("prefabs")
	_pick("prefab:bureau")
	await click(Vector2(6, 6))
	await key(KEY_E)
	ed.inventory.show_category("prefabs")
	_pick("prefab:sacs_sable")
	await key(KEY_R)
	at.check(ed.place_rot == 90, "R : sacs de sable pivotés avant la pose")
	await click(Vector2(15, 5))
	await key(KEY_E)
	ed.inventory.show_category("prefabs")
	_pick("prefab:fauteuils")
	await click(Vector2(9, 9))
	var n_prefabs := ed.doc.objets.filter(func(o): return o.type == "prefab").size()
	at.check(n_prefabs == 4, "4 décors posés (%d)" % n_prefabs)
	var sand: Array = ed.doc.objets.filter(func(o): return o.get("prefab", "") == "sacs_sable")
	at.check(not sand.is_empty() and int(sand[0].rot) == 90, "sacs de sable posés pivotés")
	# Refus : décor sur un autre, décor dans un mur.
	await key(KEY_E)
	ed.inventory.show_category("prefabs")
	_pick("prefab:caisses")
	await click(Vector2(24, 9.5))
	at.check(ed.doc.objets.filter(func(o): return o.type == "prefab").size() == 4 and cv.refusal != "", "caisses sur les gravats refusées : « %s »" % cv.refusal)
	# Format 7 : le décor se pose librement, même à cheval sur un mur
	# (docs/MAP_OBJECTS.md § 8) ; annulé ensuite (Ctrl+Z).
	await click(Vector2(18.1, 11))
	at.check(ed.doc.objets.filter(func(o): return o.type == "prefab").size() == 5, "caisses à cheval sur le mur acceptées (décor libre) %s" % cv.refusal)
	await key(KEY_Z, true)
	at.check(ed.doc.objets.filter(func(o): return o.type == "prefab").size() == 4, "Ctrl+Z : caisses retirées")
	# Luminaires.
	var bureau: Dictionary = ed.doc.objets.filter(func(o): return o.get("prefab", "") == "bureau")[0]
	for pick in [["luminaire:lampe_bureau", MapRules.footprint_rect(bureau).get_center()], ["luminaire:suspension", Vector2(11, 6)],
			["luminaire:applique", Vector2(2.6, 9)], ["luminaire:feu", Vector2(21, 12)], ["luminaire:neon", Vector2(24, 5)],
			["luminaire:bougies", Vector2(16, 12)]]:
		await key(KEY_E)
		ed.inventory.show_category("lumieres")
		_pick(String(pick[0]))
		await click(pick[1])
	var lights := ed.doc.objets.filter(func(o): return o.type == "luminaire")
	at.check(lights.size() == 6, "6 luminaires posés (%d)" % lights.size())
	var lamp: Array = lights.filter(func(o): return o.luminaire == "lampe_bureau")
	at.check(not lamp.is_empty() and MapRules.support_under(ed.doc, lamp[0]).get("id", "") == bureau.id, "lampe de bureau posée sur le bureau")
	var sconce: Array = lights.filter(func(o): return o.luminaire == "applique")
	at.check(not sconce.is_empty() and sconce[0].get("mur", "") == "o", "applique contre le mur ouest")
	# Réglages d'un luminaire : couleur et vacillement dans les propriétés.
	await key(KEY_QUOTELEFT)
	var sus: Dictionary = lights.filter(func(o): return o.luminaire == "suspension")[0]
	await click(MapGeom.v2(sus.position))
	at.check(ed.selected == String(sus.id), "suspension choisie")
	ed.panels.refresh_now()
	var cp := ed.panels._props.find_children("*", "ColorPickerButton", true, false)
	at.check(cp.size() == 1, "couleur réglable")
	if not cp.is_empty():
		(cp[0] as ColorPickerButton).color = Color(1.0, 0.55, 0.3)
		(cp[0] as ColorPickerButton).popup_closed.emit()
	at.check(String(ed.doc.find(String(sus.id)).couleur) == "#ff8c4d", "couleur enregistrée (%s)" % ed.doc.find(String(sus.id)).get("couleur", ""))

	# Textures des pièces (onglet Propriétés), mur mitoyen à deux faces.
	var a: Dictionary = ed.doc.pieces[0]
	var b: Dictionary = ed.doc.pieces[1]
	await click(Vector2(4, 11))
	at.check(ed.selected == String(a.id), "pièce A choisie")
	ed.panels.show_tab("props")
	ed.panels.refresh_now()
	_surface_pick(Lang.t("Murs", "Walls"), "brick")
	_surface_pick(Lang.t("Sol", "Floor"), "parquet")
	_surface_pick(Lang.t("Plafond", "Ceiling"), "wood")
	await click(Vector2(26, 13))
	at.check(ed.selected == String(b.id), "pièce B choisie")
	ed.panels.refresh_now()
	_surface_pick(Lang.t("Murs", "Walls"), "wall_green")
	_surface_pick(Lang.t("Sol", "Floor"), "tiles")
	at.check(String(a.get("surface_murs", "")) == "brick" and String(a.get("surface_plafond", "")) == "wood" and String(b.get("surface_murs", "")) == "wall_green",
		"textures des pièces : A brique / bois, B plâtre vert")
	await click(Vector2(4, 11))
	ed.panels.refresh_now()
	var v := ed.validate()
	at.check(v.ok(), "carte décorée jouable (%s)" % " | ".join(v.errors().map(func(m): return String(m.fr))))
	var lay := MapLayoutExport.build(v)
	var wall_mats := {}
	for bl in lay.blocks:
		wall_mats[bl.mat] = true
	at.check(wall_mats.has("brick") and wall_mats.has("wall_green"), "murs construits en brique et plâtre vert : %s" % str(wall_mats.keys()))
	ed.panels.show_tab("props")
	cv.frame_all()
	await frames(3)
	await at.screenshot("textures")

	# Onglet « Objets sur la carte » : ouvert d'un clic (L), survol dans les deux sens.
	await key(KEY_L)
	await frames(3)
	var lst := ed.object_list
	at.check(lst.expanded and lst.entries.size() == ed.doc.pieces.size() + ed.doc.ouvertures.size() + ed.doc.objets.size(), "liste ouverte : %d éléments" % lst.entries.size())
	cv.frame_all()
	await frames(2)
	_motion(MapRules.footprint_rect(bureau).get_center() + Vector2(0.6, 0.3))
	await frames(2)
	at.check(ed.hover_id == String(bureau.id) and lst.row_of(String(bureau.id)) >= 0, "survol du bureau sur la carte : sa ligne est surlignée (%s)" % ed.hover_id)
	await at.screenshot("objets")
	var mm := InputEventMouseMotion.new()
	var row := lst.row_of(String(sus.id))
	mm.position = Vector2(30, (row + 0.5) * MapObjectList.row_h())
	lst.rows._gui_input(mm)
	await frames(2)
	at.check(ed.hover_id == String(sus.id), "survol de la ligne : la suspension s'allume sur la carte")

	# Enregistrer (format 2), puis 60 apparitions en plus : page 2 de la liste.
	await key(KEY_S, true)
	var dir := ed.map_dir
	at.check(EditorMap.is_map_dir(dir) and int(JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json"))).format) == EditorMap.FORMAT,
		"Ctrl+S : enregistrée au format %d" % EditorMap.FORMAT)
	var saved := ed.doc.duplicate_map()
	var before := ed.doc.snapshot()
	for i in 60:
		@warning_ignore("integer_division")
		ed.doc.objets.append({"id": ed.doc.new_id("q"), "type": "apparition", "altitude": 0, "position": [3.0 + (i % 12), 3.0 + (i / 12) * 0.5 + 8.5]})
	ed.changed()
	await frames(2)
	at.check(lst._page_label.text.contains("1/2"), "plus de 50 éléments : deux pages (%s)" % lst._page_label.text)
	lst._next.pressed.emit()
	await frames(2)
	at.check(lst.page == 1 and lst.rows.items.size() == lst.shown.size() - 50, "page 2 : %d éléments" % lst.rows.items.size())
	await at.screenshot("page2")
	ed.doc.restore(before)
	ed.changed()
	ed.dirty = false
	ed.open_dir(dir)
	await frames(2)
	at.check(ed.doc.same_as(saved), "carte décorée rechargée identique")

	# En jeu : TESTER, une vue de la pièce A (brique, parquet, bureau, lampes).
	if not ed.test_map():
		at.fail("TESTER refusé")
		return
	var ok: bool = await until(func(): return Game.instance != null and Game.instance.local_player != null, 30.0, "partie lancée")
	if not ok:
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	game.combat.debug_invulnerable = true
	var off := MapGeom.WORLD_OFFSET
	at.check(game.map_def is EditorMapDef and (game.map_def as EditorMapDef).validator.props.size() == 4, "partie : 4 décors")
	var omni := game.world.find_children("*", "OmniLight3D", true, false)
	at.check(omni.size() >= 6, "lumières de la carte : %d" % omni.size())
	await seconds(1.0)
	p.global_position = Vector3(off + 16.5, 0.05, off + 12.5)
	AutotestHelpers.aim_at(p, Vector3(off + 6.0, 1.0, off + 6.5))
	await seconds(0.8)
	AutotestHelpers.aim_at(p, Vector3(off + 6.0, 1.0, off + 6.5))
	await frames(4)
	await at.screenshot("en_jeu")
	Router.back_to_menu()
	if not await until(func(): return tree().current_scene is MapEditor, 10.0, "retour dans l'éditeur"):
		return
	ed = tree().current_scene
	cv = ed.canvas
	await frames(3)
	at.check(ed.doc.objets.filter(func(o): return o.type == "luminaire").size() == 6, "retour dans l'éditeur sur la carte décorée")
	_clean(EditorMap.maps_root())


## Choix d'une texture dans l'onglet Propriétés (ligne `label`).
func _surface_pick(label: String, surface: String) -> void:
	for h in ed.panels._props.get_children():
		if not h is HBoxContainer or h.get_child_count() < 3 or not h.get_child(0) is Label or (h.get_child(0) as Label).text != label:
			continue
		var o := h.get_child(2) as OptionButton
		if o == null:
			continue
		var i := MapCatalog.allowed_surfaces().find(surface) + 1
		o.select(i)
		o.item_selected.emit(i)
		return
	at.fail("texture « %s » introuvable dans les propriétés" % label)


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
