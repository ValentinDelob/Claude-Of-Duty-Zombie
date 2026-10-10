class_name MeshMapGeometry
extends RefCounted
## Architecture d'une carte en maillage construite DANS LE JEU à partir de sa
## description (clés rooms, walls, blocks, slabs, stairs, rails du
## layout.json) : même résultat que tools/blender/mesh_map.py, sans Blender.
## Sert aux cartes de l'éditeur (docs/MAP_AUTHORING.md), jouables aussitôt,
## y compris dans le .exe.
##
## Mêmes noms de nœuds que le .glb importé, lus par MeshMapBuilder._setup_nodes :
##   <matériau>__<salle>__<type>        MeshInstance3D (visible)
##   <matériau>__<salle>__<type>__col   StaticBody3D (collision)
## Collisions : pavés (BoxShape3D) pour les murs, blocs et garde-corps,
## prismes convexes pour les dalles et la rampe des escaliers (le joueur n'a
## pas de logique de montée de marche), surfaces (ConcavePolygonShape3D) pour
## les sols et plafonds.
## Escaliers, rampes, garde-corps et sols en pente : visuel en colonnes de
## cubes de 5 cm (CubeColumns, docs/VOXEL_ARCHITECTURE_PLAN.md § 2.3, lot D),
## collisions inchangées.

var _groups: Dictionary = {}   # clé -> {v, n, faces, boxes, convex}
var _kind := "wall"
## Collisions des murs en biais (clé « obliques ») : pavés CollisionBox tournés.
var _col_boxes: Array[CollisionBox] = []
## Caisse et baril posés (types historiques de l'éditeur, bloc « crate » /
## « barrel ») : modèle cubique au lieu du pavé texturé. [salle, modèle, pied, taille].
var _decor: Array = []
const DECOR_MODELS := {"crate": "caisse", "barrel": "baril"}


static func build(layout: Dictionary) -> Node3D:
	var g := MeshMapGeometry.new()
	return g._build(layout)


func _group(mat: String, room: String) -> Dictionary:
	var key := "%s__%s__%s" % [mat, room, _kind]
	if not _groups.has(key):
		_groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "faces": PackedVector3Array(), "boxes": [], "convex": []}
	return _groups[key]


## Triangle tourné vers `n` (Godot : faces avant dans le sens horaire).
## `sn` : normale d'éclairage si elle diffère de la face (murs en escalier).
static func _tri(g: Dictionary, a: Vector3, b: Vector3, c: Vector3, n: Vector3, vis: bool, col: bool, sn := Vector3.ZERO) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	if vis:
		var ln := n if sn == Vector3.ZERO else sn
		g.v.append_array([a, b, c])
		g.n.append_array([ln, ln, ln])
	if col:
		g.faces.append_array([a, b, c])


static func _quad(g: Dictionary, p: Array, n: Vector3, vis := true, col := false, sn := Vector3.ZERO) -> void:
	_tri(g, p[0], p[1], p[2], n, vis, col, sn)
	_tri(g, p[0], p[2], p[3], n, vis, col, sn)


## Boîte orientée : `size` = (longueur x, hauteur y, épaisseur z), lacet autour de y.
func _box(g: Dictionary, center: Vector3, size: Vector3, yaw: float, vis := true, col := true) -> void:
	var ux := Vector3(cos(yaw), 0, -sin(yaw))
	var uz := Vector3(sin(yaw), 0, cos(yaw))
	var h := size * 0.5
	if vis:
		for axis in [[ux, h.x, Vector3.UP, h.y, uz, h.z], [Vector3.UP, h.y, ux, h.x, uz, h.z], [uz, h.z, ux, h.x, Vector3.UP, h.y]]:
			var n: Vector3 = axis[0]
			var a: Vector3 = axis[2] * float(axis[3])
			var b: Vector3 = axis[4] * float(axis[5])
			for s in [1.0, -1.0]:
				var c: Vector3 = center + n * float(axis[1]) * s
				if n == Vector3.UP and s < 0.0:
					# Dessous : sans les parties où un plafond est dans son plan.
					_down_face(g, [c - a - b, c + a - b, c + a + b, c - a + b])
					continue
				_quad(g, [c - a - b, c + a - b, c + a + b, c - a + b], n * s)
	if col:
		g.boxes.append([Transform3D(Basis(ux, Vector3.UP, uz), center), size])


# ------------------------------------------------------------------ plafonds dans le plan d'un dessous (format 20)

## Plafonds des salles (format 20, docs/VOXEL_ARCHITECTURE_PLAN.md § 2.1) :
## hauteur en mm -> [{bb: Rect2, poly}]. Le plafond d'une salle sous une dalle
## EST la face du dessous de cette dalle (plus d'écart de 1 cm) : la face du
## dessous d'une dalle, d'un bloc ou d'un mur dans le plan d'un plafond n'est
## pas dessinée là où ce plafond la couvre (une seule face, pas de
## scintillement ; le plafond garde la texture de plafond de sa salle).
var _covers: Dictionary = {}


func _collect_covers(L: Dictionary) -> void:
	_covers = {}
	for r in L.get("rooms", []):
		if r.get("no_ceiling", false) or r.has("ceiling_slab") or not r.has("ceiling"):
			continue
		var p2 := PackedVector2Array()
		for p in r.outline:
			p2.append(Vector2(float(p[0]), float(p[1])))
		if p2.size() < 3:
			continue
		(_covers.get_or_add(roundi(float(r.ceiling) * 1000.0), []) as Array).append({"bb": _bb2(p2), "poly": p2})


static func _bb2(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


## Face horizontale tournée vers le bas (sommets 3D à la même hauteur, dans
## l'ordre du contour), moins les plafonds dans son plan (_covers).
func _down_face(g: Dictionary, pts: Array) -> void:
	var y := float((pts[0] as Vector3).y)
	var covers: Array = _covers.get(roundi(y * 1000.0), [])
	if covers.is_empty():
		_quad_or_poly(g, pts)
		return
	var p2 := PackedVector2Array()
	for p: Vector3 in pts:
		p2.append(Vector2(p.x, p.z))
	var bb := _bb2(p2)
	var pieces: Array = [p2]
	var cut := false
	for cv in covers:
		if not (cv.bb as Rect2).intersects(bb):
			continue
		cut = true
		var next := []
		for pc in pieces:
			next.append_array(_minus(pc, cv.poly, 0))
		pieces = next
		if pieces.is_empty():
			return
	if not cut:
		_quad_or_poly(g, pts)
		return
	for pc: PackedVector2Array in pieces:
		var idx := Geometry2D.triangulate_polygon(pc)
		for i in range(0, idx.size(), 3):
			_tri(g, Vector3(pc[idx[i]].x, y, pc[idx[i]].y), Vector3(pc[idx[i + 1]].x, y, pc[idx[i + 1]].y),
				Vector3(pc[idx[i + 2]].x, y, pc[idx[i + 2]].y), Vector3.DOWN, true, false)


func _quad_or_poly(g: Dictionary, pts: Array) -> void:
	if pts.size() == 4 and Geometry2D.is_polygon_clockwise(PackedVector2Array([Vector2(pts[0].x, pts[0].z), Vector2(pts[1].x, pts[1].z), Vector2(pts[2].x, pts[2].z)])) \
			== Geometry2D.is_polygon_clockwise(PackedVector2Array([Vector2(pts[0].x, pts[0].z), Vector2(pts[2].x, pts[2].z), Vector2(pts[3].x, pts[3].z)])):
		# Quadrilatère convexe (face d'une boîte) : deux triangles, comme avant.
		_quad(g, pts, Vector3.DOWN)
		return
	var p2 := PackedVector2Array()
	for p: Vector3 in pts:
		p2.append(Vector2(p.x, p.z))
	var idx := Geometry2D.triangulate_polygon(p2)
	for i in range(0, idx.size(), 3):
		_tri(g, pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]], Vector3.DOWN, true, false)


