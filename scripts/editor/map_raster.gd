class_name MapRaster
extends RefCounted
## Carte de l'éditeur (EditorMap) -> grille du validateur (MapValidator) :
## une case de 0,5 m centrée sur chaque multiple de 0,5 m (MapGeom), par étage.
##   - pièce : les cases que traverse son contour sont des MURS, celles dont le
##     centre est à l'intérieur son SOL (zone de la pièce) ; deux pièces collées
##     partagent les cases de leur bord commun : un seul mur mitoyen ;
##   - pièce « double hauteur » : à l'étage du dessus, son contour reste un mur
##     et son intérieur un VIDE (trémie) ; une pièce posée au-dessus forme une
##     mezzanine (ses bords au-dessus du vide ont un garde-corps) ;
##   - ouvertures : les cases du mur commun (porte, débris, passage) ou
##     extérieur (fenêtre, 1 m) sur la largeur de l'ouverture ;
##   - piliers, murs libres, décor : cases pleines ; escalier : cases de marches
##     et vide au-dessus ; objets : leurs cases (emprise le long du mur ou au sol).
## Zones : la zone de départ devient « a » (MapLayout.start_zone), les autres
## « b », « c »... dans l'ordre de zones.json.

const K := MapValidator.K
## Cases de marge au-delà de la carte (cours des fenêtres).
const MARGIN := 8

var doc: EditorMap
var v: MapValidator
## Zone de l'éditeur -> lettre du jeu.
var letters: Dictionary = {}
## Élément de l'éditeur -> [étage, cases] (dessin, clic sur un problème).
var cells_of: Dictionary = {}


static func build(d: EditorMap) -> MapRaster:
	var r := MapRaster.new()
	r.doc = d
	r._build()
	return r


## Lettre de jeu de la n-ième zone (0 -> a, 25 -> z, 26 -> za...).
static func letter(n: int) -> String:
	if n < 26:
		return String.chr(97 + n)
	return "z" + letter(n - 26)


func _build() -> void:
	v = MapValidator.new()
	var c: Dictionary = doc.carte
	v.id = doc.id()
	v.display_name = doc.display_name()
	var desc: Dictionary = c.get("description", {})
	v.description = Lang.t(String(desc.get("fr", "")), String(desc.get("en", desc.get("fr", ""))))
	v.music = String(c.get("musique", "ambience_bunker"))
	v.door_height = float(c.get("hauteur_portes", MapValidator.DOOR_HEIGHT))
	v.lamps_auto = bool(c.get("lampes_auto", true))
	_zones()
	# Étages.
	var n := doc.floor_count()
	for k in n:
		var f := MapValidator.Floor.new()
		f.index = k
		f.sol = doc.floor_sol(k)
		f.plafond = f.sol + doc.floor_height(k)
		v.floors.append(f)
	# Taille de la grille : tout ce qui est posé, plus la marge.
	var hi := Vector2(10, 10)
	var neg := false
	for p in doc.pieces:
		for pt in p.get("contour", []):
			hi = hi.max(MapGeom.v2(pt))
			neg = neg or float(pt[0]) < -0.001 or float(pt[1]) < -0.001
	for o in doc.objets + doc.ouvertures:
		for key in ["position", "a", "b"]:
			if o.has(key):
				hi = hi.max(MapGeom.v2(o[key]))
				neg = neg or float(o[key][0]) < -0.001 or float(o[key][1]) < -0.001
		if o.has("rect"):
			hi = hi.max(MapGeom.rect_of(o.rect).end)
	if neg:
		_err("un élément est hors du terrain : les coordonnées x et y doivent être positives", "an element is off the board: x and y coordinates must be positive")
	var w := ceili(hi.x / MapGeom.CELL) + MARGIN + 1
	var h := ceili(hi.y / MapGeom.CELL) + MARGIN + 1
	for f in v.floors:
		f.setup(w, h)
	for k in n:
		_floor(k)


func _err(fr: String, en: String, k := -1, cells: Array = []) -> void:
	v._msg("erreur", fr, en, k, cells)


func _zones() -> void:
	var order := []
	if not doc.zone(doc.depart).is_empty():
		order.append(doc.zone(doc.depart))
	for z in doc.zones:
		if String(z.id) != doc.depart:
			order.append(z)
	for i in order.size():
		var z: Dictionary = order[i]
		var l := letter(i)
		letters[String(z.id)] = l
		var nm: Dictionary = z.get("nom", {})
		var fr := String(nm.get("fr", z.id))
		var en := String(nm.get("en", fr))
		v.zone_label[l] = [fr, en]
		v.zone_names[l] = Lang.t(fr, en)
		if z.has("sol"):
			v.floor_mats[l] = String(z.sol)
		if z.has("murs"):
			v.wall_mats[l] = String(z.murs)
	# Pièce sans zone connue : sa propre zone (le nom de la pièce).
	for p in doc.pieces:
		var zid := String(p.get("zone", ""))
		if not letters.has(zid):
			var l := letter(letters.size())
			letters[zid if zid != "" else "_" + String(p.id)] = l
			v.zone_label[l] = [String(p.get("nom", p.id)), String(p.get("nom", p.id))]
			v.zone_names[l] = String(p.get("nom", p.id))


