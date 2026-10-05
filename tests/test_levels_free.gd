extends TestCase
## Niveaux libres (docs/LEVELS_PLAN.md, étape 1b) : aucun écart minimal entre
## deux niveaux posés côte à côte (demi-niveau de 1,5 m relié par une rampe à
## travers le mur commun), pièces empilées à 3,1 m au moins (refus à la pose
## et erreur du validateur), pièce haute qui traverse plusieurs niveaux (deux
## mezzanines), escalier qui saute un niveau (plancher du niveau traversé
## au-dessus des marches : erreur), dégagement de 2,1 m au-dessus des
## marches, plafond coupé = le plus bas des deux ; export sans blocs de mur
## qui se recoupent ni boîtes de zone qui se chevauchent. Les cartes servent
## aussi au scénario levels_play (zombies sur un demi-niveau et un escalier
## qui saute un niveau).


static func rect(x0: float, y0: float, x1: float, y1: float) -> Array:
	return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]


## Carte d'une seule zone (une fenêtre suffit) : départ et boîte au sol de la
## première pièce.
static func _map(id: String, rooms: Array, start: Array, box: Array, window: Array) -> EditorMap:
	var doc := EditorMap.blank(id, id.to_upper(), id.to_upper())
	var z := doc.add_zone("Salle", "Hall")
	for r: Dictionary in rooms:
		r["zone"] = String(z.id)
		doc.pieces.append(r)
	doc.depart = String(z.id)
	doc.objets.append({"id": "s1", "type": "depart", "altitude": 0, "position": start})
	doc.objets.append({"id": "b1", "type": "boite", "altitude": 0, "position": box, "mur": "n", "depart": true})
	doc.ouvertures.append({"id": "w1", "type": "fenetre", "altitude": 0, "position": window})
	return doc


## Demi-niveau : salle A au sol (4 m sous plafond), palier P à 1,5 m collé à
## l'est (mur commun x = 12) ; rampe de 1,5 m dans A qui arrive à travers le
## mur commun sur le sol de P.
static func half_level() -> EditorMap:
	var doc := _map("demi_niveau", [
		{"id": "pa", "nom": "Salle", "altitude": 0, "plafond": 4.0, "contour": rect(0, 0, 12, 10)},
		{"id": "pp", "nom": "Palier", "altitude": 1.5, "contour": rect(12, 0, 22, 10)}],
		[3.0, 7.0], [3.25, 0.0], [3.25, 10.0])
	doc.objets.append({"id": "r1", "type": "escalier", "altitude": 0, "altitude_haut": 1.5, "rect": [6.0, 3.0, 12.0, 5.5], "monte": "e"})
	return doc


## Pièce haute H (9,5 m sous plafond) qui traverse les niveaux 3,5 m et 7 m :
## mezzanine M1 à 3,5 m à l'ouest, M2 à 7 m à l'est ; escalier S1 de 0 à
## 3,5 m vers M1, escalier S2 de 0 à 7 m (il saute le niveau 3,5 m) vers M2.
static func high_hall() -> EditorMap:
	var doc := _map("halle_haute", [
		{"id": "ph", "nom": "Halle", "altitude": 0, "plafond": 9.5, "contour": rect(0, 0, 24, 16)},
		{"id": "m1", "nom": "Mezzanine 1", "altitude": 3.5, "contour": rect(0, 0, 6, 16)},
		{"id": "m2", "nom": "Mezzanine 2", "altitude": 7.0, "contour": rect(16, 0, 24, 16)}],
		[12.0, 7.0], [12.75, 0.0], [12.25, 16.0])
	doc.objets.append({"id": "s1e", "type": "escalier", "altitude": 0, "altitude_haut": 3.5, "rect": [6.0, 2.0, 13.0, 4.5], "monte": "o"})
	doc.objets.append({"id": "s2e", "type": "escalier", "altitude": 0, "altitude_haut": 7.0, "rect": [7.0, 11.0, 16.0, 13.5], "monte": "e"})
	return doc


