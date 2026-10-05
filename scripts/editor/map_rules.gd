class_name MapRules
extends RefCounted
## Règles de pose de l'éditeur de cartes : chaque fonction dit si un élément
## peut être posé là et, sinon, POURQUOI ({ok, fr, en}) ; si oui, elle rend la
## position accrochée (au mur commun, au mur extérieur, contre le mur...).
##   - porte, débris, porte du courant, passage : sur le bord COMMUN de deux
##     pièces collées du même étage ; elle relie exactement ces deux pièces ;
##   - fenêtre : sur un mur extérieur, avec la place des zombies dehors ;
##   - objet mural : contre un mur de la pièce, face vers l'intérieur ;
##   - objet au sol, pilier, escalier, piège : à l'intérieur d'une pièce, sans
##     chevauchement (format 9 : réglage de la carte « chevauchement_decor »,
##     le décor et les piliers peuvent se chevaucher entre eux) ;
##   - barrière invisible (format 9, polygone) : n'importe où (check_clip).
## Le validateur (MapValidator) revérifie tout à la fin (onglet Vérification).

## Distance maximale du curseur au mur visé (m).
const SNAP_DIST := 1.6
## Mur plein laissé à chaque bout d'une ouverture (m).
const END_MARGIN := 0.5
const MIN_ROOM_SIDE := 1.5
## Cour des zombies derrière une fenêtre (m) : profondeur, largeur.
const POCKET := Vector2(2.75, 3.0)


static func refuse(fr: String, en: String) -> Dictionary:
	return {"ok": false, "fr": fr, "en": en}


static func why(r: Dictionary) -> String:
	return Lang.t(String(r.get("fr", "")), String(r.get("en", "")))


static func _name(o: Dictionary) -> Array:
	if o.has("contour"):
		return [String(o.get("nom", "pièce")), String(o.get("nom", "room"))]
	var it := MapCatalog.item_for(o)
	return [String(it.get("fr", o.get("type", ""))), String(it.get("en", o.get("type", "")))]


# ------------------------------------------------------------------ pièces

## `overlap_ok` : les pièces recouvertes ne comptent pas (pièce tracée par-dessus
## d'autres : elles seront découpées après confirmation, MapCarve). `alt` :
## altitude de la pièce (absente : celle du niveau `k`).
static func check_room(doc: EditorMap, k: int, poly: PackedVector2Array, ignore_id := "", overlap_ok := false, alt := NAN) -> Dictionary:
	if poly.size() < 3 or not MapGeom.is_simple(poly):
		return refuse("contour invalide : ses côtés se croisent", "invalid outline: its sides cross")
	if poly.size() > CustomMapGuard.MAX_VERTICES:
		return refuse("trop de sommets (%d au plus)" % CustomMapGuard.MAX_VERTICES, "too many vertices (%d at most)" % CustomMapGuard.MAX_VERTICES)
	for i in poly.size():
		if poly[i].distance_to(poly[(i + 1) % poly.size()]) < 0.1:
			return refuse("côté trop court (10 cm au moins)", "side too short (at least 10 cm)")
	var bb := MapGeom.bbox(poly)
	# Format 17 : coordonnées libres (négatives comprises), aucune étendue
	# maximale ; seule garde technique : la grille du validateur doit tenir en
	# mémoire (CustomMapGuard.grid_ok).
	if not (is_finite(bb.position.x) and is_finite(bb.position.y) and is_finite(bb.end.x) and is_finite(bb.end.y)):
		return refuse("coordonnées invalides", "invalid coordinates")
	if not CustomMapGuard.grid_ok(_grid_bytes(bb)):
		return refuse("pièce trop grande pour la mémoire du validateur", "room too large for the validator's memory")
	if bb.size.x < MIN_ROOM_SIDE or bb.size.y < MIN_ROOM_SIDE or MapGeom.area(poly) < 2.0:
		return refuse("pièce trop petite (1,5 m de côté au moins)", "room too small (at least 1.5 m per side)")
	# Niveaux libres (format 17) : une pièce d'une autre altitude qu'elle
	# recouvre en plan est à MIN_STACK m au moins (au-dessus comme en dessous) ;
	# côte à côte, n'importe quel écart. Même avec `overlap_ok` (découpe :
	# seulement à la même altitude).
	var a := doc.level_alt(k) if is_nan(alt) else alt
	for p in doc.pieces:
		var d := absf(EditorMap.alt_of(p) - a)
		if String(p.id) == ignore_id or d <= EditorMap.ALT_EQ or d >= EditorMap.MIN_STACK - EditorMap.ALT_EQ:
			continue
		if MapGeom.overlap(poly, doc.room_poly(p)):
			return refuse("elle recouvre la pièce « %s » à %s d'écart : il faut %s au moins entre deux pièces empilées (hauteur sous plafond 2,8 m + dalle) ; côte à côte, n'importe quelle altitude" % [p.get("nom", p.id), EditorMap.alt_text(d), EditorMap.alt_text(EditorMap.MIN_STACK)],
				"it overlaps room \"%s\" %s apart: stacked rooms must be at least %s apart (2.8 m ceiling + slab); side by side, any altitude" % [p.get("nom", p.id), EditorMap.alt_text(d, false), EditorMap.alt_text(EditorMap.MIN_STACK, false)])
	if overlap_ok:
		return {"ok": true}
	for p in doc.pieces:
		if absf(EditorMap.alt_of(p) - a) > EditorMap.ALT_EQ:
			continue
		if String(p.id) != ignore_id and MapGeom.overlap(poly, doc.room_poly(p)):
			return refuse("elle chevauche la pièce « %s » (deux pièces peuvent se toucher, pas se recouvrir)" % p.get("nom", p.id),
				"it overlaps room \"%s\" (rooms may touch, not overlap)" % p.get("nom", p.id))
	return {"ok": true}


## Mémoire (octets) de la grille du validateur pour un seul niveau couvrant
## `bb` (m) : garde technique des grandes formes (CustomMapGuard.grid_ok).
static func _grid_bytes(bb: Rect2) -> int:
	return CustomMapGuard.extent_bytes(bb.size, 1)


## Bords communs de deux pièces collées de l'étage : [{a, b, rooms: [id, id],
## grid}] ; `grid` : le bord est construit en blocs de la grille (il longe un
## côté de la grille de l'une des deux pièces), sinon c'est un mur oblique.
static func shared_edges(doc: EditorMap, k: int) -> Array:
	var out := []
	var rooms := doc.rooms_on(k)
	var polys := rooms.map(func(r): return doc.room_poly(r))
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			for s in MapGeom.common_segments(polys[i], polys[j]):
				var grid := on_grid_edge(polys[i], s[0], s[1]) or on_grid_edge(polys[j], s[0], s[1])
				out.append({"a": s[0], "b": s[1], "rooms": [String(rooms[i].id), String(rooms[j].id)], "grid": grid})
	return out


## Le segment [a, b] longe-t-il (à JOIN_TOL près) un côté de la grille du contour ?
static func on_grid_edge(poly: PackedVector2Array, a: Vector2, b: Vector2) -> bool:
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		if MapGeom.is_grid_seg(p, q) and MapGeom.dist_to_segment(a, p, q) <= MapGeom.JOIN_TOL \
				and MapGeom.dist_to_segment(b, p, q) <= MapGeom.JOIN_TOL:
			return true
	return false


## Point juste de l'autre côté d'un bord (normale sortante de la pièce).
static func _outside(poly: PackedVector2Array, a: Vector2, b: Vector2, d := 0.3) -> Vector2:
	var m := (a + b) * 0.5
	var t := (b - a).normalized()
	var n := Vector2(-t.y, t.x)
	return m + n * d if not MapGeom.contains(poly, m + n * d) else m - n * d


## Bords extérieurs des pièces de l'étage (ni communs, ni au-dessus du vide
## d'une double hauteur) : [{a, b, room}].
static func outer_edges(doc: EditorMap, k: int) -> Array:
	var out := []
	var rooms := doc.rooms_on(k)
	var voids := []
	for p in doc.rooms_through(k):
		voids.append(doc.room_poly(p))
	for r in rooms:
		var poly := doc.room_poly(r)
		for i in poly.size():
			var pieces := [[poly[i], poly[(i + 1) % poly.size()]]]
			for q in rooms:
				if q == r:
					continue
				var next := []
				for pc in pieces:
					next.append_array(_subtract(pc[0], pc[1], MapGeom.edge_common(pc[0], pc[1], doc.room_poly(q))))
				pieces = next
			var grid := MapGeom.is_grid_seg(poly[i], poly[(i + 1) % poly.size()])
			for pc in pieces:
				var outside := _outside(poly, pc[0], pc[1])
				if voids.any(func(vp): return MapGeom.strictly_inside(vp, outside)):
					continue
				out.append({"a": pc[0], "b": pc[1], "room": String(r.id), "grid": grid})
	return out


## [a, b] moins des sous-segments colinéaires -> morceaux restants.
static func _subtract(a: Vector2, b: Vector2, cuts: Array) -> Array:
	var d := b - a
	var len2 := d.length_squared()
	if len2 < 1e-9:
		return []
	var iv := []
	for c in cuts:
		var t0 := clampf((c[0] - a).dot(d) / len2, 0.0, 1.0)
		var t1 := clampf((c[1] - a).dot(d) / len2, 0.0, 1.0)
		iv.append([minf(t0, t1), maxf(t0, t1)])
	iv.sort()
	var out := []
	var t := 0.0
	for p in iv:
		if p[0] > t + 1e-6:
			out.append([a + d * t, a + d * p[0]])
		t = maxf(t, p[1])
	if t < 1.0 - 1e-6:
		out.append([a + d * t, b])
	return out


# ------------------------------------------------------------------ ouvertures

## Largeur (m) d'une ouverture. Entrée des zombies : celle de son type
## (fenêtre et porte simple 1 m, porte double 2 m ; format 8).
static func opening_width(o: Dictionary) -> float:
	if String(o.get("type", "")) == "fenetre":
		return MapCatalog.barricade_width(MapCatalog.barricade_kind(o))
	return float(o.get("largeur", 2.0))


## Change le type d'une entrée des zombies (ou la variante de tout autre
## élément) si elle tient encore à sa place (une porte double est plus large) :
## position recalée le long du mur ; sinon {ok: false, fr, en}, rien changé.
static func apply_variant(doc: EditorMap, o: Dictionary, v: String) -> Dictionary:
	if String(o.get("type", "")) != "fenetre":
		return {"ok": MapCatalog.set_variant(o, v)}
	var cand := o.duplicate(true)
	if not MapCatalog.set_variant(cand, v):
		return refuse("type inconnu", "unknown type")
	var res := place_opening(doc, doc.level_of(o), "fenetre", MapGeom.v2(o.position), opening_width(cand), String(o.get("id", "")))
	if not res.ok:
		return res
	MapCatalog.set_variant(o, v)
	o["position"] = res.position
	return {"ok": true}


## Ouverture : axe du mur (true : horizontal, y constant) et intervalle le long.
static func opening_span(o: Dictionary, horizontal: bool) -> Vector2:
	var p := MapGeom.v2(o.position)
	var w := maxi(1, roundi(opening_width(o) / MapGeom.CELL)) * MapGeom.CELL
	var along := p.x if horizontal else p.y
	return Vector2(along - w * 0.5, along + w * 0.5)


## Pose d'une ouverture de type `type`, de largeur `width`, près de `mouse`.
## -> {ok, position, rooms, horizontal} ou {ok: false, fr, en}. `shrink` (pose
## à la souris) : sur un mur trop court (côté d'un cercle...), la porte est
## réduite par pas de 0,5 m jusqu'à 1 m pour y tenir (clé « largeur » du résultat).
static func place_opening(doc: EditorMap, k: int, type: String, mouse: Vector2, width: float, ignore_id := "", shrink := false) -> Dictionary:
	if shrink and type != "fenetre":
		var first := place_opening(doc, k, type, mouse, width, ignore_id)
		if first.ok:
			return first
		var w2 := width - MapGeom.CELL
		while w2 >= 1.0 - MapGeom.EPS:
			var r2 := place_opening(doc, k, type, mouse, w2, ignore_id)
			if r2.ok:
				r2["largeur"] = w2
				return r2
			w2 -= MapGeom.CELL
		return first
	var window := type == "fenetre"
	var cands := outer_edges(doc, k) if window else shared_edges(doc, k)
	var best: Variant = null
	var best_d := SNAP_DIST
	for e in cands:
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var d := MapGeom.dist_to_segment(mouse, a, b)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		if window:
			return refuse("une fenêtre se pose sur un mur extérieur d'une pièce (visez le bord de la pièce, côté dehors)",
				"a window goes on an outer wall of a room (aim at the room's edge, outside side)")
		if doc.rooms_on(k).size() < 2 or shared_edges(doc, k).is_empty():
			return refuse("une porte relie deux pièces : il faut deux pièces collées (un bord commun) à ce niveau (même altitude)",
				"a door links two rooms: you need two touching rooms (a shared edge) on this level (same altitude)")
		return refuse("visez le mur commun de deux pièces collées : une porte ne donne que sur une autre pièce",
			"aim at the shared wall of two touching rooms: a door only leads into another room")
	var a: Vector2 = best.a
	var b: Vector2 = best.b
	if not bool(best.get("grid", MapGeom.is_grid_seg(a, b))):
		return _place_opening_oblique(doc, k, window, mouse, width, best, ignore_id)
	var horizontal := absf(a.y - b.y) < MapGeom.JOIN_TOL
	var n := maxi(1, roundi(width / MapGeom.CELL))
	var w := n * MapGeom.CELL
	var lo := minf(a.x, b.x) if horizontal else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if horizontal else maxf(a.y, b.y)
	if hi - lo < w + 2.0 * END_MARGIN - MapGeom.EPS:
		return refuse("ce mur est trop court pour une ouverture de %s m (il faut %s m de mur, 0,5 m de chaque côté)" % [_m(w), _m(w + 2.0 * END_MARGIN)],
			"this wall is too short for a %s m opening (%s m of wall needed, 0.5 m on each side)" % [_m(w, false), _m(w + 2.0 * END_MARGIN, false)])
	var along := MapGeom.snap_along(mouse.x if horizontal else mouse.y, n)
	var min_c := MapGeom.snap_along(lo + END_MARGIN + w * 0.5 + 0.01, n)
	if min_c - w * 0.5 < lo + END_MARGIN - MapGeom.EPS:
		min_c += MapGeom.CELL
	var max_c := MapGeom.snap_along(hi - END_MARGIN - w * 0.5 - 0.01, n)
	if max_c + w * 0.5 > hi - END_MARGIN + MapGeom.EPS:
		max_c -= MapGeom.CELL
	along = clampf(along, min_c, max_c)
	# Trait du mur de la grille (une pièce collée sans grille peut en être à
	# quelques millimètres).
	var line := snappedf(a.y if horizontal else a.x, MapGeom.CELL)
	var pos := Vector2(along, line) if horizontal else Vector2(line, along)
	var span := Vector2(along - w * 0.5, along + w * 0.5)
	# Autres ouvertures du même mur : 0,5 m de mur entre deux ouvertures.
	for o in doc.openings_on(k):
		if String(o.id) == ignore_id:
			continue
		var op := MapGeom.v2(o.position)
		if absf((op.y if horizontal else op.x) - line) > MapGeom.EPS or _on_oblique_wall(doc, k, op):
			continue
		var s := opening_span(o, horizontal)
		if s.x < span.y + END_MARGIN - MapGeom.EPS and s.y > span.x - END_MARGIN + MapGeom.EPS:
			var nm := _name(o)
			return refuse("trop près d'une autre ouverture (%s) : laissez 0,5 m de mur entre les deux" % nm[0].to_lower(),
				"too close to another opening (%s): leave 0.5 m of wall between them" % nm[1].to_lower())
	# Objets muraux contre ce mur à cet endroit.
	for o in doc.objects_on(k):
		if MapCatalog.tool_of(o) != "wall_item" or MapGeom.item_oblique(o):
			continue
		var d := String(o.get("mur", "n"))
		var op := MapGeom.v2(o.position)
		if (d in ["n", "s"]) != horizontal or absf((op.y if horizontal else op.x) - line) > MapGeom.EPS:
			continue
		var half := MapScale.foot_m(o).x * 0.5
		var oc := op.x if horizontal else op.y
		if oc - half < span.y - MapGeom.EPS and oc + half > span.x + MapGeom.EPS:
			var nm := _name(o)
			return refuse("%s est contre ce mur à cet endroit" % nm[0], "%s stands against this wall here" % nm[1])
	var res := {"ok": true, "position": MapGeom.arr(pos), "horizontal": horizontal}
	if window:
		res["rooms"] = [best.room]
		# Cour des zombies : du vide dehors (aucune pièce).
		var poly := doc.room_poly(doc.find(best.room))
		var out_dir := (_outside(poly, a, b, 0.3) - (a + b) * 0.5).normalized()
		var side := Vector2(1, 0) if horizontal else Vector2(0, 1)
		# Cour : 1 m de plus que l'ouverture de chaque côté (porte double : 4 m).
		var pw := pocket_width(w)
		var c0 := pos + out_dir * 0.3 - side * pw * 0.5
		var c1 := pos + out_dir * POCKET.x + side * pw * 0.5
		var pocket := MapGeom.rect_poly(Rect2(c0, Vector2.ZERO).expand(c1))
		for q in doc.rooms_on(k):
			if MapGeom.overlap(pocket, doc.room_poly(q)):
				return refuse("pas de place dehors pour les zombies : il faut 2,5 m × %s m de vide derrière la fenêtre (gêné par « %s »)" % [_m(pw), q.get("nom", q.id)],
					"no room outside for the zombies: 2.5 m × %s m of empty space is needed behind the window (blocked by \"%s\")" % [_m(pw, false), q.get("nom", q.id)])
	else:
		res["rooms"] = best.rooms
	return res


