class_name StairGen
extends RefCounted
## Escaliers d'une carte en maillage (docs/MAP_OBJECTS.md § Escaliers) : plan
## commun au jeu (géométrie : MeshMapGeometry ; navigation : MeshNav,
## StairLane), à l'aperçu 3D de l'éditeur (même code) et au validateur de
## l'éditeur (pied, sortie, pente).
##
## Une entrée « stairs » de la description en maillage :
##   a      [x, y, z] milieu du bord du PIED de l'emprise (y : sol du bas)
##   b      [x, y, z] milieu du bord opposé de l'emprise (y : sol du haut)
##   w      largeur de l'emprise (m)
##   kind   type (absent : « droit », l'escalier d'avant les types) :
##            droit       une volée droite
##            palier      deux volées droites et un palier au milieu
##            quart       en L : volée, palier d'angle, volée tournée de 90°
##            demi_tour   en U : volée, palier, volée qui revient (sortie du côté du pied)
##            large       escalier d'honneur : 3 m et plus, garde-corps des deux côtés
##            service     escalier de service étroit (1 m), en file indienne
##            colimacon   en colimaçon autour d'un noyau, puis palier de sortie
##            rampe       plan incliné sans marches
##   turn   1 (à droite, défaut) ou -1 (à gauche) : côté du virage (quart,
##          demi_tour) ou sens du colimaçon, vu en montant
##   steps  nombre de marches visibles (absent : ≈ 18 cm chacune)
##   rail   garde-corps sur les côtés ouverts (absent : oui pour « large »)
##   closed côtés fermés (limons pleins jusqu'à la main courante)
##   mat, room
##
## Collisions : sous chaque volée, un prisme plein en pente douce (jamais de
## marche de collision : le joueur n'a pas de montée de marche et les zombies
## flottent au-dessus du sol, StairGen.STEP_HEIGHT) ; paliers à fleur des
## volées ; colimaçon en secteurs minces ; au haut de chaque escalier, un
## tablier CollisionBox (objet du projet) à fleur du palier comble toute fente
## entre la dernière marche et le sol d'arrivée.
##
## Ancres des zombies (`lane`) : une ancre d'entrée devant le pied, une ancre
## de sortie sur le palier d'arrivée (assez loin du bord), et des points sur
## l'axe de chaque volée et à chaque palier ou virage, avec la demi-largeur où
## un zombie peut s'écarter de l'axe (largeur de la volée moins le garde-corps,
## le rayon de la capsule et une marge).

const KINDS := ["droit", "palier", "quart", "demi_tour", "large", "service", "colimacon", "rampe"]
const DEFAULT_KIND := "droit"
## Types dont la sortie n'est pas en face du pied (le sens de montée est donné
## par l'éditeur, « monte », et non déduit des sols).
const SHAPED := ["quart", "demi_tour", "colimacon"]
## Marche maximale franchie par un zombie (capsule décollée de 0,3 m :
## Zombie.STEP_GAP) et par le navmesh (MeshNav : agent_max_climb).
const STEP_HEIGHT := 0.3
## Hauteur visée d'une marche visible.
const STEP_RISE := 0.18
## Demi-largeur d'un zombie aux épaules (Zombie.SHOULDER_RADIUS : sur les
## marches, ni bras ni épaules dans le garde-corps) et marge aux côtés.
const AGENT_RADIUS := 0.3
const LANE_MARGIN := 0.12
## Épaisseur d'un garde-corps ou d'un limon plein.
const RAIL_T := 0.1
const RAIL_H := 1.0
## Ancres : distance devant le pied et au-delà du haut.
const ENTRY_GAP := 0.75
const EXIT_GAP := 0.9
## Écart maximal entre deux points de l'axe.
const LANE_STEP := 1.0
## Colimaçon : rayon du noyau, épaisseur des secteurs, nombre de secteurs.
const COLUMN_R := 0.25
const SPIRAL_T := 0.25
const SPIRAL_SECTORS := 32
## Pente au-delà de laquelle le navmesh ne marche plus (MeshNav : 42°) : le
## couloir du colimaçon reste là où la pente est sous SPIRAL_SLOPE.
const SPIRAL_SLOPE := 36.0
## Tablier du haut : longueur sur le palier, épaisseur.
const APRON := 0.6
const APRON_T := 0.3
## Largeur minimale (m) de l'emprise selon le type, et côté minimal du colimaçon.
const MIN_WIDTH := {"droit": 1.5, "palier": 1.5, "quart": 3.0, "demi_tour": 3.0, "large": 3.0, "service": 1.0, "colimacon": 4.0, "rampe": 1.5}
const MIN_LENGTH := {"quart": 3.0, "demi_tour": 3.0, "colimacon": 4.0}
## Colimaçon : hauteur minimale (passage sous le dernier quart de tour).
const SPIRAL_MIN_RISE := 3.2
const HEADROOM := 2.1