## Halle haute, couloir C (4 m sous plafond) ouvert sur elle à l'est (passage
## x = 24) et, au bout du couloir, un demi-niveau P à 1,5 m relié par une
## rampe à travers leur mur commun (x = 32) ; scénario levels_play : niveaux
## 0, 1,5, 3,5 et 7 m. (Le mur de la halle, qui traverse 3,5 et 7 m, laisserait
## 1,7 m au-dessus d'un palier à 1,5 m : la rampe part du couloir.)
static func split_hall() -> EditorMap:
	var doc := high_hall()
	var z := String(doc.pieces[0].zone)
	doc.pieces.append({"id": "pc", "nom": "Couloir", "altitude": 0, "plafond": 4.0, "zone": z, "contour": rect(24, 4, 32, 12)})
	doc.pieces.append({"id": "pp", "nom": "Palier", "altitude": 1.5, "zone": z, "contour": rect(32, 4, 40, 12)})
	doc.ouvertures.append({"id": "pa1", "type": "passage", "altitude": 0, "position": [24.0, 8.0], "largeur": 3.0})
	doc.objets.append({"id": "r1", "type": "escalier", "altitude": 0, "altitude_haut": 1.5, "rect": [26.0, 7.0, 32.0, 9.5], "monte": "e"})
	return doc


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


## Les boîtes [x0, y0, z0, x1, y1, z1] `a` et `b` se recoupent-elles (volume > 0) ?
static func _cut(a: Array, b: Array, eps := 0.002) -> bool:
	for i in 3:
		if minf(float(a[i + 3]), float(b[i + 3])) - maxf(float(a[i]), float(b[i])) <= eps:
			return false
	return true


## Export : aucun bloc de mur qui en recoupe un autre, aucune boîte de zone
## qui en chevauche une autre (de zones différentes ou de la même).
func _export_sane(name: String, doc: EditorMap) -> Dictionary:
	var v := _check(doc)
	assert_true(v.ok(), "%s : carte acceptée\n%s" % [name, _errs(v)])
	var lay := MapLayoutExport.build(v)
	var blocks: Array = lay.blocks
	var bad := []
	for i in blocks.size():
		for j in range(i + 1, blocks.size()):
			if _cut(blocks[i].box, blocks[j].box):
				bad.append("%s / %s" % [str(blocks[i].box), str(blocks[j].box)])
	assert_true(bad.is_empty(), "%s : blocs de mur qui se recoupent : %s" % [name, str(bad.slice(0, 4))])
	var boxes := []
	for z in lay.zones:
		for b in lay.zones[z].boxes:
			boxes.append([z, b])
	var over := []
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			if _cut(boxes[i][1], boxes[j][1]):
				over.append("%s %s / %s %s" % [boxes[i][0], str(boxes[i][1]), boxes[j][0], str(boxes[j][1])])
	assert_true(over.is_empty(), "%s : boîtes de zone qui se chevauchent : %s" % [name, str(over.slice(0, 4))])
	return lay


# ------------------------------------------------------------------ demi-niveau

func test_half_level_ramp_through_the_shared_wall() -> void:
	var doc := half_level()
	assert_eq(doc.levels(), [0.0, 1.5], "deux niveaux à 1,5 m l'un de l'autre")
	assert_true(doc.stack_issue().is_empty(), "côte à côte : aucun recouvrement")
	# Pose : la rampe arrive à travers le mur commun (palier dans le mur).
	var r := MapRules.check_existing(doc, doc.find("r1"))
	assert_true(r.ok, "rampe admise à la pose (%s)" % MapRules.why(r))
	assert_eq(int(r.get("to", -1)), 1, "elle arrive au niveau 1,5 m")
	var v := _check(doc)
	assert_true(v.ok(), "demi-niveau accepté :\n" + _errs(v))
	assert_eq(v.stairs.size(), 1)
	assert_eq(int(v.stairs[0].to), 1, "escalier du niveau 0 au niveau 1,5 m")
	# Connexité : le sol du palier est atteint depuis le départ.
	var f1 := v.floors[1]
	var c := Vector2i(36, 8)   # (18 m, 4 m) : sol du palier
	assert_eq(f1.room_of(c), "pp")
	assert_eq(int(v.reach[1][c.y * f1.w + c.x]), 1, "palier atteint à pied depuis le départ")
	# Palier dans le mur (x = 12 m) : du sol à 1,5 m, le mur du bas s'arrête sous sa dalle.
	var land := Vector2i(24, 8)
	assert_eq(f1.at(land), MapValidator.K.SOL, "palier dans l'épaisseur du mur")
	assert_near(MapVertical.wall_top(v, 0, land), 1.5 - MapValidator.DALLE, 0.001, "mur du bas sous la dalle du palier")
	var lay := _export_sane("demi-niveau", doc)
	assert_eq(lay.stairs.size(), 1)
	assert_near(float(lay.stairs[0].a[1]), 0.0, 0.001, "rampe : pied au sol")
	assert_near(float(lay.stairs[0].b[1]), 1.5, 0.001, "rampe : haut à 1,5 m")


