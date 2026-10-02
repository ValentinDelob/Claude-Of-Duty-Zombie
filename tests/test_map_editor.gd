extends TestCase
## Éditeur de cartes (scripts/editor/, docs/MAP_AUTHORING.md) : règles de
## pose (porte seulement entre deux pièces collées, fenêtre seulement sur un
## mur extérieur, objets contre un mur ou dans une pièce), murs mitoyens,
## annuler / rétablir, sauvegarde et archive .zip relues à l'identique,
## conversion en carte jouable (géométrie construite par le jeu) et DRAFT
## ARENA migrée dans le nouveau format.

const TMP := "res://tests/_out/test_map_editor"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


# ------------------------------------------------------------------ outils

static func _room(doc: EditorMap, x0: float, y0: float, x1: float, y1: float, k := 0, zone := "") -> Dictionary:
	var id := doc.new_id("p")
	var z := zone
	if z == "":
		z = String(doc.add_zone("Salle " + id, "Room " + id).id)
	var r := {"id": id, "nom": "Salle " + id, "etage": k, "zone": z,
		"contour": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]}
	doc.pieces.append(r)
	return r


static func _obj(doc: EditorMap, o: Dictionary, k := 0) -> Dictionary:
	o["id"] = doc.new_id("x")
	o["etage"] = k
	doc.objets.append(o)
	return o


static func _open(doc: EditorMap, o: Dictionary, k := 0) -> Dictionary:
	o["id"] = doc.new_id("o")
	o["etage"] = k
	doc.ouvertures.append(o)
	return o


## Deux salles collées (A : départ, 14 × 10 m ; B : 10 × 10 m), une porte,
## une fenêtre chacune, une boîte, une arme, un atout, le départ.
static func _base() -> EditorMap:
	var doc := EditorMap.blank("test_editeur", "TEST", "TEST")
	_room(doc, 0, 0, 14, 10)
	_room(doc, 14, 0, 24, 10)
	doc.depart = String(doc.zones[0].id)
	_open(doc, {"type": "porte", "position": [14.0, 5.25], "largeur": 2.0, "prix": 750})
	_open(doc, {"type": "fenetre", "position": [3.25, 0.0]})
	_open(doc, {"type": "fenetre", "position": [19.25, 0.0]})
	_obj(doc, {"type": "depart", "position": [9.0, 7.0]})
	_obj(doc, {"type": "boite", "position": [6.75, 10.0], "mur": "s", "depart": false})
	_obj(doc, {"type": "arme", "arme": "m14", "position": [11.25, 10.0], "mur": "s"})
	_obj(doc, {"type": "atout", "atout": "titan", "position": [24.0, 5.0], "mur": "e"})
	return doc


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


# ------------------------------------------------------------------ géométrie et murs

func test_common_edges_of_touching_rooms() -> void:
	var a := MapGeom.rect_poly(Rect2(0, 0, 10, 8))
	var b := MapGeom.rect_poly(Rect2(10, 2, 6, 10))
	var c := MapGeom.rect_poly(Rect2(11, 0, 4, 1))
	var common := MapGeom.common_segments(a, b)
	assert_eq(common.size(), 1, "un bord commun")
	assert_true(common[0][0].is_equal_approx(Vector2(10, 2)) and common[0][1].is_equal_approx(Vector2(10, 8)), "bord commun x = 10, y 2 à 8 : %s" % str(common))
	assert_true(MapGeom.common_segments(a, c).is_empty(), "pièces séparées : aucun bord commun")
	assert_false(MapGeom.overlap(a, b), "collées ne veut pas dire superposées")
	assert_true(MapGeom.overlap(a, MapGeom.rect_poly(Rect2(9, 0, 4, 4))), "chevauchement détecté")