static func kind_of(st: Dictionary) -> String:
	var k := String(st.get("kind", DEFAULT_KIND))
	return k if KINDS.has(k) else DEFAULT_KIND


static func is_shaped(kind: String) -> bool:
	return SHAPED.has(kind)


static func _v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Entrée de description d'après un rectangle de l'éditeur : centre et taille
## (m, repère du plan x / y = x / z du jeu), rotation (degrés, sens horaire vu
## de dessus), direction de montée `up` (vecteur unitaire déjà tourné),
## longueur le long de `up`, largeur en travers, sols du bas et du haut.
static func spec(center: Vector2, up: Vector2, length: float, width: float, y0: float, y1: float, kind := DEFAULT_KIND, opts := {}) -> Dictionary:
	var a := center - up * (length * 0.5)
	var b := center + up * (length * 0.5)
	var st := {"a": [a.x, y0, a.y], "b": [b.x, y1, b.y], "w": width}
	if kind != DEFAULT_KIND:
		st["kind"] = kind
	st.merge(opts)
	return st


## Plan d'un escalier (entrée « stairs ») : volées, paliers, colimaçon, murs
## et garde-corps, pied et sortie, couloir des ancres. Positions 2D en (x, z).
static func plan(st: Dictionary) -> Dictionary:
	var a := _v3(st.a)
	var b := _v3(st.b)
	var kind := kind_of(st)
	var W := maxf(float(st.get("w", 1.5)), 0.2)
	var t := -1.0 if float(st.get("turn", 1)) < 0.0 else 1.0
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var L := maxf(a2.distance_to(b2), 0.05)
	var u := (b2 - a2) / L if a2.distance_to(b2) > 0.001 else Vector2(0, -1)
	var right := Vector2(-u.y, u.x)
	var y0 := a.y
	var y1 := b.y
	var H := y1 - y0
	var rail := bool(st.get("rail", kind == "large"))
	var closed := bool(st.get("closed", false))
	var side_t := RAIL_T if (rail or closed) else 0.0
	var p := {"kind": kind, "a": a, "b": b, "a2": a2, "u": u, "right": right, "L": L, "W": W, "turn": t,
		"y0": y0, "y1": y1, "rail": rail, "closed": closed, "flights": [], "landings": [], "spiral": {},
		"edges": [], "dividers": [], "polys": [], "steps": int(st.get("steps", 0)),
		"foot": {}, "exit": {}, "lane": []}
	var P := func(s: float, lat: float) -> Vector2: return a2 + u * s + right * lat
	var lane: Array = []   # [Vector3, demi-largeur]
	match kind:
		"palier":
			var D := clampf(W * 0.6, 1.0, 2.0)
			D = minf(D, L * 0.34)
			var s1 := (L - D) * 0.5
			var s2 := (L + D) * 0.5
			var ym := y0 + H * 0.5
			var half := _half(W, side_t, side_t)
			_flight(p, P.call(0.0, 0.0), y0, P.call(s1, 0.0), ym, W, y0)
			_landing(p, [P.call(s1, -W * 0.5), P.call(s2, -W * 0.5), P.call(s2, W * 0.5), P.call(s1, W * 0.5)], ym)
			_flight(p, P.call(s2, 0.0), ym, P.call(L, 0.0), y1, W, y0)
			p.polys.append(_rect_poly(P, 0.0, L, -W * 0.5, W * 0.5))
			_line(lane, _at(P.call(0.0, 0.0), y0), _at(P.call(s1, 0.0), ym), half, true)
			_line(lane, _at(P.call(s1, 0.0), ym), _at(P.call(s2, 0.0), ym), half, false)
			_line(lane, _at(P.call(s2, 0.0), ym), _at(P.call(L, 0.0), y1), half, false)
			if rail or closed:
				for lat in [-W * 0.5, W * 0.5]:
					_edge(p, _at(P.call(0.0, lat), y0), _at(P.call(s1, lat), ym), y0, lat < 0.0)
					_edge(p, _at(P.call(s1, lat), ym), _at(P.call(s2, lat), ym), y0, lat < 0.0)
					_edge(p, _at(P.call(s2, lat), ym), _at(P.call(L, lat), y1), y0, lat < 0.0)
			p.foot = {"m": P.call(0.0, 0.0), "n": -u, "h": W * 0.5}
			p.exit = {"m": P.call(L, 0.0), "n": u, "h": W * 0.5}
		"quart":
			var f := quart_flight_width(W, L)
			var c1 := -t * (W * 0.5 - f * 0.5)
			var r1 := L - f
			var r2 := W - f
			var yl := y0 + H * r1 / maxf(r1 + r2, 0.01)
			var half := _half(f, side_t, side_t)
			var far: Vector2 = P.call(L - f * 0.5, c1)
			_flight(p, P.call(0.0, c1), y0, P.call(r1, c1), yl, f, y0)
			_landing(p, _rect_poly(P, r1, L, c1 - f * 0.5, c1 + f * 0.5), yl)
			_flight(p, P.call(L - f * 0.5, c1 + t * f * 0.5), yl, P.call(L - f * 0.5, t * W * 0.5), y1, f, y0)
			p.polys.append(_rect_poly(P, 0.0, L, c1 - f * 0.5, c1 + f * 0.5))
			p.polys.append(_rect_poly(P, r1, L, minf(c1 + t * f * 0.5, t * W * 0.5), maxf(c1 + t * f * 0.5, t * W * 0.5)))
			_line(lane, _at(P.call(0.0, c1), y0), _at(P.call(r1, c1), yl), half, true)
			_line(lane, _at(P.call(r1, c1), yl), _at(far, yl), half, false)
			_line(lane, _at(far, yl), _at(P.call(L - f * 0.5, c1 + t * f * 0.5), yl), half, false)
			_line(lane, _at(P.call(L - f * 0.5, c1 + t * f * 0.5), yl), _at(P.call(L - f * 0.5, t * W * 0.5), y1), half, false)
			if rail or closed:
				var outer := c1 - t * f * 0.5   # côté extérieur de la première volée
				var inner := c1 + t * f * 0.5
				_edge(p, _at(P.call(0.0, outer), y0), _at(P.call(r1, outer), yl), y0, true)
				_edge(p, _at(P.call(r1, outer), yl), _at(P.call(L, outer), yl), y0, true)
				_edge(p, _at(P.call(L, outer), yl), _at(P.call(L, inner), yl), y0, true)
				_edge(p, _at(P.call(L, inner), yl), _at(P.call(L, t * W * 0.5), y1), y0, true)
				_edge(p, _at(P.call(0.0, inner), y0), _at(P.call(r1, inner), yl), y0, false)
				_edge(p, _at(P.call(r1, inner), yl), _at(P.call(r1, t * W * 0.5), y1), y0, false)
			p.foot = {"m": P.call(0.0, c1), "n": -u, "h": f * 0.5}
			p.exit = {"m": P.call(L - f * 0.5, t * W * 0.5), "n": right * t, "h": f * 0.5}
		"demi_tour":
			var f := W * 0.5
			var D := minf(f, L * 0.4)
			var r := L - D
			var ym := y0 + H * 0.5
			var c1 := -t * f * 0.5
			var c2 := t * f * 0.5
			var half := _half(f, side_t, RAIL_T)
			_flight(p, P.call(0.0, c1), y0, P.call(r, c1), ym, f, y0)
			_landing(p, _rect_poly(P, r, L, -W * 0.5, W * 0.5), ym)
			_flight(p, P.call(r, c2), ym, P.call(0.0, c2), y1, f, y0)
			p.polys.append(_rect_poly(P, 0.0, L, -W * 0.5, W * 0.5))
			# Noyau entre les deux volées : limon plein jusqu'à la main courante
			# de la volée haute (la volée qui revient est plus haute).
			p.dividers.append({"a": P.call(0.0, 0.0), "b": P.call(r, 0.0), "ya": y1 + RAIL_H, "yb": ym + RAIL_H, "y0": y0})
			_line(lane, _at(P.call(0.0, c1), y0), _at(P.call(r, c1), ym), half, true)
			_line(lane, _at(P.call(r, c1), ym), _at(P.call(L - D * 0.5, c1), ym), half, false)
			_line(lane, _at(P.call(L - D * 0.5, c1), ym), _at(P.call(L - D * 0.5, c2), ym), half, false)
			_line(lane, _at(P.call(L - D * 0.5, c2), ym), _at(P.call(r, c2), ym), half, false)
			_line(lane, _at(P.call(r, c2), ym), _at(P.call(0.0, c2), y1), half, false)
			if rail or closed:
				var o1 := -t * W * 0.5
				var o2 := t * W * 0.5
				_edge(p, _at(P.call(0.0, o1), y0), _at(P.call(r, o1), ym), y0, true)
				_edge(p, _at(P.call(r, o1), ym), _at(P.call(L, o1), ym), y0, true)
				_edge(p, _at(P.call(L, o1), ym), _at(P.call(L, o2), ym), y0, true)
				_edge(p, _at(P.call(L, o2), ym), _at(P.call(r, o2), ym), y0, true)
				_edge(p, _at(P.call(r, o2), ym), _at(P.call(0.0, o2), y1), y0, true)
			p.foot = {"m": P.call(0.0, c1), "n": -u, "h": f * 0.5}
			p.exit = {"m": P.call(0.0, c2), "n": -u, "h": f * 0.5}
		"colimacon":
			var R := minf(W, L) * 0.5
			var c: Vector2 = P.call(L * 0.5, 0.0)
			var band := spiral_band(R, H, side_t)
			var rm := (band.x + band.y) * 0.5
			var half := maxf((band.y - band.x) * 0.5, 0.0)
			var e1 := -right * t
			var e2 := u
			p.spiral = {"c": c, "r_in": COLUMN_R, "r_out": R, "rm": rm, "e1": e1, "e2": e2, "y0": y0, "y1": y1}
			p.polys.append(_rect_poly(P, 0.0, L, -W * 0.5, W * 0.5))
			# Palier de sortie : quart de cercle au-dessus du début de la vis.
			var lr := [P.call(L * 0.5, -t * COLUMN_R), P.call(L, -t * COLUMN_R), P.call(L, -t * R), P.call(L * 0.5, -t * R)]
			_landing(p, lr, y1)
			var start := c + e1 * rm
			_line(lane, _at(P.call(0.0, -t * rm), y0), _at(start, y0), half, true)
			var n := 24
			var prev := _at(start, y0)
			for i in range(1, n + 1):
				var th := TAU * i / n
				var q := c + (e1 * cos(th) + e2 * sin(th)) * rm
				var cur := _at(q, y0 + H * float(i) / n)
				_line(lane, prev, cur, half, false)
				prev = cur
			_line(lane, prev, _at(P.call(L, -t * rm), y1), half, false)
			if rail or closed:
				var m := 24
				for i in m:
					var tha := TAU * i / m
					var thb := TAU * (i + 1) / m
					var pa := c + (e1 * cos(tha) + e2 * sin(tha)) * R
					var pb := c + (e1 * cos(thb) + e2 * sin(thb)) * R
					_edge(p, _at(pa, y0 + H * float(i) / m), _at(pb, y0 + H * float(i + 1) / m), maxf(y0, y0 + H * float(i) / m - SPIRAL_T), true)
				_edge(p, _at(P.call(L * 0.5, -t * COLUMN_R), y1), _at(P.call(L, -t * COLUMN_R), y1), y1 - SPIRAL_T, false)
			p.foot = {"m": P.call(0.0, -t * (COLUMN_R + R) * 0.5), "n": -u, "h": (R - COLUMN_R) * 0.5}
			p.exit = {"m": P.call(L, -t * (COLUMN_R + R) * 0.5), "n": u, "h": (R - COLUMN_R) * 0.5}
		_:
			# droit, large, service, rampe : une volée sur toute l'emprise.
			var half := _half(W, side_t, side_t)
			_flight(p, a2, y0, b2, y1, W, y0)
			p.polys.append(_rect_poly(P, 0.0, L, -W * 0.5, W * 0.5))
			_line(lane, _at(a2, y0), _at(b2, y1), half, true)
			if rail or closed:
				for lat in [-W * 0.5, W * 0.5]:
					_edge(p, _at(P.call(0.0, lat), y0), _at(P.call(L, lat), y1), y0, lat < 0.0)
			p.foot = {"m": a2, "n": -u, "h": W * 0.5}
			p.exit = {"m": b2, "n": u, "h": W * 0.5}
	# Ancres : devant le pied (sol du bas) et sur le palier d'arrivée.
	var first: Array = lane[0]
	var last: Array = lane[lane.size() - 1]
	var fm: Vector2 = p.foot.m
	var em: Vector2 = p.exit.m
	var entry := _at(fm + (p.foot.n as Vector2) * ENTRY_GAP, y0)
	var exit_p := _at(em + (p.exit.n as Vector2) * EXIT_GAP, y1)
	# Écart réduit de moitié aux ancres : la horde se resserre sur l'axe pour
	# passer une porte en haut ou en bas des marches.
	lane.insert(0, [entry, float(first[1]) * 0.5])
	lane.append([exit_p, float(last[1]) * 0.5])
	p.lane = lane
	return p


