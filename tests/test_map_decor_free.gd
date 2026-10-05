extends TestCase
## Décor posé librement dans l'éditeur de cartes (docs/MAP_OBJECTS.md § 8) :
## l'aspect des murs (texture de chaque face) ne dépend que des pièces, jamais
## d'un objet posé contre eux (décor, caisse, baril, arme murale, porte,
## débris) ; décor contre un mur, à moitié dedans, au centimètre, tourné ;
## appliques à toute hauteur et partout le long d'un mur ; caisse et baril
## construits et heurtés à leur vraie place ; format 7 (hauteur d'une
## applique) relu, contrôlé, formats d'avant lus tels quels.

const TMP := "res://tests/_out/test_map_decor_free"
const OFF := MapGeom.WORLD_OFFSET
const DECOR_MATS := ["crate", "barrel"]


func before_each() -> void:
	EditorMap.root_override = ProjectSettings.globalize_path(TMP + "/maps")


func after_each() -> void:
	EditorMap.root_override = ""


# ------------------------------------------------------------------ outils

static func _room(doc: EditorMap, x0: float, y0: float, x1: float, y1: float, walls: String) -> Dictionary:
	var id := doc.new_id("p")
	var z := String(doc.add_zone("Salle " + id, "Room " + id).id)
	var r := {"id": id, "nom": "Salle " + id, "altitude": 0, "zone": z, "contour": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]],
		"surface_murs": walls}
	doc.pieces.append(r)
	return r


static func _obj(doc: EditorMap, o: Dictionary) -> Dictionary:
	o["id"] = doc.new_id("x")
	o["altitude"] = 0.0
	doc.objets.append(o)
	return o


## Deux salles collées : A (0..14 × 0..10, briques), B (14..24 × 0..10, vert),
## porte entre elles, fenêtres, départ ; rien contre les murs.
static func two_rooms() -> EditorMap:
	var doc := EditorMap.blank("decor_libre", "DÉCOR LIBRE", "FREE DECOR")
	_room(doc, 0, 0, 14, 10, "brick")
	_room(doc, 14, 0, 24, 10, "wall_green")
	doc.depart = String(doc.zones[0].id)
	doc.ouvertures.append({"id": "o1", "type": "porte", "altitude": 0, "position": [14.0, 5.25], "largeur": 2.0, "prix": 750})
	doc.ouvertures.append({"id": "o2", "type": "fenetre", "altitude": 0, "position": [3.25, 0.0]})
	doc.ouvertures.append({"id": "o3", "type": "fenetre", "altitude": 0, "position": [19.25, 0.0]})
	_obj(doc, {"type": "depart", "position": [7.0, 6.0]})
	_obj(doc, {"type": "boite", "position": [19.0, 10.0], "mur": "s", "depart": true})
	return doc


static func layout(doc: EditorMap) -> Dictionary:
	var v := MapRaster.build(doc).v
	v.analyze()
	return MapLayoutExport.build(v)


## Matériau du mur (bloc d'architecture) au point (x, y) de l'éditeur, à
## `h` m du sol ; "" : pas de mur (ouverture, trou).
static func wall_mat_at(data: Dictionary, x: float, y: float, h := 1.2) -> String:
	var p := Vector3(x + OFF, h, y + OFF)
	for b in data.blocks:
		var bx: Array = b.box
		if String(b.mat) in DECOR_MATS:
			continue
		if p.x > float(bx[0]) and p.x < float(bx[3]) and p.y > float(bx[1]) and p.y < float(bx[4]) and p.z > float(bx[2]) and p.z < float(bx[5]):
			return String(b.mat)
	return ""