func test_shared_wall_is_a_single_wall() -> void:
	var doc := _base()
	var f: MapValidator.Floor = MapRaster.build(doc).v.floors[0]
	# Mur commun x = 14 m (case 28) : un seul mur de 0,5 m, du sol de chaque côté.
	var y := 4   # y = 2 m
	assert_eq(f.at(Vector2i(28, y)), MapValidator.K.MUR, "mur mitoyen sur le bord commun")
	assert_eq(f.at(Vector2i(27, y)), MapValidator.K.SOL, "sol de A juste à côté")
	assert_eq(f.at(Vector2i(29, y)), MapValidator.K.SOL, "sol de B juste à côté")
	assert_true(f.zone_of(Vector2i(27, y)) != f.zone_of(Vector2i(29, y)), "deux zones différentes")
	# Murs extérieurs sur le contour, porte dans le mur commun.
	assert_eq(f.at(Vector2i(0, 4)), MapValidator.K.MUR, "mur extérieur ouest sur le contour")
	assert_eq(f.at(Vector2i(28, 10)), MapValidator.K.PORTE, "porte dans le mur commun")
	assert_eq(f.at(Vector2i(6, 0)), MapValidator.K.FENETRE, "fenêtre dans le mur nord")


func test_valid_map_is_accepted() -> void:
	var v := _check(_base())
	assert_true(v.ok(), "carte correcte acceptée :\n" + _errs(v))
	assert_eq(v.zones, ["a", "b"], "zone de départ = a")
	assert_eq(v.doors.size(), 1)
	assert_eq(v.doors[0].cost, 750)
	assert_eq(v.windows.size(), 2)


# ------------------------------------------------------------------ règles de pose

func test_door_needs_two_touching_rooms() -> void:
	var doc := EditorMap.blank()
	_room(doc, 0, 0, 10, 10)
	var r := MapRules.place_opening(doc, 0, "porte", Vector2(10, 5), 2.0)
	assert_false(r.ok, "une seule pièce : porte refusée")
	assert_true(String(r.fr).contains("deux pièces collées"), "raison : %s" % r.fr)
	# Deux pièces séparées d'un mètre : toujours refusée.
	_room(doc, 11, 0, 20, 10)
	r = MapRules.place_opening(doc, 0, "porte", Vector2(10.5, 5), 2.0)
	assert_false(r.ok, "pièces qui ne se touchent pas : porte refusée (%s)" % r.get("fr", ""))
	# Collées : acceptée sur le bord commun, elle relie exactement ces deux pièces.
	var doc2 := EditorMap.blank()
	var a := _room(doc2, 0, 0, 10, 10)
	var b := _room(doc2, 10, 2, 18, 8)
	r = MapRules.place_opening(doc2, 0, "porte", Vector2(10.4, 5.2), 2.0)
	assert_true(r.ok, "porte acceptée sur le bord commun : %s" % r.get("fr", ""))
	assert_eq(r.position, [10.0, 5.25], "accrochée sur le mur commun (x = 10) ; 4 cases : milieu à 0,25 m de la grille")
	assert_eq(r.rooms, [String(a.id), String(b.id)], "relie les deux pièces")
	# Sur un mur extérieur de A : refusée.
	r = MapRules.place_opening(doc2, 0, "porte", Vector2(0.2, 5), 2.0)
	assert_false(r.ok, "porte sur un mur extérieur refusée")
	# Bord commun trop court (0,5 m de mur de chaque côté).
	r = MapRules.place_opening(doc2, 0, "porte", Vector2(10, 5), 6.0)
	assert_false(r.ok, "porte plus large que le bord commun refusée")


func test_door_margins_and_other_openings() -> void:
	var doc := EditorMap.blank()
	_room(doc, 0, 0, 10, 10)
	_room(doc, 10, 0, 20, 10)
	var r := MapRules.place_opening(doc, 0, "porte", Vector2(10, 0.1), 2.0)
	assert_true(r.ok, "porte près d'un coin : ramenée à 0,5 m du bout")
	assert_eq(r.position, [10.0, 1.75], "0,5 m de mur plein au bout")
	_open(doc, {"type": "porte", "position": r.position, "largeur": 2.0, "prix": 750})
	r = MapRules.place_opening(doc, 0, "debris", Vector2(10, 3.0), 2.0)
	assert_false(r.ok, "deux ouvertures collées refusées")
	assert_true(String(r.fr).contains("trop près"), r.get("fr", ""))


