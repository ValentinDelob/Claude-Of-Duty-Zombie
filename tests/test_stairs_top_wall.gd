extends TestCase
## Escalier dont le BOUT HAUT touche un mur (docs/LEVELS_PLAN.md § 4) : clé
## « sortie » (gauche / droite, vu en montant) des escaliers droit, palier,
## large, service, rampe ; plan StairGen (palier plat en haut, volée
## raccourcie, bord de sortie latéral, couloir des zombies et tablier
## orientés) ; choix automatique à la pose (droite puis gauche, refus
## détaillé sinon) ; validateur qui lit « sortie » sans choisir ; dégagement
## au-dessus du palier ; export ; garde ; carte en coordonnées négatives.
## La baie side_bay sert aussi au scénario stairs_types (des zombies sortent
## sur le côté).

const Floors := preload("res://tests/test_stairs_floors.gd")
const Negative := preload("res://tests/test_map_negative.gd")
const Migration := preload("res://tests/test_levels_migration.gd")
const SIDE_KINDS := ["droit", "palier", "large", "service", "rampe"]
## Escalier du test : dans l'immeuble (16 × 14 m par étage), contre le mur
## nord (le haut des marches à y = 0), à côté de la cage d'escalier.
const RECT := [8.5, 0.0, 11.0, 7.0]


# ------------------------------------------------------------------ outils

static func _check(doc: EditorMap) -> MapValidator:
	var v := MapRaster.build(doc).v
	v.analyze()
	return v


## Erreurs du validateur qui parlent d'un escalier.
static func _stair_errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)).filter(func(t): return t.contains("scalier")))


func _errs(v: MapValidator) -> String:
	return "\n".join(v.errors().map(func(m): return String(m.fr)))


## Entrée StairGen d'un type (emprise de 2,5 × 7 m tracée, montée de 3,5 m).
static func _spec(kind: String, side: int, opts := {}) -> Dictionary:
	var o := {"type": "escalier", "rect": [0.0, 0.0, 3.0 if kind == "large" else 2.5, 7.0], "monte": "n"}
	MapCatalog.set_variant(o, kind)
	if side != 0:
		o["sortie"] = "droite" if side > 0 else "gauche"
	var st := MapRaster.stair_spec(o, 0.0, 3.5)
	st.merge(opts, true)
	st["room"] = "r"
	return st


## Escalier tenu par la pose (MapRules.check_rect, comme MapCanvas._creation).
static func _pose(doc: EditorMap, k: int, rect: Array, monte := "n", kind := "", sortie := "") -> Dictionary:
	var o := {"type": "escalier", "rect": rect, "monte": monte}
	if kind != "":
		MapCatalog.set_variant(o, kind)
	if sortie != "":
		o["sortie"] = sortie
	return MapRules.check_rect(doc, k, "escalier", MapGeom.rect_of(rect), "", 0, kind, o)


## Baie « sortie sur le côté » ajoutée à la carte d'essai des types
## (tests/test_stairs.gd : grand hall à double hauteur) : le hall s'allonge
## d'une baie à l'est ; une mezzanine du niveau 3,5 m contre le mur nord du
## hall ; un escalier droit dont le haut touche ce mur, sortie à droite.
static func side_bay(doc: EditorMap) -> Dictionary:
	var hall: Dictionary = doc.pieces[0]
	var c: Array = hall.contour
	var x := float(c[1][0])
	var w := x + 9.0
	hall["contour"] = [[0, 0], [w, 0], [w, c[2][1]], [0, c[2][1]]]
	var m := {"id": doc.new_id("p"), "nom": "Mezzanine est", "altitude": EditorMap.FLOOR_STEP, "zone": String(hall.zone),
		"contour": [[x, 0], [x + 8, 0], [x + 8, 9], [x, 9]]}
	doc.pieces.append(m)
	var o := {"id": doc.new_id("e"), "type": "escalier", "altitude": 0, "altitude_haut": EditorMap.FLOOR_STEP,
		"rect": [x + 1, 0, x + 3.5, 7], "monte": "n", "sortie": "droite"}
	doc.objets.append(o)
	return o


