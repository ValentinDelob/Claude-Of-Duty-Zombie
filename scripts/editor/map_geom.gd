class_name MapGeom
extends RefCounted
## Géométrie 2D de l'éditeur de cartes (docs/MAP_AUTHORING.md). Repère de
## l'éditeur : mètres, x vers la droite (est), y vers le bas (sud), soit le
## plan (x, z) du jeu décalé de WORLD_OFFSET. Fonctions pures, testées par
## tests/test_map_editor.gd.
##
## Grille de conversion : une case de 0,5 m CENTRÉE sur chaque multiple de
## 0,5 m (case i : centre x = 0,5·i). Les murs d'une pièce sont les cases que
## traverse son contour : un contour tracé sur la grille donne un mur de 0,5 m
## centré sur le trait, et le bord commun de deux pièces collées est le même
## mur pour les deux (mur mitoyen unique).

const CELL := 0.5
const EPS := 0.001
## Monde du jeu = éditeur + WORLD_OFFSET (x, z) : la case i de la grille a
## son centre en x = 4 + 0,5·i + 0,25 dans le jeu (MapValidator.ORIGIN).
const WORLD_OFFSET := 4.25
## Directions des murs : « n » = le mur est au nord de l'objet (y plus petit).
const DIRS := {"n": Vector2i(0, -1), "s": Vector2i(0, 1), "e": Vector2i(1, 0), "o": Vector2i(-1, 0)}