## Sondes juste derrière chaque face intérieure de mur (5 cm dans le mur), le
## long de tous les murs des deux salles : {"x:y": matériau}.
static func probes(data: Dictionary) -> Dictionary:
	var out := {}
	var along := func(a: float, b: float) -> Array:
		var l := []
		var t := a + 0.35
		while t < b - 0.3:
			l.append(snappedf(t, 0.01))
			t += 0.2
		return l
	for x in along.call(0.0, 14.0):
		out["%s:%s" % [x, 0.2]] = wall_mat_at(data, x, 0.2)    # A, mur nord
		out["%s:%s" % [x, 9.8]] = wall_mat_at(data, x, 9.8)    # A, mur sud
	for x in along.call(14.0, 24.0):
		out["%s:%s" % [x, 0.2]] = wall_mat_at(data, x, 0.2)
		out["%s:%s" % [x, 9.8]] = wall_mat_at(data, x, 9.8)
	for y in along.call(0.0, 10.0):
		out["%s:%s" % [0.2, y]] = wall_mat_at(data, 0.2, y)      # A, mur ouest
		out["%s:%s" % [13.8, y]] = wall_mat_at(data, 13.8, y)    # A, côté du mur mitoyen
		out["%s:%s" % [14.2, y]] = wall_mat_at(data, 14.2, y)    # B, côté du mur mitoyen
		out["%s:%s" % [23.8, y]] = wall_mat_at(data, 23.8, y)    # B, mur est
	return out


## Différences entre deux relevés de sondes (texte vide : identiques).
static func diff(a: Dictionary, b: Dictionary) -> String:
	var out := []
	for k in a:
		if String(a[k]) != String(b.get(k, "?")):
			out.append("%s : %s -> %s" % [k, a[k], b.get(k, "?")])
	return ", ".join(out.slice(0, 6)) + (" (+%d)" % (out.size() - 6) if out.size() > 6 else "")


# ------------------------------------------------------------------ bug du papier peint

func test_reference_probes_follow_rooms() -> void:
	var p := probes(layout(two_rooms()))
	assert_eq(String(p["5.35:0.2"]), "brick", "A nord : briques")
	assert_eq(String(p["0.2:2.35"]), "brick", "A ouest : briques")
	assert_eq(String(p["13.8:2.35"]), "brick", "mur mitoyen côté A : briques")
	assert_eq(String(p["14.2:2.35"]), "wall_green", "mur mitoyen côté B : vert")
	assert_eq(String(p["13.8:5.35"]), "", "porte : pas de mur à hauteur d'homme")


## Le bug signalé : un décor poussé contre un mur changeait la texture de ce
## mur (la face prenait celle de la pièce d'à côté, ou la texture par défaut).
func test_wall_texture_ignores_objects_pushed_against_walls() -> void:
	var ref := probes(layout(two_rooms()))
	var cases := [
		["bureau contre le mur ouest", _prefab_at("bureau", 1.0, 5.0, 0)],
		["bureau contre le mur mitoyen (côté A)", _prefab_at("bureau", 13.0, 2.5, 0)],
		["sacs de sable contre le mur nord", _prefab_at("sacs_sable", 7.0, 0.75, 0)],
		["étagère dans l'angle nord-ouest", _prefab_at("etagere", 1.0, 0.5, 0)],
		["gravats contre le mur mitoyen (côté B)", _prefab_at("gravats", 15.75, 2.0, 0)],
		["caisse contre le mur sud", {"type": "caisse", "position": [6.0, 9.25]}],
		["baril contre le mur mitoyen", {"type": "baril", "position": [13.5, 8.5]}],
		["barrière invisible contre le mur est", {"type": "bloc_invisible", "rect": [23.25, 3.0, 23.75, 6.0]}],
		["tonneaux tournés dans un angle", _prefab_at("tonneaux", 22.75, 8.75, 30)],
		["lampe de bureau au pied du mur", _light_at("lampe_bureau", 0.5, 7.5)],
		["brasero au pied du mur", _light_at("feu", 23.25, 1.25)],
	]
	for c in cases:
		var doc := two_rooms()
		_obj(doc, (c[1] as Dictionary).duplicate(true))
		var d := diff(ref, probes(layout(doc)))
		assert_eq(d, "", "%s : texture des murs inchangée" % c[0])