## Largeur d'une volée en L : la moitié du petit côté, au demi-mètre, 1 à 2,5 m.
static func quart_flight_width(W: float, L: float) -> float:
	return clampf(floorf(minf(W, L) * 0.5 / 0.5) * 0.5, 1.0, 2.5)


## Colimaçon : rayons intérieur et extérieur (x, y) du couloir des zombies.
static func spiral_band(R: float, H: float, side_t: float) -> Vector2:
	var steep := absf(H) / (TAU * tan(deg_to_rad(SPIRAL_SLOPE)))
	var r_in := maxf(COLUMN_R + AGENT_RADIUS + LANE_MARGIN, steep + 0.4)
	var r_out := R - side_t - AGENT_RADIUS - LANE_MARGIN
	return Vector2(r_in, maxf(r_out, r_in))


## Demi-largeur de couloir d'une volée de largeur `w` (garde-corps éventuels de chaque côté).
static func _half(w: float, ta: float, tb: float) -> float:
	return maxf(w * 0.5 - maxf(ta, tb) - AGENT_RADIUS - LANE_MARGIN, 0.0)


static func _at(q: Vector2, y: float) -> Vector3:
	return Vector3(q.x, y, q.y)


static func _rect_poly(P: Callable, s0: float, s1: float, l0: float, l1: float) -> PackedVector2Array:
	var lo := minf(l0, l1)
	var hi := maxf(l0, l1)
	return PackedVector2Array([P.call(s0, lo), P.call(s1, lo), P.call(s1, hi), P.call(s0, hi)])


