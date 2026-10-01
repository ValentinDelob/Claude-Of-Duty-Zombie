class_name StairLane
extends RefCounted
## Couloir d'ancres d'un escalier (StairGen.plan, clé « lane ») tel que la
## navigation des zombies l'utilise (MeshNav) : ancre d'entrée au pied,
## points sur l'axe des volées et à chaque palier ou virage, ancre de sortie
## sur le palier d'arrivée. Indice 0 = ancre du bas, dernier = ancre du haut.
##
## Chaque zombie suit le couloir à son propre écart latéral (`offset_point` :
## de -1 à 1, réparti sur la demi-largeur de chaque point) : une horde monte
## de front sans s'empiler, et jamais plus près d'un côté que la largeur de
## la volée moins le garde-corps, le rayon de la capsule et une marge.

## Retrait de l'emprise pour reconnaître un chemin qui EMPRUNTE l'escalier
## (un chemin qui frôle le bord du pied ne compte pas).
const INSET := 0.15
## Hauteur au-delà des sols du bas et du haut où un point compte encore.
const Y_SLACK := 0.35

var index := 0
var name := ""
var pts := PackedVector3Array()
var half := PackedFloat32Array()
## Vecteur d'écart (x, z) de chaque point pour un écart de 1 m vers la droite
## du sens de montée : normale de la volée, en onglet aux virages.
var miter := PackedVector2Array()
## Abscisse curviligne (3D) de chaque point.
var cum := PackedFloat32Array()
var polys: Array[PackedVector2Array] = []
var outer: Array[PackedVector2Array] = []
var y0 := 0.0
var y1 := 0.0
var aabb := Rect2()
## Les deux ancres sont-elles sur le navmesh (sinon le couloir ne sert pas) ?
var ok := true
var problem := ""
## Passage du navmesh d'une ancre à l'autre (MeshNav) et portes payantes
## sur le couloir (le passage est coupé tant que l'une d'elles est fermée).
var link: NavigationLink3D
var doors: Array[String] = []


static func from_plan(pl: Dictionary, idx := 0, label := "") -> StairLane:
	var l := StairLane.new()
	l.index = idx
	l.name = label
	l.y0 = minf(float(pl.y0), float(pl.y1))
	l.y1 = maxf(float(pl.y0), float(pl.y1))
	for e in pl.lane:
		l.pts.append(e[0])
		l.half.append(float(e[1]))
	l._finish()
	var first := true
	for poly: PackedVector2Array in pl.polys:
		l.outer.append(poly)
		var inset := Geometry2D.offset_polygon(poly, -INSET)
		l.polys.append(inset[0] if not inset.is_empty() else poly)
		for q in poly:
			if first:
				l.aabb = Rect2(q, Vector2.ZERO)
				first = false
			else:
				l.aabb = l.aabb.expand(q)
	l.aabb = l.aabb.grow(0.05)
	return l


func _finish() -> void:
	var n := pts.size()
	miter.resize(n)
	cum.resize(n)
	var acc := 0.0
	for i in n:
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		cum[i] = acc
		var d0 := _dir(i - 1, i) if i > 0 else _dir(i, i + 1)
		var d1 := _dir(i, i + 1) if i < n - 1 else d0
		# Ancres et bords des marches : la normale de la volée elle-même (une
		# ancre décalée par le décor ne fait pas pencher l'écart en onglet).
		if n >= 4 and i <= 1:
			d0 = _dir(1, 2)
			d1 = d0
		elif n >= 4 and i >= n - 2:
			d0 = _dir(n - 3, n - 2)
			d1 = d0
		var n0 := Vector2(-d0.y, d0.x)
		var n1 := Vector2(-d1.y, d1.x)
		var m := n0 + n1
		if m.length() < 0.001:
			m = n1
		m = m.normalized()
		miter[i] = m / maxf(m.dot(n1), 0.5)


func _dir(i: int, j: int) -> Vector2:
	var d := pts[clampi(j, 0, pts.size() - 1)] - pts[clampi(i, 0, pts.size() - 1)]
	var v := Vector2(d.x, d.z)
	return v.normalized() if v.length() > 0.0001 else Vector2(0, -1)


func length() -> float:
	return cum[cum.size() - 1] if not cum.is_empty() else 0.0


## Point `i` du couloir pour un zombie d'écart `bias` (-1 à 1 : part de la
## demi-largeur, + à droite en montant), borné à la demi-largeur du point.
func offset_point(i: int, bias: float) -> Vector3:
	var o := clampf(bias, -1.0, 1.0) * half[i]
	var m := miter[i] * o
	return pts[i] + Vector3(m.x, 0.0, m.y)


## Le point est-il sur l'escalier (emprise rentrée de INSET, entre les sols) ?
func contains(p: Vector3) -> bool:
	if p.y < y0 - Y_SLACK or p.y > y1 + Y_SLACK:
		return false
	var q := Vector2(p.x, p.z)
	if not aabb.has_point(q):
		return false
	for poly in polys:
		if Geometry2D.is_point_in_polygon(q, poly):
			return true
	return false


