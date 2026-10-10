extends TestCase
## Format 16 -> 17 (docs/LEVELS_PLAN.md § 2, EditorMap.migrate_levels) : plus
## d'étages, une « altitude » par pièce, ouverture et objet, « altitude_haut »
## des escaliers, plafond de l'étage écrit sur la pièce, double hauteur = grand
## plafond ; cartes de tout format, sans format, idempotence, relecture ;
## contrôle des cartes reçues à deux schémas (CustomMapGuard).


## Textes d'une carte : `carte` (complétée), listes d'éléments.
static func texts(carte: Dictionary, pieces: Array, ouvertures: Array = [], objets: Array = [], zones: Array = []) -> Dictionary:
	var c := {"id": "essai", "nom": {"fr": "ESSAI", "en": "TEST"}}
	c.merge(carte, true)
	return {"carte.json": JSON.stringify(c), "pieces.json": JSON.stringify({"pieces": pieces}),
		"ouvertures.json": JSON.stringify({"ouvertures": ouvertures}), "objets.json": JSON.stringify({"objets": objets}),
		"zones.json": JSON.stringify({"depart": "z1", "zones": zones if not zones.is_empty() else [{"id": "z1", "nom": {"fr": "A", "en": "A"}}]})}


static func rect(x0: float, y0: float, x1: float, y1: float) -> Array:
	return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]


## Deux étages (sols 0 et 4, hauteurs 3,6 et 3) : salle en bas, double hauteur
## à l'ouest (mezzanine au-dessus d'une partie), escalier, porte, objets.
static func two_floors(fmt: Variant = 16) -> Dictionary:
	var carte := {"etages": [{"sol": 0, "hauteur": 3.6}, {"sol": 4, "hauteur": 3}]}
	if fmt != null:
		carte["format"] = fmt
	return texts(carte,
		[{"id": "p1", "nom": "Bas", "etage": 0, "zone": "z1", "contour": rect(0, 0, 10, 8)},
			{"id": "p2", "nom": "Halle", "etage": 0, "zone": "z1", "contour": rect(10, 0, 20, 8), "double_hauteur": true},
			{"id": "p3", "nom": "Mezzanine", "etage": 1, "zone": "z1", "contour": rect(10, 0, 14, 8)},
			{"id": "p4", "nom": "Haut", "etage": 1, "zone": "z1", "contour": rect(0, 0, 10, 8), "plafond": 4.5}],
		[{"id": "o1", "type": "porte", "etage": 0, "position": [10, 4], "largeur": 2, "prix": 750},
			{"id": "o2", "type": "fenetre", "etage": 1, "position": [5, 8]}],
		[{"id": "e1", "type": "escalier", "etage": 0, "rect": [1, 1, 3.5, 7], "monte": "n"},
			{"id": "c1", "type": "caisse", "etage": 1, "position": [8, 4]},
			{"id": "s1", "type": "depart", "position": [5, 4]}])


func test_format_16_converted() -> void:
	var m := EditorMap.from_texts(two_floors())
	assert_true(m.load_errors.is_empty(), str(m.load_errors))
	assert_false(m.carte.has("etages"), "carte.etages retirée")
	for list in [m.pieces, m.ouvertures, m.objets]:
		for e in list:
			assert_false(e.has("etage"), "%s : plus d'etage" % e.id)
			assert_false(e.has("double_hauteur"), "%s : plus de double hauteur" % e.id)
			assert_true(e.has("altitude"), "%s : altitude" % e.id)
	assert_eq(m.levels(), [0.0, 4.0], "niveaux = sols des étages")
	assert_near(EditorMap.alt_of(m.find("p3")), 4.0, 0.0001)
	# Plafond de l'étage écrit sur la pièce (3,6) ; pièce couverte : jusqu'à la dalle (3,7).
	assert_near(EditorMap.room_ceiling(m.find("p1")), 3.7, 0.0001, "pièce entièrement sous une pièce du dessus : dessous de dalle")
	# Double hauteur : jusqu'en haut de l'étage du dessus (4 + 3 - 0).
	assert_near(EditorMap.room_ceiling(m.find("p2")), 7.0, 0.0001, "double hauteur -> plafond de 7 m")
	assert_true(m.is_high(m.find("p2")), "pièce haute")
	assert_eq(m.rooms_through(1).map(func(p): return String(p.id)), ["p2"], "elle traverse le niveau 4 m")
	assert_near(EditorMap.room_ceiling(m.find("p3")), 3.0, 0.0001, "plafond de l'étage 1 écrit")
	assert_near(EditorMap.room_ceiling(m.find("p4")), 4.5, 0.0001, "plafond propre gardé")
	assert_near(EditorMap.alt_of(m.find("o2")), 4.0, 0.0001, "ouverture : altitude de son étage")
	assert_near(EditorMap.alt_of(m.find("c1")), 4.0, 0.0001, "objet : altitude de son étage")
	assert_near(EditorMap.alt_of(m.find("s1")), 0.0, 0.0001, "sans etage : rez-de-chaussée")
	var e1 := m.find("e1")
	assert_near(EditorMap.alt_of(e1), 0.0, 0.0001)
	assert_near(float(e1.altitude_haut), 4.0, 0.0001, "escalier : arrivée au sol de l'étage du dessus")


