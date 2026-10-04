class_name MapSummary
extends RefCounted
## RÉSUMÉ CALCULÉ D'UNE CARTE pour l'agent (serveur MCP de l'éditeur) :
## résumé par étage (editor_get_map, format « summary »), éléments complets
## (editor_get_element) et proposition de couloir entre deux pièces
## (editor_plan_corridor), sans jamais rien appliquer.
##
## Port À L'IDENTIQUE de l'ancien pont Python (tools/mcp/map_geom.py) : une
## fois sérialisés en JSON, les résultats sont les mêmes (clés, valeurs, ordre
## des listes, arrondis). D'où quelques choix inhabituels :
##   - points en tableaux [x, y] de flottants 64 bits, jamais Vector2 (32 bits) ;
##   - arrondis de Python : round(v, 2) exact au pair (r2), round(v) au pair
##     (snap), « %.2f » exact (_fmt) ;
##   - distances par l'algorithme de math.hypot de CPython (hypot), sommes de
##     flottants compensées comme sum() de Python ≥ 3.12 (_fsum) ;
##   - tris stables, premier maximum gardé (comme min / max de Python).
## Coordonnées en mètres, x vers l'est, y vers le sud ; une pièce = un contour
## (liste de [x, y]), trait de ses murs ; deux côtés parallèles à moins de
## JOIN_TOL (3 cm) l'un de l'autre forment un bord commun (mur mitoyen).
## Le document est un instantané de carte (EditorMap.snapshot() ou son JSON) :
## {carte, pieces, ouvertures, objets, zones, depart}.

const EPS := 0.001
const JOIN_TOL := 0.03
const CELL := 0.5
## Tolérance pour dire qu'une ouverture (position) est sur le trait d'une pièce.
const OPENING_TOL := 0.05
## Pièces proches (non collées) gardées par pièce, et distance maximale.
const NEAR_LIMIT := 3
const NEAR_MAX := 20.0
## Clés qui précisent un objet (ce qu'il est, contre quel mur).
const OBJ_DETAIL_KEYS := ["atout", "arme", "prefab", "luminaire", "variante", "mur", "angle", "rot",
	"monte", "depart", "epaisseur", "hauteur", "courant", "echelle", "incl", "z"]
const UNITES := "mètres ; x vers l'est, y vers le sud ; bbox = [x0, y0, x1, y1]"

## Lettres accentuées (Latin-1, Latin étendu A) et leur lettre de base, comme
## la décomposition NFKD de Python privée de ses accents (_fold).
const _FOLD_SRC := "ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿĀāĂăĄąĆćĈĉĊċČčĎďĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĨĩĪīĬĭĮįİĴĵĶķĹĺĻļĽľŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžſ"
const _FOLD_DST := "AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceeeeiiiinooooouuuuyyAaAaAaCcCcCcCcDdEeEeEeEeEeGgGgGgGgHhIiIiIiIiIJjKkLlLlLlNnNnNnOoOoOoRrRrRrSsSsSsSsTtTtUuUuUuUuUuUuWwYyYZzZzZzs"
const _FOLD_MULTI := {"Ĳ": "IJ", "ĳ": "ij", "Ŀ": "L·", "ŀ": "l·", "ŉ": "ʼn", "ß": "ss", "ẞ": "ss",
	"ﬀ": "ff", "ﬁ": "fi", "ﬂ": "fl", "ﬃ": "ffi", "ﬄ": "ffl", "ﬅ": "st", "ﬆ": "st"}
## Blancs de str.split() de Python.
const _SPACES := " \t\n\u000b\u000c\r\u001c\u001d\u001e\u001f\u0085                 　"

const _SPLITTER := 134217729.0
const _INV_LN2 := 1.4426950408889634

static var _fold_map := {}


# ------------------------------------------------------------------ nombres (comme Python)

## Découpe de Veltkamp (produit exact de Dekker).
static func _split(x: float) -> PackedFloat64Array:
	var t := x * 134217729.0
	var hi := t - (t - x)
	return PackedFloat64Array([hi, x - hi])


## Erreur exacte du produit flottant p = a * b (a * b = p + erreur).
static func _prod_err(a: float, b: float, p: float) -> float:
	var sa := _split(a)
	var sb := _split(b)
	return ((sa[0] * sb[0] - p) + sa[0] * sb[1] + sa[1] * sb[0]) + sa[1] * sb[1]


## math.hypot(x, y) de CPython (vector_norm : mise à l'échelle, sommes en
## double longueur, correction différentielle) : même résultat au bit près.
## Calcul en ligne (sans tableau) : c'est la fonction la plus appelée.
static func hypot(x: float, y: float) -> float:
	x = absf(x)
	y = absf(y)
	if is_inf(x) or is_inf(y):
		return INF
	if is_nan(x) or is_nan(y):
		return NAN
	var mx := x if x > y else y
	if mx == 0.0:
		return mx
	# frexp : mx = m * 2^e avec 0,5 <= m < 1 ; scale = 2^-e.
	var e := int(floorf(log(mx) * _INV_LN2)) + 1
	var m := mx * pow(2.0, -e)
	if m >= 1.0:
		e += 1
	elif m < 0.5:
		e -= 1
	if e < -1023:
		# Sous-normaux : remis en normaux, comme CPython.
		var dbl_min := pow(2.0, -1022)  # (littéral mal relu par Godot)
		return dbl_min * hypot(x / dbl_min, y / dbl_min)
	var scale := pow(2.0, -e)
	# Carrés exacts (dl_mul de Dekker) ajoutés à csum = 1 (dl_fast_sum).
	var csum := 1.0
	var frac1 := 0.0
	var frac2 := 0.0
	var v := x * scale
	var tt := v * _SPLITTER
	var vh := tt - (tt - v)
	var vl := v - vh
	var p := vh * vh
	var q := vh * vl + vl * vh
	var z := p + q
	var sh := csum + z
	frac1 += p - z + q + vl * vl
	frac2 += (csum - sh) + z
	csum = sh
	v = y * scale
	tt = v * _SPLITTER
	vh = tt - (tt - v)
	vl = v - vh
	p = vh * vh
	q = vh * vl + vl * vh
	z = p + q
	sh = csum + z
	frac1 += p - z + q + vl * vl
	frac2 += (csum - sh) + z
	csum = sh
	var h := sqrt(csum - 1.0 + (frac1 + frac2))
	# dl_mul(-h, h)
	tt = h * _SPLITTER
	var hh := tt - (tt - h)
	var hl := h - hh
	p = -hh * hh
	q = -hh * hl + -hl * hh
	z = p + q
	sh = csum + z
	frac1 += p - z + q + -hl * hl
	frac2 += (csum - sh) + z
	csum = sh
	h += (csum - 1.0 + (frac1 + frac2)) / (2.0 * h)
	return h / scale