## Arme murale, porte et débris déplacés jusqu'à toucher un mur : seule leur
## propre ouverture change, jamais la texture des autres murs.
func test_wall_texture_ignores_wall_buys_and_doors_near_corners() -> void:
	var ref := probes(layout(two_rooms()))
	var doc := two_rooms()
	_obj(doc, {"type": "arme", "arme": "m14", "position": [0.75, 10.0], "mur": "s"})   # dans l'angle sud-ouest
	_obj(doc, {"type": "atout", "atout": "titan", "position": [24.0, 1.25], "mur": "e"})
	assert_eq(diff(ref, probes(layout(doc))), "", "arme murale et atout dans un angle : murs inchangés")
	for t in ["porte", "debris"]:
		var d2 := two_rooms()
		# Ouverture poussée au bout du mur mitoyen (contre le mur nord).
		d2.ouvertures[0]["type"] = t
		d2.ouvertures[0]["position"] = [14.0, 1.25]
		var got := probes(layout(d2))
		var bad := []
		for k in ref:
			var y := float(String(k).split(":")[1])
			var x := float(String(k).split(":")[0])
			var in_old := absf(x - 14.0) < 0.5 and y > 4.25 and y < 6.25
			var in_new := absf(x - 14.0) < 0.5 and y > 0.25 and y < 2.25
			if in_old or in_new:
				continue
			if String(ref[k]) != String(got[k]):
				bad.append("%s : %s -> %s" % [k, ref[k], got[k]])
		assert_eq(", ".join(bad), "", "%s au bout du mur : les autres murs gardent leur texture" % t)
		assert_eq(String(got["13.8:1.35"]), "", "%s : l'ouverture à sa nouvelle place" % t)
		assert_eq(String(got["13.8:5.35"]), "brick", "%s : mur refermé à l'ancienne place, côté A en briques" % t)
		assert_eq(String(got["14.2:5.35"]), "wall_green", "%s : mur refermé à l'ancienne place, côté B en vert" % t)
		# Linteau au-dessus de l'ouverture : chaque face garde la texture de sa pièce.
		assert_eq(wall_mat_at(layout(d2), 13.8, 1.25, 2.9), "brick", "%s : linteau côté A" % t)
		assert_eq(wall_mat_at(layout(d2), 14.2, 1.25, 2.9), "wall_green", "%s : linteau côté B" % t)


static func _prefab_at(id: String, x: float, y: float, rot: int) -> Dictionary:
	return {"type": "prefab", "prefab": id, "position": [x, y], "rot": rot}


static func _light_at(id: String, x: float, y: float) -> Dictionary:
	var o: Dictionary = MapCatalog.item("luminaire:" + id).make.duplicate(true)
	o["position"] = [x, y]
	return o


# ------------------------------------------------------------------ pose libre du décor

func test_floor_decor_against_into_walls_and_at_odd_positions() -> void:
	var doc := two_rooms()
	var cases := [
		["baril à cheval sur le mur ouest", {"type": "baril"}, Vector2(0.0, 3.0), true],
		["caisse à moitié dans le mur nord", {"type": "caisse"}, Vector2(4.0, 0.1), true],
		["bureau collé au mur mitoyen", {"type": "prefab", "prefab": "bureau", "rot": 0}, Vector2(13.0, 8.0), true],
		["étagère tournée de 37° dans l'angle", {"type": "prefab", "prefab": "etagere", "rot": 37}, Vector2(0.6, 9.4), true],
		["brasero sur le mur est", MapCatalog.item("luminaire:feu").make.duplicate(true), Vector2(24.0, 7.0), true],
		["suspension au-dessus du mur", MapCatalog.item("luminaire:suspension").make.duplicate(true), Vector2(14.0, 8.5), true],
		["baril dehors, loin des pièces", {"type": "baril"}, Vector2(-3.0, 3.0), false],
		["départ contre un mur (objet de jeu : règle d'avant)", {"type": "depart"}, Vector2(0.1, 3.0), false],
		["apparition dans le mur (objet de jeu)", {"type": "apparition"}, Vector2(0.0, 3.0), false],
	]
	for c in cases:
		var r := MapRules.place_floor_item(doc, 0, c[1], c[2], "", false)
		assert_eq(bool(r.ok), bool(c[3]), "%s : %s" % [c[0], r.get("fr", "accepté")])
		if r.ok:
			assert_true(MapGeom.v2(r.position).distance_to(c[2]) < 0.006, "%s : là où est le curseur (%s)" % [c[0], str(r.position)])
	# Sur la grille : aimanté, mais toujours accepté contre le mur.
	var g := MapRules.place_floor_item(doc, 0, {"type": "caisse"}, Vector2(4.1, 0.2), "", true)
	assert_true(g.ok, "caisse aimantée dans le mur : %s" % g.get("fr", ""))
	# Le décor ne se pose pas sur un objet de jeu ni sur un autre décor (comme avant).
	_obj(doc, {"type": "caisse", "position": [5.25, 5.25]})
	assert_false(MapRules.place_floor_item(doc, 0, {"type": "baril"}, Vector2(5.25, 5.25), "", false).ok, "baril sur la caisse : refusé")
	assert_false(MapRules.place_floor_item(doc, 0, {"type": "baril"}, Vector2(7.0, 6.0), "", false).ok, "baril sur le départ : refusé")
	# Un décor posé dans un mur reste valide (dessin normal, pas en rouge).
	var b := _obj(doc, {"type": "baril", "position": [0.0, 3.0]})
	assert_true(MapRules.check_existing(doc, b).ok, "baril dans le mur : valide")