## Côté de pièce de l'étage qui passe par `p` : [a, b] (le premier trouvé),
## [] sinon.
static func edge_through(doc: EditorMap, k: int, p: Vector2, tol := 0.01) -> Array:
	for r in doc.rooms_on(k):
		var poly := doc.room_poly(r)
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if MapGeom.dist_to_segment(p, a, b) <= tol:
				return [a, b]
	return []


## `p` est-il sur un mur en biais (et sur aucun mur droit) ?
static func _on_oblique_wall(doc: EditorMap, k: int, p: Vector2) -> bool:
	var oblique := false
	for r in doc.rooms_on(k):
		var poly := doc.room_poly(r)
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if MapGeom.dist_to_segment(p, a, b) <= 0.01:
				if MapGeom.is_grid_seg(a, b):
					return false
				oblique = true
	return oblique


## Distance de `p` à la droite (a, direction unitaire t).
static func _line_dist(p: Vector2, a: Vector2, t: Vector2) -> float:
	return absf((p - a).dot(Vector2(-t.y, t.x)))


## Ouverture sur un mur EN BIAIS (côté de pièce oblique) : même règles que sur
## un mur droit (0,5 m de mur à chaque bout et entre deux ouvertures, rien
## d'accroché au mur à cet endroit, place dehors pour la cour d'une fenêtre),
## le long du mur ; le milieu est aimanté (grille de 0,25 m sur un côté à 45°).
static func _place_opening_oblique(doc: EditorMap, k: int, window: bool, mouse: Vector2, width: float, best: Dictionary, ignore_id: String) -> Dictionary:
	var a: Vector2 = best.a
	var b: Vector2 = best.b
	var seg_len := a.distance_to(b)
	var t := (b - a) / seg_len
	var w := maxi(1, roundi(width / MapGeom.CELL)) * MapGeom.CELL
	var s := MapGeom.snap_on_segment(a, b, (mouse - a).dot(t), w, END_MARGIN)
	if s < 0.0:
		return refuse("ce mur est trop court pour une ouverture de %s m (il faut %s m de mur, 0,5 m de chaque côté)" % [_m(w), _m(w + 2.0 * END_MARGIN)],
			"this wall is too short for a %s m opening (%s m of wall needed, 0.5 m on each side)" % [_m(w, false), _m(w + 2.0 * END_MARGIN, false)])
	var pos := a + t * s
	for o in doc.openings_on(k):
		if String(o.id) == ignore_id:
			continue
		var op := MapGeom.v2(o.position)
		if _line_dist(op, a, t) > MapGeom.JOIN_TOL:
			continue
		var oc := (op - a).dot(t)
		var ow := opening_width(o) * 0.5
		if oc - ow < s + w * 0.5 + END_MARGIN - MapGeom.EPS and oc + ow > s - w * 0.5 - END_MARGIN + MapGeom.EPS:
			var nm := _name(o)
			return refuse("trop près d'une autre ouverture (%s) : laissez 0,5 m de mur entre les deux" % nm[0].to_lower(),
				"too close to another opening (%s): leave 0.5 m of wall between them" % nm[1].to_lower())
	for o in doc.objects_on(k):
		if MapCatalog.tool_of(o) != "wall_item":
			continue
		var op := MapGeom.v2(o.position)
		if _line_dist(op, a, t) > MapGeom.JOIN_TOL or absf(MapGeom.item_wall_dir(o).dot(t)) > 0.05:
			continue
		var half := MapScale.foot_m(o).x * 0.5
		var oc := (op - a).dot(t)
		if oc - half < s + w * 0.5 - MapGeom.EPS and oc + half > s - w * 0.5 + MapGeom.EPS:
			var nm := _name(o)
			return refuse("%s est contre ce mur à cet endroit" % nm[0], "%s stands against this wall here" % nm[1])
	var res := {"ok": true, "position": MapGeom.arr(pos), "horizontal": false, "dir": [t.x, t.y]}
	if window:
		res["rooms"] = [best.room]
		var poly := doc.room_poly(doc.find(best.room))
		var out_dir := (_outside(poly, a, b, 0.3) - (a + b) * 0.5).normalized()
		var pocket := pocket_poly(pos, out_dir, w)
		var pw := pocket_width(w)
		for q in doc.rooms_on(k):
			if MapGeom.overlap(pocket, doc.room_poly(q)):
				return refuse("pas de place dehors pour les zombies : il faut 2,5 m × %s m de vide derrière la fenêtre (gêné par « %s »)" % [_m(pw), q.get("nom", q.id)],
					"no room outside for the zombies: 2.5 m × %s m of empty space is needed behind the window (blocked by \"%s\")" % [_m(pw, false), q.get("nom", q.id)])
	else:
		res["rooms"] = best.rooms
	return res


## Largeur (m) de la cour des zombies derrière une entrée de largeur `w` :
## 1 m de plus de chaque côté (fenêtre et porte simple : 3 m ; double : 4 m).
static func pocket_width(w: float) -> float:
	return POCKET.y + w - 1.0


## Cour des zombies derrière une fenêtre en `pos` (sur le trait), `out_dir`
## vers dehors : 3 m le long du mur (porte double : 4 m), de 0,3 à 2,75 m du trait.
static func pocket_poly(pos: Vector2, out_dir: Vector2, w := 1.0) -> PackedVector2Array:
	return MapGeom.oriented_rect(pos + out_dir * 0.3, out_dir, pocket_width(w), POCKET.x - 0.3)


static func _m(v: float, fr := true) -> String:
	var s := ("%.2f" % v).trim_suffix("0").trim_suffix("0").trim_suffix(".")
	return s.replace(".", ",") if fr else s


# ------------------------------------------------------------------ objets

## Pièce de l'étage qui contient `p` (strictement à l'intérieur), {} sinon.
static func room_at(doc: EditorMap, k: int, p: Vector2) -> Dictionary:
	for r in doc.rooms_on(k):
		if MapGeom.contains(doc.room_poly(r), p):
			return r
	return {}


## Pièce de l'étage dont le sol touche l'emprise `poly` (décor posé à cheval
## sur un mur) : celle qui en couvre le plus de coins et le centre, {} sinon.
static func room_touching(doc: EditorMap, k: int, poly: PackedVector2Array) -> Dictionary:
	var best := {}
	var best_n := 0
	var pts := Array(poly)
	pts.append(MapGeom.centroid(poly))
	for r in doc.rooms_on(k):
		var rp := doc.room_poly(r)
		if not MapGeom.overlap(rp, poly):
			continue
		var n := 1
		for p in pts:
			if MapGeom.contains(rp, p):
				n += 1
		if n > best_n:
			best_n = n
			best = r
	return best


## Emprise (m) d'un élément posé, pour le dessin, le clic et les chevauchements.
static func footprint_rect(o: Dictionary) -> Rect2:
	var t := String(o.get("type", ""))
	if t == "bloc_invisible":
		return MapGeom.bbox(MapRaster.clip_poly(o))
	if t == "effet":
		return MapGeom.bbox(effect_poly(o))
	if o.has("rect"):
		if MapGeom.rot_of(o) != 0:
			return MapGeom.bbox(MapRaster.rect_poly(o))
		return MapGeom.rect_of(o.rect)
	if t == "mur":
		var half := float(o.get("epaisseur", 0.5)) * 0.5
		return Rect2(MapGeom.v2(o.a), Vector2.ZERO).expand(MapGeom.v2(o.b)).grow(half)
	if t == "mur_courbe":
		return MapGeom.bbox(MapShapes.wall_arc(o)).grow(float(o.get("epaisseur", 0.5)) * 0.5)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	var tool := MapCatalog.tool_of(o)
	if tool == "floor_item" and MapRaster.free_rot(o) and MapCatalog.rotates(o):
		return MapGeom.bbox(MapRaster.floor_poly(o))
	if tool == "wall_item" and MapGeom.item_oblique(o):
		# Contre un mur en biais : rectangle englobant de l'emprise tournée.
		return MapGeom.bbox(wall_item_poly(o))
	if tool == "wall_item":
		var d := MapGeom.dir_vec(String(o.get("mur", "n")))
		# Format 14 : emprise d'un décor mural mis à l'échelle (MapScale).
		var fm := MapScale.foot_m(o)
		var along := fm.x
		var depth := fm.y
		# Face du mur à 0,25 m du trait, objet devant (côté intérieur).
		var face := p - d * MapGeom.CELL * 0.5
		var back := face - d * depth
		var lat := Vector2(absf(d.y), absf(d.x)) * along * 0.5
		return Rect2(face - lat, Vector2.ZERO).expand(back + lat)
	var n := MapCatalog.floor_size(o)
	var s := Vector2(n) * MapGeom.CELL
	return Rect2(p - s * 0.5, s)


## Emprise exacte (4 sommets, m) d'un objet mural : de la face du mur (0,25 m
## du trait, côté pièce) vers l'intérieur, sur sa largeur le long du mur.
static func wall_item_poly(o: Dictionary) -> PackedVector2Array:
	if String(o.get("type", "")) == "effet":
		return effect_poly(o)
	var fm := MapScale.foot_m(o)
	var dv := MapGeom.item_wall_dir(o)
	var face := MapGeom.v2(o.get("position", [0, 0])) - dv * MapGeom.WALL_HALF
	return MapGeom.oriented_rect(face, -dv, fm.x, fm.y)


## Format 11 : zone d'un effet (m), le rectangle qu'il remplit : au sol et au
## plafond, largeur × profondeur centrées sur sa position, tournées de
## « rot » ; mural, sur la face du mur (0,25 m du trait), largeur le long du
## mur et sa portée dans la pièce.
static func effect_poly(o: Dictionary) -> PackedVector2Array:
	var z := MapCatalog.effect_zone(o)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	if MapCatalog.effect_mount(o) == "mur":
		var dv := MapGeom.item_wall_dir(o)
		return MapGeom.oriented_rect(p - dv * MapGeom.WALL_HALF, -dv, z.x, z.y)
	return MapGeom.rot_rect_poly(p, Vector2(z.x, z.y), MapGeom.rot_of(o))


## Reporte le mur visé d'un résultat de pose (place_wall_item) sur l'objet :
## « mur » (n, e, s, o) et, contre un mur en biais, « angle ».
static func apply_wall(o: Dictionary, res: Dictionary) -> void:
	o["mur"] = String(res.get("mur", o.get("mur", "n")))
	if res.has("angle"):
		o["angle"] = res.angle
	else:
		o.erase("angle")


## L'élément `o` couvre-t-il le point `p` (clic, gomme) ?
static func hit(doc: EditorMap, o: Dictionary, p: Vector2) -> bool:
	if o.has("contour"):
		return MapGeom.contains(doc.room_poly(o), p)
	if String(o.get("type", "")) == "bloc_invisible":
		var cp := MapRaster.clip_poly(o)
		return MapGeom.contains(cp, p) or MapGeom.on_boundary(cp, p, 0.05)
	if String(o.get("type", "")) == "mur":
		return MapGeom.dist_to_segment(p, MapGeom.v2(o.a), MapGeom.v2(o.b)) <= maxf(0.3, float(o.get("epaisseur", 0.5)) * 0.5)
	if String(o.get("type", "")) == "mur_courbe":
		var half := maxf(0.3, float(o.get("epaisseur", 0.5)) * 0.5)
		return MapShapes.arc_segments(o).any(func(s): return MapGeom.dist_to_segment(p, s[0], s[1]) <= half)
	if o.has("position") and not o.has("rect") and ouvertures_types().has(String(o.get("type", ""))):
		return MapGeom.v2(o.position).distance_to(p) <= maxf(0.5, opening_width(o) * 0.5)
	if String(o.get("type", "")) == "effet":
		# Format 11 : toute la zone de l'effet (tournée).
		var ep := effect_poly(o)
		return MapGeom.contains(ep, p) or MapGeom.on_boundary(ep, p, 0.05)
	if MapGeom.item_oblique(o) and MapCatalog.tool_of(o) == "wall_item":
		var poly := wall_item_poly(o)
		return MapGeom.contains(poly, p) or MapGeom.on_boundary(poly, p, 0.05)
	if o.has("rect") and MapGeom.rot_of(o) != 0:
		var poly := MapRaster.rect_poly(o)
		return MapGeom.contains(poly, p) or MapGeom.on_boundary(poly, p, 0.05)
	if MapCatalog.tool_of(o) == "floor_item" and MapRaster.free_rot(o) and MapCatalog.rotates(o):
		var poly := MapRaster.floor_poly(o)
		return MapGeom.contains(poly, p) or MapGeom.on_boundary(poly, p, 0.05)
	return footprint_rect(o).grow(0.05).has_point(p)


static func ouvertures_types() -> Array:
	return ["porte", "debris", "porte_courant", "passage", "fenetre"]


## Couche d'un objet pour les chevauchements : « plafond » (lampes et
## luminaires du plafond), « mur_haut » (appliques, à 2 m) ou « sol » (tout le
## reste). Deux objets ne se gênent que dans la même couche.
static func layer_of(o: Dictionary) -> String:
	match MapCatalog.light_mount(o):
		"plafond":
			return "plafond"
		"mur":
			return "mur_haut"
	return "sol"


## Vérification en série (onglet d'état de toute la carte) : emprises des
## objets calculées une fois et rangées par cases de 4 m (sinon chaque
## vérification relit tous les objets : lent avec 2000 éléments).
const BUCKET := 4.0
static var _batch: Dictionary = {}   # étage -> {Vector2i: [[objet, emprise, couche]]}
static var _batch_doc: EditorMap = null
static var _batch_lists: Dictionary = {}   # étage -> [escaliers et murs libres]
## Escaliers du lot : [[escalier, altitude du pied, altitude d'arrivée]].
static var _batch_stairs: Array = []