func test_window_only_on_an_outer_wall() -> void:
	var doc := EditorMap.blank()
	_room(doc, 0, 0, 10, 10)
	_room(doc, 10, 0, 20, 10)
	var r := MapRules.place_opening(doc, 0, "fenetre", Vector2(10, 5), 1.0)
	assert_false(r.ok, "fenêtre refusée sur le mur commun")
	r = MapRules.place_opening(doc, 0, "fenetre", Vector2(5, -0.3), 1.0)
	assert_true(r.ok, "fenêtre acceptée sur le mur extérieur nord : %s" % r.get("fr", ""))
	assert_eq(r.position, [5.25, 0.0], "fenêtre de 1 m : deux cases")
	# Une pièce juste derrière : pas de place pour les zombies.
	_room(doc, 3, -6, 8, -1.5)
	r = MapRules.place_opening(doc, 0, "fenetre", Vector2(5, -0.3), 1.0)
	assert_false(r.ok, "pas de place dehors : refusée")


func test_wall_items_stand_against_a_wall() -> void:
	var doc := EditorMap.blank()
	_room(doc, 0, 0, 12, 10)
	var perk := {"type": "atout", "atout": "titan"}
	var r := MapRules.place_wall_item(doc, 0, perk, Vector2(6.2, 0.8))
	assert_true(r.ok, "atout contre le mur nord : %s" % r.get("fr", ""))
	assert_eq(r.mur, "n", "face vers l'intérieur (mur au nord)")
	assert_eq(r.position, [6.0, 0.0], "posé sur le trait du mur, 3 cases : milieu sur la grille")
	r = MapRules.place_wall_item(doc, 0, perk, Vector2(6, 5))
	assert_false(r.ok, "au milieu de la pièce, loin des murs : refusé")
	r = MapRules.place_wall_item(doc, 0, perk, Vector2(-3, 5))
	assert_false(r.ok, "hors de toute pièce : refusé")
	_obj(doc, {"type": "atout", "atout": "titan", "position": [6.0, 0.0], "mur": "n"})
	r = MapRules.place_wall_item(doc, 0, {"type": "arme", "arme": "m14"}, Vector2(6.5, 0.6))
	assert_false(r.ok, "chevauche l'atout : refusé")
	assert_true(String(r.fr).contains("chevauche"), r.get("fr", ""))
	# Une ouverture dans le mur : pas de mur plein derrière.
	_room(doc, 12, 0, 20, 10)
	_open(doc, {"type": "porte", "position": [12.0, 5.0], "largeur": 2.0, "prix": 750})
	r = MapRules.place_wall_item(doc, 0, {"type": "arme", "arme": "m14"}, Vector2(11.4, 5.0))
	assert_false(r.ok, "arme devant une porte refusée")


func test_floor_items_inside_a_room_without_overlap() -> void:
	var doc := EditorMap.blank()
	_room(doc, 0, 0, 10, 10)
	var r := MapRules.place_floor_item(doc, 0, {"type": "depart"}, Vector2(5.2, 4.9))
	assert_true(r.ok, "départ dans la pièce")
	assert_eq(r.position, [5.0, 5.0])
	r = MapRules.place_floor_item(doc, 0, {"type": "depart"}, Vector2(0.1, 5))
	assert_false(r.ok, "sur le mur : refusé")
	r = MapRules.place_floor_item(doc, 0, {"type": "depart"}, Vector2(15, 5))
	assert_false(r.ok, "dehors : refusé")
	_obj(doc, {"type": "caisse", "position": [5.25, 5.25]})
	r = MapRules.place_floor_item(doc, 0, {"type": "apparition"}, Vector2(5.0, 5.0))
	assert_false(r.ok, "chevauche la caisse : refusé")
	var s := MapRules.check_rect(doc, 0, "escalier", Rect2(1, 1, 2, 5))
	assert_false(s.ok, "escalier sans étage au-dessus refusé")
	assert_true(String(s.fr).contains("ajoutez d'abord un étage"), s.get("fr", ""))


func test_rooms_may_touch_but_not_overlap() -> void:
	var doc := EditorMap.blank()
	_room(doc, 0, 0, 10, 10)
	assert_true(MapRules.check_room(doc, 0, MapGeom.rect_poly(Rect2(10, 0, 5, 5))).ok, "pièce collée acceptée")
	var r := MapRules.check_room(doc, 0, MapGeom.rect_poly(Rect2(8, 0, 5, 5)))
	assert_false(r.ok, "pièce qui en recouvre une autre refusée")
	assert_true(String(r.fr).contains("chevauche"), r.get("fr", ""))
	assert_true(MapRules.check_room(doc, 1, MapGeom.rect_poly(Rect2(8, 0, 5, 5))).ok, "à un autre étage : acceptée")
	assert_false(MapRules.check_room(doc, 0, MapGeom.rect_poly(Rect2(20, 0, 1, 1))).ok, "trop petite")


