class_name CubeColumns
extends RefCounted
## Colonnes de cubes de l'architecture (docs/VOXEL_ARCHITECTURE_PLAN.md
## § 2.3, lot D) : escaliers, rampes, colimaçons, garde-corps et pentes en
## terrasses. Une grille de cases carrées (côté `cell` : 5 cm, ou 10 cm pour
## les escaliers tournés et le colimaçon) alignée sur la grille du monde ;
## des pavés pleins de cases entières, de hauteur en cubes de 5 cm. Une case
## appartient à une forme si son centre (poussé d'un rien, pour départager un
## bord qui passe pile au centre) y tombe.
##
## Rendu (emit) : seules les faces visibles, fusionnées en rectangles (dessus
## et dessous par hauteur, côtés par rangée), toutes axiales, tous les
## sommets sur la grille de 5 cm. Les pavés sont rangés sur une grille
## comprimée (leurs seuls bords) : une marche de 2,5 m de large posée d'un
## bloc ne coûte qu'une case. Les dessous passent par
## MeshMapGeometry._down_face (plafond dans le même plan : une seule face).
## Aucune collision : les collisions restent celles d'avant (rampes, paliers,
## panneaux), posées par MeshMapGeometry.

const CUBE := 0.05
## Poussée du centre d'une case (départage un bord qui passe pile au centre :
## un seul des deux côtés prend la case).
const NUDGE := Vector2(1.3e-4, 0.7e-4)

var cell := CUBE
var origin := Vector2.ZERO
## Pavés pleins : [i0, j0, i1, j1, y0, y1] (cases [i0, i1[ × [j0, j1[,
## hauteur en cubes de 5 cm).
var boxes: Array = []
## Hauteur (cubes) des dessous posés au sol : pas de face dessinée.
var floor_level := -(1 << 30)


func _init(c := CUBE, o := Vector2.ZERO) -> void:
	cell = c
	origin = o


static func cubes(y: float) -> int:
	return roundi(y / CUBE)


func center(k: Vector2i) -> Vector2:
	return origin + (Vector2(k) + Vector2(0.5, 0.5)) * cell


func cell_of(q: Vector2) -> Vector2i:
	return Vector2i(floori((q.x - origin.x) / cell), floori((q.y - origin.y) / cell))


## Ajoute l'intervalle plein [y0, y1] (m, arrondis au cube) à la case `k`.
func add(k: Vector2i, y0: float, y1: float) -> void:
	add_box(k.x, k.y, k.x + 1, k.y + 1, y0, y1)


## Pavé plein des cases [i0, i1[ × [j0, j1[, de y0 à y1 (m, arrondis au cube).
func add_box(i0: int, j0: int, i1: int, j1: int, y0: float, y1: float) -> void:
	var a := cubes(y0)
	var b := cubes(y1)
	if b > a and i1 > i0 and j1 > j0:
		boxes.append([i0, j0, i1, j1, a, b])


## Cases [début, fin[ (le long de x : axis 0, de z : axis 1) dont le centre
## poussé est dans [lo, hi[ (m).
func span(lo: float, hi: float, axis: int) -> Vector2i:
	var o := origin[axis] + NUDGE[axis]
	return Vector2i(ceili((lo - o) / cell - 0.5), ceili((hi - o) / cell - 0.5))


## Pavé d'un rectangle du monde aligné sur les axes (centres dedans).
func add_rect(r: Rect2, y0: float, y1: float) -> void:
	var sx := span(r.position.x, r.end.x, 0)
	var sz := span(r.position.y, r.end.y, 1)
	add_box(sx.x, sz.x, sx.y, sz.y, y0, y1)


## Cases dont le centre est dans le rectangle `bb` (m) : [[case, centre poussé]].
func cells_in(bb: Rect2) -> Array:
	var out := []
	var k0 := cell_of(bb.position - Vector2(cell, cell))
	var k1 := cell_of(bb.end + Vector2(cell, cell))
	for j in range(k0.y, k1.y + 1):
		for i in range(k0.x, k1.x + 1):
			var k := Vector2i(i, j)
			out.append([k, center(k) + NUDGE])
	return out


## Cases d'un contour (centre dedans) : intervalle [y0, y1] ; un rectangle
## aligné sur les axes d'un seul pavé.
func fill_poly(poly: PackedVector2Array, y0: float, y1: float) -> void:
	var bb := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		bb = bb.expand(q)
	if poly.size() == 4 and _axis_rect(poly):
		add_rect(bb, y0, y1)
		return
	for e in cells_in(bb):
		if Geometry2D.is_point_in_polygon(e[1], poly):
			add(e[0], y0, y1)


static func _axis_rect(p: PackedVector2Array) -> bool:
	for i in 4:
		var d := p[(i + 1) % 4] - p[i]
		if absf(d.x) > 1e-5 and absf(d.y) > 1e-5:
			return false
	return true


