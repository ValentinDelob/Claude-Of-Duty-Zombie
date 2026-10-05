extends TestCase
## Opérations de l'éditeur collaboratif (MapOps, docs/MAP_COLLAB.md § 2) :
## diff, application, inverse, validation, empreinte, ajouts « $n » de l'agent.


func _map() -> EditorMap:
	var m := EditorMap.blank("essai", "ESSAI", "TEST")
	m.pieces = [
		{"id": "p1", "altitude": 0, "nom": "Hall", "zone": "z1", "contour": [[2, 2], [10, 2], [10, 8], [2, 8]]},
		{"id": "p2", "altitude": 0, "nom": "Salle", "zone": "z2", "contour": [[10, 2], [16, 2], [16, 8], [10, 8]]},
	]
	m.zones = [{"id": "z1", "nom": {"fr": "Hall", "en": "Hall"}}, {"id": "z2", "nom": {"fr": "Salle", "en": "Room"}}]
	m.ouvertures = [{"id": "o1", "type": "porte", "altitude": 0, "position": [10, 5], "largeur": 2.0, "prix": 750}]
	m.objets = [{"id": "w1", "type": "arme", "altitude": 0, "arme": "m14", "position": [2.25, 5.0], "mur": "o"}]
	m.depart = "z1"
	return m


func test_diff_then_apply_gives_the_same_map() -> void:
	var a := _map()
	var b := a.duplicate_map()
	b.pieces[1]["nom"] = "Salle 2"
	b.objets.append({"id": "d1", "type": "prefab", "altitude": 0, "prefab": "caisses", "position": [5.0, 5.0]})
	b.ouvertures.clear()
	b.depart = "z2"
	b.carte["musique"] = "autre"
	var ops := MapOps.diff(a, b.snapshot())
	assert_eq(ops.size(), 5, "nom, objet, porte, départ, carte : %s" % str(ops))
	var c := a.duplicate_map()
	MapOps.apply(c, ops)
	assert_true(c.same_as(b), "diff appliqué : même carte")
	assert_eq(MapOps.hash_of(c), MapOps.hash_of(b), "même empreinte")
	assert_true(MapOps.diff(b, b.snapshot()).is_empty(), "aucun changement : diff vide")


func test_inverse_restores_order_and_content() -> void:
	var a := _map()
	var b := a.duplicate_map()
	# Suppression de la première pièce (et de sa zone), d'un objet, ajout d'un autre.
	b.pieces.remove_at(0)
	b.zones.remove_at(0)
	b.objets.clear()
	b.objets.append({"id": "d1", "type": "prefab", "altitude": 0, "prefab": "caisses", "position": [5.0, 5.0]})
	var ops := MapOps.diff(a, b)
	var inv := MapOps.inverse(a.snapshot(), ops)
	var c := a.duplicate_map()
	MapOps.apply(c, ops)
	assert_true(c.same_as(b), "changement appliqué")
	MapOps.apply(c, inv)
	assert_true(c.same_as(a), "inverse : carte d'avant, pièces et zones à leur place")
	assert_eq(String(c.pieces[0].id), "p1", "la pièce supprimée revient en tête")


func test_apply_on_a_snapshot_and_put_at() -> void:
	var s := _map().snapshot()
	MapOps.apply(s, [{"op": "put", "coll": "zones", "el": {"id": "z9", "nom": {"fr": "A", "en": "A"}}, "at": 0},
		{"op": "del", "coll": "objets", "id": "absent"}, {"op": "put", "coll": "pieces", "el": {"id": "p1", "altitude": 0, "nom": "X", "contour": []}}])
	assert_eq(String(s.zones[0].id), "z9", "put avec at : inséré à l'indice")
	assert_eq(String(s.pieces[0].nom), "X", "put d'un élément existant : remplacé sur place")
	assert_eq((s.objets as Array).size(), 1, "del d'un absent : sans effet")


