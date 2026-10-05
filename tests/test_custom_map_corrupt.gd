extends TestCase
## Contrôle des cartes perso (CustomMapGuard) face à des données corrompues ou
## piégées : UTF-8 invalide (surlong, substituts, tronqué), identifiants, noms
## et textes refusés, points et rectangles mal formés, fichiers trop gros ou
## trop imbriqués, trop de sommets, pièces trop grandes, règles de catalogue
## inconnues. Passe par check_texts / unpack quand c'est possible.

const DRAFT := "res://assets/maps/draft_arena/"


func before_each() -> void:
	CustomMapGuard.source_override = {}
	CustomMapGuard.reset_schema()


func after_each() -> void:
	CustomMapGuard.source_override = {}
	CustomMapGuard.reset_schema()


func _draft_texts() -> Dictionary:
	return EditorMap.load_dir(DRAFT).file_texts()


func _with(file: String, v: Variant) -> Dictionary:
	var t := _draft_texts()
	t[file] = v if v is String else JSON.stringify(v)
	return t


func _json(file: String) -> Variant:
	return JSON.parse_string(_draft_texts()[file])


func _objets_plus(extra: Dictionary) -> Dictionary:
	var o = _json("objets.json")
	o.objets.append(extra)
	return o


## Refus attendu, dont la première raison (FR) contient `fr_part`.
func _refused(texts: Dictionary, fr_part: String, what: String) -> void:
	var r := CustomMapGuard.check_texts(texts)
	assert_false(r.ok, "refus attendu : " + what)
	var reasons: Array = r.get("reasons", [])
	assert_true(not reasons.is_empty() and reasons[0] is Array and reasons[0].size() == 2,
		"raison FR/EN : %s -> %s" % [what, str(reasons)])
	if not reasons.is_empty():
		assert_true((fr_part == "" or String(reasons[0][0]).contains(fr_part)) and String(reasons[0][1]) != "",
			"%s : raison « %s » attendue, obtenu %s" % [what, fr_part, str(reasons[0])])


# ------------------------------------------------------------------ UTF-8

const UTF8_GOOD := [
	[0x41], [0xC3, 0xA9], [0xE2, 0x82, 0xAC], [0xE0, 0xA0, 0x80], [0xED, 0x9F, 0xBF],
	[0xF0, 0x9F, 0x98, 0x80], [0xF0, 0x90, 0x80, 0x80], [0xF4, 0x8F, 0xBF, 0xBF],
]

const UTF8_BAD := {
	"octet nul": [0x41, 0x00, 0x42],
	"suite isolée": [0x80],
	"surlong C0": [0xC0, 0x80],
	"surlong C1": [0xC1, 0xBF],
	"surlong E0": [0xE0, 0x80, 0x80],
	"surlong E0 9F": [0xE0, 0x9F, 0xBF],
	"substitut ED A0": [0xED, 0xA0, 0x80],
	"substitut ED BF": [0xED, 0xBF, 0xBF],
	"surlong F0": [0xF0, 0x80, 0x80, 0x80],
	"au-delà de U+10FFFF": [0xF4, 0x90, 0x80, 0x80],
	"octet F5": [0xF5, 0x80, 0x80, 0x80],
	"octet FF": [0xFF],
	"tronqué 2 octets": [0xC3],
	"tronqué 3 octets": [0xE2, 0x82],
	"tronqué 4 octets": [0x41, 0xF0, 0x9F, 0x98],
	"suite invalide (2)": [0xC3, 0x41],
	"suite invalide (3)": [0xE2, 0x82, 0x41],
	"suite invalide (4)": [0xF0, 0x9F, 0xC0, 0x80],
}


func test_utf8_valid_sequences_accepted() -> void:
	for s in UTF8_GOOD:
		var b := PackedByteArray(s)
		assert_true(CustomMapGuard.utf8_ok(b), "séquence valide %s" % b.hex_encode())
		assert_true(CustomMapGuard.decode_utf8(b) is String, "décodée %s" % b.hex_encode())
	assert_true(CustomMapGuard.utf8_ok(PackedByteArray()), "vide accepté")


func test_utf8_invalid_sequences_refused() -> void:
	for what in UTF8_BAD:
		var b := PackedByteArray(UTF8_BAD[what])
		assert_false(CustomMapGuard.utf8_ok(b), "%s refusé (%s)" % [what, b.hex_encode()])
		assert_eq(CustomMapGuard.decode_utf8(b), null, "%s : pas de texte" % what)