## Le segment (à plat) traverse-t-il l'emprise, à une hauteur de l'escalier ?
func crosses(a: Vector3, b: Vector3) -> bool:
	if maxf(a.y, b.y) < y0 - Y_SLACK or minf(a.y, b.y) > y1 + Y_SLACK:
		return false
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var box := Rect2(a2, Vector2.ZERO).expand(b2)
	if not box.intersects(aabb):
		return false
	for poly in outer:
		if Geometry2D.is_point_in_polygon(a2, poly) or Geometry2D.is_point_in_polygon(b2, poly):
			return true
		for k in poly.size():
			if Geometry2D.segment_intersects_segment(a2, b2, poly[k], poly[(k + 1) % poly.size()]) != null:
				return true
	return false


## Point du couloir le plus proche de `p` (en 3D : un colimaçon ou un U se
## recouvrent vus de dessus) : [abscisse, indice du segment, écart latéral
## signé (m, + à droite en montant), demi-largeur permise à cet endroit,
## point de l'axe].
func project(p: Vector3) -> Array:
	var best := INF
	var out := [0.0, 0, 0.0, half[0] if not half.is_empty() else 0.0, pts[0] if not pts.is_empty() else p]
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var k := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-8 else 0.0
		var q := a + ab * k
		var d2 := q.distance_squared_to(p)
		if d2 < best:
			best = d2
			var d := Vector2(ab.x, ab.z).normalized()
			var lat := Vector2(p.x - q.x, p.z - q.z).dot(Vector2(-d.y, d.x))
			out = [lerpf(cum[i], cum[i + 1], k), i, lat, lerpf(half[i], half[i + 1], k), q]
	return out


## `p` est-il déjà engagé dans le couloir, entre ses deux ancres (dans sa
## largeur, à la hauteur de l'axe) ? Un zombie qui a dépassé l'ancre du pied
## (ou un joueur arrêté entre le haut des marches et l'ancre de sortie) n'est
## pas renvoyé en arrière jusqu'à l'ancre.
func engaged(p: Vector3) -> Array:
	var pr := project(p)
	var s: float = pr[0]
	var q: Vector3 = pr[4]
	if s <= cum[0] + 0.05 or s >= length() - 0.05:
		return []
	if absf(float(pr[2])) > float(pr[3]) + 0.5 or absf(q.y - p.y) > 0.6:
		return []
	return pr


## Indice du premier point strictement après l'abscisse `s` (montée) ou
## strictement avant (descente).
func next_index(s: float, up: bool) -> int:
	if up:
		for i in pts.size():
			if cum[i] > s + 0.05:
				return i
		return pts.size() - 1
	for i in range(pts.size() - 1, -1, -1):
		if cum[i] < s - 0.05:
			return i
	return 0


## Points du couloir de l'abscisse `s_from` à `s_to` (dans ce sens), à l'écart
## `bias` ; `from_end` : depuis l'ancre du bout de départ (sinon : après
## `s_from`) ; `to_end` : jusqu'à l'ancre de ce bout (sinon : avant `s_to`).
func points_between(s_from: float, s_to: float, bias: float, to_end: bool, from_end := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	var up := s_to > s_from
	var i := next_index(s_from, up)
	if from_end:
		i = 0 if up else pts.size() - 1
	if up:
		while i < pts.size() and (cum[i] < s_to - 0.05 or (to_end and i == pts.size() - 1)):
			out.append(offset_point(i, bias))
			i += 1
	else:
		while i >= 0 and (cum[i] > s_to + 0.05 or (to_end and i == 0)):
			out.append(offset_point(i, bias))
			i -= 1
	return out


## Reste à parcourir (m) de `p` jusqu'au point `exit` du couloir : écart
## d'abscisse, plus la distance de `p` à l'axe (un zombie à côté de
## l'ouverture est plus loin que celui qui est en face). Même mesure pour
## tous les zombies qui prennent le couloir dans ce sens : de deux voisins,
## un seul est « devant » l'autre (Zombie._lane_yield), jamais les deux.
func left_to(p: Vector3, exit: Vector3) -> float:
	var pr := project(p)
	var q: Vector3 = pr[4]
	return absf(float(project(exit)[0]) - float(pr[0])) + Vector2(p.x - q.x, p.z - q.z).length()


## Bout (0 : bas, 1 : haut) le plus proche d'un point par sa hauteur.
func end_of(p: Vector3) -> int:
	return 0 if absf(p.y - pts[0].y) <= absf(p.y - pts[pts.size() - 1].y) else 1


## Poussée (x, z) qui ramène dans le couloir un zombie sorti de sa
## demi-largeur (le long des garde-corps et des bords) ; ZERO sinon.
func push_back(p: Vector3) -> Vector3:
	var pr := project(p)
	var lat: float = pr[2]
	var lim: float = float(pr[3]) + 0.05
	if absf(lat) <= lim:
		return Vector3.ZERO
	var i: int = pr[1]
	var d := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).normalized()
	var n := Vector2(-d.y, d.x) * (-signf(lat))
	return Vector3(n.x, 0.0, n.y) * clampf((absf(lat) - lim) * 4.0, 0.0, 1.0)
