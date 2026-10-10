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
static func _tri(g: Dictionary, a: Vector3, b: Vector3, c: Vector3, n: Vector3, vis: bool, col: bool) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	if vis:
		g.v.append_array([a, b, c])
		g.n.append_array([n, n, n])
	if col:
		g.faces.append_array([a, b, c])


static func _quad(g: Dictionary, p: Array, n: Vector3, vis := true, col := false) -> void:
	_tri(g, p[0], p[1], p[2], n, vis, col)
	_tri(g, p[0], p[2], p[3], n, vis, col)


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
				_quad(g, [c - a - b, c + a - b, c + a + b, c - a + b], n * s)
	if col:
		g.boxes.append([Transform3D(Basis(ux, Vector3.UP, uz), center), size])


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


## Pavé orienté visible dont les deux grandes faces ont chacune leur
## matériau : face +z (normale du mur) -> `gn`, face -z -> `gm`, dessus,
## dessous et bouts -> `gn`.
func _two_sided_box(gn: Dictionary, gm: Dictionary, center: Vector3, size: Vector3, yaw: float) -> void:
	var ux := Vector3(cos(yaw), 0, -sin(yaw))
	var uz := Vector3(sin(yaw), 0, cos(yaw))
	var h := size * 0.5
	for axis in [[ux, h.x, Vector3.UP, h.y, uz, h.z], [Vector3.UP, h.y, ux, h.x, uz, h.z], [uz, h.z, ux, h.x, Vector3.UP, h.y]]:
		var n: Vector3 = axis[0]
		var a: Vector3 = axis[2] * float(axis[3])
		var b: Vector3 = axis[4] * float(axis[5])
		for s in [1.0, -1.0]:
			var c: Vector3 = center + n * float(axis[1]) * s
			var g := gm if (n == uz and s < 0.0) else gn
			_quad(g, [c - a - b, c + a - b, c + a + b, c - a + b], n * s)


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
	_polygon(g, outline, func(_x, _z): return top - th, false, true, false)
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
	# Collision : prisme convexe (contours rectangulaires de l'éditeur), sinon surfaces.
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
	# Salles : sols et plafonds.
	for r in L.get("rooms", []):
		var rid := String(r.id)
		_kind = "floor"
		var g := _group(String(r.get("floor_mat", "floor")), rid)
		if r.has("floor_slab"):
			_slab(g, r.outline, float(r.get("floor", 0.0)), float(r.floor_slab))
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
			for pc in wall_pieces(-t / 2.0, length + t / 2.0, y0, y1, cuts):
				if pc[1] - pc[0] < 0.001 or pc[3] - pc[2] < 0.001:
					continue
				var c: Vector3 = a + d * ((pc[0] + pc[1]) * 0.5) + Vector3.UP * ((pc[2] + pc[3]) * 0.5)
				_box(g, c, Vector3(pc[1] - pc[0], pc[3] - pc[2], t), yaw)
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
		for pc in wall_pieces(0.0, length, y0, y1, w.get("openings", [])):
			if pc[1] - pc[0] < 0.001 or pc[3] - pc[2] < 0.001:
				continue
			var c: Vector3 = a + d * ((pc[0] + pc[1]) * 0.5) + Vector3.UP * ((pc[2] + pc[3]) * 0.5)
			var size := Vector3(pc[1] - pc[0], pc[3] - pc[2], t)
			_two_sided_box(gn, gm, c, size, yaw)
			var cb := CollisionBox.make(c, size, yaw, false, mat_n)
			cb.name = "Biais_%d" % _col_boxes.size()
			_col_boxes.append(cb)
	# Dalles (balcons, mezzanines).
	_kind = "slab"
	for sl in L.get("slabs", []):
		_slab(_group(String(sl.get("mat", "wood")), String(sl.room)), sl.outline, float(sl.y), float(sl.get("thick", 0.25)))
	# Escaliers : marches visibles, rampe de collision (coin plein). Types
	# (palier, en L, en U, colimaçon, rampe...) et options (garde-corps, côtés
	# fermés, nombre de marches) : StairGen, voir _stair.
	_kind = "stair"
	for st in L.get("stairs", []):
		if StairGen.kind_of(st) != StairGen.DEFAULT_KIND or st.has("rail") or st.has("closed") or st.has("steps") or StairGen.side_of(st) != 0:
			_stair(st)
			_kind = "stair"
			continue
		var a := Vector3(st.a[0], st.a[1], st.a[2])
		var b := Vector3(st.b[0], st.b[1], st.b[2])
		var w := float(st.get("w", 1.5))
		var run := Vector3(b.x - a.x, 0, b.z - a.z)
		var rise := b.y - a.y
		var n := maxi(1, roundi(absf(rise) / 0.18))
		var d := run.normalized()
		var yaw := atan2(-d.z, d.x)
		var side := Vector3(d.z, 0, -d.x)
		var g := _group(String(st.get("mat", "wood")), String(st.room))
		var step := run.length() / n
		for i in n:
			var top := a.y + rise * (i + 1) / n
			var c := a + d * (step * (i + 0.5))
			_box(g, Vector3(c.x, (a.y + top) * 0.5, c.z), Vector3(step, top - a.y, w), yaw, true, false)
		var lo := Vector3(b.x, a.y, b.z)
		g.convex.append(PackedVector3Array([a - side * (w / 2), a + side * (w / 2), b + side * (w / 2), b - side * (w / 2),
			lo + side * (w / 2), lo - side * (w / 2)]))
	# Garde-corps : main courante, lisse, barreaux et un bloc de collision.
	_kind = "rail"
	for rl in L.get("rails", []):
		var pts: Array = rl.path
		var h := float(rl.get("h", 1.0))
		var y := float(rl.y)
		var g := _group(String(rl.get("mat", "dark_wood")), String(rl.room))
		for i in pts.size() - 1:
			var a := Vector3(pts[i][0], 0, pts[i][1])
			var bb := Vector3(pts[i + 1][0], 0, pts[i + 1][1])
			var seg := bb - a
			var d := seg.normalized()
			var yaw := atan2(-d.z, d.x)
			var c := a + seg * 0.5
			_box(g, Vector3(c.x, y + h, c.z), Vector3(seg.length(), 0.08, 0.1), yaw, true, false)
			_box(g, Vector3(c.x, y + 0.1, c.z), Vector3(seg.length(), 0.08, 0.1), yaw, true, false)
			var nb := maxi(1, int(seg.length() / 0.3))
			for k in nb + 1:
				var p := a + seg * (float(k) / nb)
				_box(g, Vector3(p.x, y + h / 2.0, p.z), Vector3(0.05, h, 0.05), yaw, true, false)
			_box(g, Vector3(c.x, y + h / 2.0, c.z), Vector3(seg.length(), h, 0.1), yaw, false, true)
	return _nodes()