func test_package_with_invalid_utf8_refused() -> void:
	# Par l'entrée publique : paquet réseau dont un octet est remplacé.
	var good: PackedByteArray = CustomMapGuard.package_of(EditorMap.load_dir(DRAFT)).bytes
	assert_true(CustomMapGuard.unpack(good).ok, "paquet d'origine lu")
	var at := int(good.size() * 0.5)
	for what in UTF8_BAD:
		var seq: Array = UTF8_BAD[what]
		var b := good.slice(0, at)
		b.append_array(PackedByteArray(seq))
		b.append_array(good.slice(at))
		var u := CustomMapGuard.unpack(b)
		assert_false(u.ok, "paquet avec %s refusé" % what)


# ------------------------------------------------------------------ identifiants

func test_id_ok_bounds() -> void:
	assert_false(CustomMapGuard.id_ok(""), "vide")
	assert_false(CustomMapGuard.id_ok("a".repeat(CustomMapGuard.MAX_ID + 1)), "trop long")
	assert_true(CustomMapGuard.id_ok("a".repeat(CustomMapGuard.MAX_ID)), "longueur maximale")
	for bad in ["a b", "é", "a/b", "..", "a.b", "a:b", "\u0000"]:
		assert_false(CustomMapGuard.id_ok(bad), "« %s » refusé" % bad)
	_refused(_with("objets.json", _objets_plus({"id": "", "type": "lampe", "altitude": 0, "position": [5, 5]})), "identifiant invalide", "id vide")
	_refused(_with("objets.json", _objets_plus({"id": "x".repeat(40), "type": "lampe", "altitude": 0, "position": [5, 5]})), "identifiant invalide", "id trop long")


# ------------------------------------------------------------------ catalogue

func test_as_list_shapes() -> void:
	assert_eq(CustomMapGuard._as_list({"a": 1, "b": 2}), ["a", "b"], "clés d'un dictionnaire")
	assert_eq(CustomMapGuard._as_list(["x", "y"]), ["x", "y"], "tableau")
	assert_eq(CustomMapGuard._as_list(PackedStringArray(["p"])), ["p"], "PackedStringArray")
	assert_eq(CustomMapGuard._as_list(42), [], "autre valeur : liste vide")
	assert_eq(CustomMapGuard._as_list(null), [], "null : liste vide")


func test_rule_of_spec_unknown() -> void:
	assert_eq(CustomMapGuard._rule_of_spec(5), "", "spec qui n'est pas un dictionnaire")
	assert_eq(CustomMapGuard._rule_of_spec("id"), "", "texte au lieu d'une spec")
	assert_eq(CustomMapGuard._rule_of_spec({}), "", "spec sans type")
	assert_eq(CustomMapGuard._rule_of_spec({"t": "script"}), "", "type de spec inconnu")
	assert_eq(CustomMapGuard._rule_of_spec({"t": "text", "max": 999999}), "text:%d" % CustomMapGuard.MAX_TEXT, "longueur de texte bornée")


func test_catalog_unknown_spec_falls_back_to_safe_scalar() -> void:
	# Catalogue dont deux clés de pièce ont une spec inconnue : la règle ""
	# n'accepte qu'un scalaire court et sûr.
	CustomMapGuard.source_override = {"items": MapCatalog.items(), "kinds": {}, "surfaces": MapCatalog.materials(),
		"musics": MapCatalog.musics(), "zone_keys": {},
		"room_keys": {"id": {"t": "id"}, "nom": {"t": "text", "max": 64}, "altitude": {"t": "number"},
			"zone": {"t": "id"}, "contour": {"t": "polygon"}, "plafond": {"t": "number", "min": 2.8},
			"bizarre": 5, "autre": {"t": "inconnu"}}}
	CustomMapGuard.reset_schema()
	var sc := CustomMapGuard.schema()
	assert_eq(sc.room_keys.bizarre, "", "spec non dictionnaire -> règle vide")
	assert_eq(sc.room_keys.autre, "", "spec inconnue -> règle vide")
	assert_true(CustomMapGuard.check_texts(_draft_texts()).ok, "carte d'origine acceptée")
	for ok_v in [true, 12, "texte_court"]:
		var p = _json("pieces.json")
		p.pieces[0]["bizarre"] = ok_v
		var r := CustomMapGuard.check_texts(_with("pieces.json", p))
		assert_true(r.ok, "scalaire sûr %s accepté : %s" % [str(ok_v), str(r.get("reasons"))])
	for bad_v in [[1, 2], {"a": 1}, "../../x", 5000]:
		var p = _json("pieces.json")
		p.pieces[0]["autre"] = bad_v
		_refused(_with("pieces.json", p), "", "valeur %s refusée" % str(bad_v))


# ------------------------------------------------------------------ fichiers : taille, profondeur, lisibilité

