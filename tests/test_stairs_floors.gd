extends TestCase
## Escaliers sur plusieurs étages (docs/MAP_OBJECTS.md § 4) : immeuble de 5
## étages (cage aux volées alternées, escaliers décalés, hauteurs d'étage
## différentes, double hauteur, petite pièce d'arrivée) : chaque escalier posé
## par les règles de l'éditeur (MapRules.check_rect / check_stair), accepté
## par le validateur et exporté d'un sol à l'autre ; chaque refus attendu dit
## quoi et où, avec ses zones (départ, arrivée, trémie, cases fautives) ;
## escalier qui descend (posé depuis l'étage 3, enregistré à l'étage 2 qui
## monte vers 3) et refusé au rez-de-chaussée. La carte sert aussi au
## scénario stairs_floors (le joueur monte au 5e étage, un zombie le suit).

const FLOORS := 5
const W := 16.0
const D := 14.0


# ------------------------------------------------------------------ carte d'essai

## Volée de l'étage k dans la cage (volées alternées, côte à côte) : [rect, monte].
static func flight(k: int) -> Array:
	return [[2.0, 3.0, 4.5, 11.0], "n"] if k % 2 == 0 else [[5.0, 3.0, 7.5, 11.0], "s"]


## Immeuble de 5 étages : une salle de 16 × 14 m par étage (une zone par
## étage, une fenêtre chacune au sud), départ et boîte au rez-de-chaussée,
## sans escalier.
static func tower(sols: Array = [], heights: Array = []) -> EditorMap:
	var doc := EditorMap.blank("immeuble", "IMMEUBLE", "TOWER")
	(doc.carte.etages as Array).clear()
	for k in FLOORS:
		doc.carte.etages.append({"sol": float(sols[k]) if k < sols.size() else k * EditorMap.FLOOR_STEP,
			"hauteur": float(heights[k]) if k < heights.size() else EditorMap.DEFAULT_CEILING})
	for k in FLOORS:
		var z := doc.add_zone("Étage %d" % k, "Floor %d" % k)
		doc.pieces.append({"id": "p%d" % k, "nom": "Étage %d" % k, "etage": k, "zone": String(z.id), "contour": [[0, 0], [W, 0], [W, D], [0, D]]})
	doc.depart = String(doc.pieces[0].zone)
	doc.objets.append({"id": "s1", "type": "depart", "etage": 0, "position": [12.0, 7.0]})
	doc.objets.append({"id": "b1", "type": "boite", "etage": 0, "position": [12.75, 0.0], "mur": "n", "depart": true})
	for k in FLOORS:
		doc.ouvertures.append({"id": "o%d" % k, "type": "fenetre", "etage": k, "position": [12.25, D]})
	return doc


## Immeuble avec sa cage d'escalier complète (du rez-de-chaussée au 5e étage).
static func tower_with_stairs() -> EditorMap:
	var doc := tower()
	for k in FLOORS - 1:
		var f := flight(k)
		doc.objets.append({"id": "e%d" % k, "type": "escalier", "etage": k, "rect": f[0], "monte": f[1]})
	return doc


## Pose d'un escalier comme l'outil de l'éditeur (MapCanvas._creation) :
## refus ou escalier ajouté à la carte.
static func place(doc: EditorMap, k: int, rect: Array, monte: String, down := false) -> Dictionary:
	var o := {"type": "escalier", "rect": rect, "monte": monte}
	var res := MapRules.check_rect(doc, k, "escalier", MapGeom.rect_of(rect), "", 0, "", o, down)
	if res.ok:
		o["id"] = doc.new_id("e")
		o["etage"] = k
		doc.objets.append(o)
	return res


static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