func zone_letter(p: Dictionary) -> String:
	var zid := String(p.get("zone", ""))
	return letters.get(zid if zid != "" else "_" + String(p.id), "a")


func _ceil_of(p: Dictionary, k: int) -> float:
	return doc.floor_sol(k) + float(p.get("plafond", doc.floor_height(k)))


## Contour -> [cases du bord (dictionnaire), cases intérieures (tableau)].
static func room_cells(poly: PackedVector2Array) -> Array:
	var border := {}
	for i in poly.size():
		for c in MapGeom.segment_cells(poly[i], poly[(i + 1) % poly.size()]):
			border[c] = true
	var inner := []
	var bb := MapGeom.bbox(poly)
	for j in range(floori(bb.position.y / MapGeom.CELL), ceili(bb.end.y / MapGeom.CELL) + 1):
		for i in range(floori(bb.position.x / MapGeom.CELL), ceili(bb.end.x / MapGeom.CELL) + 1):
			var c := Vector2i(i, j)
			if not border.has(c) and Geometry2D.is_point_in_polygon(MapGeom.cell_center(c), poly):
				inner.append(c)
	return [border, inner]


func _floor(k: int) -> void:
	var f := v.floors[k]
	var ceil_up := f.sol + doc.floor_height(k)
	# (a) Pièces à double hauteur de l'étage du dessous : vide et murs qui montent.
	var voids := {}   # case -> true (intérieur d'une double hauteur)
	if k > 0:
		for p in doc.rooms_on(k - 1):
			if not p.get("double_hauteur", false):
				continue
			var rc := room_cells(doc.room_poly(p))
			for c in rc[1]:
				f.put(c, K.TREMIE, "tremie")
				f.ceil[c.y * f.w + c.x] = ceil_up
				voids[c] = true
			for c in rc[0]:
				f.put(c, K.MUR, "mur")
				f.ceil[c.y * f.w + c.x] = ceil_up
		# Piliers et murs d'une double hauteur : jusqu'en haut.
		for o in doc.objects_on(k - 1):
			if String(o.type) in ["pilier", "mur"]:
				for c in _obstacle_cells(o):
					if voids.has(c):
						f.put(c, K.MUR, "mur")
	# (b) Pièces de cet étage.
	var inner_of := {}
	var border_of := {}
	for p in doc.rooms_on(k):
		var rc := room_cells(doc.room_poly(p))
		var z := zone_letter(p)
		var ce := _ceil_of(p, k)
		var own := []
		for c in rc[1]:
			if inner_of.has(c):
				_err("les pièces « %s » et « %s » se chevauchent" % [p.get("nom", p.id), inner_of[c].get("nom", "")],
					"rooms \"%s\" and \"%s\" overlap" % [p.get("nom", p.id), inner_of[c].get("nom", "")], k, [c])
				break
			inner_of[c] = p
		for c in rc[1]:
			if f.at(c) == K.MUR and f.key_at(c) == "mur" and k > 0 and not voids.has(c):
				continue   # mur d'une double hauteur : il reste
			f.put(c, K.SOL, "zone", z)
			f.ceil[c.y * f.w + c.x] = ce
			own.append(c)
		for c in rc[0]:
			border_of.get_or_add(c, []).append(p)
		cells_of[String(p.id)] = [k, own]
	for c in border_of:
		var list: Array = border_of[c]
		var p: Dictionary = list[0]
		var i: int = c.y * f.w + c.x
		if not f.inside(c):
			continue
		if list.size() == 1 and voids.has(c) and not inner_of.has(c):
			# Bord d'une mezzanine au-dessus du vide : plancher (garde-corps).
			f.put(c, K.SOL, "zone", zone_letter(p))
			f.ceil[i] = _ceil_of(p, k)
			continue
		if inner_of.has(c):
			continue
		f.put(c, K.MUR, "mur")
		var ce := 0.0
		for q in list:
			ce = maxf(ce, _ceil_of(q, k))
		f.ceil[i] = maxf(f.ceil[i], ce)
	# (c) Escaliers de l'étage du dessous : vide au-dessus des marches.
	if k > 0:
		for o in doc.objects_on(k - 1):
			if String(o.type) == "escalier":
				for c in MapGeom.rect_cells_inside(MapGeom.rect_of(o.rect)):
					f.put(c, K.TREMIE, "tremie")
					f.ceil[c.y * f.w + c.x] = ceil_up
	# (d) Ouvertures.
	for o in doc.openings_on(k):
		_opening(f, o)
	# (e) Piliers, murs libres, décor.
	for o in doc.objects_on(k):
		match String(o.type):
			"pilier", "mur":
				var cells := _obstacle_cells(o)
				for c in cells:
					f.put(c, K.MUR, "mur")
				cells_of[String(o.id)] = [k, cells]
			"caisse", "baril":
				var fp := MapCatalog.footprint(o)
				var cells := _square(o, fp.x)
				var key := "decor#" + String(o.id)
				for c in cells:
					f.put(c, K.MUR, key)
				v.eid_of[key] = String(o.id)
				v.decor.append({"floor": k, "rect": MapValidator._bbox(cells), "h": 1.0 if o.type == "caisse" else 0.9,
					"mat": "crate" if o.type == "caisse" else "barrel", "eid": String(o.id)})
				cells_of[String(o.id)] = [k, cells]
	# (f) Escaliers de cet étage.
	for o in doc.objects_on(k):
		if String(o.type) == "escalier":
			var key := "escalier#" + String(o.id)
			var cells := MapGeom.rect_cells_inside(MapGeom.rect_of(o.rect))
			for c in cells:
				f.put(c, K.ESCALIER, key, f.zone_of(c))
			v.eid_of[key] = String(o.id)
			cells_of[String(o.id)] = [k, cells]
	# (g) Objets muraux et au sol.
	for o in doc.objects_on(k):
		var t := String(o.type)
		var tool := MapCatalog.tool_of(o)
		if t == "lampe":
			var c := MapGeom.cell_of(MapGeom.v2(o.position))
			v.lamps_extra.append({"floor": k, "center": Vector2(c) + Vector2(0.5, 0.5)})
			cells_of[String(o.id)] = [k, [c]]
			continue
		if t in ["caisse", "baril", "pilier", "mur", "escalier"]:
			continue
		var cells := []
		if tool == "wall_item":
			cells = wall_item_cells(o)
		elif t == "piege":
			cells = MapGeom.rect_cells_inside(MapGeom.rect_of(o.rect))
		elif tool == "floor_item":
			cells = _square(o, MapCatalog.footprint(o).x)
		if cells.is_empty():
			continue
		var key := "%s#%s" % [MapCatalog.validator_key(o), o.id]
		var e := MapValidator.entry(key)
		var bad := cells.filter(func(c): return f.at(c) != K.SOL)
		if not bad.is_empty():
			var w := v._at(k, bad[0])
			if f.at(bad[0]) == K.MARQUEUR:
				_err("%s en %s : chevauche un autre objet" % [e.fr, w[0]], "%s at %s: overlaps another object" % [e.en, w[1]], k, bad)
			else:
				_err("%s en %s : doit être posé sur le sol d'une pièce (pas dans un mur ni dehors)" % [e.fr, w[0]],
					"%s at %s: must stand on a room floor (not in a wall nor outside)" % [e.en, w[1]], k, bad)
			continue
		for c in cells:
			f.put(c, K.MARQUEUR, key, f.zone_of(c))
		if tool == "wall_item":
			v.wall_hint[key] = MapGeom.DIRS.get(String(o.get("mur", "n")), Vector2i(0, -1))
		v.eid_of[key] = String(o.id)
		cells_of[String(o.id)] = [k, cells]