func test_check_texts_file_level_refusals() -> void:
	var big := _draft_texts()
	big["carte.json"] = " ".repeat(CustomMapGuard.MAX_PACKAGE_BYTES + 1)
	_refused(big, "trop volumineuse", "fichier de plus de 2 Mo")
	var split := _draft_texts()
	var half := int(CustomMapGuard.MAX_PACKAGE_BYTES * 0.5) + 10
	split["pieces.json"] = " ".repeat(half) + String(split["pieces.json"])
	split["objets.json"] = " ".repeat(half) + String(split["objets.json"])
	_refused(split, "trop volumineuse", "total de plus de 2 Mo")
	_refused(_with("zones.json", "{\"depart\": \"z1"), "mal fermé", "chaîne non fermée")
	_refused(_with("zones.json", "{" + "\"a\":{".repeat(10) + "}".repeat(11)), "trop imbriqué", "profondeur 11")
	_refused(_with("zones.json", "{\"depart\": }"), "illisible", "JSON invalide")
	_refused(_with("zones.json", "\"texte\""), "illisible", "JSON qui n'est pas un objet")
	var not_str := _draft_texts()
	not_str["objets.json"] = 42
	_refused(not_str, "absent", "fichier qui n'est pas un texte")
	var odd_key := _draft_texts()
	odd_key[7] = "x"
	_refused(odd_key, "non autorisé", "clé non textuelle")


func _circle(cx: float, cy: float, r: float, n: int) -> Array:
	var pts := []
	for i in n:
		pts.append([cx + r * cos(TAU * i / n), cy + r * sin(TAU * i / n)])
	return pts


func test_too_many_total_vertices() -> void:
	var rooms := []
	var n := ceili(float(CustomMapGuard.MAX_TOTAL_VERTICES) / CustomMapGuard.MAX_VERTICES) + 1
	for i in n:
		rooms.append({"id": "r%d" % i, "altitude": 0, "contour": _circle(10 + (i % 8) * 20, 10 + int(i / 8.0) * 20, 2.0, CustomMapGuard.MAX_VERTICES)})
	_refused(_with("pieces.json", {"pieces": rooms}), "trop de sommets", "%d sommets" % (n * CustomMapGuard.MAX_VERTICES))


func test_rooms_too_large() -> void:
	var full := [[0, 0], [256, 0], [256, 256], [0, 256]]
	var rooms := [{"id": "g1", "altitude": 0, "contour": full}, {"id": "g2", "altitude": 0, "contour": full}]
	_refused(_with("pieces.json", {"pieces": rooms}), "trop grandes", "deux pièces de 256 x 256 m")


# ------------------------------------------------------------------ points et rectangles

func test_malformed_points() -> void:
	for bad in ["abc", [1, 2, 3], [], [5], {"x": 1, "y": 2}, 12]:
		_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "lampe", "altitude": 0, "position": bad})),
			"point [x, y] attendu", "point %s" % str(bad))
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "lampe", "altitude": 0, "position": [1, "x"]})), "nombre attendu", "coordonnée texte")
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "lampe", "altitude": 0, "position": [-5, 3]})), "hors limites", "coordonnée négative")
	var t := _with("objets.json", _objets_plus({"id": "q1", "type": "lampe", "altitude": 0, "position": [3, 4]}))
	t["objets.json"] = String(t["objets.json"]).replace("[3,4]", "[3,-1e999]")
	assert_true(String(t["objets.json"]).contains("-1e999"), "infini négatif écrit")
	_refused(t, "hors limites", "coordonnée -infinie")
	# Point de contour de pièce mal formé.
	var p = _json("pieces.json")
	p.pieces[0].contour[1] = [1, 2, 3]
	_refused(_with("pieces.json", p), "point [x, y] attendu", "sommet à trois coordonnées")


func test_malformed_rects() -> void:
	for bad in [[1, 2, 3], "1,2,3,4", [1, 2, 3, 4, 5], null]:
		_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "pilier", "altitude": 0, "rect": bad})),
			"rectangle [x0, y0, x1, y1] attendu", "rectangle %s" % str(bad))
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "pilier", "altitude": 0, "rect": [1, 2, "x", 4]})), "nombre attendu", "rectangle avec texte")
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "pilier", "altitude": 0, "rect": [1, 2, 300, 4]})), "hors limites", "rectangle hors terrain")
	_refused(_with("objets.json", _objets_plus({"id": "q1", "type": "pilier", "altitude": 0, "rect": [1, 2, [3], 4]})), "nombre attendu", "rectangle imbriqué")


# ------------------------------------------------------------------ noms et textes

const BAD_ROOM_NAMES := ["[b]gras[/b]", "<i>x</i>", "a\u0007b", "..\\evil", 42, ["x"], null]


func _room_names_check(fr_part: String, what: String) -> void:
	for bad in BAD_ROOM_NAMES + ["A".repeat(65)]:
		var p = _json("pieces.json")
		p.pieces[0]["nom"] = bad
		_refused(_with("pieces.json", p), fr_part, "%s : nom de pièce %s" % [what, str(bad).left(20)])
	var ok = _json("pieces.json")
	ok.pieces[0]["nom"] = "Salle d'essai n°2"
	var r := CustomMapGuard.check_texts(_with("pieces.json", ok))
	assert_true(r.ok, "%s : nom ordinaire accepté %s" % [what, str(r.get("reasons"))])