## Bande de largeur `w` le long du segment a -> b, prolongée de `ext` à
## chaque bout, de hauteurs `heights(t)` (Array de Vector2 : [bas, haut] en
## m ; t : distance depuis a, bornée à [0, longueur]) : un segment sur les
## axes est posé par tronçons de hauteurs égales (un pavé chacun) ; sinon
## case par case (band).
func strip(a: Vector2, b: Vector2, w: float, ext: float, heights: Callable) -> void:
	var len := a.distance_to(b)
	if len < 0.001:
		return
	var d := (b - a) / len
	if absf(d.x) > 1e-6 and absf(d.y) > 1e-6:
		band(a, b, w, ext, func(k: Vector2i, t: float, _q: Vector2) -> void:
			for iv: Vector2 in heights.call(t):
				add(k, iv.x, iv.y))
		return
	var ax := 0 if absf(d.x) > 0.5 else 1
	var la := 1 - ax
	var sg := signf(d[ax])
	var lat := span(a[la] - w * 0.5, a[la] + w * 0.5, la)
	var run := span(minf(a[ax], b[ax]) - ext, maxf(a[ax], b[ax]) + ext, ax)
	var start := run.x
	var prev: Array = []
	for i in range(run.x, run.y + 1):
		var cur: Array = []
		if i < run.y:
			var c := origin[ax] + (i + 0.5) * cell + NUDGE[ax]
			cur = heights.call(clampf((c - a[ax]) * sg, 0.0, len))
		if i > run.x and (i == run.y or cur != prev):
			for iv: Vector2 in prev:
				if ax == 0:
					add_box(start, lat.x, i, lat.y, iv.x, iv.y)
				else:
					add_box(lat.x, start, lat.y, i, iv.x, iv.y)
			start = i
		prev = cur


## Bande de largeur `w` le long du segment a -> b (prolongée de `ext` à
## chaque bout) : appelle fn(case, t, centre) pour chaque case dont le centre
## y tombe (t : distance le long du segment depuis a, bornée à [0, longueur]).
func band(a: Vector2, b: Vector2, w: float, ext: float, fn: Callable) -> void:
	var len := a.distance_to(b)
	if len < 0.001:
		return
	var d := (b - a) / len
	var nrm := Vector2(-d.y, d.x)
	var bb := Rect2(a, Vector2.ZERO).expand(b).grow(ext + w)
	for e in cells_in(bb):
		var q: Vector2 = e[1]
		var t := (q - a).dot(d)
		if t < -ext or t > len + ext or absf((q - a).dot(nrm)) > w * 0.5:
			continue
		fn.call(e[0], clampf(t, 0.0, len), q)


# ------------------------------------------------------------------ rendu

## Faces visibles dans le groupe `g` de `geo` (MeshMapGeometry). `lean` :
## axes (Vector3 horizontaux) vers lesquels pencher la normale d'éclairage
## des faces verticales (escalier tourné : comme les murs en biais,
## MeshMapGeometry.step_shade) ; vide : la normale de la face.
## -> nombre de faces (quadrilatères) créées.
func emit(geo: MeshMapGeometry, g: Dictionary, lean: Array = []) -> int:
	if boxes.is_empty():
		return 0
	# Grille comprimée : les seuls bords des pavés.
	var xs_set := {}
	var zs_set := {}
	for bx: Array in boxes:
		xs_set[bx[0]] = true
		xs_set[bx[2]] = true
		zs_set[bx[1]] = true
		zs_set[bx[3]] = true
	var xs: Array = xs_set.keys()
	var zs: Array = zs_set.keys()
	xs.sort()
	zs.sort()
	var xi := {}
	var zi := {}
	for i in xs.size():
		xi[xs[i]] = i
	for j in zs.size():
		zi[zs[j]] = j
	# Case comprimée -> intervalles (cubes) triés et fusionnés.
	var cols := {}
	for bx: Array in boxes:
		for j in range(int(zi[bx[1]]), int(zi[bx[3]])):
			for i in range(int(xi[bx[0]]), int(xi[bx[2]])):
				(cols.get_or_add(Vector2i(i, j), []) as Array).append(Vector2i(bx[4], bx[5]))
	for k in cols:
		var iv: Array = cols[k]
		if iv.size() == 1:
			continue
		iv.sort_custom(func(p: Vector2i, q: Vector2i): return p.x < q.x)
		var merged: Array = []
		for v: Vector2i in iv:
			if not merged.is_empty() and v.x <= (merged[-1] as Vector2i).y:
				merged[-1] = Vector2i(merged[-1].x, maxi(merged[-1].y, v.y))
			else:
				merged.append(v)
		cols[k] = merged
	var wx := func(i: int) -> float: return origin.x + int(xs[i]) * cell
	var wz := func(j: int) -> float: return origin.y + int(zs[j]) * cell
	var faces := 0
	# Dessus et dessous, par hauteur.
	var tops := {}
	var bots := {}
	for k: Vector2i in cols:
		for v: Vector2i in cols[k]:
			(tops.get_or_add(v.y, {}) as Dictionary)[k] = true
			if v.x != floor_level:
				(bots.get_or_add(v.x, {}) as Dictionary)[k] = true
	for y: int in tops:
		for r: Rect2i in _rects(tops[y]):
			MeshMapGeometry._quad(g, _rect_pts(r, y * CUBE, wx, wz), Vector3.UP)
			faces += 1
	for y: int in bots:
		for r: Rect2i in _rects(bots[y]):
			geo._down_face(g, _rect_pts(r, y * CUBE, wx, wz))
			faces += 1
	# Côtés : partie de chaque plein que la case voisine ne couvre pas,
	# fusionnée le long de la rangée. Clé : (sens, plan, bas, haut) -> cases.
	var sides := {}
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for k: Vector2i in cols:
		var mine: Array = cols[k]
		for di in 4:
			var d: Vector2i = dirs[di]
			var nb: Array = cols.get(k + d, [])
			if nb == mine:
				continue
			var plane := (k.x + (1 if d.x > 0 else 0)) if d.x != 0 else (k.y + (1 if d.y > 0 else 0))
			var along := k.y if d.x != 0 else k.x
			for v: Vector2i in mine:
				for piece: Vector2i in _minus(v, nb):
					(sides.get_or_add(Vector4i(di, plane, piece.x, piece.y), []) as Array).append(along)
	for key: Vector4i in sides:
		var list: Array = sides[key]
		list.sort()
		var d: Vector2i = dirs[key.x]
		var n := Vector3(d.x, 0, d.y)
		var sn := _lean(n, lean)
		var y0 := key.z * CUBE
		var y1 := key.w * CUBE
		var i := 0
		while i < list.size():
			var j := i
			while j + 1 < list.size() and int(list[j + 1]) == int(list[j]) + 1:
				j += 1
			var pts := []
			if d.x != 0:
				var px: float = wx.call(key.y)
				var a0: float = wz.call(int(list[i]))
				var a1: float = wz.call(int(list[j]) + 1)
				pts = [Vector3(px, y0, a0), Vector3(px, y0, a1), Vector3(px, y1, a1), Vector3(px, y1, a0)]
			else:
				var pz: float = wz.call(key.y)
				var a0: float = wx.call(int(list[i]))
				var a1: float = wx.call(int(list[j]) + 1)
				pts = [Vector3(a0, y0, pz), Vector3(a1, y0, pz), Vector3(a1, y1, pz), Vector3(a0, y1, pz)]
			MeshMapGeometry._quad(g, pts, n, true, false, sn)
			faces += 1
			i = j + 1
	return faces


