extends TestCase
## Découpe des pièces (MapCarve, docs/MAP_AUTHORING.md § 3, « Pièce tracée
## sur une autre ») : découpe simple, nouvelle pièce au centre (anneau coupé en
## deux morceaux reliés par des passages), pièce coupée en deux (zone propre),
## pièce avalée, plusieurs pièces, contenu transféré ou supprimé, ouvertures
## déplacées ou retirées, refus d'un escalier rendu invalide, éditeur (aperçu,
## confirmation, annulation unique, un seul lot de session), agent (MCP :
## refus sans « decouper », découpe dans le même lot avec).

const TMP := "res://tests/_out/test_map_carve"


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


static func _room(doc: EditorMap, nom: String, x0: float, y0: float, x1: float, y1: float, k := 0) -> Dictionary:
	var z := doc.add_zone(nom, nom)
	var r := {"id": doc.new_id("p"), "nom": nom, "altitude": k * EditorMap.FLOOR_STEP, "zone": String(z.id), "contour": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]}
	doc.pieces.append(r)
	return r


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return MapGeom.rect_poly(Rect2(x0, y0, x1 - x0, y1 - y0))


## Pièce `poly` posée et découpe faite sur `doc` : le résultat de carve().
static func _carve(doc: EditorMap, nom: String, poly: PackedVector2Array, k := 0) -> Dictionary:
	var z := doc.add_zone(nom, nom)
	var r := {"id": doc.new_id("p"), "nom": nom, "altitude": k * EditorMap.FLOOR_STEP, "zone": String(z.id), "contour": MapGeom.poly_arr(poly)}
	doc.pieces.append(r)
	return MapCarve.carve(doc, r)


## Aucune pièce de l'étage n'en recouvre une autre, et chacune est valide.
func _rooms_ok(doc: EditorMap, k := 0, what := "") -> void:
	var rooms := doc.rooms_on(k)
	for i in rooms.size():
		var r := MapRules.check_existing(doc, rooms[i])
		assert_true(r.ok, "%s : « %s » valide (%s)" % [what, rooms[i].nom, MapRules.why(r)])
		for j in range(i + 1, rooms.size()):
			assert_false(MapGeom.overlap(doc.room_poly(rooms[i]), doc.room_poly(rooms[j])), "%s : « %s » / « %s » sans recouvrement" % [what, rooms[i].nom, rooms[j].nom])


func _errors(doc: EditorMap) -> String:
	var v := MapRaster.build(doc).v
	v.analyze()
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


func test_simple_cut() -> void:
	var doc := EditorMap.blank()
	var a := _room(doc, "Atelier", 0, 0, 10, 8)
	var poly := _rect(7, 4, 13, 10)
	# Pièce tracée : refus d'avant sans découpe, admise avec (overlap_ok).
	assert_false(MapRules.check_room(doc, 0, poly).ok, "chevauchement refusé sans découpe")
	assert_true(MapRules.check_room(doc, 0, poly, "", true).ok, "admis pour une découpe")
	var pl := MapCarve.plan(doc, 0, poly)
	assert_true(pl.carve and pl.ok, "découpe prévue")
	assert_eq((pl.cut as Array).size(), 1)
	assert_near(float(pl.cut[0].area), 12.0, 0.01, "partie hachurée : 3 × 4 m")
	assert_near(MapGeom.area(doc.room_poly(a)), 80.0, 0.001, "plan : la carte n'est pas touchée")
	assert_true(MapCarve.describe(pl, true).contains("« Atelier » sera découpée (12 m² retirés)"), MapCarve.describe(pl, true))
	assert_true(MapCarve.describe(pl, false).contains("Room \"Atelier\" will be cut"), "texte anglais")
	var rep := _carve(doc, "Cagibi", poly)
	assert_true(rep.ok, "découpe faite")
	assert_eq(doc.pieces.size(), 2)
	assert_near(MapGeom.area(doc.room_poly(a)), 68.0, 0.001, "Atelier : 80 - 12 m²")
	assert_eq(doc.room_poly(a).size(), 6, "Atelier en L (6 sommets)")
	_rooms_ok(doc, 0, "simple")
	# Une pièce qui ne fait que toucher : rien à découper.
	assert_false(MapCarve.plan(doc, 0, _rect(10, 0, 14, 4)).carve, "pièce collée : aucune découpe")


