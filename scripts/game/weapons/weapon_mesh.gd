class_name WeaponMesh
extends RefCounted
## Géométrie procédurale des armes et des mains : primitives arrondies ou
## chanfreinées (plutôt que des cubes) accumulées dans un tampon, puis
## fusionnées en UN maillage par matériau (quelques appels de dessin par arme).
##
## Primitives (repère local de la pièce, l'arme pointe vers -Z) :
##   prism : profil 2D (z, y) extrudé selon X, arêtes chanfreinées (récepteurs,
##           crosses, poignées, chargeurs courbés, glissières...) ;
##   box   : pavé chanfreiné (prisme d'un rectangle aux coins cassés) ;
##   lathe : profil de révolution (z, rayon) autour de Z (canons, cache-flammes,
##           lunettes, bagues, doigts) ; cyl : cylindre aux bords cassés.
##
## Couleur de sommet (donnée, pas une teinte) : r = arête (1 sur les
## chanfreins : usure brillante du bronzage), g = variation propre à la pièce.


class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	## Sommets de la pièce en cours, en repère local (transformés d'un bloc).
	var _lv := PackedVector3Array()
	var _ln := PackedVector3Array()
	## Transformation de la pièce en cours et sa couleur de donnée.
	var xf := Transform3D.IDENTITY:
		set(value):
			flush()
			xf = value
	var tone := 0.5
	## Finesse des révolutions (vue FPS : fine ; 3e personne : grossière).
	var seg := 16

	func add(p: Vector3, nn: Vector3, edge: float) -> void:
		_lv.append(p)
		_ln.append(nn)
		c.append(Color(edge, tone, 0.0, 1.0))

	## Applique la transformation courante aux sommets en attente (natif).
	func flush() -> void:
		if _lv.is_empty():
			return
		v.append_array(xf * _lv)
		n.append_array(Transform3D(xf.basis, Vector3.ZERO) * _ln)
		_lv.clear()
		_ln.clear()

	## Sommets, normales, couleurs (données pures : utilisables hors du fil
	## principal).
	func arrays() -> Array:
		flush()
		return [v, n, c]

	static func make_mesh(arr: Array) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = arr[0]
		arrays[Mesh.ARRAY_NORMAL] = arr[1]
		arrays[Mesh.ARRAY_COLOR] = arr[2]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m

	## Triangle orienté d'après la normale voulue (Godot : faces avant dans le
	## sens horaire).
	func tri(a: Vector3, b: Vector3, cc: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ea := 0.0, eb := 0.0, ec := 0.0) -> void:
		var fn := (b - a).cross(cc - a)
		if fn.dot(na + nb + nc) > 0.0:
			add(a, na, ea)
			add(cc, nc, ec)
			add(b, nb, eb)
		else:
			add(a, na, ea)
			add(b, nb, eb)
			add(cc, nc, ec)

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, e := 0.0) -> void:
		tri(a, b, cc, na, nb, nc, e, e, e)
		tri(a, cc, d, na, nc, nd, e, e, e)

	func is_empty() -> bool:
		return v.is_empty() and _lv.is_empty()

	func commit() -> ArrayMesh:
		return make_mesh(arrays())


static func _v(x: float, p: Vector2) -> Vector3:
	return Vector3(x, p.y, p.x)


