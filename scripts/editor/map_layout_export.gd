class_name MapLayoutExport
extends RefCounted
## Description de carte en maillage tirée d'une carte de l'éditeur validée
## (MapValidator) : même format que assets/maps/kino/layout.json, lu par
## MeshMapLayout (jeu) et construit par MeshMapGeometry (ou, pour les cartes
## faites dans Blender, tools/blender/mesh_map.py). Salles (sols, plafonds,
## dalles d'étage), blocs (murs, allèges, linteaux, décor), garde-corps,
## escaliers (rampe de collision), zones, marqueurs (objets muraux donnés par
## la face du mur et la direction du mur).

const Kd := MapValidator.K

var md: MapValidator
var S := 0.5
var n_floors := 0
var rooms: Array = []
var blocks: Array = []
var walls: Array = []
var rails: Array = []
var stairs: Array = []
## Murs en biais : [{a, b ([x, z]), y0, y1, thick, mat_n, mat_m, room, openings}]
## (MeshMapGeometry : pavés obliques, collisions en CollisionBox tournées).
var obliques: Array = []
var props: Array = []   # décor posé : [{id, model | build, p, yaw, scale, remap, nocollide}]
var blockers: Array = []   # collisions du décor et des luminaires : [{center, size, yaw, barrier, surface}]
var zone_boxes: Array = []   # [étage, volume, zone, boîte]
## Boîtes de zone des morceaux de sol le long des murs obliques : testées après
## celles des salles de la grille (une boîte englobante déborde un peu du mur).
var filler_boxes: Array = []
var ref_room: Dictionary = {}   # étage -> id d'une salle (hauteur de sol des murs)
var door_of: Array = []   # par étage : {Vector2i: porte}


static func build(v: MapValidator) -> Dictionary:
	var ex := MapLayoutExport.new()
	ex.md = v
	return ex._build()


func _r(v: float) -> float:
	return snappedf(v, 0.001)


func wx(px: float) -> float:
	return _r(MapValidator.ORIGIN + px * S)


func top(k: int) -> float:
	return md.floors[k + 1].sol - MapValidator.DALLE if k < n_floors - 1 else md.floors[k].plafond


## Plafond au-dessus d'une case : [hauteur, plafond dessiné (sinon : dessous de dalle)].
func ceil_at(k: int, c: Vector2i) -> Array:
	var own := md.floors[k].ceil_at(c)
	if k == n_floors - 1:
		return [own if own > 0.0 else top(k), true]
	var above := md.floors[k + 1].at(c)
	if above == Kd.TREMIE:
		return ceil_at(k + 1, c)
	if above == Kd.VIDE:
		return [own if own > 0.0 else top(k), true]
	return [md.floors[k + 1].sol - MapValidator.DALLE, false]


func wall_top(k: int, c: Vector2i) -> float:
	if k < n_floors - 1:
		var above := md.floors[k + 1].at(c)
		if above == Kd.TREMIE:
			return wall_top(k + 1, c)
		if above != Kd.VIDE:
			return top(k)
	var own := md.floors[k].ceil_at(c)
	return own if own > 0.0 else top(k)


func _wall_mat(f: MapValidator.Floor, c: Vector2i) -> String:
	var count := {}
	for d in MapValidator.DIRS:
		var z := _side_zone(f, c + d)
		if z != "":
			count[z] = count.get(z, 0) + 1
	var best := ""
	for z in count:
		if best == "" or count[z] > count[best] or (count[z] == count[best] and z < best):
			best = z
	return String(md.wall_mats.get(best, "wall"))


## Rectangles maximaux de cases de même clé ("" : rien). -> [[Rect2i, clé]]
static func merge_rects(w: int, h: int, keys: PackedStringArray) -> Array:
	var used := PackedByteArray()
	used.resize(w * h)
	var out := []
	for y in h:
		for x in w:
			var key := keys[y * w + x]
			if key == "" or used[y * w + x]:
				continue
			var x1 := x
			while x1 + 1 < w and keys[y * w + x1 + 1] == key and not used[y * w + x1 + 1]:
				x1 += 1
			var y1 := y
			var grow := true
			while grow and y1 + 1 < h:
				for xx in range(x, x1 + 1):
					if keys[(y1 + 1) * w + xx] != key or used[(y1 + 1) * w + xx]:
						grow = false
						break
				if grow:
					y1 += 1
			for yy in range(y, y1 + 1):
				for xx in range(x, x1 + 1):
					used[yy * w + xx] = 1
			out.append([Rect2i(x, y, x1 - x + 1, y1 - y + 1), key])
	return out


func _outline(r: Rect2i) -> Array:
	var x0 := wx(r.position.x)
	var x1 := wx(r.end.x)
	var z0 := wx(r.position.y)
	var z1 := wx(r.end.y)
	return [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]


func _build() -> Dictionary:
	S = md.scale
	n_floors = md.floors.size()
	for f in md.floors:
		var dm := {}
		for d in md.doors:
			if d.floor == f.index:
				for c in d.cells:
					dm[c] = d
		door_of.append(dm)
	for f in md.floors:
		_rooms(f)
		_fillers(f)
	for f in md.floors:
		_walls(f)
		_obliques(f)
		_rails(f)
	_decor()
	_props()
	_clips()
	_stairs()
	var markers := _markers()
	_pockets()
	# Zones : boîtes des salles ; étages hauts d'abord, puis les plus petites.
	zone_boxes.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	filler_boxes.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	zone_boxes.append_array(filler_boxes)
	var zones := {}
	var zone_order := []
	for zb in zone_boxes:
		zones.get_or_add(zb[2], {"boxes": []}).boxes.append(zb[3])
		zone_order.append({"zone": zb[2], "box": zb[3]})
	var out := {
		"id": md.id,
		"note": "Généré par l'éditeur de cartes (MapLayoutExport) - ne pas modifier à la main.",
		"rooms": rooms, "walls": walls, "blocks": blocks, "rails": rails, "stairs": stairs,
		"props": props, "blockers": blockers,
		"zones": zones, "zone_order": zone_order, "markers": markers, "map_def": _map_def(),
	}
	if not obliques.is_empty():
		out["obliques"] = obliques
	return out