## Contour `a` moins le contour `b` : morceaux sans trou (un trou est évité en
## coupant `a` en deux par une verticale à travers lui, puis chaque moitié).
static func _minus(a: PackedVector2Array, b: PackedVector2Array, depth: int) -> Array:
	var res := Geometry2D.clip_polygons(a, b)
	var hole := -1
	for i in res.size():
		for j in res.size():
			if i != j and Geometry2D.is_point_in_polygon(res[i][0], res[j]) and _area2(res[i]) < _area2(res[j]):
				hole = i
		if hole >= 0:
			break
	if hole < 0 or depth > 8:
		return res.filter(func(p): return _area2(p) > 1e-6)
	var bb := _bb2(a)
	var x := _bb2(res[hole]).get_center().x
	var out := []
	for half in [Rect2(bb.position.x - 1.0, bb.position.y - 1.0, x - bb.position.x + 1.0, bb.size.y + 2.0),
			Rect2(x, bb.position.y - 1.0, bb.end.x - x + 1.0, bb.size.y + 2.0)]:
		var hp := PackedVector2Array([half.position, Vector2(half.end.x, half.position.y), half.end, Vector2(half.position.x, half.end.y)])
		for part in Geometry2D.intersect_polygons(a, hp):
			out.append_array(_minus(part, b, depth + 1))
	return out


static func _area2(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].cross(p[(i + 1) % p.size()])
	return absf(s) * 0.5


## Morceaux pleins d'un mur de `s0` à `s1` (le long du mur) et de `y0` à
## `y1`, percé des ouvertures `cuts` [{t (milieu), w, y0, y1}] : de part et
## d'autre de chaque ouverture, allège dessous et linteau dessus.
## -> [[début, fin, bas, haut]].
static func wall_pieces(s0: float, s1: float, y0: float, y1: float, cuts: Array) -> Array:
	var sorted := cuts.duplicate()
	sorted.sort_custom(func(p, q): return float(p.t) < float(q.t))
	var pieces := []
	var s := s0
	for o in sorted:
		var o0 := float(o.t) - float(o.w) / 2.0
		var o1 := float(o.t) + float(o.w) / 2.0
		if o0 > s:
			pieces.append([s, o0, y0, y1])
		if float(o.y0) > y0:
			pieces.append([o0, o1, y0, float(o.y0)])
		if float(o.y1) < y1:
			pieces.append([o0, o1, float(o.y1), y1])
		s = o1
	pieces.append([s, s1, y0, y1])
	return pieces


## Côté d'un cube de décor (GAME_CONCEPT.md § 4.19) : grille de l'architecture.
const CUBE := 0.05
## Marche des murs en biais, en cubes : 2 (marches de 10 cm, 2 × 2 cubes de
## 5 cm, sommets sur la grille de 5 cm). Avec 1 (5 cm), le contour noir trace
## un trait tous les 5 cm et le mur vu de biais à 4-6 m fait du moiré, pour
## deux fois plus de triangles (pilote, docs/VOXEL_ARCHITECTURE_PLAN.md § 4).
static var step_grain := 2
## Poids de la normale du mur dans l'éclairage des faces en escalier : les
## faces restent des cubes, mais les deux orientations (±x, ±z) d'un mur en
## biais s'éclairent moins différemment (moins de rayures et de moiré au
## loin). 0 : éclairage de la face seule.
static var step_shade := 2.0


## Murs en escalier de cubes (lot B, docs/VOXEL_ARCHITECTURE_PLAN.md § 2.2) :
## murs en biais, raccords d'angle, piliers tournés, murs courbes, cours
## tournées et cadres des ouvertures en biais sont rastérisés ENSEMBLE (union
## des cellules) puis leurs faces visibles créées d'un bloc (_emit_cols) : un
## mur courbe est UN contour en escalier régulier (pas un escalier par
## segment), un raccord ne double aucune face, deux murs qui se croisent n'ont
## pas de face cachée. Grille au sol de 5 cm (cellule (i, j) : coin en
## (i, j) × CUBE dans le monde), rangée j (le long de x) -> étendues triées
## et disjointes [i0, i1, [[y0, y1, propriétaire], ...]] (cellules i0 à i1
## comprises, pleines sur les mêmes hauteurs) : le coût suit le nombre
## d'étendues, pas de cellules.
var _rows: Dictionary = {}
## Propriétaires des cellules : {gn, gm (groupes des faces tournées vers +u et
## -u), u (normale du mur, Vector2 en x, z), arc (centre d'un mur courbe, ou
## null), pri (0 mur, 1 raccord : le mur l'emporte sur une cellule commune),
## gni (indice de gn), sides (côtés ±x, ±z d'un mur droit : _side_of)}.
var _owners: Array = []
## Groupes des faces en escalier (indices des clés de fusion des faces).
var _gids: Array = []
## Côtés d'une colonne : +x, -x, +z, -z.
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _owner(gn: Dictionary, gm: Dictionary, u: Vector2, arc: Variant = null, pri := 0) -> int:
	var ow := {"gn": gn, "gm": gm, "u": u, "arc": arc, "pri": pri, "gni": _gid(gn), "sides": []}
	for dv: Vector2i in DIRS:
		ow.sides.append(_side_of(ow, Vector3(dv.x, 0, dv.y), u))
	_owners.append(ow)
	return _owners.size() - 1


## Côté `n` d'une colonne de normale de mur `u` : [groupe, indice du groupe,
## normale d'éclairage, clé de la normale].
func _side_of(ow: Dictionary, n: Vector3, u: Vector2) -> Array:
	var u3 := Vector3(u.x, 0, u.y)
	var g: Dictionary = ow.gm if n.dot(u3) < -1e-4 else ow.gn
	var sn := _shade_n(n, u3)
	return [g, _gid(g), sn, Vector3i(roundi(sn.x * 1e4), roundi(sn.y * 1e4), roundi(sn.z * 1e4))]


func _gid(g: Dictionary) -> int:
	for i in _gids.size():
		if is_same(_gids[i], g):
			return i
	_gids.append(g)
	return _gids.size() - 1


## Morceau de mur en biais [s0, s1] (le long de `d` depuis `a`) × [y0, y1],
## épaisseur `t`, rendu en ESCALIER de cubes alignés sur la grille du monde :
## une cellule de step_grain × 5 cm de côté au sol est pleine si son centre
## tombe dans le pavé ; seules les faces visibles sont créées (dessus,
## dessous, côtés que la colonne voisine ne couvre pas), fusionnées en
## rectangles. Face tournée vers la normale du mur (+u) : `gn`, vers -u : `gm`.
## Morceau seul (tests, mesures) : _build rastérise tous les murs ensemble.
## -> nombre de rangées de marches (mesure).
func _stepped_piece(gn: Dictionary, gm: Dictionary, a: Vector3, d: Vector3, s0: float, s1: float, t: float, y0: float, y1: float) -> int:
	var rows := _raster_piece(_owner(gn, gm, Vector2(-d.z, d.x)), Vector2(a.x, a.z), Vector2(d.x, d.z), s0, s1, t, y0, y1)
	_emit_cols()
	return rows


## Mur axial (le long de x ou de z) : marche d'un cube (ses faces tombent sur
## la grille de 5 cm, rien à mettre en escalier).
static func _axial(d: Vector2) -> bool:
	return absf(d.x) < 1e-6 or absf(d.y) < 1e-6


## Cellules du pavé [s0, s1] × [-t/2, t/2] (repère du mur : `a`, direction
## `d`, normale u = (-d.y, d.x)) de y0 à y1, au propriétaire `o` : cellules
## de step_grain cubes (un cube pour un mur axial) dont le centre est dans le
## pavé, par rangées le long de z (pavé convexe : un intervalle par rangée).
## -> nombre de rangées de marches.
func _raster_piece(o: int, a: Vector2, d: Vector2, s0: float, s1: float, t: float, y0: float, y1: float) -> int:
	var u := Vector2(-d.y, d.x)
	var g := 1 if _axial(d) else step_grain
	var c := CUBE * g
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in [s0, s1]:
		for k in [-t / 2.0, t / 2.0]:
			var p: Vector2 = a + d * float(s) + u * float(k)
			lo = lo.min(p)
			hi = hi.max(p)
	var rows := 0
	var iv := [y0, y1, o]
	for j in range(floori(lo.y / c), ceili(hi.y / c) + 1):
		var r := (j + 0.5) * c
		var q := Vector2(-INF, INF)
		q = _clip_1d(q, d.x, d.y * (r - a.y) - d.x * a.x, s0, s1)
		q = _clip_1d(q, u.x, u.y * (r - a.y) - u.x * a.x, -t / 2.0, t / 2.0)
		if q.x > q.y:
			continue
		var i0 := ceili(q.x / c - 0.5 - 1e-6)
		var i1 := floori(q.y / c - 0.5 + 1e-6)
		if i0 > i1:
			continue
		rows += 1
		_add_run(j, i0, i1, g, iv)
	return rows