## sum() de Python (≥ 3.12) sur des flottants : somme compensée de Neumaier.
static func _fsum(values: Array) -> float:
	var s := 0.0
	var c := 0.0
	for v: float in values:
		var t := s + v
		if absf(s) >= absf(v):
			c += (s - t) + v
		else:
			c += (v - t) + s
		s = t
	if c != 0.0 and is_finite(c):
		s += c
	return s


## Entier (en flottant) le plus proche de v * m, égalité au pair, calculé sur
## la valeur exacte du produit (comme l'arrondi décimal de Python). Exact pour
## |v * m| < 2^53.
static func _round_scaled(v: float, m: float) -> float:
	var p := v * m
	if absf(p) >= 9007199254740992.0:  # 2^53
		return p
	var err := _prod_err(v, m, p)
	var fl := floorf(p)
	var frac := p - fl
	if frac == 0.0 and err < 0.0:
		fl -= 1.0
		frac = 1.0
	var s := (frac - 0.5) + err
	if s > 0.0 or (s == 0.0 and fmod(fl, 2.0) != 0.0):
		return fl + 1.0
	return fl


## round(v, 2) de Python sans « -0.0 » : arrondi au centimètre (affichage).
static func r2(v: float) -> float:
	# Au-delà de 2^46, l'écart entre deux flottants dépasse 1/64 : round(v, 2) == v.
	if not is_finite(v) or absf(v) >= 70368744177664.0:
		return v
	var r := _round_scaled(v, 100.0) / 100.0
	return 0.0 if r == 0.0 else r


static func rp(p: Array) -> Array:
	return [r2(p[0]), r2(p[1])]


## « %.Nf » % v de Python (N = 1 ou 2).
static func _fmt(v: float, nd: int) -> String:
	if not is_finite(v):
		return str(v)
	var neg := v < 0.0 or (v == 0.0 and str(v).begins_with("-"))
	var digits := str(int(_round_scaled(absf(v), pow(10.0, nd))))
	while digits.length() <= nd:
		digits = "0" + digits
	var txt := digits.substr(0, digits.length() - nd) + "." + digits.substr(digits.length() - nd)
	return ("-" if neg else "") + txt


## round(x) de Python : entier le plus proche, égalité au pair.
static func _round_even(x: float) -> float:
	var f := floorf(x)
	var d := x - f
	if d > 0.5 or (d == 0.5 and fmod(f, 2.0) != 0.0):
		return f + 1.0
	return f


static func snap(v: float, step := CELL) -> float:
	return _round_even(v / step) * step


## float(v) de Python ; null si illisible.
static func _float(v: Variant) -> Variant:
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is String or v is StringName:
		var s := String(v).strip_edges()
		if s.is_valid_float():
			return s.to_float()
	return null


## int(v or 0) de Python (valeur illisible : 0).
static func _int(v: Variant) -> int:
	if v is bool:
		return 1 if v else 0
	if v is int:
		return v
	if v is float:
		return int(v) if is_finite(v) else 0
	if v is String or v is StringName:
		var s := String(v).strip_edges()
		return s.to_int() if s.is_valid_int() else 0
	return 0


## str(v) de Python pour les valeurs d'un document JSON.
static func _pystr(v: Variant) -> String:
	if v == null:
		return "None"
	if v is bool:
		return "True" if v else "False"
	if v is float:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) < 1e16:
			return "%d.0" % int(f)
		return JSON.stringify(f, "", false, true)
	return str(v)


## _num de Python : un flottant est arrondi au centimètre, le reste passe tel quel.
static func _num(v: Variant) -> Variant:
	if v is float:
		return r2(v)
	return v


static func _name(v: Variant) -> String:
	if v is Dictionary:
		return _pystr(v.get("fr", v.get("en", "")))
	return "" if v == null else _pystr(v)


## Liste du document (pieces, ouvertures...) réduite à ses dictionnaires.
static func _dicts(doc: Dictionary, key: String) -> Array:
	var out := []
	var l: Variant = doc.get(key)
	if l is Array:
		for e: Variant in l:
			if e is Dictionary:
				out.append(e)
	return out


# ------------------------------------------------------------------ bases

## Contour JSON ([[x, y], ...]) en liste de points [x, y] ; ignore les points illisibles.
static func pts(contour: Variant) -> Array:
	var out := []
	if not (contour is Array or contour is PackedFloat64Array or contour is PackedFloat32Array):
		return out
	for p: Variant in contour:
		var q := _point(p)
		if not q.is_empty():
			out.append(q)
	return out


static func _point(p: Variant) -> Array:
	if not (p is Array or p is PackedFloat64Array or p is PackedFloat32Array or p is PackedInt32Array
			or p is PackedInt64Array):
		return []
	if p.size() < 2:
		return []
	var x: Variant = _float(p[0])
	var y: Variant = _float(p[1])
	if x == null or y == null:
		return []
	return [x, y]


## Boîte englobante [x0, y0, x1, y1] (vide : [0, 0, 0, 0]).
static func bbox(poly: Array) -> Array:
	if poly.is_empty():
		return [0.0, 0.0, 0.0, 0.0]
	var x0: float = poly[0][0]
	var y0: float = poly[0][1]
	var x1 := x0
	var y1 := y0
	for p: Array in poly:
		if p[0] < x0:
			x0 = p[0]
		if p[1] < y0:
			y0 = p[1]
		if p[0] > x1:
			x1 = p[0]
		if p[1] > y1:
			y1 = p[1]
	return [x0, y0, x1, y1]


## Surface (m², formule du lacet, toujours positive).
static func area(poly: Array) -> float:
	var s := 0.0
	var n := poly.size()
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		s += a[0] * b[1] - b[0] * a[1]
	return absf(s) / 2.0


## Centre de gravité du contour (moyenne des sommets si surface nulle).
static func centroid(poly: Array) -> Array:
	var a := 0.0
	var cx := 0.0
	var cy := 0.0
	var n := poly.size()
	for i in n:
		var p1: Array = poly[i]
		var p2: Array = poly[(i + 1) % n]
		var c: float = p1[0] * p2[1] - p2[0] * p1[1]
		a += c
		cx += (p1[0] + p2[0]) * c
		cy += (p1[1] + p2[1]) * c
	if absf(a) < EPS:
		if n == 0:
			return [0.0, 0.0]
		return [_fsum(poly.map(func(p: Array) -> float: return p[0])) / n,
			_fsum(poly.map(func(p: Array) -> float: return p[1])) / n]
	a *= 0.5
	return [cx / (6 * a), cy / (6 * a)]


## Rectangle aligné sur les axes (comme MapGeom.is_axis_rect).
static func is_axis_rect(poly: Array) -> bool:
	if poly.size() < 4:
		return false
	var b := bbox(poly)
	for p: Array in poly:
		var on_x: bool = absf(p[0] - b[0]) < EPS or absf(p[0] - b[2]) < EPS
		var on_y: bool = absf(p[1] - b[1]) < EPS or absf(p[1] - b[3]) < EPS
		if not (on_x and on_y):
			return false
	return absf(area(poly) - (b[2] - b[0]) * (b[3] - b[1])) < EPS