func test_validate_refuses_bad_batches() -> void:
	assert_eq(MapOps.validate([{"op": "put", "coll": "pieces", "el": {"id": "p1"}}]), "")
	assert_true(MapOps.validate("x") != "", "pas une liste")
	assert_true(MapOps.validate([{"op": "boom"}]) != "", "op inconnue")
	assert_true(MapOps.validate([{"op": "put", "coll": "secrets", "el": {"id": "a"}}]) != "", "coll inconnue")
	assert_true(MapOps.validate([{"op": "put", "coll": "pieces", "el": {"id": ""}}]) != "", "id vide")
	assert_true(MapOps.validate([{"op": "put", "coll": "pieces", "el": {"id": "x".repeat(65)}}]) != "", "id trop long")
	assert_true(MapOps.validate([{"op": "put", "coll": "pieces", "el": {"id": "a", "v": NAN}}]) != "", "nombre non fini")
	assert_true(MapOps.validate([{"op": "put", "coll": "pieces", "el": {"id": "a", "v": Vector2.ONE}}]) != "", "objet Godot")
	var deep: Variant = 1
	for i in 10:
		deep = [deep]
	assert_true(MapOps.validate([{"op": "put", "coll": "pieces", "el": {"id": "a", "v": deep}}]) != "", "trop profond")
	assert_true(MapOps.validate([{"op": "add", "coll": "pieces", "el": {}}]) != "", "add refusé hors agent")
	assert_eq(MapOps.validate([{"op": "add", "coll": "pieces", "el": {"id": "$1"}}], true), "", "add de l'agent")
	assert_true(MapOps.validate([{"op": "add", "coll": "pieces", "el": {"id": "p7"}}], true) != "", "add : id provisoire seulement")
	var many := []
	for i in MapOps.MAX_OPS + 1:
		many.append({"op": "del", "coll": "objets", "id": "a"})
	assert_true(MapOps.validate(many) != "", "plus de 5000 opérations")


func test_hash_ignores_int_float_and_key_order() -> void:
	var a := _map()
	var b := EditorMap.new()
	b.restore(JSON.parse_string(JSON.stringify(a.snapshot(), "", false, true)))
	assert_eq(MapOps.hash_of(a), MapOps.hash_of(b), "carte passée par le JSON : même empreinte")
	b.pieces[0]["nom"] = "Autre"
	assert_true(MapOps.hash_of(a) != MapOps.hash_of(b), "contenu différent : empreinte différente")


func test_resolve_adds_assigns_ids_and_zones() -> void:
	var m := _map()
	var ops := [
		{"op": "add", "coll": "pieces", "el": {"id": "$1", "contour": [[16, 2], [22, 2], [22, 8], [16, 8]]}},
		{"op": "add", "coll": "ouvertures", "el": {"id": "$2", "type": "porte", "position": [16, 5]}},
		{"op": "add", "coll": "objets", "el": {"id": "$3", "type": "luminaire", "luminaire": "ampoule", "position": [19.0, 5.0]}},
		{"op": "add", "coll": "pieces", "el": {"id": "$4", "nom": "Cour", "zone": "z1", "contour": [[2, 8], [10, 8], [10, 14], [2, 14]]}},
		{"op": "depart", "id": "$1"},
	]
	var r := MapOps.resolve_adds(m, ops)
	assert_eq(r.ids, {"$1": "p3", "$2": "o2", "$3": "lu1", "$4": "p4"}, "ids attribués avec les préfixes de l'éditeur")
	var zone_op: Array = r.ops.filter(func(o): return o.op == "put" and o.coll == "zones")
	assert_eq(zone_op.size(), 1, "une zone créée pour la pièce sans zone")
	MapOps.apply(m, r.ops)
	var p3 := m.find("p3")
	assert_false(m.zone(String(p3.zone)).is_empty(), "la nouvelle pièce a sa zone")
	assert_eq(String(m.find("p4").zone), "z1", "zone donnée gardée")
	assert_eq(int(m.find("o2").prix), 1000, "deuxième porte : 1000")
	assert_eq(m.depart, "p3", "« $1 » remplacé partout")
	assert_eq(MapOps.check_elements(m, r.ops).invalid, {}, "éléments admis par le contrôle des cartes")


func test_check_elements_filters_bad_content() -> void:
	var m := _map()
	var r := MapOps.check_elements(m, [
		{"op": "put", "coll": "objets", "el": {"id": "x1", "type": "lance_missiles", "altitude": 0, "position": [1, 1]}},
		{"op": "put", "coll": "objets", "el": {"id": "x2", "type": "caisse", "altitude": 0, "position": [1, 1], "script": "res://a.gd"}},
		{"op": "put", "coll": "objets", "el": {"id": "x3", "type": "caisse", "etage": 5, "position": [1, 1]}},
		{"op": "put", "coll": "objets", "el": {"id": "x4", "type": "caisse", "altitude": 0, "position": [1, 1]}},
	])
	assert_eq(r.ops.size(), 1, "seul l'élément valide passe")
	assert_eq((r.invalid as Dictionary).keys(), ["x1", "x2", "x3"], "raisons : type inconnu, clé inconnue, clé etage du format 16")
