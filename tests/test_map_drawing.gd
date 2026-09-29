extends TestCase
## Cartes dessinées (tools/maps/map_drawing.gd, docs/MAP_AUTHORING.md) : le
## validateur accepte une carte correcte et refuse des dessins volontairement
## fautifs avec un message qui pointe la bonne case ; indicateurs d'amusement ;
## export au format de MeshMapLayout ; le layout.json versionné de draft_arena
## correspond à son dessin.

## Caractère -> clé de la légende (un caractère = une case de 0,5 m).
const CH := {
	".": "vide", "#": "mur", "=": "tremie", "/": "escalier", "D": "porte", "R": "debris", "W": "fenetre",
	"a": "zone_a", "b": "zone_b", "c": "zone_c", "S": "depart", "X": "boite", "x": "boite_depart",
	"P": "courant", "J": "atout_titan", "Q": "atout_lazarus", "M": "arme_m14", "K": "pap",
	"T": "teleporteur", "F": "arrivee", "E": "piege", "H": "levier",
}
const PROPS := "id = test_dessin\netage 0 = e0.png, sol 0, plafond 3.2\nzone A = Départ\nzone B = Salle\nporte A-B = 750\n"
const PROPS2 := "id = test_dessin\netage 0 = e0.png, sol 0\netage 1 = e1.png, sol 3.5, plafond 6.7\nzone A = Départ\nzone B = Salle\nzone C = Passerelle\nporte A-B = 750\n"


static func _blank(w: int, h: int) -> Array:
	var rows := []
	for y in h:
		rows.append(".".repeat(w))
	return rows


