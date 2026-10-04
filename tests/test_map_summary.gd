extends TestCase
## Résumé de carte de l'agent (MapSummary, port de l'ancien tools/mcp/map_geom.py) :
## la sortie GDScript est celle du Python de référence
## enregistrée dans tests/fixtures/map_summary/ (cartes réelles de l'éditeur,
## formes tordues, couloirs droits / en L / refusés, grosse carte aléatoire),
## arrondis et distances au bit près ; plus les cas de géométrie des tests du pont.
## NB : JSON.parse_string de Godot ne relit au bit près que les décimaux courts
## (les flottants à 17 chiffres peuvent changer d'un bit) ; les documents des
## fixtures n'ont donc que des nombres courts, numbers.json donne les bits IEEE,
## et la sortie est comparée telle quelle (2 et 2.0 égaux, comme en JSON) puis,
## après aller-retour JSON, à 1e-9 près.

const DIR := "res://tests/fixtures/map_summary/"


func _load(name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(DIR + name))


## Aller-retour JSON, comme la réponse du serveur MCP.
func _rt(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v, "", false, true))


## Première différence entre deux valeurs JSON ("" si égales ; 2 et 2.0 égaux ;
## tol : écart permis entre deux nombres).
func _diff(a: Variant, b: Variant, path := "", tol := 0.0) -> String:
	if (a is int or a is float) and (b is int or b is float):
		var ok: bool = float(a) == float(b) or absf(float(a) - float(b)) <= tol
		return "" if ok else "%s : %s ≠ %s" % [path, var_to_str(a), var_to_str(b)]
	if typeof(a) != typeof(b):
		return "%s : type %s ≠ %s (%s / %s)" % [path, type_string(typeof(a)), type_string(typeof(b)), str(a), str(b)]
	if a is Array:
		if a.size() != b.size():
			return "%s : %d éléments ≠ %d (%s / %s)" % [path, a.size(), b.size(), str(a), str(b)]
		for i in a.size():
			var d := _diff(a[i], b[i], "%s[%d]" % [path, i], tol)
			if d != "":
				return d
		return ""
	if a is Dictionary:
		if a.size() != b.size() or not a.keys().all(func(k: Variant) -> bool: return b.has(k)):
			return "%s : clés %s ≠ %s" % [path, str(a.keys()), str(b.keys())]
		for k: Variant in a:
			var d := _diff(a[k], b[k], "%s.%s" % [path, k], tol)
			if d != "":
				return d
		return ""
	return "" if a == b else "%s : %s ≠ %s" % [path, str(a), str(b)]


func _run(doc: Dictionary, fn: String, args: Array) -> Dictionary:
	match fn:
		"summarize":
			return MapSummary.summarize(doc, int(args[0]) if not args.is_empty() else -1)
		"find_elements":
			return MapSummary.find_elements(doc, args[0])
		"plan_corridor":
			return MapSummary.plan_corridor(doc, args[0], args[1], float(args[2]), int(args[3]))
	return {}


func test_fixtures_identiques_au_python() -> void:
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool:
		return f.ends_with(".json") and f != "numbers.json")
	assert_true(files.size() >= 10, "fixtures présentes")
	var n := 0
	for f: String in files:
		var fx: Dictionary = _load(f)
		for c: Dictionary in fx.calls:
			# Document neuf à chaque appel (le résumé ne doit rien modifier).
			var doc: Dictionary = fx.doc.duplicate(true)
			var got := _run(doc, c.fn, c.args)
			var d := _diff(got, c.out)
			if d == "":
				d = _diff(_rt(got), c.out, "(JSON)", 1e-9)
			if d != "":
				failures.append("%s %s%s %s" % [f, c.fn, str(c.args), d])
			assert_eq(doc, fx.doc, "%s %s : document intact" % [f, c.fn])
			n += 1
	assert_true(n > 200, "assez de cas (%d)" % n)


## Flottant donné par ses bits IEEE en hexadécimal (gros-boutiste).
func _f(h: String) -> float:
	var b := h.hex_decode()
	b.reverse()
	return b.decode_double(0)


