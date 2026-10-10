extends TestCase
## Revue de l'éditeur (boîte au sol, barrières invisibles, cartes écrites à
## la main) : une boîte posée au sol est PLEINE pour le parcours (couloir
## bouché, départ collé) et refusée à la pose si elle bouche un couloir ; un
## objet indispensable enfermé par une barrière invisible est une erreur (les
## autres : un avertissement) ; une carte sans « format » garde ses boîtes
## murales d'avant.

const DecorFree := preload("res://tests/test_map_decor_free.gd")
## Milieu du couloir de corridor_map (y, m).
const MID := 5.125


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


static func _fr(msgs: Array) -> String:
	return "\n".join(msgs.map(func(m): return String(m.fr)))


static func _clip(doc: EditorMap, pts: Array) -> void:
	doc.objets.append({"id": doc.new_id("i"), "type": "bloc_invisible", "altitude": 0, "sommets": pts})


## Salle A (0..10 × 0..10, départ, fenêtre, boîte murale), couloir de
## 2,75 m (10..22 × 3,75..6,5 : 2,25 m entre les faces des murs, une boîte
## de 2 m le couvre sur toute sa largeur de cases) et salle B (22..32 × 0..10), une seule zone, reliés
## par des passages libres.
static func corridor_map() -> EditorMap:
	var doc := EditorMap.blank("couloir", "COULOIR", "CORRIDOR")
	var a := DecorFree._room(doc, 0, 0, 10, 10, "brick")
	var c := DecorFree._room(doc, 10, 3.75, 22, 6.5, "brick")
	var b := DecorFree._room(doc, 22, 0, 32, 10, "brick")
	c.zone = a.zone
	b.zone = a.zone
	doc.zones = doc.zones.filter(func(z): return String(z.id) == String(a.zone))
	doc.depart = String(a.zone)
	doc.ouvertures.append({"id": "o1", "type": "passage", "altitude": 0, "position": [10.0, MID], "largeur": 2.0})
	doc.ouvertures.append({"id": "o2", "type": "passage", "altitude": 0, "position": [22.0, MID], "largeur": 2.0})
	doc.ouvertures.append({"id": "o3", "type": "fenetre", "altitude": 0, "position": [3.25, 0.0]})
	DecorFree._obj(doc, {"type": "depart", "position": [5.0, 6.0]})
	DecorFree._obj(doc, {"type": "boite", "position": [5.0, 10.0], "mur": "s", "depart": true})
	return doc


# ------------------------------------------------------------------ 1. boîte au sol pleine

func test_box_across_a_corridor_is_an_error() -> void:
	var doc := corridor_map()
	assert_eq(_fr(_check(doc).errors()), "", "carte de base sans erreur")
	# En travers du couloir (2 m sur 2,25 m, 0,125 m de chaque côté) : bouché.
	# Avant : ses cases restaient du sol marchable, aucune erreur.
	DecorFree._obj(doc, {"type": "boite", "position": [16.0, MID], "rot": 90, "depart": false})
	var v := _check(doc)
	assert_true(v.errors().any(func(m): return String(m.fr).contains("bouche le passage")),
		"boîte qui bouche le couloir : erreur\n%s" % _fr(v.errors()))


func test_box_blocking_a_corridor_refused_when_placed() -> void:
	var doc := corridor_map()
	for rot in [90, 0, 30]:
		var r := MapRules.place_box(doc, 0, {"type": "boite", "depart": false, "rot": rot}, Vector2(16.0, MID), "", false, false)
		assert_false(r.ok, "couloir de 2,75 m, rot %d : refusée" % rot)
		assert_true(MapRules.why(r).contains("bouche le passage") or MapRules.why(r).contains("mur"), "raison : %s" % MapRules.why(r))
	var r90 := MapRules.place_box(doc, 0, {"type": "boite", "depart": false, "rot": 90}, Vector2(16.0, MID), "", false, false)
	assert_true(MapRules.why(r90).contains("bouche le passage"), "rot 90 : le passage (%s)" % MapRules.why(r90))
	# Grande salle : acceptée, au milieu comme près d'un seul mur.
	for p in [Vector2(5.0, 4.0), Vector2(27.0, 1.2), Vector2(26.0, 5.0)]:
		var ok := MapRules.place_box(doc, 0, {"type": "boite", "depart": false, "rot": 0}, p, "", false, false)
		assert_true(ok.ok, "salle en %s : acceptée (%s)" % [p, MapRules.why(ok)])