# ------------------------------------------------------------------ plan StairGen

func test_plan_side_exit() -> void:
	for kind: String in SIDE_KINDS:
		var front := StairGen.plan(_spec(kind, 0))
		for side: int in [1, -1]:
			var what := "%s sortie %s" % [kind, "droite" if side > 0 else "gauche"]
			var pl := StairGen.plan(_spec(kind, side))
			var W := float(pl.W)
			var L := float(pl.L)
			var D := float(pl.depth)
			assert_eq(int(pl.side), side, what + " : côté lu")
			assert_near(D, StairGen.side_depth(W), 0.001, what + " : profondeur du palier")
			assert_true(D >= 1.0 and D <= 1.5, what + " : palier de 1 à 1,5 m (%.2f)" % D)
			# Palier plat en haut, au sol d'arrivée, sur toute la largeur.
			var top: Dictionary = pl.landings[pl.landings.size() - 1]
			assert_near(float(top.y), 3.5, 0.001, what + " : palier au sol du haut")
			var u: Vector2 = pl.u
			var right: Vector2 = pl.right
			var a2: Vector2 = pl.a2
			var mid := a2 + u * (L - D * 0.5)
			assert_near(StairGen.surface_y(pl, mid), 3.5, 0.001, what + " : milieu du palier à 3,5 m")
			assert_near(StairGen.surface_y(pl, mid + right * (W * 0.45)), 3.5, 0.001, what + " : palier sur toute la largeur")
			# Volée raccourcie : elle s'arrête au palier, pente plus forte qu'en face.
			var last: Dictionary = pl.flights[pl.flights.size() - 1]
			var lb := Vector2(last.b.x, last.b.z)
			assert_near((lb - a2).dot(u), L - D, 0.001, what + " : volée sur L − D")
			assert_true(StairGen.max_slope(pl) > StairGen.max_slope(front), what + " : volée raccourcie plus raide")
			if kind != "palier":
				assert_near(StairGen.max_slope(pl), rad_to_deg(atan2(3.5, L - D)), 0.01, what + " : pente de la volée raccourcie")
			assert_near(StairGen.run_length(pl), StairGen.run_length(front) - D, 0.01, what + " : longueur des marches")
			# Bord de sortie latéral, du côté voulu, au milieu du palier.
			var ex: Dictionary = pl.exit
			var n: Vector2 = ex.n
			assert_true(n.is_equal_approx(right * side), what + " : sortie vers %s (%s)" % [right * side, n])
			assert_near(((ex.m as Vector2) - a2).dot(right), side * W * 0.5, 0.001, what + " : bord sur le côté")
			assert_near(((ex.m as Vector2) - a2).dot(u), L - D * 0.5, 0.001, what + " : bord au palier")
			assert_near(float(ex.h), D * 0.5, 0.001, what + " : bord de la profondeur du palier")
			assert_true(StairGen.walk_width(pl) >= 0.95, what + " : passage %.2f m" % StairGen.walk_width(pl))
			# Couloir des zombies : l'ancre de sortie au-delà du bord latéral.
			var lane: Array = pl.lane
			var exit_p: Vector3 = lane[lane.size() - 1][0]
			var ep := Vector2(exit_p.x, exit_p.z)
			assert_near(exit_p.y, 3.5, 0.001, what + " : ancre de sortie au sol du haut")
			assert_near((ep - (ex.m as Vector2)).dot(n), StairGen.EXIT_GAP, 0.001, what + " : ancre devant le bord latéral")
			assert_true((ep - a2).dot(u) <= L, what + " : ancre pas au-delà du bout du haut")
			# Tablier orienté vers la sortie.
			var ap := StairGen.apron(_spec(kind, side))
			var ac := Vector2(float(ap.center[0]), float(ap.center[2]))
			assert_near((ac - (ex.m as Vector2)).dot(n), StairGen.APRON * 0.5, 0.001, what + " : tablier au-delà du bord")
			assert_near(float(ap.yaw), atan2(-n.y, n.x), 0.001, what + " : tablier tourné vers la sortie")
			assert_near(float(ap.size[2]), D, 0.001, what + " : tablier de la largeur du passage")
			# Garde-corps : jamais sur le passage de sortie ; côté opposé et bout.
			var pr := StairGen.plan(_spec(kind, side, {"rail": true}))
			var opp := false
			var end := false
			for e in pr.edges:
				var ea := Vector2(e.a.x, e.a.z)
				var eb := Vector2(e.b.x, e.b.z)
				var q := (ea + eb) * 0.5
				var along := (q - a2).dot(u)
				var lat := (q - a2).dot(right) * side
				assert_false(along > L - D + 0.01 and lat > W * 0.5 - 0.01 and absf((eb - ea).dot(u)) > 0.01, what + " : pas de garde-corps sur la sortie")
				if along > L - D and lat < -W * 0.5 + 0.01:
					opp = true
				if absf(along - L) < 0.01:
					end = true
			assert_true(opp and end, what + " : garde-corps du côté opposé (%s) et au bout (%s)" % [opp, end])
	# L, U, colimaçon : « side » ignoré.
	for kind: String in ["quart", "demi_tour", "colimacon"]:
		var o := {"type": "escalier", "rect": [0.0, 0.0, 4.5, 5.0], "monte": "n", "sortie": "droite"}
		MapCatalog.set_variant(o, kind)
		assert_eq(MapCatalog.stair_side(o), 0, kind + " : pas de sortie sur le côté")
		MapCatalog.tidy_stair(o)
		assert_false(o.has("sortie"), kind + " : tidy_stair retire « sortie »")


