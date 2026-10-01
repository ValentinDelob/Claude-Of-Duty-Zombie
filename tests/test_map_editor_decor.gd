extends TestCase
## Éditeur de cartes, décor et confort (docs/MAP_AUTHORING.md) : liste des
## objets sur la carte (pagination par 50, filtres, survol carte <-> ligne,
## 2000 éléments), prefabs de décor et luminaires (règles de pose, rotation,
## meubles porteurs), textures par pièce (enregistrées, relues, construites
## en jeu, mur mitoyen à deux faces), format 2 et lecture du format 1, types
## admis (MapCatalog.allowed_kinds) et construction jouable.

const TMP := "res://tests/_out/test_map_editor_decor"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


# ------------------------------------------------------------------ outils

static func _room(doc: EditorMap, x0: float, y0: float, x1: float, y1: float, k := 0) -> Dictionary:
	var id := doc.new_id("p")
	var z := String(doc.add_zone("Salle " + id, "Room " + id).id)
	var r := {"id": id, "nom": "Salle " + id, "etage": k, "zone": z, "contour": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]}
	doc.pieces.append(r)
	return r


static func _obj(doc: EditorMap, o: Dictionary, k := 0) -> Dictionary:
	o["id"] = doc.new_id(String(o.get("_p", "x")))
	o.erase("_p")
	o["etage"] = k
	doc.objets.append(o)
	return o


static func _prefab(id: String, x: float, y: float, rot := 0) -> Dictionary:
	return {"type": "prefab", "prefab": id, "position": [x, y], "rot": rot}


static func _light(id: String, x: float, y: float) -> Dictionary:
	var o: Dictionary = MapCatalog.item("luminaire:" + id).make.duplicate(true)
	o["position"] = [x, y]
	return o


## Carte jouable : deux salles (A : départ, B), une porte, fenêtres, boîte,
## arme, atout, décor, luminaires et textures.
static func _decorated() -> EditorMap:
	var doc := EditorMap.blank("decor", "DÉCOR", "DECOR")
	var a := _room(doc, 0, 0, 14, 10)
	var b := _room(doc, 14, 0, 24, 10)
	doc.depart = String(doc.zones[0].id)
	a["surface_murs"] = "brick"
	a["surface_sol"] = "tiles"
	a["surface_plafond"] = "wood"
	b["surface_murs"] = "wall_green"
	doc.ouvertures.append({"id": "o1", "type": "porte", "etage": 0, "position": [14.0, 5.25], "largeur": 2.0, "prix": 750})
	doc.ouvertures.append({"id": "o2", "type": "fenetre", "etage": 0, "position": [3.25, 0.0]})
	doc.ouvertures.append({"id": "o3", "type": "fenetre", "etage": 0, "position": [19.25, 0.0]})
	_obj(doc, {"type": "depart", "position": [9.0, 7.0]})
	_obj(doc, {"type": "boite", "position": [6.75, 10.0], "mur": "s", "depart": false})
	_obj(doc, {"type": "arme", "arme": "m14", "position": [11.25, 10.0], "mur": "s"})
	_obj(doc, {"type": "atout", "atout": "titan", "position": [24.0, 5.0], "mur": "e"})
	_obj(doc, _prefab("gravats", 19.25, 6.25))
	_obj(doc, _prefab("bureau", 4.5, 4.25))
	_obj(doc, _prefab("sacs_sable", 10.25, 3.25, 90))
	_obj(doc, _prefab("debris_epars", 20.25, 2.75))
	_obj(doc, _light("lampe_bureau", 4.5, 4.5))
	_obj(doc, _light("suspension", 7.5, 5.5))
	_obj(doc, _light("feu", 17.25, 8.25))
	var sconce := _light("applique", 0.0, 5.0)
	sconce["mur"] = "o"
	sconce["couleur"] = "#40a0ff"
	_obj(doc, sconce)
	return doc


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


# ------------------------------------------------------------------ liste des objets