## Surface d'une partie (« sol », « murs », « plafond ») de la pièce de
## l'éditeur `room_id` : celle de la pièce, sinon celle de sa zone, sinon `fallback`.
func surface_of(room_id: String, part: String, zone: String, fallback: String) -> String:
	var own: Dictionary = md.room_surfaces.get(room_id, {})
	if own.has(part):
		return String(own[part])
	var zm: Dictionary = {"sol": md.floor_mats, "murs": md.wall_mats, "plafond": md.ceil_mats}[part]
	return String(zm.get(zone, fallback))


## Case de sol d'une pièce, y compris sous le décor posé (prefabs, caisses).
func _floor_cell(f: MapValidator.Floor, c: Vector2i) -> bool:
	if md._walk(f, c):
		return true
	return f.at(c) == Kd.MUR and f.key_at(c).begins_with("decor#") and f.room_of(c) != ""


func _rooms(f: MapValidator.Floor) -> void:
	var k := f.index
	var keys := PackedStringArray()
	keys.resize(f.w * f.h)
	var info := {}
	var dc := _diag(k)
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			if not _floor_cell(f, c) or dc.has(c):
				continue
			var ce := ceil_at(k, c)
			var key := ""
			var zone := f.zone_of(c)
			var rid := f.room_of(c)
			if zone == "" and rid != "":
				zone = String(md.room_zone.get(rid, ""))
			if door_of[k].has(c):
				key = "porte%s|%s|%s" % [door_of[k][c].id, ce[0], ce[1]]
				info[key] = [door_of[k][c].id, zone, ce, "wood", "ceiling"]
			else:
				var fm := surface_of(rid, "sol", zone, "concrete")
				var cm := surface_of(rid, "plafond", zone, "ceiling")
				key = "%s|%s|%s|%s|%s" % [zone, ce[0], ce[1], fm, cm]
				info[key] = ["", zone, ce, fm, cm]
			keys[y * f.w + x] = key
	var n := 0
	for rk in merge_rects(f.w, f.h, keys):
		var r: Rect2i = rk[0]
		var inf: Array = info[rk[1]]
		n += 1
		var zone: String = inf[1]
		var rid := ("porte%s_%d" % [inf[0], n]) if inf[0] != "" else ("%s%d_%d" % [zone, k, n])
		var room := {"id": rid, "outline": _outline(r), "floor": _r(f.sol), "ceiling": _r(inf[2][0]),
			"floor_mat": String(inf[3]), "ceiling_mat": String(inf[4])}
		if not inf[2][1]:
			if String(inf[4]) != "ceiling":
				# Plafond choisi sous l'étage du dessus : dessiné juste sous sa dalle.
				room["ceiling"] = _r(float(inf[2][0]) - 0.01)
			else:
				room["no_ceiling"] = true
		if k > 0:
			room["floor_slab"] = MapValidator.DALLE
		rooms.append(room)
		if inf[0] == "":
			if not ref_room.has(k):
				ref_room[k] = rid
			var lo := f.sol - (0.5 if k == 0 else 0.15)
			var b := [wx(r.position.x), _r(lo), wx(r.position.y), wx(r.end.x), _r(inf[2][0]), wx(r.end.y)]
			zone_boxes.append([k, (b[3] - b[0]) * (b[4] - b[1]) * (b[5] - b[2]), zone, b])


## Matériau d'un demi-mur : la moitié (sx, sy) de la case de mur `c` (0 :
## côté ouest / nord, 1 : côté est / sud) prend la texture de la pièce qui la
## touche de ce côté ; un mur mitoyen montre ainsi de chaque côté la texture
## de sa pièce. Sans pièce de ce côté (mur extérieur), celle de la case.
func _half_wall_mat(f: MapValidator.Floor, c: Vector2i, sx: int, sy: int, whole: String) -> String:
	var dx := -1 if sx == 0 else 1
	var dy := -1 if sy == 0 else 1
	for n in [c + Vector2i(dx, 0), c + Vector2i(0, dy), c + Vector2i(dx, dy)]:
		var z := _side_zone(f, n)
		if z != "" and (f.at(n) in [Kd.SOL, Kd.MARQUEUR, Kd.ESCALIER] or _under_decor(f, n)):
			return surface_of(f.room_of(n), "murs", z, "wall")
	return whole


## Case de sol d'une pièce sous un décor posé (prefab, caisse, baril,
## luminaire, barrière invisible) : le raster en fait une case pleine sans
## zone (trajets, validateur) mais, pour l'aspect des murs, c'est toujours le
## sol de sa pièce. L'aspect d'un mur ne dépend que des pièces qui le
## bordent, jamais d'un objet posé contre lui (sinon sa face prenait la
## texture de la pièce d'à côté, ou celle par défaut).
func _under_decor(f: MapValidator.Floor, n: Vector2i) -> bool:
	return f.at(n) == Kd.MUR and f.key_at(n).begins_with("decor#") and f.room_of(n) != ""


## Zone d'une case voisine d'un mur, pour sa texture : la sienne, ou celle de
## la pièce sous un décor posé.
func _side_zone(f: MapValidator.Floor, n: Vector2i) -> String:
	if _under_decor(f, n):
		return String(md.room_zone.get(f.room_of(n), ""))
	return f.zone_of(n)


## Matériau d'une case de mur entière : la pièce la plus présente autour.
func _cell_wall_mat(f: MapValidator.Floor, c: Vector2i) -> String:
	var count := {}
	for d in MapValidator.DIRS:
		var n: Vector2i = c + d
		var z := _side_zone(f, n)
		if z != "":
			var m := surface_of(f.room_of(n), "murs", z, "wall")
			count[m] = count.get(m, 0) + 1
	var best := ""
	for m in count:
		if best == "" or count[m] > count[best] or (count[m] == count[best] and m < best):
			best = m
	return best if best != "" else _wall_mat(f, c)