func test_lane_and_apron_in_game_plan() -> void:
	# Couloir d'ancres du jeu (StairLane) : points sur l'escalier, dernier
	# tronçon vers le côté ; la description garde « side ».
	var st := _spec("droit", 1)
	assert_eq(int(st.get("side", 0)), 1, "description : side")
	var pl := StairGen.plan(st)
	var l := StairLane.from_plan(pl)
	var d := l.pts[l.pts.size() - 1] - l.pts[l.pts.size() - 2]
	var right: Vector2 = pl.right
	assert_true(Vector2(d.x, d.z).normalized().dot(right) > 0.99, "dernier tronçon vers la droite")
	assert_eq(StairGen.side_of({"side": 1, "kind": "quart"}), 0, "L : side ignoré")
	assert_eq(StairGen.side_of({"side": -1}), -1, "droit : à gauche")
	assert_eq(StairGen.side_of({"side": "x"}), 0, "valeur illisible : en face")


# ------------------------------------------------------------------ pose

func test_top_against_arrival_wall_gets_side_exit() -> void:
	var doc := Floors.tower_with_stairs()
	var r := _pose(doc, 0, RECT)
	assert_true(r.ok, "haut contre le mur nord : posé (%s)" % MapRules.why(r))
	assert_eq(String(r.get("sortie", "")), "droite", "sortie choisie : la droite d'abord")
	assert_eq(MapCanvas.stair_side_status("droite"), Lang.t("Arrivée sur le côté droit : le haut des marches touche un mur", "Arrival on the right side: the top of the stairs touches a wall"))
	# Droite bloquée par un pilier au niveau d'arrivée : la gauche.
	var lp := doc.duplicate_map()
	lp.objets.append({"id": "pl1", "type": "pilier", "altitude": EditorMap.FLOOR_STEP, "rect": [11.0, 0.5, 12.0, 2.0]})
	r = _pose(lp, 0, RECT)
	assert_true(r.ok and String(r.get("sortie", "")) == "gauche", "droite gênée : sortie à gauche (%s)" % MapRules.why(r))
	# Posé : le validateur l'accepte, arrivée sur le côté.
	Floors.place(doc, 0, RECT, "n")
	var o: Dictionary = doc.objets[doc.objets.size() - 1]
	assert_eq(String(o.get("sortie", "")), "droite", "« sortie » écrite")
	var v := _check(doc)
	assert_true(v.ok(), "carte acceptée :\n" + _errs(v))
	var st := {}
	for s in v.stairs:
		if v.eid_of.get(String(s.key), "") == String(o.id):
			st = s
	assert_false(st.is_empty(), "escalier retenu")
	for c: Vector2i in st.top:
		assert_eq(c.x, 22, "arrivée sur le côté droit (x 11 m) : %s" % c)
		assert_true(c.y >= 1 and c.y <= 3, "arrivée près du haut : %s" % c)
	assert_eq((st.top as Dictionary).size(), 3, "trois cases de sortie (palier de 1,5 m)")
	# Les autres types qui sortent en face aussi.
	for kind: String in ["palier", "service", "rampe"]:
		var dk := Floors.tower_with_stairs()
		# Palier : deux volées et un palier au milieu, 7,5 m pour rester sous 40°.
		var rect: Array = {"service": [8.5, 0.0, 10.0, 7.0], "palier": [8.5, 0.0, 11.0, 7.5]}.get(kind, RECT)
		var rk := _pose(dk, 0, rect, "n", kind)
		assert_true(rk.ok and rk.has("sortie"), "%s : posé avec une sortie sur le côté (%s)" % [kind, MapRules.why(rk)])
	# En L : jamais de sortie choisie (sa sortie est ailleurs).
	var dq := Floors.tower_with_stairs()
	var rq := _pose(dq, 0, [8.5, 0.0, 12.5, 7.0], "n", "quart")
	assert_false(rq.has("sortie"), "en L : pas de « sortie »")