func test_pagination_by_fifty() -> void:
	var p := MapObjectList.paginate(0, 0)
	assert_eq([p.pages, p.page, p.from, p.to], [1, 0, 0, 0], "liste vide : une page vide")
	p = MapObjectList.paginate(50, 0)
	assert_eq([p.pages, p.from, p.to], [1, 0, 50], "50 éléments : une seule page")
	p = MapObjectList.paginate(51, 1)
	assert_eq([p.pages, p.page, p.from, p.to], [2, 1, 50, 51], "51 éléments : page 2 avec le dernier")
	p = MapObjectList.paginate(2000, 99)
	assert_eq([p.pages, p.page, p.from, p.to], [40, 39, 1950, 2000], "2000 éléments : 40 pages, page bornée à la dernière")
	assert_eq(MapObjectList.page_of(49), 0)
	assert_eq(MapObjectList.page_of(50), 1)
	assert_eq(MapObjectList.page_of(1999), 39)
	assert_eq(MapObjectList.PER_PAGE, 50)


func test_entries_sorted_by_id_and_filtered() -> void:
	var doc := _decorated()
	for i in 12:
		_obj(doc, {"type": "apparition", "position": [2.0 + i * 0.5, 8.0], "_p": "q"})
	var entries := MapObjectList.build_entries(doc)
	assert_eq(entries.size(), doc.pieces.size() + doc.ouvertures.size() + doc.objets.size(), "tous les éléments")
	var ids := entries.map(func(e): return String(e.id))
	assert_true(ids.find("q2") < ids.find("q10"), "tri naturel par identifiant : q2 avant q10")
	var sorted := ids.duplicate()
	sorted.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	assert_eq(ids, sorted, "ordre stable par identifiant")
	var by := {}
	for e in entries:
		by[e.filter] = by.get(e.filter, 0) + 1
	assert_eq(by.get("pieces"), 2, "2 pièces")
	assert_eq(by.get("ouvertures"), 3, "3 ouvertures")
	assert_eq(by.get("prefabs"), 4, "4 décors")
	assert_eq(by.get("lumieres"), 4, "4 luminaires")
	var bureau: Dictionary = entries.filter(func(e): return String(e.name) == Lang.t("Bureau", "Desk"))[0]
	assert_eq(bureau.floor, 0)
	assert_true((bureau.pos as Vector2).is_equal_approx(Vector2(4.5, 4.25)), "position en mètres : %s" % bureau.pos)


func test_list_in_the_editor_hover_both_ways() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	var doc := EditorMap.blank("liste", "LISTE", "LIST")
	_room(doc, 0, 0, 40, 30)
	for i in 120:
		@warning_ignore("integer_division")
		_obj(doc, {"type": "apparition", "position": [2.0 + (i % 30) * 1.0, 2.0 + (i / 30) * 2.0], "_p": "q"})
	ed._reset(doc)
	ed.object_list.set_expanded(true, false)
	await wait_frames(2)
	var lst := ed.object_list
	assert_eq(lst.entries.size(), 121, "121 éléments")
	assert_eq(lst.rows.items.size(), 50, "page de 50 lignes")
	assert_true(lst._page_label.text.contains("1/3"), "page 1/3 : %s" % lst._page_label.text)
	# Survol sur la carte -> ligne surlignée, liste à la bonne page.
	var target: Dictionary = lst.shown[75]
	var e := doc.find(String(target.id))
	ed.canvas.mouse_m = MapRules.footprint_rect(e).get_center()
	ed.canvas.update_hover()
	assert_eq(ed.hover_id, String(target.id), "élément survolé sur la carte")
	assert_eq(lst.page, 1, "la liste saute à la page 2")
	assert_eq(lst.row_of(String(target.id)), 25, "sa ligne (26e de la page 2)")
	assert_true(lst._page_label.text.contains("2/3"), lst._page_label.text)
	# Survol d'une ligne -> élément entouré sur la carte, vue immobile.
	var origin := ed.canvas.origin
	var zoom := ed.canvas.zoom
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(20, MapObjectList.row_h() * 3.5)
	lst.rows._gui_input(mm)
	assert_eq(ed.hover_id, String(lst.rows.items[3].id), "ligne survolée -> élément surligné sur la carte")
	assert_true(ed.canvas.origin == origin and ed.canvas.zoom == zoom, "la vue ne bouge pas au survol")
	# Clic : choisir et centrer ; double-clic : centrer et zoomer.
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = mm.position
	lst.rows._gui_input(mb)
	assert_eq(ed.selected, String(lst.rows.items[3].id), "clic : élément choisi")
	mb.double_click = true
	lst.rows._gui_input(mb)
	assert_true(ed.canvas.zoom > zoom, "double-clic : zoom (%s -> %s)" % [zoom, ed.canvas.zoom])
	# Filtre et recherche.
	lst.set_filter("pieces")
	assert_eq(lst.shown.size(), 1, "filtre Pièces")
	lst.set_filter("tout")
	lst.set_search("q119")
	assert_eq(lst.shown.map(func(x): return x.id), ["q119"], "recherche par identifiant")
	lst.set_search("")
	# Aucune reconstruction au survol ni à chaque image.
	var n := lst.rebuild_count
	for i in 30:
		ed.canvas.mouse_m = Vector2(2.0 + i, 2.0)
		ed.canvas.update_hover()
	await wait_frames(5)
	assert_eq(lst.rebuild_count, n, "survols et images : la liste n'est pas refaite")
	# Replier / rouvrir : état mémorisé.
	lst.toggle()
	assert_false(lst.expanded)
	assert_false(bool(MapEditor.pref("liste_objets", true)), "état replié mémorisé")
	lst.toggle()
	assert_true(bool(MapEditor.pref("liste_objets", false)), "état ouvert mémorisé")
	ed.queue_free()
	await wait_frames(1)