func test_wall_decor_anywhere_along_a_wall() -> void:
	var doc := two_rooms()
	var sconce: Dictionary = MapCatalog.item("luminaire:applique").make.duplicate(true)
	# Au centimètre, sans grille.
	var r := MapRules.place_wall_item(doc, 0, sconce, Vector2(6.37, 0.6))
	assert_true(r.ok and r.mur == "n", "applique au nord : %s" % str(r))
	assert_eq(r.position, [6.37, 0.0], "au centimètre, sur le trait du mur")
	# Grille : au quart de mètre.
	r = MapRules.place_wall_item(doc, 0, sconce, Vector2(6.37, 0.6), "", true)
	assert_eq(r.position, [6.25, 0.0], "grille : au quart de mètre")
	# Au-dessus de la porte (sa hauteur se règle à part) et jusque dans l'angle.
	r = MapRules.place_wall_item(doc, 0, sconce, Vector2(13.6, 5.25))
	assert_true(r.ok and r.mur == "e" and r.position == [14.0, 5.25], "applique au-dessus de la porte : %s" % str(r))
	r = MapRules.place_wall_item(doc, 0, sconce, Vector2(0.3, 0.1))
	assert_true(r.ok, "applique dans l'angle : %s" % str(r))
	var p := MapGeom.v2(r.position)
	assert_true(p.y >= 0.5 - 0.001 or p.x >= 0.5 - 0.001, "l'applique reste sur la face du mur (pas dans le mur voisin) : %s" % str(p))
	# Au-dessus d'une fenêtre.
	r = MapRules.place_wall_item(doc, 0, sconce, Vector2(3.25, 0.5))
	assert_true(r.ok and r.position == [3.25, 0.0], "applique au-dessus d'une fenêtre : %s" % str(r))
	# Refus : loin d'un mur, hors des pièces.
	assert_false(MapRules.place_wall_item(doc, 0, sconce, Vector2(7.0, 5.0)).ok, "au milieu de la pièce : refusé")
	assert_false(MapRules.place_wall_item(doc, 0, sconce, Vector2(-2.0, 5.0)).ok, "dehors : refusé")
	# Objet de jeu mural : règles d'avant (pas au-dessus d'une porte).
	assert_false(MapRules.place_wall_item(doc, 0, {"type": "arme", "arme": "m14"}, Vector2(13.6, 5.25)).ok, "arme murale devant la porte : refusée")
	# Posée, elle reste valide (check_existing), même au raccord de deux murs.
	var o := sconce.duplicate(true)
	o.merge({"position": [0.0, 0.3], "mur": "o"}, true)
	_obj(doc, o)
	assert_true(MapRules.check_existing(doc, o).ok, "applique contre le mur ouest, près de l'angle : valide")


func test_wall_decor_along_maths() -> void:
	assert_eq(MapRules.wall_decor_along(3.0, 10.0, 0.5, 0.25), 3.0, "au milieu du mur : sous le curseur")
	assert_eq(MapRules.wall_decor_along(-1.0, 10.0, 0.5, 0.25), 0.5, "avant le début : sur la face, contre le mur voisin")
	assert_eq(MapRules.wall_decor_along(11.0, 10.0, 0.5, 0.25), 9.5, "après la fin : de même")
	assert_eq(MapRules.wall_decor_along(0.1, 0.8, 0.5, 0.25), 0.25, "mur court : sans la marge des angles")
	assert_eq(MapRules.wall_decor_along(0.1, 0.3, 0.5, 0.25), 0.15, "mur plus court que l'objet : son milieu")