## Murs, allèges et linteaux : blocs fusionnés sur une grille de demi-cases
## (0,25 m) pour que chaque face d'un mur ait la texture de sa pièce.
func _walls(f: MapValidator.Floor) -> void:
	var k := f.index
	var y0 := f.sol - (0.1 if k == 0 else MapValidator.DALLE)
	var w2 := f.w * 2
	var h2 := f.h * 2
	var main := PackedStringArray()
	var upper := PackedStringArray()
	main.resize(w2 * h2)
	upper.resize(w2 * h2)
	var dc := _diag(k)
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			var i := y * f.w + x
			if dc.has(c):
				continue   # mur en biais : vrai mur oblique (_obliques)
			var kd := f.at(c)
			var lo := ""   # grille principale : "bas|haut"
			var hi := ""   # grille du haut (linteaux)
			if kd == Kd.MUR:
				# Décor bloquant : ses propres blocs (_decor) ou objets, pas un mur.
				if f.key[i].begins_with("decor#"):
					continue
				lo = "%s|%s" % [y0, wall_top(k, c)]
			elif kd == Kd.FENETRE:
				# Allège et linteau autour de l'ouverture (hauteurs de Barricade).
				lo = "%s|%s" % [y0, f.sol + MapValidator.SILL]
				hi = "%s|%s" % [f.sol + MapValidator.LINTEL, wall_top(k, c)]
			elif kd == Kd.PORTE or kd == Kd.DEBRIS:
				var ce: float = ceil_at(k, c)[0]
				if ce > f.sol + md.door_height + 0.05:
					hi = "%s|%s" % [f.sol + md.door_height, ce]
			if lo == "" and hi == "":
				continue
			var whole := _cell_wall_mat(f, c)
			for sy in 2:
				for sx in 2:
					var mat := _half_wall_mat(f, c, sx, sy, whole)
					var j := (y * 2 + sy) * w2 + x * 2 + sx
					if lo != "":
						main[j] = mat + "|" + lo
					if hi != "":
						upper[j] = mat + "|" + hi
	for grid in [main, upper]:
		for rk in merge_rects(w2, h2, grid):
			var r: Rect2i = rk[0]
			var p: PackedStringArray = String(rk[1]).split("|")
			blocks.append({"room": ref_room.get(k, "x"), "box": [wx(r.position.x * 0.5), _r(p[1].to_float()), wx(r.position.y * 0.5),
				wx(r.end.x * 0.5), _r(p[2].to_float()), wx(r.end.y * 0.5)], "mat": p[0]})


# ------------------------------------------------------------------ murs en biais

## Cases des murs en biais de l'étage k ({Vector2i: true}).
func _diag(k: int) -> Dictionary:
	return md.diag_cells[k] if k < md.diag_cells.size() else {}


## Point de l'éditeur (m) -> [x, z] du monde.
static func _xz(m: Vector2) -> Array:
	return [snappedf(m.x + MapGeom.WORLD_OFFSET, 0.001), snappedf(m.y + MapGeom.WORLD_OFFSET, 0.001)]


## Plafond d'une case pour une pièce de plafond `own` (m) : comme ceil_at, mais
## avec le plafond de CETTE pièce (un mur mitoyen porte le plus haut des deux).
func _ceil_room(k: int, c: Vector2i, own: float) -> Array:
	if k == n_floors - 1:
		return [own, true]
	var above := md.floors[k + 1].at(c)
	if above == Kd.TREMIE:
		return ceil_at(k + 1, c)
	if above == Kd.VIDE:
		return [own, true]
	return [md.floors[k + 1].sol - MapValidator.DALLE, false]


## Salle (sol, plafond) d'un morceau de contour `outline` ([[x, z]...], monde).
func _room_entry(rid: String, outline: Array, f: MapValidator.Floor, ce: Array, fm: String, cm: String) -> Dictionary:
	var room := {"id": rid, "outline": outline, "floor": _r(f.sol), "ceiling": _r(ce[0]), "floor_mat": fm, "ceiling_mat": cm}
	if not ce[1]:
		if cm != "ceiling":
			room["ceiling"] = _r(float(ce[0]) - 0.01)
		else:
			room["no_ceiling"] = true
	if f.index > 0:
		room["floor_slab"] = MapValidator.DALLE
	return room


## Sols et plafonds le long des murs en biais : pour chaque pièce, la part de
## ses cases de mur oblique qui est DANS son contour (rangées de cases
## fusionnées, découpées selon le vrai contour puis triangulées par
## MeshMapGeometry) ; le reste de la pièce garde ses rectangles de cases. Le
## sol suit ainsi exactement le trait du mur, sans marches.
func _fillers(f: MapValidator.Floor) -> void:
	var k := f.index
	var dc := _diag(k)
	if dc.is_empty():
		return
	var cells := dc.keys()
	cells.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var half := MapGeom.CELL * 0.5
	for r in md.room_polys[k]:
		var poly: PackedVector2Array = r.poly
		var bb := MapGeom.bbox(poly).grow(MapGeom.CELL)
		var runs := []   # [ligne, x0, x1]
		for c in cells:
			if not bb.has_point(MapGeom.cell_center(c)):
				continue
			if not runs.is_empty() and runs[-1][0] == c.y and runs[-1][2] == c.x - 1:
				runs[-1][2] = c.x
			else:
				runs.append([c.y, c.x, c.x])
		var zone := String(r.zone)
		var fm := surface_of(String(r.id), "sol", zone, "concrete")
		var cm := surface_of(String(r.id), "plafond", zone, "ceiling")
		for run in runs:
			var rect := Rect2(Vector2(run[1], run[0]) * MapGeom.CELL - Vector2(half, half), Vector2((run[2] - run[1] + 1) * MapGeom.CELL, MapGeom.CELL))
			var ce := _ceil_room(k, Vector2i((run[1] + run[2]) / 2, run[0]), float(r.ceil))
			for piece in Geometry2D.intersect_polygons(MapGeom.rect_poly(rect), poly):
				if MapGeom.area(piece) < 1e-4:
					continue
				var outline := []
				for q in piece:
					outline.append(_xz(q))
				rooms.append(_room_entry("biais_%s%d" % [zone, k], outline, f, ce, fm, cm))
				# Zone de ce morceau de sol (testée après les salles de la grille).
				var pb := MapGeom.bbox(piece)
				var lo := f.sol - (0.5 if k == 0 else 0.15)
				var zb := [_r(pb.position.x + MapGeom.WORLD_OFFSET), _r(lo), _r(pb.position.y + MapGeom.WORLD_OFFSET),
					_r(pb.end.x + MapGeom.WORLD_OFFSET), _r(float(ce[0])), _r(pb.end.y + MapGeom.WORLD_OFFSET)]
				filler_boxes.append([k, pb.get_area() * (zb[4] - zb[1]), zone, zb])


## Texture d'un côté de mur en biais : celle des murs de la pièce `rid`.
func _oblique_mat(rid: String) -> String:
	if rid == "":
		return ""
	return surface_of(rid, "murs", String(md.room_zone.get(rid, "")), "wall")