## Chaque volée posée, la carte acceptée, chaque escalier exporté d'un sol à l'autre.
func _accepts(name: String, doc: EditorMap, flights: Array) -> void:
	for k in flights.size():
		var f: Array = flights[k]
		var r := place(doc, k, f[0], f[1])
		assert_true(r.ok, "%s : escalier de l'étage %d posé (%s)" % [name, k, MapRules.why(r)])
	var v := _check(doc)
	assert_true(v.ok(), "%s : carte acceptée :\n%s" % [name, _errs(v)])
	assert_eq(v.stairs.size(), FLOORS - 1, "%s : un escalier par étage" % name)
	for s in v.stairs:
		var f: Array = flights[int(s.floor)]
		assert_eq(s.up, Vector2i(MapGeom.dir_vec(String(f[1]))), "%s : escalier de l'étage %d dans le sens tracé" % [name, s.floor])
	var def := EditorMapDef.from_map(doc, "perso:immeuble")
	assert_true(def.is_valid(), "%s : carte jouable" % name)
	var lay := MapLayoutExport.build(v)
	var ys := []
	for st in lay.stairs:
		ys.append([float(st.a[1]), float(st.b[1])])
	ys.sort()
	for k in FLOORS - 1:
		assert_near(float(ys[k][0]), doc.floor_sol(k), 0.01, "%s : pied de l'escalier %d au sol de l'étage %d" % [name, k, k])
		assert_near(float(ys[k][1]), doc.floor_sol(k + 1), 0.01, "%s : haut de l'escalier %d au sol de l'étage %d" % [name, k, k + 1])


# ------------------------------------------------------------------ cinq étages

func test_five_floors_cage_offset_heights_double_height_small_room() -> void:
	var cage := []
	for k in FLOORS - 1:
		cage.append(flight(k))
	_accepts("cage", tower(), cage)
	# Escaliers décalés, tous vers le nord.
	var offset := []
	for k in FLOORS - 1:
		offset.append([[2.0 + 3.5 * k, 3.0, 4.5 + 3.5 * k, 11.0], "n"])
	_accepts("décalés", tower(), offset)
	# Hauteurs d'étage différentes (3,5 à 4,5 m entre deux sols).
	_accepts("hauteurs", tower([0.0, 4.0, 7.5, 12.0, 15.5], [3.6, 3.2, 4.0, 3.0, 3.2]), cage)
	# Double hauteur à l'étage 2 : l'étage 3 n'est qu'une mezzanine à l'ouest.
	var dh := tower()
	dh.pieces[2]["double_hauteur"] = true
	dh.pieces[3]["contour"] = [[0, 0], [9, 0], [9, D], [0, D]]
	dh.find("o3")["position"] = [8.25, 0.0]
	_accepts("double hauteur", dh, cage)
	# Le dernier escalier arrive dans une petite pièce (5,5 × 11 m) du 5e étage.
	var small := tower()
	small.pieces[4]["contour"] = [[4, 2], [9.5, 2], [9.5, 13], [4, 13]]
	small.find("o4")["position"] = [8.25, 13.0]
	_accepts("petite pièce", small, cage)