func test_two_thousand_elements_stay_fluid() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	var doc := EditorMap.blank("gros", "GROS", "BIG")
	_room(doc, 0, 0, 102, 82)
	for i in 2000:
		@warning_ignore("integer_division")
		_obj(doc, {"type": "apparition", "position": [1.0 + (i % 50) * 2.0, 1.0 + (i / 50) * 2.0], "_p": "q"})
	var t0 := Time.get_ticks_msec()
	ed._reset(doc)
	ed.object_list.set_expanded(true, false)
	var t_open := Time.get_ticks_msec() - t0
	assert_eq(ed.object_list.entries.size(), 2001)
	assert_true(ed.object_list._page_label.text.contains("1/41"), ed.object_list._page_label.text)
	t0 = Time.get_ticks_msec()
	ed.add_object({"type": "apparition", "position": [3.0, 2.0]}, 0)
	await wait_frames(1)
	var t_change := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	for i in 60:
		ed.canvas.mouse_m = Vector2(1.0 + (i * 7 % 50) * 2.0, 1.0 + (i * 3 % 40) * 2.0)
		ed.canvas.update_hover()
	var t_hover := (Time.get_ticks_msec() - t0) / 60.0
	print("    2000 éléments : ouverture %d ms, pose %d ms, survol %.1f ms" % [t_open, t_change, t_hover])
	assert_true(t_hover < 12.0, "survol sur la carte : %.1f ms par image" % t_hover)
	assert_true(t_change < 2500, "pose d'un objet : %d ms" % t_change)
	assert_true(ed.hover_id != "" and ed.object_list.row_of(ed.hover_id) >= 0, "ligne du dernier survol affichée")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ prefabs et luminaires