## Cellules (i0..i1, j) de `g` cubes de côté pleines selon `iv` [y0, y1, propriétaire].
func _add_run(j: int, i0: int, i1: int, g: int, iv: Array) -> void:
	for dj in g:
		var jj := j * g + dj
		_rows[jj] = _insert(_rows.get(jj, []), i0 * g, i1 * g + g - 1, iv)


## Étendues d'une rangée avec les cellules [i0, i1] pleines selon `iv` en plus.
static func _insert(spans: Array, i0: int, i1: int, iv: Array) -> Array:
	var out := []
	var cur := i0
	for sp: Array in spans:
		var a: int = sp[0]
		var b: int = sp[1]
		if b < cur or a > i1:
			if a > i1 and cur <= i1:
				out.append([cur, i1, [iv]])
				cur = i1 + 1
			out.append(sp)
			continue
		if a > cur:
			out.append([cur, a - 1, [iv]])
		if a < cur:
			out.append([a, cur - 1, sp[2]])
		var hi := mini(b, i1)
		out.append([maxi(a, cur), hi, (sp[2] as Array) + [iv]])
		if b > i1:
			out.append([i1 + 1, b, sp[2]])
		cur = hi + 1
	if cur <= i1:
		out.append([cur, i1, [iv]])
	return out


## Cadre cubique d'une ouverture dans un mur en biais (porte, fenêtre, porte à
## zombies, passage) : le jambage `sj` (le long du mur) est un plan en biais,
## l'escalier du mur rentre par endroits jusqu'à 7 cm derrière lui et laisse
## un jour entre l'objet tourné (porte, barricade) et les marches. Les
## cellules à cheval sur ce plan, côté ouverture (`side` : +1 si l'ouverture
## est vers les s croissants), dans l'épaisseur du mur, sont pleines sur toute
## la hauteur du mur : le jambage en cubes couvre toujours le plan vrai
## (il déborde d'au plus une marche dans l'ouverture).
func _raster_jamb(o: int, a: Vector2, d: Vector2, sj: float, side: float, t: float, y0: float, y1: float) -> void:
	var u := Vector2(-d.y, d.x)
	var c := CUBE * step_grain
	# Demi-étendue d'une cellule le long du mur.
	var half := (absf(d.x) + absf(d.y)) * c * 0.5
	var p0 := a + d * sj - u * (t / 2.0)
	var p1 := a + d * sj + u * (t / 2.0)
	var lo := p0.min(p1) - Vector2(c, c)
	var hi := p0.max(p1) + Vector2(c, c)
	var iv := [y0, y1, o]
	for j in range(floori(lo.y / c), ceili(hi.y / c) + 1):
		for i in range(floori(lo.x / c), ceili(hi.x / c) + 1):
			var p := Vector2((i + 0.5) * c, (j + 0.5) * c) - a
			var ds := p.dot(d) - sj
			if absf(p.dot(u)) > t / 2.0 + 1e-6 or ds * side <= 1e-6 or absf(ds) >= half - 1e-6:
				continue
			_add_run(j, i, i, step_grain, iv)


## Faces visibles de toutes les étendues, fusionnées : dessus et dessous en
## rectangles (même hauteur, même groupe), côtés en bandes le long de leur
## plan (même hauteur, même groupe, même normale d'éclairage). Vide les
## rangées et les propriétaires.
func _emit_cols() -> void:
	for j: int in _rows:
		# Intervalles fusionnés ; étendues voisines devenues pareilles réunies.
		var merged := []
		for sp: Array in _rows[j]:
			if (sp[2] as Array).size() > 1:
				sp[2] = _merge_iv(sp[2])
			if not merged.is_empty() and int(merged[-1][1]) == int(sp[0]) - 1 and merged[-1][2] == sp[2]:
				merged[-1][1] = sp[1]
			else:
				merged.append(sp)
		_rows[j] = merged
	var tops := {}    # Vector2i(hauteur en mm, groupe) -> [bandes codées (_KEY)]
	var bots := {}
	var sides := {}   # [côté, plan, bas, haut (mm), groupe, normale] -> {n, plane, ya, yb, g, sn, along: [Vector2i]}
	for j: int in _rows:
		var spans: Array = _rows[j]
		var up: Array = _rows.get(j + 1, [])
		var dn: Array = _rows.get(j - 1, [])
		for k in spans.size():
			var sp: Array = spans[k]
			var i0: int = sp[0]
			var i1: int = sp[1]
			var list: Array = sp[2]
			var band := _band_key(j, i0, i1)
			for iv: Array in list:
				var gi: int = _owners[iv[2]].gni
				(tops.get_or_add(Vector2i(roundi(float(iv[1]) * 1000.0), gi), []) as Array).append(band)
				(bots.get_or_add(Vector2i(roundi(float(iv[0]) * 1000.0), gi), []) as Array).append(band)
			# ±x : les cellules voisines au bout de l'étendue (même rangée).
			var left: Array = spans[k - 1][2] if k > 0 and int(spans[k - 1][1]) == i0 - 1 else []
			var right: Array = spans[k + 1][2] if k + 1 < spans.size() and int(spans[k + 1][0]) == i1 + 1 else []
			_faces(sides, list, left, 1, i0, i0, i0, j)
			_faces(sides, list, right, 0, i1 + 1, i1, i1, j)
			# ±z : morceaux de [i0, i1] face aux étendues des rangées voisines.
			for e in [[up, 2, j + 1], [dn, 3, j]]:
				var cur := i0
				for nb: Array in e[0]:
					var a: int = nb[0]
					var b: int = nb[1]
					if b < cur:
						continue
					if a > i1:
						break
					if a > cur:
						_faces(sides, list, [], e[1], e[2], cur, a - 1, j)
					var hi := mini(b, i1)
					_faces(sides, list, nb[2], e[1], e[2], maxi(a, cur), hi, j)
					cur = hi + 1
				if cur <= i1:
					_faces(sides, list, [], e[1], e[2], cur, i1, j)
	for k: Vector2i in tops:
		var g: Dictionary = _gids[k.y]
		for r: Rect2i in _rects(tops[k]):
			_quad(g, _rect_pts(r, k.x / 1000.0), Vector3.UP)
	for k: Vector2i in bots:
		var g: Dictionary = _gids[k.y]
		for r: Rect2i in _rects(bots[k]):
			# Dessous : sans les parties où un plafond est dans son plan (format 20).
			_down_face(g, _rect_pts(r, k.x / 1000.0))
	for e: Dictionary in sides.values():
		var n: Vector3 = e.n
		var p := float(e.plane) * CUBE
		var ya := float(e.ya)
		var yb := float(e.yb)
		for run: Vector2i in _merge_runs(e.along):
			var q0 := run.x * CUBE
			var q1 := (run.y + 1) * CUBE
			var pts := [Vector3(p, ya, q0), Vector3(p, ya, q1), Vector3(p, yb, q1), Vector3(p, yb, q0)] if n.x != 0.0 \
				else [Vector3(q0, ya, p), Vector3(q1, ya, p), Vector3(q1, yb, p), Vector3(q0, yb, p)]
			_quad(e.g, pts, n, true, false, e.sn)
	_rows = {}
	_owners = []


## Faces du côté `di` (DIRS) des cellules x0..x1 de la rangée j (côtés ±x :
## une seule cellule, x0 = x1) pleines selon `list`, là où les cellules
## voisines (`nb`, leurs intervalles) ne les couvrent pas ; `plane` : plan de
## la face (en cubes). Mur courbe : une normale d'éclairage par marche.
func _faces(sides: Dictionary, list: Array, nb: Array, di: int, plane: int, x0: int, x1: int, j: int) -> void:
	for iv: Array in list:
		var y0 := float(iv[0])
		var y1 := float(iv[1])
		var segs: Array
		if nb.is_empty():
			segs = [Vector2(y0, y1)]
		elif nb.size() == 1 and float(nb[0][0]) <= y0 + 1e-4 and float(nb[0][1]) >= y1 - 1e-4:
			continue   # couvert par la cellule voisine (cas courant)
		else:
			segs = _iv_minus(y0, y1, nb)
			if segs.is_empty():
				continue
		var ow: Dictionary = _owners[iv[2]]
		var parts := [[x0, x1, ow.sides[di]]]
		if ow.arc != null:
			parts = []
			var dv: Vector2i = DIRS[di]
			for m in range(floori(float(x0) / step_grain), floori(float(x1) / step_grain) + 1):
				var a := maxi(x0, m * step_grain)
				parts.append([a, mini(x1, m * step_grain + step_grain - 1), _side_of(ow, Vector3(dv.x, 0, dv.y), _cell_u(ow, Vector2i(a, j)))])
		for pt: Array in parts:
			var sd: Array = pt[2]
			var along := Vector2i(j, j) if di < 2 else Vector2i(pt[0], pt[1])
			for sg: Vector2 in segs:
				var sk := [di, plane, roundi(sg.x * 1000.0), roundi(sg.y * 1000.0), sd[1], sd[3]]
				var e: Variant = sides.get(sk)
				if e == null:
					var dv: Vector2i = DIRS[di]
					e = {"n": Vector3(dv.x, 0, dv.y), "plane": plane, "ya": sg.x, "yb": sg.y, "g": sd[0], "sn": sd[2], "along": []}
					sides[sk] = e
				(e.along as Array).append(along)