static func _put(rows: Array, ch: String, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		var s: String = rows[y]
		rows[y] = s.substr(0, x0) + ch.repeat(x1 - x0 + 1) + s.substr(x1 + 1)


## Deux salles (A : départ, B), une porte, une fenêtre chacune, objets muraux.
static func _base() -> Array:
	var r := _blank(46, 30)
	_put(r, "#", 6, 6, 39, 23)
	_put(r, "a", 7, 7, 26, 22)
	_put(r, "b", 28, 7, 38, 22)
	_put(r, "D", 27, 13, 27, 16)
	_put(r, "W", 10, 6, 11, 6)
	_put(r, "W", 32, 6, 33, 6)
	_put(r, "S", 20, 18, 20, 18)
	_put(r, "X", 14, 22, 15, 22)
	_put(r, "X", 35, 22, 36, 22)
	_put(r, "M", 24, 22, 24, 22)
	_put(r, "J", 38, 15, 38, 15)
	_put(r, "P", 29, 22, 29, 22)
	return r


## Étage : passerelle C au-dessus du nord de A, trémie sur le reste de A.
static func _upper() -> Array:
	var r := _blank(46, 30)
	_put(r, "#", 6, 6, 27, 23)
	_put(r, "=", 7, 7, 26, 22)
	_put(r, "c", 7, 7, 14, 9)
	_put(r, "W", 12, 6, 13, 6)
	return r


static func _draw(rows: Array, props := PROPS, upper: Array = []) -> MapDrawing:
	var imgs: Array[Image] = [MapDrawing.image_from_ascii(rows, CH)]
	if not upper.is_empty():
		imgs.append(MapDrawing.image_from_ascii(upper, CH))
	return MapDrawing.from_images(imgs, props)


func _texts(md: MapDrawing, level: String) -> String:
	return "\n".join(md.messages.filter(func(m): return m.level == level).map(func(m): return String(m.text)))


func _expect_error(md: MapDrawing, part: String, where := "") -> void:
	var errs := _texts(md, "erreur")
	assert_false(md.ok(), "carte refusée (%s)" % part)
	assert_true(errs.contains(part), "erreur « %s » attendue, obtenu :\n%s" % [part, errs])
	if where != "":
		assert_true(errs.contains(where), "position %s attendue dans :\n%s" % [where, errs])


func test_legend_colors_are_unambiguous() -> void:
	var cols: Array = MapDrawing.legend().couleurs
	var tol := float(MapDrawing.legend().tolerance)
	var worst := INF
	for i in cols.size():
		for j in range(i + 1, cols.size()):
			var a: Array = cols[i].rgb
			var b: Array = cols[j].rgb
			worst = minf(worst, Vector3(a[0] - b[0], a[1] - b[1], a[2] - b[2]).length())
	assert_true(worst > 2.0 * tol, "deux couleurs de la légende à %.0f l'une de l'autre (tolérance %.0f)" % [worst, tol])


## L'image de légende (tools/maps/legend.py) : carrés aux couleurs EXACTES,
## lus par le convertisseur comme la bonne clé (pipette sûre).
func test_legend_image_swatches_are_exact() -> void:
	var img := Image.new()
	assert_eq(img.load(ProjectSettings.globalize_path("res://docs/map_authoring/legende.png")), OK, "docs/map_authoring/legende.png")
	var cols: Array = MapDrawing.legend().couleurs
	for i in cols.size():
		var x := 30 + floori(i / 15.0) * 620 + 22
		var y := 110 + (i % 15) * 62 + 22
		var c := img.get_pixel(x, y)
		var got := [roundi(c.r * 255), roundi(c.g * 255), roundi(c.b * 255)]
		assert_eq(got, cols[i].rgb.map(func(v): return int(v)), "carré « %s »" % cols[i].nom)


func test_constants_match_the_game() -> void:
	assert_near(MapDrawing.SILL, Barricade.SILL_TOP, 0.0001, "allège des fenêtres")
	assert_near(MapDrawing.LINTEL, Barricade.LINTEL_BOTTOM, 0.0001, "linteau des fenêtres")
	assert_near(MapDrawing.MIN_SPAWN_DIST, Spawner.MIN_PLAYER_DIST, 0.0001, "distance mini d'apparition")
	for m in MapDrawing.MATERIALS:
		assert_true(WorldLook.SURFACES.has(m), "matériau %s connu de WorldLook" % m)
	for e in MapDrawing.legend().couleurs:
		if e.has("atout"):
			assert_true(PerkDB.exists(e.atout), "atout %s" % e.atout)
		if e.has("arme"):
			assert_true(WeaponDB.wall_cost(e.arme) > 0 or KnifeDB.exists(e.arme), "arme murale %s" % e.arme)


func test_valid_map_is_accepted_and_exported() -> void:
	var md := _draw(_base())
	assert_true(md.ok(), "carte correcte acceptée :\n" + _texts(md, "erreur"))
	assert_eq(md.zones, ["a", "b"])
	assert_eq(md.doors.size(), 1)
	assert_eq(md.doors[0].zones, ["a", "b"])
	assert_eq(md.doors[0].cost, 750)
	assert_eq(md.windows.size(), 2)
	var lay := MapDrawingExport.build(md)
	var m: Dictionary = lay.markers
	assert_eq(m.player_spawns.size(), 4, "4 départs autour du carré vert")
	assert_eq(m.doors[0].yaw, snappedf(PI / 2.0, 0.001), "porte dans un mur nord-sud")
	assert_eq(m.doors[0].w, 2.0, "porte de 4 cases = 2 m")
	assert_eq(m.box.size(), 2)
	assert_eq(m.box[0].wall, [0, 0, 1], "boîte contre le mur sud")
	# Face du mur sud de A : case 23 -> 4 + 23 × 0,5 m.
	assert_near(float(m.box[0].p[2]), 15.5, 0.001, "boîte posée sur la face du mur")
	assert_eq(m.perks[0].perk, "titan")
	assert_eq(m.wall_buys[0].weapon, "m14")
	assert_eq(m.windows[0].in, [0, 0, 1], "fenêtre nord, intérieur vers le sud")
	assert_true(m.windows[0].spawns[0][2] < m.windows[0].p[2], "apparition dehors, derrière la fenêtre")
	assert_eq(lay.map_def.doors, {"1": {"cost": 750}})
	assert_eq(lay.map_def.box_starts, [0, 1], "sans « boîte (départ) » : départ au hasard")
	assert_true(lay.zones.has("a") and lay.zones.has("b"))
	assert_eq(lay.walls.size(), 2, "une cour à trois murs par fenêtre")


func test_unknown_color_is_pointed() -> void:
	var img := MapDrawing.image_from_ascii(_base(), CH)
	img.set_pixel(20, 10, Color8(200, 120, 60))
	var md := MapDrawing.from_images([img] as Array[Image], PROPS)
	_expect_error(md, "couleur 200,120,60 inconnue", "(x 20, y 10)")


func test_floor_without_wall() -> void:
	var r := _base()
	_put(r, ".", 6, 17, 6, 19)
	_expect_error(_draw(r), "sol au bord du vide sans mur", "(x 7, y 1")


func test_window_on_an_inner_wall() -> void:
	var r := _base()
	_put(r, "W", 27, 9, 27, 10)
	_expect_error(_draw(r), "doit être dans un mur extérieur", "(x 27, y 9)")


func test_window_without_room_for_zombies() -> void:
	var r := _base()
	_put(r, "#", 9, 2, 12, 2)
	_expect_error(_draw(r), "pas de place dehors pour les zombies", "(x 10, y 6)")


func test_window_size() -> void:
	var r := _base()
	_put(r, "W", 10, 6, 13, 6)
	_expect_error(_draw(r), "une fenêtre = 2 cases")


func test_door_between_parts_of_the_same_zone() -> void:
	var r := _base()
	_put(r, "a", 28, 7, 38, 22)
	_put(r, "J", 38, 15, 38, 15)
	_put(r, "P", 29, 22, 29, 22)
	_put(r, "X", 35, 22, 36, 22)
	_expect_error(_draw(r), "même zone A", "(x 27, y 13)")


func test_door_without_price() -> void:
	_expect_error(_draw(_base(), PROPS.replace("porte A-B = 750\n", "")), "ajoutez « porte A-B = 750 »", "(x 27, y 13)")


func test_door_not_in_a_wall() -> void:
	var r := _base()
	_put(r, "D", 12, 12, 13, 12)
	_expect_error(_draw(r), "doit être posée dans un mur", "(x 12, y 12)")


func test_closed_room_is_unreachable() -> void:
	var r := _base()
	_put(r, "#", 27, 13, 27, 16)
	_expect_error(_draw(r, PROPS.replace("porte A-B = 750\n", "")), "zone B inaccessible depuis le départ")


func test_zone_without_window() -> void:
	var r := _base()
	_put(r, "#", 32, 6, 33, 6)
	_expect_error(_draw(r), "zone B sans fenêtre")


func test_start_too_close_to_every_window() -> void:
	var r := _base()
	_put(r, "a", 20, 18, 20, 18)
	_put(r, "S", 11, 9, 11, 9)
	_expect_error(_draw(r), "à moins de 7 m de toutes les fenêtres")


func test_start_outside_zone_a() -> void:
	var r := _base()
	_put(r, "a", 20, 18, 20, 18)
	_put(r, "S", 33, 18, 33, 18)
	_expect_error(_draw(r), "il doit être dans la zone A", "(x 33, y 18)")


func test_wall_item_away_from_walls() -> void:
	var r := _base()
	_put(r, "b", 38, 15, 38, 15)
	_put(r, "J", 33, 15, 33, 15)
	_expect_error(_draw(r), "doit toucher un mur", "(x 33, y 15)")


func test_wall_item_without_room() -> void:
	var r := _base()
	_put(r, "X", 14, 22, 15, 22)
	_put(r, "#", 14, 21, 14, 21)
	_expect_error(_draw(r), "pas la place")


func test_parasitic_wall_splitting_a_zone() -> void:
	var r := _base()
	_put(r, "#", 17, 7, 17, 22)
	var md := _draw(r)
	_expect_error(md, "inaccessible depuis le départ")
	_expect_error(md, "zone A coupée en morceaux")


func test_narrow_passage() -> void:
	var r := _base()
	_put(r, "#", 17, 7, 17, 22)
	_put(r, "a", 17, 15, 17, 15)
	_expect_error(_draw(r), "passage de 0.5 m", "(x 17, y 15)")


func test_stairs_between_two_floors() -> void:
	var r := _base()
	_put(r, "/", 7, 10, 9, 20)
	var md := _draw(r, PROPS2, _upper())
	assert_true(md.ok(), "escalier et passerelle acceptés :\n" + _texts(md, "erreur"))
	assert_eq(md.stairs.size(), 1)
	assert_eq(md.stairs[0].up, Vector2i(0, -1), "monte vers le nord")
	assert_eq([md.stairs[0].lower, md.stairs[0].upper], ["a", "c"])
	assert_eq(md.open_links.get("a", []), ["c"], "zones reliées par l'escalier")
	var lay := MapDrawingExport.build(md)
	assert_eq(lay.stairs.size(), 1)
	assert_eq(lay.stairs[0].a[1], 0.0)
	assert_eq(lay.stairs[0].b[1], 3.5, "haut de l'escalier au sol de l'étage")
	assert_true(lay.rails.size() >= 2, "garde-corps au bord de la passerelle (%d)" % lay.rails.size())
	for rl in lay.rails:
		# Aucun garde-corps en travers du haut de l'escalier (x 7..9 -> 7,5..9 m, z = 9 m).
		var p: Array = rl.path
		var across_top: bool = is_equal_approx(float(p[0][1]), 9.0) and is_equal_approx(float(p[1][1]), 9.0) and minf(p[0][0], p[1][0]) < 9.0
		assert_false(across_top, "garde-corps qui barre l'escalier : %s" % str(p))


func test_stairs_covered_by_the_upper_floor() -> void:
	var r := _base()
	_put(r, "/", 7, 10, 9, 20)
	var up := _upper()
	_put(up, "c", 8, 15, 8, 15)
	_expect_error(_draw(r, PROPS2, up), "le recouvre", "(x 8, y 15, étage 1)")


func test_stairs_without_landing() -> void:
	var r := _base()
	_put(r, "/", 7, 10, 9, 20)
	var up := _upper()
	_put(up, "=", 7, 9, 14, 9)
	_expect_error(_draw(r, PROPS2, up), "il faut du sol au pied")


func test_stairs_too_narrow() -> void:
	var r := _base()
	_put(r, "/", 7, 10, 8, 20)
	_expect_error(_draw(r, PROPS2, _upper()), "escalier en (x 7, y 10, étage 0) : trop étroit")


func test_tremie_open_to_the_void() -> void:
	var r := _base()
	_put(r, "/", 7, 10, 9, 20)
	var up := _upper()
	_put(up, ".", 27, 12, 27, 14)
	_expect_error(_draw(r, PROPS2, up), "bordée de vide", "étage 1")


func test_fun_indicators() -> void:
	var md := _draw(_base())
	var warn := _texts(md, "attention")
	assert_true(warn.contains("aucune boucle"), "pas de boucle signalée :\n" + warn)
	assert_true(warn.contains("2 emplacement(s) de boîte"), "peu de boîtes signalé")
	assert_true(_texts(md, "info").contains("Courbe d'ouverture (moins cher d'abord) : 750"))
	# Un pilier au milieu de A : boucle de training.
	var r := _base()
	_put(r, "#", 12, 11, 16, 15)
	var md2 := _draw(r)
	assert_true(md2.ok(), _texts(md2, "erreur"))
	assert_true(_texts(md2, "info").contains("Boucle de training autour du bloc en (x 12, y 11)"), _texts(md2, "info"))
	# Première porte trop chère pour BO1.
	var md3 := _draw(_base(), PROPS.replace("750", "2000"))
	assert_true(_texts(md3, "attention").contains("première porte à 2000 points"))


func test_traps_teleporter_and_pack_a_punch() -> void:
	var r := _base()
	_put(r, "E", 30, 11, 31, 14)
	_put(r, "H", 28, 12, 28, 12)
	_put(r, "T", 12, 16, 12, 16)
	_put(r, "F", 34, 18, 34, 18)
	_put(r, "K", 32, 7, 32, 7)
	var md := _draw(r)
	# K collé à la fenêtre : une fenêtre n'est pas un mur.
	_expect_error(md, "Pack-a-Punch en (x 32, y 7) : doit toucher un mur")
	_put(r, "b", 32, 7, 32, 7)
	_put(r, "K", 38, 9, 38, 9)
	md = _draw(r)
	assert_true(md.ok(), _texts(md, "erreur"))
	var m: Dictionary = MapDrawingExport.build(md).markers
	assert_eq(m.traps.size(), 1)
	assert_eq(m.traps[0].lever.wall, [-1, 0, 0], "levier contre le mur ouest de B")
	assert_eq(m.teleporter.exit_zone, "b")
	assert_true(m.has("pap"))
	# Levier sans piège à moins de 10 m.
	_put(r, "H", 7, 20, 7, 20)
	_expect_error(_draw(r), "aucune zone de piège à moins de 10 m", "(x 7, y 20)")


func test_template_properties_parse() -> void:
	var md := MapDrawing.new()
	md.parse_properties(FileAccess.get_file_as_string("res://tools/maps/modele/carte.txt"))
	assert_eq(md.errors().size(), 0, "modèle tools/maps/modele/carte.txt lisible : %s" % str(md.errors()))
	assert_eq(md.floors.size(), 1)


func test_properties_errors() -> void:
	var md := _draw(_base(), PROPS + "sol A = moquette\ncouleur = rouge\n")
	_expect_error(md, "matériau inconnu « moquette »")
	_expect_error(md, "propriété inconnue « couleur »")


func test_draft_arena_drawing_is_valid_and_in_sync() -> void:
	var md := MapDrawing.load_file("res://assets/maps/draft_arena/dessin/carte.txt")
	assert_true(md.ok(), "dessin de draft_arena valide :\n" + _texts(md, "erreur"))
	assert_eq(_texts(md, "attention"), "", "aucun avertissement sur draft_arena")
	var dump: String = load("res://tools/maps/draw2layout.gd").dump(MapDrawingExport.build(md))
	var fresh = JSON.parse_string(dump)
	var saved = JSON.parse_string(FileAccess.get_file_as_string("res://assets/maps/draft_arena/layout.json"))
	assert_true(fresh == saved, "assets/maps/draft_arena/layout.json à jour avec le dessin (relancez sh tools/maps/build_map.sh assets/maps/draft_arena/dessin/carte.txt)")
	var def: MapDef = load(Game.MAP_SCRIPTS["draft_arena"]).new()
	assert_eq(def.zone_names.get("c"), "Entrepôt", "réglages lus dans la description")
	assert_eq(def.doors.get("3", {}).get("cost"), 750.0)
	assert_false(Game.MENU_MAPS.has("draft_arena"), "carte de test, hors menus")