func test_file_written_in_17() -> void:
	var m := EditorMap.from_texts(two_floors())
	var t := m.file_texts()
	assert_true(String(t["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT), t["carte.json"])
	for f in EditorMap.FILES:
		assert_false(String(t[f]).contains("\"etage\""), "%s sans etage" % f)
		assert_false(String(t[f]).contains("double_hauteur"), "%s sans double hauteur" % f)
	assert_false(String(t["carte.json"]).contains("etages"))
	# Plafond par défaut (3,2) jamais écrit.
	var m2 := EditorMap.from_texts(texts({"format": 16, "etages": [{"sol": 0, "hauteur": 3.2}]}, [{"id": "p1", "etage": 0, "contour": rect(0, 0, 4, 4)}]))
	assert_false(m2.find("p1").has("plafond"), "plafond 3,2 m : clé absente")


func test_idempotent_and_reread() -> void:
	var m := EditorMap.from_texts(two_floors())
	var t1 := m.file_texts()
	var m2 := EditorMap.from_texts(t1)
	assert_eq(m2.file_texts(), t1, "relecture : fichiers identiques")
	m2.migrate_levels()
	assert_eq(m2.file_texts(), t1, "conversion idempotente")


func test_any_format_and_no_format() -> void:
	for fmt in [1, 5, 12, 16, null]:
		var m := EditorMap.from_texts(two_floors(fmt))
		assert_eq(m.levels(), [0.0, 4.0], "format %s : niveaux" % str(fmt))
		assert_near(EditorMap.room_ceiling(m.find("p2")), 7.0, 0.0001, "format %s : double hauteur" % str(fmt))
	# Format 1 sans étages ni « etage » : tout au rez-de-chaussée.
	var m1 := EditorMap.from_texts(texts({"format": 1}, [{"id": "p1", "contour": rect(0, 0, 4, 4)}], [], [{"id": "c1", "type": "caisse", "position": [2, 2]}]))
	assert_eq(m1.levels(), [0.0])
	assert_eq(EditorMap.alt_of(m1.find("c1")), 0.0)
	assert_true(m1.find("c1").has("altitude"))
	# Sans format, avec des étages : lu comme avant (étages convertis).
	var m3 := EditorMap.from_texts(two_floors(null))
	assert_false(m3.carte.has("etages"))
	# Étage sans « sol » : k × 3,5 m ; élément d'un étage absent de la liste : idem.
	var m4 := EditorMap.from_texts(texts({"format": 16, "etages": [{}, {}]}, [{"id": "p1", "etage": 1, "contour": rect(0, 0, 4, 4)},
		{"id": "p2", "etage": 2, "contour": rect(0, 0, 4, 4)}]))
	assert_eq(m4.levels(), [3.5, 7.0])


func test_double_height_on_top_floor_dropped() -> void:
	var m := EditorMap.from_texts(texts({"format": 16, "etages": [{"sol": 0, "hauteur": 3.2}]},
		[{"id": "p1", "etage": 0, "contour": rect(0, 0, 4, 4), "double_hauteur": true}]))
	assert_false(m.find("p1").has("double_hauteur"))
	assert_false(m.find("p1").has("plafond"), "dernier étage : clé simplement retirée")


func test_hand_written_17_with_floor_keys_converted() -> void:
	# Format 17 annoncé mais clés d'étage (fichier modifié à la main) : converti.
	var m := EditorMap.from_texts(texts({"format": 17}, [{"id": "p1", "etage": 0, "contour": rect(0, 0, 4, 4)},
		{"id": "p2", "altitude": 3.5, "contour": rect(0, 0, 4, 4)}]))
	assert_false(m.find("p1").has("etage"))
	assert_eq(m.levels(), [0.0, 3.5], "altitude d'une pièce au format 17 gardée")


func test_stair_top_guessed_when_missing() -> void:
	var m := EditorMap.from_texts(texts({"format": 17}, [{"id": "p1", "altitude": 0, "contour": rect(0, 0, 10, 10)},
		{"id": "p2", "altitude": 4.2, "contour": rect(0, 0, 10, 10)}], [],
		[{"id": "e1", "type": "escalier", "altitude": 0, "rect": [1, 1, 3.5, 8], "monte": "n"},
			{"id": "e2", "type": "escalier", "altitude": 4.2, "rect": [5, 1, 7.5, 8], "monte": "n"}]))
	assert_near(float(m.find("e1").altitude_haut), 4.2, 0.0001, "premier niveau au-dessus dont une pièce contient le haut")
	assert_near(float(m.find("e2").altitude_haut), 7.7, 0.0001, "sinon 3,5 m plus haut")


func test_legacy_draft_arena() -> void:
	var m := EditorMap.load_dir("res://tests/fixtures/maps/legacy_draft_arena/")
	var now := EditorMap.load_dir("res://assets/maps/draft_arena/")
	assert_eq(m.file_texts(), now.file_texts(), "carte livrée = carte d'avant convertie")
	assert_true(String(FileAccess.get_file_as_string("res://assets/maps/draft_arena/carte.json")).contains("\"format\": %d" % EditorMap.FORMAT), "carte livrée au format courant")
	assert_true(m.is_high(m.find("p3")), "entrepôt : pièce haute")


func test_facade() -> void:
	var m := EditorMap.from_texts(two_floors())
	assert_eq(m.level_count(), 2)
	assert_eq(m.level_index(4.003), 1, "même niveau à 5 mm près")
	assert_eq(m.level_index(4.2), -1)
	assert_eq(m.level_of(m.find("c1")), 1)
	assert_near(m.level_alt(2), 7.5, 0.0001, "au-delà du dernier : un niveau tous les 3,5 m")
	assert_eq(m.rooms_on(1).size(), 2)
	assert_eq(m.objects_on(1).map(func(o): return String(o.id)), ["c1"])
	m.view_levels.append(9.0)
	assert_eq(m.levels(), [0.0, 4.0, 9.0], "niveau vide de l'éditeur")
	assert_false(m.file_texts()["pieces.json"].contains("9"), "jamais enregistré")
	m.view_levels.clear()
	# Décaler un niveau : son contenu et l'arrivée des escaliers qui y montent.
	m.shift_level(1, 0.5)
	assert_eq(m.levels(), [0.0, 4.5])
	assert_near(float(m.find("e1").altitude_haut), 4.5, 0.0001)
	assert_near(EditorMap.alt_of(m.find("o2")), 4.5, 0.0001)
	var lv := m.levels().duplicate()
	var c := m.find("c1").duplicate()
	EditorMap.shift_levels(c, lv, -1)
	assert_eq(EditorMap.alt_of(c), 0.0)
	# Étape 1b : pièces empilées à 3,1 m au moins (par paires qui se recouvrent).
	assert_true(m.stack_issue().is_empty())
	m.find("p3")["altitude"] = 2.0
	assert_false(m.stack_issue().is_empty(), "mezzanine à 2 m au-dessus de la halle signalée")
	assert_true(m.stack_issue(["p1"]).is_empty(), "la salle du bas, à côté, n'est pas concernée")
	assert_eq(String(m.stack_issue(["p3"]).get("b", {}).get("id", "")), "p2", "paire mezzanine / halle")


func test_validator_level_checks() -> void:
	var m := EditorMap.from_texts(two_floors())
	# Étape 1b : arrivée d'escalier à une altitude sans pièce : erreur claire.
	m.find("e1")["altitude_haut"] = 6.0
	var v := MapRaster.build(m).v
	assert_true(v.errors().any(func(e): return String(e.fr).contains("il arrive à 6 m, aucune pièce à cette altitude")), "arrivée sans pièce signalée")
	# Élément sans pièce à son altitude : signalé, jamais perdu.
	var m2 := EditorMap.from_texts(two_floors())
	m2.find("c1")["altitude"] = 9.0
	var v2 := MapRaster.build(m2).v
	assert_true(v2.errors().any(func(e): return String(e.fr).contains("aucune pièce à cette altitude")), "objet orphelin signalé")
	# Plafond sans maximum : 20 m accepté.
	var m3 := EditorMap.from_texts(two_floors())
	m3.find("p4")["plafond"] = 20.0
	assert_false(MapRaster.build(m3).v.errors().any(func(e): return String(e.fr).contains("plafond")), "plafond de 20 m admis")


# ------------------------------------------------------------------ cartes reçues : deux schémas

func test_guard_two_schemas() -> void:
	var r16 := CustomMapGuard.check_texts(two_floors())
	assert_true(r16.ok, "format 16 contrôlé avec son schéma : %s" % [r16.reasons])
	assert_false((r16.map as EditorMap).carte.has("etages"), "puis converti")
	var t17 := (r16.map as EditorMap).file_texts()
	var r17 := CustomMapGuard.check_texts(t17)
	assert_true(r17.ok, "format 17 : %s" % [r17.reasons])
	# Clés d'étage dans une carte au format 17 : refus expliqué.
	var bad := t17.duplicate()
	bad["pieces.json"] = JSON.stringify({"pieces": [{"id": "p1", "etage": 0, "contour": rect(0, 0, 4, 4)}]})
	var rb := CustomMapGuard.check_texts(bad)
	assert_false(rb.ok)
	assert_true(String(rb.reasons[0][0]).contains("altitude"), str(rb.reasons))
	var bad2 := t17.duplicate()
	bad2["carte.json"] = String(t17["carte.json"]).replace("\"format\": %d" % EditorMap.FORMAT, "\"format\": %d, \"etages\": []" % EditorMap.FORMAT)
	assert_false(CustomMapGuard.check_texts(bad2).ok, "etages refusé au format 17")
	# « altitude » dans une carte au format 16 : clé inconnue (schéma figé).
	var old := two_floors()
	old["objets.json"] = JSON.stringify({"objets": [{"id": "c1", "type": "caisse", "etage": 0, "altitude": 3.5, "position": [2, 2]}]})
	assert_false(CustomMapGuard.check_texts(old).ok, "altitude refusée au format 16")
	# Pas de borne de conception : altitude libre, plafond de 50 m.
	var free := texts({"format": 17}, [{"id": "p1", "altitude": -7.25, "zone": "z1", "contour": rect(0, 0, 4, 4), "plafond": 50},
		{"id": "p2", "altitude": 120.5, "zone": "z1", "contour": rect(0, 0, 4, 4)}])
	var rf := CustomMapGuard.check_texts(free)
	assert_true(rf.ok, "altitudes et plafond libres : %s" % [rf.reasons])
	var low := texts({"format": 17}, [{"id": "p1", "altitude": 0, "contour": rect(0, 0, 4, 4), "plafond": 2.5}])
	assert_false(CustomMapGuard.check_texts(low).ok, "plafond sous 2,8 m refusé")


func test_guard_memory() -> void:
	# Garde technique : grille cases × niveaux estimée avant de construire.
	var rooms := []
	for i in 300:
		rooms.append({"id": "p%d" % i, "altitude": i * 3.5, "contour": rect(0, 0, 250, 250)})
	assert_false(CustomMapGuard.grid_ok(CustomMapGuard.grid_bytes(rooms)), "300 niveaux de 250 m de côté : refus propre")
	assert_true(CustomMapGuard.grid_ok(CustomMapGuard.grid_bytes(rooms.slice(0, 3))), "3 niveaux : admis")


## Textes d'une carte au format 17 réécrits comme une carte d'un format plus
## ancien `fmt` (≤ 16) : « etage » (indice du niveau) et « etages » à la place
## des altitudes (tests des conversions des formats d'avant).
static func as_format(texts: Dictionary, fmt: int) -> Dictionary:
	var out := texts.duplicate()
	var pieces: Array = JSON.parse_string(String(texts["pieces.json"])).get("pieces", [])
	var alts := []
	for p in pieces:
		alts.append(EditorMap.alt_of(p))
	var lv := EditorMap.merge_alts(alts)
	if lv.is_empty():
		lv = [0.0]
	var to_old := func(e: Dictionary) -> void:
		var k := EditorMap.level_index_in(lv, EditorMap.alt_of(e))
		e.erase("altitude")
		e.erase("altitude_haut")
		e["etage"] = maxi(0, k)
	for pair in [["pieces.json", "pieces"], ["ouvertures.json", "ouvertures"], ["objets.json", "objets"]]:
		var d: Dictionary = JSON.parse_string(String(texts[pair[0]]))
		for e in d.get(pair[1], []):
			to_old.call(e)
		out[pair[0]] = EditorMap.dump(EditorMap._ints(d))
	var c: Dictionary = JSON.parse_string(String(texts["carte.json"]))
	c["format"] = fmt
	c["etages"] = lv.map(func(a): return {"sol": a, "hauteur": EditorMap.DEFAULT_CEILING})
	out["carte.json"] = EditorMap.dump(EditorMap._ints(c))
	return out


func test_as_format_helper() -> void:
	var m := EditorMap.from_texts(two_floors())
	var old := as_format(m.file_texts(), 9)
	assert_true(CustomMapGuard.check_texts(old).ok, "carte réécrite au format 9 : contrôlée avec le schéma figé")
	var back := EditorMap.from_texts(old)
	assert_eq(back.levels(), [0.0, 4.0])