func test_new_room_in_the_middle() -> void:
	var doc := EditorMap.blank()
	var a := _room(doc, "Atelier", 0, 0, 12, 10)
	a["surface_sol"] = "parquet"
	a["plafond"] = 3.6
	var rep := _carve(doc, "Bureau", _rect(4, 3, 8, 7))
	assert_true(rep.ok, "découpe faite : %s" % MapRules.why(rep))
	var parts := doc.pieces.filter(func(p): return String(p.nom).begins_with("Atelier"))
	assert_eq(parts.size(), 2, "anneau coupé en deux morceaux (le format n'a pas de trou)")
	assert_eq(parts.map(func(p): return String(p.nom)), ["Atelier", "Atelier (2)"], "noms")
	assert_eq(String(parts[0].id), String(a.id), "le plus grand garde l'identifiant")
	assert_eq(String(parts[1].zone), String(a.zone), "même zone")
	assert_eq(String(parts[1].get("surface_sol", "")), "parquet", "mêmes réglages")
	assert_near(float(parts[1].get("plafond", 0.0)), 3.6, 0.001)
	var area := 0.0
	for p in parts:
		area += MapGeom.area(doc.room_poly(p))
	assert_near(area, 104.0, 0.01, "120 - 16 m²")
	var passages := doc.ouvertures.filter(func(o): return String(o.type) == "passage")
	assert_eq(passages.size(), 2, "un passage libre de chaque côté de la nouvelle pièce")
	assert_eq(int(rep.victims[0].passages), 2)
	_rooms_ok(doc, 0, "centre")
	for o in passages:
		assert_true(MapRules.check_existing(doc, o).ok, "passage valide")
	assert_false(_errors(doc).contains("coupée en morceaux"), "zone d'un seul tenant : %s" % _errors(doc))
	assert_true(MapCarve.describe(rep, true).contains("coupée en 2 pièces"), MapCarve.describe(rep, true))


func test_split_in_two_gets_own_zone() -> void:
	var doc := EditorMap.blank()
	var a := _room(doc, "Atelier", 0, 2, 12, 8)
	var rep := _carve(doc, "Couloir", _rect(5, 0, 8, 10))
	assert_true(rep.ok)
	var parts := doc.pieces.filter(func(p): return String(p.nom).begins_with("Atelier"))
	assert_eq(parts.size(), 2, "deux morceaux")
	assert_near(MapGeom.area(doc.room_poly(a)), 30.0, 0.001, "le plus grand (5 × 6) garde l'id")
	assert_near(MapGeom.area(doc.room_poly(parts[1])), 24.0, 0.001)
	assert_true(String(parts[1].zone) != String(a.zone), "morceau séparé : sa propre zone")
	assert_eq(String(doc.zone(String(parts[1].zone)).nom.fr), "Atelier (2)")
	assert_eq(rep.victims[0].own_zone, ["Atelier (2)"])
	_rooms_ok(doc, 0, "coupée")


func test_swallowed_and_several_rooms() -> void:
	var doc := EditorMap.blank()
	var cag := _room(doc, "Cagibi", 2, 2, 4, 4)
	var a := _room(doc, "Atelier", 6, 0, 12, 6)
	var b := _room(doc, "Bureau", 12, 0, 18, 6)
	var zc := String(cag.zone)
	var rep := _carve(doc, "Hall", _rect(0, 0, 14, 5))
	assert_true(rep.ok)
	assert_true(doc.find(String(cag.id)).is_empty(), "pièce avalée : supprimée")
	assert_true(doc.zone(zc).is_empty(), "sa zone vide est retirée")
	assert_true(rep.get("start_moved", false), "c'était la zone de départ")
	var hall: Array = doc.pieces.filter(func(p): return String(p.nom) == "Hall")
	assert_eq(doc.depart, String(hall[0].zone), "départ : la zone de la nouvelle pièce")
	assert_true(doc.find(String(a.id)).is_empty(), "Atelier : il n'en reste que 6 × 1 m (moins de 1,5 m de côté) : supprimée")
	assert_near(MapGeom.area(doc.room_poly(b)), 26.0, 0.001, "Bureau : 36 - 10 m²")
	assert_eq((rep.victims as Array).size(), 3, "trois pièces touchées")
	assert_true(MapCarve.describe(rep, true).contains("« Cagibi » sera supprimée"), MapCarve.describe(rep, true))
	_rooms_ok(doc, 0, "plusieurs")