## Prisme : polygone `pts` (Vector2(z, y)) extrudé sur la largeur `w` (X),
## arêtes chanfreinées de `b`. Les sommets voisins presque alignés partagent
## leur normale (courbes lisses : chargeurs, crosses).
static func prism(acc: Acc, pts_in: Array, w: float, b: float) -> void:
	var pts: Array = pts_in.duplicate()
	var cnt := pts.size()
	if cnt < 3:
		return
	var area := 0.0
	for i in cnt:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % cnt]
		area += p0.x * p1.y - p1.x * p0.y
	if area < 0.0:
		pts.reverse()
	b = minf(b, w * 0.45)
	# Normales extérieures des côtés (polygone direct dans le plan z, y).
	var en: Array[Vector2] = []
	for i in cnt:
		var d: Vector2 = pts[(i + 1) % cnt] - pts[i]
		en.append(Vector2(d.y, -d.x).normalized())
	# Contour intérieur (faces latérales chanfreinées) : décalage en onglet.
	var inner: Array[Vector2] = []
	for i in cnt:
		var np: Vector2 = en[(i - 1 + cnt) % cnt]
		var nn: Vector2 = en[i]
		var m := (np + nn) / maxf(1.0 + np.dot(nn), 0.15) * b
		m = m.limit_length(b * 2.5)
		inner.append(pts[i] - m)
	var hw := w * 0.5
	var xb := hw - b
	var X := Vector3.RIGHT
	# Faces planes des deux côtés (triangulées).
	var poly := PackedVector2Array(inner)
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		poly = PackedVector2Array(pts)
		idx = Geometry2D.triangulate_polygon(poly)
	for side in [1.0, -1.0]:
		var nx: Vector3 = X * side
		var xs: float = hw * side
		for t in range(0, idx.size(), 3):
			acc.tri(_v(xs, poly[idx[t]]), _v(xs, poly[idx[t + 1]]), _v(xs, poly[idx[t + 2]]), nx, nx, nx)
	# Chanfreins des deux faces.
	if b > 0.0:
		for side in [1.0, -1.0]:
			for i in cnt:
				var j := (i + 1) % cnt
				var ne := Vector3(0, en[i].y, en[i].x)
				var nb: Vector3 = (ne + X * side).normalized()
				acc.quad(_v(hw * side, inner[i]), _v(hw * side, inner[j]), _v(xb * side, pts[j]), _v(xb * side, pts[i]), nb, nb, nb, nb, 1.0)
	# Tranche : normales lissées aux sommets peu anguleux.
	for i in cnt:
		var j := (i + 1) % cnt
		var ni := _vert_normal(en, i, i)
		var nj := _vert_normal(en, j, i)
		acc.quad(_v(xb, pts[i]), _v(xb, pts[j]), _v(-xb, pts[j]), _v(-xb, pts[i]), ni, nj, nj, ni)


## Normale au sommet `vi` vue depuis le côté `ei` : moyenne avec le côté voisin
## si l'angle est faible (< 38°), sinon celle du côté (arête vive).
static func _vert_normal(en: Array[Vector2], vi: int, ei: int) -> Vector3:
	var cnt := en.size()
	var other := (vi - 1 + cnt) % cnt if vi == ei else vi
	var a := en[ei]
	var o := en[other]
	var r := a
	if a.dot(o) > 0.79:
		r = (a + o).normalized()
	return Vector3(0, r.y, r.x)


## Rectangle (z, y) aux coins cassés de `c` (8 sommets).
static func chamfer_rect(sz: float, sy: float, c: float) -> Array:
	var hz := sz * 0.5
	var hy := sy * 0.5
	c = minf(c, minf(hz, hy) * 0.9)
	if c <= 0.0:
		return [Vector2(-hz, -hy), Vector2(hz, -hy), Vector2(hz, hy), Vector2(-hz, hy)]
	return [Vector2(-hz + c, -hy), Vector2(hz - c, -hy), Vector2(hz, -hy + c), Vector2(hz, hy - c),
		Vector2(hz - c, hy), Vector2(-hz + c, hy), Vector2(-hz, hy - c), Vector2(-hz, -hy + c)]


## Rectangle aux coins arrondis de rayon `r` (`n` pas par coin).
static func round_rect(sz: float, sy: float, r: float, n := 3) -> Array:
	var hz := sz * 0.5
	var hy := sy * 0.5
	r = minf(r, minf(hz, hy) * 0.95)
	var out := []
	var centers := [Vector2(hz - r, -hy + r), Vector2(hz - r, hy - r), Vector2(-hz + r, hy - r), Vector2(-hz + r, -hy + r)]
	for k in 4:
		for s in n + 1:
			var a := -PI * 0.5 + PI * 0.5 * k + PI * 0.5 * s / n
			out.append(centers[k] + Vector2(cos(a), sin(a)) * r)
	return out


static func box(acc: Acc, size: Vector3, b := -1.0) -> void:
	if b < 0.0:
		b = clampf(minf(size.x, minf(size.y, size.z)) * 0.14, 0.0004, 0.004)
	prism(acc, chamfer_rect(size.z, size.y, b), size.x, b)