static func _flight(p: Dictionary, a: Vector2, ya: float, b: Vector2, yb: float, w: float, base: float) -> void:
	p.flights.append({"a": Vector3(a.x, ya, a.y), "b": Vector3(b.x, yb, b.y), "w": w, "base": base})


static func _landing(p: Dictionary, poly: Variant, y: float) -> void:
	p.landings.append({"poly": PackedVector2Array(poly), "y": y})


## Bord ouvert (garde-corps ou limon plein) de `a` à `b` sur la surface de
## marche ; `base` : bas du limon plein. `left` : côté gauche vu en montant.
static func _edge(p: Dictionary, a: Vector3, b: Vector3, base: float, left: bool) -> void:
	p.edges.append({"a": a, "b": b, "base": base, "left": left})


## Points de l'axe de `a` à `b` (au plus LANE_STEP entre deux), `first` : avec `a`.
static func _line(lane: Array, a: Vector3, b: Vector3, half: float, first: bool) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / LANE_STEP))
	for i in range(0 if first else 1, n + 1):
		lane.append([a.lerp(b, float(i) / n), half])


## Tablier du haut (entrée de `blockers`, CollisionBox) : pavé invisible du
## bord de sortie jusqu'à APRON au-delà, dessus à fleur du sol du haut.
static func apron(st: Dictionary) -> Dictionary:
	var pl := plan(st)
	var ex: Dictionary = pl.exit
	var n: Vector2 = ex.n
	var m: Vector2 = ex.m
	# Du bord même (à fleur de l'arête haute de la rampe : aucun rebord).
	var c := m + n * (APRON * 0.5)
	var y1 := float(pl.y1)
	return {"center": [c.x, y1 - APRON_T * 0.5, c.y], "size": [APRON, APRON_T, float(ex.h) * 2.0],
		"yaw": atan2(-n.y, n.x), "barrier": false, "surface": "wood"}