# ------------------------------------------------------------------ validateur

func test_validator_errors_point_at_the_problem() -> void:
	# Pièce B sans porte : inaccessible.
	var doc := _base()
	doc.ouvertures = doc.ouvertures.filter(func(o): return o.type != "porte")
	var v := _check(doc)
	assert_false(v.ok())
	assert_true(_errs(v).contains("inaccessible depuis le départ"), _errs(v))
	# Zone sans fenêtre.
	doc = _base()
	doc.ouvertures = doc.ouvertures.filter(func(o): return not (o.type == "fenetre" and float(o.position[0]) > 14.0))
	v = _check(doc)
	assert_true(_errs(v).contains("sans fenêtre"), _errs(v))
	# Porte entre deux pièces de la même zone.
	doc = _base()
	doc.pieces[1]["zone"] = doc.pieces[0].zone
	doc.tidy_zones()
	v = _check(doc)
	assert_true(_errs(v).contains("même zone"), _errs(v))
	# Départ collé à une fenêtre de la zone de départ : plus une erreur (les
	# zombies des fenêtres n'ont plus de distance minimale aux joueurs, comme
	# dans BO1 : ils viennent aussi à la fenêtre où l'on se tient), seulement
	# un avertissement.
	doc = _base()
	doc.objets[0]["position"] = [3.0, 1.5]
	v = _check(doc)
	assert_true(v.ok(), "départ près des fenêtres : pas d'erreur\n" + _errs(v))
	assert_false(_errs(v).contains("à moins de 7 m"), _errs(v))
	var near: Array = v.warnings().filter(func(m): return String(m.fr).contains("les premiers zombies arrivent aussitôt"))
	assert_eq(near.size(), 1, "avertissement : fenêtre collée au départ")
	# Message bilingue avec la distance en mètres.
	var m: Dictionary = near[0] if not near.is_empty() else {"fr": "", "en": ""}
	assert_true(String(m.fr) != String(m.en) and String(m.en).contains("m from a window"), "message FR et EN")


func test_passage_merges_or_links_zones() -> void:
	var doc := _base()
	doc.ouvertures[0]["type"] = "passage"
	doc.ouvertures[0].erase("prix")
	var v := _check(doc)
	assert_true(v.ok(), _errs(v))
	assert_eq(v.doors.size(), 0, "passage libre : pas de porte")
	assert_eq(v.open_links.get("a", []), ["b"], "zones ouvertes l'une sur l'autre")


func test_stairs_mezzanine_and_double_height() -> void:
	var doc := _base()
	doc.carte.etages.append({"sol": 3.5, "hauteur": 3.2})
	doc.pieces[0]["double_hauteur"] = true
	# Mezzanine au-dessus du nord de A, escalier qui y monte.
	var up := _room(doc, 0, 0, 5, 5, 1)
	_open(doc, {"type": "fenetre", "position": [2.25, 0.0]}, 1)
	_obj(doc, {"type": "escalier", "rect": [0.0, 4.5, 2.0, 9.5], "monte": "n"})
	var r := MapRaster.build(doc)
	var f1: MapValidator.Floor = r.v.floors[1]
	assert_eq(f1.at(Vector2i(20, 12)), MapValidator.K.TREMIE, "vide au-dessus de la double hauteur")
	assert_eq(f1.at(Vector2i(0, 12)), MapValidator.K.MUR, "le mur de la double hauteur monte à l'étage")
	assert_eq(f1.at(Vector2i(10, 4)), MapValidator.K.SOL, "bord de la mezzanine au-dessus du vide : plancher (garde-corps)")
	var v := r.v
	v.analyze()
	assert_true(v.ok(), "étage, mezzanine et escalier acceptés :\n" + _errs(v))
	assert_eq(v.stairs.size(), 1)
	assert_eq(v.stairs[0].up, Vector2i(0, -1), "monte vers le nord")
	var lay := MapLayoutExport.build(v)
	assert_true(lay.rails.size() >= 2, "garde-corps au bord de la mezzanine (%d)" % lay.rails.size())
	assert_eq(float(lay.stairs[0].b[1]), 3.5, "haut de l'escalier au sol de l'étage")
	assert_true(String(up.id) != "", "")