## Normale du mur pour une cellule (5 cm) d'un mur courbe : la normale du vrai
## arc au milieu de la marche (éclairage régulier le long de la courbe), du
## même côté que celle du segment.
func _cell_u(ow: Dictionary, key: Vector2i) -> Vector2:
	var c := CUBE * step_grain
	var p := Vector2((floori(float(key.x) / step_grain) + 0.5) * c, (floori(float(key.y) / step_grain) + 0.5) * c)
	var r: Vector2 = p - (ow.arc as Vector2)
	if r.length() < 1e-6:
		return ow.u
	r = r.normalized()
	return r if r.dot(ow.u) >= 0.0 else -r


## Intervalles [y0, y1, propriétaire] triés et fusionnés (ceux qui se touchent
## ou se chevauchent) ; le mur l'emporte sur un raccord (pri).
func _merge_iv(list: Array) -> Array:
	var sorted := list.duplicate()
	sorted.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	var out := []
	for iv: Array in sorted:
		if not out.is_empty() and float(iv[0]) <= float(out[-1][1]) + 1e-4:
			out[-1][1] = maxf(float(out[-1][1]), float(iv[1]))
			if int(_owners[iv[2]].pri) < int(_owners[out[-1][2]].pri):
				out[-1][2] = iv[2]
		else:
			out.append(iv.duplicate())
	return out


## Parties de [y0, y1] hors des intervalles `cover` (triés, disjoints) : [Vector2].
static func _iv_minus(y0: float, y1: float, cover: Array) -> Array:
	var out := []
	var y := y0
	for c: Array in cover:
		if float(c[1]) <= y + 1e-4:
			continue
		if float(c[0]) >= y1 - 1e-4:
			break
		if float(c[0]) > y + 1e-4:
			out.append(Vector2(y, float(c[0])))
		y = maxf(y, float(c[1]))
		if y >= y1 - 1e-4:
			return out
	if y1 > y + 1e-4:
		out.append(Vector2(y, y1))
	return out


## Codage d'une bande (rangée j, cellules i0 à i1) en un entier (tri rapide) :
## champs de 20 bits, cellules à ±2^19 (± 26 km).
const _KEY_OFF := 1 << 19
const _KEY_BITS := 1 << 20


static func _band_key(j: int, i0: int, i1: int) -> int:
	return ((j + _KEY_OFF) * _KEY_BITS + (i0 + _KEY_OFF)) * _KEY_BITS + (i1 + _KEY_OFF)


## Bandes (_band_key) -> rectangles (Rect2i, en cellules) : bandes
## identiques de rangées voisines réunies.
@warning_ignore("integer_division")
static func _rects(bands: Array) -> Array:
	var keys := PackedInt64Array(bands)
	keys.sort()
	# Bandes voisines d'une même rangée réunies : [j, i0, i1].
	var runs := []
	for key in keys:
		var i1 := key % _KEY_BITS - _KEY_OFF
		var i0 := (key / _KEY_BITS) % _KEY_BITS - _KEY_OFF
		var j := key / (_KEY_BITS * _KEY_BITS) - _KEY_OFF
		if not runs.is_empty() and runs[-1][0] == j and runs[-1][2] == i0 - 1:
			runs[-1][2] = i1
		else:
			runs.append([j, i0, i1])
	var out := []
	var open := {}   # Vector2i(i0, i1) -> Rect2i en cours
	for rw: Array in runs:
		var j: int = rw[0]
		var i0: int = rw[1]
		var i1: int = rw[2]
		var rn := Vector2i(i0, i1)
		var r: Variant = open.get(rn)
		if r != null and (r as Rect2i).end.y == j:
			open[rn] = (r as Rect2i).grow_side(SIDE_BOTTOM, 1)
		else:
			if r != null:
				out.append(r)
			open[rn] = Rect2i(i0, j, i1 - i0 + 1, 1)
	out.append_array(open.values())
	return out


## Coins d'un rectangle de cellules (Rect2i) à la hauteur y, dans l'ordre du contour.
static func _rect_pts(r: Rect2i, y: float) -> Array:
	var x0 := r.position.x * CUBE
	var x1 := r.end.x * CUBE
	var z0 := r.position.y * CUBE
	var z1 := r.end.y * CUBE
	return [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]


## Morceaux [Vector2i(début, fin)] -> suites consécutives réunies.
static func _merge_runs(list: Array) -> Array:
	list.sort()
	var out := []
	for v: Vector2i in list:
		if not out.is_empty() and (out[-1] as Vector2i).y >= v.x - 1:
			out[-1] = Vector2i((out[-1] as Vector2i).x, maxi((out[-1] as Vector2i).y, v.y))
		else:
			out.append(v)
	return out


## Normale d'éclairage d'une face verticale en escalier : la face penchée
## vers la normale du mur du même côté (step_shade ; 0 : la face seule).
static func _shade_n(n: Vector3, u: Vector3) -> Vector3:
	if step_shade <= 0.0:
		return Vector3.ZERO
	var side := u if n.dot(u) >= 0.0 else -u
	return (n + side * step_shade).normalized()


## Intervalle de q (borné par `iv`) où  k·q + c  est dans [lo, hi].
static func _clip_1d(iv: Vector2, k: float, c: float, lo: float, hi: float) -> Vector2:
	if absf(k) < 1e-9:
		return iv if (c >= lo - 1e-9 and c <= hi + 1e-9) else Vector2(1, 0)
	var q0 := (lo - c) / k
	var q1 := (hi - c) / k
	return Vector2(maxf(iv.x, minf(q0, q1)), minf(iv.y, maxf(q0, q1)))



## Face plane d'un contour [[x, z]...] à la hauteur height_fn(x, z).
static func _polygon(g: Dictionary, outline: Array, height_fn: Callable, up: bool, vis: bool, col: bool) -> void:
	var p2 := PackedVector2Array()
	for p in outline:
		p2.append(Vector2(float(p[0]), float(p[1])))
	var idx := Geometry2D.triangulate_polygon(p2)
	var n := Vector3.UP if up else Vector3.DOWN
	for i in range(0, idx.size(), 3):
		var pts := []
		for j in 3:
			var q := p2[idx[i + j]]
			pts.append(Vector3(q.x, float(height_fn.call(q.x, q.y)), q.y))
		_tri(g, pts[0], pts[1], pts[2], n, vis, col)


## Dalle pleine (dessus à `top`, épaisseur `th`) : planchers de niveau, balcons.
func _slab(g: Dictionary, outline: Array, top: float, th: float) -> void:
	var p2 := PackedVector2Array()
	for p in outline:
		p2.append(Vector2(float(p[0]), float(p[1])))
	_polygon(g, outline, func(_x, _z): return top, true, true, false)
	# Dessous : sans les parties où le plafond d'une salle est dans son plan
	# (format 20 : ce plafond est la face du dessous de la dalle).
	var under := []
	for q in p2:
		under.append(Vector3(q.x, top - th, q.y))
	_down_face(g, under)
	var ccw := 0.0
	for i in p2.size():
		ccw += p2[i].cross(p2[(i + 1) % p2.size()])
	for i in p2.size():
		var a := p2[i]
		var b := p2[(i + 1) % p2.size()]
		var d := (b - a).normalized()
		# Normale sortante dans le plan (x, z).
		var out := Vector2(d.y, -d.x) if ccw > 0.0 else Vector2(-d.y, d.x)
		var n := Vector3(out.x, 0, out.y)
		_quad(g, [Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, top - th, b.y), Vector3(a.x, top - th, a.y)], n)
	_slab_col(g, outline, top, th)