func test_content_follows_position() -> void:
	var doc := EditorMap.blank()
	var a := _room(doc, "Atelier", 0, 1, 10, 8)
	doc.objets.append({"id": "c1", "type": "baril", "altitude": 0, "position": [8.0, 4.5]})
	doc.objets.append({"id": "c2", "type": "caisse", "altitude": 0, "position": [2.5, 3.5]})
	doc.objets.append({"id": "c3", "type": "baril", "altitude": 0, "position": [9.5, 4.5]})
	for id in ["c1", "c2", "c3"]:
		var r0 := MapRules.check_existing(doc, doc.find(id))
		assert_true(r0.ok, "%s valide avant (%s)" % [id, MapRules.why(r0)])
	# Nouvelle pièce en travers : il reste à l'est une bande de 1 × 7 m (trop
	# petite) où est c3 : supprimée avec elle.
	var rep := _carve(doc, "Réserve", _rect(7, 0, 9, 9))
	assert_true(rep.ok)
	var r: Dictionary = doc.pieces[-1]
	assert_true(MapTransform.attached(doc, doc.find(String(r.id))).has("c1"), "la caisse de la partie découpée suit la nouvelle pièce")
	assert_true(MapTransform.attached(doc, a).has("c2"), "celle du reste ne bouge pas")
	assert_true(doc.find("c3").is_empty(), "objet d'un morceau retiré : supprimé")
	assert_eq(int(rep.removed_objects), 1)
	_rooms_ok(doc, 0, "contenu")


func test_openings_moved_or_removed() -> void:
	var doc := EditorMap.blank()
	var a := _room(doc, "Atelier", 0, 0, 10, 8)
	var c := _room(doc, "Couloir", 10, 0, 14, 8)
	doc.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": [10, 4.25], "largeur": 2, "prix": 750})
	assert_true(MapRules.check_existing(doc, doc.find("o1")).ok, "porte valide avant")
	# La nouvelle pièce prend le bas du mur commun : la porte n'y tient plus,
	# elle glisse sur ce qui reste du mur Atelier / Couloir.
	var rep := _carve(doc, "Réserve", _rect(6, 5, 10, 8))
	assert_true(rep.ok)
	var o1 := doc.find("o1")
	assert_false(o1.is_empty(), "porte gardée")
	assert_eq(o1.position, [10.0, 3.25], "déplacée le long du mur commun")
	assert_true(MapRules.check_existing(doc, o1).ok, "porte valide après")
	assert_eq((rep.moved as Array).size(), 1)
	# Porte au milieu de la nouvelle pièce (les deux pièces recouvertes) : retirée.
	var doc2 := EditorMap.blank()
	_room(doc2, "Atelier", 0, 0, 10, 8)
	_room(doc2, "Couloir", 10, 0, 14, 8)
	doc2.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": [10, 4.25], "largeur": 2, "prix": 750})
	assert_true(MapRules.check_existing(doc2, doc2.find("o1")).ok, "porte valide avant")
	var rep2 := _carve(doc2, "Hall", _rect(8, 2, 12, 6))
	assert_true(rep2.ok)
	assert_true(doc2.find("o1").is_empty(), "porte retirée")
	assert_eq((rep2.removed as Array).size(), 1)
	assert_true(MapCarve.describe(rep2, true).contains("Ouvertures retirées"), MapCarve.describe(rep2, true))
	assert_eq((rep2.victims as Array).size(), 2, "les deux pièces découpées")
	_rooms_ok(doc2, 0, "porte retirée")
	assert_true(String(a.id) != "" and String(c.id) != "")


func test_stairs_refuse() -> void:
	var doc := EditorMap.blank()
	var hall := _room(doc, "Hall", 0, 0, 12, 20)
	hall["plafond"] = 6.7
	var mez := {"id": "p9", "nom": "Mezzanine", "altitude": 1 * EditorMap.FLOOR_STEP, "zone": String(hall.zone), "contour": [[0, 4], [8, 4], [8, 9], [0, 9]]}
	doc.pieces.append(mez)
	doc.objets.append({"id": "e1", "type": "escalier", "altitude": 0, "rect": [1, 9, 3.5, 16], "monte": "n"})
	var st := MapRules.check_existing(doc, doc.find("e1"))
	assert_true(st.ok, "escalier valide avant : %s" % MapRules.why(st))
	var pl := MapCarve.plan(doc, 0, _rect(2, 11, 6, 14))
	assert_true(pl.carve, "recouvre le hall")
	assert_false(pl.ok, "escalier coupé : découpe refusée")
	assert_true(String(pl.fr).contains("escalier"), String(pl.fr))
	var pl2 := MapCarve.plan(doc, 0, _rect(8, 14, 11, 18))
	assert_true(pl2.carve and pl2.ok, "ailleurs : découpe permise (%s)" % MapRules.why(pl2))