func test_both_sides_blocked_detailed_refusal() -> void:
	var doc := Floors.tower()
	# Au niveau 3,5 m, la pièce n'a que la largeur de l'escalier.
	doc.pieces[1]["contour"] = [[0, 0], [2.5, 0], [2.5, Floors.D], [0, Floors.D]]
	var r := _pose(doc, 0, [0.0, 0.0, 2.5, 7.0])
	assert_false(r.ok, "les deux côtés dans un mur : refusé")
	var fr := String(r.get("fr", ""))
	assert_true(fr.contains("tombe dans") and fr.contains("sortie sur le côté impossible : à droite, ") and fr.contains("; à gauche, "), fr)
	assert_true(String(r.get("en", "")).contains("no side exit either: on the right, "), String(r.get("en", "")))
	var roles := (r.get("marks", []) as Array).map(func(m): return String(m.role))
	assert_true(roles.count("faute") >= 2, "cases fautives en face et sur les côtés : %s" % str(roles))
	# Sortie sur le côté trop raide : « allongez-le à X m ».
	var short := Floors.tower()
	r = _pose(short, 0, [8.5, 0.0, 11.0, 5.0])
	assert_false(r.ok, "4,5 m de marches moins le palier : trop raide")
	fr = String(r.get("fr", ""))
	assert_true(fr.contains("trop raide avec la sortie sur le côté") and fr.contains("allongez-le à 6,5 m"), fr)
	short.objets.append({"id": "x", "type": "escalier", "altitude": 0.0, "altitude_haut": 3.5, "rect": [8.5, 0.0, 11.0, 6.5], "monte": "n", "sortie": "droite"})
	var rx := MapRules.check_existing(short, short.find("x"))
	assert_true(rx.ok, "allongé à 6,5 m : admis (%s)" % MapRules.why(rx))


func test_arrival_beyond_wall_when_arrival_room_goes_on() -> void:
	# Le haut touche le mur nord de la pièce du pied, mais la pièce d'arrivée
	# continue au-delà (et en coordonnées négatives) : arrivée en face.
	var doc := Floors.tower_with_stairs()
	doc.pieces[1]["contour"] = [[0, -4], [Floors.W, -4], [Floors.W, Floors.D], [0, Floors.D]]
	var r := _pose(doc, 0, RECT)
	assert_true(r.ok and not r.has("sortie"), "arrivée au-delà du mur : en face (%s)" % MapRules.why(r))
	# Demi-niveau à côté (1b) : palier dans le mur commun, toujours en face.
	var half := EditorMap.blank("demi", "DEMI", "HALF")
	var za := half.add_zone("A", "A")
	half.pieces.append({"id": "pa", "nom": "A", "altitude": 0.0, "zone": String(za.id), "contour": [[0, 0], [10, 0], [10, 10], [0, 10]]})
	half.pieces.append({"id": "pb", "nom": "B", "altitude": 1.5, "zone": String(za.id), "contour": [[0, -6], [10, -6], [10, 0], [0, 0]]})
	r = _pose(half, 0, [3.0, 0.0, 5.5, 4.0])
	assert_true(r.ok and not r.has("sortie"), "palier dans le mur commun : en face (%s)" % MapRules.why(r))