## Collision d'une dalle : prisme convexe (contours rectangulaires de
## l'éditeur), sinon surfaces du dessus et du dessous.
func _slab_col(g: Dictionary, outline: Array, top: float, th: float) -> void:
	var p2 := PackedVector2Array()
	for p in outline:
		p2.append(Vector2(float(p[0]), float(p[1])))
	var pts := PackedVector3Array()
	for q in p2:
		pts.append(Vector3(q.x, top, q.y))
		pts.append(Vector3(q.x, top - th, q.y))
	if Geometry2D.convex_hull(p2).size() == p2.size() + 1:
		g.convex.append(pts)
	else:
		_polygon(g, outline, func(_x, _z): return top, true, false, true)
		_polygon(g, outline, func(_x, _z): return top - th, false, false, true)


static func _floor_height(r: Dictionary) -> Callable:
	if r.has("slope"):
		var s: Array = r.slope
		var p1 := Vector3(s[0][0], s[0][1], s[0][2])
		var p2 := Vector3(s[1][0], s[1][1], s[1][2])
		var p3 := Vector3(s[2][0], s[2][1], s[2][2])
		var nrm := (p2 - p1).cross(p3 - p1)
		return func(x: float, z: float) -> float: return p1.y - (nrm.x * (x - p1.x) + nrm.z * (z - p1.z)) / nrm.y if absf(nrm.y) > 1e-6 else p1.y
	var y := float(r.get("floor", 0.0))
	return func(_x, _z): return y


func _build(L: Dictionary) -> Node3D:
	_collect_covers(L)
	# Salles : sols et plafonds.
	for r in L.get("rooms", []):
		var rid := String(r.id)
		_kind = "floor"
		var g := _group(String(r.get("floor_mat", "floor")), rid)
		if r.has("floor_slab"):
			_slab(g, r.outline, float(r.get("floor", 0.0)), float(r.floor_slab))
		elif r.has("slope"):
			# Pente : terrasses de 5 cm (visuel), plan incliné (collision).
			_terraces(g, r.outline, _floor_height(r))
			_polygon(g, r.outline, _floor_height(r), true, false, true)
		else:
			_polygon(g, r.outline, _floor_height(r), true, true, true)
		if not r.get("no_ceiling", false):
			_kind = "ceil"
			var gc := _group(String(r.get("ceiling_mat", "ceiling")), rid)
			var ce := float(r.ceiling)
			if r.has("ceiling_slab"):
				_slab(gc, r.outline, ce + float(r.ceiling_slab), float(r.ceiling_slab))
			else:
				_polygon(gc, r.outline, func(_x, _z): return ce, false, true, true)
	# Blocs (murs, allèges, linteaux, décor).
	for bl in L.get("blocks", []):
		_kind = "barrier" if bl.get("barrier", false) else "block"
		var b: Array = bl.box
		var lo := Vector3(b[0], b[1], b[2])
		var hi := Vector3(b[3], b[4], b[5])
		var mat := String(bl.get("mat", "wood"))
		# Caisse et baril de l'éditeur : collision du bloc (inchangée), visuel
		# cubique (decor_model) posé au pied du bloc.
		var model := String(DECOR_MODELS.get(mat, ""))
		if model != "":
			_box(_group(mat, String(bl.get("room", "x"))), (lo + hi) * 0.5, hi - lo, 0.0, false, not bl.get("nocollide", false))
			_decor.append([String(bl.get("room", "x")), model, Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5), hi - lo])
			continue
		_box(_group(mat, String(bl.get("room", "x"))), (lo + hi) * 0.5, hi - lo, 0.0, true, not bl.get("nocollide", false))
	# Murs (chemins avec ouvertures ; cours des fenêtres).
	_kind = "wall"
	for w in L.get("walls", []):
		var pts: Array = w.path.duplicate()
		if w.get("closed", false):
			pts.append(w.path[0])
		var t := float(w.get("thick", 0.3))
		var y0 := float(w.y0)
		var y1 := float(w.y1)
		var g := _group(String(w.get("mat", "wall")), String(w.get("room", "x")))
		for si in pts.size() - 1:
			var a := Vector3(pts[si][0], 0, pts[si][1])
			var bb := Vector3(pts[si + 1][0], 0, pts[si + 1][1])
			var length := a.distance_to(bb)
			if length < 0.001:
				continue
			var d := (bb - a) / length
			var yaw := atan2(-d.z, d.x)
			var cuts: Array = w.get("openings", []).filter(func(o): return int(o.seg) == si)
			# Tronçon tourné (cour d'une fenêtre sur un mur en biais) : visuel en
			# escalier de cubes avec les murs en biais (_emit_cols), collision :
			# le pavé tourné lisse (inchangée).
			var d2 := Vector2(d.x, d.z)
			var ow := -1 if _axial(d2) else _owner(g, g, Vector2(-d.z, d.x))
			for pc in wall_pieces(-t / 2.0, length + t / 2.0, y0, y1, cuts):
				if pc[1] - pc[0] < 0.001 or pc[3] - pc[2] < 0.001:
					continue
				var c: Vector3 = a + d * ((pc[0] + pc[1]) * 0.5) + Vector3.UP * ((pc[2] + pc[3]) * 0.5)
				_box(g, c, Vector3(pc[1] - pc[0], pc[3] - pc[2], t), yaw, ow < 0)
				if ow >= 0:
					_raster_piece(ow, Vector2(a.x, a.z), d2, pc[0], pc[1], t, pc[2], pc[3])
	# Murs en biais (cartes de l'éditeur) : vrais murs droits obliques, une
	# texture par face (celle de la pièce de chaque côté), collisions en
	# pavés CollisionBox tournés comme le mur (balles, grenades, joueurs et
	# zombies suivent le vrai mur ; le navmesh est cuit dessus). Type
	# « biais » : le rendu pose le motif le long du mur (MeshMapBuilder).
	_kind = "biais"
	for w in L.get("obliques", []):
		var a := Vector3(float(w.a[0]), 0, float(w.a[1]))
		var bb := Vector3(float(w.b[0]), 0, float(w.b[1]))
		var length := a.distance_to(bb)
		if length < 0.001:
			continue
		var d := (bb - a) / length
		var yaw := atan2(-d.z, d.x)
		var t := float(w.get("thick", 0.5))
		var y0 := float(w.y0)
		var y1 := float(w.y1)
		var mat_n := String(w.get("mat_n", "wall"))
		var gn := _group(mat_n, String(w.get("room", "x")))
		var gm := _group(String(w.get("mat_m", mat_n)), String(w.get("room", "x")))
		var a2 := Vector2(a.x, a.z)
		var d2 := Vector2(d.x, d.z)
		# Mur courbe (« arc » : centre de l'arc) : normale d'éclairage du vrai
		# arc ; raccord d'angle : cède ses cellules communes au mur.
		var arc: Variant = Vector2(float(w.arc[0]), float(w.arc[1])) if w.get("arc") is Array else null
		var ow := _owner(gn, gm, Vector2(-d.z, d.x), arc, 1 if w.get("joint", false) else 0)
		for pc in wall_pieces(0.0, length, y0, y1, w.get("openings", [])):
			if pc[1] - pc[0] < 0.001 or pc[3] - pc[2] < 0.001:
				continue
			var c: Vector3 = a + d * ((pc[0] + pc[1]) * 0.5) + Vector3.UP * ((pc[2] + pc[3]) * 0.5)
			var size := Vector3(pc[1] - pc[0], pc[3] - pc[2], t)
			# Visuel en escalier de cubes (marches de step_grain cubes, tous les
			# murs ensemble : _emit_cols) ; collision : le pavé tourné lisse
			# (écart ≤ une demi-diagonale de marche, 7 cm ;
			# docs/VOXEL_ARCHITECTURE_PLAN.md § 2.2).
			_raster_piece(ow, a2, d2, pc[0], pc[1], t, pc[2], pc[3])
			var cb := CollisionBox.make(c, size, yaw, false, mat_n)
			cb.name = "Biais_%d" % _col_boxes.size()
			_col_boxes.append(cb)
		# Cadres cubiques des ouvertures (jambages à l'intérieur du mur).
		if not _axial(d2):
			for o in w.get("openings", []):
				for e in [[float(o.t) - float(o.w) / 2.0, 1.0], [float(o.t) + float(o.w) / 2.0, -1.0]]:
					if e[0] > 0.001 and e[0] < length - 0.001:
						_raster_jamb(ow, a2, d2, e[0], e[1], t, y0, y1)
	# Faces de tous les murs en escalier (murs en biais, cours tournées).
	_emit_cols()
	# Dalles (balcons, mezzanines).
	_kind = "slab"
	for sl in L.get("slabs", []):
		_slab(_group(String(sl.get("mat", "wood")), String(sl.room)), sl.outline, float(sl.y), float(sl.get("thick", 0.25)))
	# Escaliers : marches en colonnes de cubes (StairGen : hauteur et giron
	# en cubes entiers), collisions inchangées (rampe pleine sous chaque
	# volée, paliers, panneaux). Types (palier, en L, en U, colimaçon,
	# rampe...) et options (garde-corps, côtés fermés, nombre de marches,
	# sortie sur le côté) : voir _stair.
	for st in L.get("stairs", []):
		_kind = "stair"
		_stair(st)
	# Garde-corps : main courante et lisse de 2 × 2 cubes, barreaux d'un
	# cube tous les 6 cubes (CubeColumns) ; collision : un pavé par tronçon.
	_kind = "rail"
	for rl in L.get("rails", []):
		var pts: Array = rl.path
		var h := float(rl.get("h", 1.0))
		var y := float(rl.y)
		var g := _group(String(rl.get("mat", "dark_wood")), String(rl.room))
		var vox := CubeColumns.new()
		for i in pts.size() - 1:
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var bb := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			_rail_cells(vox, a, bb, func(_t: float) -> float: return y, h)
			var seg := Vector3(bb.x - a.x, 0, bb.y - a.y)
			var d := seg.normalized()
			var c := Vector3(a.x, 0, a.y) + seg * 0.5
			_box(g, Vector3(c.x, y + h / 2.0, c.z), Vector3(seg.length(), h, 0.1), atan2(-d.z, d.x), false, true)
		vox.emit(self, g)
	return _nodes()