func test_wall_decor_height_format_7() -> void:
	var doc := two_rooms()
	var o: Dictionary = MapCatalog.item("luminaire:applique").make.duplicate(true)
	o.merge({"position": [7.0, 0.0], "mur": "n"}, true)
	_obj(doc, o)
	assert_near(MapCatalog.wall_light_height(o), 2.0, 0.001, "sans clé : 2 m (comme avant)")
	MapCatalog.set_wall_light_height(o, 2.0)
	assert_false(o.has("hauteur"), "valeur par défaut : jamais écrite")
	MapCatalog.set_wall_light_height(o, 0.65)
	assert_eq(o.get("hauteur"), 0.65, "hauteur choisie")
	var data := layout(doc)
	var fx: Array = data.markers.lamps.filter(func(l): return l.get("fixture", "") == "applique")
	assert_eq(fx.size(), 1, "une applique construite")
	if fx.size() == 1:
		assert_near(float(fx[0].fixture_p[1]), 0.65, 0.001, "applique construite à 0,65 m")
		assert_near(float(fx[0].p[1]), 0.65, 0.001, "lumière à la même hauteur")
	# Plus haut que le plafond : bornée sous lui en jeu.
	MapCatalog.set_wall_light_height(o, 9.0)
	fx = layout(doc).markers.lamps.filter(func(l): return l.get("fixture", "") == "applique")
	assert_true(fx.size() == 1 and float(fx[0].fixture_p[1]) < EditorMap.DEFAULT_CEILING, "sous le plafond (%s)" % str(fx))
	# Enregistrée, relue, contrôlée.
	MapCatalog.set_wall_light_height(o, 2.6)
	var texts := doc.file_texts()
	assert_true(String(texts["objets.json"]).contains("\"hauteur\":2.6"), "clé écrite dans objets.json")
	assert_true(String(texts["carte.json"]).contains("\"format\": %d" % EditorMap.FORMAT) and EditorMap.FORMAT >= 7, "format 7 et plus")
	var back := EditorMap.from_texts(texts)
	assert_near(float(back.objets.filter(func(x): return x.type == "luminaire")[0].hauteur), 2.6, 0.001, "relue")
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "contrôle des cartes : acceptée")
	# Format 17 : plus de maximum de 30 m, seulement la garde technique (10 km).
	for bad in ["\"hauteur\":\"haut\"", "\"hauteur\":-1", "\"hauteur\":20000"]:
		var t := texts.duplicate()
		t["objets.json"] = String(t["objets.json"]).replace("\"hauteur\":2.6", bad)
		assert_false(CustomMapGuard.check_texts(t).reasons.is_empty(), "contrôle des cartes : %s refusée" % bad)
	# Format 6 relu sans rien changer ; clé illisible écrite à la main retirée.
	o.erase("hauteur")
	texts = doc.file_texts()
	texts = load("res://tests/test_levels_migration.gd").as_format(texts, 6)
	back = EditorMap.from_texts(texts)
	assert_eq(back.format_read, 6, "format 6 lu")
	assert_false(back.objets.filter(func(x): return x.type == "luminaire")[0].has("hauteur"), "applique du format 6 : pas de hauteur ajoutée")
	texts["objets.json"] = String(texts["objets.json"]).replace("\"luminaire\":\"applique\"", "\"luminaire\":\"applique\",\"hauteur\":\"x\"")
	back = EditorMap.from_texts(texts)
	assert_false(back.objets.filter(func(x): return x.type == "luminaire")[0].has("hauteur"), "hauteur illisible retirée")


# ------------------------------------------------------------------ construction en jeu