func test_landing_headroom() -> void:
	# A (sol 0, plafond 3,2 m) ; B à 1,5 m à l'est (mur commun x = 10) ; le
	# haut des marches contre le mur nord de A, sortie à droite réglée : dans
	# le mur commun (palier de 1b), mais 1,7 m seulement au-dessus du palier.
	var doc := EditorMap.blank("palier", "PALIER", "LANDING")
	var z := doc.add_zone("A", "A")
	var a := {"id": "pa", "nom": "A", "altitude": 0.0, "zone": String(z.id), "contour": [[0, 0], [10, 0], [10, 10], [0, 10]]}
	doc.pieces.append(a)
	doc.pieces.append({"id": "pb", "nom": "B", "altitude": 1.5, "zone": String(z.id), "contour": [[10, 0], [20, 0], [20, 10], [10, 10]]})
	var rect := [7.5, 0.0, 10.0, 5.0]
	var r := _pose(doc, 0, rect, "n", "", "droite")
	assert_false(r.ok, "palier sous un plafond trop bas : refusé")
	assert_true(String(r.get("fr", "")).contains("plafond trop bas au-dessus du palier du haut (1,7 m de passage"), String(r.get("fr", "")))
	# Validateur (fichier écrit à la main) : même faute, lue sur la grille.
	var bad := doc.duplicate_map()
	bad.objets.append({"id": "e1", "type": "escalier", "altitude": 0.0, "altitude_haut": 1.5, "rect": rect, "monte": "n", "sortie": "droite"})
	var se := _stair_errs(_check(bad))
	assert_true(se.contains("plafond trop bas au-dessus"), se)
	# Pièce du pied plus haute : admis, palier dans le mur commun.
	a["plafond"] = 4.0
	r = _pose(doc, 0, rect, "n", "", "droite")
	assert_true(r.ok, "plafond de 4 m : sortie à droite admise (%s)" % MapRules.why(r))
	var good := doc.duplicate_map()
	good.objets.append({"id": "e1", "type": "escalier", "altitude": 0.0, "altitude_haut": 1.5, "rect": rect, "monte": "n", "sortie": "droite"})
	var v := _check(good)
	assert_eq(_stair_errs(v), "", "validateur : escalier admis")
	assert_true(v.landings.has(1) and not (v.landings[1] as Dictionary).is_empty(), "palier dans l'épaisseur du mur commun")


# ------------------------------------------------------------------ validateur

func test_validator_reads_sortie_without_choosing() -> void:
	# Sortie à droite écrite à la main contre le mur est : erreur (pas de
	# nouveau choix), la gauche est libre.
	var doc := Floors.tower_with_stairs()
	doc.objets.append({"id": "x1", "type": "escalier", "altitude": 0.0, "altitude_haut": 3.5, "rect": [13.5, 0.0, 16.0, 7.0], "monte": "n", "sortie": "droite"})
	var se := _stair_errs(_check(doc))
	assert_true(se.contains("sur le côté droit, en haut"), se)
	doc.find("x1")["sortie"] = "gauche"
	var v := _check(doc)
	assert_true(v.ok(), "sortie à gauche : acceptée :\n" + _errs(v))
	# Sans « sortie » : en face, dans le mur (le validateur ne choisit pas).
	doc.find("x1").erase("sortie")
	se = _stair_errs(_check(doc))
	assert_true(se.contains("escalier en") and (se.contains("mur") or se.contains("pilier")), se)