## Garde-corps en cubes le long de a -> b (CubeColumns `vox`) : main courante
## de 2 × 2 cubes (dessus à `h` au-dessus de la surface), lisse de 2 × 2 cubes
## à + 0,1 m, barreaux d'un cube tous les 6 cubes (30 cm). `surf(t)` : surface
## (m) à t m de a ; sur une volée, en escalier (StairGen.step_top) : la main
## courante suit les marches, un tronçon par marche, relié au précédent.
func _rail_cells(vox: CubeColumns, a: Vector2, b: Vector2, surf: Callable, h: float) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var w := RAIL_CUBES * CUBE
	vox.strip(a, b, w, w * 0.5, func(t: float) -> Array:
		var sf: float = surf.call(t)
		var lo := minf(sf, float(surf.call(maxf(t - CUBE, 0.0))))
		return [Vector2(lo + h - w, sf + h), Vector2(lo + 0.1, sf + 0.1 + w)])
	var d := (b - a) / len
	var ts := []
	var t := 0.0
	while t <= len + 0.001:
		ts.append(minf(t, len))
		t += BALUSTER_GAP
	if len - float(ts[-1]) > BALUSTER_GAP * 0.25:
		ts.append(len)
	for tb: float in ts:
		var sf: float = surf.call(tb)
		vox.add(vox.cell_of(a + d * tb + CubeColumns.NUDGE), sf + 0.1 + w, sf + h - w)


## Garde-corps : main courante et lisse de 2 cubes de côté, barreaux d'un
## cube tous les 6 cubes (docs/VOXEL_ARCHITECTURE_PLAN.md § 2.3).
const RAIL_CUBES := 2
const BALUSTER_GAP := 0.3
## Côté du noyau carré du colimaçon (10 × 10 cubes).
const CORE := 0.5
## Épaisseur des marches du colimaçon (on passe dessous).
const SPIRAL_STEP_T := 0.2


## Escalier d'un type (StairGen.plan) en colonnes de cubes (CubeColumns) :
## volées en marches de 3 ou 4 cubes de haut et d'au moins 5 cubes de giron
## (rampe : marches d'un cube), paliers pleins, noyau d'un U en marches,
## colimaçon à marches carrées et noyau carré, garde-corps et limons en
## escalier. Grille de 5 cm pour un escalier sur les axes ; 10 cm (marche
## des murs en biais, step_grain) pour un escalier tourné et le colimaçon.
## Collisions inchangées : prisme plein en pente sous chaque volée, dalles à
## fleur, noyau, secteurs du colimaçon, panneaux des bords.
func _stair(st: Dictionary) -> void:
	var pl := StairGen.plan(st)
	var room := String(st.get("room", "x"))
	var g := _group(String(st.get("mat", "wood")), room)
	var y0 := float(pl.y0)
	var u: Vector2 = pl.u
	var spiral := not (pl.spiral as Dictionary).is_empty()
	var axial := not spiral and (absf(u.x) < 1e-4 or absf(u.y) < 1e-4)
	var o := Vector2.ZERO
	if spiral:
		# Noyau carré de 10 × 10 cubes : sur des cases entières.
		var sc: Vector2 = pl.spiral.c
		o = Vector2(snappedf(sc.x, CUBE), snappedf(sc.y, CUBE)) - Vector2.ONE * (CORE * 0.5)
	var vox := CubeColumns.new(CUBE * (1 if axial else step_grain), o)
	vox.floor_level = CubeColumns.cubes(y0)
	# Pièces minces (limons, noyau du U) : toujours au cube de 5 cm.
	var thin := vox if axial else CubeColumns.new()
	thin.floor_level = vox.floor_level
	var r2: Vector2 = pl.right
	var lean := [] if (axial or spiral) else [Vector3(u.x, 0, u.y), Vector3(-u.x, 0, -u.y), Vector3(r2.x, 0, r2.y), Vector3(-r2.x, 0, -r2.y)]
	for f in pl.flights:
		var a: Vector3 = f.a
		var b: Vector3 = f.b
		var w := float(f.w)
		var base := float(f.base)
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var len := a2.distance_to(b2)
		if len > 0.001 and axial:
			# Sur les axes : un pavé par marche (giron [i·M/n, (i+1)·M/n[ cubes).
			var d2 := (b2 - a2) / len
			var nrm := Vector2(-d2.y, d2.x) * (w * 0.5)
			var n := int(f.n)
			var M := maxi(1, roundi(len / CUBE))
			var N := roundi(absf(b.y - a.y) / CUBE)
			for i in n:
				@warning_ignore("integer_division")
				var p0 := a2 + d2 * (len * float((i * M) / n) / M)
				@warning_ignore("integer_division")
				var p1 := a2 + d2 * (len * float(((i + 1) * M) / n) / M)
				var top := b.y if N <= 0 else a.y + (b.y - a.y) * float(StairGen.rise_at(N, n, i)) / N
				vox.add_rect(Rect2(p0 - nrm, Vector2.ZERO).expand(p0 + nrm).expand(p1 - nrm).expand(p1 + nrm), base, top)
		elif len > 0.001:
			var d2 := (b2 - a2) / len
			var nrm := Vector2(-d2.y, d2.x)
			var n := int(f.n)
			for e in vox.cells_in(Rect2(a2, Vector2.ZERO).expand(b2).grow(w * 0.5 + vox.cell)):
				var q: Vector2 = e[1]
				var s := (q - a2).dot(d2)
				if s < 0.0 or s >= len or absf((q - a2).dot(nrm)) > w * 0.5:
					continue
				vox.add(e[0], base, StairGen.step_top(a.y, b.y, len, n, s))
		# Collision : prisme plein en pente sous la volée (inchangé).
		var run := Vector3(b.x - a.x, 0, b.z - a.z)
		var d := run.normalized()
		var side := Vector3(d.z, 0, -d.x) * (w * 0.5)
		var top := [a - side, b - side, b + side, a + side]
		var bot := [Vector3(a.x, base, a.z) - side, Vector3(b.x, base, b.z) - side, Vector3(b.x, base, b.z) + side, Vector3(a.x, base, a.z) + side]
		var pts := PackedVector3Array(top)
		for q in bot:
			if not _near_any(pts, q):
				pts.append(q)
		g.convex.append(pts)
	for l in pl.landings:
		var outline := []
		for q: Vector2 in l.poly:
			outline.append([q.x, q.y])
		var ly := float(l.y)
		var th := maxf((ly - y0) if not spiral else SPIRAL_STEP_T, 0.05)
		_slab_col(g, outline, ly, th)
		vox.fill_poly(l.poly, ly - th, ly)
	for dv in pl.dividers:
		var a2: Vector2 = dv.a
		var b2: Vector2 = dv.b
		var d2 := (b2 - a2).normalized()
		var s := Vector3(-d2.y, 0, d2.x) * (StairGen.RAIL_T * 0.5)
		var top := [Vector3(a2.x, dv.ya, a2.y) - s, Vector3(b2.x, dv.yb, b2.y) - s, Vector3(b2.x, dv.yb, b2.y) + s, Vector3(a2.x, dv.ya, a2.y) + s]
		var bot := [Vector3(a2.x, dv.y0, a2.y) - s, Vector3(b2.x, dv.y0, b2.y) - s, Vector3(b2.x, dv.y0, b2.y) + s, Vector3(a2.x, dv.y0, a2.y) + s]
		g.convex.append(PackedVector3Array(top + bot))
		# Visuel : en marches, à RAIL_H au-dessus de la volée haute (qui
		# monte de b, palier, vers a, pied).
		var len := a2.distance_to(b2)
		var ya := float(dv.ya) - StairGen.RAIL_H
		var yb := float(dv.yb) - StairGen.RAIL_H
		var n := StairGen.flight_steps(pl, ya - yb, len)
		var by := float(dv.y0)
		thin.strip(a2, b2, StairGen.RAIL_T, 0.0, func(t: float) -> Array:
			return [Vector2(by, StairGen.step_top(yb, ya, len, n, len - t) + StairGen.RAIL_H)])
	if spiral:
		_spiral(g, vox, pl)
	_kind = "rail"
	var gr := _group("dark_wood", room)
	var rails := CubeColumns.new()
	var edge_vox := thin if pl.closed else rails
	for e in pl.edges:
		_stair_edge(g if pl.closed else gr, pl, e, edge_vox)
	if spiral and (pl.rail or pl.closed):
		_spiral_rail(edge_vox, pl)
	vox.emit(self, g, lean)
	if thin != vox:
		thin.emit(self, g, lean)
	rails.emit(self, gr, lean)