## Cases d'un pilier (contour et intérieur) ou d'un mur libre (segment épais).
func _obstacle_cells(o: Dictionary) -> Array:
	if String(o.type) == "pilier":
		return MapGeom.rect_cells_closed(MapGeom.rect_of(o.rect))
	var a := MapGeom.v2(o.a)
	var b := MapGeom.v2(o.b)
	var cells := {}
	for c in MapGeom.segment_cells(a, b):
		cells[c] = true
	var half := (float(o.get("epaisseur", 0.5)) - MapGeom.CELL) * 0.5 + 0.01
	if half > 0.1:
		var bb := Rect2(a, Vector2.ZERO).expand(b).grow(half + MapGeom.CELL)
		for j in range(floori(bb.position.y / MapGeom.CELL), ceili(bb.end.y / MapGeom.CELL) + 1):
			for i in range(floori(bb.position.x / MapGeom.CELL), ceili(bb.end.x / MapGeom.CELL) + 1):
				if MapGeom.dist_to_segment(MapGeom.cell_center(Vector2i(i, j)), a, b) <= half:
					cells[Vector2i(i, j)] = true
	return cells.keys()


## Carré de n × n cases centré sur la position de l'objet.
static func _square(o: Dictionary, n: int) -> Array:
	var p := MapGeom.v2(o.position)
	var i0 := MapGeom.first_cell(p.x, n)
	var j0 := MapGeom.first_cell(p.y, n)
	var out := []
	for j in n:
		for i in n:
			out.append(Vector2i(i0 + i, j0 + j))
	return out