## Murs en biais de l'étage : de vrais murs droits obliques (MeshMapGeometry),
## coupés par tronçons de même hauteur (étage du dessus, double hauteur) et
## percés de leurs ouvertures (portes, débris, passages, fenêtres) ; chaque
## face a la texture de la pièce de son côté. Aux angles entre murs en biais,
## un raccord (pavé ajusté à l'angle) ferme la jonction.
func _obliques(f: MapValidator.Floor) -> void:
	var k := f.index
	if k >= md.oblique_walls.size() or md.oblique_walls[k].is_empty():
		return
	var y0 := f.sol - (0.1 if k == 0 else MapValidator.DALLE)
	var dc := _diag(k)
	var ends := {}   # sommet -> {p, list: [{n, half, top, mat}]}
	for w in md.oblique_walls[k]:
		var a: Vector2 = w.a
		var b: Vector2 = w.b
		var t: Vector2 = w.t
		var mat_pos := _oblique_mat(String(w.pos))
		var mat_neg := _oblique_mat(String(w.neg))
		if mat_pos == "":
			mat_pos = mat_neg if mat_neg != "" else String(md.wall_mats.get("a", "wall"))
		if mat_neg == "":
			mat_neg = mat_pos
		var seg_len := a.distance_to(b)
		var nseg := maxi(1, ceili(seg_len / 0.25))
		var runs := []   # [s0, s1, haut]
		for i in nseg:
			var s := (i + 0.5) * seg_len / nseg
			var top_y := wall_top(k, MapGeom.cell_of(a + t * s))
			if not runs.is_empty() and absf(float(runs[-1][2]) - top_y) < 0.001:
				runs[-1][1] = (i + 1) * seg_len / nseg
			else:
				runs.append([i * seg_len / nseg, (i + 1) * seg_len / nseg, top_y])
		var top_max := 0.0
		for run in runs:
			var pa: Vector2 = a + t * float(run[0])
			var pb: Vector2 = a + t * float(run[1])
			top_max = maxf(top_max, float(run[2]))
			obliques.append({"room": ref_room.get(k, "x"), "a": _xz(pa), "b": _xz(pb), "y0": _r(y0), "y1": _r(float(run[2])),
				"thick": _r(float(w.half) * 2.0), "mat_n": mat_pos, "mat_m": mat_neg,
				"openings": _oblique_cuts(f, pa, t, float(run[1]) - float(run[0]), y0, float(run[2]))})
		if String(w.kind) == "pilier":
			continue   # pilier tourné : un pavé plein, sans raccord
		for e in [a, b]:
			# Bouts à 2 cm près (sommets tracés sans grille, murs mitoyens
			# regroupés avec tolérance) : le même sommet.
			var key := "%.3f:%.3f" % [e.x, e.y]
			if not ends.has(key):
				for k2 in ends:
					if Vector2(ends[k2].p).distance_to(e) < 0.02:
						key = k2
						break
			ends.get_or_add(key, {"p": e, "list": []}).list.append({"n": w.n, "half": float(w.half), "top": top_max, "mat": mat_pos})
	# Raccords des angles (sommets entre murs en biais, hors blocs de la grille).
	var keys := ends.keys()
	keys.sort()
	for key in keys:
		var e: Dictionary = ends[key]
		var v: Vector2 = e.p
		if e.list.size() < 2 or not dc.has(MapGeom.cell_of(v)):
			continue
		var pts := PackedVector2Array([v])
		var top_y := 0.0
		for it in e.list:
			pts.append(v + Vector2(it.n) * float(it.half))
			pts.append(v - Vector2(it.n) * float(it.half))
			top_y = maxf(top_y, float(it.top))
		var box := _min_box(pts)
		if box.is_empty() or float(box.w) * float(box.d) < 0.005:
			continue
		var u: Vector2 = box.u
		var c: Vector2 = box.c
		obliques.append({"room": ref_room.get(k, "x"), "a": _xz(c - u * float(box.w) * 0.5), "b": _xz(c + u * float(box.w) * 0.5),
			"y0": _r(y0), "y1": _r(top_y), "thick": _r(float(box.d)), "mat_n": String(e.list[0].mat), "mat_m": String(e.list[0].mat),
			"openings": [], "joint": true})