func test_half_level_side_by_side_without_stairs_is_free() -> void:
	# Deux salles côte à côte à 0 et 1,5 m : aucun écart minimal (avant : 3,1 m).
	var doc := half_level()
	doc.objets = doc.objets.filter(func(o): return String(o.type) != "escalier")
	var v := MapRaster.build(doc).v
	assert_false(v.errors().any(func(m): return String(m.fr).contains("entre deux sols") or String(m.fr).contains("se recouvrent")), _errs(v))


func test_door_between_two_altitudes_is_flagged() -> void:
	# Décision 4 : porte entre la salle (0 m) et le palier (1,5 m) : gardée, signalée.
	var doc := half_level()
	doc.ouvertures.append({"id": "d1", "type": "porte", "altitude": 0, "position": [12.0, 8.0], "largeur": 1.5, "prix": 750})
	var v := MapRaster.build(doc).v
	assert_true(v.errors().any(func(m): return String(m.fr).contains("reliez deux niveaux par un escalier")), _errs(v))
	assert_false(doc.find("d1").is_empty(), "jamais supprimée")


# ------------------------------------------------------------------ pièce haute et mezzanines

func test_high_room_through_two_levels_with_two_mezzanines() -> void:
	var doc := high_hall()
	assert_eq(doc.levels(), [0.0, 3.5, 7.0])
	assert_eq(doc.rooms_through(1).map(func(p): return String(p.id)), ["ph"], "la halle traverse 3,5 m")
	assert_eq(doc.rooms_through(2).map(func(p): return String(p.id)), ["ph"], "et 7 m")
	assert_true(doc.is_high(doc.find("ph")))
	for o in doc.objets.filter(func(x): return String(x.type) == "escalier"):
		var r := MapRules.check_existing(doc, o)
		assert_true(r.ok, "%s admis à la pose (%s)" % [o.id, MapRules.why(r)])
	var v := _check(doc)
	assert_true(v.ok(), "halle et deux mezzanines acceptées :\n" + _errs(v))
	# Vide de la halle aux deux niveaux traversés, mezzanines au-dessus.
	var mid := Vector2i(24, 14)   # (12 m, 7 m)
	assert_eq(v.floors[1].at(mid), MapValidator.K.TREMIE, "vide de la halle à 3,5 m")
	assert_eq(v.floors[2].at(mid), MapValidator.K.TREMIE, "vide de la halle à 7 m")
	assert_eq(v.floors[1].room_of(Vector2i(4, 14)), "m1")
	assert_eq(v.floors[2].room_of(Vector2i(40, 14)), "m2")
	# Plafonds réels de la halle : sous chaque mezzanine sa dalle, ailleurs 9,5 m.
	assert_eq(MapVertical.ceil_at(v, 0, Vector2i(4, 14)), [3.5 - MapValidator.DALLE, false], "sous M1")
	assert_eq(MapVertical.ceil_at(v, 0, Vector2i(40, 14)), [7.0 - MapValidator.DALLE, false], "sous M2")
	assert_eq(MapVertical.ceil_at(v, 0, mid), [9.5, true], "halle ouverte jusqu'à son plafond")
	# Escaliers : S1 de 0 à 3,5 m, S2 de 0 à 7 m (il saute le niveau 3,5 m).
	var to := {}
	for s in v.stairs:
		to[v.eid_of[s.key]] = int(s.to)
	assert_eq(to, {"s1e": 1, "s2e": 2})
	var lay := _export_sane("halle haute", doc)
	var rail_y := {}
	for rl in lay.rails:
		rail_y[snappedf(float(rl.y), 0.01)] = true
	assert_true(rail_y.has(3.5) and rail_y.has(7.0), "garde-corps au bord des deux mezzanines : %s" % str(rail_y.keys()))
	var sb: Array = (lay.stairs as Array).filter(func(s): return absf(float(s.b[1]) - 7.0) < 0.01)
	assert_eq(sb.size(), 1, "un escalier exporté de 0 à 7 m")
	if not sb.is_empty():
		assert_near(float(sb[0].a[1]), 0.0, 0.001)