static func begin_batch(doc: EditorMap) -> void:
	if not ThreadGuard.main_only("MapRules.begin_batch"):   # fil principal seulement
		return
	if _batch_doc != null:
		_batch_doc.thaw_levels()
	_batch = {}
	_batch_doc = doc
	doc.freeze_levels()
	_floor_bases = {}   # étages lus par les contrôles d'escaliers (_stair_floor_base)
	_batch_stairs = []
	_batch_lists = {}
	for o in doc.objets:
		var t := String(o.get("type", ""))
		if t == "escalier" or t == "mur" or t == "mur_courbe":
			# Escaliers et murs libres par étage (contrôles d'escaliers).
			(_batch_lists.get_or_add(doc.level_of(o), []) as Array).append(o)
		if t == "escalier":
			# Format 17 : pied et arrivée (trémies des niveaux traversés).
			_batch_stairs.append([o, EditorMap.alt_of(o), doc.stair_top_of(o)])
		if t in NO_OVERLAP_CHECK:
			continue
		var r := footprint_rect(o)
		var e := [o, r, layer_of(o)]
		var grid: Dictionary = _batch.get_or_add(doc.level_of(o), {})
		for b in _buckets(r):
			grid.get_or_add(b, []).append(e)


## Escaliers de la carte : [[escalier, altitude du pied, altitude d'arrivée]]
## (hors lot ; pendant un lot : _batch_stairs).
static func _stairs_of(doc: EditorMap) -> Array:
	var out := []
	for o in doc.objets:
		if String(o.get("type", "")) == "escalier":
			out.append([o, EditorMap.alt_of(o), doc.stair_top_of(o)])
	return out


static func end_batch() -> void:
	if not ThreadGuard.main_only("MapRules.end_batch"):   # fil principal seulement
		return
	if _batch_doc != null:
		_batch_doc.thaw_levels()
	_batch = {}
	_batch_doc = null
	_floor_bases = {}
	_batch_lists = {}


static func _buckets(r: Rect2) -> Array:
	var out := []
	for j in range(floori(r.position.y / BUCKET), floori(r.end.y / BUCKET) + 1):
		for i in range(floori(r.position.x / BUCKET), floori(r.end.x / BUCKET) + 1):
			out.append(Vector2i(i, j))
	return out


## Objets de l'étage qui pourraient toucher `r` : [[objet, emprise, couche]].
static func _near(doc: EditorMap, k: int, r: Rect2) -> Array:
	# Fil de travail (aperçu 3D) : jamais le lot du fil principal (état partagé).
	if not ThreadGuard.worker() and _batch_doc == doc:
		var grid: Dictionary = _batch.get(k, {})
		var seen := {}
		var out := []
		for b in _buckets(r):
			for e in grid.get(b, []):
				var eid := String(e[0].get("id", ""))
				if not seen.has(eid):
					seen[eid] = true
					out.append(e)
		return out
	var out := []
	for o in doc.objects_on(k):
		if not String(o.get("type", "")) in NO_OVERLAP_CHECK:
			out.append([o, footprint_rect(o), layer_of(o)])
	return out


## Éléments jamais comptés dans les chevauchements : murs libres (ils ont
## leurs règles) et barrières invisibles (format 9 : posées n'importe où, par
## dessus n'importe quoi, elles ne gênent jamais la pose d'un autre objet) et
## effets (format 10 : sans collision, ils ne gênent rien et rien ne les gêne).
const NO_OVERLAP_CHECK := ["mur", "mur_courbe", "bloc_invisible", "effet"]


## Réglage de la carte (format 9, MapCatalog.OVERLAP_KEY) : le décor et les
## obstacles peuvent-ils se chevaucher ?
static func overlaps_allowed(doc: EditorMap) -> bool:
	return doc != null and bool(doc.carte.get(MapCatalog.OVERLAP_KEY, false))


## Objets que `tmpl` chevauche vraiment : réglage « chevauchement_decor »
## coché, un décor ou un obstacle (MapCatalog.OVERLAP_TYPES) ne compte pas
## les autres décors et obstacles ; les objets de jeu restent comptés.
static func _blocking_overlaps(doc: EditorMap, tmpl: Dictionary, others: Array) -> Array:
	# Effet (format 10) : se pose par-dessus n'importe quoi.
	if String(tmpl.get("type", "")) == "effet":
		return []
	if not (overlaps_allowed(doc) and MapCatalog.may_overlap(tmpl)):
		return others
	return others.filter(func(q): return not MapCatalog.may_overlap(q))


## Premier objet de la couche `layer` qui chevauche `r` ({} sinon).
static func _overlaps(doc: EditorMap, k: int, r: Rect2, ignore_id: String, layer := "sol") -> Dictionary:
	var all := _overlaps_all(doc, k, r, ignore_id, layer)
	return all[0] if not all.is_empty() else {}


static func _overlaps_all(doc: EditorMap, k: int, r: Rect2, ignore_id: String, layer := "sol") -> Array:
	var out := []
	for e in _near(doc, k, r):
		var o: Dictionary = e[0]
		if String(o.get("id", "")) == ignore_id or String(e[2]) != layer:
			continue
		if (e[1] as Rect2).grow(-0.01).intersects(r.grow(-0.01)):
			out.append(o)
	return out


## Hauteur du dessus d'un meuble (m), 0 s'il n'en a pas (un luminaire posé au
## sol peut se poser dessus : lampe de bureau sur un bureau).
static func support_height(o: Dictionary) -> float:
	if String(o.get("type", "")) == "prefab":
		# Format 14 : le dessus monte avec l'échelle ; un décor incliné ne porte rien.
		if not MapScale.carries(o):
			return 0.0
		return float(MapCatalog.def_of(o).get("support", 0.0)) * MapScale.scale_of(o).z
	return 1.0 if String(o.get("type", "")) == "caisse" else 0.0


## Meuble sous un luminaire posé au sol ({} : posé par terre).
static func support_under(doc: EditorMap, o: Dictionary) -> Dictionary:
	var r := footprint_rect(o)
	for other in _overlaps_all(doc, doc.level_of(o), r, String(o.get("id", "")), "sol"):
		if support_height(other) > 0.0:
			return other
	return {}


## Cases intérieures des pièces (contour -> {case: true}), gardées d'une pose à
## l'autre : poser 2000 objets dans une grande pièce ne recalcule pas ses cases.
static var _inner_cache: Dictionary = {}


static func inner_cells(poly: PackedVector2Array) -> Dictionary:
	# Cache du fil principal : hors de lui, calculé sans le cache (et noté).
	var main := ThreadGuard.main_only("MapRules._inner_cache")
	var key := var_to_str(poly)
	if main and _inner_cache.has(key):
		return _inner_cache[key]
	if main and _inner_cache.size() > 2048:
		_inner_cache.clear()
	var inner := {}
	for c in MapRaster.room_cells(poly)[1]:
		inner[c] = true
	if main:
		_inner_cache[key] = inner
	return inner


## Pose d'un objet contre un mur (atout, arme, boîte, Pack-a-Punch...).
## Décor mural (appliques) : place_wall_decor (`grid` : position le long du
## mur au quart de mètre ; sinon au centimètre, là où est le curseur).
static func place_wall_item(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, ignore_id := "", grid := false) -> Dictionary:
	if MapCatalog.is_decor(tmpl):
		return place_wall_decor(doc, k, tmpl, mouse, ignore_id, grid)
	var room := room_at(doc, k, mouse)
	var nm := _name(tmpl)
	if room.is_empty():
		return refuse("%s se pose dans une pièce, contre un de ses murs" % nm[0], "%s goes inside a room, against one of its walls" % nm[1])
	var poly := doc.room_poly(room)
	var best := -1
	var best_d := SNAP_DIST + 0.5
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := MapGeom.dist_to_segment(mouse, a, b)
		if d < best_d:
			best_d = d
			best = i
	# Mur libre (outil Mur, mur courbe) plus proche que les côtés de la pièce :
	# l'objet se pose contre lui, du côté du curseur.
	var segs := free_wall_segments(doc, k)
	var fw := -1
	for i in segs.size():
		var d := _free_wall_dist(mouse, segs[i])
		if d < best_d:
			best_d = d
			fw = i
	if fw >= 0:
		return _place_wall_item_free(doc, k, tmpl, mouse, room, segs, fw, ignore_id)
	if best < 0:
		return refuse("rapprochez-vous d'un mur : %s se pose contre un mur" % nm[0].to_lower(), "move closer to a wall: %s stands against a wall" % nm[1].to_lower())
	var a := poly[best]
	var b := poly[(best + 1) % poly.size()]
	if not MapGeom.is_grid_seg(a, b):
		# Mur en biais ou tracé hors de la grille : vrai mur oblique.
		return _place_wall_item_oblique(doc, k, tmpl, mouse, room, a, b, ignore_id)
	var horizontal := absf(a.y - b.y) < MapGeom.EPS
	var fp := MapCatalog.footprint(tmpl)
	var n := fp.x
	var line := a.y if horizontal else a.x
	var dir := ""
	if horizontal:
		dir = "s" if mouse.y < line else "n"
	else:
		dir = "e" if mouse.x < line else "o"
	var lo := minf(a.x, b.x) if horizontal else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if horizontal else maxf(a.y, b.y)
	var w := n * MapGeom.CELL
	if hi - lo < w + MapGeom.CELL - MapGeom.EPS:
		return refuse("ce mur est trop court pour %s (%s m de mur)" % [nm[0].to_lower(), _m(w)], "this wall is too short for %s (%s m of wall)" % [nm[1].to_lower(), _m(w, false)])
	var along := clampf(MapGeom.snap_along(mouse.x if horizontal else mouse.y, n), lo + w * 0.5 + MapGeom.CELL * 0.5 - MapGeom.EPS, hi - w * 0.5 - MapGeom.CELL * 0.5 + MapGeom.EPS)
	along = MapGeom.snap_along(along, n)
	if along - w * 0.5 < lo + MapGeom.CELL * 0.5 - MapGeom.EPS:
		along += MapGeom.CELL
	if along + w * 0.5 > hi - MapGeom.CELL * 0.5 + MapGeom.EPS:
		along -= MapGeom.CELL
	var pos := Vector2(along, line) if horizontal else Vector2(line, along)
	var obj := tmpl.duplicate()
	obj["position"] = MapGeom.arr(pos)
	obj["mur"] = dir
	obj.erase("angle")
	var span := Vector2(along - w * 0.5, along + w * 0.5)
	for o in doc.openings_on(k):
		var op := MapGeom.v2(o.position)
		if absf((op.y if horizontal else op.x) - line) > MapGeom.EPS or _on_oblique_wall(doc, k, op):
			continue
		var s := opening_span(o, horizontal)
		if s.x < span.y - MapGeom.EPS and s.y > span.x + MapGeom.EPS:
			var on := _name(o)
			return refuse("il faut du mur plein derrière : %s est dans ce mur à cet endroit" % on[0].to_lower(),
				"a solid wall is needed behind it: %s is in this wall here" % on[1].to_lower())
	var fr := footprint_rect(obj)
	for c in [fr.position, fr.end, Vector2(fr.position.x, fr.end.y), Vector2(fr.end.x, fr.position.y)]:
		if not MapGeom.contains(poly, c.lerp(fr.get_center(), 0.02)):
			return refuse("pas la place devant %s dans cette pièce" % nm[0].to_lower(), "not enough room in front of %s in this room" % nm[1].to_lower())
	var other := _overlaps(doc, k, fr, ignore_id, layer_of(tmpl))
	if not other.is_empty():
		var on := _name(other)
		return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	return {"ok": true, "position": obj.position, "mur": dir, "room": String(room.id)}


## Objet mural contre un côté EN BIAIS [a, b] de la pièce `room` : face vers
## l'intérieur, « angle » = direction du mur vu depuis l'objet (degrés, sens
## horaire depuis le nord) et « mur » = direction cardinale la plus proche.
static func _place_wall_item_oblique(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, room: Dictionary, a: Vector2, b: Vector2, ignore_id: String) -> Dictionary:
	var nm := _name(tmpl)
	var poly := doc.room_poly(room)
	var seg_len := a.distance_to(b)
	var t := (b - a) / seg_len
	var inward := Vector2(-t.y, t.x)
	if not MapGeom.contains(poly, (a + b) * 0.5 + inward * 0.3):
		inward = -inward
	var dv := -inward
	var fp := MapCatalog.footprint(tmpl)
	var w := fp.x * MapGeom.CELL
	var s := MapGeom.snap_on_segment(a, b, (mouse - a).dot(t), w, MapGeom.CELL * 0.5)
	if s < 0.0:
		return refuse("ce mur est trop court pour %s (%s m de mur)" % [nm[0].to_lower(), _m(w)], "this wall is too short for %s (%s m of wall)" % [nm[1].to_lower(), _m(w, false)])
	var pos := a + t * s
	var obj := tmpl.duplicate()
	obj["position"] = MapGeom.arr(pos)
	obj["mur"] = MapGeom.cardinal_of(dv)
	obj["angle"] = snappedf(MapGeom.dir_deg(dv), 0.01)
	for o in doc.openings_on(k):
		var op := MapGeom.v2(o.position)
		if _line_dist(op, a, t) > MapGeom.JOIN_TOL:
			continue
		var oc := (op - a).dot(t)
		var ow := opening_width(o) * 0.5
		if oc - ow < s + w * 0.5 - MapGeom.EPS and oc + ow > s - w * 0.5 + MapGeom.EPS:
			var on := _name(o)
			return refuse("il faut du mur plein derrière : %s est dans ce mur à cet endroit" % on[0].to_lower(),
				"a solid wall is needed behind it: %s is in this wall here" % on[1].to_lower())
	var fpoly := wall_item_poly(obj)
	var fc := MapGeom.centroid(fpoly)
	for c in fpoly:
		if not MapGeom.contains(poly, c.lerp(fc, 0.02)):
			return refuse("pas la place devant %s dans cette pièce" % nm[0].to_lower(), "not enough room in front of %s in this room" % nm[1].to_lower())
	var other := _overlaps(doc, k, footprint_rect(obj), ignore_id, layer_of(tmpl))
	if not other.is_empty():
		var on := _name(other)
		return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	return {"ok": true, "position": obj.position, "mur": obj.mur, "angle": obj.angle, "room": String(room.id)}


# ------------------------------------------------------------------ décor mural (format 7)

## Pas (m) d'un décor mural le long de son mur quand la grille est active.
const WALL_DECOR_STEP := 0.25