static func v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func arr(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


static func poly(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(v2(p))
	return out


static func poly_arr(p: PackedVector2Array) -> Array:
	var out := []
	for v in p:
		out.append(arr(v))
	return out


static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Rectangle [x0, y0, x1, y1] (ordre quelconque) -> Rect2 normalisé.
static func rect_of(a: Array) -> Rect2:
	var p0 := Vector2(minf(a[0], a[2]), minf(a[1], a[3]))
	var p1 := Vector2(maxf(a[0], a[2]), maxf(a[1], a[3]))
	return Rect2(p0, p1 - p0)


static func rect_arr(r: Rect2) -> Array:
	return [snappedf(r.position.x, 0.001), snappedf(r.position.y, 0.001), snappedf(r.end.x, 0.001), snappedf(r.end.y, 0.001)]


static func bbox(p: PackedVector2Array) -> Rect2:
	if p.is_empty():
		return Rect2()
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


static func area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


static func centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in p:
		c += v
	return c / maxf(1.0, p.size())


## Contour rectangle aligné sur les axes (4 sommets) ?
static func is_axis_rect(p: PackedVector2Array) -> bool:
	if p.size() != 4:
		return false
	var r := bbox(p)
	for v in p:
		var on_x := absf(v.x - r.position.x) < EPS or absf(v.x - r.end.x) < EPS
		var on_y := absf(v.y - r.position.y) < EPS or absf(v.y - r.end.y) < EPS
		if not (on_x and on_y):
			return false
	return absf(area(p) - r.get_area()) < EPS


static func contains(p: PackedVector2Array, pt: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(pt, p)


static func dist_to_segment(pt: Vector2, a: Vector2, b: Vector2) -> float:
	return pt.distance_to(Geometry2D.get_closest_point_to_segment(pt, a, b))


static func on_boundary(p: PackedVector2Array, pt: Vector2, tol := EPS) -> bool:
	for i in p.size():
		if dist_to_segment(pt, p[i], p[(i + 1) % p.size()]) <= tol:
			return true
	return false


## Point strictement à l'intérieur (ni dehors, ni sur le contour).
static func strictly_inside(p: PackedVector2Array, pt: Vector2) -> bool:
	return contains(p, pt) and not on_boundary(p, pt)


## Contour simple (pas d'arêtes qui se croisent), au moins 3 sommets, non plat.
static func is_simple(p: PackedVector2Array) -> bool:
	var n := p.size()
	if n < 3 or area(p) < 0.01:
		return false
	for i in n:
		var a1 := p[i]
		var a2 := p[(i + 1) % n]
		if a1.distance_to(a2) < EPS:
			return false
		for j in range(i + 1, n):
			if absi(i - j) <= 1 or (i == 0 and j == n - 1):
				continue
			if Geometry2D.segment_intersects_segment(a1, a2, p[j], p[(j + 1) % n]) != null:
				return false
	return true


## Les intérieurs de deux contours se recouvrent-ils (plus que se toucher) ?
static func overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if not bbox(a).grow(-EPS).intersects(bbox(b).grow(-EPS)):
		return false
	for part in Geometry2D.intersect_polygons(a, b):
		if area(part) > 0.01:
			return true
	return false


## Segments communs (colinéaires, qui se recouvrent) des contours de deux
## pièces : [[a, b], ...].
static func common_segments(pa: PackedVector2Array, pb: PackedVector2Array) -> Array:
	var out := []
	if not bbox(pa).grow(0.01).intersects(bbox(pb).grow(0.01)):
		return out
	for i in pa.size():
		out.append_array(edge_common(pa[i], pa[(i + 1) % pa.size()], pb))
	return out


## Parties du segment [a1, a2] qui longent le contour `pb` : [[a, b], ...].
static func edge_common(a1: Vector2, a2: Vector2, pb: PackedVector2Array) -> Array:
	var out := []
	var d := (a2 - a1)
	var seg_len := d.length()
	if seg_len < EPS:
		return out
	d /= seg_len
	var n := Vector2(-d.y, d.x)
	for j in pb.size():
		var b1 := pb[j]
		var b2 := pb[(j + 1) % pb.size()]
		# Colinéaires : b1 et b2 sur la droite de (a1, a2).
		if absf((b1 - a1).dot(n)) > EPS or absf((b2 - a1).dot(n)) > EPS:
			continue
		var t1 := (b1 - a1).dot(d)
		var t2 := (b2 - a1).dot(d)
		var lo := maxf(0.0, minf(t1, t2))
		var hi := minf(seg_len, maxf(t1, t2))
		if hi - lo > EPS:
			out.append([a1 + d * lo, a1 + d * hi])
	return out


## Le segment [a, b] coupe-t-il le carré de centre `c` et de demi-côté `h` ?
## (découpage de Liang-Barsky)
static func segment_hits_square(a: Vector2, b: Vector2, c: Vector2, h: float) -> bool:
	var lo := c - Vector2(h, h)
	var hi := c + Vector2(h, h)
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var p := d[axis]
		var q0 := a[axis] - lo[axis]
		var q1 := hi[axis] - a[axis]
		if absf(p) < 1e-9:
			if q0 < 0.0 or q1 < 0.0:
				return false
			continue
		var ta := -q0 / p
		var tb := q1 / p
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


## Cases (Vector2i) traversées par le segment [a, b] (murs).
static func segment_cells(a: Vector2, b: Vector2) -> Array:
	var out := []
	var i0 := floori(minf(a.x, b.x) / CELL) - 1
	var i1 := ceili(maxf(a.x, b.x) / CELL) + 1
	var j0 := floori(minf(a.y, b.y) / CELL) - 1
	var j1 := ceili(maxf(a.y, b.y) / CELL) + 1
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if segment_hits_square(a, b, Vector2(i, j) * CELL, CELL * 0.5 - 0.0005):
				out.append(Vector2i(i, j))
	return out


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.y / CELL))


## Première case d'une rangée de `n` cases centrée sur `along` (m).
static func first_cell(along: float, n: int) -> int:
	return roundi((along - (n - 1) * CELL * 0.5) / CELL)


## Position le long d'un mur arrondie pour que `n` cases y tiennent
## exactement (pas de 0,25 m quand n est pair).
static func snap_along(along: float, n: int) -> float:
	return first_cell(along, n) * CELL + (n - 1) * CELL * 0.5


## Cases dont le centre est strictement dans le rectangle (escaliers, pièges).
static func rect_cells_inside(r: Rect2) -> Array:
	var out := []
	for j in range(floori(r.position.y / CELL + EPS) + 1, ceili(r.end.y / CELL - EPS)):
		for i in range(floori(r.position.x / CELL + EPS) + 1, ceili(r.end.x / CELL - EPS)):
			out.append(Vector2i(i, j))
	return out


## Cases dont le centre est dans le rectangle, bords compris (piliers : leur
## contour est un mur, comme celui d'une pièce).
static func rect_cells_closed(r: Rect2) -> Array:
	var out := []
	for j in range(ceili(r.position.y / CELL - EPS), floori(r.end.y / CELL + EPS) + 1):
		for i in range(ceili(r.position.x / CELL - EPS), floori(r.end.x / CELL + EPS) + 1):
			out.append(Vector2i(i, j))
	return out


## Rectangle (m) couvert par des cases (bords des cases).
static func cells_rect(cells: Array) -> Rect2:
	if cells.is_empty():
		return Rect2()
	var r := Rect2(cell_center(cells[0]) - Vector2.ONE * CELL * 0.5, Vector2.ONE * CELL)
	for c in cells:
		r = r.merge(Rect2(cell_center(c) - Vector2.ONE * CELL * 0.5, Vector2.ONE * CELL))
	return r


## Tourne un point de 90° (sens horaire à l'écran) autour de `c`.
static func rot90(p: Vector2, c: Vector2) -> Vector2:
	var d := p - c
	return c + Vector2(-d.y, d.x)


static func dir_vec(d: String) -> Vector2:
	var v: Vector2i = DIRS.get(d, Vector2i(0, -1))
	return Vector2(v)


## Direction suivante (rotation de 90° horaire) : n -> e -> s -> o.
static func dir_rot(d: String) -> String:
	return {"n": "e", "e": "s", "s": "o", "o": "n"}.get(d, "n")


## Direction opposée.
static func dir_back(d: String) -> String:
	return {"n": "s", "s": "n", "e": "o", "o": "e"}.get(d, "s")