# ------------------------------------------------------------------ fichiers

func test_json_files_are_readable() -> void:
	var texts := _base().file_texts()
	assert_eq(texts.keys(), EditorMap.FILES, "cinq fichiers")
	var pieces: String = texts["pieces.json"]
	assert_eq(pieces.split("\n").size(), 4 + 2, "une pièce par ligne (2 pièces) :\n" + pieces)
	for f in texts:
		assert_true(JSON.parse_string(texts[f]) is Dictionary, "%s : JSON valide" % f)
	assert_eq(int(JSON.parse_string(texts["carte.json"]).format), EditorMap.FORMAT, "version du format")


func test_save_and_reload_identical() -> void:
	var doc := _base()
	var dir := ProjectSettings.globalize_path(TMP + "/saved")
	assert_eq(doc.save_dir(dir), OK)
	var back := EditorMap.load_dir(dir)
	assert_true(back.load_errors.is_empty(), str(back.load_errors))
	assert_true(back.same_as(doc), "relue à l'identique")
	assert_eq(int(back.find("o1").prix), 750, "prix relu")
	var v := _check(back)
	assert_true(v.ok(), "carte relue toujours valide :\n" + _errs(v))


func test_zip_export_import_identical() -> void:
	var doc := _base()
	var path := ProjectSettings.globalize_path(TMP + "/carte.zip")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	assert_eq(doc.export_zip(path), OK)
	var r := ZIPReader.new()
	assert_eq(r.open(path), OK)
	var files := Array(r.get_files())
	files.sort()
	r.close()
	var want := EditorMap.FILES.duplicate()
	want.sort()
	assert_eq(files, want, "archive : les cinq JSON")
	var back := EditorMap.import_zip(path)
	assert_true(back.load_errors.is_empty(), str(back.load_errors))
	assert_true(back.same_as(doc), "archive relue à l'identique")


func test_hand_written_json_is_read() -> void:
	var texts := {
		"carte.json": '{"format": 1, "id": "main", "nom": {"fr": "À LA MAIN", "en": "BY HAND"}, "etages": [{"sol": 0, "hauteur": 3}]}',
		"pieces.json": '{"pieces": [{"id": "a", "nom": "Salle", "etage": 0, "zone": "z", "contour": [[0,0],[8,0],[8,6],[0,6]]}]}',
		"ouvertures.json": '{"ouvertures": []}', "objets.json": '{"objets": []}',
		"zones.json": '{"depart": "z", "zones": [{"id": "z", "nom": {"fr": "Salle", "en": "Room"}}]}',
	}
	var m := EditorMap.from_texts(texts)
	assert_true(m.load_errors.is_empty(), str(m.load_errors))
	assert_eq(m.rooms_on(0).size(), 1)
	assert_true(m.pieces[0].etage is int, "étage entier")
	var bad := EditorMap.from_texts({"carte.json": "{ pas du json"})
	assert_false(bad.load_errors.is_empty(), "fichier illisible signalé")


## Identifiant en double (carte « Quai 13 ») : réparé à la lecture, sinon le
## contrôle du jeu refuse la carte et TESTER démarre sur la carte par défaut.
func test_duplicate_ids_are_repaired() -> void:
	var doc := _base()
	var p := _obj(doc, {"type": "prefab", "prefab": "etagere", "position": [3, 3], "rot": 0})
	var q := _obj(doc, {"type": "prefab", "prefab": "planches", "position": [5, 3], "rot": 0})
	p["id"] = "d6"
	q["id"] = "d6"
	var texts := doc.file_texts()
	assert_false(CustomMapGuard.check_texts(texts).ok, "doublon refusé par le contrôle du jeu")
	var back := EditorMap.from_texts(texts)
	var ids := {}
	for list in [back.pieces, back.ouvertures, back.objets, back.zones]:
		for e in list:
			assert_false(ids.has(String(e.id)), "identifiant unique : %s" % e.id)
			ids[String(e.id)] = true
	assert_true(ids.has("d6") and ids.has("d1"), "le second reçoit le premier numéro libre du même préfixe")
	assert_true(CustomMapGuard.check_texts(back.file_texts()).ok, "carte réparée acceptée :\n%s" % CustomMapGuard.reasons_text(CustomMapGuard.check_texts(back.file_texts()).reasons))