## Décor mural (applique) : contre le mur le plus proche du curseur (côté de
## pièce droit ou en biais, ou face d'un mur libre), PARTOUT le long de ce mur
## (jusque dans les angles, au-dessus d'une porte ou d'une fenêtre : sa
## hauteur se règle à part, clé « hauteur ») ; position au centimètre, ou au
## quart de mètre avec `grid`. Seul refus : loin de tout mur, hors des pièces,
## ou sur un autre décor mural. « position » est sur le trait du mur (comme un
## objet mural de jeu), « mur » / « angle » donnent la direction du mur.
static func place_wall_decor(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, ignore_id := "", grid := false) -> Dictionary:
	var full := _effects_full(doc, tmpl, ignore_id)
	if not full.is_empty():
		return full
	var nm := _name(tmpl)
	var room := room_at(doc, k, mouse)
	if room.is_empty():
		return refuse("%s se pose dans une pièce, contre un de ses murs" % nm[0], "%s goes inside a room, against one of its walls" % nm[1])
	var wall := nearest_wall_trait(doc, k, room, mouse)
	if wall.is_empty() or float(wall.d) > SNAP_DIST + 0.5:
		return refuse("rapprochez-vous d'un mur : %s se pose contre un mur" % nm[0].to_lower(), "move closer to a wall: %s stands against a wall" % nm[1].to_lower())
	var ta: Vector2 = wall.a
	var tb: Vector2 = wall.b
	var t := (tb - ta).normalized()
	var dv: Vector2 = -Vector2(wall.inward)
	var w := MapScale.foot_m(tmpl).x
	if String(tmpl.get("type", "")) == "effet":
		# Format 11 : largeur réelle de la zone de l'effet.
		w = MapCatalog.effect_zone(tmpl).x
	var u := wall_decor_along((mouse - ta).dot(t), ta.distance_to(tb), w, float(wall.margin))
	var pos := ta + t * u
	if grid:
		if MapGeom.is_axis_seg(ta, tb):
			var horizontal := absf(t.y) < MapGeom.EPS
			var c := snappedf(pos.x if horizontal else pos.y, WALL_DECOR_STEP)
			u = wall_decor_along((Vector2(c, ta.y) - ta).dot(t) if horizontal else (Vector2(ta.x, c) - ta).dot(t), ta.distance_to(tb), w, float(wall.margin))
		else:
			u = wall_decor_along(snappedf(u, WALL_DECOR_STEP), ta.distance_to(tb), w, float(wall.margin))
		pos = ta + t * u
	pos = MapGeom.round_mm(pos)
	var obj := tmpl.duplicate()
	obj["position"] = MapGeom.arr(pos)
	obj["mur"] = MapGeom.cardinal_of(dv)
	obj.erase("angle")
	var horizontal_wall := MapGeom.is_axis_seg(ta, tb) and absf(t.y) < MapGeom.EPS
	if not (MapGeom.is_axis_seg(ta, tb) and MapGeom.on_grid(ta.y if horizontal_wall else ta.x)):
		obj["angle"] = snappedf(MapGeom.dir_deg(dv), 0.01)
	var others := _overlaps_all(doc, k, footprint_rect(obj), ignore_id, layer_of(tmpl))
	others = others.filter(func(q): return MapGeom.overlap(exact_poly(obj), exact_poly(q)))
	others = _blocking_overlaps(doc, tmpl, others)
	if not others.is_empty():
		var on := _name(others[0])
		return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	var res := {"ok": true, "position": obj.position, "mur": obj.mur, "room": String(room.id)}
	if obj.has("angle"):
		res["angle"] = obj.angle
	return res


## Nouvel effet (format 10) sur une carte qui en a déjà MapCatalog.MAX_EFFECTS :
## le refus ; {} sinon (autre objet, ou effet déjà posé qu'on déplace).
static func _effects_full(doc: EditorMap, tmpl: Dictionary, ignore_id: String) -> Dictionary:
	if String(tmpl.get("type", "")) != "effet" or ignore_id != "" or MapCatalog.effect_count(doc) < MapCatalog.MAX_EFFECTS:
		return {}
	return refuse("%d effets au plus par carte" % MapCatalog.MAX_EFFECTS, "at most %d effects per map" % MapCatalog.MAX_EFFECTS)


## Décor mural déjà posé : toujours sur le trait d'un mur (côté de sa pièce
## ou face d'un mur libre), tourné vers la pièce comme lui (même au raccord de
## deux murs, où le mur le plus proche du curseur serait ambigu).
static func wall_decor_still_on_wall(doc: EditorMap, o: Dictionary) -> Dictionary:
	var k := doc.level_of(o)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	var dv := MapGeom.item_wall_dir(o)
	var front := p - dv * (MapGeom.WALL_HALF + 0.05)
	var room := room_at(doc, k, front)
	if not room.is_empty():
		var traits := []
		var poly := doc.room_poly(room)
		for i in poly.size():
			traits.append([poly[i], poly[(i + 1) % poly.size()]])
		for s in free_wall_segments(doc, k):
			# Trait de la face tournée vers l'objet (0,25 m derrière elle).
			var off := (float(s.half) - MapGeom.WALL_HALF) * (-dv)
			traits.append([Vector2(s.a) + off, Vector2(s.b) + off])
		for seg in traits:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			if a.distance_to(b) < 0.01 or MapGeom.dist_to_segment(p, a, b) > 0.02:
				continue
			var t := (b - a).normalized()
			if absf(t.dot(dv)) < 0.01:
				return {"ok": true, "room": String(room.id)}
	return refuse("n'est plus contre un mur", "is no longer against a wall")


## Position le long d'un mur de longueur `seg_len` (m depuis son début) d'un
## objet de largeur `w` sous le curseur `u` : bornée pour que l'objet reste
## sur la face du mur (`margin` à chaque bout : l'épaisseur du mur voisin
## dans un angle de pièce) ; mur plus court que l'objet : son milieu.
static func wall_decor_along(u: float, seg_len: float, w: float, margin: float) -> float:
	var lo := w * 0.5 + margin
	var hi := seg_len - w * 0.5 - margin
	if hi < lo:
		lo = w * 0.5
		hi = seg_len - w * 0.5
	if hi < lo:
		return seg_len * 0.5
	return clampf(u, lo, hi)