# ------------------------------------------------------------------ mesures (validateur, tests)

## Longueur horizontale parcourue sur les marches (pente du validateur).
static func run_length(pl: Dictionary) -> float:
	var total := 0.0
	for f in pl.flights:
		var d: Vector3 = f.b - f.a
		total += Vector2(d.x, d.z).length()
	if not (pl.spiral as Dictionary).is_empty():
		total += TAU * float(pl.spiral.rm)
	return total


## Pente la plus forte d'une volée (degrés) ; colimaçon : sur l'axe.
static func max_slope(pl: Dictionary) -> float:
	var worst := 0.0
	for f in pl.flights:
		var d: Vector3 = f.b - f.a
		worst = maxf(worst, rad_to_deg(atan2(absf(d.y), maxf(Vector2(d.x, d.z).length(), 0.01))))
	if not (pl.spiral as Dictionary).is_empty():
		var sp: Dictionary = pl.spiral
		worst = maxf(worst, rad_to_deg(atan2(absf(float(sp.y1) - float(sp.y0)), TAU * float(sp.rm))))
	return worst


## Largeur de passage la plus étroite (m) : volées, ou couloir du colimaçon.
static func walk_width(pl: Dictionary) -> float:
	if not (pl.spiral as Dictionary).is_empty():
		return float(pl.spiral.r_out) - float(pl.spiral.r_in)
	var w := INF
	for f in pl.flights:
		w = minf(w, float(f.w))
	return w