## Pavé orienté quelconque (base `basis` orthonormée, `size` le long de ses axes).
func _obox(g: Dictionary, center: Vector3, size: Vector3, basis: Basis) -> void:
	var h := size * 0.5
	var ax := [basis.x * h.x, basis.y * h.y, basis.z * h.z]
	for k in 3:
		var n: Vector3 = (ax[k] as Vector3).normalized()
		var a: Vector3 = ax[(k + 1) % 3]
		var b: Vector3 = ax[(k + 2) % 3]
		for s in [1.0, -1.0]:
			var c: Vector3 = center + ax[k] * s
			_quad(g, [c - a - b, c + a - b, c + a + b, c - a + b], n * s)


## Prisme convexe visible : contour du dessus `top` et du dessous `bot`
## (mêmes points, même ordre), faces latérales comprises.
static func _prism_visual(g: Dictionary, top: Array, bot: Array) -> void:
	var c := Vector3.ZERO
	for q in top + bot:
		c += q
	c /= float(top.size() + bot.size())
	var n := top.size()
	for i in range(1, n - 1):
		_tri(g, top[0], top[i], top[i + 1], ((top[i] - top[0]).cross(top[i + 1] - top[0])).normalized() * _side_sign(top[0], top[i], top[i + 1], c), true, false)
		_tri(g, bot[0], bot[i], bot[i + 1], ((bot[i] - bot[0]).cross(bot[i + 1] - bot[0])).normalized() * _side_sign(bot[0], bot[i], bot[i + 1], c), true, false)
	for i in n:
		var j := (i + 1) % n
		var quad := [top[i], top[j], bot[j], bot[i]]
		var nn: Vector3 = (quad[1] - quad[0]).cross(quad[3] - quad[0])
		if nn.length() < 1e-6:
			nn = ((quad[2] - quad[1]).cross(quad[3] - quad[1]))
		if nn.length() < 1e-6:
			continue
		nn = nn.normalized()
		if nn.dot((quad[0] + quad[2]) * 0.5 - c) < 0.0:
			nn = -nn
		_quad(g, quad, nn)


## +1 si la normale (b - a) x (c - a) s'éloigne du centre `o`, -1 sinon.
static func _side_sign(a: Vector3, b: Vector3, c: Vector3, o: Vector3) -> float:
	var nn := (b - a).cross(c - a)
	return 1.0 if nn.dot((a + b + c) / 3.0 - o) >= 0.0 else -1.0