# ------------------------------------------------------------------ éditeur (annuler / rétablir)

func test_undo_redo_in_the_editor() -> void:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(2)
	ed.new_map(true)
	var room := ed.add_object({"contour": [[2, 2], [10, 2], [10, 8], [2, 8]]}, 0)
	ed.add_object({"contour": [[10, 2], [16, 2], [16, 8], [10, 8]]}, 0)
	assert_eq(ed.doc.pieces.size(), 2)
	assert_eq(ed.doc.zones.size(), 2, "une zone par pièce par défaut")
	var door := MapRules.place_opening(ed.doc, 0, "porte", Vector2(10, 5), 2.0)
	assert_true(door.ok, str(door))
	ed.add_object({"type": "porte", "position": door.position, "largeur": 2.0}, 0)
	assert_eq(int(ed.doc.ouvertures[0].prix), 750, "première porte à 750 (BO1)")
	ed.merge_zones(String(ed.doc.zones[1].id), String(ed.doc.zones[0].id))
	assert_eq(ed.doc.zones.size(), 1, "zones fusionnées")
	for i in 3:
		ed.undo()
	assert_eq(ed.doc.pieces.size(), 1, "annuler x3 : une pièce")
	assert_eq(ed.doc.ouvertures.size(), 0)
	for i in 3:
		ed.redo()
	assert_eq(ed.doc.zones.size(), 1, "rétablir x3 : zones de nouveau fusionnées")
	assert_eq(ed.doc.ouvertures.size(), 1)
	ed.select(String(room.id))
	ed.rotate_selected()
	assert_eq(MapGeom.bbox(ed.doc.room_poly(ed.doc.find(String(room.id)))).size, Vector2(6, 8), "pièce pivotée de 90°")
	ed.undo()
	ed.delete_element(String(room.id))
	assert_eq(ed.doc.ouvertures.size(), 0, "la porte de la pièce part avec elle")
	ed.undo()
	assert_eq(ed.doc.ouvertures.size(), 1, "annuler la suppression")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ conversion et jeu

func test_catalog_comes_from_the_game_databases() -> void:
	for pid in PerkDB.PERKS:
		assert_false(MapCatalog.item("atout:" + pid).is_empty(), "atout %s dans l'inventaire" % pid)
	for wid in WeaponDB.WEAPONS:
		assert_eq(MapCatalog.item("arme:" + wid).is_empty(), WeaponDB.wall_cost(wid) == 0, "arme %s au mur ssi elle a un prix mural" % wid)
	assert_eq(int(MapCatalog.item("arme:bowie").price), KnifeDB.wall_cost("bowie"), "couteau de chasse")
	assert_eq(int(MapCatalog.item("boite").price), MysteryBox.COST)
	for c in MapCatalog.CATEGORIES:
		# Prefabs de la carte (format 10) : vide tant que la carte n'en a pas.
		if String(c[0]) == MapCatalog.MAP_CAT:
			continue
		assert_false(MapCatalog.in_category(String(c[0])).is_empty(), "catégorie %s remplie" % c[0])
	assert_near(MapValidator.SILL, Barricade.SILL_TOP, 0.0001, "allège des fenêtres")
	assert_near(MapValidator.LINTEL, Barricade.LINTEL_BOTTOM, 0.0001, "linteau des fenêtres")
	assert_near(MapValidator.MIN_SPAWN_DIST, Spawner.MIN_PLAYER_DIST, 0.0001, "distance mini d'apparition")