## Trait du mur le plus proche du curseur dans la pièce `room` : un de ses
## côtés (le trait est la ligne du contour) ou la face d'un mur libre (trait à
## 0,25 m derrière sa face, comme pour un mur de pièce).
## -> {a, b (trait), inward (vers la pièce), d (distance), margin} ou {}.
static func nearest_wall_trait(doc: EditorMap, k: int, room: Dictionary, mouse: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	var poly := doc.room_poly(room)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if a.distance_to(b) < 0.01:
			continue
		var d := MapGeom.dist_to_segment(mouse, a, b)
		if d < best_d:
			var t := (b - a).normalized()
			var n := Vector2(-t.y, t.x)
			best_d = d
			best = {"a": a, "b": b, "inward": n if (mouse - a).dot(n) >= 0.0 else -n, "d": d, "margin": MapGeom.WALL_HALF}
	for s in free_wall_segments(doc, k):
		var d := _free_wall_dist(mouse, s)
		if d < best_d:
			var a: Vector2 = s.a
			var b: Vector2 = s.b
			var t := (b - a).normalized()
			var n := Vector2(-t.y, t.x)
			var inward := n if (mouse - a).dot(n) >= 0.0 else -n
			var off := float(s.half) - MapGeom.WALL_HALF
			best_d = d
			best = {"a": a + inward * off, "b": b + inward * off, "inward": inward, "d": d, "margin": 0.0}
	return best


# ------------------------------------------------------------------ murs libres

## Segments des murs libres de l'étage (outil Mur : un segment ; mur courbe :
## ses segments droits) : [{a, b, half (demi-épaisseur), eid, i (rang)}].
static func free_wall_segments(doc: EditorMap, k: int) -> Array:
	var out := []
	for o in doc.objects_on(k):
		var t := String(o.get("type", ""))
		var half := float(o.get("epaisseur", 0.5)) * 0.5
		if t == "mur":
			out.append({"a": MapGeom.v2(o.a), "b": MapGeom.v2(o.b), "half": half, "eid": String(o.id), "i": 0})
		elif t == "mur_courbe":
			var i := 0
			for s in MapShapes.arc_segments(o):
				if (s[0] as Vector2).distance_to(s[1]) >= 0.01:
					out.append({"a": s[0], "b": s[1], "half": half, "eid": String(o.id), "i": i})
				i += 1
	return out


## Distance du curseur au « trait » d'une face d'un mur libre : la ligne à
## 0,25 m derrière sa face (celle d'un mur de pièce de 0,5 m), de chaque côté.
static func _free_wall_dist(mouse: Vector2, s: Dictionary) -> float:
	var off := float(s.half) - MapGeom.WALL_HALF
	return maxf(0.0, MapGeom.dist_to_segment(mouse, s.a, s.b) - off)


## Distance d'un contour convexe (emprise) à un segment (0 s'ils se coupent).
static func _poly_seg_dist(poly: PackedVector2Array, a: Vector2, b: Vector2) -> float:
	var best := INF
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		if Geometry2D.segment_intersects_segment(p, q, a, b) != null:
			return 0.0
		best = minf(best, MapGeom.dist_to_segment(p, a, b))
		best = minf(best, MapGeom.dist_to_segment(a, p, q))
		best = minf(best, MapGeom.dist_to_segment(b, p, q))
	if MapGeom.contains(poly, a):
		return 0.0
	return best


## Objet mural contre un MUR LIBRE (segment `segs[fw]`) : sur la face du côté
## du curseur, face de l'objet vers ce côté. Mêmes règles que contre un mur de
## pièce : mur plein derrière sur toute sa largeur (l'objet ne dépasse pas les
## bouts du mur), place devant dans la pièce, sans toucher les murs de la
## pièce ni un autre mur libre, sans chevaucher un autre objet. « position » :
## sur le trait de la face (à 0,25 m derrière elle, comme sur un mur de pièce ;
## sur le trait même d'un mur de 0,5 m). Mur droit de la grille : l'objet suit
## la grille (« mur » n, e, s, o) ; sinon « angle » (vrai mur oblique).
static func _place_wall_item_free(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, room: Dictionary, segs: Array, fw: int, ignore_id: String) -> Dictionary:
	var nm := _name(tmpl)
	var poly := doc.room_poly(room)
	var host: Dictionary = segs[fw]
	var a: Vector2 = host.a
	var b: Vector2 = host.b
	var seg_len := a.distance_to(b)
	var t := (b - a) / seg_len
	var nrm := Vector2(-t.y, t.x)
	var inward := nrm if (mouse - a).dot(nrm) >= 0.0 else -nrm
	var dv := -inward
	var off := float(host.half) - MapGeom.WALL_HALF
	var ta := a + inward * off
	var tb := b + inward * off
	var fp := MapCatalog.footprint(tmpl)
	var n := fp.x
	var w := n * MapGeom.CELL
	var horizontal := absf(t.y) < MapGeom.EPS
	# Trait droit sur la grille de 0,5 m : l'objet suit les cases de la grille.
	var grid := MapGeom.is_axis_seg(ta, tb) and MapGeom.on_grid(ta.y if horizontal else ta.x)
	# Mur de la grille (bouts sur la grille) : ses cases débordent de 0,25 m
	# après chaque bout.
	var ext := MapGeom.CELL * 0.5 if MapGeom.is_grid_seg(a, b) else 0.0
	if seg_len + 2.0 * ext < w - MapGeom.EPS:
		return refuse("ce mur est trop court pour %s (%s m de mur)" % [nm[0].to_lower(), _m(w)], "this wall is too short for %s (%s m of wall)" % [nm[1].to_lower(), _m(w, false)])
	var lo := (minf(ta.x, tb.x) if horizontal else minf(ta.y, tb.y)) - ext
	var hi := (maxf(ta.x, tb.x) if horizontal else maxf(ta.y, tb.y)) + ext
	var u0 := (mouse - ta).dot(t)
	var first := {}
	var seen := {}
	# Position aimantée sous le curseur ; si elle touche un mur de la pièce ou
	# un autre mur libre (bout d'un mur collé à la pièce), les voisines le long
	# du mur (pas de 0,25 m, jusqu'à une largeur d'objet).
	for j in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
		if absf(float(j) * MapGeom.CELL * 0.5) > w + MapGeom.EPS:
			continue
		var u: float = u0 + float(j) * MapGeom.CELL * 0.5
		var pos := Vector2.ZERO
		if grid:
			var c := MapGeom.snap_along((ta + t * u).x if horizontal else (ta + t * u).y, n)
			while c - w * 0.5 < lo - MapGeom.EPS:
				c += MapGeom.CELL
			while c + w * 0.5 > hi + MapGeom.EPS:
				c -= MapGeom.CELL
			if c - w * 0.5 < lo - MapGeom.EPS:
				continue
			pos = Vector2(c, ta.y) if horizontal else Vector2(ta.x, c)
		else:
			var s := MapGeom.snap_on_segment(ta, tb, u, w, 0.0)
			if s < 0.0:
				continue
			pos = MapGeom.round_mm(ta + t * s)
		var key := MapGeom.arr(pos)
		if seen.has(key):
			continue
		seen[key] = true
		var obj := tmpl.duplicate()
		obj["position"] = MapGeom.arr(pos)
		obj["mur"] = MapGeom.cardinal_of(dv)
		obj.erase("angle")
		if not grid:
			obj["angle"] = snappedf(MapGeom.dir_deg(dv), 0.01)
		var r := _free_wall_room_check(doc, k, obj, poly, segs, fw)
		if not r.ok:
			if first.is_empty():
				first = r
			continue
		var fpoly := wall_item_poly(obj)
		var others := _overlaps_all(doc, k, footprint_rect(obj) if grid else MapGeom.bbox(fpoly), ignore_id, layer_of(tmpl))
		if not grid:
			# Emprise tournée : les vrais contours (deux objets dos à dos
			# contre un mur en biais ne se gênent pas).
			others = others.filter(func(q): return MapGeom.overlap(fpoly, exact_poly(q)))
		if not others.is_empty():
			var other: Dictionary = others[0]
			var on := _name(other)
			return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
		var res := {"ok": true, "position": obj.position, "mur": obj.mur, "room": String(room.id)}
		if obj.has("angle"):
			res["angle"] = obj.angle
		return res
	if first.is_empty():
		return refuse("ce mur est trop court pour %s (%s m de mur)" % [nm[0].to_lower(), _m(w)], "this wall is too short for %s (%s m of wall)" % [nm[1].to_lower(), _m(w, false)])
	return first


## Contour exact (m) de l'emprise d'un objet posé : tournée pour un objet
## contre un mur en biais, un décor, un pilier... tournés ; son rectangle sinon.
static func exact_poly(o: Dictionary) -> PackedVector2Array:
	var tool := MapCatalog.tool_of(o)
	if tool == "poly":
		return MapRaster.clip_poly(o)
	if String(o.get("type", "")) == "effet":
		return effect_poly(o)
	if tool == "wall_item" and MapGeom.item_oblique(o):
		return wall_item_poly(o)
	if o.has("rect") and MapGeom.rot_of(o) != 0:
		return MapRaster.rect_poly(o)
	if tool == "floor_item" and MapRaster.free_rot(o) and MapCatalog.rotates(o):
		return MapRaster.floor_poly(o)
	return MapGeom.rect_poly(footprint_rect(o))


## Place devant un objet contre un mur libre : son emprise est dans la pièce,
## à 0,25 m au moins de ses murs (face intérieure), et ne touche aucun autre
## mur libre (ni les autres segments d'un mur courbe).
static func _free_wall_room_check(_doc: EditorMap, _k: int, obj: Dictionary, poly: PackedVector2Array, segs: Array, fw: int) -> Dictionary:
	var nm := _name(obj)
	var fpoly := wall_item_poly(obj)
	var fc := MapGeom.centroid(fpoly)
	for c in fpoly:
		if not MapGeom.contains(poly, c.lerp(fc, 0.02)):
			return refuse("pas la place devant %s dans cette pièce" % nm[0].to_lower(), "not enough room in front of %s in this room" % nm[1].to_lower())
	var inner := PackedVector2Array()
	for c in fpoly:
		inner.append(c.lerp(fc, 0.02))
	for i in poly.size():
		if _poly_seg_dist(inner, poly[i], poly[(i + 1) % poly.size()]) < MapGeom.WALL_HALF - 0.02:
			return refuse("%s touche un mur de la pièce : décalez-le le long du mur" % nm[0], "%s touches a wall of the room: slide it along the wall" % nm[1])
	for i in segs.size():
		if i == fw:
			continue
		var s: Dictionary = segs[i]
		if _poly_seg_dist(inner, s.a, s.b) < float(s.half) - 0.02:
			return refuse("%s touche un autre mur : décalez-le le long du mur" % nm[0], "%s touches another wall: slide it along the wall" % nm[1])
	return {"ok": true}


# ------------------------------------------------------------------ boîte mystère (format 15)

## Aimant de l'outil Boîte : curseur à moins de BOX_MAGNET m du trait d'un mur
## (côté de la pièce ou mur libre) -> la boîte se colle à ce mur (son centre
## est alors à 0,75 m du trait).
const BOX_MAGNET := 1.3
## Boîte au sol : jeu (m) entre son emprise et la face d'un mur, pour que le
## couvercle ouvert (il bascule derrière la boîte, MysteryBox.LID_OPEN_ANGLE)
## n'entre pas dans le mur.
const BOX_WALL_CLEAR := 0.1
## Boîte au sol : passage libre (m) qu'elle doit laisser d'un côté au moins
## (MAP_DESIGN_RULES §3.2 et §6.3 : 1,5 m au moins entre un obstacle et un
## mur). Serrée entre deux murs sur deux côtés opposés, elle bouche un couloir.
const BOX_MIN_PASS := 1.5


## Orientation (« rot », degrés) d'une boîte au sol dont l'avant regarde `front`
## (à 0 : vers le sud, +y ; sens horaire vu de dessus, comme un décor).
static func rot_facing(front: Vector2) -> int:
	return MapGeom.norm_deg(rad_to_deg(atan2(-front.x, front.y)))


## Avant (vecteur unitaire, m) d'une boîte : au sol, d'après « rot » ; murale,
## à l'opposé de son mur (vers la pièce).
static func box_front(o: Dictionary) -> Vector2:
	if MapCatalog.floor_box(o):
		return Vector2(0, 1).rotated(deg_to_rad(float(MapGeom.rot_of(o))))
	return -MapGeom.item_wall_dir(o)


## Le point `p` est-il à moins de `r` m du trait d'un mur de sa pièce ou d'un
## mur libre de l'étage ?
static func near_wall(doc: EditorMap, k: int, p: Vector2, r: float) -> bool:
	var room := room_at(doc, k, p)
	if not room.is_empty():
		var poly := doc.room_poly(room)
		for i in poly.size():
			if MapGeom.dist_to_segment(p, poly[i], poly[(i + 1) % poly.size()]) < r:
				return true
	for s in free_wall_segments(doc, k):
		if _free_wall_dist(p, s) < r:
			return true
	return false


## Format 15 : pose d'une boîte mystère (outil « wall_snap »). Près d'un mur
## (curseur à moins de BOX_MAGNET m de son trait ; `magnet` faux : Alt, jamais),
## elle s'y colle face à la pièce, comme un objet mural (place_wall_item) ;
## sinon (ou si ce mur la refuse : ouverture derrière, mur trop court), elle
## se pose au sol, à sa rotation (place_floor_box). Une boîte murale qu'on
## décolle garde son orientation (avant vers la pièce).
## -> {ok, position, room, mur (+ angle) | rot} ou la raison du refus.
static func place_box(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, ignore_id := "", grid := false, magnet := true) -> Dictionary:
	var wall_res := {}
	if magnet and near_wall(doc, k, mouse, BOX_MAGNET):
		var wt := tmpl.duplicate()
		wt["mur"] = String(tmpl.get("mur", "n"))
		wt.erase("rot")
		wall_res = place_wall_item(doc, k, wt, mouse, ignore_id, grid)
		if wall_res.ok:
			return wall_res
	var ft := tmpl.duplicate()
	ft["rot"] = MapGeom.rot_of(tmpl) if MapCatalog.floor_box(tmpl) else rot_facing(box_front(tmpl))
	ft.erase("mur")
	ft.erase("angle")
	var res := place_floor_box(doc, k, ft, mouse, ignore_id, grid)
	if res.ok or wall_res.is_empty():
		return res
	return wall_res


## Boîte au sol (format 15) : comme un objet de jeu au sol (dans une pièce,
## sans chevauchement, place_floor_item) et, au centimètre près, son emprise
## tournée (2 × 1 m) dans la pièce, à BOX_WALL_CLEAR m au moins de la face
## de ses murs et de tout mur libre. `tmpl` : boîte sans « mur », avec « rot ».
static func place_floor_box(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, ignore_id := "", grid := false) -> Dictionary:
	var res := place_floor_item(doc, k, tmpl, mouse, ignore_id, grid)
	if not res.ok:
		return res
	var nm := _name(tmpl)
	var obj := tmpl.duplicate()
	obj["position"] = res.position
	var fpoly := MapRaster.floor_poly(obj)
	var room := room_at(doc, k, MapGeom.v2(res.position))
	var rp := doc.room_poly(room)
	for c in fpoly:
		if not MapGeom.contains(rp, c):
			return refuse("%s dépasse de la pièce : posez-la plus au milieu" % nm[0], "%s sticks out of the room: place it further inside" % nm[1])
	for i in rp.size():
		if _poly_seg_dist(fpoly, rp[i], rp[(i + 1) % rp.size()]) < MapGeom.WALL_HALF + BOX_WALL_CLEAR - 0.001:
			return refuse("%s touche un mur : écartez-la, ou approchez-la pour la coller au mur" % nm[0],
				"%s touches a wall: move it away, or closer to snap it to the wall" % nm[1])
	for s in free_wall_segments(doc, k):
		if _poly_seg_dist(fpoly, s.a, s.b) < float(s.half) + BOX_WALL_CLEAR - 0.001:
			return refuse("%s touche un mur : écartez-la, ou approchez-la pour la coller au mur" % nm[0],
				"%s touches a wall: move it away, or closer to snap it to the wall" % nm[1])
	if _box_squeezed(fpoly, rp, free_wall_segments(doc, k)):
		return refuse("%s bouche le passage : laissez %s m libres d'un côté (couloir trop étroit pour elle)" % [nm[0], str(BOX_MIN_PASS).replace(".", ",")],
			"%s blocks the way: leave %s m free on one side (corridor too narrow for it)" % [nm[1], str(BOX_MIN_PASS)])
	res["rot"] = MapGeom.rot_of(tmpl)
	return res


## Boîte au sol serrée entre deux murs : sur deux côtés OPPOSÉS de son emprise
## `fpoly`, un mur (de la pièce `rp` ou libre `segs`) à moins de BOX_MIN_PASS m
## de sa face. Une boîte en travers d'un couloir de 3 m (0,35 m de chaque
## côté) le bouchait sans que rien ne le dise (le validateur le signale aussi).
static func _box_squeezed(fpoly: PackedVector2Array, rp: PackedVector2Array, segs: Array) -> bool:
	var walls := []
	for i in rp.size():
		walls.append({"a": rp[i], "b": rp[(i + 1) % rp.size()], "half": MapGeom.WALL_HALF})
	walls.append_array(segs)
	var mid := Vector2.ZERO
	for p in fpoly:
		mid += p
	mid /= fpoly.size()
	var tight := []
	for i in fpoly.size():
		var p := fpoly[i]
		var q := fpoly[(i + 1) % fpoly.size()]
		var nrm := (q - p).orthogonal().normalized()
		if nrm.dot((p + q) * 0.5 - mid) < 0.0:
			nrm = -nrm
		# Bande de BOX_MIN_PASS m devant ce côté : un mur y entre -> côté serré.
		var strip := PackedVector2Array([p, q, q + nrm * BOX_MIN_PASS, p + nrm * BOX_MIN_PASS])
		tight.append(walls.any(func(s): return _poly_seg_dist(strip, s.a, s.b) < float(s.half) - 0.001))
	return fpoly.size() == 4 and ((tight[0] and tight[2]) or (tight[1] and tight[3]))


## Reporte un résultat de place_box sur la boîte `o` : contre un mur (« mur »,
## « angle », sans « rot ») ou au sol (« rot », sans « mur » ni « angle »).
static func apply_box(o: Dictionary, res: Dictionary) -> void:
	o["position"] = res.position
	if res.has("mur"):
		apply_wall(o, res)
		o.erase("rot")
	else:
		o.erase("mur")
		o.erase("angle")
		o["rot"] = int(res.get("rot", 0))


## Pose d'un objet au sol (départ, apparition, téléporteur, lampe, caisse,
## prefab, luminaire...). Emprise rectangulaire, rotation comprise (prefabs).
## Couches (layer_of) : un luminaire du plafond ne gêne que les autres
## luminaires du plafond ; un luminaire posé au sol peut se poser sur un
## meuble qui a un dessus (support : bureau, chariot...).
static func place_floor_item(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, ignore_id := "", grid := true) -> Dictionary:
	var full := _effects_full(doc, tmpl, ignore_id)
	if not full.is_empty():
		return full
	var n := MapCatalog.floor_size(tmpl)
	var pos := Vector2(MapGeom.snap_along(mouse.x, n.x), MapGeom.snap_along(mouse.y, n.y))
	if not grid or MapRaster.free_rot(tmpl):
		# Sans grille, ou tourné au degré près : là où est le curseur (au centimètre).
		pos = MapGeom.round_cm(mouse)
	var obj := tmpl.duplicate()
	obj["position"] = MapGeom.arr(pos)
	var nm := _name(tmpl)
	var room := room_at(doc, k, pos)
	var decor := MapCatalog.is_decor(tmpl)
	if room.is_empty() and decor:
		# Décor (format 7) : centre sur un mur, ou à moitié dehors ; il suffit
		# qu'il touche le sol d'une pièce.
		room = room_touching(doc, k, exact_poly(obj))
	if room.is_empty():
		if decor:
			return refuse("%s doit toucher le sol d'une pièce" % nm[0], "%s must touch a room floor" % nm[1])
		return refuse("%s se pose à l'intérieur d'une pièce" % nm[0], "%s goes inside a room" % nm[1])
	# Objets de jeu (départ, apparition, téléporteur) : dans la pièce, loin du
	# mur. Le décor se pose contre un mur, et même à moitié dedans (le mur reste
	# entier : MapRaster ne rend pleines que ses cases de sol).
	if not decor:
		var inner := inner_cells(doc.room_poly(room))
		for c in MapRaster.floor_cells(obj):
			if not inner.has(c):
				return refuse("%s touche un mur : posez-le plus au milieu de la pièce" % nm[0], "%s touches a wall: place it further inside the room" % nm[1])
	var fr := footprint_rect(obj)
	var layer := layer_of(tmpl)
	var others := _overlaps_all(doc, k, fr, ignore_id, layer)
	var on_top := {}
	if layer == "sol" and MapCatalog.light_mount(tmpl) == "sol" and not others.is_empty():
		# Luminaire posé sur un meuble : tout ce qu'il touche doit être un dessus de meuble.
		var all_supports := others.all(func(q): return support_height(q) > 0.0)
		if all_supports and others.size() == 1 and footprint_rect(others[0]).grow(0.01).encloses(fr):
			on_top = others[0]
			others = []
	elif support_height(tmpl) > 0.0:
		# Meuble : les luminaires posés sur son dessus ne le gênent pas.
		others = others.filter(func(q): return not (MapCatalog.light_mount(q) == "sol" and fr.grow(0.01).encloses(footprint_rect(q))))
	# Format 12 : un décor posé SUR un autre (hauteur de pose) ne le chevauche pas.
	if String(tmpl.get("type", "")) in ["prefab", "caisse", "baril"]:
		others = others.filter(func(q): return not _stacked(tmpl, q))
	# Format 9 : décor et obstacles qui se chevauchent (réglage de la carte).
	others = _blocking_overlaps(doc, tmpl, others)
	if not others.is_empty():
		var on := _name(others[0])
		return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	var res := {"ok": true, "position": obj.position, "room": String(room.id)}
	if not on_top.is_empty():
		res["sur"] = String(on_top.id)
	return res


## Deux décors posés au sol l'un au-dessus de l'autre (format 12 : tranches de
## hauteur disjointes, un dessus de meuble pouvant porter l'autre) ?
static func _stacked(a: Dictionary, b: Dictionary) -> bool:
	if not String(b.get("type", "")) in ["prefab", "caisse", "baril"] or MapVertical.mount_of(b) not in ["sol", ""]:
		return false
	var a0 := MapVertical.decor_z(a)
	var b0 := MapVertical.decor_z(b)
	return a0 >= MapVertical.decor_top(b) - MapVertical.REST_TOL or b0 >= MapVertical.decor_top(a) - MapVertical.REST_TOL


## Rectangle au sol (pilier, escalier, piège) : dans une seule pièce, sans
## chevauchement ; `rot` : rotation au degré près (sens horaire) autour de son centre.
## Escalier : `stair` = l'escalier tracé (monte, variante...), sinon celui
## déplacé (`ignore_id`) ; `down` : posé avec l'escalier qui descend (mots du
## message, check_stair).
static func check_rect(doc: EditorMap, k: int, type: String, r: Rect2, ignore_id := "", rot := 0, variant := "", stair := {}, down := false) -> Dictionary:
	var o := {"type": type}
	var nm := _name(o)
	var sz0 := r.size   # taille avant rotation (largeur d'un escalier)
	var r0 := r
	if type == "escalier" and k < 0:
		return check_stair(doc, k, {}, ignore_id, down)
	if type == "bloc_invisible":
		# Barrière d'avant le format 9 (rectangle) : mêmes règles qu'un polygone.
		return check_clip(MapGeom.rot_rect_poly(r.get_center(), r.size, posmod(rot, 360)))
	if r.size.x < MapGeom.CELL * 2 - MapGeom.EPS or r.size.y < MapGeom.CELL * 2 - MapGeom.EPS:
		return refuse("%s trop petit (1 m de côté au moins)" % nm[0], "%s too small (at least 1 m per side)" % nm[1])
	var room := _stair_room_at(doc, k, r.get_center()) if type == "escalier" else room_at(doc, k, r.get_center())
	if room.is_empty():
		return refuse("%s se pose à l'intérieur d'une pièce" % nm[0], "%s goes inside a room" % nm[1])
	var poly := doc.room_poly(room)
	var corners := MapGeom.rot_rect_poly(r.get_center(), r.size, posmod(rot, 360))
	for c in corners:
		if not MapGeom.contains(poly, c.lerp(r.get_center(), 0.01)) and not MapGeom.on_boundary(poly, c, 0.01):
			return refuse("%s déborde de la pièce « %s »" % [nm[0], room.get("nom", room.id)], "%s sticks out of room \"%s\"" % [nm[1], room.get("nom", room.id)])
	if posmod(rot, 360) != 0:
		# Rectangle tourné : aucun côté de la pièce ne le traverse (pièce concave).
		for i in poly.size():
			for j in 4:
				if Geometry2D.segment_intersects_segment(poly[i], poly[(i + 1) % poly.size()], corners[j].lerp(r.get_center(), 0.01),
						corners[(j + 1) % 4].lerp(r.get_center(), 0.01)) != null:
					return refuse("%s déborde de la pièce « %s »" % [nm[0], room.get("nom", room.id)], "%s sticks out of room \"%s\"" % [nm[1], room.get("nom", room.id)])
		r = MapGeom.bbox(corners)
	if type == "escalier":
		if k >= doc.floor_count() - 1 or k < 0:
			return check_stair(doc, k, {}, ignore_id, down)
		# Type d'escalier (format 6) : celui donné, sinon celui de l'escalier déplacé.
		var kind := variant
		if kind == "" and not stair.is_empty():
			kind = MapCatalog.stair_kind(stair)
		elif kind == "" and ignore_id != "":
			kind = MapCatalog.stair_kind(doc.find(ignore_id))
		if kind == "":
			kind = StairGen.DEFAULT_KIND
		var mw := MapCatalog.stair_min_width(kind)
		if minf(sz0.x, sz0.y) < mw - MapGeom.EPS:
			var ms := ("%s" % snappedf(mw, 0.1)).trim_suffix(".0")
			var vn := MapCatalog.variant_names("escalier", kind)
			return refuse("%s trop étroit (%s m au moins)" % [vn[0], ms.replace(".", ",")], "%s too narrow (at least %s m)" % [vn[1], ms])
	var others := _blocking_overlaps(doc, o, _overlaps_all(doc, k, r, ignore_id))
	if not others.is_empty():
		var on := _name(others[0])
		if type == "escalier" and String(others[0].get("type", "")) == "escalier":
			on = stair_label_of(doc, others[0])
			var sp := _xy(MapGeom.cell_of(MapRules.footprint_rect(others[0]).intersection(r).get_center()))
			return refuse("l'escalier chevauche %s %s" % [on[0], sp[0]], "the stairs overlap %s %s" % [on[1], sp[1]])
		return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	if type == "escalier":
		# Les deux étages qu'il relie (départ, arrivée, trémie).
		var so: Dictionary = stair.duplicate() if not stair.is_empty() else (doc.find(ignore_id).duplicate() if ignore_id != "" else {})
		so["type"] = "escalier"
		so["rect"] = MapGeom.rect_arr(r0)
		so["rot"] = posmod(rot, 360)
		if not so.has("monte"):
			so["monte"] = "n"
		if variant != "":
			MapCatalog.set_variant(so, variant)
		var st := check_stair(doc, k, so, ignore_id, down)
		if not st.ok:
			return st
		# Sens retenu (pick_stair_dir) : le panneau propose de corriger « monte ».
		return {"ok": true, "room": String(room.id), "monte": st.monte, "to": st.get("to", k + 1)}
	return {"ok": true, "room": String(room.id)}


# ------------------------------------------------------------------ escaliers (deux étages)

## Escalier posé à l'étage `k` : il monte à l'étage k + 1. Escalier « qui
## descend » (inventaire) : enregistré comme un escalier de l'étage du dessous
## qui monte vers l'étage courant (aucun champ de plus, `down` ne change que
## les mots : « départ » en haut, « arrivée » en bas).
## Cases d'un escalier, comme le validateur (MapValidator._stairs,
## _diag_stair, _shaped_stair) : marches (body, son étage ; trémie à l'étage
## du dessus), pied (foot : sol de son étage devant la première marche) et
## arrivée (exit : plancher de l'étage du dessus au-delà du haut) ; case -> true.
static func stair_parts(o: Dictionary, y0 := 0.0, y1 := 3.5) -> Dictionary:
	# Mémoire par contenu (plusieurs appels par image pendant un tracé, chaque
	# escalier vérifié à chaque modification) : jamais recalculé pour rien.
	var key := [o.get("rect"), o.get("monte"), o.get("rot"), o.get("variante"), o.get("sens"), o.get("marches"), y0, y1]
	var main := not ThreadGuard.worker()
	var h := key.hash()
	if main and _parts_cache.has(h) and _parts_cache[h][0] == key:
		return _parts_cache[h][1]
	var body := {}
	for c in MapRaster.stair_cells(o):
		body[c] = true
	var foot := {}
	var top := {}
	var shaped := StairGen.is_shaped(MapCatalog.stair_kind(o))
	var pl := MapRaster.stair_plan(o, y0, maxf(y1, y0 + 0.5)) if shaped else {}
	var fr := MapRaster.stair_frame(o)
	var u: Vector2 = fr.up
	var lat := Vector2(-u.y, u.x)
	var c0: Vector2 = fr.center
	var wide := float(fr.width)
	for c: Vector2i in body:
		for d in MapValidator.DIRS:
			var q: Vector2i = c + d
			if body.has(q):
				continue
			var qc := MapGeom.cell_center(q)
			if shaped:
				if MapValidator._beyond(pl.foot, qc):
					foot[q] = true
				elif MapValidator._beyond(pl.exit, qc):
					top[q] = true
				continue
			# Hors des marches et dans leur largeur : au-delà d'un petit côté.
			var rel := qc - c0
			if absf(rel.dot(lat)) > wide * 0.5 - 0.2:
				continue
			if rel.dot(u) < 0.0:
				foot[q] = true
			else:
				top[q] = true
	var bb := Rect2i()
	var first := true
	for d: Dictionary in [body, foot, top]:
		for c: Vector2i in d:
			bb = Rect2i(c, Vector2i.ONE) if first else bb.merge(Rect2i(c, Vector2i.ONE))
			first = false
	var out := {"body": body, "foot": foot, "exit": top, "bb": bb.grow(1)}
	if main:
		if _parts_cache.size() > 2048:
			_parts_cache.clear()
		_parts_cache[h] = [key.duplicate(true), out]
	return out


## Mémoires des escaliers (fil principal) : cases d'un escalier (stair_parts)
## et cases d'une pièce (_room_cells), par contenu.
static var _parts_cache: Dictionary = {}
static var _room_cache: Dictionary = {}


## Cases d'une pièce : [bord (dictionnaire), intérieur (dictionnaire)], par contenu
## du contour (MapRaster.room_cells).
static func _room_cells(poly: PackedVector2Array) -> Array:
	var main := not ThreadGuard.worker()
	var h := [poly].hash()
	if main and _room_cache.has(h) and _room_cache[h][0] == poly:
		return _room_cache[h][1]
	var rc := MapRaster.room_cells(poly)
	var inner := {}
	for c in rc[1]:
		inner[c] = true
	var out := [rc[0], inner]
	if main:
		if _room_cache.size() > 4096:
			_room_cache.clear()
		_room_cache[h] = [poly, out]
	return out


## Sens retenu d'un escalier, règle commune au validateur (MapValidator._stairs)
## et à la pose (check_stair) : le sens tracé (« monte ») s'il convient, sinon
## le seul sens possible (cartes d'avant, « monte » réglé à contresens), sinon
## le sens tracé (son bout fautif est alors signalé). Vector2i.ZERO : aucun.
static func pick_stair_dir(traced: Vector2i, valid: Array) -> Vector2i:
	if traced != Vector2i.ZERO and valid.has(traced):
		return traced
	if valid.size() == 1:
		return valid[0]
	return traced


## Sens de montée (« monte ») d'un escalier tracé de `a` vers `b` : celui du
## glissement (du bas vers le haut) ; escalier qui descend (`down`) : on trace
## du haut, à l'étage où l'on est, vers le bas : l'inverse.
static func stair_dir(a: Vector2, b: Vector2, down := false) -> String:
	var d := b - a
	var m := ("e" if d.x > 0 else "o") if absf(d.x) > absf(d.y) else ("s" if d.y > 0 else "n")
	return String({"n": "s", "s": "n", "e": "o", "o": "e"}[m]) if down else m


## Nom d'un escalier qui monte de l'altitude `a0` à `a1` (m) : [fr, en].
static func stair_label(a0: float, a1: float) -> Array:
	return ["l'escalier de %s vers %s" % [EditorMap.alt_text(a0), EditorMap.alt_text(a1)],
		"the stairs from %s to %s" % [EditorMap.alt_text(a0, false), EditorMap.alt_text(a1, false)]]


## Nom de l'escalier `o` de la carte : [fr, en].
static func stair_label_of(doc: EditorMap, o: Dictionary) -> Array:
	return stair_label(EditorMap.alt_of(o), doc.stair_top_of(o))


## Nom du niveau `k` dans les refus : [« niveau 3,5 m », « level 3.5 m »].
static func level_label(doc: EditorMap, k: int) -> Array:
	var a := doc.level_alt(k)
	return ["niveau %s" % EditorMap.alt_text(a), "level %s" % EditorMap.alt_text(a, false)]


## Niveau d'arrivée de l'escalier `o` posé au niveau `k` : celui de son
## « altitude_haut » (format 17 : n'importe quel niveau au-dessus) ; absente
## (escalier en cours de tracé), le niveau suivant. -1 : aucun niveau là.
static func stair_top_level(doc: EditorMap, k: int, o: Dictionary) -> int:
	if o.has("altitude_haut"):
		return doc.level_index(EditorMap.stair_top(o))
	return k + 1 if k + 1 < doc.level_count() else -1


## Position d'une case pour un message : [fr, en] (coin de la case, comme le
## validateur).
static func _xy(c: Vector2i) -> Array:
	var x := c.x * MapGeom.CELL
	var y := c.y * MapGeom.CELL
	return ["(x %s m, y %s m)" % [_m(x), _m(y)], "(x %s m, y %s m)" % [_m(x, false), _m(y, false)]]


## Cases d'un ensemble {case: true} triées (messages et dessin stables).
static func _sorted_cells(d: Dictionary) -> Array:
	var out := d.keys()
	out.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## Ce qu'un contrôle d'escalier doit connaître d'un étage `j`, calculé une
## fois par contrôle (`ctx`) : pièces et leurs cases, doubles hauteurs de
## l'étage du dessous, autres escaliers (et leurs cases), murs libres et
## obstacles près de l'escalier (lot spatial de begin_batch s'il est ouvert).
static func _stair_floor(ctx: Dictionary, j: int) -> Dictionary:
	var floors: Dictionary = ctx.floors
	if floors.has(j):
		return floors[j]
	var doc: EditorMap = ctx.doc
	var base := _stair_floor_base(doc, j)
	var info := {"rooms": base.rooms, "voids": base.voids, "walls": base.walls, "items": base.items,
		"room_grid": base.room_grid, "stair_grid": base.stair_grid, "wells": base.wells, "well_grid": base.well_grid,
		"stairs": base.stairs}   # avec celui contrôlé : sauté par les boucles (id)
	floors[j] = info
	return info


## Obstacles (pilier, caisse, baril, décor ou luminaire qui bloque) près de
## l'escalier contrôlé, à l'étage `j` : lus seulement si un bout y arrive.
static func _stair_blockers(ctx: Dictionary, j: int) -> Array:
	var info := _stair_floor(ctx, j)
	if info.has("near"):
		return info.near
	var near := []
	info["near"] = near
	var ignore := String(ctx.ignore)
	var area: Rect2 = ctx.area
	for e in _base_near(info, area):
		var o: Dictionary = e[0]
		if String(o.get("id", "")) == ignore:
			continue
		var t := String(o.get("type", ""))
		var solid := t in ["pilier", "caisse", "baril"] or (t in ["prefab", "luminaire"] and MapCatalog.blocking(o) != "non" and String(e[2]) == "sol")
		if solid and (e[1] as Rect2).intersects(area):
			near.append([o, e[1]])
	return near


## Partie d'un étage commune à tous les contrôles d'escaliers (pièces,
## doubles hauteurs du dessous, escaliers, murs libres) ; gardée pendant un
## lot (begin_batch : MapEditor._update_invalid) ou tant que la carte n'a
## pas changé (stair_cache_tag : version de la carte, MapCanvas pendant un
## tracé ; -1 : pas de mémoire).
static func _stair_floor_base(doc: EditorMap, j: int) -> Dictionary:
	var main := not ThreadGuard.worker()
	var keep := main and (_batch_doc == doc or (stair_cache_tag >= 0 and _base_doc == doc and _base_tag == stair_cache_tag))
	if keep and _floor_bases.has(j):
		return _floor_bases[j]
	if main and not keep:
		_floor_bases = {}
		_base_doc = doc
		_base_tag = stair_cache_tag if _batch_doc != doc else -1
	# Lot (MapEditor._update_invalid à chaque modification) : la base d'avant
	# resert si les pièces de l'étage (et du dessous), ses escaliers, ses murs
	# libres et les sols n'ont pas changé (empreinte de leur contenu).
	var fp := 0
	# Escaliers d'un niveau plus bas qui traversent ce niveau ou y arrivent
	# (format 17 : leur trémie est ici) : [escalier, arrivée ?].
	var through := doc.rooms_through(j) if j > 0 and j < doc.floor_count() else []
	var wells := []
	if j > 0 and j < doc.floor_count():
		var sol := doc.floor_sol(j)
		var all: Array = _batch_stairs if main and _batch_doc == doc else _stairs_of(doc)
		for s: Array in all:
			if float(s[1]) < sol - EditorMap.ALT_EQ and float(s[2]) >= sol - EditorMap.ALT_EQ:
				wells.append([s[0], absf(float(s[2]) - sol) <= EditorMap.ALT_EQ, s[2]])
	if main and _batch_doc == doc and j >= 0 and j < doc.floor_count():
		fp = [doc.rooms_on(j), through, _batch_lists.get(j, []), wells, doc.floor_sol(j),
			doc.floor_sol(j + 1) if j + 1 < doc.floor_count() else -1.0].hash()
		var old: Array = _fp_bases.get(j, [])
		if not old.is_empty() and old[0] == fp and old[1] == doc:
			var again: Dictionary = old[2]
			again.items = _batch.get(j, {})
			_floor_bases[j] = again
			return again
	# items : objets au sol (hors murs libres, barrières, effets) par cases de
	# BUCKET m, comme le lot de begin_batch, pour cet étage seulement.
	# room_grid / stair_grid : pièces et escaliers par cases de BUCKET m.
	var base := {"rooms": [], "voids": [], "stairs": [], "walls": [], "items": {}, "room_grid": {}, "stair_grid": {}, "wells": [], "well_grid": {}}
	if j >= 0 and j < doc.floor_count():
		for p in doc.rooms_on(j):
			var poly := doc.room_poly(p)
			var rc := _room_cells(poly)
			var re := [p, rc[0], rc[1], poly]
			base.rooms.append(re)
			for bk in _buckets(MapGeom.bbox(poly).grow(MapGeom.CELL)):
				(base.room_grid.get_or_add(bk, []) as Array).append(re)
		for p in through:
			var rc := _room_cells(doc.room_poly(p))
			base.voids.append([p, rc[0], rc[1]])
		for wl in wells:
			var o: Dictionary = wl[0]
			var we := [o, stair_parts(o, EditorMap.alt_of(o), float(wl[2])), wl[1]]
			base.wells.append(we)
			var cb: Rect2i = we[1].bb
			for bk in _buckets(Rect2((Vector2(cb.position) - Vector2.ONE * 0.5) * MapGeom.CELL, Vector2(cb.size) * MapGeom.CELL)):
				(base.well_grid.get_or_add(bk, []) as Array).append(we)
		var batched := _batch_doc == doc and main
		for o in (_batch_lists.get(j, []) if batched else doc.objects_on(j)):
			var t := String(o.get("type", ""))
			if t == "escalier":
				var se := [o, stair_parts(o, doc.floor_sol(j), doc.stair_top_of(o))]
				base.stairs.append(se)
				var cb: Rect2i = se[1].bb
				for bk in _buckets(Rect2((Vector2(cb.position) - Vector2.ONE * 0.5) * MapGeom.CELL, Vector2(cb.size) * MapGeom.CELL)):
					(base.stair_grid.get_or_add(bk, []) as Array).append(se)
			elif t == "mur" or t == "mur_courbe":
				base.walls.append(o)
			if not t in NO_OVERLAP_CHECK and not batched:
				var r := footprint_rect(o)
				var e := [o, r, layer_of(o)]
				for bk in _buckets(r):
					(base.items.get_or_add(bk, []) as Array).append(e)
	if _batch_doc == doc and main:
		base.items = _batch.get(j, {})   # le lot range déjà les objets par cases
	if main and (_batch_doc == doc or stair_cache_tag >= 0):
		_floor_bases[j] = base
	if fp != 0:
		base["fp"] = fp
		_fp_bases[j] = [fp, doc, base]
	return base


## room_at pour un escalier : par les pièces rangées en cases (base d'étage)
## quand elle est gardée (lot, tracé), sinon room_at.
static func _stair_room_at(doc: EditorMap, k: int, p: Vector2) -> Dictionary:
	var main := not ThreadGuard.worker()
	if not main or not (_batch_doc == doc or stair_cache_tag >= 0) or k < 0 or k >= doc.floor_count():
		return room_at(doc, k, p)
	var base := _stair_floor_base(doc, k)
	for re: Array in base.room_grid.get(Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET)), []):
		if MapGeom.contains(re[3], p):
			return re[0]
	return {}


