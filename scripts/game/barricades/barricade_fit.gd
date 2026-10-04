class_name BarricadeFit
extends RefCounted
## Ajuste la barrière de collision d'une entrée des zombies (fenêtre, porte)
## au mur RÉELLEMENT percé d'une carte en maillage (KINO, cartes de
## l'éditeur) : épaisseur du mur, milieu de cette épaisseur et largeur de la
## découpe, mesurés sur la description de la carte (blocs, murs, murs en
## biais : la même géométrie que les collisions construites).
##
## Pourquoi : la barrière d'une fenêtre faisait 1 m de profondeur (murs de 1 m
## des cartes grille) quels que soient les murs. Sur les murs de 0,41 m de
## KINO elle dépassait de 30 cm dans la salle (43 cm à la fenêtre des loges,
## posée hors du milieu du mur), sur ceux de 0,5 m de l'éditeur de 25 cm :
## deux coins vifs devant chaque fenêtre où la capsule du joueur qui longe le
## mur s'arrêtait net. Ajustée, la barrière affleure les deux faces du mur et
## bouche toute la découpe : le nu du mur est continu, rien n'accroche.
## Fonctions pures (testées : tests/test_barricade_wall_fit.gd).

## Mesures valides seulement si le mur trouvé a une épaisseur plausible.
const MIN_DEPTH := 0.1
const MAX_DEPTH := 1.2
## Écart toléré entre deux pavés de mur qui se boutent (blocs fusionnés par
## demi-cases de l'éditeur, une texture par face : bord commun exact). Moins
## que le retrait du décor contre un mur (MapLayoutExport.DECOR_WALL_INSET,
## 5 mm) : une caisse posée contre le mur n'épaissit pas la barrière.
const JOIN := 0.002


## Renseigne wall_depth, wall_mid et cut_width de chaque ouverture
## (BarricadeLayout.Opening) d'après la description `data` de la carte.
## Rien de trouvé : valeurs laissées à 0 (barrière par défaut du type).
static func fit(data: Dictionary, openings: Array) -> void:
	if openings.is_empty():
		return
	var rects := solids(data)
	for o: BarricadeLayout.Opening in openings:
		var sec := wall_section(rects, o)
		if sec.y - sec.x >= MIN_DEPTH and sec.y - sec.x <= MAX_DEPTH:
			o.wall_depth = sec.y - sec.x
			o.wall_mid = (sec.x + sec.y) * 0.5
		var span := cut_span(rects, o)
		o.cut_width = span.y - span.x
		o.cut_off = (span.x + span.y) * 0.5


## Pavés pleins de la carte (collisions des murs) : [{c: Vector2 (x, z),
## u: Vector2 (axe de la longueur), hu, hv (demi-longueur, demi-épaisseur),
## y0, y1}]. Blocs (sauf barrières et blocs sans collision), murs (morceaux
## autour des ouvertures, MeshMapGeometry.wall_pieces), murs en biais.
static func solids(data: Dictionary) -> Array:
	var out := []
	for bl in data.get("blocks", []):
		if bl.get("barrier", false) or bl.get("nocollide", false):
			continue
		var b: Array = bl.box
		out.append({"c": Vector2((float(b[0]) + float(b[3])) * 0.5, (float(b[2]) + float(b[5])) * 0.5), "u": Vector2.RIGHT,
			"hu": absf(float(b[3]) - float(b[0])) * 0.5, "hv": absf(float(b[5]) - float(b[2])) * 0.5,
			"y0": minf(float(b[1]), float(b[4])), "y1": maxf(float(b[1]), float(b[4]))})
	for w in data.get("walls", []):
		var pts: Array = w.path.duplicate()
		if w.get("closed", false):
			pts.append(w.path[0])
		var t := float(w.get("thick", 0.3))
		for si in pts.size() - 1:
			var cuts: Array = w.get("openings", []).filter(func(o): return int(o.seg) == si)
			_segment(out, Vector2(pts[si][0], pts[si][1]), Vector2(pts[si + 1][0], pts[si + 1][1]), t, -t / 2.0, t / 2.0,
				float(w.y0), float(w.y1), cuts)
	for w in data.get("obliques", []):
		_segment(out, Vector2(w.a[0], w.a[1]), Vector2(w.b[0], w.b[1]), float(w.get("thick", 0.5)), 0.0, 0.0,
			float(w.y0), float(w.y1), w.get("openings", []))
	return out


## Morceaux pleins d'un tronçon de mur de `a` à `b` (rallongé de `ext0` au
## début et `ext1` à la fin, comme MeshMapGeometry).
static func _segment(out: Array, a: Vector2, b: Vector2, t: float, ext0: float, ext1: float, y0: float, y1: float, cuts: Array) -> void:
	var length := a.distance_to(b)
	if length < 0.001:
		return
	var d := (b - a) / length
	for pc in MeshMapGeometry.wall_pieces(ext0, length + ext1, y0, y1, cuts):
		if pc[1] - pc[0] < 0.001 or pc[3] - pc[2] < 0.001:
			continue
		out.append({"c": a + d * ((pc[0] + pc[1]) * 0.5), "u": d, "hu": (pc[1] - pc[0]) * 0.5, "hv": t * 0.5,
			"y0": float(pc[2]), "y1": float(pc[3])})