func test_stairs_skipping_a_level_under_a_floor() -> void:
	# Plancher du niveau 3,5 m au-dessus des marches de S2 (0 -> 7 m) : erreur.
	var doc := high_hall()
	doc.find("m1")["contour"] = rect(0, 0, 10, 16)
	doc.find("s1e")["rect"] = [10.0, 2.0, 17.0, 4.5]
	var v := MapRaster.build(doc).v
	assert_true(v.errors().any(func(m): return String(m.fr).contains("le plancher du niveau 3,5 m passe au-dessus de ses marches")), _errs(v))
	var r := MapRules.check_existing(doc, doc.find("s2e"))
	assert_true(not r.ok and String(r.fr).contains("passe au-dessus des marches"), "refus à la pose : %s" % MapRules.why(r))
	# Mezzanine à côté (à l'ouest de l'escalier) : admis.
	doc = high_hall()
	assert_true(MapRules.check_existing(doc, doc.find("s2e")).ok)
	assert_true(_check(doc).ok())


func test_slab_too_close_above_the_steps() -> void:
	# Pièce à 3,5 m au-dessus de la rampe (0 -> 1,5 m) : sa dalle (3,2 m) laisse
	# 1,7 m au-dessus de la dernière marche (2,1 m au moins).
	var doc := half_level()
	doc.pieces.append({"id": "pu", "nom": "Dessus", "altitude": 3.5, "zone": String(doc.pieces[0].zone), "contour": rect(4, 1, 11.5, 8)})
	var v := _check(doc)
	assert_true(v.errors().any(func(m): return String(m.fr).contains("plafond trop bas au-dessus des marches")), _errs(v))
	var m: Dictionary = v.errors().filter(func(x): return String(x.fr).contains("plafond trop bas au-dessus des marches"))[0]
	assert_eq(int(m.floor), 0, "cases des marches montrées au niveau du pied")
	assert_false((m.cells as Array).is_empty())


# ------------------------------------------------------------------ pièces empilées

func test_stacked_rooms_need_3_1_m() -> void:
	var doc := _map("empilees", [{"id": "pa", "nom": "Bas", "altitude": 0, "contour": rect(0, 0, 10, 10)}], [3.0, 7.0], [3.25, 0.0], [3.25, 10.0])
	var poly := MapGeom.poly(rect(2, 2, 8, 8))
	var r := MapRules.check_room(doc, 0, poly, "", false, 3.0)
	assert_false(r.ok, "Δ 3,0 m refusé à la pose")
	assert_true(String(r.fr).contains("3,1 m au moins"), String(r.get("fr", "")))
	assert_true(MapRules.check_room(doc, 0, poly, "", false, 3.1).ok, "Δ 3,1 m admis")
	assert_true(MapRules.check_room(doc, 0, poly, "", false, -3.1).ok, "en dessous aussi")
	assert_false(MapRules.check_room(doc, 0, poly, "", true, 1.0).ok, "même pour une découpe")
	assert_true(MapRules.check_room(doc, 0, MapGeom.poly(rect(10, 0, 14, 10)), "", false, 1.5).ok, "côte à côte : n'importe quelle altitude")
	# Validateur : pièce posée sans les règles (fichier, Claude) à 3 m.
	doc.pieces.append({"id": "pb", "nom": "Haut", "altitude": 3.0, "zone": String(doc.pieces[0].zone), "contour": rect(2, 2, 8, 8)})
	var v := MapRaster.build(doc).v
	assert_true(v.errors().any(func(m): return String(m.fr).contains("se recouvrent à 3 m")), _errs(v))
	assert_eq(String(doc.stack_issue(["pb"]).get("b", {}).get("id", "")), "pa")
	doc.find("pb")["altitude"] = 3.1
	assert_false(MapRaster.build(doc).v.errors().any(func(m): return String(m.fr).contains("se recouvrent")), "à 3,1 m : accepté")