func test_every_prefab_placed_or_refused_by_the_rules() -> void:
	var doc := EditorMap.blank()
	_room(doc, 0, 0, 20, 20)
	for pid in MapCatalog.PREFABS:
		var tmpl := {"type": "prefab", "prefab": pid, "rot": 0}
		var r := MapRules.place_floor_item(doc, 0, tmpl, Vector2(10, 10))
		assert_true(r.ok, "%s posé au milieu d'une pièce : %s" % [pid, r.get("fr", "")])
		# Format 7 : le décor se pose librement, même à cheval sur un mur.
		r = MapRules.place_floor_item(doc, 0, tmpl, Vector2(0.05, 10))
		assert_true(r.ok, "%s à cheval sur le mur : accepté (décor libre) : %s" % [pid, r.get("fr", "")])
		r = MapRules.place_floor_item(doc, 0, tmpl, Vector2(30, 10))
		assert_false(r.ok, "%s hors de toute pièce : refusé" % pid)
	# Chevauchement et rotation.
	var bureau := _obj(doc, _prefab("bureau", 5.5, 5.25))
	var r := MapRules.place_floor_item(doc, 0, {"type": "prefab", "prefab": "gravats", "rot": 0}, Vector2(6, 6))
	assert_false(r.ok, "gravats sur le bureau : refusé")
	assert_true(String(r.fr).contains("chevauche"), r.get("fr", ""))
	assert_eq(MapCatalog.floor_size(bureau), Vector2i(3, 2), "bureau 1,5 × 1 m")
	bureau["rot"] = 90
	assert_eq(MapCatalog.floor_size(bureau), Vector2i(2, 3), "pivoté : 1 × 1,5 m")
	# Collisions : un prefab qui bloque rend ses cases pleines, pas un décor au sol.
	var epars := _obj(doc, _prefab("debris_epars", 14.25, 14.25))
	var gravats := _obj(doc, _prefab("gravats", 14.25, 5.25))
	var f: MapValidator.Floor = MapRaster.build(doc).v.floors[0]
	assert_eq(f.at(MapGeom.cell_of(Vector2(14, 5))), MapValidator.K.MUR, "gravats : infranchissables")
	assert_eq(f.at(MapGeom.cell_of(Vector2(14, 14))), MapValidator.K.SOL, "débris épars : on marche dessus")
	assert_eq(MapCatalog.blocking(epars), "non")
	assert_eq(MapCatalog.blocking(gravats), "solide")
	assert_eq(MapCatalog.blocking({"type": "prefab", "prefab": "fauteuils"}), "barriere")


func test_every_light_placed_or_refused_by_the_rules() -> void:
	var doc := EditorMap.blank()
	_room(doc, 0, 0, 20, 20)
	for lid in MapCatalog.LIGHTS:
		var d: Dictionary = MapCatalog.LIGHTS[lid]
		var tmpl: Dictionary = MapCatalog.item("luminaire:" + lid).make
		if d.mount == "mur":
			var r := MapRules.place_wall_item(doc, 0, tmpl, Vector2(10, 0.6))
			assert_true(r.ok and r.mur == "n", "%s contre le mur nord : %s" % [lid, r.get("fr", "")])
			assert_false(MapRules.place_wall_item(doc, 0, tmpl, Vector2(10, 10)).ok, "%s au milieu de la pièce : refusé" % lid)
		else:
			var r := MapRules.place_floor_item(doc, 0, tmpl, Vector2(10, 10))
			assert_true(r.ok, "%s dans la pièce : %s" % [lid, r.get("fr", "")])
			assert_false(MapRules.place_floor_item(doc, 0, tmpl, Vector2(30, 10)).ok, "%s dehors : refusé" % lid)
	# Plafond : au-dessus du décor, mais pas sur un autre luminaire du plafond.
	_obj(doc, _prefab("gravats", 5.0, 5.0))
	var sus: Dictionary = MapCatalog.item("luminaire:suspension").make
	assert_true(MapRules.place_floor_item(doc, 0, sus, Vector2(5, 5)).ok, "suspension au-dessus des gravats : acceptée")
	_obj(doc, _light("suspension", 5.5, 5.5))
	var r := MapRules.place_floor_item(doc, 0, sus, Vector2(5.5, 5.5))
	assert_false(r.ok, "deux suspensions au même endroit : refusé")
	# Au sol : sur un meuble porteur, pas sur des gravats.
	var bureau := _obj(doc, _prefab("bureau", 14.5, 14.25))
	var lamp: Dictionary = MapCatalog.item("luminaire:lampe_bureau").make
	r = MapRules.place_floor_item(doc, 0, lamp, Vector2(14.5, 14.5))
	assert_true(r.ok and r.get("sur", "") == String(bureau.id), "lampe de bureau posée sur le bureau : %s" % str(r))
	assert_false(MapRules.place_floor_item(doc, 0, lamp, Vector2(5, 5)).ok, "lampe de bureau sur les gravats : refusée")
	# Le bureau reste valide avec sa lampe dessus.
	var l := _obj(doc, _light("lampe_bureau", 14.5, 14.5))
	assert_true(MapRules.check_existing(doc, bureau).ok, "bureau et sa lampe : valides")
	assert_true(MapRules.check_existing(doc, l).ok, "lampe sur le bureau : valide")
	var lp: Array = MapRaster.build(doc).v.lamps_extra.filter(func(x): return x.get("luminaire", "") == "lampe_bureau")
	assert_eq(lp.size(), 1)
	assert_near(float(lp[0].support), 0.78, 0.01, "lampe à la hauteur du dessus du bureau")