func test_refusals_say_what_and_where() -> void:
	var doc := tower_with_stairs()
	# Au même endroit qu'une volée du dessous : dans sa trémie.
	var r := place(doc, 1, flight(0)[0], "n")
	assert_false(r.ok, "escalier empilé refusé")
	assert_true(String(r.fr).contains("passe dans la trémie de l'escalier de l'étage 0 vers l'étage 1") and String(r.fr).contains("(x 2,5 m, y 3,5 m)"), String(r.fr))
	assert_true(String(r.en).contains("stairwell of the stairs from floor 0 to floor 1"), String(r.en))
	var marks: Array = r.get("marks", [])
	var roles := marks.map(func(m): return String(m.role))
	assert_true(roles.has("faute") and roles.has("depart") and roles.has("arrivee") and roles.has("tremie"), "zones montrées : %s" % str(roles))
	assert_false((marks.filter(func(m): return m.role == "faute")[0].cells as Array).is_empty(), "cases fautives")
	# Sa trémie tomberait sur la volée de l'étage du dessus.
	r = place(doc, 0, flight(1)[0], "n")
	assert_true(not r.ok and String(r.fr).contains("tombe sur l'escalier de l'étage 1 vers l'étage 2"), String(r.get("fr", "")))
	# Départ sur une autre volée de l'étage.
	r = place(doc, 2,[8.0, 3.0, 10.5, 11.0], "n")
	assert_true(r.ok, "une volée libre de plus à l'étage 2 (%s)" % MapRules.why(r))
	r = place(doc, 2, [10.0, 6.0, 15.0, 8.5], "e")
	assert_true(not r.ok and String(r.fr).begins_with("l'escalier chevauche l'escalier de l'étage 2 vers l'étage 3 (x "), String(r.get("fr", "")))
	# Départ dans la trémie de la volée du dessous (contour à cheval sur elle).
	var one := tower()
	assert_true(place(one, 0, flight(0)[0], "n").ok)
	r = place(one, 1, [4.0, 6.0, 12.0, 8.5], "e")
	assert_true(not r.ok and String(r.fr).contains("Le départ (au pied, étage 1) tombe dans la trémie de l'escalier de l'étage 0 vers l'étage 1"), String(r.get("fr", "")))
	# Dernier étage : rien au-dessus.
	r = place(doc, 4, [10.0, 3.0, 12.5, 11.0], "n")
	assert_true(not r.ok and String(r.fr).contains("ajoutez d'abord un étage"), String(r.get("fr", "")))
	# Trop raide (3,5 m de montée sur 3,5 m).
	r = place(tower(), 0, [6.0, 6.0, 8.5, 9.5], "n")
	assert_true(not r.ok and String(r.fr).contains("trop raide") and String(r.fr).contains("allongez-le à 4,5 m"), String(r.get("fr", "")))
	# Arrivée sans pièce à l'étage du dessus (une autre pièce y existe).
	var half := tower()
	half.pieces[1]["contour"] = [[8, 0], [W, 0], [W, D], [8, D]]
	r = place(half, 0, [2.0, 3.0, 4.5, 11.0], "n")
	assert_true(not r.ok and String(r.fr).begins_with("pas de pièce à l'étage 1 au-dessus de l'arrivée de l'escalier (x 2,5 m, y 3 m)"), String(r.get("fr", "")))
	assert_eq(int((r.marks as Array).filter(func(m): return m.role == "faute")[0].floor), 1, "cases fautives à l'étage 1")
	# Étage du dessus encore vide : admis (la pièce viendra ensuite).
	var empty := tower()
	empty.pieces = empty.pieces.filter(func(p): return int(p.etage) != 1)
	assert_true(place(empty, 0, [2.0, 3.0, 4.5, 11.0], "n").ok, "étage du dessus vide : posé")
	# Arrivée dans le mur de la pièce du dessus.
	var wall := tower()
	wall.pieces[1]["contour"] = [[0, 3], [W, 3], [W, D], [0, D]]
	r = place(wall, 0, [2.0, 3.0, 4.5, 11.0], "n")
	assert_true(not r.ok and String(r.fr).contains("tombe dans un mur de l'étage 1"), String(r.get("fr", "")))
	# Départ dans le mur de sa propre pièce.
	r = place(tower(), 0, [2.0, 3.0, 4.5, D], "n")
	assert_true(not r.ok and String(r.fr).contains("Le départ (au pied, étage 0) tombe dans un mur"), String(r.get("fr", "")))


func test_validator_says_what_and_where() -> void:
	# Volée posée sans les règles (fichier, autre éditeur) au-dessus d'une autre.
	var doc := tower_with_stairs()
	doc.objets.append({"id": "x1", "type": "escalier", "etage": 2, "rect": flight(1)[0], "monte": "s"})
	var e := _errs(_check(doc))
	assert_true(e.contains("trémie, étage 2) est occupé par l'escalier de l'étage 2 vers l'étage 3"), e)
	# Pas de pièce au-dessus de l'arrivée.
	doc = tower_with_stairs()
	doc.pieces[3]["contour"] = [[9, 0], [W, 0], [W, D], [9, D]]
	var v := _check(doc)
	e = _errs(v)
	assert_true(e.contains("pas de pièce à l'étage 3 au-dessus de son arrivée"), e)
	var m: Dictionary = v.errors().filter(func(x): return String(x.fr).contains("pas de pièce à l'étage 3"))[0]
	assert_eq(int(m.floor), 3, "cases montrées à l'étage 3")
	assert_false((m.cells as Array).is_empty(), "cases de l'arrivée montrées")
	assert_false(e.contains("ambigu"), "plus de « sens ambigu » entre étages empilés")