func test_ceiling_cut_by_the_slab_is_the_lower_one() -> void:
	# Décision 2 : plafond réel = min(plafond réglé, dessous de la dalle du dessus).
	var doc := _map("plafonds", [
		{"id": "pa", "nom": "Haute", "altitude": 0, "plafond": 5.0, "contour": rect(0, 0, 10, 10)},
		{"id": "pb", "nom": "Basse", "altitude": 0, "plafond": 2.9, "contour": rect(10, 0, 20, 10)},
		{"id": "pc", "nom": "Dessus", "altitude": 3.5, "contour": rect(0, 0, 20, 10)}],
		[3.0, 7.0], [3.25, 0.0], [3.25, 10.0])
	var v := MapRaster.build(doc).v
	assert_eq(MapVertical.ceil_at(v, 0, Vector2i(10, 10)), [3.2, false], "5 m sous une dalle à 3,2 m : la dalle")
	assert_eq(MapVertical.ceil_at(v, 0, Vector2i(30, 10)), [2.9, true], "2,9 m sous une dalle à 3,2 m : son plafond")
	# Pièce empilée plus haut (7 m, dalle à 6,7 m) : plafond réglé ; le mur monte
	# jusqu'à la dalle si elle est à 3 m au plus de son haut, sinon s'arrête.
	doc.find("pc")["altitude"] = 7.0
	v = MapRaster.build(doc).v
	assert_eq(MapVertical.ceil_at(v, 0, Vector2i(10, 10)), [5.0, true], "5 m sous une dalle à 6,7 m : son plafond")
	assert_near(MapVertical.wall_top(v, 0, Vector2i(0, 10)), 6.7, 0.001, "mur de 5 m fermé jusqu'à la dalle (1,7 m au-dessus)")
	assert_near(MapVertical.wall_top(v, 0, Vector2i(40, 10)), 2.9, 0.001, "mur de 2,9 m : la dalle est à 3,8 m au-dessus, il s'arrête")


func test_walls_and_zone_boxes_of_stacked_levels() -> void:
	# Pièces empilées à 3,1 m, demi-niveau, halle : aucun bloc de mur ni boîte de zone qui se recoupe.
	var doc := _map("pile", [
		{"id": "pa", "nom": "Bas", "altitude": 0, "plafond": 2.8, "contour": rect(0, 0, 10, 10)},
		{"id": "pb", "nom": "Milieu", "altitude": 3.1, "plafond": 2.8, "contour": rect(0, 0, 10, 10)},
		{"id": "pc", "nom": "Haut", "altitude": 6.2, "contour": rect(0, 0, 10, 10)}],
		[3.0, 7.0], [3.25, 0.0], [3.25, 10.0])
	doc.objets.append({"id": "e1", "type": "escalier", "altitude": 0, "altitude_haut": 3.1, "rect": [5.0, 1.0, 7.5, 9.0], "monte": "n"})
	doc.objets.append({"id": "e2", "type": "escalier", "altitude": 3.1, "altitude_haut": 6.2, "rect": [1.0, 1.0, 3.5, 9.0], "monte": "s"})
	doc.ouvertures.append({"id": "w2", "type": "fenetre", "altitude": 3.1, "position": [8.25, 10.0]})
	doc.ouvertures.append({"id": "w3", "type": "fenetre", "altitude": 6.2, "position": [8.25, 10.0]})
	_export_sane("pile à 3,1 m", doc)
	_export_sane("demi-niveau", half_level())
	_export_sane("halle haute", high_hall())
	var lay := _export_sane("halle et demi-niveau", split_hall())
	assert_eq(lay.stairs.size(), 3, "trois escaliers (0 -> 1,5, 0 -> 3,5, 0 -> 7 m)")
	# Carte livrée : toujours sans recoupement.
	_export_sane("draft_arena", EditorMap.load_dir(EditorMap.EXAMPLES.draft_arena))