## Intervalles pleins (m, triés) de la droite `o + dir * s` à la hauteur
## `y` ; `merge` : intervalles qui se touchent ou se chevauchent fusionnés.
static func spans(rects: Array, o: Vector2, dir: Vector2, y: float, merge := true) -> Array[Vector2]:
	var raw: Array[Vector2] = []
	for r in rects:
		if y <= float(r.y0) or y >= float(r.y1):
			continue
		var u: Vector2 = r.u
		var v := Vector2(-u.y, u.x)
		var rel: Vector2 = o - r.c
		var lo := -INF
		var hi := INF
		var empty := false
		for ax in [[u, float(r.hu)], [v, float(r.hv)]]:
			var e: Vector2 = ax[0]
			var h: float = ax[1]
			var p0 := rel.dot(e)
			var dd := dir.dot(e)
			if absf(dd) < 1e-9:
				if absf(p0) > h:
					empty = true
				continue
			var t1 := (-h - p0) / dd
			var t2 := (h - p0) / dd
			lo = maxf(lo, minf(t1, t2))
			hi = minf(hi, maxf(t1, t2))
		if not empty and hi - lo > 1e-4:
			raw.append(Vector2(lo, hi))
	raw.sort_custom(func(p, q): return p.x < q.x)
	if not merge:
		return raw
	var merged: Array[Vector2] = []
	for s in raw:
		if not merged.is_empty() and s.x <= merged[-1].y + JOIN:
			merged[-1].y = maxf(merged[-1].y, s.y)
		else:
			merged.append(s)
	return merged


## Section du mur percé, le long de inward_dir depuis o.pos : (face côté
## dehors, face côté salle). Fenêtre : mesurée dans l'allège, sous
## l'ouverture (le mur lui-même, jamais un mur voisin) ; porte (pas
## d'allège) : à côté de l'ouverture, la plus mince des deux mesures (un mur
## perpendiculaire collé au bord ne compte pas). Vector2.ZERO : introuvable.
static func wall_section(rects: Array, o: BarricadeLayout.Opening) -> Vector2:
	var p := Vector2(o.pos.x, o.pos.z)
	var inn := Vector2(o.inward_dir.x, o.inward_dir.z).normalized()
	var side := Vector2(-inn.y, inn.x)
	var probes := []
	if not BarricadeRules.is_door(o.kind):
		probes.append([p, o.pos.y + Barricade.SILL_TOP * 0.5])
	for s in [1.0, -1.0]:
		probes.append([p + side * s * (o.width * 0.5 + 0.15), o.pos.y + 1.0])
	var best := Vector2.ZERO
	for pr in probes:
		var sec := _around_zero(spans(rects, pr[0], inn, pr[1], false))
		if sec == Vector2.ZERO:
			continue
		if best == Vector2.ZERO or sec.y - sec.x < best.y - best.x:
			best = sec
		if pr[1] < o.pos.y + 0.9:
			return sec   # allège d'une fenêtre : la mesure de référence
	return best


## Épaisseur du mur autour de 0 : le pavé qui contient 0 (ou le plus
## proche, à moins de 0,6 m ; à égalité le plus mince), prolongé des pavés
## qui le BOUTENT (demi-cases de l'éditeur, une texture par face). Un pavé
## qui le chevauche est un autre ouvrage (mur de la poche d'une fenêtre de
## KINO, plaqué contre la face extérieure) : pas compté.
static func _around_zero(list: Array[Vector2]) -> Vector2:
	var best := Vector2.ZERO
	var best_key := Vector2(0.6, INF)
	for s in list:
		var key := Vector2(0.0 if (s.x <= 0.0 and s.y >= 0.0) else minf(absf(s.x), absf(s.y)), s.y - s.x)
		if key.x < best_key.x - 1e-6 or (key.x <= best_key.x + 1e-6 and key.y < best_key.y):
			best = s
			best_key = key
	if best == Vector2.ZERO:
		return best
	var grown := true
	while grown:
		grown = false
		for s in list:
			if absf(s.x - best.y) <= JOIN and s.y > best.y + 1e-4:
				best.y = s.y
				grown = true
			elif absf(s.y - best.x) <= JOIN and s.x < best.x - 1e-4:
				best.x = s.x
				grown = true
	return best


## Découpe du mur à mi-hauteur de l'ouverture, de part et d'autre de o.pos,
## le long de l'axe X local de la barricade (Barricade : rotation.y =
## atan2(inward.x, inward.z), donc X = (inward.z, -inward.x)) : Vector2(bord
## côté -X (<= 0), bord côté +X (>= 0)). Ouverture décalée de son repère : la
## barrière couvre toute la découpe réelle, pas deux fois le plus petit côté
## (il restait un jour latéral par où un zombie passait). ZERO : introuvable.
static func cut_span(rects: Array, o: BarricadeLayout.Opening) -> Vector2:
	var p := Vector2(o.pos.x, o.pos.z)
	var inn := Vector2(o.inward_dir.x, o.inward_dir.z).normalized()
	var ax := Vector2(inn.y, -inn.x)
	var y := o.pos.y + (1.0 if BarricadeRules.is_door(o.kind) else (Barricade.SILL_TOP + Barricade.LINTEL_BOTTOM) * 0.5)
	var side := [INF, INF]
	for k in 2:
		for sp in spans(rects, p, ax * (1.0 if k == 1 else -1.0), y):
			if sp.y > 0.0:
				side[k] = maxf(sp.x, 0.0)
				break
	var lo: float = side[0]
	var hi: float = side[1]
	if lo == INF or hi == INF or lo > o.width or hi > o.width or lo + hi < o.width * 0.5:
		return Vector2.ZERO
	return Vector2(-lo, hi)


## Largeur découpée dans le mur (cut_span) ; 0 : introuvable.
static func cut_width(rects: Array, o: BarricadeLayout.Opening) -> float:
	var s := cut_span(rects, o)
	return s.y - s.x