## Cases d'un objet mural : la rangée collée au mur, sur sa largeur. La
## position est sur le trait du mur (centre de l'objet le long du mur).
static func wall_item_cells(o: Dictionary) -> Array:
	var p := MapGeom.v2(o.position)
	var d: Vector2i = MapGeom.DIRS.get(String(o.get("mur", "n")), Vector2i(0, -1))
	var n := MapCatalog.footprint(o).x
	var out := []
	if d.x == 0:
		var j := roundi(p.y / MapGeom.CELL) - d.y
		var i0 := MapGeom.first_cell(p.x, n)
		for i in n:
			out.append(Vector2i(i0 + i, j))
	else:
		var i := roundi(p.x / MapGeom.CELL) - d.x
		var j0 := MapGeom.first_cell(p.y, n)
		for j in n:
			out.append(Vector2i(i, j0 + j))
	return out


## Cases d'une ouverture : sur le trait du mur, centrées sur sa position.
## `horizontal` : mur est-ouest (y constant).
static func opening_cells(o: Dictionary, horizontal: bool) -> Array:
	var p := MapGeom.v2(o.position)
	var n := maxi(1, roundi(float(o.get("largeur", 1.0 if o.type == "fenetre" else 2.0)) / MapGeom.CELL))
	var out := []
	if horizontal:
		var j := roundi(p.y / MapGeom.CELL)
		var i0 := MapGeom.first_cell(p.x, n)
		for i in n:
			out.append(Vector2i(i0 + i, j))
	else:
		var i := roundi(p.x / MapGeom.CELL)
		var j0 := MapGeom.first_cell(p.y, n)
		for j in n:
			out.append(Vector2i(i, j0 + j))
	return out


## Sens du mur sous une ouverture : un bord de pièce (horizontal ou vertical)
## qui passe par sa position. -1 : aucun.
func opening_axis(o: Dictionary) -> int:
	var p := MapGeom.v2(o.position)
	for r in doc.rooms_on(int(o.get("etage", 0))):
		var poly := doc.room_poly(r)
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if MapGeom.dist_to_segment(p, a, b) > 0.01:
				continue
			if absf(a.y - b.y) < MapGeom.EPS:
				return 1
			if absf(a.x - b.x) < MapGeom.EPS:
				return 0
	return -1


func _opening(f: MapValidator.Floor, o: Dictionary) -> void:
	var t := String(o.type)
	var axis := opening_axis(o)
	var cells := opening_cells(o, axis != 0)
	cells_of[String(o.id)] = [f.index, cells]
	if axis < 0:
		var w := v._at(f.index, cells[0])
		_err("ouverture en %s : elle doit être posée sur un mur droit (horizontal ou vertical) d'une pièce" % w[0],
			"opening at %s: it must sit on a straight (horizontal or vertical) room wall" % w[1], f.index, cells)
		return
	var key := "%s#%s" % ["fenetre" if t == "fenetre" else "porte", o.id]
	v.eid_of[key] = String(o.id)
	match t:
		"fenetre":
			for c in cells:
				f.put(c, K.FENETRE, key)
		"passage":
			# Sol de la pièce au nord (ou à l'ouest) du mur, sinon de l'autre côté.
			var side := Vector2i(0, -1) if axis == 1 else Vector2i(-1, 0)
			var z := ""
			for c in cells:
				z = f.zone_of(c + side) if f.zone_of(c + side) != "" else z
			if z == "":
				for c in cells:
					z = f.zone_of(c - side) if f.zone_of(c - side) != "" else z
			for c in cells:
				f.put(c, K.SOL, "zone", z)
				var i: int = c.y * f.w + c.x
				if f.inside(c):
					f.ceil[i] = maxf(f.ceil_at(c + side), f.ceil_at(c - side))
		_:
			for c in cells:
				f.put(c, K.DEBRIS if t == "debris" else K.PORTE, key)
			v.door_info[key] = {"cost": 0 if t == "porte_courant" else int(o.get("prix", 1000)), "power": t == "porte_courant",
				"debris": t == "debris", "eid": String(o.id)}