## Plus petit rectangle orienté qui contient les points (raccord d'angle) :
## {c (centre), u (direction de la longueur), w (longueur), d (épaisseur)}.
static func _min_box(pts: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(pts)
	var best := {}
	var best_area := INF
	for i in hull.size() - 1:
		var edge := hull[i + 1] - hull[i]
		if edge.length() < 1e-4:
			continue
		var u := edge.normalized()
		var nn := Vector2(-u.y, u.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in hull:
			var q := Vector2(p.dot(u), p.dot(nn))
			lo = lo.min(q)
			hi = hi.max(q)
		var sz := hi - lo
		if sz.x * sz.y < best_area:
			best_area = sz.x * sz.y
			var mid := (lo + hi) * 0.5
			best = {"c": u * mid.x + nn * mid.y, "u": u, "w": sz.x, "d": sz.y}
	return best


## Ouvertures d'un tronçon de mur en biais (de `pa`, direction `t`, longueur
## `seg_len`) : [{t (milieu le long du tronçon), w, y0, y1}] (hauteurs absolues).
func _oblique_cuts(f: MapValidator.Floor, pa: Vector2, t: Vector2, seg_len: float, y0: float, top_y: float) -> Array:
	var out := []
	var nrm := Vector2(-t.y, t.x)
	for key in md.diag_open:
		var o: Dictionary = md.diag_open[key]
		if int(o.floor) != f.index:
			continue
		var p: Vector2 = o.p
		if absf((p - pa).dot(nrm)) > MapGeom.JOIN_TOL or absf(Vector2(o.t).dot(t)) < 0.999:
			continue
		var c := (p - pa).dot(t)
		var hw := float(o.w) * 0.5
		if c + hw <= 0.001 or c - hw >= seg_len - 0.001:
			continue
		var oy0 := y0
		var oy1 := top_y
		match String(o.type):
			"fenetre":
				oy0 = f.sol + MapValidator.SILL
				oy1 = f.sol + MapValidator.LINTEL
			"passage":
				# Passage libre : ouvert jusqu'au plus bas des deux plafonds.
				var ce := INF
				for r in md.room_polys[f.index]:
					if MapGeom.on_boundary(r.poly, p, MapGeom.JOIN_TOL):
						ce = minf(ce, float(r.ceil))
				oy1 = minf(top_y, ce) if ce < INF else top_y
			_:
				if top_y > f.sol + md.door_height + 0.05:
					oy1 = f.sol + md.door_height
		var lo := maxf(c - hw, 0.0)
		var hi := minf(c + hw, seg_len)
		out.append({"t": _r((lo + hi) * 0.5), "w": _r(hi - lo), "y0": _r(oy0), "y1": _r(oy1)})
	return out


## Retrait (m) d'un bloc de décor qui entre dans un mur : ses faces ne sont
## jamais dans le plan d'une face de mur (pas de scintillement, « z-fighting »,
## de l'autre côté d'un mur mitoyen).
const DECOR_WALL_INSET := 0.005


## Décor bloquant (caisses, barils) : un bloc plein à sa hauteur, à sa vraie
## place (posé au centimètre : pas sur les cases arrondies du validateur).
func _decor() -> void:
	for d in md.decor:
		var sol: float = md.floors[d.floor].sol
		var r: Rect2 = d.box
		if bool(d.get("in_wall", false)):
			r = r.grow(-DECOR_WALL_INSET)
		var a: Array = _xz(r.position)
		var b: Array = _xz(r.end)
		blocks.append({"room": ref_room.get(d.floor, "x"), "box": [a[0], _r(sol), a[1], b[0], _r(sol + float(d.h)), b[1]], "mat": String(d.mat)})


## Point du monde d'un point de l'éditeur (m) à l'étage k, `dy` au-dessus du sol.
func _world(k: int, m: Vector2, dy := 0.0) -> Vector3:
	return Vector3(_r(m.x + MapGeom.WORLD_OFFSET), _r(md.floors[k].sol + dy), _r(m.y + MapGeom.WORLD_OFFSET))


static func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## Pavés de collision d'un objet (coordonnées de l'objet) -> « blockers » du
## monde (CollisionBox) : jamais une collision tirée d'un modèle Blender.
func _blockers_of(boxes: Array, origin: Vector3, yaw: float, barrier: bool, surface: String) -> void:
	var b := Basis(Vector3.UP, yaw)
	for bx in boxes:
		var c: Array = bx.center
		blockers.append({"center": _v3(origin + b * Vector3(c[0], c[1], c[2])), "size": bx.size,
			"yaw": _r(yaw + float(bx.get("yaw", 0.0))), "barrier": barrier, "surface": surface})


## Décor posé (prefabs) : objets du jeu (« props » : modèle ou objet
## construit par EditorPrefabs) et leurs collisions (« blockers »).
func _props() -> void:
	for pr in md.props:
		var d: Dictionary = MapCatalog.PREFABS.get(String(pr.prefab), {})
		if d.is_empty():
			continue
		var k: int = pr.floor
		var yaw := -deg_to_rad(float(pr.rot))
		var origin := _world(k, pr.center)
		var block := String(d.bloque)
		var copies: Array = d.get("copies", [[0, 0, 0]])
		for i in copies.size():
			var cp: Array = copies[i]
			var p := origin + Basis(Vector3.UP, yaw) * Vector3(cp[0], 0, cp[1])
			var e := {"id": "%s_%d" % [pr.eid, i] if copies.size() > 1 else String(pr.eid), "p": _v3(p), "yaw": _r(yaw + float(cp[2]))}
			if d.has("model"):
				e["model"] = String(d.model)
				if d.has("scale"):
					e["scale"] = float(d.scale)
				if d.has("remap"):
					e["remap"] = d.remap
				# Collisions du modèle (<modèle>.collision.json) seulement s'il
				# bloque et que le catalogue n'en donne pas.
				if block == "non" or d.has("boxes"):
					e["nocollide"] = true
			else:
				e["build"] = String(d.build)
			props.append(e)
		if block != "non" and d.has("boxes"):
			_blockers_of(d.boxes, origin, yaw, block == "barriere", String(d.get("surface", "concrete")))


## Barrières invisibles (format 5) : un pavé de collision chacune, sur la
## couche BARRIER (joueurs et zombies arrêtés, navmesh cuit autour ; balles et
## grenades passent), du sol jusqu'au plafond de l'étage (ou sa hauteur),
## JAMAIS de maillage en jeu. « clip » et « eid » : l'aperçu 3D peut les
## montrer (MapPreviewBuilder) ; CollisionBox.from_dict les ignore.
func _clips() -> void:
	for cl in md.clips:
		var k: int = cl.floor
		var sol: float = md.floors[k].sol
		var h := float(cl.h)
		if h <= 0.0:
			h = maxf(top(k) - sol, 2.0)
		var sz: Vector2 = cl.size
		blockers.append({"center": _v3(_world(k, cl.center, h * 0.5)), "size": [_r(sz.x), _r(h), _r(sz.y)],
			"yaw": _r(-deg_to_rad(float(cl.rot))), "barrier": true, "surface": "concrete", "clip": true, "eid": String(cl.eid)})


## Garde-corps : bord d'un plancher d'étage sur un vide (sauf en haut d'escalier).
func _rails(f: MapValidator.Floor) -> void:
	var k := f.index
	if k == 0:
		return
	var skip := {}
	for s in md.stairs:
		if s.floor == k - 1:
			# Bord du palier vers les marches (droites ou tournées) : pas de garde-corps.
			for c in s.links:
				for t in s.links[c]:
					var d: Vector2i = c - t
					skip["%d:%d:%d:%d" % [t.x, t.y, d.x, d.y]] = true
	var lines := {}   # "v:x" / "h:z" -> [[début, fin]] (cases)
	for y in f.h:
		for x in f.w:
			var c := Vector2i(x, y)
			if not f.at(c) in [Kd.SOL, Kd.MARQUEUR, Kd.PORTE, Kd.DEBRIS]:
				continue
			for d in MapValidator.DIRS:
				if f.at(c + d) != Kd.TREMIE or skip.has("%d:%d:%d:%d" % [x, y, d.x, d.y]):
					continue
				if d.x != 0:
					lines.get_or_add("v:%d" % (x + (1 if d.x > 0 else 0)), []).append([y, y + 1])
				else:
					lines.get_or_add("h:%d" % (y + (1 if d.y > 0 else 0)), []).append([x, x + 1])
	var keys := lines.keys()
	keys.sort()
	for key in keys:
		var runs: Array = lines[key]
		runs.sort()
		var merged := []
		for r in runs:
			if not merged.is_empty() and r[0] <= merged[-1][1]:
				merged[-1][1] = maxi(merged[-1][1], r[1])
			else:
				merged.append([r[0], r[1]])
		var at := int(String(key).substr(2))
		for m in merged:
			var path := [[wx(at), wx(m[0])], [wx(at), wx(m[1])]] if String(key).begins_with("v") else [[wx(m[0]), wx(at)], [wx(m[1]), wx(at)]]
			rails.append({"room": ref_room.get(k, "x"), "path": path, "y": _r(f.sol), "h": 1.0, "mat": "dark_wood"})


func _stairs() -> void:
	for s in md.stairs:
		var k: int = s.floor
		# Type et réglages (format 6) : clés de la description seulement s'ils
		# ne sont pas ceux d'avant (une carte d'avant garde sa description).
		var opts: Dictionary = md.stair_opts.get(String(s.get("key", "")), {})
		if s.has("diag") and s.diag.get("shaped", false):
			# En L, en U, en colimaçon : l'emprise de ses cases (MapRaster.stair_spec),
			# sens de montée donné.
			var sp := MapRaster.stair_spec(s.diag.obj, md.floors[k].sol, md.floors[k + 1].sol)
			var fa: Array = _xz(Vector2(float(sp.a[0]), float(sp.a[2])))
			var fb: Array = _xz(Vector2(float(sp.b[0]), float(sp.b[2])))
			var e := {"room": ref_room.get(k, "x"), "a": [fa[0], _r(md.floors[k].sol), fa[1]],
				"b": [fb[0], _r(md.floors[k + 1].sol), fb[1]], "w": _r(float(sp.w)), "mat": "wood"}
			e.merge(opts)
			stairs.append(e)
			continue
		if s.has("diag"):
			# Escalier tourné : du milieu du pied au milieu du haut des marches
			# (0,25 m en retrait du contour tracé, comme sur la grille).
			var info: Dictionary = s.diag
			var u: Vector2 = info.up
			var sz: Vector2 = info.size
			var along_x := absf(Vector2(1, 0).rotated(deg_to_rad(float(info.rot))).dot(u)) > 0.7
			var half_run := (sz.x if along_x else sz.y) * 0.5 - MapGeom.WALL_HALF
			var tread := (sz.y if along_x else sz.x) - MapGeom.CELL
			var c: Vector2 = info.center
			var foot: Array = _xz(c - u * half_run)
			var head: Array = _xz(c + u * half_run)
			var ed := {"room": ref_room.get(k, "x"), "a": [foot[0], _r(md.floors[k].sol), foot[1]],
				"b": [head[0], _r(md.floors[k + 1].sol), head[1]], "w": _r(tread), "mat": "wood"}
			ed.merge(opts)
			stairs.append(ed)
			continue
		var r: Rect2i = s.rect
		var d: Vector2i = s.up
		var mid := Vector2(r.position) + Vector2(r.size) * 0.5
		var a := mid
		var b := mid
		if d.x != 0:
			a.x = r.end.x if d.x < 0 else r.position.x
			b.x = r.position.x if d.x < 0 else r.end.x
		else:
			a.y = r.end.y if d.y < 0 else r.position.y
			b.y = r.position.y if d.y < 0 else r.end.y
		var eg := {"room": ref_room.get(k, "x"), "a": [wx(a.x), _r(md.floors[k].sol), wx(a.y)],
			"b": [wx(b.x), _r(md.floors[k + 1].sol), wx(b.y)], "w": _r(s.width * S), "mat": "wood"}
		eg.merge(opts)
		stairs.append(eg)


func _p(k: int, v: Vector2, dy := 0.0) -> Array:
	return [wx(v.x), _r(md.floors[k].sol + dy), wx(v.y)]


func _wall_item(it: Dictionary) -> Dictionary:
	if it.has("oblique"):
		# Mur en biais : direction exacte du mur (vecteur unitaire).
		return {"p": _p(it.floor, it.face), "wall": [_r(it.wall.x), 0, _r(it.wall.y)]}
	return {"p": _p(it.floor, it.face), "wall": [it.wall.x, 0, it.wall.y]}


func _markers() -> Dictionary:
	var m := {"player_spawns": [], "zombie_spawns": [], "doors": [], "wall_buys": [], "perks": [],
		"grenade_buys": [], "box": [], "traps": [], "windows": [], "lamps": []}
	# Départ, regard vers le milieu de la zone de départ.
	var mean := Vector2.ZERO
	for p in md.start_points:
		m.player_spawns.append(_p(p[0], p[1], 0.05))
		mean += p[1]
	mean /= md.start_points.size()
	var cz := Vector2.ZERO
	var nz := 0
	var f0 := md.floors[md.start_points[0][0]]
	for y in f0.h:
		for x in f0.w:
			if f0.zone_of(Vector2i(x, y)) == "a" and f0.at(Vector2i(x, y)) == Kd.SOL:
				cz += Vector2(x + 0.5, y + 0.5)
				nz += 1
	var look := cz / maxi(nz, 1) - mean
	m["player_yaw"] = _r(atan2(-look.x, -look.y)) if look.length() > 2.0 else PI
	# Fenêtres et apparitions derrière elles.
	for w in md.windows:
		var ww := md._world_window(w)
		var p: Vector3 = ww.p
		var sp: Vector3 = ww.spawn
		var inn: Array = [_r(w.inward.x), 0, _r(w.inward.y)] if w.has("oblique") else [w.inward.x, 0, w.inward.y]
		m.windows.append({"p": [_r(p.x), _r(p.y), _r(p.z)], "in": inn, "h": MapValidator.LINTEL,
			"zone": w.zone, "spawns": [[_r(sp.x), _r(sp.y), _r(sp.z)]]})
		m.zombie_spawns.append({"p": [_r(sp.x), _r(sp.y), _r(sp.z)], "zone": w.zone})
	for it in md.floor_items:
		if it.base == "apparition":
			m.zombie_spawns.append({"p": _p(it.floor, it.center), "zone": it.zone})
	# Portes.
	for d in md.doors:
		var r: Rect2i = d.rect
		var thick := r.size.x if d.axis.x != 0 else r.size.y
		var dj := {"id": d.id, "p": _p(d.floor, Vector2(r.position) + Vector2(r.size) * 0.5), "yaw": _r(PI / 2.0) if d.axis.x != 0 else 0.0,
			"w": _r(d.width * S), "h": _r(md.door_height), "depth": _r(thick * S + 0.5), "cost": d.cost, "zones": d.zones}
		if d.has("oblique"):
			# Mur en biais : milieu exact sur le trait, porte tournée comme le mur.
			var t: Vector2 = d.t
			dj["p"] = _p(d.floor, Vector2(d.p) / S + Vector2(0.5, 0.5))
			dj["yaw"] = _r(atan2(-t.y, t.x))
			dj["depth"] = _r(MapGeom.WALL_HALF * 2.0 + 0.5)
		if d.debris:
			dj["debris"] = true
		if d.power:
			dj["power"] = true
		# Format 5 : aspect choisi dans l'éditeur (absent : aspect par défaut).
		if md.variants.has(String(d.get("eid", ""))):
			dj["variant"] = String(md.variants[String(d.eid)])
		m.doors.append(dj)
	# Objets muraux (ordre de lecture de la grille).
	var used_ids := {}
	for it in md.wall_items:
		var e: Dictionary = it.entry
		var wi := _wall_item(it)
		if e.has("arme") or e.has("atout"):
			var base := String(e.get("arme", e.get("atout", "")))
			var n: int = used_ids.get(base, 0) + 1
			used_ids[base] = n
			wi["id"] = base if n == 1 else "%s_%d" % [base, n]
			if e.has("arme"):
				wi["weapon"] = base
				var weid := String(md.eid_of.get(it.key, ""))
				if md.variants.has(weid):
					wi["variant"] = String(md.variants[weid])
				m.wall_buys.append(wi)
			else:
				wi["perk"] = base
				m.perks.append(wi)
			continue
		match it.base:
			"boite", "boite_depart":
				m.box.append(wi)
			"courant":
				m["power"] = wi
			"pap":
				m["pap"] = wi
			"grenades":
				wi["id"] = "grenades_%d" % (m.grenade_buys.size() + 1)
				m.grenade_buys.append(wi)
			"poste_central":
				m["_mainframe"] = wi
	# Pièges : zone au sol, un ou deux leviers.
	for it in md.floor_items:
		if it.base != "piege":
			continue
		var r: Rect2i = it.rect
		var sol: float = md.floors[it.floor].sol
		var lv: Array = it.get("levers", [])
		if lv.is_empty():
			# Zone sans levier (carte pas encore vérifiée : aperçu 3D) : pas de
			# piège, jamais d'erreur (une erreur de script dans le fil de
			# l'aperçu peut planter le jeu exporté).
			continue
		var t := {"id": "trap_%d" % (m.traps.size() + 1), "lever": _wall_item(lv[0]),
			"area": [wx(r.position.x), _r(sol), wx(r.position.y), wx(r.end.x), _r(sol + 2.5), wx(r.end.y)],
			"active": 40.0, "cooldown": 60.0}
		var tg: Dictionary = md.diag_traps.get(String(md.eid_of.get(it.key, "")), {})
		if not tg.is_empty():
			# Zone tournée ou hors de la grille : le vrai rectangle (0,25 m en
			# retrait du contour, comme sur la grille), tourné autour de son centre.
			var c: Array = _xz(tg.center)
			var h: Vector2 = (Vector2(tg.size) - Vector2.ONE * MapGeom.CELL).max(Vector2.ONE * MapGeom.CELL) * 0.5
			t["area"] = [_r(c[0] - h.x), _r(sol), _r(c[1] - h.y), _r(c[0] + h.x), _r(sol + 2.5), _r(c[1] + h.y)]
			t["yaw"] = _r(-deg_to_rad(float(tg.rot)))
		if lv.size() > 1:
			t["lever2"] = _wall_item(lv[1])
		m.traps.append(t)
	# Téléporteur.
	var pad: Variant = null
	var exit: Variant = null
	for it in md.floor_items:
		if it.base == "teleporteur":
			pad = it
		elif it.base == "arrivee":
			exit = it
	if pad != null and exit != null:
		var tp := {"pad": _p(pad.floor, pad.center), "exit": _p(exit.floor, exit.center, 0.05), "exit_zone": exit.zone}
		if m.has("_mainframe"):
			tp["mainframe"] = m._mainframe
		m["teleporter"] = tp
	m.erase("_mainframe")
	m.lamps = _lamps() if md.lamps_auto else []
	for l in md.lamps_extra:
		if l.has("luminaire"):
			m.lamps.append(_fixture(l))
		else:
			m.lamps.append(_lamp(int(l.floor), Vector2i(floori(l.center.x), floori(l.center.y))))
	return m


## Luminaire posé : lumière (couleur, intensité, portée, courant, vacillement)
## et son objet (« fixture » : EditorPrefabs.fixture), à la hauteur de son
## montage (plafond, mur, sol ou dessus d'un meuble).
func _fixture(l: Dictionary) -> Dictionary:
	var d: Dictionary = MapCatalog.LIGHTS.get(String(l.luminaire), {})
	var k := int(l.floor)
	var c: Vector2 = l.center
	var cell := Vector2i(floori(c.x), floori(c.y))
	var sol: float = md.floors[k].sol
	var fix_y := 0.0   # hauteur de l'objet (m au-dessus du sol)
	var light_y := 0.0
	match String(l.mount):
		"plafond":
			var h: float = float(ceil_at(k, cell)[0]) - sol
			fix_y = h
			light_y = h - float(d.get("drop", 0.4))
		"mur":
			# Hauteur choisie (format 7), toujours sous le plafond de la pièce.
			fix_y = float(l.get("y", d.get("y", 2.0)))
			fix_y = clampf(fix_y, MapCatalog.WALL_LIGHT_HEIGHT[0], maxf(MapCatalog.WALL_LIGHT_HEIGHT[0], float(ceil_at(k, cell)[0]) - sol - 0.15))
			light_y = fix_y
		_:
			fix_y = float(l.get("support", 0.0))
			light_y = fix_y + float(d.get("y", 0.5))
	var at := Vector2(wx(c.x), wx(c.y))
	var pl := Vector3(at.x, sol + light_y, at.y)
	if String(l.mount) == "mur":
		# La lumière devant l'applique (0,2 m du mur), pas dans le mur.
		var wv := Vector2(l.wall)
		pl -= Vector3(wv.x, 0, wv.y) * 0.2
	var col: Color = l.color
	var e := {"p": _v3(pl), "range": _r(float(l.range)), "energy": _r(float(l.energy) * 1.4), "color": col.to_html(false),
		"power": bool(l.power), "flicker": bool(l.flicker), "fixture": String(l.luminaire),
		"fixture_p": _v3(Vector3(at.x, sol + fix_y, at.y)), "yaw": _r(float(l.yaw))}
	var boxes: Array = l.get("boxes", [])
	if not boxes.is_empty() and String(d.get("bloque", "non")) != "non":
		_blockers_of(boxes, Vector3(at.x, sol + fix_y, at.y), float(l.yaw), bool(l.barrier), "metal")
	return e


## Lampes : une grille de 6 m par zone et par étage, sous le plafond.
func _lamps() -> Array:
	var out := []
	var step := roundi(6.0 / S)
	for f in md.floors:
		var k := f.index
		for z in md.zones:
			var cells := []
			var lo := Vector2i(f.w, f.h)
			var hi := Vector2i(-1, -1)
			for y in f.h:
				for x in f.w:
					var c := Vector2i(x, y)
					if f.zone_of(c) == z and f.at(c) in [Kd.SOL, Kd.MARQUEUR]:
						cells.append(c)
						lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
						hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
			if cells.is_empty():
				continue
			var got := 0
			var nx := maxi(1, roundi(float(hi.x - lo.x + 1) / step))
			var ny := maxi(1, roundi(float(hi.y - lo.y + 1) / step))
			for iy in ny:
				for ix in nx:
					var c := Vector2i(lo.x + int((ix + 0.5) * (hi.x - lo.x + 1) / nx), lo.y + int((iy + 0.5) * (hi.y - lo.y + 1) / ny))
					if f.zone_of(c) != z or not f.at(c) in [Kd.SOL, Kd.MARQUEUR]:
						continue
					out.append(_lamp(k, c))
					got += 1
			if got == 0:
				var mean := Vector2.ZERO
				for c in cells:
					mean += Vector2(c)
				mean /= cells.size()
				cells.sort_custom(func(a, b): return (Vector2(a) - mean).length() < (Vector2(b) - mean).length())
				out.append(_lamp(k, cells[0]))
	return out


func _lamp(k: int, c: Vector2i) -> Dictionary:
	var ce: float = ceil_at(k, c)[0]
	var h := ce - md.floors[k].sol
	return {"p": _p(k, Vector2(c) + Vector2(0.5, 0.5), h - 0.35), "range": _r(clampf(h * 1.6 + 4.0, 8.0, 13.0)), "energy": 2.2}


## Cours des zombies derrière les fenêtres : sol, plafond bas, trois murs.
func _pockets() -> void:
	for i in md.windows.size():
		var w: Dictionary = md.windows[i]
		var k: int = w.floor
		var sol: float = md.floors[k].sol
		if w.has("oblique"):
			_pocket_oblique(i, w, k, sol)
			continue
		var r: Rect2i = w.pocket
		var x0 := wx(r.position.x)
		var x1 := wx(r.end.x)
		var z0 := wx(r.position.y)
		var z1 := wx(r.end.y)
		var room := {"id": "dehors_%d" % i, "outline": _outline(r), "floor": _r(sol), "ceiling": _r(sol + MapValidator.POCKET_HEIGHT),
			"floor_mat": "cobble", "ceiling_mat": "ceiling"}
		if k > 0:
			room["floor_slab"] = MapValidator.DALLE
		rooms.append(room)
		var inn: Vector2i = w.inward
		var path := []
		if inn == Vector2i(0, 1):
			path = [[x0, z1], [x0, z0], [x1, z0], [x1, z1]]
		elif inn == Vector2i(0, -1):
			path = [[x0, z0], [x0, z1], [x1, z1], [x1, z0]]
		elif inn == Vector2i(1, 0):
			path = [[x1, z0], [x0, z0], [x0, z1], [x1, z1]]
		else:
			path = [[x0, z0], [x1, z0], [x1, z1], [x0, z1]]
		walls.append({"room": "dehors_%d" % i, "path": path, "y0": _r(sol - (0.25 if k == 0 else MapValidator.DALLE)),
			"y1": _r(sol + MapValidator.POCKET_HEIGHT), "thick": 0.3, "mat": "brick", "openings": []})


## Cour d'une fenêtre sur un mur en biais : sol et plafond tournés comme le
## mur (de sa face extérieure à 2,75 m du trait, 3 m de large), trois murs.
func _pocket_oblique(i: int, w: Dictionary, k: int, sol: float) -> void:
	var poly: PackedVector2Array = w.pocket_poly
	var outline := []
	for q in poly:
		outline.append(_xz(q))
	var room := {"id": "dehors_%d" % i, "outline": outline, "floor": _r(sol), "ceiling": _r(sol + MapValidator.POCKET_HEIGHT),
		"floor_mat": "cobble", "ceiling_mat": "ceiling"}
	if k > 0:
		room["floor_slab"] = MapValidator.DALLE
	rooms.append(room)
	# oriented_rect : [face - t, face + t, fond + t, fond - t] ; le côté de la face reste ouvert.
	walls.append({"room": "dehors_%d" % i, "path": [_xz(poly[1]), _xz(poly[2]), _xz(poly[3]), _xz(poly[0])],
		"y0": _r(sol - (0.25 if k == 0 else MapValidator.DALLE)), "y1": _r(sol + MapValidator.POCKET_HEIGHT), "thick": 0.3, "mat": "brick", "openings": []})


func _map_def() -> Dictionary:
	var doors := {}
	for d in md.doors:
		doors[d.id] = {"cost": d.cost}
	var n_box := 0
	var start := -1
	for it in md.wall_items:
		if it.base == "boite_depart":
			start = n_box
		if it.base == "boite" or it.base == "boite_depart":
			n_box += 1
	var names := {}
	for z in md.zones:
		names[z] = String(md.zone_names.get(z, "Zone " + z.to_upper()))
	var has_mainframe := md.wall_items.any(func(it): return it.base == "poste_central")
	return {
		"display_name": md.display_name if md.display_name != "" else md.id.to_upper(),
		"description": md.description, "music": md.music, "zone_names": names, "doors": doors,
		"open_links": md.open_links, "box_start": maxi(start, 0),
		"box_starts": [] if start >= 0 else range(n_box),
		"teleporter_link": has_mainframe,
	}