static func _near_any(pts: PackedVector3Array, q: Vector3) -> bool:
	for p in pts:
		if p.distance_to(q) < 0.001:
			return true
	return false


## Bord ouvert d'un escalier : limon plein (côtés fermés) ou garde-corps, en
## cubes et en escalier (vox) ; collision : panneau mince jusqu'à la main
## courante (inchangé). Les arcs du colimaçon : _spiral_rail (anneau entier).
func _stair_edge(g: Dictionary, pl: Dictionary, e: Dictionary, vox: CubeColumns) -> void:
	var a: Vector3 = e.a
	var b: Vector3 = e.b
	var seg := b - a
	if Vector2(seg.x, seg.z).length() < 0.01:
		return
	var d2 := Vector2(seg.x, seg.z).normalized()
	var s := Vector3(-d2.y, 0, d2.x) * (StairGen.RAIL_T * 0.5)
	var H := StairGen.RAIL_H
	var hang := not (pl.spiral as Dictionary).is_empty()
	var lo_a := float(e.base) if (pl.closed or hang) else a.y - 0.05
	var lo_b := (float(e.base) + (b.y - a.y) if hang else float(e.base)) if (pl.closed or hang) else b.y - 0.05
	var top := [a + Vector3.UP * H - s, b + Vector3.UP * H - s, b + Vector3.UP * H + s, a + Vector3.UP * H + s]
	var bot := [Vector3(a.x, lo_a, a.z) - s, Vector3(b.x, lo_b, b.z) - s, Vector3(b.x, lo_b, b.z) + s, Vector3(a.x, lo_a, a.z) + s]
	g.convex.append(PackedVector3Array(top + bot))
	if e.get("arc", false):
		return
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var len := a2.distance_to(b2)
	var n := StairGen.flight_steps(pl, b.y - a.y, len)
	var surf := func(t: float) -> float: return StairGen.step_top(a.y, b.y, len, n, t)
	if pl.closed:
		var base := float(e.base)
		vox.strip(a2, b2, StairGen.RAIL_T, StairGen.RAIL_T * 0.5, func(t: float) -> Array:
			var sf: float = surf.call(t)
			return [Vector2(base + (sf - a.y if hang else 0.0), sf + H)])
		return
	_rail_cells(vox, a2, b2, surf, H)


## Colimaçon : noyau carré de 10 × 10 cubes, marches carrées (cases de
## 10 cm dont le centre tombe dans le secteur de la marche, jusqu'au rayon
## extérieur), épaisses de 20 cm (on passe dessous). Collision inchangée :
## noyau à 12 pans, secteurs minces qui suivent l'hélice.
func _spiral(g: Dictionary, vox: CubeColumns, pl: Dictionary) -> void:
	var sp: Dictionary = pl.spiral
	var c: Vector2 = sp.c
	var e1: Vector2 = sp.e1
	var e2: Vector2 = sp.e2
	var ri := float(sp.r_in)
	var ro := float(sp.r_out)
	var y0 := float(sp.y0)
	var y1 := float(sp.y1)
	var H := y1 - y0
	var at := func(th: float, r: float, y: float) -> Vector3:
		var q := c + (e1 * cos(th) + e2 * sin(th)) * r
		return Vector3(q.x, y, q.y)
	var core := vox.origin + Vector2.ONE * (CORE * 0.5)
	var top := y1 + StairGen.RAIL_H
	# Noyau : visuel carré (cases du noyau ci-dessous) ; collision inchangée,
	# le prisme à 12 pans de rayon COLUMN_R (le carré le dépasse de 10 cm au
	# plus, aux coins).
	var ct := []
	var cb := []
	for i in 12:
		var th := TAU * i / 12.0
		ct.append(at.call(th, ri, top))
		cb.append(at.call(th, ri, y0))
	g.convex.append(PackedVector3Array(ct + cb))
	for e in vox.cells_in(Rect2(c - Vector2.ONE * ro, Vector2.ONE * ro * 2.0)):
		var q: Vector2 = e[1]
		if absf(q.x - core.x) < CORE * 0.5 and absf(q.y - core.y) < CORE * 0.5:
			vox.add(e[0], y0, top)
			continue
		if q.distance_to(c) > ro:
			continue
		var ty := StairGen.spiral_top(sp, StairGen.spiral_angle(sp, q))
		vox.add(e[0], maxf(y0, ty - SPIRAL_STEP_T), ty)
	# Collision : secteurs minces le long de l'hélice, qui se chevauchent d'un
	# demi-degré (un rayon de sol pile sur la jointure de deux secteurs ne
	# passe jamais au travers).
	var m := StairGen.SPIRAL_SECTORS
	var eps := deg_to_rad(0.6)
	for i in m:
		var tha := maxf(TAU * i / m - eps, 0.0)
		var thb := minf(TAU * (i + 1) / m + eps, TAU)
		var ya := y0 + H * tha / TAU
		var yb := y0 + H * thb / TAU
		var pts := PackedVector3Array([at.call(tha, ri, ya), at.call(tha, ro, ya), at.call(thb, ro, yb), at.call(thb, ri, yb)])
		for q in [at.call(tha, ri, ya), at.call(tha, ro, ya), at.call(thb, ro, yb), at.call(thb, ri, yb)]:
			var lo := maxf(y0, (q as Vector3).y - StairGen.SPIRAL_T)
			if lo < (q as Vector3).y - 0.001:
				pts.append(Vector3(q.x, lo, q.z))
		if pts.size() == 4:
			pts.append(at.call((tha + thb) * 0.5, (ri + ro) * 0.5, y0 - 0.02))
		g.convex.append(pts)


## Colimaçon : garde-corps (ou limon plein, côtés fermés) sur l'anneau
## extérieur, en escalier de marche en marche ; barreaux tous les 30 cm.
func _spiral_rail(vox: CubeColumns, pl: Dictionary) -> void:
	var sp: Dictionary = pl.spiral
	var c: Vector2 = sp.c
	var R := float(sp.r_out)
	var y0 := float(sp.y0)
	var H := StairGen.RAIL_H
	var w := RAIL_CUBES * CUBE
	var closed: bool = pl.closed
	for e in vox.cells_in(Rect2(c - Vector2.ONE * (R + w), Vector2.ONE * (R + w) * 2.0)):
		var q: Vector2 = e[1]
		if absf(q.distance_to(c) - R) > w * 0.5:
			continue
		var th := StairGen.spiral_angle(sp, q)
		var sf := StairGen.spiral_top(sp, th)
		if closed:
			vox.add(e[0], maxf(y0, sf - StairGen.SPIRAL_T), sf + H)
			continue
		var lo := minf(sf, StairGen.spiral_top(sp, th - CUBE / R))
		vox.add(e[0], lo + H - w, sf + H)
		vox.add(e[0], lo + 0.1, sf + 0.1 + w)
	if closed:
		return
	var nb := floori(TAU * R / BALUSTER_GAP)
	var e1: Vector2 = sp.e1
	var e2: Vector2 = sp.e2
	for i in nb:
		var th := TAU * i / nb
		var sf := StairGen.spiral_top(sp, th)
		vox.add(vox.cell_of(c + (e1 * cos(th) + e2 * sin(th)) * R + CubeColumns.NUDGE), sf + 0.1 + w, sf + H - w)