func test_box_in_a_large_room_is_fine() -> void:
	var doc := corridor_map()
	DecorFree._obj(doc, {"type": "boite", "position": [27.0, 5.0], "rot": 90, "depart": false})
	var v := _check(doc)
	assert_eq(_fr(v.errors()), "", "boîte au milieu de B : aucune erreur")
	var fm: Dictionary = preload("res://tests/test_mystery_box_floor.gd").floor_map(0)
	assert_eq(_fr(_check(fm.doc).errors()), "", "boîte au sol dans une grande salle : aucune erreur")


func test_box_next_to_the_single_start_is_an_error() -> void:
	var doc := DecorFree.two_rooms()
	assert_eq(_fr(_check(doc).errors()), "", "carte de base sans erreur")
	# Départ en (7, 6) : ses apparitions (± 0,6 m) touchent la boîte (6..8 × 4..5).
	DecorFree._obj(doc, {"type": "boite", "position": [7.0, 4.5], "rot": 0, "depart": false})
	var v := _check(doc)
	assert_true(v.errors().any(func(m): return String(m.fr).contains("départ des joueurs") and String(m.fr).contains("trop près")),
		"boîte collée au départ : erreur\n%s" % _fr(v.errors()))


func test_existing_maps_unchanged() -> void:
	# DRAFT ARENA (boîtes murales, distributeurs) : mêmes messages qu'avant.
	var da := EditorMap.load_dir("res://assets/maps/draft_arena/")
	var v := _check(da)
	assert_eq(_fr(v.errors()), "", "DRAFT ARENA sans erreur")
	assert_false(v.messages.any(func(m): return String(m.fr).contains("bouche le passage") or String(m.fr).contains("barrière invisible")),
		"aucun message nouveau")


# ------------------------------------------------------------------ 2. objet indispensable enfermé

func test_power_switch_shut_in_is_an_error() -> void:
	var doc := DecorFree.two_rooms()
	doc.objets.append({"id": "pw", "type": "courant", "altitude": 0, "position": [5.0, 0.0], "mur": "n"})
	var e0 := _check(doc).errors().size()
	_clip(doc, [[4, 0], [6.5, 0], [6.5, 2.5], [4, 2.5]])
	var v := _check(doc)
	assert_true(v.errors().any(func(m): return String(m.fr).begins_with("Interrupteur du courant") and String(m.fr).contains("indispensable")),
		"interrupteur enfermé : erreur\n%s" % _fr(v.errors()))
	assert_eq(v.errors().size(), e0 + 1, "une seule erreur de plus")


func test_other_object_shut_in_stays_a_warning() -> void:
	var doc := DecorFree.two_rooms()
	doc.objets.append({"id": "pc", "type": "poste_central", "altitude": 0, "position": [5.0, 0.0], "mur": "n"})
	var e0 := _check(doc).errors().size()
	_clip(doc, [[4, 0], [6.5, 0], [6.5, 2.5], [4, 2.5]])
	var v := _check(doc)
	assert_eq(v.errors().size(), e0, "poste central (pas exigé) : pas d'erreur\n%s" % _fr(v.errors()))
	assert_true(v.warnings().any(func(m): return String(m.fr).begins_with("Poste central") and String(m.fr).contains("barrière invisible")),
		"avertissement gardé")


func test_shut_in_box() -> void:
	# Caisse au hasard enfermée : elle n'est pas exigée par la carte,
	# avertissement seulement (plus d'erreur « boîte de départ »).
	var doc := DecorFree.two_rooms()
	var e0 := _check(doc).errors().size()
	_clip(doc, [[17.5, 7.5], [21.5, 7.5], [21.5, 10], [17.5, 10]])
	var v := _check(doc)
	assert_eq(v.errors().size(), e0, "caisse enfermée : pas d'erreur\n%s" % _fr(v.errors()))
	assert_true(v.warnings().any(func(m): return String(m.fr).begins_with("Caisse au hasard") and String(m.fr).contains("barrière invisible")),
		"avertissement\n%s" % _fr(v.warnings()))