func test_clean_and_subtract() -> void:
	var p := MapCarve.clean(PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0), Vector2(4, 4), Vector2(4, 4.0004), Vector2(0, 4)]))
	assert_eq(p.size(), 4, "sommets alignés et doublons retirés")
	var parts: Variant = MapCarve.subtract(_rect(0, 0, 10, 10), _rect(3, 3, 6, 6))
	assert_true(parts is Array and (parts as Array).size() == 2, "anneau : deux contours simples")
	for q in parts:
		assert_true(MapGeom.is_simple(q), "contour simple")
	assert_eq(MapCarve._base_name("Atelier (3)"), "Atelier")


# ------------------------------------------------------------------ éditeur

func _editor() -> MapEditor:
	var ed: MapEditor = load(MapEditor.SCENE).instantiate()
	host.add_child(ed)
	await wait_frames(3)
	ed.new_map(true)
	return ed


func test_editor_confirm_and_single_undo() -> void:
	var ed: MapEditor = await _editor()
	var doc := EditorMap.blank()
	_room(doc, "Atelier", 0, 0, 12, 10)
	ed.doc = doc
	ed.collab.reset_doc(ed.doc)
	ed.changed()
	var sig0 := MapUnsaved.signature(ed.doc)
	var n0: int = ed.collab.history.entries.size()
	ed.pick_item("piece_rect")
	var cv := ed.canvas
	# Tracé en cours : la découpe est prévue (aperçu hachuré).
	var res := cv._creation(ed.current_item(), Vector2(4, 3), Vector2(8, 7))
	assert_true(res.ok and res.has("carve"), "tracé par-dessus : découpe prévue")
	# Relâcher : boîte de confirmation, rien n'est encore créé.
	cv.drag = {"kind": "create", "start": Vector2(4, 3)}
	cv._finish_create(Vector2(8, 7))
	var d: ConfirmationDialog = ed.carve_dialog
	assert_true(d != null and d.visible, "confirmation ouverte")
	assert_eq(String(d.name), "CarveDialog")
	assert_true(d.dialog_text.contains("Atelier"), d.dialog_text)
	assert_eq(MapUnsaved.signature(ed.doc), sig0, "rien de créé avant la réponse")
	# Annuler : rien n'est créé.
	d.canceled.emit()
	await wait_frames(1)
	assert_eq(MapUnsaved.signature(ed.doc), sig0, "Annuler : carte inchangée")
	assert_eq(ed.collab.history.entries.size(), n0, "aucune entrée d'historique")
	# Découper : une seule entrée d'historique (un lot pour la session).
	cv.drag = {"kind": "create", "start": Vector2(4, 3)}
	cv._finish_create(Vector2(8, 7))
	ed.carve_dialog.confirmed.emit()
	await wait_frames(1)
	assert_eq(ed.doc.pieces.size(), 3, "nouvelle pièce + deux morceaux")
	# L'aperçu (plan) a construit la pièce comme la pose : même carte.
	assert_eq(MapUnsaved.signature(res.carve.doc), MapUnsaved.signature(ed.doc), "aperçu = résultat (pièce, zone, morceaux, passages)")
	assert_eq(ed.collab.history.entries.size(), n0 + 1, "un seul lot")
	var ops: Array = ed.collab.history.entries[-1].ops
	assert_true(ops.size() >= 4, "lot : pièce, découpe, morceau, passages (%d ops)" % ops.size())
	assert_eq(ed.selected, String(ed.doc.pieces[1].id), "la nouvelle pièce est choisie")
	assert_false(String(ed.doc.pieces[1].nom).begins_with("Atelier"), "nouvelle pièce : son propre nom")
	# Une seule annulation défait tout.
	ed.undo()
	await wait_frames(1)
	assert_eq(MapUnsaved.signature(ed.doc), sig0, "Ctrl+Z : tout est défait d'un coup")
	ed.redo()
	await wait_frames(1)
	assert_eq(ed.doc.pieces.size(), 3, "Ctrl+Y : tout est refait")
	ed.queue_free()
	await wait_frames(1)