func test_stairs_going_down() -> void:
	var item := MapCatalog.item("escalier_bas")
	assert_true(bool(item.get("descend", false)), "escalier qui descend dans l'inventaire")
	assert_eq(String(item.make.type), "escalier", "un seul type d'objet")
	assert_eq(MapCatalog.name_of(MapCatalog.item("escalier")), Lang.t("Escalier qui monte", "Stairs going up"))
	# Depuis l'étage 3 : tracé du haut (nord, ici) vers le bas (sud).
	var doc := tower()
	var a := Vector2(2.0, 3.0)
	var b := Vector2(4.5, 11.0)
	var monte := MapRules.stair_dir(a, b, true)
	assert_eq(monte, "n", "il monte vers l'endroit où l'on était (le haut)")
	assert_eq(MapRules.stair_dir(a, b), "s", "l'escalier qui monte suit le tracé")
	var rect := MapGeom.rect_arr(Rect2(a, Vector2.ZERO).expand(b))
	var r := place(doc, 2, rect, monte, true)
	assert_true(r.ok, "posé depuis l'étage 3 (%s)" % MapRules.why(r))
	var o: Dictionary = doc.objets.filter(func(x): return x.type == "escalier")[0]
	assert_eq(int(o.etage), 2, "enregistré à l'étage du dessous")
	assert_false(o.has("descend"), "aucun champ de plus dans la carte")
	var parts := MapRules.stair_parts(o)
	for c in parts.exit:
		assert_true(MapGeom.cell_center(c).y < 3.01, "arrivée en haut là où le tracé a commencé (%s)" % MapGeom.cell_center(c))
	var v := _check(doc)
	assert_eq(v.stairs.size(), 1)
	assert_eq(int(v.stairs[0].floor), 2, "relie les étages 2 et 3")
	assert_eq(v.stairs[0].up, Vector2i(0, -1))
	# Mots du sens de la marche : l'arrivée est en bas.
	var low := tower()
	low.objets.append({"id": "x1", "type": "pilier", "etage": 2, "rect": [8.0, 11.0, 10.5, 12.5]})
	r = place(low, 2, [8.0, 3.0, 10.5, 11.0], "n", true)
	assert_true(not r.ok and String(r.fr).contains("L'arrivée (en bas, étage 2)"), String(r.get("fr", "")))
	# Rez-de-chaussée : pas d'étage en dessous.
	r = place(tower(), -1, rect, monte, true)
	assert_true(not r.ok and String(r.fr).contains("rez-de-chaussée"), String(r.get("fr", "")))
	assert_true(String(r.en).contains("ground floor"), String(r.get("en", "")))


func test_existing_maps_keep_their_stairs() -> void:
	# Les escaliers des cartes livrées et de la carte d'essai des types restent
	# admis par les nouvelles règles de pose (rien en rouge à l'ouverture).
	var maps := [EditorMap.load_dir(EditorMap.EXAMPLES.draft_arena), preload("res://tests/test_stairs.gd").stairs_map(), tower_with_stairs()]
	for doc: EditorMap in maps:
		for o in doc.objets:
			if String(o.get("type", "")) == "escalier":
				var r := MapRules.check_existing(doc, o)
				assert_true(r.ok, "%s : escalier %s admis (%s)" % [doc.id(), o.id, MapRules.why(r)])