## Objets de la base d'un étage qui pourraient toucher `r` : [[objet, emprise, couche]].
static func _base_near(base: Dictionary, r: Rect2) -> Array:
	var seen := {}
	var out := []
	for bk in _buckets(r):
		for e in base.items.get(bk, []):
			var eid := String(e[0].get("id", ""))
			if not seen.has(eid):
				seen[eid] = true
				out.append(e)
	return out


## Version de la carte donnée par l'éditeur pendant un tracé (MapCanvas) :
## tant qu'elle ne change pas, les étages déjà lus resservent ; -1 : rien.
static var stair_cache_tag := -1
static var _floor_bases: Dictionary = {}
static var _fp_bases: Dictionary = {}   # étage -> [empreinte, carte, base] (d'un lot à l'autre)
static var _base_doc: EditorMap = null
static var _base_tag := -1


## Ce qui se trouve dans la case `c` de l'étage `j` pour un bout d'escalier
## (MapRaster en raccourci, sans construire la grille) : {kind, what [fr, en]}
## avec kind « sol » (plancher libre d'une pièce), « vide », « mur »,
## « tremie », « escalier » ou « obstacle ».
static func _stair_cell(ctx: Dictionary, j: int, c: Vector2i) -> Dictionary:
	# Chaque case n'est examinée qu'une fois par contrôle (sens, puis bouts).
	var memo: Dictionary = _stair_floor(ctx, j).get_or_add("cells", {})
	if not memo.has(c):
		memo[c] = _stair_cell_now(ctx, j, c)
	return memo[c]