## Révolution du profil `prof` (Vector2(z, rayon), z croissant) autour de Z ;
## disques de fermeture aux bouts de rayon non nul.
static func lathe(acc: Acc, prof: Array, seg := -1, caps := true) -> void:
	if seg < 0:
		seg = acc.seg
	var cnt := prof.size()
	var cs := PackedFloat32Array()
	var sn := PackedFloat32Array()
	for k in seg + 1:
		var a := TAU * k / seg
		cs.append(cos(a))
		sn.append(sin(a))
	for i in cnt - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var d := p1 - p0
		if d.length() < 0.00001:
			continue
		# Normale du segment dans le plan (z, r) : (-dr, dz).
		var n2 := Vector2(-d.y, d.x).normalized()
		var e := 1.0 if d.length() < 0.0035 else 0.0
		for k in seg:
			var na := Vector3(cs[k] * n2.y, sn[k] * n2.y, n2.x)
			var nb := Vector3(cs[k + 1] * n2.y, sn[k + 1] * n2.y, n2.x)
			var a0 := Vector3(cs[k] * p0.y, sn[k] * p0.y, p0.x)
			var b0 := Vector3(cs[k + 1] * p0.y, sn[k + 1] * p0.y, p0.x)
			var a1 := Vector3(cs[k] * p1.y, sn[k] * p1.y, p1.x)
			var b1 := Vector3(cs[k + 1] * p1.y, sn[k + 1] * p1.y, p1.x)
			if p0.y < 0.00001:
				acc.tri(a0, b1, a1, na, nb, na, e, e, e)
			elif p1.y < 0.00001:
				acc.tri(a0, b0, a1, na, nb, na, e, e, e)
			else:
				acc.quad(a0, b0, b1, a1, na, nb, nb, na, e)
	if not caps:
		return
	for end in [0, cnt - 1]:
		var p: Vector2 = prof[end]
		if p.y < 0.00001:
			continue
		var nz := Vector3(0, 0, -1.0 if end == 0 else 1.0)
		var c0 := Vector3(0, 0, p.x)
		for k in seg:
			acc.tri(c0, Vector3(cs[k] * p.y, sn[k] * p.y, p.x), Vector3(cs[k + 1] * p.y, sn[k + 1] * p.y, p.x), nz, nz, nz)


## Cylindre selon Z (rayon `r`, longueur `l`) aux bords cassés.
static func cyl(acc: Acc, r: float, l: float, seg := -1) -> void:
	var c := minf(r * 0.18, minf(0.0016, l * 0.25))
	var h := l * 0.5
	lathe(acc, [Vector2(-h, r - c), Vector2(-h + c, r), Vector2(h - c, r), Vector2(h, r - c)], seg)


## Capsule effilée de `a` à `b` (rayons ra, rb) : doigts, phalanges.
static func capsule(acc: Acc, a: Vector3, b: Vector3, ra: float, rb: float, seg := 8) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var saved := acc.xf
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	# -Z du repère local vers b : le profil va de z = 0 (a) à z = -l (b).
	var basis := Basis.looking_at(d, up)
	acc.xf = saved * Transform3D(basis, a)
	var prof := []
	var steps := 3
	# Hémisphère côté b (z = -l - rb .. -l), fût, hémisphère côté a.
	for s in steps + 1:
		var t := PI * 0.5 * s / steps
		prof.append(Vector2(-l - cos(t) * rb, sin(t) * rb))
	for s in steps + 1:
		var t := PI * 0.5 * s / steps
		prof.append(Vector2(sin(t) * ra, cos(t) * ra))
	lathe(acc, prof, seg, false)
	acc.xf = saved


## Sphère (articulations).
static func sphere(acc: Acc, center: Vector3, r: float, seg := 8) -> void:
	var saved := acc.xf
	acc.xf = saved * Transform3D(Basis.IDENTITY, center)
	var prof := []
	var steps := 4
	for s in steps + 1:
		var t := PI * s / steps
		prof.append(Vector2(-cos(t) * r, sin(t) * r))
	lathe(acc, prof, seg, false)
	acc.xf = saved


## Tube tronconique ouvert de `a` à `b` (manches, avant-bras) : profil libre
## [t (0..1 de a vers b), rayon] ; section légèrement aplatie (`flat` en X).
static func limb(acc: Acc, a: Vector3, b: Vector3, prof: Array, seg := 10, flat := 1.0) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return
	var saved := acc.xf
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	acc.xf = saved * Transform3D(Basis.looking_at(d, up).scaled_local(Vector3(flat, 1.0, 1.0)), a)
	var pr := []
	for q in prof:
		pr.append(Vector2(-l * float(q[0]), float(q[1])))
	pr.reverse()
	lathe(acc, pr, seg, true)
	acc.xf = saved