func test_editor_polygon_and_refusal() -> void:
	var ed: MapEditor = await _editor()
	var doc := EditorMap.blank()
	var hall := _room(doc, "Hall", 0, 0, 12, 20)
	hall["plafond"] = 6.7
	doc.pieces.append({"id": "p9", "nom": "Mezzanine", "altitude": 1 * EditorMap.FLOOR_STEP, "zone": String(hall.zone), "contour": [[0, 4], [8, 4], [8, 9], [0, 9]]})
	doc.objets.append({"id": "e1", "type": "escalier", "altitude": 0, "rect": [1, 9, 3.5, 16], "monte": "n"})
	ed.doc = doc
	ed.collab.reset_doc(ed.doc)
	ed.changed()
	ed.pick_item("piece_poly")
	var res := ed.canvas._poly_creation(ed.current_item(), _rect(2, 11, 6, 14))
	assert_false(res.ok, "polygone sur l'escalier : refusé")
	assert_true(MapRules.why(res).contains("escalier") or MapRules.why(res).contains("stairs"), MapRules.why(res))
	res = ed.canvas._poly_creation(ed.current_item(), PackedVector2Array([Vector2(8, 14), Vector2(11, 14), Vector2(11, 18)]))
	assert_true(res.ok and res.has("carve"), "triangle dans le hall : découpe prévue")
	var rep := ed.carve_room(res.obj, 0)
	assert_true(rep.ok)
	_rooms_ok(ed.doc, 0, "triangle")
	ed.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ agent (MCP)

func test_agent_apply_decouper() -> void:
	var m := EditorMap.blank("essai", "ESSAI", "TEST")
	_room(m, "Atelier", 0, 0, 12, 10)
	var collab := MapCollab.new(m)
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	host.add_child(link)
	var ops := [{"op": "add", "coll": "pieces", "el": {"id": "$1", "nom": "Bureau", "contour": [[8, 6], [14, 6], [14, 12], [8, 12]]}}]
	var r := link.cmd_apply({"label": "bureau", "ops": ops.duplicate(true)})
	assert_true(r.has("error") and String(r.error).contains("decouper"), "sans « decouper » : refus expliqué (%s)" % str(r))
	assert_eq(m.pieces.size(), 1, "rien d'appliqué")
	assert_eq(collab.history.entries.size(), 0)
	r = link.cmd_apply({"label": "bureau", "ops": ops.duplicate(true), "decouper": true, "animate": false})
	assert_false(r.has("error"), str(r))
	assert_true(r.has("decoupe"), "découpe rapportée")
	assert_eq(String(r.decoupe[0].decoupees[0].nom), "Atelier")
	assert_near(float(r.decoupe[0].decoupees[0].retire_m2), 16.0, 0.01)
	assert_eq(m.pieces.size(), 2)
	assert_near(MapGeom.area(m.room_poly(m.pieces[0])), 104.0, 0.01, "Atelier découpée")
	assert_eq(collab.history.entries.size(), 1, "un seul lot")
	collab.request_undo(true)
	assert_eq(m.pieces.size(), 1, "undo : tout défait")
	assert_near(MapGeom.area(m.room_poly(m.pieces[0])), 120.0, 0.01)
	link.queue_free()
	collab.queue_free()
	await wait_frames(1)


# ------------------------------------------------------------------ revue (5 à 8)

## 5. Agent : la pièce qui découpe passe les contrôles du tracé (contour
## simple, terrain, taille) ; sinon tout le lot est refusé, rien n'est appliqué.
func test_agent_invalid_cutting_room_refused() -> void:
	var m := EditorMap.blank("essai", "ESSAI", "TEST")
	_room(m, "Atelier", 0, 0, 12, 10)
	var sig := MapUnsaved.signature(m)
	var bad := {
		"croisée": [[2, 2], [8, 8], [8, 2], [2, 8]],
		"hors terrain": [[-2, 2], [4, 2], [4, 6], [-2, 6]],
		"trop petite": [[5, 5], [6, 5], [6, 6], [5, 6]],
	}
	for what in bad:
		var ops := [{"op": "put", "coll": "pieces", "el": {"id": "p7", "nom": "X", "altitude": 0, "zone": String(m.pieces[0].zone), "contour": bad[what]}}]
		var r := MapCarve.carve_ops(m, ops, true)
		assert_false(r.ok, "%s : refusée" % what)
		assert_true(String(r.get("fr", "")).contains("ne peut pas découper"), "%s : %s" % [what, r.get("fr", "")])
	assert_eq(MapUnsaved.signature(m), sig, "carte inchangée")