static func _stair_cell_now(ctx: Dictionary, j: int, c: Vector2i) -> Dictionary:
	var here := _stair_floor(ctx, j)
	var ignore := String(ctx.ignore)
	# Seuls les pièces et escaliers rangés dans la case de BUCKET m du point.
	var bk := Vector2i(floori(c.x * MapGeom.CELL / BUCKET), floori(c.y * MapGeom.CELL / BUCKET))
	var doc0: EditorMap = ctx.doc
	for s: Array in here.well_grid.get(bk, []):
		if (s[1].body as Dictionary).has(c) and String(s[0].get("id", "")) != ignore:
			var lb := stair_label_of(doc0, s[0])
			return {"kind": "tremie", "what": ["la trémie de " + lb[0], "the stairwell of " + lb[1]], "of": s[0]}
	for s: Array in here.stair_grid.get(bk, []):
		if (s[1].body as Dictionary).has(c) and String(s[0].get("id", "")) != ignore:
			return {"kind": "escalier", "what": stair_label_of(doc0, s[0]), "of": s[0]}
	var room := {}
	var near_rooms: Array = here.room_grid.get(bk, [])
	for r: Array in near_rooms:
		if (r[2] as Dictionary).has(c):
			room = r[0]
			break
	if room.is_empty():
		# Bord d'une mezzanine au-dessus d'une double hauteur : plancher (MapRaster).
		var borders := []
		for r: Array in near_rooms:
			if (r[1] as Dictionary).has(c):
				borders.append(r[0])
		var void_of: Array = (here.voids as Array).filter(func(v): return (v[2] as Dictionary).has(c))
		var ll := level_label(doc0, j)
		if borders.size() == 1 and not void_of.is_empty():
			room = borders[0]
		elif not borders.is_empty():
			return {"kind": "mur", "what": ["un mur du %s" % ll[0], "a wall on %s" % ll[1]], "rooms": borders}
		elif not void_of.is_empty():
			var vp: Dictionary = void_of[0][0]
			return {"kind": "vide", "what": ["le vide de la pièce haute « %s »" % vp.get("nom", vp.id), "the void of the high room \"%s\"" % vp.get("nom", vp.id)]}
		else:
			return {"kind": "vide", "what": ["le vide (pas de pièce au %s)" % ll[0], "empty space (no room on %s)" % ll[1]]}
	# Mur d'une pièce haute du niveau du dessous : il monte jusqu'ici.
	for v: Array in here.voids:
		if (v[1] as Dictionary).has(c):
			var p: Dictionary = v[0]
			return {"kind": "mur", "what": ["le mur de la pièce haute « %s »" % p.get("nom", p.id), "the wall of the high room \"%s\"" % p.get("nom", p.id)]}
	var center := MapGeom.cell_center(c)
	var cr := Rect2((Vector2(c) - Vector2.ONE * 0.5) * MapGeom.CELL, Vector2.ONE * MapGeom.CELL).grow(-0.02)
	var reach := MapGeom.WALL_HALF + MapGeom.CELL * 0.5
	for o: Dictionary in here.walls:
		var hit := false
		if String(o.type) == "mur":
			hit = MapGeom.dist_to_segment(center, MapGeom.v2(o.a), MapGeom.v2(o.b)) < reach
		else:
			var arc := MapShapes.wall_arc(o)
			for i in arc.size() - 1:
				if MapGeom.dist_to_segment(center, arc[i], arc[i + 1]) < reach:
					hit = true
					break
		if hit:
			var nm := _name(o)
			return {"kind": "obstacle", "what": [nm[0].to_lower(), nm[1].to_lower()], "of": o}
	for b: Array in _stair_blockers(ctx, j):
		if (b[1] as Rect2).intersects(cr):
			var nm := _name(b[0])
			return {"kind": "obstacle", "what": [nm[0].to_lower(), nm[1].to_lower()], "of": b[0]}
	return {"kind": "sol", "room": room}


## Refus d'un escalier : message, zones à montrer sur le plan (MapCanvas :
## « marks » [{floor, cells, role}] ; role « faute » en rouge, « depart »,
## « arrivee », « tremie » en contour). `kt` : niveau d'arrivée.
static func _stair_refuse(fr: String, en: String, bad_floor: int, bad: Array, k: int, parts: Dictionary, kt := -1) -> Dictionary:
	if kt < 0:
		kt = k + 1
	var r := refuse(fr, en)
	r["marks"] = [
		{"floor": k, "cells": _sorted_cells(parts.foot), "role": "depart"},
		{"floor": kt, "cells": _sorted_cells(parts.exit), "role": "arrivee"},
		{"floor": kt, "cells": _sorted_cells(parts.body), "role": "tremie"},
		{"floor": bad_floor, "cells": bad, "role": "faute"},
	]
	return r


## Bouts libres d'un escalier (départ au niveau k, arrivée au niveau kt) ?
static func _stair_ends_free(ctx: Dictionary, k: int, kt: int, parts: Dictionary) -> bool:
	if (parts.foot as Dictionary).is_empty() or (parts.exit as Dictionary).is_empty():
		return false
	for c in parts.foot:
		if String(_stair_cell(ctx, k, c).kind) != "sol":
			return false
	for c in parts.exit:
		var info := _stair_cell(ctx, kt, c)
		if String(info.kind) != "sol" and not _landing_ok(ctx, k, c, info, parts):
			return false
	return true


## Case d'arrivée `c` sur un mur (info : _stair_cell du niveau d'arrivée) qui
## devient un palier (MapRaster._landing) : mur commun de la pièce du pied
## (son bord, au niveau `k`) et d'une seule pièce d'arrivée, dont le sol est
## juste au-delà, à l'opposé des marches (deux pièces côte à côte
## d'altitudes différentes : demi-niveau).
static func _landing_ok(ctx: Dictionary, k: int, c: Vector2i, info: Dictionary, parts: Dictionary) -> bool:
	if String(info.kind) != "mur" or (info.get("rooms", []) as Array).size() != 1:
		return false
	var room: Dictionary = info.rooms[0]
	var bk := Vector2i(floori(c.x * MapGeom.CELL / BUCKET), floori(c.y * MapGeom.CELL / BUCKET))
	var foot_wall := false
	for r: Array in _stair_floor(ctx, k).room_grid.get(bk, []):
		if (r[1] as Dictionary).has(c):
			foot_wall = true
	if not foot_wall:
		return false
	var doc: EditorMap = ctx.doc
	var inner: Dictionary = _room_cells(doc.room_poly(room))[1]
	for d in MapValidator.DIRS:
		if (parts.body as Dictionary).has(c + d) and inner.has(c - d):
			return true
	return false


## Escalier `o` (rect, monte, rot, variante, altitude_haut) posé au niveau
## `k` : contrôles des niveaux qu'il relie, ceux du validateur, à la pose :
## pas dans la trémie ni sur le départ / l'arrivée d'un autre escalier ;
## trémie (vide au-dessus des marches, à chaque niveau traversé et au niveau
## d'arrivée) libre, sans plancher d'un niveau traversé au-dessus des marches ;
## départ (pied) sur le sol libre de la pièce ; arrivée sur le plancher libre
## d'une pièce du niveau d'arrivée (format 17 : celui de « altitude_haut »,
## n'importe lequel au-dessus ; absente : le niveau suivant ; un niveau
## d'arrivée encore vide est admis : la pièce viendra ensuite, le validateur
## le rappelle), ou à travers le mur commun d'une pièce posée à côté
## (_landing_ok). Sens : celui du validateur (pick_stair_dir ; un escalier
## droit sur la grille dont « monte » contredit la forme garde le seul sens
## possible, rendu dans « monte »). Pente : 40° au plus. Refus : quoi et où,
## zones fautives (« marks »). `down` : posé avec l'escalier qui descend
## (depuis le niveau d'arrivée) : « départ » en haut, « arrivée » en bas.
## Mots d'un bout d'escalier selon le sens de la pose (`top` : le haut, au
## niveau kt ; sinon le bas, au niveau k) : [fr, en, fr court, en court].
## Calculés seulement pour un refus (contrôle à chaque image d'un tracé).
static func _end_words(doc: EditorMap, k: int, kt: int, down: bool, top: bool) -> Array:
	var l := level_label(doc, kt if top else k)
	if top:
		return ["le départ (en haut, %s)" % l[0], "the start (at the top, %s)" % l[1], "le départ", "the start"] if down \
			else ["l'arrivée (en haut, %s)" % l[0], "the arrival (at the top, %s)" % l[1], "l'arrivée", "the arrival"]
	return ["l'arrivée (en bas, %s)" % l[0], "the arrival (at the bottom, %s)" % l[1], "l'arrivée", "the arrival"] if down \
		else ["le départ (au pied, %s)" % l[0], "the start (at the foot, %s)" % l[1], "le départ", "the start"]


static func check_stair(doc: EditorMap, k: int, o: Dictionary, ignore_id := "", down := false) -> Dictionary:
	# Niveaux figés pendant le contrôle (level_of sur chaque objet proche).
	doc.freeze_levels()
	var r := _check_stair(doc, k, o, ignore_id, down)
	doc.thaw_levels()
	return r


