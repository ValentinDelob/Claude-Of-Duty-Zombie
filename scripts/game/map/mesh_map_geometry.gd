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


## Dalle pleine (dessus à `top`, épaisseur `th`) : planchers d'étage, balcons.
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
		_box(_group(String(bl.get("mat", "wood")), String(bl.get("room", "x"))), (lo + hi) * 0.5, hi - lo, 0.0, true, not bl.get("nocollide", false))
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
			cuts.sort_custom(func(p, q): return float(p.t) < float(q.t))
			var pieces := []
			var s := -t / 2.0
			for o in cuts:
				var o0 := float(o.t) - float(o.w) / 2.0
				var o1 := float(o.t) + float(o.w) / 2.0
				if o0 > s:
					pieces.append([s, o0, y0, y1])
				if float(o.y0) > y0:
					pieces.append([o0, o1, y0, float(o.y0)])
				if float(o.y1) < y1:
					pieces.append([o0, o1, float(o.y1), y1])
				s = o1
			pieces.append([s, length + t / 2.0, y0, y1])
			for pc in pieces:
				if pc[1] - pc[0] < 0.001 or pc[3] - pc[2] < 0.001:
					continue
				var c: Vector3 = a + d * ((pc[0] + pc[1]) * 0.5) + Vector3.UP * ((pc[2] + pc[3]) * 0.5)
				_box(g, c, Vector3(pc[1] - pc[0], pc[3] - pc[2], t), yaw)
	# Dalles (balcons, mezzanines).
	_kind = "slab"
	for sl in L.get("slabs", []):
		_slab(_group(String(sl.get("mat", "wood")), String(sl.room)), sl.outline, float(sl.y), float(sl.get("thick", 0.25)))
	# Escaliers : marches visibles, rampe de collision (coin plein).
	_kind = "stair"
	for st in L.get("stairs", []):
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
	return root