func test_conversion_to_a_playable_map() -> void:
	var def := EditorMapDef.from_map(_base(), "perso:test")
	assert_true(def.is_valid(), "carte convertie :\n" + _errs(def.validator))
	assert_eq(def.doors, {"1": {"cost": 750}}, "prix des portes")
	assert_eq(def.zone_names.get("a"), Lang.t("Salle p1", "Room p1"), "noms des zones")
	var layout := def.create_layout() as MeshMapLayout
	assert_true(layout != null and layout.is_multilevel(), "carte en maillage")
	assert_eq(layout.windows().size(), 2)
	assert_eq(layout.doors().size(), 1)
	assert_eq(layout.player_spawns().size(), 4, "4 départs autour du point")
	assert_eq(layout.perks()[0].data.perk, "titan")
	assert_eq(layout.wall_buys()[0].data.weapon, "m14")
	assert_eq(layout.box_spots().size(), 1)
	assert_eq(layout.zone_at(Vector3(4.25 + 5.0, 0.0, 4.25 + 5.0)), "a", "repère du jeu = éditeur + 4,25 m")
	assert_eq(layout.zone_at(Vector3(4.25 + 19.0, 0.0, 4.25 + 5.0)), "b")
	# Géométrie construite par le jeu (sans Blender) : visibles + collisions.
	var arch := MeshMapGeometry.build(layout.data)
	var meshes := arch.find_children("*", "MeshInstance3D", true, false)
	var bodies := arch.find_children("*", "StaticBody3D", true, false)
	assert_true(meshes.size() > 5 and bodies.size() > 5, "%d maillages, %d collisions" % [meshes.size(), bodies.size()])
	for n in meshes:
		assert_eq(String(n.name).split("__").size(), 3, "nom <matériau>__<salle>__<type> : %s" % n.name)
	# Faces avant dans le sens horaire (Godot) : le sol est vu d'en haut.
	var floor_mesh: MeshInstance3D = null
	for n in meshes:
		if String(n.name).ends_with("__floor"):
			floor_mesh = n
			break
	var arrays := floor_mesh.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_true((v[1] - v[0]).cross(v[2] - v[0]).dot(Vector3.UP) < 0.0, "sol tourné vers le haut")
	arch.free()


func test_draft_arena_migrated() -> void:
	var doc := EditorMap.load_dir("res://assets/maps/draft_arena/")
	assert_true(doc.load_errors.is_empty(), str(doc.load_errors))
	var v := _check(doc)
	assert_true(v.ok(), "DRAFT ARENA valide :\n" + _errs(v))
	assert_eq(v.warnings().size(), 0, "aucun avertissement : %s" % str(v.warnings().map(func(m): return m.fr)))
	assert_eq(v.windows.size(), 7, "7 fenêtres")
	assert_eq(v.zones, ["a", "b", "c", "d", "e"])
	assert_eq(v.doors.map(func(d): return [d.id, d.cost, d.debris]), [["1", 1000, false], ["2", 1250, true], ["3", 750, false]])
	assert_eq(v.open_links.get("c", []), ["d", "e"], "entrepôt, atelier et passerelle ouverts l'un sur l'autre")
	var def: MapDef = load(Game.MAP_SCRIPTS["draft_arena"]).new()
	assert_true(def is EditorMapDef and (def as EditorMapDef).is_valid(), "script de carte : carte de l'éditeur")
	assert_eq(def.zone_names.get("c"), "Entrepôt", "réglages lus dans la carte")
	assert_eq(def.doors.get("3", {}).get("cost"), 750)
	assert_eq(def.box_start, 1, "boîte de départ : le couloir")
	assert_false(Game.MENU_MAPS.has("draft_arena"), "carte de test, hors menus")
	var layout := def.create_layout() as MeshMapLayout
	assert_eq(layout.glb_path, "", "géométrie construite par le jeu (plus de .glb)")
	assert_true(layout.data.rooms.size() > 20, "salles (%d)" % layout.data.rooms.size())
	assert_eq(layout.data.stairs.size(), 1, "escalier")


func test_custom_maps_are_found_by_the_game() -> void:
	var doc := _base()
	var dir := EditorMap.map_dir("ma_carte")
	assert_eq(doc.save_dir(dir), OK)
	assert_true(Game.has_map("perso:ma_carte"), "carte perso connue du jeu")
	assert_false(Game.has_map("perso:inconnue"))
	var def := Game.make_map_def("perso:ma_carte") as EditorMapDef
	assert_true(def != null and def.is_valid() and def.id == "perso:ma_carte", "carte perso chargée")
	assert_eq(EditorMap.list_maps().map(func(m): return m.id), ["ma_carte"], "liste des cartes")