static func _check_stair(doc: EditorMap, k: int, o: Dictionary, ignore_id := "", down := false) -> Dictionary:
	if k < 0:
		return refuse("pas de niveau sous le plus bas : l'escalier qui descend se pose depuis un niveau plus haut (au niveau le plus bas, prenez l'escalier qui monte)",
			"no level below the lowest one: stairs going down are placed from a higher level (on the lowest level, use the stairs going up)")
	var kt := stair_top_level(doc, k, o)
	if kt < 0 and o.has("altitude_haut"):
		return refuse("aucune pièce à l'altitude d'arrivée (%s) : posez-y une pièce, ou réglez l'arrivée sur un niveau" % EditorMap.alt_text(EditorMap.stair_top(o)),
			"no room at the arrival altitude (%s): put a room there, or set the arrival on a level" % EditorMap.alt_text(EditorMap.stair_top(o), false))
	if kt < 0 or kt <= k:
		var lk0 := level_label(doc, k)
		return refuse("pas de niveau au-dessus du %s : ajoutez d'abord un niveau (onglet Niveaux), ou prenez l'escalier qui descend" % lk0[0],
			"no level above %s: add a level first (Levels tab), or use the stairs going down" % lk0[1])
	var y0 := doc.floor_sol(k)
	var y1 := doc.floor_sol(kt)
	# Zone des obstacles : le rectangle et une case autour (les bouts, dans les quatre sens).
	var ctx := {"doc": doc, "ignore": ignore_id, "floors": {}, "area": MapGeom.bbox(MapRaster.rect_poly(o)).grow(0.8)}
	# Sens retenu (règle du validateur) : escalier droit sur la grille seulement
	# (tourné, en L, en U, colimaçon : le sens tracé, comme le validateur).
	var kind := MapCatalog.stair_kind(o)
	var traced := String(o.get("monte", "n"))
	var monte := traced
	if not StairGen.is_shaped(kind) and MapRaster.rect_on_grid(o) and not _stair_ends_free(ctx, k, kt, stair_parts(o, y0, y1)):
		var valid := []
		for m in ["n", "e", "s", "o"]:
			var om := o.duplicate()
			om["monte"] = m
			if _stair_ends_free(ctx, k, kt, stair_parts(om, y0, y1)):
				valid.append(Vector2i(MapGeom.dir_vec(m)))
		var pick := pick_stair_dir(Vector2i(MapGeom.dir_vec(traced)), valid)
		for m in ["n", "e", "s", "o"]:
			if Vector2i(MapGeom.dir_vec(m)) == pick:
				monte = m
		if monte != traced:
			o = o.duplicate()
			o["monte"] = monte
	var parts := stair_parts(o, y0, y1)
	# Pente (même calcul que le validateur ; palier, L, U, colimaçon : validateur).
	if not (StairGen.is_shaped(kind) or kind == "palier"):
		var fr := MapRaster.stair_frame(o)
		var run := float(fr.length) - (0.0 if MapRaster.rect_on_grid(o) else MapGeom.CELL)
		var rise := y1 - y0
		var slope := rad_to_deg(atan2(rise, maxf(run, 0.01)))
		if slope > MapValidator.MAX_STAIR_SLOPE + 0.01:
			var need := ceilf((rise / tan(deg_to_rad(MapValidator.MAX_STAIR_SLOPE)) + (0.0 if MapRaster.rect_on_grid(o) else MapGeom.CELL)) / MapGeom.CELL) * MapGeom.CELL
			return refuse("escalier trop raide (%d° ; %d° au plus pour %s de montée, de %s à %s) : allongez-le à %s m" % [roundi(slope), int(MapValidator.MAX_STAIR_SLOPE), EditorMap.alt_text(rise), EditorMap.alt_text(y0), EditorMap.alt_text(y1), _m(need)],
				"stairs too steep (%d°; at most %d° for a %s rise, from %s to %s): make them %s m long" % [roundi(slope), int(MapValidator.MAX_STAIR_SLOPE), EditorMap.alt_text(rise, false), EditorMap.alt_text(y0, false), EditorMap.alt_text(y1, false), _m(need, false)])
	# Marches du niveau k : ni dans la trémie d'un escalier qui traverse ce
	# niveau, ni sur l'arrivée d'un escalier qui y monte ; ni sur le départ
	# d'un autre escalier du niveau.
	for s: Array in _stair_floor(ctx, k).wells:
		if not (parts.bb as Rect2i).intersects(s[1].bb) or String(s[0].get("id", "")) == ignore_id:
			continue
		var lb := stair_label_of(doc, s[0])
		var hit: Array = _common(parts.body, s[1].body)
		if not hit.is_empty():
			var p := _xy(hit[0])
			return _stair_refuse("l'escalier passe dans la trémie de %s %s : posez-le à côté (cage d'escalier : les volées côte à côte)" % [lb[0], p[0]],
				"the stairs run through the stairwell of %s %s: put them next to it (stair tower: flights side by side)" % [lb[1], p[1]], k, hit, k, parts, kt)
		if bool(s[2]):
			hit = _common(parts.body, s[1].exit)
			if not hit.is_empty():
				var p := _xy(hit[0])
				return _stair_refuse("l'escalier bloque l'arrivée de %s %s" % [lb[0], p[0]], "the stairs block the arrival of %s %s" % [lb[1], p[1]], k, hit, k, parts, kt)
	for s: Array in _stair_floor(ctx, k).stairs:
		if not (parts.bb as Rect2i).intersects(s[1].bb) or String(s[0].get("id", "")) == ignore_id:
			continue
		var lb := stair_label_of(doc, s[0])
		var hit: Array = _common(parts.body, s[1].foot)
		if not hit.is_empty():
			var p := _xy(hit[0])
			return _stair_refuse("l'escalier bloque le départ de %s %s" % [lb[0], p[0]], "the stairs block the start of %s %s" % [lb[1], p[1]], k, hit, k, parts, kt)
		# Sa trémie (niveaux traversés et d'arrivée) avalerait l'arrivée de
		# l'autre escalier (qui arrive au même niveau ou plus bas).
		if doc.stair_top_of(s[0]) <= y1 + EditorMap.ALT_EQ:
			hit = _common(parts.body, s[1].exit)
			if not hit.is_empty():
				var p := _xy(hit[0])
				return _stair_refuse("la trémie de l'escalier (le vide au-dessus de ses marches) tombe sur l'arrivée de %s %s" % [lb[0], p[0]],
					"the stairwell (the opening above the steps) falls on the arrival of %s %s" % [lb[1], p[1]], kt, hit, k, parts, kt)
		# Son départ ou son arrivée sur l'autre escalier (ou dans sa trémie).
		hit = _common(parts.foot, s[1].body)
		if not hit.is_empty():
			var p := _xy(hit[0])
			return _stair_refuse("%s chevauche %s %s" % [_cap(_end_words(doc, k, kt, down, false)[0]), lb[0], p[0]], "%s overlaps %s %s" % [_cap(_end_words(doc, k, kt, down, false)[1]), lb[1], p[1]], k, hit, k, parts, kt)
	# Trémie à chaque niveau traversé et au niveau d'arrivée : rien au-dessus
	# des marches (escalier, objet ; plancher d'un niveau traversé).
	var tremie_rect := MapGeom.bbox(MapRaster.rect_poly(o))
	for j in range(k + 1, kt + 1):
		var lj := level_label(doc, j)
		for s: Array in _stair_floor(ctx, j).stairs:
			if not (parts.bb as Rect2i).intersects(s[1].bb) or String(s[0].get("id", "")) == ignore_id:
				continue
			var lb := stair_label_of(doc, s[0])
			var hit: Array = _common(parts.body, s[1].body)
			if hit.is_empty():
				hit = _common(parts.body, s[1].foot)
				if not hit.is_empty():
					var p := _xy(hit[0])
					return _stair_refuse("la trémie de l'escalier (le vide au-dessus de ses marches, %s) tombe sur le départ de %s %s" % [lj[0], lb[0], p[0]],
						"the stairwell (the opening above the steps, %s) falls on the start of %s %s" % [lj[1], lb[1], p[1]], j, hit, k, parts, kt)
				continue
			var p := _xy(hit[0])
			return _stair_refuse("la trémie de l'escalier (le vide au-dessus de ses marches, %s) tombe sur %s %s : posez les escaliers côte à côte" % [lj[0], lb[0], p[0]],
				"the stairwell (the opening above the steps, %s) falls on %s %s: put the flights side by side" % [lj[1], lb[1], p[1]], j, hit, k, parts, kt)
		for e in _base_near(_stair_floor(ctx, j), tremie_rect):
			var q: Dictionary = e[0]
			var qr: Rect2 = e[1]
			if String(q.get("id", "")) == ignore_id or String(q.get("type", "")) == "escalier" or String(e[2]) != "sol" \
					or not qr.grow(-0.01).intersects(tremie_rect.grow(-0.01)):
				continue
			var hit := _sorted_cells(parts.body).filter(func(c): return Rect2((Vector2(c) - Vector2.ONE * 0.5) * MapGeom.CELL, Vector2.ONE * MapGeom.CELL).grow(-0.02).intersects(qr))
			if hit.is_empty():
				continue
			var nm := _name(q)
			var p := _xy(hit[0])
			return _stair_refuse("la trémie de l'escalier (le vide au-dessus de ses marches, %s) tombe sur %s %s : déplacez-le" % [lj[0], nm[0].to_lower(), p[0]],
				"the stairwell (the opening above the steps, %s) falls on %s %s: move it" % [lj[1], nm[1].to_lower(), p[1]], j, hit, k, parts, kt)
		if j == kt:
			continue
		# Niveau traversé : aucun plancher (sol ou mur d'une pièce) au-dessus des marches.
		var over := _sorted_cells(parts.body).filter(func(c): return String(_stair_cell(ctx, j, c).kind) in ["sol", "mur", "obstacle"])
		if not over.is_empty():
			var p := _xy(over[0])
			return _stair_refuse("le plancher du %s passe au-dessus des marches %s : un escalier qui saute des niveaux monte dans un vide (pièce haute) ; déplacez la pièce ou l'escalier" % [lj[0], p[0]],
				"the floor of %s runs above the steps %s: stairs that skip levels go up through a void (high room); move the room or the stairs" % [lj[1], p[1]], j, over, k, parts, kt)
	# Les deux bouts (chaque case examinée une seule fois).
	var upper_empty := (_stair_floor(ctx, kt).rooms as Array).is_empty()
	for end in [[k, parts.foot, false], [kt, parts.exit, true]]:
		var j: int = end[0]
		var cells := _sorted_cells(end[1])
		if cells.is_empty():
			var nm0 := _end_words(doc, k, kt, down, end[2])
			return _stair_refuse("%s de l'escalier n'a pas de place" % _cap(nm0[0]), "%s of the stairs has no room" % _cap(nm0[1]), j, [], k, parts, kt)
		var infos := cells.map(func(c): return _stair_cell(ctx, j, c))
		var bad := []
		var first := {}
		var first_c := Vector2i.ZERO
		for i in cells.size():
			if String(infos[i].kind) != "sol" and not (j == kt and _landing_ok(ctx, k, cells[i], infos[i], parts)):
				bad.append(cells[i])
				if first.is_empty():
					first = infos[i]
					first_c = cells[i]
		if first.is_empty():
			continue
		var name := _end_words(doc, k, kt, down, end[2])
		var kd := String(first.kind)
		var p := _xy(first_c)
		var what: Array = first.what
		var lj := level_label(doc, j)
		match kd:
			"vide":
				if j == kt and upper_empty:
					continue   # niveau d'arrivée encore vide : sa pièce viendra ensuite
				if j == kt and String(what[0]).begins_with("le vide (pas"):
					return _stair_refuse("pas de pièce au %s au-dessus %s de l'escalier %s : tracez-y une pièce, ou retournez l'escalier" % [lj[0], _de(name[2]), p[0]],
						"no room on %s above %s of the stairs %s: draw a room there, or turn the stairs around" % [lj[1], name[3], p[1]], j, bad, k, parts, kt)
				return _stair_refuse("%s tombe dans %s %s" % [_cap(name[0]), what[0], p[0]], "%s falls into %s %s" % [_cap(name[1]), what[1], p[1]], j, bad, k, parts, kt)
			"mur":
				return _stair_refuse("%s tombe dans %s %s : éloignez l'escalier du mur ou retournez-le" % [_cap(name[0]), what[0], p[0]],
					"%s falls into %s %s: move the stairs away from the wall or turn them around" % [_cap(name[1]), what[1], p[1]], j, bad, k, parts, kt)
			"tremie":
				return _stair_refuse("%s tombe dans %s %s" % [_cap(name[0]), what[0], p[0]], "%s falls into %s %s" % [_cap(name[1]), what[1], p[1]], j, bad, k, parts, kt)
			"escalier":
				return _stair_refuse("%s chevauche %s %s" % [_cap(name[0]), what[0], p[0]], "%s overlaps %s %s" % [_cap(name[1]), what[1], p[1]], j, bad, k, parts, kt)
			_:
				return _stair_refuse("%s : %s barre le passage %s" % [_cap(name[0]), what[0], p[0]], "%s: %s blocks the way %s" % [_cap(name[1]), what[1], p[1]], j, bad, k, parts, kt)
	return {"ok": true, "monte": monte, "to": kt}


## Cases communes à deux ensembles {case: true}, triées (vide : aucune).
static func _common(a: Dictionary, b: Dictionary) -> Array:
	var small := a if a.size() <= b.size() else b
	var big := b if small == a else a
	var hit := {}
	for c in small:
		if big.has(c):
			hit[c] = true
	return _sorted_cells(hit) if not hit.is_empty() else []


## Première lettre en majuscule (début de phrase).
static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


## « le départ » -> « du départ », « l'arrivée » -> « de l'arrivée ».
static func _de(s: String) -> String:
	if s.begins_with("le "):
		return "du " + s.substr(3)
	return "de " + s

# ------------------------------------------------------------------ barrière invisible (format 9)

## Contour d'une barrière invisible (polygone, m) : elle se pose N'IMPORTE
## OÙ (dans une pièce, à cheval sur un mur, dehors, par-dessus n'importe quel
## objet). Seules règles : 3 à 64 sommets, côtés de 5 cm au moins, côtés qui
## ne se croisent pas, 0,04 m² au moins (format 17 : coordonnées libres).
static func check_clip(poly: PackedVector2Array) -> Dictionary:
	var lim: Array = MapCatalog.CLIP_POINTS
	if poly.size() < int(lim[0]):
		return refuse("barrière invisible : 3 sommets au moins", "invisible barrier: at least 3 corners")
	if poly.size() > int(lim[1]):
		return refuse("barrière invisible : %d sommets au plus" % int(lim[1]), "invisible barrier: at most %d corners" % int(lim[1]))
	for i in poly.size():
		if poly[i].distance_to(poly[(i + 1) % poly.size()]) < MapCatalog.CLIP_MIN_SIDE:
			return refuse("barrière invisible : côté trop court (5 cm au moins)", "invisible barrier: side too short (at least 5 cm)")
	if not MapGeom.is_simple(poly):
		return refuse("barrière invisible : contour invalide (ses côtés se croisent)", "invisible barrier: invalid outline (its sides cross)")
	if MapGeom.area(poly) < MapCatalog.CLIP_MIN_AREA:
		return refuse("barrière invisible trop petite (0,04 m² au moins)", "invisible barrier too small (at least 0.04 m²)")
	if not CustomMapGuard.grid_ok(_grid_bytes(MapGeom.bbox(poly))):
		return refuse("barrière invisible trop grande pour la mémoire du validateur", "invisible barrier too large for the validator's memory")
	if Geometry2D.decompose_polygon_in_convex(poly).is_empty():
		return refuse("barrière invisible : contour invalide", "invisible barrier: invalid outline")
	return {"ok": true}


static func check_wall(a: Vector2, b: Vector2) -> Dictionary:
	if a.distance_to(b) < MapGeom.CELL - MapGeom.EPS:
		return refuse("mur trop court", "wall too short")
	if not CustomMapGuard.grid_ok(_grid_bytes(Rect2(a, Vector2.ZERO).expand(b))):
		return refuse("mur trop long pour la mémoire du validateur", "wall too long for the validator's memory")
	return {"ok": true}


## Mur courbe (arc en segments) : rayon d'un mètre au moins, ouverture de 5 à
## 360° (format 17 : où que ce soit, coordonnées négatives comprises).
static func check_arc(o: Dictionary) -> Dictionary:
	var r := float(o.get("rayon", 0.0))
	if r < 1.0 - MapGeom.EPS:
		return refuse("mur courbe trop petit (1 m de rayon au moins)", "curved wall too small (at least 1 m radius)")
	if r > MapShapes.MAX_RADIUS:
		return refuse("mur courbe trop grand", "curved wall too large")
	var op := float(o.get("ouverture", 0.0))
	if op < 5.0 or op > 360.0:
		return refuse("ouverture du mur courbe : 5 à 360°", "curved wall opening: 5 to 360°")
	return {"ok": true}


## Escalier déjà posé (MapEditor._update_invalid, à chaque modification de la
## carte) : check_rect, dont le résultat resert d'un lot à l'autre tant que
## rien de ce qu'il lit n'a changé : l'escalier, les niveaux, et pour chaque
## niveau de son pied à son arrivée, l'empreinte de sa base (pièces, pièces
## hautes, escaliers, murs libres, trémies : _stair_floor_base) et les objets
## proches (zone des obstacles, comme _stair_blockers). Hors lot : recalculé.
static func _check_existing_stair(doc: EditorMap, k: int, o: Dictionary) -> Dictionary:
	var main := not ThreadGuard.worker()
	var kt := stair_top_level(doc, k, o)
	if not main or _batch_doc != doc or kt <= k:
		return check_rect(doc, k, "escalier", MapGeom.rect_of(o.rect), String(o.id), MapGeom.rot_of(o), "", o)
	doc.freeze_levels()
	var area := MapGeom.bbox(MapRaster.rect_poly(o)).grow(0.8)
	var key := [o, doc.levels(), overlaps_allowed(doc)]
	for j in range(k, kt + 1):
		var base := _stair_floor_base(doc, j)
		key.append(int(base.get("fp", 0)))
		key.append(_base_near(base, area).map(func(e): return e[0]))
	doc.thaw_levels()
	var h := key.hash()
	var hit: Array = _stair_results.get(h, [])
	if not hit.is_empty() and hit[0] == doc and hit[1] == key:
		return (hit[2] as Dictionary).duplicate(true)
	var r := check_rect(doc, k, "escalier", MapGeom.rect_of(o.rect), String(o.id), MapGeom.rot_of(o), "", o)
	if _stair_results.size() > 512:
		_stair_results.clear()
	_stair_results[h] = [doc, key.duplicate(true), r.duplicate(true)]
	return r


## Résultats de _check_existing_stair (fil principal) : empreinte -> [carte, clé, résultat].
static var _stair_results: Dictionary = {}


## Vérifie un élément déjà posé (dessin en rouge des éléments devenus invalides).
static func check_existing(doc: EditorMap, o: Dictionary) -> Dictionary:
	var k := doc.level_of(o)
	var t := String(o.get("type", ""))
	if k < 0:
		return refuse("aucune pièce à son altitude (%s) : posez-le au niveau d'une pièce" % EditorMap.alt_text(EditorMap.alt_of(o)),
			"no room at its altitude (%s): put it on a room's level" % EditorMap.alt_text(EditorMap.alt_of(o), false))
	if o.has("contour"):
		return check_room(doc, k, doc.room_poly(o), String(o.id))
	if t in ouvertures_types():
		var r := place_opening(doc, k, t, MapGeom.v2(o.position), opening_width(o), String(o.id))
		if r.ok and MapGeom.v2(r.position).distance_to(MapGeom.v2(o.position)) > 0.3:
			return refuse("n'est plus sur un mur valide", "is no longer on a valid wall")
		return r
	if MapCatalog.is_decor(o) and MapCatalog.tool_of(o) == "wall_item":
		return wall_decor_still_on_wall(doc, o)
	match MapCatalog.tool_of(o):
		"wall_item":
			# Curseur juste devant la face (0,05 m) : le mur de l'objet reste le plus
			# proche, même au raccord d'un mur libre et d'un mur de la pièce.
			var r := place_wall_item(doc, k, o, MapGeom.v2(o.position) - MapGeom.item_wall_dir(o) * 0.3, String(o.id))
			if r.ok:
				# Même mur, même direction (à 0,6° près), à la même place.
				var now := o.duplicate()
				apply_wall(now, r)
				if MapGeom.v2(r.position).distance_to(MapGeom.v2(o.position)) > 0.3 or MapGeom.item_wall_dir(now).dot(MapGeom.item_wall_dir(o)) < 0.99995:
					return refuse("n'est plus contre un mur", "is no longer against a wall")
			return r
		"floor_item":
			if MapCatalog.floor_box(o):
				# Format 15 : boîte au sol, à sa place et sa rotation exactes.
				return place_floor_box(doc, k, o, MapGeom.v2(o.position), String(o.id), false)
			return place_floor_item(doc, k, o, MapGeom.v2(o.position), String(o.id), false)
		"rect":
			# Escalier : lui-même (sens, type), sans le rechercher dans la carte.
			if t == "escalier":
				return _check_existing_stair(doc, k, o)
			return check_rect(doc, k, t, MapGeom.rect_of(o.rect), String(o.id), MapGeom.rot_of(o), "", {})
		"poly":
			return check_clip(MapRaster.clip_poly(o))
		"wall":
			return check_wall(MapGeom.v2(o.a), MapGeom.v2(o.b))
		"arc":
			return check_arc(o)
	return {"ok": true}