func test_rotation_with_r_in_the_editor() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	ed.add_object({"contour": [[0, 0], [16, 0], [16, 12], [0, 12]]}, 0)
	var sb := ed.add_object(_prefab("sacs_sable", 8.25, 6.25), 0)
	assert_eq(MapCatalog.floor_size(sb), Vector2i(4, 2))
	ed.select(String(sb.id))
	ed.rotate_selected()
	var now := ed.doc.find(String(sb.id))
	assert_eq(int(now.rot), 90, "R : pivoté de 90°")
	assert_eq(MapCatalog.floor_size(now), Vector2i(2, 4), "emprise pivotée")
	assert_true(MapRules.check_existing(ed.doc, now).ok, "toujours valide après rotation")
	ed.undo()
	assert_eq(int(ed.doc.find(String(sb.id)).rot), 0, "Ctrl+Z : rotation annulée")
	# R avec un décor en main : il pivote avant d'être posé.
	ed.set_hotbar(2, "prefab:chariot")
	ed.rotate_selected()
	assert_eq(ed.place_rot, 90, "R : objet tenu pivoté")
	ed.canvas.mouse_m = Vector2(4, 4)
	ed.canvas._update_preview()
	assert_eq(int(ed.canvas.preview.obj.rot), 90, "aperçu pivoté")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ textures

func test_room_textures_saved_reloaded_and_built() -> void:
	var doc := _decorated()
	var dir := ProjectSettings.globalize_path(TMP + "/textures")
	assert_eq(doc.save_dir(dir), OK)
	var back := EditorMap.load_dir(dir)
	assert_true(back.same_as(doc), "relue à l'identique")
	assert_eq(String(back.pieces[0].surface_murs), "brick", "texture des murs relue")
	assert_eq(String(back.pieces[0].surface_plafond), "wood", "texture du plafond relue")
	assert_false(back.pieces[1].has("surface_sol"), "sans texture : celle de la zone")
	assert_true(String(doc.file_texts()["pieces.json"]).contains("\"surface_murs\":\"brick\""), "clé lisible dans pieces.json")
	var v := _check(back)
	assert_true(v.ok(), _errs(v))
	var lay := MapLayoutExport.build(v)
	var mats := {}
	for r in lay.rooms:
		mats[String(r.floor_mat)] = true
		mats["c:" + String(r.ceiling_mat)] = true
	assert_true(mats.has("tiles") and mats.has("concrete"), "sols : carrelage (A) et béton de la zone (B) : %s" % str(mats.keys()))
	assert_true(mats.has("c:wood") and mats.has("c:ceiling"), "plafonds : bois (A) et celui par défaut (B)")
	# Mur mitoyen (x = 14 m) : brique côté A, plâtre vert côté B.
	var west := []
	var east := []
	for bl in lay.blocks:
		var b: Array = bl.box
		if absf(float(b[0]) - (4.25 + 13.75)) < 0.01 and absf(float(b[3]) - (4.25 + 14.0)) < 0.01:
			west.append(bl.mat)
		if absf(float(b[0]) - (4.25 + 14.0)) < 0.01 and absf(float(b[3]) - (4.25 + 14.25)) < 0.01:
			east.append(bl.mat)
	assert_true(west.has("brick"), "face ouest du mur mitoyen en brique : %s" % str(west))
	assert_true(east.has("wall_green"), "face est du mur mitoyen en plâtre vert : %s" % str(east))
	assert_false(west.has("wall_green") or east.has("brick"), "chaque face garde la texture de sa pièce")