## Nombre de marches visibles d'une volée de hauteur `rise` (total `steps`
## réparti au prorata ; jamais plus de STEP_HEIGHT par marche).
static func flight_steps(pl: Dictionary, rise: float) -> int:
	var H := absf(float(pl.y1) - float(pl.y0))
	var n := 0
	if int(pl.steps) > 0 and H > 0.01:
		n = roundi(float(pl.steps) * absf(rise) / H)
	else:
		n = roundi(absf(rise) / STEP_RISE)
	return maxi(maxi(1, n), ceili(absf(rise) / (STEP_HEIGHT - 0.02)))


## Hauteur de la surface de marche (collision) en (x, z), ou NAN hors de
## l'escalier : sert aux tests (profil sans marche ni fente).
static func surface_y(pl: Dictionary, q: Vector2) -> float:
	var best := NAN
	for f in pl.flights:
		var a: Vector3 = f.a
		var b: Vector3 = f.b
		var a2 := Vector2(a.x, a.z)
		var d := Vector2(b.x, b.z) - a2
		var len := d.length()
		if len < 0.001:
			continue
		var dir := d / len
		var s := (q - a2).dot(dir)
		var lat := absf((q - a2).dot(Vector2(-dir.y, dir.x)))
		if s >= -0.001 and s <= len + 0.001 and lat <= float(f.w) * 0.5 + 0.001:
			var y := a.y + (b.y - a.y) * clampf(s / len, 0.0, 1.0)
			best = y if is_nan(best) else maxf(best, y)
	for l in pl.landings:
		if Geometry2D.is_point_in_polygon(q, l.poly):
			best = float(l.y) if is_nan(best) else maxf(best, float(l.y))
	return best