# ------------------------------------------------------------------ export, garde, carte négative

func test_export_and_guard() -> void:
	var doc := Floors.tower_with_stairs()
	Floors.place(doc, 0, RECT, "n")
	var v := _check(doc)
	assert_true(v.ok(), _errs(v))
	var lay := MapLayoutExport.build(v)
	var side_st := (lay.stairs as Array).filter(func(s): return int(s.get("side", 0)) != 0)
	assert_eq(side_st.size(), 1, "un escalier exporté avec « side »")
	var st: Dictionary = side_st[0]
	assert_eq(int(st.side), 1, "sortie à droite")
	var pl := StairGen.plan(st)
	assert_true((pl.exit.n as Vector2).is_equal_approx(Vector2(1, 0)), "sortie vers l'est dans le jeu : %s" % pl.exit.n)
	assert_near(float(st.a[1]), 0.0, 0.01, "pied au sol du bas")
	assert_near(float(st.b[1]), 3.5, 0.01, "haut au sol du haut")
	var ap := StairGen.apron(st)
	assert_true(float(ap.center[0]) > float((pl.exit.m as Vector2).x), "tablier à l'est du bord de sortie")
	assert_true(EditorMapDef.from_map(doc, "perso:immeuble").is_valid(), "carte jouable")
	# Garde : « sortie » au format 17 (gauche / droite), refusée au format 16.
	var texts := doc.file_texts()
	assert_eq(CustomMapGuard.check_texts(texts).reasons, [], "format 17 : « sortie » admise")
	var objs: Dictionary = JSON.parse_string(texts["objets.json"])
	for e in objs.objets:
		if e.has("sortie"):
			e["sortie"] = "haut"
	var bad := texts.duplicate()
	bad["objets.json"] = JSON.stringify(objs)
	assert_false(CustomMapGuard.check_texts(bad).ok, "« sortie » inconnue refusée")
	var old := Migration.two_floors()
	var od: Dictionary = JSON.parse_string(old["objets.json"])
	for e in od.objets:
		if String(e.get("type", "")) == "escalier":
			e["sortie"] = "droite"
	old["objets.json"] = JSON.stringify(od)
	assert_false(CustomMapGuard.check_texts(old).ok, "format 16 : « sortie » inconnue")
	# Relue : gardée ; tidy_stair ne la retire pas.
	var back := EditorMap.from_texts(texts)
	var found := back.objets.filter(func(e): return e.has("sortie"))
	assert_eq(found.size(), 1, "« sortie » relue")


func test_negative_map() -> void:
	var doc := Floors.tower_with_stairs()
	Floors.place(doc, 0, RECT, "n")
	var neg := Negative.moved(doc, Vector2(-30.0, -20.0))
	var v0 := _check(doc)
	var v1 := _check(neg)
	assert_true(v1.ok(), "carte négative acceptée :\n" + _errs(v1))
	assert_eq(v1.shift, Vector2(30.0, 20.0), "copie décalée")
	assert_eq(JSON.stringify(MapLayoutExport.build(v1).stairs), JSON.stringify(MapLayoutExport.build(v0).stairs), "escaliers exportés identiques")
	# Pose en coordonnées négatives : même choix.
	var fresh := Negative.moved(Floors.tower_with_stairs(), Vector2(-30.0, -20.0))
	var r := _pose(fresh, 0, [RECT[0] - 30.0, RECT[1] - 20.0, RECT[2] - 30.0, RECT[3] - 20.0])
	assert_true(r.ok and String(r.get("sortie", "")) == "droite", "carte négative : sortie à droite (%s)" % MapRules.why(r))
	# Baie de la carte des types (scénario stairs_types) : acceptée.
	var types := preload("res://tests/test_stairs.gd").stairs_map()
	side_bay(types)
	var vt := _check(types)
	assert_true(vt.ok(), "carte des types avec la baie de sortie sur le côté :\n" + _errs(vt))
	assert_eq(vt.stairs.size(), preload("res://tests/test_stairs.gd").KINDS.size() + 1, "un escalier de plus")