## Une seule caisse au hasard par carte : au-delà, avertissement (une carte
## d'avant à plusieurs boîtes reste jouable) ; l'export n'en garde qu'une,
## celle marquée « depart » sinon la première ; sans caisse : aucune erreur.
func test_one_crate_per_map() -> void:
	var doc := DecorFree.two_rooms()
	var e0 := _check(doc).errors().size()
	assert_false(_check(doc).warnings().any(func(m): return String(m.fr).contains("caisses au hasard")), "une caisse : pas d'avertissement")
	doc.objets.append({"id": "b2", "type": "boite", "altitude": 0, "position": [24.0, 5.0], "mur": "e"})
	var v := _check(doc)
	assert_eq(v.errors().size(), e0, "deux caisses : pas d'erreur\n%s" % _fr(v.errors()))
	assert_true(v.warnings().any(func(m): return String(m.fr).begins_with("2 caisses au hasard")), "deux caisses : avertissement\n%s" % _fr(v.warnings()))
	var lay: Dictionary = DecorFree.layout(doc)
	assert_eq((lay.markers.box as Array).size(), 1, "export : une seule caisse")
	assert_eq(int(lay.map_def.box_start), 0)
	assert_false(lay.map_def.has("box_starts"), "plus de départ au hasard")
	# La boîte « depart » (carte d'avant) est celle gardée, où qu'elle soit.
	for o in doc.objets:
		if String(o.get("type", "")) == "boite":
			o.erase("depart")
	doc.find("b2")["depart"] = true
	var lay2: Dictionary = DecorFree.layout(doc)
	assert_eq((lay2.markers.box as Array).size(), 1)
	assert_true(Vector3(lay2.markers.box[0].p[0], 0, lay2.markers.box[0].p[2]).distance_to(Vector3(lay.markers.box[0].p[0], 0, lay.markers.box[0].p[2])) > 1.0,
		"la boîte marquée « depart » est gardée (%s / %s)" % [str(lay2.markers.box[0].p), str(lay.markers.box[0].p)])
	# Sans caisse : la carte reste valable.
	doc.objets = doc.objets.filter(func(o): return String(o.get("type", "")) != "boite")
	assert_eq(_check(doc).errors().size(), e0, "sans caisse : aucune erreur de plus\n%s" % _fr(_check(doc).errors()))
	assert_eq((DecorFree.layout(doc).markers.box as Array).size(), 0)


func test_start_shut_in_is_an_error() -> void:
	var doc := DecorFree.two_rooms()
	# Départ (7, 6) dans un enclos de barrière : la carte n'est pas jouable.
	_clip(doc, [[5, 4.5], [9, 4.5], [9, 5], [5, 5]])
	_clip(doc, [[5, 7], [9, 7], [9, 7.5], [5, 7.5]])
	_clip(doc, [[5, 5], [5.5, 5], [5.5, 7], [5, 7]])
	_clip(doc, [[8.5, 5], [9, 5], [9, 7], [8.5, 7]])
	var v := _check(doc)
	assert_false(v.errors().is_empty(), "départ enfermé : erreur")


# ------------------------------------------------------------------ 5. carte sans « format »

func test_map_without_format_keeps_old_wall_boxes() -> void:
	var doc := DecorFree.two_rooms()
	DecorFree._obj(doc, {"type": "boite", "position": [9.0, 0.0], "depart": false})
	DecorFree._obj(doc, {"type": "boite", "position": [5.0, 5.0], "rot": 30, "depart": false})
	var texts := doc.file_texts()
	var carte: Dictionary = JSON.parse_string(texts["carte.json"])
	carte.erase("format")
	texts["carte.json"] = JSON.stringify(carte, "\t")
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "carte reçue sans format : acceptée")
	var m := EditorMap.from_texts(texts)
	assert_false(m.format_given, "format absent noté")
	var old: Array = m.objets.filter(func(o): return String(o.type) == "boite" and MapGeom.v2(o.position) == Vector2(9, 0))
	assert_true(old.size() == 1 and String(old[0].get("mur", "")) == "n" and not old[0].has("rot"), "boîte sans mur ni rot : mur nord, comme avant (%s)" % str(old))
	var fl: Array = m.objets.filter(func(o): return String(o.type) == "boite" and MapGeom.v2(o.position) == Vector2(5, 5))
	assert_true(fl.size() == 1 and MapCatalog.floor_box(fl[0]) and int(fl[0].rot) == 30, "boîte avec rot : au sol (%s)" % str(fl))
	# Avec « format » 15 : la boîte sans mur ni rot est au sol (format courant).
	var m15 := EditorMap.from_texts(doc.file_texts())
	var b15: Array = m15.objets.filter(func(o): return String(o.type) == "boite" and MapGeom.v2(o.position) == Vector2(9, 0))
	assert_true(b15.size() == 1 and not b15[0].has("mur"), "format écrit : au sol")