## Normale d'éclairage penchée vers l'axe de `lean` le plus proche de `n`.
static func _lean(n: Vector3, lean: Array) -> Vector3:
	if lean.is_empty() or MeshMapGeometry.step_shade <= 0.0:
		return Vector3.ZERO
	var best: Vector3 = lean[0]
	for a: Vector3 in lean:
		if a.dot(n) > best.dot(n):
			best = a
	return (n + best * MeshMapGeometry.step_shade).normalized()


## Coins (m) d'un rectangle de cases comprimées à la hauteur y, dans l'ordre du contour.
static func _rect_pts(r: Rect2i, y: float, wx: Callable, wz: Callable) -> Array:
	var x0: float = wx.call(r.position.x)
	var x1: float = wx.call(r.end.x)
	var z0: float = wz.call(r.position.y)
	var z1: float = wz.call(r.end.y)
	return [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]


## Intervalle `v` moins la réunion des intervalles `nb` (triés, disjoints).
static func _minus(v: Vector2i, nb: Array) -> Array:
	var out := []
	var lo := v.x
	for o: Vector2i in nb:
		if o.y <= lo:
			continue
		if o.x >= v.y:
			break
		if o.x > lo:
			out.append(Vector2i(lo, o.x))
		lo = maxi(lo, o.y)
		if lo >= v.y:
			return out
	if lo < v.y:
		out.append(Vector2i(lo, v.y))
	return out


## Rectangles (cases) qui couvrent l'ensemble `cells` (Vector2i -> true),
## fusion gloutonne : le long de x, puis rangées entières le long de y.
static func _rects(cells: Dictionary) -> Array:
	var keys := cells.keys()
	keys.sort_custom(func(p: Vector2i, q: Vector2i): return p.y < q.y or (p.y == q.y and p.x < q.x))
	var done := {}
	var out := []
	for k: Vector2i in keys:
		if done.has(k):
			continue
		var x1 := k.x
		while cells.has(Vector2i(x1 + 1, k.y)) and not done.has(Vector2i(x1 + 1, k.y)):
			x1 += 1
		var y1 := k.y
		while true:
			var ok := true
			for x in range(k.x, x1 + 1):
				var c := Vector2i(x, y1 + 1)
				if not cells.has(c) or done.has(c):
					ok = false
					break
			if not ok:
				break
			y1 += 1
		for y in range(k.y, y1 + 1):
			for x in range(k.x, x1 + 1):
				done[Vector2i(x, y)] = true
		out.append(Rect2i(k.x, k.y, x1 - k.x + 1, y1 - k.y + 1))
	return out