func test_nombres_comme_python() -> void:
	var nums: Dictionary = _load("numbers.json")
	for c: Array in nums.round2:
		assert_eq(MapSummary.r2(_f(c[0])), _f(c[1]) + 0.0, "round(%s, 2)" % c[0])
	for c: Array in nums.fmt2:
		assert_eq(MapSummary._fmt(_f(c[0]), 2), c[1], "%%.2f de %s" % c[0])
	for c: Array in nums.fmt1:
		assert_eq(MapSummary._fmt(_f(c[0]), 1), c[1], "%%.1f de %s" % c[0])
	for c: Array in nums.snap:
		assert_eq(MapSummary.snap(_f(c[0])), _f(c[1]), "snap(%s)" % c[0])
	for c: Array in nums.hypot:
		assert_eq(MapSummary.hypot(_f(c[0]), _f(c[1])), _f(c[2]), "hypot(%s, %s)" % [c[0], c[1]])
	for c: Array in nums.fsum:
		assert_eq(MapSummary._fsum((c[0] as Array).map(_f)), _f(c[1]), "sum(%s)" % str(c[0]))


## Cas de TestPure.test_geometry (tools/mcp/test_map_editor_mcp.py).
func test_geometrie() -> void:
	var a := MapSummary.pts([[0, 0], [10, 0], [10, 8], [0, 8]])
	var b := MapSummary.pts([[10, 2], [14, 2], [14, 6], [10, 6]])
	var c := MapSummary.pts([[13, 0], [20, 0], [20, 3], [13, 3]])
	assert_eq(MapSummary.bbox(a), [0.0, 0.0, 10.0, 8.0])
	assert_eq(MapSummary.area(a), 80.0)
	assert_true(MapSummary.is_axis_rect(a))
	assert_eq(MapSummary.common_segments(a, b), [[[10.0, 2.0], [10.0, 6.0]]])
	assert_false(MapSummary.polys_overlap(a, b))
	assert_true(MapSummary.polys_overlap(b, c))
	assert_true(MapSummary.polys_overlap(a, a))
	var cp := MapSummary.closest_points(a, MapSummary.pts([[15, 10], [18, 10], [18, 12], [15, 12]]))
	assert_near(cp[0], sqrt(5.0 * 5.0 + 2.0 * 2.0), 1e-9)
	assert_eq([cp[1], cp[2]], [[10.0, 8.0], [15.0, 10.0]])
	assert_eq(MapSummary.nearest_edge_point(a, b), [10.0, 2.0])
	# Points illisibles ignorés.
	assert_eq(MapSummary.pts([[1, 2], ["x", 3], [4], null, ["5", true]]), [[1.0, 2.0], [5.0, 1.0]])


## Cas de TestPure.test_l_corridor.
func test_couloir_en_l() -> void:
	var doc := {"pieces": [
		{"id": "p1", "etage": 0, "zone": "z1", "contour": [[0, 0], [8, 0], [8, 8], [0, 8]]},
		{"id": "p2", "etage": 0, "zone": "z2", "contour": [[16, 14], [24, 14], [24, 22], [16, 22]]},
	], "ouvertures": [], "objets": []}
	var plan := MapSummary.plan_corridor(doc, "p1", "p2", 2.0)
	assert_eq(plan.get("type"), "en_L")
	var poly := MapSummary.pts(plan.ops[0].el.contour)
	assert_eq(poly.size(), 6)
	assert_near(MapSummary.area(poly), (plan.longueurs[0] + plan.longueurs[1]) * 2 - 4, 0.001)
	assert_eq(plan.ops[2].el.prix, 750)
	doc.pieces[1].etage = 1
	assert_true(MapSummary.plan_corridor(doc, "p1", "p2", 2.5).has("error"), "étages différents")


## Cas de TestPure.test_resolve_room.
func test_piece_par_nom() -> void:
	var doc := {"pieces": [
		{"id": "p1", "nom": "Salle Électrique", "contour": []},
		{"id": "p2", "nom": {"fr": "Théâtre", "en": "Theater"}, "contour": []},
		{"id": "p3", "nom": "Cave", "contour": []},
		{"id": "p4", "nom": "cave", "contour": []},
	]}
	assert_eq(MapSummary.resolve_room(doc, "p3"), {"id": "p3"})
	assert_eq(MapSummary.resolve_room(doc, "salle  electrique"), {"id": "p1"})
	assert_eq(MapSummary.resolve_room(doc, "THEATRE"), {"id": "p2"})
	assert_eq(MapSummary.resolve_room(doc, "theater"), {"id": "p2"})
	assert_true(MapSummary.resolve_room(doc, "Cave").has("error"), "ambigu")
	assert_true(MapSummary.resolve_room(doc, "").has("error"), "vide")