func test_agent_apply_reports_stair_refusals() -> void:
	# Serveur MCP (editor_apply) : un escalier mal placé est listé dans
	# « invalid » avec le message précis ; celui qui descend s'écrit à l'étage
	# du dessous et passe.
	var collab := MapCollab.new(tower_with_stairs())
	host.add_child(collab)
	var link := MapAgentLink.new()
	link.collab = collab
	var res := link.cmd_apply({"label": "essai", "animate": false, "ops": [
		{"op": "add", "coll": "objets", "el": {"id": "$1", "type": "escalier", "etage": 2, "rect": [5.0, 3.0, 7.5, 11.0], "monte": "n"}},
		{"op": "add", "coll": "objets", "el": {"id": "$2", "type": "escalier", "etage": 2, "rect": [9.0, 3.0, 11.5, 11.0], "monte": "n"}}]})
	var bad := String(res.ids.get("$1", ""))
	var good := String(res.ids.get("$2", ""))
	assert_true((res.invalid as Dictionary).has(bad), "escalier empilé listé : %s" % str(res.invalid))
	assert_true(String(res.invalid.get(bad, "")).contains(Lang.t("trémie de l'escalier de l'étage 1 vers l'étage 2", "stairwell of the stairs from floor 1 to floor 2")), str(res.invalid))
	assert_false((res.invalid as Dictionary).has(good), "escalier libre admis : %s" % str(res.invalid))
	link.free()
	collab.queue_free()


## Grande carte : 5 étages de 20 pièces de 10 × 10 m (100 pièces), 5 volées
## par paire d'étages (20 escaliers), 400 caisses de décor.
static func big_map() -> EditorMap:
	var doc := EditorMap.blank("grand_immeuble", "GRAND", "BIG")
	(doc.carte.etages as Array).clear()
	for k in FLOORS:
		doc.carte.etages.append({"sol": k * EditorMap.FLOOR_STEP, "hauteur": EditorMap.DEFAULT_CEILING})
	for k in FLOORS:
		for row in 4:
			for col in 5:
				var z := doc.add_zone("S", "R")
				doc.pieces.append({"id": "p%d_%d_%d" % [k, row, col], "nom": "S", "etage": k, "zone": String(z.id),
					"contour": [[col * 10, row * 10], [col * 10 + 10, row * 10], [col * 10 + 10, row * 10 + 10], [col * 10, row * 10 + 10]]})
				for i in 4:
					doc.objets.append({"id": "c%d_%d_%d_%d" % [k, row, col, i], "type": "caisse", "etage": k, "position": [col * 10 + 8.5, row * 10 + 1.5 + i * 2.0]})
	for k in FLOORS - 1:
		for col in 5:
			var x := col * 10.0 + 1.0 + (k % 2) * 3.0
			doc.objets.append({"id": "e%d_%d" % [k, col], "type": "escalier", "etage": k, "rect": [x, 2.0, x + 2.5, 9.0], "monte": "n" if k % 2 == 0 else "s"})
	return doc


func test_stair_checks_stay_fast_on_a_big_map() -> void:
	var doc := big_map()
	var stairs := doc.objets.filter(func(o): return o.type == "escalier")
	assert_eq(stairs.size(), 20)
	# Vérification de chaque élément (MapEditor._update_invalid), à chaque modification.
	var t_all := []
	for n in 5:
		MapRules.begin_batch(doc)   # emprises de tous les objets (coût d'avant, hors escaliers)
		var t0 := Time.get_ticks_usec()
		for o in stairs:
			var r := MapRules.check_existing(doc, o)
			assert_true(r.ok, "%s admis (%s)" % [o.id, MapRules.why(r)])
		t_all.append((Time.get_ticks_usec() - t0) / 1000.0)
		MapRules.end_batch()
	# Tracé d'un escalier (chaque image du glisser, MapCanvas._creation).
	var t_drag := []
	for n in 20:
		var o := {"type": "escalier", "rect": [24.0, 12.0, 26.5, 19.0], "monte": "n"}
		var t0 := Time.get_ticks_usec()
		MapRules.stair_cache_tag = 7   # version de la carte, comme MapCanvas pendant un tracé
		MapRules.check_rect(doc, 1, "escalier", MapGeom.rect_of(o.rect), "", 0, "", o)
		MapRules.stair_cache_tag = -1
		t_drag.append((Time.get_ticks_usec() - t0) / 1000.0)
	t_all.sort()
	t_drag.sort()
	print("  escaliers : vérification des 20 escaliers %.2f ms (médiane), tracé %.2f ms (médiane)" % [t_all[2], t_drag[10]])
	assert_true(t_all[2] < 10.0, "20 escaliers vérifiés en %.2f ms (objectif 5 ms, marge ×2)" % t_all[2])
	assert_true(t_drag[10] < 5.0, "tracé d'un escalier : %.2f ms par image (objectif 5 ms)" % t_drag[10])