static func closest_on_segment(p: Array, a: Array, b: Array) -> Array:
	var dx: float = b[0] - a[0]
	var dy: float = b[1] - a[1]
	var l2 := dx * dx + dy * dy
	if l2 < EPS * EPS:
		return a
	var t := maxf(0.0, minf(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
	return [a[0] + t * dx, a[1] + t * dy]


static func dist(a: Array, b: Array) -> float:
	return hypot(a[0] - b[0], a[1] - b[1])


static func dist_to_segment(p: Array, a: Array, b: Array) -> float:
	return dist(p, closest_on_segment(p, a, b))


static func dist_to_boundary(poly: Array, p: Array) -> float:
	var best := INF
	var n := poly.size()
	for i in n:
		var d := dist_to_segment(p, poly[i], poly[(i + 1) % n])
		if d < best:
			best = d
	return best


static func on_boundary(poly: Array, p: Array, tol := OPENING_TOL) -> bool:
	return _near_boundary(poly, p, tol)


## dist_to_boundary(poly, p) <= tol, sans calculer chaque distance exacte : un
## côté dont le carré de la distance (calcul direct) dépasse nettement tol² ne
## peut pas passer sous tol (même résultat, bien plus rapide).
static func _near_boundary(poly: Array, p: Array, tol: float) -> bool:
	var lim := tol * tol * (1.0 + 1e-9)
	var n := poly.size()
	for i in n:
		var q := closest_on_segment(p, poly[i], poly[(i + 1) % n])
		var dx: float = p[0] - q[0]
		var dy: float = p[1] - q[1]
		if dx * dx + dy * dy > lim:
			continue
		if hypot(dx, dy) <= tol:
			return true
	return false


## Point dans le polygone (règle pair-impair ; bord : indéterminé).
static func contains(poly: Array, p: Array) -> bool:
	var x: float = p[0]
	var y: float = p[1]
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var xi: float = poly[i][0]
		var yi: float = poly[i][1]
		var xj: float = poly[j][0]
		var yj: float = poly[j][1]
		if (yi > y) != (yj > y):
			var xc := xi + (y - yi) * (xj - xi) / (yj - yi)
			if x < xc:
				inside = not inside
		j = i
	return inside


static func strictly_inside(poly: Array, p: Array, tol := JOIN_TOL) -> bool:
	return contains(poly, p) and not _near_boundary(poly, p, tol)


# ------------------------------------------------------------------ bords communs, distances

## Parties du segment [a1, a2] qui longent le contour pb (MapGeom.edge_common).
static func edge_common(a1: Array, a2: Array, pb: Array, tol := JOIN_TOL) -> Array:
	var out := []
	var dx: float = a2[0] - a1[0]
	var dy: float = a2[1] - a1[1]
	var seg_len := hypot(dx, dy)
	if seg_len < EPS:
		return out
	dx /= seg_len
	dy /= seg_len
	var nx := -dy
	var ny := dx
	var n := pb.size()
	for i in n:
		var b1: Array = pb[i]
		var b2: Array = pb[(i + 1) % n]
		if absf((b1[0] - a1[0]) * nx + (b1[1] - a1[1]) * ny) > tol:
			continue
		if absf((b2[0] - a1[0]) * nx + (b2[1] - a1[1]) * ny) > tol:
			continue
		var bl := dist(b1, b2)
		if bl > EPS and absf(((b2[0] - b1[0]) * nx + (b2[1] - b1[1]) * ny) / bl) > 0.0175:
			continue
		var t1: float = (b1[0] - a1[0]) * dx + (b1[1] - a1[1]) * dy
		var t2: float = (b2[0] - a1[0]) * dx + (b2[1] - a1[1]) * dy
		var lo := maxf(0.0, minf(t1, t2))
		var hi := minf(seg_len, maxf(t1, t2))
		if hi - lo > EPS:
			out.append([[a1[0] + dx * lo, a1[1] + dy * lo], [a1[0] + dx * hi, a1[1] + dy * hi]])
	return out


static func _bbox_apart(ba: Array, bb: Array, g: float) -> bool:
	return ba[2] + g < bb[0] or bb[2] + g < ba[0] or ba[3] + g < bb[1] or bb[3] + g < ba[1]


## Segments communs (mur mitoyen) des contours de deux pièces.
static func common_segments(pa: Array, pb: Array, tol := JOIN_TOL) -> Array:
	return _common_segments(pa, pb, bbox(pa), bbox(pb), tol)


## common_segments avec les boîtes des deux contours déjà calculées.
static func _common_segments(pa: Array, pb: Array, ba: Array, bb: Array, tol := JOIN_TOL) -> Array:
	if _bbox_apart(ba, bb, tol + 0.01):
		return []
	var out := []
	var n := pa.size()
	for i in n:
		out.append_array(edge_common(pa[i], pa[(i + 1) % n], pb, tol))
	return out


## Distance entre les contours de deux pièces et points les plus proches :
## [distance, point sur le bord de pa, point sur le bord de pb]. Pour deux
## segments qui ne se coupent pas, le minimum est atteint à un bout de l'un d'eux.
static func closest_points(pa: Array, pb: Array) -> Array:
	if pa.is_empty() or pb.is_empty():
		return [INF, [0.0, 0.0], [0.0, 0.0]]
	# Calcul en flottants locaux (fonction la plus coûteuse du résumé) ; mêmes
	# opérations que closest_on_segment / dist, dans le même ordre.
	var best_d := INF
	var best_p: Array = [0.0, 0.0]
	var best_q: Array = [0.0, 0.0]
	var best_sq := INF
	var na := pa.size()
	var nb := pb.size()
	var bxs := PackedFloat64Array()
	var bys := PackedFloat64Array()
	for q: Array in pb:
		bxs.append(q[0])
		bys.append(q[1])
	for i in na:
		var a1: Array = pa[i]
		var a2: Array = pa[(i + 1) % na]
		var a1x: float = a1[0]
		var a1y: float = a1[1]
		var a2x: float = a2[0]
		var a2y: float = a2[1]
		var aminx := minf(a1x, a2x)
		var amaxx := maxf(a1x, a2x)
		var aminy := minf(a1y, a2y)
		var amaxy := maxf(a1y, a2y)
		for j in nb:
			var j2 := (j + 1) % nb
			var b1x := bxs[j]
			var b1y := bys[j]
			var b2x := bxs[j2]
			var b2y := bys[j2]
			# Boîtes des deux segments disjointes : pas de croisement ; et si leur
			# écart dépasse déjà le meilleur, aucun bout ne fera mieux.
			var gx := maxf(minf(b1x, b2x) - amaxx, aminx - maxf(b1x, b2x))
			var gy := maxf(minf(b1y, b2y) - amaxy, aminy - maxf(b1y, b2y))
			if gx > 1e-6 or gy > 1e-6:
				gx = maxf(gx, 0.0)
				gy = maxf(gy, 0.0)
				if gx * gx + gy * gy > best_sq:
					continue
			elif segments_cross(a1, a2, pb[j], pb[j2]):
				var x: Variant = intersection(a1, a2, pb[j], pb[j2])
				var p: Array = a1 if x == null else x
				return [0.0, p, p]
			for c in 4:
				# Bout p (de a puis de b) et segment s1-s2 de l'autre contour.
				var px := a1x
				var py := a1y
				var s1x := b1x
				var s1y := b1y
				var s2x := b2x
				var s2y := b2y
				if c == 1:
					px = a2x
					py = a2y
				elif c >= 2:
					px = b1x if c == 2 else b2x
					py = b1y if c == 2 else b2y
					s1x = a1x
					s1y = a1y
					s2x = a2x
					s2y = a2y
				var sdx := s2x - s1x
				var sdy := s2y - s1y
				var qx := s1x
				var qy := s1y
				var l2 := sdx * sdx + sdy * sdy
				if not l2 < EPS * EPS:
					var tt := maxf(0.0, minf(1.0, ((px - s1x) * sdx + (py - s1y) * sdy) / l2))
					qx = s1x + tt * sdx
					qy = s1y + tt * sdy
				var dx := px - qx
				var dy := py - qy
				# Nettement plus loin que le meilleur (carrés directs) : distance exacte inutile.
				if dx * dx + dy * dy > best_sq:
					continue
				var d := hypot(dx, dy)
				if d < best_d:
					best_d = d
					best_sq = d * d * (1.0 + 1e-9)
					var pp: Array
					if c == 0:
						pp = a1
					elif c == 1:
						pp = a2
					elif c == 2:
						pp = pb[j]
					else:
						pp = pb[j2]
					if c < 2:
						best_p = pp
						best_q = [qx, qy]
					else:
						best_p = [qx, qy]
						best_q = pp
	return [best_d, best_p, best_q]


## Point du bord de `room` le plus proche de la pièce `other`.
static func nearest_edge_point(room: Array, other: Array) -> Array:
	return closest_points(room, other)[1]


static func _orient(a: Array, b: Array, c: Array) -> float:
	return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


## Les deux segments se coupent-ils franchement (pas un simple contact) ?
static func segments_cross(a1: Array, a2: Array, b1: Array, b2: Array, tol := 1e-9) -> bool:
	var d1 := _orient(b1, b2, a1)
	var d2 := _orient(b1, b2, a2)
	var d3 := _orient(a1, a2, b1)
	var d4 := _orient(a1, a2, b2)
	return ((d1 > tol and d2 < -tol) or (d1 < -tol and d2 > tol)) \
		and ((d3 > tol and d4 < -tol) or (d3 < -tol and d4 > tol))


## Point d'intersection des deux droites (null si parallèles).
static func intersection(a1: Array, a2: Array, b1: Array, b2: Array) -> Variant:
	var d: float = (a2[0] - a1[0]) * (b2[1] - b1[1]) - (a2[1] - a1[1]) * (b2[0] - b1[0])
	if absf(d) < 1e-12:
		return null
	var t: float = ((b1[0] - a1[0]) * (b2[1] - b1[1]) - (b1[1] - a1[1]) * (b2[0] - b1[0])) / d
	return [a1[0] + t * (a2[0] - a1[0]), a1[1] + t * (a2[1] - a1[1])]


## Points témoins de l'intérieur d'un contour : sommets décalés vers
## l'intérieur, milieux des côtés décalés, centre.
static func _samples(poly: Array) -> Array:
	var out := []
	var c := centroid(poly)
	if contains(poly, c):
		out.append(c)
	var n := poly.size()
	for i in n:
		var a: Array = poly[i]
		var b: Array = poly[(i + 1) % n]
		var m := [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]
		for p: Array in [a, m]:
			var q := [p[0] + (c[0] - p[0]) * 0.02, p[1] + (c[1] - p[1]) * 0.02]
			if contains(poly, q):
				out.append(q)
		# Point juste à l'intérieur du milieu du côté (normale vers l'intérieur).
		var dx: float = b[0] - a[0]
		var dy: float = b[1] - a[1]
		var ln := hypot(dx, dy)
		if ln > EPS:
			for s: int in [1, -1]:
				var q := [m[0] - s * dy / ln * 0.1, m[1] + s * dx / ln * 0.1]
				if strictly_inside(poly, q, 0.05):
					out.append(q)
					break
	return out


## Les intérieurs des deux contours se recouvrent-ils ? (un bord commun ou un
## contact ne compte pas). Approché mais sûr pour des pièces usuelles : côtés
## qui se coupent franchement ou point témoin de l'un dans l'autre.
static func polys_overlap(pa: Array, pb: Array) -> bool:
	var ba := bbox(pa)
	var bb := bbox(pb)
	if ba[2] <= bb[0] + JOIN_TOL or bb[2] <= ba[0] + JOIN_TOL \
			or ba[3] <= bb[1] + JOIN_TOL or bb[3] <= ba[1] + JOIN_TOL:
		return false
	var na := pa.size()
	var nb := pb.size()
	for i in na:
		for j in nb:
			if segments_cross(pa[i], pa[(i + 1) % na], pb[j], pb[(j + 1) % nb]):
				return true
	for p: Array in _samples(pa):
		if strictly_inside(pb, p):
			return true
	for p: Array in _samples(pb):
		if strictly_inside(pa, p):
			return true
	return false


## Le segment [a, b] est-il entièrement porté par le contour (un côté droit) ?
static func segment_on_boundary(poly: Array, a: Array, b: Array, tol := JOIN_TOL) -> bool:
	var cover := 0.0
	var n := poly.size()
	for i in n:
		for s: Array in edge_common(a, b, [poly[i], poly[(i + 1) % n]], tol):
			cover += dist(s[0], s[1])
	# Un polygone à 2 points [e1, e2] donne aussi le côté retour : moitié.
	return cover / 2.0 >= dist(a, b) - 0.01


# ------------------------------------------------------------------ résumé de carte

## Ids des pièces dont le trait passe par la position d'une ouverture.
static func _room_of_opening(rooms: Array, pos: Array) -> Array:
	var out := []
	var g := OPENING_TOL + EPS
	for r: Dictionary in rooms:
		var bb: Array = r.bbox
		# (Hors de la boîte de la pièce élargie de la tolérance : pas sur son trait.)
		if pos[0] < bb[0] - g or pos[0] > bb[2] + g or pos[1] < bb[1] - g or pos[1] > bb[3] + g:
			continue
		if on_boundary(r.poly, pos):
			out.append(r.id)
	return out


## Emplacement compact d'un objet (position, rect, segment ou arc).
static func _obj_place(o: Dictionary) -> Dictionary:
	var out := {}
	if o.get("position") is Array:
		var pp := pts([o.position])
		out["pos"] = rp(pp[0]) if not pp.is_empty() else o.position
	if o.get("rect") is Array and o.rect.size() == 4:
		var vals := []
		for v: Variant in o.rect:
			var f: Variant = _float(v)
			if f == null:
				vals = []
				break
			vals.append(r2(f))
		out["rect"] = vals if vals.size() == 4 else o.rect
	if o.get("sommets") is Array:
		# Format 9 : barrière invisible en polygone.
		var sp := pts(o.sommets)
		if not sp.is_empty():
			out["sommets"] = sp.map(func(p: Array) -> Array: return rp(p))
	if o.get("a") is Array and o.get("b") is Array:
		var ab := pts([o.a, o.b])
		if ab.size() == 2:
			out["a"] = rp(ab[0])
			out["b"] = rp(ab[1])
	if o.get("centre") is Array:
		var c := pts([o.centre])
		if not c.is_empty():
			out["centre"] = rp(c[0])
		if o.has("rayon"):
			out["rayon"] = _num(o.get("rayon"))
	return out


## Résumé compact de la carte pour raisonner : par étage, pièces (zone, boîte,
## surface, voisines par bord commun, pièces proches non collées avec les
## points les plus proches), ouvertures (pièces reliées), objets par type,
## zones, départ. floor = -1 : tous les étages.
static func summarize(doc: Dictionary, floor := -1) -> Dictionary:
	var carte: Dictionary = doc.get("carte") if doc.get("carte") is Dictionary else {}
	var pieces := _dicts(doc, "pieces")
	var ouvertures := _dicts(doc, "ouvertures")
	var objets := _dicts(doc, "objets")
	var zones := _dicts(doc, "zones")
	var dep: Variant = doc.get("depart")
	var depart := "" if _falsy(dep) else _pystr(dep)
	var etages: Array = carte.get("etages") if carte.get("etages") is Array and not carte.etages.is_empty() \
		else [{"sol": 0, "hauteur": 3.2}]

	var rooms := []
	for p: Dictionary in pieces:
		var poly := pts(p.get("contour"))
		rooms.append({"id": _pystr(p.get("id", "")), "poly": poly, "k": _int(p.get("etage")), "src": p,
			"bbox": bbox(poly)})

	var n_floors := etages.size()
	for r: Dictionary in rooms:
		n_floors = maxi(n_floors, r.k + 1)
	for o: Dictionary in ouvertures + objets:
		n_floors = maxi(n_floors, _int(o.get("etage")) + 1)

	var floors_out := []
	for k in n_floors:
		if floor != -1 and k != floor:
			continue
		var f: Dictionary = etages[k] if k < etages.size() and etages[k] is Dictionary else {}
		var on := rooms.filter(func(r: Dictionary) -> bool: return r.k == k)
		var out_rooms := []
		var all_pts := []
		for ri in on.size():
			var r: Dictionary = on[ri]
			var p: Dictionary = r.src
			var poly: Array = r.poly
			all_pts.append_array(poly)
			var e := {"id": r.id, "nom": _name(p.get("nom")), "zone": _pystr(p.get("zone", "")),
				"bbox": (r.bbox as Array).map(func(v: float) -> float: return r2(v)), "surface": r2(area(poly))}
			if not is_axis_rect(poly):
				e["contour"] = poly.map(func(q: Array) -> Array: return rp(q))
			for key: String in ["plafond", "double_hauteur", "forme"]:
				if p.has(key):
					if key == "forme" and p[key] is Dictionary:
						e[key] = p[key].get("type")
					else:
						e[key] = p[key]
			var voisins := []
			var proches := []
			for oi in on.size():
				if oi == ri:
					continue  # (identité, pas égalité : deux pièces identiques restent voisines)
				var o: Dictionary = on[oi]
				var segs := _common_segments(poly, o.poly, r.bbox, o.bbox)
				if not segs.is_empty():
					var lens := segs.map(func(s: Array) -> float: return dist(s[0], s[1]))
					var longest: Array = segs[0]
					var best: float = lens[0]
					for i in range(1, segs.size()):
						if lens[i] > best:
							best = lens[i]
							longest = segs[i]
					voisins.append({"id": o.id, "bord": [rp(longest[0]), rp(longest[1])], "longueur": r2(_fsum(lens))})
				elif not _bbox_apart(r.bbox, o.bbox, NEAR_MAX + EPS):
					# (Boîtes à plus de NEAR_MAX : distance forcément plus grande, calcul évité.)
					var cp := closest_points(poly, o.poly)
					if cp[0] <= NEAR_MAX:
						proches.append({"id": o.id, "distance": r2(cp[0]), "point_ici": rp(cp[1]), "point_la_bas": rp(cp[2])})
			if not voisins.is_empty():
				e["voisins"] = voisins
			if not proches.is_empty():
				e["proches"] = _stable_sort_by(proches, "distance").slice(0, NEAR_LIMIT)
			out_rooms.append(e)

		var out_open := []
		for o: Dictionary in ouvertures:
			if _int(o.get("etage")) != k:
				continue
			var pp := pts([o.get("position")])
			var e := {"id": _pystr(o.get("id", "")), "type": _pystr(o.get("type", ""))}
			if not pp.is_empty():
				e["pos"] = rp(pp[0])
				e["pieces"] = _room_of_opening(on, pp[0])
				all_pts.append(pp[0])
			for key: String in ["largeur", "prix", "variante"]:
				if o.has(key):
					e[key] = _num(o[key])
			out_open.append(e)

		var by_type := {}
		for o: Dictionary in objets:
			if _int(o.get("etage")) != k:
				continue
			var e := {"id": _pystr(o.get("id", ""))}
			e.merge(_obj_place(o), true)
			for key: String in OBJ_DETAIL_KEYS:
				if o.has(key):
					e[key] = _num(o[key])
			var t := _pystr(o.get("type", "?"))
			if not by_type.has(t):
				by_type[t] = []
			by_type[t].append(e)

		floors_out.append({"etage": k, "sol": _num(f.get("sol", k * 3.5)), "hauteur": _num(f.get("hauteur", 3.2)),
			"bornes": bbox(all_pts).map(func(v: float) -> float: return r2(v)), "pieces": out_rooms,
			"ouvertures": out_open, "objets": by_type})

	var zones_out := []
	for z: Dictionary in zones:
		var zid := _pystr(z.get("id", ""))
		var ids := []
		for r: Dictionary in rooms:
			if _pystr((r.src as Dictionary).get("zone", "")) == zid:
				ids.append(r.id)
		var e := {"id": zid, "nom": _name(z.get("nom")), "pieces": ids}
		if z.get("nom") is Dictionary and not _falsy(z.nom.get("en")):
			e["nom_en"] = _pystr(z.nom.en)
		if zid == depart:
			e["depart"] = true
		zones_out.append(e)

	var n_paid := 0
	var cost := 0
	for o: Dictionary in ouvertures:
		if _pystr(o.get("type", "")) in ["porte", "debris"]:
			n_paid += 1
			cost += _int(o.get("prix"))
	return {
		"carte": {"id": carte.get("id"), "nom": carte.get("nom"), "format": carte.get("format"),
			"etages": etages.size(), "zone_depart": depart},
		"totaux": {"pieces": pieces.size(), "ouvertures": ouvertures.size(), "objets": objets.size(),
			"zones": zones.size(), "portes_payantes": n_paid, "cout_total_portes": cost},
		"etages": floors_out,
		"zones": zones_out,
		"unites": UNITES,
	}


## Valeur « fausse » au sens de Python (None, False, 0, "", [], {}).
static func _falsy(v: Variant) -> bool:
	if v == null:
		return true
	if v is bool or v is int or v is float:
		return v == 0
	if v is String or v is StringName or v is Array or v is Dictionary:
		return v.is_empty()
	return false


## Tri stable croissant d'une liste de dictionnaires selon une clé numérique
## (comme list.sort(key=...) de Python ; sort_custom n'est pas stable).
static func _stable_sort_by(items: Array, key: String) -> Array:
	var idx := range(items.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		return items[a][key] < items[b][key] or (items[a][key] == items[b][key] and a < b))
	return idx.map(func(i: int) -> Variant: return items[i])


## {"elements": {id: {"coll": ..., "el": ...}}, "absents": [ids absents]}.
static func find_elements(doc: Dictionary, ids: Array) -> Dictionary:
	var found := {}
	for coll: String in ["pieces", "ouvertures", "objets", "zones"]:
		for e: Dictionary in _dicts(doc, coll):
			var id := _pystr(e.get("id", ""))
			if id in ids:
				found[id] = {"coll": coll, "el": e}
	var missing := []
	for i: Variant in ids:
		if not (i is String and found.has(i)):
			missing.append(i)
	return {"elements": found, "absents": missing}


# ------------------------------------------------------------------ proposition de couloir

static func _next_price(doc: Dictionary) -> int:
	var n := 0
	for o: Dictionary in _dicts(doc, "ouvertures"):
		if o.get("type") is String and o.type in ["porte", "debris"]:
			n += 1
	return MapCatalog.DOOR_PRICES[mini(n, MapCatalog.DOOR_PRICES.size() - 1)]


## Bande [a, a + w] calée sur la grille de 0,5 m dans [lo + margin, hi -
## margin], la plus proche possible de `prefer` (centre souhaité) ; [] si aucune.
static func _band(lo: float, hi: float, w: float, prefer: float, margin: float) -> Array:
	var lo2 := lo + margin
	var hi2 := hi - margin
	if hi2 - lo2 < w - EPS:
		return []
	var a := snap(prefer - w / 2)
	var lo_g := ceilf((lo2 - EPS) / CELL) * CELL
	var hi_g := floorf((hi2 - w + EPS) / CELL) * CELL
	a = hi_g if hi_g < a else a
	a = a if a > lo_g else lo_g
	if a < lo2 - EPS or a + w > hi2 + EPS:
		return []
	return [a, a + w]


static func _rect_poly(x0: float, y0: float, x1: float, y1: float) -> Array:
	return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]


## Texte comparable : sans accents, sans casse, espaces réduits.
static func _fold(text: String) -> String:
	if _fold_map.is_empty():
		for i in _FOLD_SRC.length():
			_fold_map[_FOLD_SRC[i]] = _FOLD_DST[i]
		_fold_map.merge(_FOLD_MULTI)
	var t := ""
	for ch in text:
		var u := ch.unicode_at(0)
		if u >= 0x300 and u <= 0x36f:
			continue  # accent seul (déjà décomposé)
		t += _fold_map.get(ch, ch)
	t = t.to_lower()
	for k: String in ["ß", "ẞ"]:
		t = t.replace(k, "ss")
	var words := PackedStringArray()
	var cur := ""
	for ch in t:
		if _SPACES.contains(ch):
			if cur != "":
				words.append(cur)
			cur = ""
		else:
			cur += ch
	if cur != "":
		words.append(cur)
	return " ".join(words)


## Pièce désignée par son id ou par son NOM (insensible à la casse et aux
## accents ; nom français ou anglais s'il est bilingue) : {"id": id} ou
## {"error": message} si aucune pièce ne correspond ou si le nom est ambigu.
static func resolve_room(doc: Dictionary, ref: String) -> Dictionary:
	var rooms := _dicts(doc, "pieces")
	for p: Dictionary in rooms:
		if _pystr(p.get("id")) == ref:
			return {"id": ref}
	var key := _fold(ref)
	var found := []
	for p: Dictionary in rooms:
		var nom: Variant = p.get("nom")
		var names: Array = [nom.get("fr", ""), nom.get("en", "")] if nom is Dictionary else [nom]
		if key == "":
			continue
		for n: Variant in names:
			if n != null and _fold(_pystr(n)) == key:
				found.append(_pystr(p.get("id")))
				break
	if found.size() == 1:
		return {"id": found[0]}
	if found.size() > 1:
		return {"error": "nom de pièce ambigu : « %s » désigne %s (donner l'id)" % [ref, ", ".join(PackedStringArray(found))]}
	return {"error": "pièce inconnue : %s" % ref}


static func _door_op(same_zone: bool, k: int, pos: Array, max_w: float, door_price: int) -> Dictionary:
	if same_zone:
		return {"op": "add", "coll": "ouvertures",
			"el": {"type": "passage", "etage": k, "position": rp(pos), "largeur": r2(max_w)}}
	return {"op": "add", "coll": "ouvertures",
		"el": {"type": "porte", "etage": k, "position": rp(pos), "largeur": r2(minf(2.0, max_w)), "prix": door_price}}


## Propose (sans rien appliquer) les ops d'un couloir entre deux pièces du même
## étage : couloir droit si leurs côtés se font face, en L sinon ; ou
## simplement une porte si elles ont déjà un mur commun. Le couloir est mis
## dans la zone de room_a (passage libre côté A), porte payante côté B si B
## est d'une autre zone. price = -1 : prix suivant de la courbe des portes.
## {"error": message} si aucun tracé simple n'est sûr.
static func plan_corridor(doc: Dictionary, room_a: String, room_b: String, width: float, price: int = -1) -> Dictionary:
	var rooms := {}
	for p: Dictionary in _dicts(doc, "pieces"):
		rooms[_pystr(p.get("id"))] = p
	var ra := resolve_room(doc, room_a)
	if ra.has("error"):
		return ra
	var rb := resolve_room(doc, room_b)
	if rb.has("error"):
		return rb
	room_a = ra.id
	room_b = rb.id
	if room_a == room_b:
		return {"error": "room_a et room_b sont la même pièce"}
	var A: Dictionary = rooms[room_a]
	var B: Dictionary = rooms[room_b]
	var k := _int(A.get("etage"))
	if _int(B.get("etage")) != k:
		return {"error": "les deux pièces ne sont pas au même étage (relier deux étages : un escalier, pas un couloir)"}
	var w := snap(width)
	if w < 1.0 or w > 6.0:
		return {"error": "largeur %s m hors de 1 à 6 m (couloir : 2 à 3 m, docs/MAP_DESIGN_RULES.md § 3.2)" % _fmt(width, 2)}
	var pa := pts(A.get("contour"))
	var pb := pts(B.get("contour"))
	if pa.size() < 3 or pb.size() < 3:
		return {"error": "contour illisible"}
	var zone_a := _pystr(A.get("zone", ""))
	var zone_b := _pystr(B.get("zone", ""))
	var same_zone := zone_a != "" and zone_a == zone_b
	var door_price := price if price != -1 else _next_price(doc)
	var warnings := []
	var others := []
	for i: String in rooms:
		if i != room_a and i != room_b and _int(rooms[i].get("etage")) == k:
			others.append(pts(rooms[i].get("contour")))

	var items := _wall_items(doc, k)

	# Déjà collées : une porte (ou un passage) sur le plus long mur commun, au
	# plus près du milieu sans toucher une ouverture ou un objet mural.
	var segs := common_segments(pa, pb)
	if not segs.is_empty():
		for o: Variant in (doc.get("ouvertures") if doc.get("ouvertures") is Array else []):
			var q := pts([o.get("position")]) if o is Dictionary and _int(o.get("etage")) == k else []
			if not q.is_empty() and not (o.get("type") is String and o.type == "fenetre") \
					and on_boundary(pa, q[0]) and on_boundary(pb, q[0]):
				return {"error": "les pièces sont déjà reliées par %s (%s)" % [_pystr(o.get("id")), _pystr(o.get("type"))]}
		var s: Array = segs[0]
		var ln := dist(s[0], s[1])
		for i in range(1, segs.size()):
			var l2 := dist(segs[i][0], segs[i][1])
			if l2 > ln:
				ln = l2
				s = segs[i]
		if ln < 1.5:
			return {"error": "mur commun trop court (%s m) pour une porte" % _fmt(ln, 2)}
		var ow := minf(w, snap(ln - 0.5)) if ln - 0.5 >= 1.0 else 1.0
		var ow_door := ow if same_zone else minf(2.0, ow)
		var ux: float = (s[1][0] - s[0][0]) / ln
		var uy: float = (s[1][1] - s[0][1]) / ln
		var spot := []
		var steps := int(ln / 0.25) + 1
		for i in steps:
			var off := float(int((i + 1) / 2.0)) * 0.25 * (1.0 if i % 2 == 1 else -1.0)
			var t := ln / 2 + off
			if t < ow_door / 2 + 0.25 - EPS or t > ln - ow_door / 2 - 0.25 + EPS:
				continue
			var p := [s[0][0] + ux * t, s[0][1] + uy * t]
			if _blocked(p, ow_door / 2, items).is_empty():
				spot = p
				break
		if spot.is_empty():
			return {"error": "pas de place libre sur le mur commun (ouvertures ou objets muraux déjà là)"}
		return {"type": "porte_directe", "label": "Claude : porte %s → %s" % [room_a, room_b],
			"ops": [_door_op(same_zone, k, spot, ow, door_price)],
			"notes": ["Les pièces ont déjà un mur commun : pas de couloir, une ouverture sur le mur commun."],
			"avertissements": warnings}

	var ba := bbox(pa)
	var bb := bbox(pb)
	var ax0: float = ba[0]
	var ay0: float = ba[1]
	var ax1: float = ba[2]
	var ay1: float = ba[3]
	var bx0: float = bb[0]
	var by0: float = bb[1]
	var bx1: float = bb[2]
	var by1: float = bb[3]
	var margin := 0.5
	var candidates := []  # [nom, contour, point_porte_A, point_porte_B, longueurs]

	# Couloir droit horizontal (A et B l'un à côté de l'autre, bandes en y communes).
	for ab: bool in [true, false]:
		var x_from := ax1 if ab else bx1
		var x_to := bx0 if ab else ax0
		if x_to - x_from <= EPS:
			continue
		var lo := by0 if by0 > ay0 else ay0
		var hi := by1 if by1 < ay1 else ay1
		var band := _band(lo, hi, w, (lo + hi) / 2, margin)
		if not band.is_empty():
			var y0: float = band[0]
			var y1: float = band[1]
			var ym := (y0 + y1) / 2
			var pA := [x_from, ym] if ab else [x_to, ym]
			var pB := [x_to, ym] if ab else [x_from, ym]
			candidates.append(["droit", _rect_poly(x_from, y0, x_to, y1), pA, pB, [x_to - x_from]])
	# Couloir droit vertical.
	for ab: bool in [true, false]:
		var y_from := ay1 if ab else by1
		var y_to := by0 if ab else ay0
		if y_to - y_from <= EPS:
			continue
		var lo := bx0 if bx0 > ax0 else ax0
		var hi := bx1 if bx1 < ax1 else ax1
		var band := _band(lo, hi, w, (lo + hi) / 2, margin)
		if not band.is_empty():
			var x0: float = band[0]
			var x1: float = band[1]
			var xm := (x0 + x1) / 2
			var pA := [xm, y_from] if ab else [xm, y_to]
			var pB := [xm, y_to] if ab else [xm, y_from]
			candidates.append(["droit", _rect_poly(x0, y_from, x1, y_to), pA, pB, [y_to - y_from]])

	# Couloir en L : sort d'un côté de A, tourne, entre par un côté de B.
	if candidates.is_empty():
		candidates.append_array(_l_candidates(pa, pb, w, margin))
		for c: Array in _l_candidates(pb, pa, w, margin):
			candidates.append([c[0], c[1], c[3], c[2], c[4]])

	var refused := []
	for c: Array in candidates:
		var cname: String = c[0]
		var poly: Array = c[1]
		var pA: Array = c[2]
		var pB: Array = c[3]
		var lengths: Array = c[4]
		var ea := _end_segment(poly, pA)
		var eb := _end_segment(poly, pB)
		if not segment_on_boundary(pa, ea[0], ea[1]) or not segment_on_boundary(pb, eb[0], eb[1]):
			refused.append("%s : un bout du couloir ne tombe pas sur un mur droit de la pièce" % cname)
			continue
		var busy := _blocked(pA, w / 2, items) + _blocked(pB, (w if same_zone else minf(2.0, w)) / 2, items)
		if not busy.is_empty():
			refused.append("%s : une porte tomberait sur %s" % [cname, ", ".join(PackedStringArray(busy))])
			continue
		var hit := false
		for o: Array in others:
			if polys_overlap(poly, o):
				hit = true
				break
		if hit or polys_overlap(poly, pa) or polys_overlap(poly, pb):
			refused.append("%s : chevaucherait une autre pièce" % cname)
			continue
		var contour := poly.map(func(q: Array) -> Array: return rp(q))
		var ops := [{"op": "add", "coll": "pieces",
				"el": {"nom": "Couloir", "etage": k, "zone": zone_a, "contour": contour}},
			{"op": "add", "coll": "ouvertures",
				"el": {"type": "passage", "etage": k, "position": rp(pA), "largeur": r2(w)}},
			_door_op(same_zone, k, pB, w, door_price)]
		for ln: float in lengths:
			if ln > 12.0 + EPS:
				warnings.append("tronçon droit de %s m : plus de 12 m (§ 3.2), ajoute un coude, une ouverture latérale ou un élargissement" % _fmt(ln, 1))
		if w > 3.0:
			warnings.append("plus de 3 m de large : ce n'est plus un couloir mais une salle à encombrer (§ 3.2)")
		if w < 2.0:
			warnings.append("moins de 2 m : seulement pour un trajet secondaire (§ 3.2)")
		var notes := ["Couloir dans la zone de %s (%s) : passage libre côté %s." % [room_a, zone_a, room_a],
			("Passage libre côté %s (même zone)." % room_b) if same_zone else
				("Porte payante (%d) côté %s : changer « prix » selon la courbe d'ouverture (§ 9.2)." % [door_price, room_b]),
			"Rien n'est appliqué : relire les ops puis les passer à editor_apply (un seul appel = un seul Ctrl+Z).",
			"Après application : editor_validate, puis décorer le couloir (§ 10.2) et vérifier les fenêtres de la zone."]
		return {"type": cname, "label": "Claude : couloir %s → %s" % [room_a, room_b], "ops": ops,
			"contour": contour.duplicate(true), "longueurs": lengths.map(func(x: float) -> float: return r2(x)),
			"notes": notes, "avertissements": warnings}
	var detail := "; ".join(PackedStringArray(refused)) if not refused.is_empty() \
		else "les pièces ne se font face sur aucun côté droit assez large (%s m + marges)" % _fmt(w, 1)
	return {"error": "aucun couloir simple (droit ou en L) n'est sûr : " + detail
		+ ". Dessine-le à la main avec editor_apply (pièce + ouvertures)."}


## Ouvertures et objets muraux de l'étage k : [id, position, demi-largeur].
static func _wall_items(doc: Dictionary, k: int) -> Array:
	var out := []
	for o: Dictionary in _dicts(doc, "ouvertures"):
		if _int(o.get("etage")) != k:
			continue
		var q := pts([o.get("position")])
		if not q.is_empty():
			var lw: Variant = _float(o.get("largeur", 1.0))
			var half: float = lw / 2 if lw != null else 0.5
			out.append([_pystr(o.get("id", "")), q[0], half])
	for o: Dictionary in _dicts(doc, "objets"):
		if _int(o.get("etage")) != k or not o.has("mur"):
			continue
		var q := pts([o.get("position")])
		if not q.is_empty():
			out.append([_pystr(o.get("id", "")), q[0], 0.75])
	return out


## Ids des ouvertures / objets muraux trop près d'une ouverture de
## demi-largeur `half` centrée en p (0,25 m de jeu).
static func _blocked(p: Array, half: float, items: Array) -> Array:
	var out := []
	for it: Array in items:
		if dist(p, it[1]) < half + it[2] + 0.25 - EPS:
			out.append(it[0])
	return out


## Côté du contour du couloir qui contient le point de porte p (son bout).
static func _end_segment(poly: Array, p: Array) -> Array:
	var best_d := INF
	var best := []
	var n := poly.size()
	for i in n:
		var d := dist_to_segment(p, poly[i], poly[(i + 1) % n])
		if best.is_empty() or d < best_d:
			best_d = d
			best = [poly[i], poly[(i + 1) % n]]
	return best


## Couloirs en L partant d'un côté vertical de A (est ou ouest) puis entrant
## par un côté horizontal de B (nord ou sud).
static func _l_candidates(pa: Array, pb: Array, w: float, margin: float) -> Array:
	var out := []
	var ba := bbox(pa)
	var bb := bbox(pb)
	var ax0: float = ba[0]
	var ay0: float = ba[1]
	var ax1: float = ba[2]
	var ay1: float = ba[3]
	var bx0: float = bb[0]
	var by0: float = bb[1]
	var bx1: float = bb[2]
	var by1: float = bb[3]
	for east: bool in [true, false]:
		# Sortie de A par l'est (B à l'est) ou par l'ouest (B à l'ouest).
		if east and bx0 - ax1 < w - EPS:
			continue
		if not east and ax0 - bx1 < w - EPS:
			continue
		for south: bool in [true, false]:
			# Entrée dans B par le nord (B au sud de A) ou par le sud (B au nord).
			if south and not by0 > ay0 + w + margin:
				continue
			if not south and not by1 < ay1 - w - margin:
				continue
			# Bande horizontale (dans le flanc de A), la plus proche de B.
			var hb := _band(ay0, ay1, w, ay1 if south else ay0, margin)
			# Bande verticale (dans le flanc de B), la plus proche de A.
			var vb := _band(bx0, bx1, w, bx0 if east else bx1, margin)
			if hb.is_empty() or vb.is_empty():
				continue
			var y0: float = hb[0]
			var y1: float = hb[1]
			var x0: float = vb[0]
			var x1: float = vb[1]
			if south and not by0 > y1 + EPS:
				continue
			if not south and not by1 < y0 - EPS:
				continue
			var poly: Array
			var xa: float
			var h_len: float
			if east:
				xa = ax1
				if south:
					poly = [[xa, y0], [x1, y0], [x1, by0], [x0, by0], [x0, y1], [xa, y1]]
				else:
					poly = [[xa, y0], [x0, y0], [x0, by1], [x1, by1], [x1, y1], [xa, y1]]
				h_len = x1 - xa
			else:
				xa = ax0
				if south:
					poly = [[xa, y0], [xa, y1], [x1, y1], [x1, by0], [x0, by0], [x0, y0]]
				else:
					poly = [[xa, y0], [xa, y1], [x0, y1], [x0, by1], [x1, by1], [x1, y0]]
				h_len = xa - x0
			var v_len := (by0 - y0) if south else (y1 - by1)
			out.append(["en_L", poly, [xa, (y0 + y1) / 2], [(x0 + x1) / 2, by0 if south else by1], [h_len, v_len]])
	return out