func test_format_1_maps_still_load() -> void:
	var texts := {
		"carte.json": '{"format": 1, "id": "ancienne", "nom": {"fr": "ANCIENNE", "en": "OLD"}, "etages": [{"sol": 0, "hauteur": 3.2}]}',
		"pieces.json": '{"pieces": [{"id": "p1", "nom": "Salle", "etage": 0, "zone": "z1", "contour": [[0,0],[16,0],[16,8],[0,8]]}]}',
		"ouvertures.json": '{"ouvertures": [{"id": "o1", "type": "fenetre", "etage": 0, "position": [2.25, 0]}]}',
		"objets.json": '{"objets": [{"id": "s1", "type": "depart", "etage": 0, "position": [12, 5]}, {"id": "c1", "type": "caisse", "etage": 0, "position": [2.25, 5.25]}, {"id": "l1", "type": "lampe", "etage": 0, "position": [5, 4]}, {"id": "b1", "type": "boite", "etage": 0, "position": [8.75, 8], "mur": "s"}]}',
		"zones.json": '{"depart": "z1", "zones": [{"id": "z1", "nom": {"fr": "Salle", "en": "Room"}, "sol": "wood"}]}',
	}
	var m := EditorMap.from_texts(texts)
	assert_true(m.load_errors.is_empty(), str(m.load_errors))
	assert_eq(m.format_read, 1, "format 1 reconnu")
	assert_eq(int(JSON.parse_string(m.file_texts()["carte.json"]).format), EditorMap.FORMAT, "réécrite au format %d" % EditorMap.FORMAT)
	assert_true(EditorMap.FORMAT >= 4, "format 4 et plus : formes libres (formes de base, rotations au degré près) ; 5 : variantes, barrière")
	var v := _check(m)
	assert_true(v.ok(), "ancienne carte toujours jouable :\n" + _errs(v))
	var da := EditorMap.load_dir("res://assets/maps/draft_arena/")
	assert_true(da.load_errors.is_empty() and da.format_read == 1, "DRAFT ARENA (format 1) se recharge")
	var newer := EditorMap.from_texts({"carte.json": '{"format": 99}'})
	assert_true(newer.load_errors.any(func(e): return String(e[0]).contains("plus récent")), "format plus récent signalé")


# ------------------------------------------------------------------ archives et identifiants (sécurité)