func test_monte_against_the_shape_falls_back_like_the_validator() -> void:
	# Escalier droit de 2,5 × 6,5 m dont « monte » dit « e » (réglé dans le
	# panneau, écrit par MCP) : le validateur garde le seul sens possible ; la
	# pose et les éléments en rouge aussi (même règle, MapRules.pick_stair_dir).
	var doc := tower()
	doc.pieces[1]["contour"] = [[0, 0], [W, 0], [W, 9], [0, 9]]
	doc.find("o1")["position"] = [12.25, 9.0]
	doc.objets.append({"id": "x1", "type": "escalier", "etage": 0, "rect": [2.0, 3.0, 4.5, 9.5], "monte": "e"})
	var v := _check(doc)
	assert_eq(v.stairs.size(), 1, "validateur : escalier retenu\n" + _errs(v))
	var r := MapRules.check_existing(doc, doc.find("x1"))
	assert_true(r.ok, "pas en rouge (%s)" % MapRules.why(r))
	assert_eq(String(r.get("monte", "")), "n" if v.stairs[0].up == Vector2i(0, -1) else "s", "même sens que le validateur")
	# Carte de 2 étages existante (mezzanine) : même accord.
	var two := preload("res://tests/test_map_editor.gd")._base()
	two.carte.etages.append({"sol": 3.5, "hauteur": 3.2})
	two.pieces[0]["double_hauteur"] = true
	two.pieces.append({"id": "pm", "nom": "M", "etage": 1, "zone": String(two.pieces[0].zone), "contour": [[0, 0], [5, 0], [5, 5], [0, 5]]})
	two.objets.append({"id": "es2", "type": "escalier", "etage": 0, "rect": [0.0, 4.5, 2.0, 9.5], "monte": "e"})
	v = _check(two)
	assert_eq(v.stairs.size(), 1, "2 étages : escalier retenu\n" + _errs(v))
	r = MapRules.check_existing(two, two.find("es2"))
	assert_true(r.ok and String(r.get("monte", "")) == "n", "2 étages : admis, monte vers le nord (%s)" % str(r))


func test_paste_keeps_the_stairs_direction() -> void:
	for m in ["e", "o", "s"]:
		var doc := tower()
		var rect: Array = [9.0, 1.0, 11.5, 8.0] if m == "s" else [9.0, 2.0, 15.5, 4.5]
		doc.objets.append({"id": "x1", "type": "escalier", "etage": 1, "rect": rect, "monte": m})
		var ed: MapEditor = load(MapEditor.SCENE).instantiate()
		host.add_child(ed)
		await wait_frames(2)
		ed._reset(doc)
		ed.set_floor(1)
		await wait_frames(1)
		ed.select("x1")
		ed.copy_selected()
		var c := MapGeom.rect_of(rect).get_center()
		ed.paste(c + (Vector2(3.5, 0) if m == "s" else Vector2(0, 5)))
		var copies := ed.doc.objets.filter(func(o): return o.type == "escalier" and String(o.id) != "x1")
		assert_eq(copies.size(), 1, "escalier vers %s collé (%s)" % [m, ed.canvas.refusal])
		if copies.size() == 1:
			assert_eq(String(copies[0].monte), m, "le collé monte toujours vers %s" % m)
		ed.queue_free()
		await wait_frames(1)