func test_room_names_refused() -> void:
	# Catalogue de l'éditeur (format 2 : nom de pièce = règle « text:64 »).
	_room_names_check("texte refusé", "catalogue réel")
	# Catalogue sans room_keys (format 1 : règle « name »).
	CustomMapGuard.source_override = {"items": MapCatalog.items(), "surfaces": MapCatalog.materials(), "musics": MapCatalog.musics()}
	CustomMapGuard.reset_schema()
	assert_eq(CustomMapGuard.schema().room_keys.nom, "name", "règle de nom du format 1")
	assert_true(CustomMapGuard.check_texts(_draft_texts()).ok, "carte d'origine acceptée (format 1)")
	_room_names_check("nom refusé", "format 1")


func test_bilingual_names_refused() -> void:
	var cases := [
		["texte simple", "attendu", "nom qui n'est pas un dictionnaire"],
		[{"fr": "a", "de": "b"}, "clé inconnue", "langue inconnue"],
		[{"fr": 5}, "texte refusé", "nom non textuel"],
		[{"fr": "[url=x]clic[/url]"}, "texte refusé", "balise"],
		[{"en": "A".repeat(65)}, "texte refusé", "nom trop long"],
	]
	for c in cases:
		var d = _json("carte.json")
		d.nom = c[0]
		_refused(_with("carte.json", d), c[1], "carte.json nom : " + c[2])
	# Description (texte long) : retour à la ligne permis, contrôle et balise non.
	var d2 = _json("carte.json")
	d2.description = {"fr": "Ligne 1\nLigne 2", "en": "Line"}
	assert_true(CustomMapGuard.check_texts(_with("carte.json", d2)).ok, "retour à la ligne accepté dans la description")
	for bad in ["bip\u0007", "<script>", "A".repeat(CustomMapGuard.MAX_TEXT + 1)]:
		var d3 = _json("carte.json")
		d3.description = {"fr": bad, "en": "x"}
		_refused(_with("carte.json", d3), "texte refusé", "description %s" % bad.left(12))
	# Nom de zone : même règle bilingue.
	var z = _json("zones.json")
	z.zones[0]["nom"] = "pas un dict"
	_refused(_with("zones.json", z), "attendu", "nom de zone texte simple")


# ------------------------------------------------------------------ règles diverses

func test_zone_reference_rule() -> void:
	for bad in ["../z1", "z 1", 5, ["z1"], null]:
		var p = _json("pieces.json")
		p.pieces[0]["zone"] = bad
		_refused(_with("pieces.json", p), "zone invalide", "zone %s" % str(bad))
	var p2 = _json("pieces.json")
	p2.pieces[0]["zone"] = ""
	assert_true(CustomMapGuard.check_texts(_with("pieces.json", p2)).ok, "zone vide acceptée")


func test_color_and_polygon_rules() -> void:
	var c := CustomMapGuard.Check.new()
	assert_true(CustomMapGuard._rule(c, "color", "#ffcc88", "couleur"), "couleur valide")
	assert_true(c.reasons.is_empty())
	for bad in ["red", "#ffcc8", "#ffcc889", "#gggggg", "ffcc88x", 0xffcc88, null]:
		var c2 := CustomMapGuard.Check.new()
		assert_false(CustomMapGuard._rule(c2, "color", bad, "couleur"), "couleur %s refusée" % str(bad))
		assert_eq(c2.reasons.size(), 1, "une raison")
	var c3 := CustomMapGuard.Check.new()
	assert_false(CustomMapGuard._rule(c3, "polygon", [[1, 1], [2, 2], [3, 1]], "x"), "liste de points hors contour refusée")
	assert_true(String(c3.reasons[0][0]).contains("liste de points"))
	var c4 := CustomMapGuard.Check.new()
	assert_false(CustomMapGuard._rule(c4, "name", "[b]", "x"), "règle name")
	assert_false(CustomMapGuard._rule(c4, "names", "x", "x"), "règle names")
	assert_eq(c4.reasons.size(), 2)


func test_check_reasons_bounded() -> void:
	# Beaucoup d'objets fautifs : au plus MAX_REASONS raisons rapportées.
	var o = _json("objets.json")
	for i in 50:
		o.objets.append({"id": "k%d" % i, "type": "lampe", "altitude": 0, "position": "faux"})
	var r := CustomMapGuard.check_texts(_with("objets.json", o))
	assert_false(r.ok)
	assert_true(r.reasons.size() <= CustomMapGuard.MAX_REASONS, "raisons bornées (%d)" % r.reasons.size())