## Archive de test : {nom: contenu (String ou PackedByteArray)}.
static func _zip(path: String, files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var z := ZIPPacker.new()
	z.open(path)
	for name in files:
		z.start_file(String(name))
		var v = files[name]
		z.write_file(v if v is PackedByteArray else String(v).to_utf8_buffer())
		z.close_file()
	z.close()


func _refused(path: String, word: String) -> void:
	var m := EditorMap.import_zip(path)
	assert_false(m.load_errors.is_empty(), "%s : archive refusée" % path.get_file())
	if not m.load_errors.is_empty():
		assert_true(String(m.load_errors[0][0]).contains(word), "%s : %s" % [path.get_file(), m.load_errors[0][0]])
	assert_true(m.pieces.is_empty(), "rien n'est lu")


func test_archives_are_checked_before_reading() -> void:
	var dir := ProjectSettings.globalize_path(TMP + "/zips")
	var texts := _decorated().file_texts()
	# Archive correcte (à la racine, puis dans un dossier) : lue.
	_zip(dir + "/ok.zip", texts)
	var ok := EditorMap.import_zip(dir + "/ok.zip")
	assert_true(ok.load_errors.is_empty() and ok.same_as(_decorated()), "archive correcte relue : %s" % str(ok.load_errors))
	var nested := {}
	for f in texts:
		nested["decor/" + f] = texts[f]
	_zip(dir + "/dossier.zip", nested)
	assert_true(EditorMap.import_zip(dir + "/dossier.zip").load_errors.is_empty(), "archive avec un dossier : lue")
	# Trop grosse (données incompressibles de 2,1 Mo).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := PackedByteArray()
	noise.resize(2200000)
	@warning_ignore("integer_division")
	for i in noise.size() / 4:
		noise.encode_u32(i * 4, rng.randi())
	_zip(dir + "/grosse.zip", {"carte.json": noise})
	_refused(dir + "/grosse.zip", "trop grosse")
	# Bombe : petit fichier .zip, 3 Mo une fois décompressé.
	var zeros := PackedByteArray()
	zeros.resize(3 * 1024 * 1024)
	_zip(dir + "/bombe.zip", {"carte.json": zeros})
	assert_true(FileAccess.open(dir + "/bombe.zip", FileAccess.READ).get_length() < 100000, "bombe : archive minuscule")
	_refused(dir + "/bombe.zip", "trop gros")
	# Trop d'entrées.
	var many := {}
	for i in 40:
		many["f%d.json" % i] = "{}"
	_zip(dir + "/entrees.zip", many)
	_refused(dir + "/entrees.zip", "trop d'entrées")
	# Nom inattendu, chemin piégé, fichiers dans deux dossiers.
	var extra := texts.duplicate()
	extra["virus.exe"] = "MZ"
	_zip(dir + "/extra.zip", extra)
	_refused(dir + "/extra.zip", "inattendu")
	_zip(dir + "/chemin.zip", {"../carte.json": texts["carte.json"]})
	_refused(dir + "/chemin.zip", "chemin interdit")
	_zip(dir + "/deux.zip", {"a/carte.json": texts["carte.json"], "b/pieces.json": texts["pieces.json"]})
	_refused(dir + "/deux.zip", "inattendu")
	# Fichier qui n'est pas une archive.
	var fa := FileAccess.open(dir + "/faux.zip", FileAccess.WRITE)
	fa.store_string("pas une archive")
	fa.close()
	assert_false(EditorMap.import_zip(dir + "/faux.zip").load_errors.is_empty(), "faux .zip refusé")


func test_map_ids_are_slugs_only() -> void:
	assert_true(EditorMap.valid_id("ma_carte_2"))
	for bad in ["", "../x", "a/b", "a\\b", "Carte", "é", "x".repeat(49), "..", "c:"]:
		assert_false(EditorMap.valid_id(bad), "identifiant refusé : « %s »" % bad)
		assert_eq(EditorMap.map_dir(bad), "", "pas de dossier pour « %s »" % bad)
	assert_true(EditorMap.map_dir("ma_carte").ends_with("/ma_carte"))
	assert_eq(EditorMapDef.custom("perso:../../x"), null, "carte perso à chemin piégé : refusée")
	assert_false(Game.has_map("perso:../maps"), "le jeu ne la connaît pas")
	var long := EditorMap.slug("Une Très Longue Carte ".repeat(8))
	assert_true(EditorMap.valid_id(long) and EditorMap.valid_id(long + "_99"), "nom tiré d'un long titre : %s" % long)
	assert_false(EditorMap.is_map_dir(""), "dossier vide : pas une carte")
	# meta.json de la sauvegarde automatique : taille bornée.
	var dir := ProjectSettings.globalize_path(TMP + "/meta")
	DirAccess.make_dir_recursive_absolute(dir)
	var fa := FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	fa.store_string("{\"name\": \"%s\"}" % "x".repeat(300000))
	fa.close()
	assert_eq(MapEditor._read_meta(dir), {}, "meta.json de plus de 256 Ko ignoré")
	fa = FileAccess.open(dir.path_join("meta.json"), FileAccess.WRITE)
	fa.store_string("{\"name\": \"ok\"}")
	fa.close()
	assert_eq(MapEditor._read_meta(dir).get("name"), "ok")


# ------------------------------------------------------------------ catalogue (types admis)

func test_allowed_kinds_cover_the_catalog() -> void:
	var kinds := MapCatalog.allowed_kinds()
	for it in MapCatalog.items():
		var t := String(it.make.get("type", ""))
		if t == "":
			continue
		assert_true(kinds.has(t), "type %s déclaré" % t)
		for key in it.make:
			assert_true(kinds[t].keys.has(key), "clé %s de %s déclarée" % [key, t])
	assert_eq(kinds.prefab.keys.prefab.values, MapCatalog.PREFABS.keys(), "prefabs admis")
	assert_eq(kinds.luminaire.keys.luminaire.values, MapCatalog.LIGHTS.keys(), "luminaires admis")
	assert_eq(kinds.porte.file, "ouvertures.json")
	assert_eq(kinds.luminaire.file, "objets.json")
	var surfaces := WorldLook.SURFACES.keys()
	surfaces.sort()
	assert_eq(MapCatalog.allowed_surfaces(), surfaces, "surfaces admises = WorldLook.SURFACES")
	for key in ["surface_sol", "surface_murs", "surface_plafond"]:
		assert_eq(MapCatalog.room_keys()[key].values, surfaces, "%s : une surface du jeu" % key)
	assert_true(MapCatalog.zone_keys().has("plafond"))
	# Toutes les clés écrites par l'éditeur pour la carte décorée sont admises.
	var doc := _decorated()
	for o in doc.objets + doc.ouvertures:
		for key in o:
			assert_true(kinds[String(o.type)].keys.has(key), "%s.%s admise" % [o.type, key])
	for p in doc.pieces:
		for key in p:
			assert_true(MapCatalog.room_keys().has(key), "pièce.%s admise" % key)


# ------------------------------------------------------------------ jeu

func test_playable_build_with_props_lights_and_textures() -> void:
	var def := EditorMapDef.from_map(_decorated(), "perso:decor")
	assert_true(def.is_valid(), "carte décorée jouable :\n" + _errs(def.validator))
	var data := def.layout_data
	assert_eq(data.props.size(), 4, "4 décors : %s" % str(data.props.map(func(p): return p.get("model", p.get("build", "")))))
	var sand: Dictionary = data.props.filter(func(p): return p.get("build", "") == "sacs_sable")[0]
	assert_near(float(sand.yaw), -PI / 2, 0.01, "sacs de sable pivotés de 90°")
	assert_true(data.blockers.size() >= 2, "collisions du décor (CollisionBox) : %d" % data.blockers.size())
	var fixtures: Array = data.markers.lamps.filter(func(l): return l.has("fixture"))
	assert_eq(fixtures.size(), 4, "4 luminaires")
	var blue: Dictionary = fixtures.filter(func(l): return l.fixture == "applique")[0]
	assert_eq(String(blue.color), "40a0ff", "couleur de l'applique")
	var fire: Dictionary = fixtures.filter(func(l): return l.fixture == "feu")[0]
	assert_true(fire.flicker and not fire.power, "feu : vacille, allumé sans courant")
	# Construction par le jeu : décor, collisions, lampes et matériaux.
	var world := Node3D.new()
	host.add_child(world)
	var mb := MeshMapBuilder.new(data, "")
	mb.build(world)
	var boxes := world.find_children("*", "CollisionBox", true, false)
	assert_true(boxes.size() >= data.blockers.size(), "collisions en CollisionBox : %d" % boxes.size())
	var lights := world.find_children("*", "OmniLight3D", true, false)
	var colored := lights.filter(func(l): return (l as OmniLight3D).light_color.is_equal_approx(Color.html("#40a0ff")))
	assert_eq(colored.size(), 1, "applique bleue")
	var names := world.find_children("*", "MeshInstance3D", true, false).map(func(n): return String(n.name))
	for mat in ["brick", "wall_green", "tiles", "wood"]:
		assert_true(names.any(func(n): return n.begins_with(mat + "__")), "matériau %s construit" % mat)
	# Pas de collision venue d'un modèle Blender : seulement des CollisionBox et l'architecture.
	for body in world.find_children("*", "StaticBody3D", true, false):
		assert_true(body is CollisionBox or String(body.name).ends_with("__col"), "collision %s" % body.name)
	# Courant : le feu reste allumé, l'applique s'éteint à moitié.
	mb.power.apply_immediate(false)
	var fire_l: OmniLight3D = lights.filter(func(l): return l.position.distance_to(Vector3(fire.p[0], fire.p[1], fire.p[2])) < 0.01)[0]
	assert_near(fire_l.light_energy, float(fire.energy), 0.01, "feu hors du réseau électrique")
	world.queue_free()
	await wait_frames(1)