## Sol en pente (« slope ») : terrasses de 5 cm de haut (colonnes de cubes,
## hauteur du plan arrondie au cube au centre de chaque case).
func _terraces(g: Dictionary, outline: Array, height_fn: Callable) -> void:
	var p2 := PackedVector2Array()
	for p in outline:
		p2.append(Vector2(float(p[0]), float(p[1])))
	var bb := _bb2(p2)
	var c := CUBE if bb.get_area() / (CUBE * CUBE) <= 20000.0 else CUBE * 2.0
	var vox := CubeColumns.new(c, Vector2(snappedf(bb.position.x, CUBE), snappedf(bb.position.y, CUBE)))
	var lo := INF
	for q in p2:
		lo = minf(lo, float(height_fn.call(q.x, q.y)))
	var base := snappedf(lo, CUBE) - CUBE
	vox.floor_level = CubeColumns.cubes(base)
	for e in vox.cells_in(bb):
		var q: Vector2 = e[1]
		if Geometry2D.is_point_in_polygon(q, p2):
			vox.add(e[0], base, snappedf(float(height_fn.call(q.x, q.y)), CUBE))
	vox.emit(self, g)


func _nodes() -> Node3D:
	var root := Node3D.new()
	root.name = "Architecture"
	var keys := _groups.keys()
	keys.sort()
	for key in keys:
		var g: Dictionary = _groups[key]
		if not (g.v as PackedVector3Array).is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = g.v
			arrays[Mesh.ARRAY_NORMAL] = g.n
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = key
			mi.mesh = mesh
			root.add_child(mi)
		if (g.faces as PackedVector3Array).is_empty() and g.boxes.is_empty() and g.convex.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = key + "__col"
		if not (g.faces as PackedVector3Array).is_empty():
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(g.faces)
			shape.backface_collision = true
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
		for bx in g.boxes:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = bx[1]
			cs.shape = shape
			cs.transform = bx[0]
			body.add_child(cs)
		for pts in g.convex:
			var cs := CollisionShape3D.new()
			var shape := ConvexPolygonShape3D.new()
			shape.points = pts
			cs.shape = shape
			body.add_child(cs)
		root.add_child(body)
	for cb in _col_boxes:
		root.add_child(cb)
	# Nœuds « voxel__<salle>__decor<i> » : matériau « voxel » (MeshMapBuilder._setup_nodes).
	for i in _decor.size():
		var it: Array = _decor[i]
		var mi := decor_model(it[1], it[3])
		mi.name = "%s__%s__decor%d" % [MeshMapBuilder.VOXEL_MAT, it[0], i]
		mi.position = it[2]
		root.add_child(mi)
	return root


# ------------------------------------------------------------------ caisse et baril
@warning_ignore_start("integer_division")

## Modèle CUBIQUE (cubes de 5 cm, VoxelBuild) d'une caisse en bois ou d'un
## baril (`kind` : « caisse », « baril ») de taille `size` (m, celle du bloc
## de collision, arrondie au cube), origine au pied, au centre.
static func decor_model(kind: String, size: Vector3) -> MeshInstance3D:
	var nx := VoxelBuild.cubes(size.x, 4)
	var ny := VoxelBuild.cubes(size.y, 4)
	var nz := VoxelBuild.cubes(size.z, 4)
	var vb := VoxelBuild.new()
	if kind == "baril":
		_barrel(vb, nx, ny, nz)
	else:
		_crate(vb, nx, ny, nz)
	return vb.node("voxel__" + kind, Vector3(-nx, 0, -nz) * VoxelBuild.CUBE * 0.5)


## Caisse en bois : planches de 4 cubes (joints sombres), cadre de 2 cubes sur
## les arêtes, écharpe peinte en escalier sur chaque côté, clous.
static func _crate(vb: VoxelBuild, nx: int, ny: int, nz: int) -> void:
	vb.fill(0, nx, 0, ny, 0, nz, VoxelBuild.col("crate_wood"), 81, 0.06, 3)
	var frame := VoxelBuild.col("wood_dark", 1.1)
	var seam := VoxelBuild.col("wood_dark", 0.75)
	for c: Vector3i in vb.cells.keys():
		var ex := c.x < 2 or c.x >= nx - 2
		var ey := c.y < 2 or c.y >= ny - 2
		var ez := c.z < 2 or c.z >= nz - 2
		# Arêtes : cadre sur les deux faces qui s'y rejoignent.
		if (ex and ey) or (ey and ez) or (ex and ez):
			vb.put(c.x, c.y, c.z, VoxelBuild.grain(c.x, c.y, c.z, frame, 82, 0.05, 2))
	# Faces des côtés (±z, ±x) : joints des planches, écharpe en escalier.
	for side in [[VoxelBuild.PZ, nx, nz - 1], [VoxelBuild.NZ, nx, 0], [VoxelBuild.PX, nz, nx - 1], [VoxelBuild.NX, nz, 0]]:
		var d: int = side[0]
		var n: int = side[1]
		for u in range(2, n - 2):
			for y in range(2, ny - 2):
				var x: int = u if d in [VoxelBuild.PZ, VoxelBuild.NZ] else side[2]
				var z: int = side[2] if d in [VoxelBuild.PZ, VoxelBuild.NZ] else u
				var k := float(u - 2) / maxf(1.0, n - 5.0)
				var yb := 2 + roundi(k * (ny - 6))
				if y >= yb and y < yb + 2:
					vb.paint(x, y, z, d, VoxelBuild.grain(x, y, z, frame, 83, 0.05, 2))
				elif (y - 2) % 4 == 3:
					vb.paint(x, y, z, d, seam)
	# Dessus : planches dans la longueur, joints sombres.
	for x in range(2, nx - 2):
		for z in range(2, nz - 2):
			if (z - 2) % 4 == 3:
				vb.paint(x, ny - 1, z, VoxelBuild.PY, seam)


## Baril de métal peint : section octogonale, cerclages en saillie (le corps
## est en retrait d'un cube entre eux), couvercle à rebord et bonde, étiquette
## de danger.
static func _barrel(vb: VoxelBuild, nx: int, ny: int, nz: int) -> void:
	var body := VoxelBuild.col("barrel_red")
	var rib := VoxelBuild.col("metal_dark", 1.15)
	var ribs := [1, 2, ny / 2, ny / 2 + 1, ny - 3, ny - 2]
	for y in ny:
		var inset := 0 if y in ribs else 1
		for x in range(inset, nx - inset):
			for z in range(inset, nz - inset):
				# Coins coupés : section octogonale.
				var dx := mini(x - inset, nx - 1 - inset - x)
				var dz := mini(z - inset, nz - 1 - inset - z)
				if dx + dz < 2:
					continue
				var c := VoxelBuild.grain(x, y, z, rib if y in ribs else body, 84, 0.05, 3)
				vb.put(x, y, z, c)
	# Couvercle : rebord clair, bonde sombre.
	for x in nx:
		for z in nz:
			if vb.has(x, ny - 1, z):
				var rim := x <= 1 or z <= 1 or x >= nx - 2 or z >= nz - 2
				vb.paint(x, ny - 1, z, VoxelBuild.PY, VoxelBuild.col("barrel_red", 1.15) if rim else VoxelBuild.col("barrel_red", 0.85))
	vb.paint(nx / 2 + 1, ny - 1, nz / 2 + 1, VoxelBuild.PY, VoxelBuild.col("rubber"))
	# Étiquette de danger (carré jaune, centre noir) sur la face avant (+z).
	# Entre les cerclages du milieu et du haut.
	var cx := nx / 2
	var cy := (ny / 2 + 2 + ny - 3) / 2
	for x in range(cx - 2, cx + 2):
		for y in range(cy - 2, cy + 2):
			var inner := x in [cx - 1, cx] and y in [cy - 1, cy]
			vb.paint_front(x, y, 0, nz, VoxelBuild.PZ, VoxelBuild.col("rubber" if inner else "hazard_yellow"))

@warning_ignore_restore("integer_division")