## Cas du pont sur sa petite carte (test_get_map_summary_full_element,
## test_summary_keeps_scale_and_tilt, test_plan_corridor[_by_name]).
func test_petite_carte() -> void:
	var fx: Dictionary = _load("small_map.json")
	var doc: Dictionary = fx.doc
	var s: Dictionary = _rt(MapSummary.summarize(doc))
	var f0: Dictionary = s.etages[0]
	var p1: Dictionary = f0.pieces.filter(func(p: Dictionary) -> bool: return p.id == "p1")[0]
	assert_eq(p1.bbox, [0.0, 0.0, 10.0, 8.0])
	assert_eq(p1.surface, 80.0)
	assert_eq(p1.voisins[0].id, "p2")
	var p2: Dictionary = f0.pieces.filter(func(p: Dictionary) -> bool: return p.id == "p2")[0]
	assert_eq(p2.proches[0].id, "p3")
	assert_eq(p2.proches[0].distance, 6.0)
	var o1: Dictionary = f0.ouvertures.filter(func(o: Dictionary) -> bool: return o.id == "o1")[0]
	assert_eq(o1.pieces, ["p1", "p2"])
	assert_eq(o1.prix, 750.0)
	assert_eq(f0.objets.atout[0].atout, "lazarus")
	assert_true(s.zones.filter(func(z: Dictionary) -> bool: return z.id == "z1")[0].get("depart", false))
	var el := MapSummary.find_elements(doc, ["o1", "zz"])
	assert_eq(el.elements.o1.coll, "ouvertures")
	assert_eq(el.absents, ["zz"])
	var plan := MapSummary.plan_corridor(doc, "p2", "p3", 2.5)
	assert_eq(plan.get("type"), "droit")
	var bb := MapSummary.bbox(MapSummary.pts(plan.ops[0].el.contour))
	assert_eq(plan.ops[0].el.zone, "z2")
	assert_eq([bb[0], bb[2]], [18.0, 24.0])
	assert_near(bb[3] - bb[1], 2.5)
	assert_eq(plan.ops[2].el.type, "porte")
	assert_eq(MapSummary.plan_corridor(doc, "atelier", "CAVE", 2.5).ops, plan.ops)
	assert_true(String(MapSummary.plan_corridor(doc, "p1", "p2", 2.5).get("error", "")).contains("déjà reliées"))
	assert_true(String(MapSummary.plan_corridor(doc, "entree", "Atelier", 2.5).get("error", "")).contains("déjà reliées"))
	assert_true(String(MapSummary.plan_corridor(doc, "Grenier", "p3", 2.5).get("error", "")).contains("inconnue"))
	var d := {"carte": {"etages": [{"sol": 0, "hauteur": 3.2}]}, "pieces": [], "ouvertures": [], "zones": [],
		"objets": [{"id": "d1", "type": "prefab", "prefab": "poutre", "etage": 0, "position": [5, 5],
			"echelle": [1.5, 1.5, 1.5], "incl": [0, 30]}]}
	var d1: Dictionary = MapSummary.summarize(d).etages[0].objets.prefab[0]
	assert_eq(d1.echelle, [1.5, 1.5, 1.5])
	assert_eq(d1.incl, [0, 30])


## Temps du résumé (le serveur MCP répond dans le fil de l'éditeur).
func test_temps_du_resume() -> void:
	for f: String in ["map_verruckt.json", "big_random.json"]:
		var doc: Dictionary = _load(f).doc
		var t0 := Time.get_ticks_usec()
		MapSummary.summarize(doc)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("  MapSummary.summarize(%s, %d pièces) : %.1f ms" % [f, doc.pieces.size(), ms])
		assert_true(ms < 2000.0, "%s : résumé en %.0f ms" % [f, ms])