## 5. Plafond des zones : morceaux à zone propre compris.
func test_caps_zones() -> void:
	var doc := EditorMap.blank()
	for i in CustomMapGuard.MAX_ZONES - 2:
		_room(doc, "R%d" % i, 3.0 * (i % 20), 50.0 + 3.0 * floorf(i / 20.0), 3.0 * (i % 20) + 2.0, 52.0 + 3.0 * floorf(i / 20.0))
	_room(doc, "Atelier", 0, 2, 12, 8)
	assert_eq(doc.zones.size(), CustomMapGuard.MAX_ZONES - 1)
	# Nouvelle zone + zone propre du morceau séparé : 65 > 64.
	var pl := MapCarve.plan(doc, 0, _rect(5, 0, 8, 10))
	assert_true(pl.carve and not pl.ok, "plafond des zones : refus")
	assert_true(String(pl.get("fr", "")).contains("zones"), String(pl.get("fr", "")))


## 8. Plafond des pièces : la pièce découpée n'est comptée qu'une fois.
func test_caps_rooms_counted_once() -> void:
	var doc := EditorMap.blank()
	var z := doc.add_zone("Remplissage", "Filler")
	for i in CustomMapGuard.MAX_ROOMS - 2:
		doc.pieces.append({"id": "f%d" % i, "nom": "F%d" % i, "altitude": 0, "zone": String(z.id),
			"contour": [[3.0 * (i % 40), 50.0 + 3.0 * floorf(i / 40.0)], [3.0 * (i % 40) + 2, 50.0 + 3.0 * floorf(i / 40.0)],
				[3.0 * (i % 40) + 2, 52.0 + 3.0 * floorf(i / 40.0)], [3.0 * (i % 40), 52.0 + 3.0 * floorf(i / 40.0)]]})
	_room(doc, "Atelier", 0, 0, 12, 10)
	# 254 + Atelier + la nouvelle = 256 : une découpe simple tient pile.
	var pl := MapCarve.plan(doc, 0, _rect(8, 6, 14, 12))
	assert_true(pl.carve and pl.ok, "256 pièces : permis (%s)" % pl.get("fr", ""))
	# Au centre : un morceau de plus (257) : refus.
	var pl2 := MapCarve.plan(doc, 0, _rect(4, 3, 8, 7))
	assert_true(pl2.carve and not pl2.ok, "257 pièces : refus")
	assert_true(String(pl2.get("fr", "")).contains("pièces"), String(pl2.get("fr", "")))


## 6. Pièce avalée qui portait la zone de départ : l'aperçu l'annonce.
func test_plan_announces_start_zone() -> void:
	var doc := EditorMap.blank()
	var cag := _room(doc, "Cagibi", 2, 2, 4, 4)
	assert_eq(doc.depart, String(cag.zone))
	var pl := MapCarve.plan(doc, 0, _rect(0, 0, 6, 6))
	assert_true(pl.ok and pl.get("start_moved", false), "aperçu : zone de départ déplacée")
	assert_true(MapCarve.describe(pl, true).contains("La zone de départ devient celle de la nouvelle pièce"), MapCarve.describe(pl, true))
	assert_true(MapCarve.describe(pl, false).contains("start zone"), "anglais")
	assert_true(MapCarve.summary(pl).zone_depart_deplacee)


## 7. Porte encore valide qui relie d'autres zones qu'avant : signalée.
func test_relinked_door_listed() -> void:
	var doc := EditorMap.blank()
	_room(doc, "Atelier", 0, 0, 10, 8)
	_room(doc, "Couloir", 10, 0, 14, 8)
	doc.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": [10, 4.25], "largeur": 2, "prix": 750})
	var pl := MapCarve.plan(doc, 0, _rect(6, 2, 10, 6), {"nom": "Réserve"})
	assert_true(pl.ok, MapRules.why(pl))
	assert_eq((pl.relinked as Array).size(), 1, "porte signalée")
	assert_eq((pl.removed as Array).size() + (pl.moved as Array).size(), 0, "ni déplacée ni retirée")
	var txt := MapCarve.describe(pl, true)
	assert_true(txt.contains("750") and txt.contains("(Atelier ↔ Couloir) donnera désormais sur : Couloir ↔ Réserve"), txt)
	assert_true(MapCarve.describe(pl, false).contains("will now lead to"), "anglais")
	assert_eq(MapCarve.summary(pl).ouvertures_reliees.size(), 1)
	var o1: Dictionary = pl.doc.find("o1")
	assert_eq(o1.position, [10, 4.25], "porte gardée à sa place")