## Une caisse ou un baril entré dans un mur : le mur reste entier (pas de
## trou), le bloc du décor est à sa vraie place, en retrait d'un demi-centimètre
## (aucune face dans le plan d'une face de mur).
func test_crate_and_barrel_into_walls_keep_walls_whole() -> void:
	var ref := probes(layout(two_rooms()))
	var doc := two_rooms()
	_obj(doc, {"type": "caisse", "position": [13.75, 3.0]})     # dans le mur mitoyen, face sur celle du mur côté B
	_obj(doc, {"type": "baril", "position": [0.0, 7.0]})        # à cheval sur le mur ouest
	_obj(doc, {"type": "caisse", "position": [5.37, 7.21]})     # au centimètre, au milieu
	var data := layout(doc)
	assert_eq(diff(ref, probes(data)), "", "murs entiers, même texture")
	assert_eq(wall_mat_at(data, 14.2, 3.0), "wall_green", "le mur mitoyen n'est pas troué côté B")
	var crates: Array = data.blocks.filter(func(b): return String(b.mat) in DECOR_MATS)
	assert_eq(crates.size(), 3, "trois blocs de décor")
	var by_x := {}
	for c in crates:
		by_x[snappedf((float(c.box[0]) + float(c.box[3])) * 0.5 - OFF, 0.01)] = c
	assert_true(by_x.has(13.75) and by_x.has(0.0) and by_x.has(5.37), "blocs à leur vraie place : %s" % str(by_x.keys()))
	if by_x.has(13.75):
		var b: Array = by_x[13.75].box
		assert_near(float(b[3]) - float(b[0]), 1.0 - 2.0 * MapLayoutExport.DECOR_WALL_INSET, 0.0001, "caisse dans le mur : en retrait")
		assert_true(absf(float(b[3]) - (14.25 + OFF)) > 0.002, "aucune face dans le plan de la face du mur côté B")
	if by_x.has(5.37):
		var b: Array = by_x[5.37].box
		assert_near(float(b[0]), 4.87 + OFF, 0.0001, "caisse au centimètre : bloc à sa place exacte")
		assert_near(float(b[2]), 6.71 + OFF, 0.0001)
	# Caisse posée sur la grille, loin des murs : bloc identique à celui d'avant (cases).
	var d3 := two_rooms()
	_obj(d3, {"type": "caisse", "position": [5.25, 5.25]})
	var c3: Array = layout(d3).blocks.filter(func(b): return String(b.mat) == "crate")
	assert_eq(c3[0].box, [4.75 + OFF, 0.0, 4.75 + OFF, 5.75 + OFF, 1.0, 5.75 + OFF], "caisse sur la grille : même bloc qu'avant")


## La vérification ne bloque pas un décor contre ou dans un mur ; un décor
## devant une porte ou une fenêtre est signalé (attention), pas refusé.
func test_validator_warns_for_decor_in_front_of_openings() -> void:
	var doc := two_rooms()
	_obj(doc, {"type": "baril", "position": [0.0, 3.0]})
	_obj(doc, _prefab_at("bureau", 1.0, 5.0, 0))
	var v := MapRaster.build(doc).v
	v.analyze()
	assert_true(v.ok(), "décor contre les murs : carte valide\n%s" % _errs(v))
	assert_true(v.warnings().filter(func(m): return String(m.fr).contains("décor posé devant")).is_empty(), "aucun avertissement de décor")
	# Baril juste devant la porte (côté A) : avertissement, carte toujours valide.
	doc = two_rooms()
	_obj(doc, {"type": "baril", "position": [13.5, 5.0]})
	v = MapRaster.build(doc).v
	v.analyze()
	assert_true(v.ok(), "baril devant la porte : pas d'erreur\n%s" % _errs(v))
	var w: Array = v.warnings().filter(func(m): return String(m.fr).contains("décor posé devant"))
	assert_eq(w.size(), 1, "un avertissement : décor devant la porte")
	if w.size() == 1:
		assert_true(String(w[0].en).contains("prop placed in front"), "en anglais aussi")
	# Devant une fenêtre : les zombies sont gênés.
	doc = two_rooms()
	_obj(doc, {"type": "baril", "position": [3.0, 0.5]})
	v = MapRaster.build(doc).v
	v.analyze()
	assert_true(v.ok(), "baril devant la fenêtre : pas d'erreur\n%s" % _errs(v))
	assert_eq(v.warnings().filter(func(m): return String(m.fr).contains("gêne l'entrée des zombies")).size(), 1, "avertissement : fenêtre gênée")


static func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))