## Escalier d'un type (StairGen.plan) : volées en marches (rampe : plan
## incliné), paliers pleins, noyau d'un U, colimaçon, garde-corps et limons.
## Collisions : prisme plein en pente sous chaque volée, dalles à fleur.
func _stair(st: Dictionary) -> void:
	var pl := StairGen.plan(st)
	var g := _group(String(st.get("mat", "wood")), String(st.get("room", "x")))
	var y0 := float(pl.y0)
	var ramp: bool = pl.kind == "rampe"
	for f in pl.flights:
		var a: Vector3 = f.a
		var b: Vector3 = f.b
		var w := float(f.w)
		var base := float(f.base)
		var run := Vector3(b.x - a.x, 0, b.z - a.z)
		var d := run.normalized()
		var yaw := atan2(-d.z, d.x)
		var side := Vector3(d.z, 0, -d.x) * (w * 0.5)
		var rise := b.y - a.y
		var top := [a - side, b - side, b + side, a + side]
		var bot := [Vector3(a.x, base, a.z) - side, Vector3(b.x, base, b.z) - side, Vector3(b.x, base, b.z) + side, Vector3(a.x, base, a.z) + side]
		if ramp:
			_prism_visual(g, top, bot)
		else:
			var n := StairGen.flight_steps(pl, rise)
			var step := run.length() / n
			for i in n:
				var ty := a.y + rise * (i + 1) / n
				var c := a + d * (step * (i + 0.5))
				_box(g, Vector3(c.x, (base + ty) * 0.5, c.z), Vector3(step, ty - base, w), yaw, true, false)
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
		var th := (ly - y0) if pl.spiral.is_empty() else 0.2
		_slab(g, outline, ly, maxf(th, 0.05))
	for dv in pl.dividers:
		var a2: Vector2 = dv.a
		var b2: Vector2 = dv.b
		var d2 := (b2 - a2).normalized()
		var s := Vector3(-d2.y, 0, d2.x) * (StairGen.RAIL_T * 0.5)
		var top := [Vector3(a2.x, dv.ya, a2.y) - s, Vector3(b2.x, dv.yb, b2.y) - s, Vector3(b2.x, dv.yb, b2.y) + s, Vector3(a2.x, dv.ya, a2.y) + s]
		var bot := [Vector3(a2.x, dv.y0, a2.y) - s, Vector3(b2.x, dv.y0, b2.y) - s, Vector3(b2.x, dv.y0, b2.y) + s, Vector3(a2.x, dv.y0, a2.y) + s]
		_prism_visual(g, top, bot)
		g.convex.append(PackedVector3Array(top + bot))
	if not (pl.spiral as Dictionary).is_empty():
		_spiral(g, pl)
	_kind = "rail"
	var gr := _group("dark_wood", String(st.get("room", "x")))
	for e in pl.edges:
		_stair_edge(g if pl.closed else gr, pl, e)


static func _near_any(pts: PackedVector3Array, q: Vector3) -> bool:
	for p in pts:
		if p.distance_to(q) < 0.001:
			return true
	return false


## Bord ouvert d'un escalier : limon plein (côtés fermés) ou garde-corps
## (main courante, lisse, barreaux) ; collision : panneau mince jusqu'à la
## main courante.
func _stair_edge(g: Dictionary, pl: Dictionary, e: Dictionary) -> void:
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
	if pl.closed:
		_prism_visual(g, top, bot)
		return
	# Garde-corps : main courante et lisse le long de la pente, barreaux.
	var fwd := seg.normalized()
	var up := Vector3.UP
	var lat := fwd.cross(up).normalized()
	var bs := Basis(fwd, lat.cross(fwd).normalized(), lat)
	var length := seg.length()
	_obox(g, (a + b) * 0.5 + up * H, Vector3(length, 0.08, 0.1), bs)
	_obox(g, (a + b) * 0.5 + up * 0.12, Vector3(length, 0.06, 0.08), bs)
	var nb := maxi(1, int(Vector2(seg.x, seg.z).length() / 0.3))
	for k in nb + 1:
		var q := a + seg * (float(k) / nb)
		_box(g, q + up * (H * 0.5), Vector3(0.05, H, 0.05), atan2(-d2.y, d2.x), true, false)


## Colimaçon : noyau, marches en secteurs, collision en secteurs minces qui
## suivent l'hélice (on passe dessous au pied, sous le dernier quart de tour).
func _spiral(g: Dictionary, pl: Dictionary) -> void:
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
	# Noyau (prisme à 12 pans).
	var ct := []
	var cb := []
	for i in 12:
		var th := TAU * i / 12.0
		ct.append(at.call(th, ri, y1 + StairGen.RAIL_H))
		cb.append(at.call(th, ri, y0))
	_prism_visual(g, ct, cb)
	g.convex.append(PackedVector3Array(ct + cb))
	# Marches visibles.
	var n := StairGen.flight_steps(pl, H)
	for i in n:
		var tha := TAU * i / n
		var thb := TAU * (i + 1) / n
		var ty := y0 + H * (i + 1) / n
		var top := [at.call(tha, ri, ty), at.call(tha, ro, ty), at.call((tha + thb) * 0.5, ro, ty), at.call(thb, ro, ty), at.call(thb, ri, ty)]
		var bot := []
		for q: Vector3 in top:
			bot.append(Vector3(q.x, maxf(y0, ty - 0.2), q.z))
		_prism_visual(g, top, bot)
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
