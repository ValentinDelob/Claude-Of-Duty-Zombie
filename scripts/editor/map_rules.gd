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
##     chevauchement.
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

static func check_room(doc: EditorMap, k: int, poly: PackedVector2Array, ignore_id := "") -> Dictionary:
	if poly.size() < 3 or not MapGeom.is_simple(poly):
		return refuse("contour invalide : ses côtés se croisent", "invalid outline: its sides cross")
	if poly.size() > CustomMapGuard.MAX_VERTICES:
		return refuse("trop de sommets (%d au plus)" % CustomMapGuard.MAX_VERTICES, "too many vertices (%d at most)" % CustomMapGuard.MAX_VERTICES)
	for i in poly.size():
		if poly[i].distance_to(poly[(i + 1) % poly.size()]) < 0.1:
			return refuse("côté trop court (10 cm au moins)", "side too short (at least 10 cm)")
	var bb := MapGeom.bbox(poly)
	if bb.position.x < -MapGeom.EPS or bb.position.y < -MapGeom.EPS:
		return refuse("hors du terrain : x et y doivent rester positifs", "off the board: x and y must stay positive")
	if bb.size.x < MIN_ROOM_SIDE or bb.size.y < MIN_ROOM_SIDE or MapGeom.area(poly) < 2.0:
		return refuse("pièce trop petite (1,5 m de côté au moins)", "room too small (at least 1.5 m per side)")
	for p in doc.rooms_on(k):
		if String(p.id) != ignore_id and MapGeom.overlap(poly, doc.room_poly(p)):
			return refuse("elle chevauche la pièce « %s » (deux pièces peuvent se toucher, pas se recouvrir)" % p.get("nom", p.id),
				"it overlaps room \"%s\" (rooms may touch, not overlap)" % p.get("nom", p.id))
	return {"ok": true}


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
	if k > 0:
		for p in doc.rooms_on(k - 1):
			if p.get("double_hauteur", false):
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

## Largeur (m) d'une ouverture.
static func opening_width(o: Dictionary) -> float:
	return 1.0 if String(o.get("type", "")) == "fenetre" else float(o.get("largeur", 2.0))


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
	var best = null
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
			return refuse("une porte relie deux pièces : il faut deux pièces collées (un bord commun) à cet étage",
				"a door links two rooms: you need two touching rooms (a shared edge) on this floor")
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
		var half := MapCatalog.footprint(o).x * MapGeom.CELL * 0.5
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
		var c0 := pos + out_dir * 0.3 - side * POCKET.y * 0.5
		var c1 := pos + out_dir * POCKET.x + side * POCKET.y * 0.5
		var pocket := MapGeom.rect_poly(Rect2(c0, Vector2.ZERO).expand(c1))
		for q in doc.rooms_on(k):
			if MapGeom.overlap(pocket, doc.room_poly(q)):
				return refuse("pas de place dehors pour les zombies : il faut 2,5 m × 3 m de vide derrière la fenêtre (gêné par « %s »)" % q.get("nom", q.id),
					"no room outside for the zombies: 2.5 m × 3 m of empty space is needed behind the window (blocked by \"%s\")" % q.get("nom", q.id))
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
	var w := 1.0 if window else maxi(1, roundi(width / MapGeom.CELL)) * MapGeom.CELL
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
		var half := MapCatalog.footprint(o).x * MapGeom.CELL * 0.5
		var oc := (op - a).dot(t)
		if oc - half < s + w * 0.5 - MapGeom.EPS and oc + half > s - w * 0.5 + MapGeom.EPS:
			var nm := _name(o)
			return refuse("%s est contre ce mur à cet endroit" % nm[0], "%s stands against this wall here" % nm[1])
	var res := {"ok": true, "position": MapGeom.arr(pos), "horizontal": false, "dir": [t.x, t.y]}
	if window:
		res["rooms"] = [best.room]
		var poly := doc.room_poly(doc.find(best.room))
		var out_dir := (_outside(poly, a, b, 0.3) - (a + b) * 0.5).normalized()
		var pocket := pocket_poly(pos, out_dir)
		for q in doc.rooms_on(k):
			if MapGeom.overlap(pocket, doc.room_poly(q)):
				return refuse("pas de place dehors pour les zombies : il faut 2,5 m × 3 m de vide derrière la fenêtre (gêné par « %s »)" % q.get("nom", q.id),
					"no room outside for the zombies: 2.5 m × 3 m of empty space is needed behind the window (blocked by \"%s\")" % q.get("nom", q.id))
	else:
		res["rooms"] = best.rooms
	return res


## Cour des zombies derrière une fenêtre en `pos` (sur le trait), `out_dir`
## vers dehors : 3 m le long du mur, de 0,3 à 2,75 m du trait.
static func pocket_poly(pos: Vector2, out_dir: Vector2) -> PackedVector2Array:
	return MapGeom.oriented_rect(pos + out_dir * 0.3, out_dir, POCKET.y, POCKET.x - 0.3)


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


## Emprise (m) d'un élément posé, pour le dessin, le clic et les chevauchements.
static func footprint_rect(o: Dictionary) -> Rect2:
	var t := String(o.get("type", ""))
	if o.has("rect"):
		if MapGeom.rot_of(o) != 0:
			return MapGeom.bbox(MapRaster.rect_poly(o))
		return MapGeom.rect_of(o.rect)
	if t == "mur":
		var half := float(o.get("epaisseur", 0.5)) * 0.5
		return Rect2(MapGeom.v2(o.a), Vector2.ZERO).expand(MapGeom.v2(o.b)).grow(half)
	if t == "mur_courbe":
		return MapGeom.bbox(MapShapes.wall_arc(o)).grow(float(o.get("epaisseur", 0.5)) * 0.5)
	var fp := MapCatalog.footprint(o)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	var tool := MapCatalog.tool_of(o)
	if tool == "floor_item" and MapRaster.free_rot(o) and MapCatalog.rotates(o):
		return MapGeom.bbox(MapRaster.floor_poly(o))
	if tool == "wall_item" and MapGeom.item_oblique(o):
		# Contre un mur en biais : rectangle englobant de l'emprise tournée.
		return MapGeom.bbox(wall_item_poly(o))
	if tool == "wall_item":
		var d := MapGeom.dir_vec(String(o.get("mur", "n")))
		var along := fp.x * MapGeom.CELL
		var depth := fp.y * MapGeom.CELL
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
	var fp := MapCatalog.footprint(o)
	var dv := MapGeom.item_wall_dir(o)
	var face := MapGeom.v2(o.get("position", [0, 0])) - dv * MapGeom.WALL_HALF
	return MapGeom.oriented_rect(face, -dv, fp.x * MapGeom.CELL, fp.y * MapGeom.CELL)


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
	if String(o.get("type", "")) == "mur":
		return MapGeom.dist_to_segment(p, MapGeom.v2(o.a), MapGeom.v2(o.b)) <= maxf(0.3, float(o.get("epaisseur", 0.5)) * 0.5)
	if String(o.get("type", "")) == "mur_courbe":
		var half := maxf(0.3, float(o.get("epaisseur", 0.5)) * 0.5)
		return MapShapes.arc_segments(o).any(func(s): return MapGeom.dist_to_segment(p, s[0], s[1]) <= half)
	if o.has("position") and not o.has("rect") and ouvertures_types().has(String(o.get("type", ""))):
		return MapGeom.v2(o.position).distance_to(p) <= maxf(0.5, opening_width(o) * 0.5)
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


static func begin_batch(doc: EditorMap) -> void:
	if not ThreadGuard.main_only("MapRules.begin_batch"):   # fil principal seulement
		return
	_batch = {}
	_batch_doc = doc
	for o in doc.objets:
		if String(o.get("type", "")) in ["mur", "mur_courbe"]:
			continue
		var r := footprint_rect(o)
		var e := [o, r, layer_of(o)]
		var grid: Dictionary = _batch.get_or_add(int(o.get("etage", 0)), {})
		for b in _buckets(r):
			grid.get_or_add(b, []).append(e)


static func end_batch() -> void:
	if not ThreadGuard.main_only("MapRules.end_batch"):   # fil principal seulement
		return
	_batch = {}
	_batch_doc = null


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
		if not String(o.get("type", "")) in ["mur", "mur_courbe"]:
			out.append([o, footprint_rect(o), layer_of(o)])
	return out


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
	return float(MapCatalog.def_of(o).get("support", 0.0)) if String(o.get("type", "")) == "prefab" else (1.0 if String(o.get("type", "")) == "caisse" else 0.0)


## Meuble sous un luminaire posé au sol ({} : posé par terre).
static func support_under(doc: EditorMap, o: Dictionary) -> Dictionary:
	var r := footprint_rect(o)
	for other in _overlaps_all(doc, int(o.get("etage", 0)), r, String(o.get("id", "")), "sol"):
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
	if main and _inner_cache.size() > 64:
		_inner_cache.clear()
	var inner := {}
	for c in MapRaster.room_cells(poly)[1]:
		inner[c] = true
	if main:
		_inner_cache[key] = inner
	return inner


## Pose d'un objet contre un mur (atout, arme, boîte, Pack-a-Punch...).
static func place_wall_item(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, ignore_id := "") -> Dictionary:
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
static func _free_wall_room_check(doc: EditorMap, k: int, obj: Dictionary, poly: PackedVector2Array, segs: Array, fw: int) -> Dictionary:
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


## Pose d'un objet au sol (départ, apparition, téléporteur, lampe, caisse,
## prefab, luminaire...). Emprise rectangulaire, rotation comprise (prefabs).
## Couches (layer_of) : un luminaire du plafond ne gêne que les autres
## luminaires du plafond ; un luminaire posé au sol peut se poser sur un
## meuble qui a un dessus (support : bureau, chariot...).
static func place_floor_item(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, ignore_id := "", grid := true) -> Dictionary:
	var n := MapCatalog.floor_size(tmpl)
	var pos := Vector2(MapGeom.snap_along(mouse.x, n.x), MapGeom.snap_along(mouse.y, n.y))
	if not grid or MapRaster.free_rot(tmpl):
		# Sans grille, ou tourné au degré près : là où est le curseur (au centimètre).
		pos = MapGeom.round_cm(mouse)
	var obj := tmpl.duplicate()
	obj["position"] = MapGeom.arr(pos)
	var nm := _name(tmpl)
	var room := room_at(doc, k, pos)
	if room.is_empty():
		return refuse("%s se pose à l'intérieur d'une pièce" % nm[0], "%s goes inside a room" % nm[1])
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
	if not others.is_empty():
		var on := _name(others[0])
		return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	var res := {"ok": true, "position": obj.position, "room": String(room.id)}
	if not on_top.is_empty():
		res["sur"] = String(on_top.id)
	return res


## Rectangle au sol (pilier, escalier, piège) : dans une seule pièce, sans
## chevauchement ; `rot` : rotation au degré près (sens horaire) autour de son centre.
static func check_rect(doc: EditorMap, k: int, type: String, r: Rect2, ignore_id := "", rot := 0) -> Dictionary:
	var o := {"type": type}
	var nm := _name(o)
	var sz0 := r.size   # taille avant rotation (largeur d'un escalier)
	if r.size.x < MapGeom.CELL * 2 - MapGeom.EPS or r.size.y < MapGeom.CELL * 2 - MapGeom.EPS:
		return refuse("%s trop petit (1 m de côté au moins)" % nm[0], "%s too small (at least 1 m per side)" % nm[1])
	var room := room_at(doc, k, r.get_center())
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
		if k >= doc.floor_count() - 1:
			return refuse("un escalier monte à l'étage du dessus : ajoutez d'abord un étage (onglet Étages)", "stairs go up to the floor above: add a floor first (Floors tab)")
		if minf(sz0.x, sz0.y) < 1.5 - MapGeom.EPS:
			return refuse("escalier trop étroit (1,5 m au moins)", "stairs too narrow (at least 1.5 m)")
	var other := _overlaps(doc, k, r, ignore_id)
	if not other.is_empty():
		var on := _name(other)
		return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	return {"ok": true, "room": String(room.id)}


static func check_wall(a: Vector2, b: Vector2) -> Dictionary:
	if a.distance_to(b) < MapGeom.CELL - MapGeom.EPS:
		return refuse("mur trop court", "wall too short")
	if minf(a.x, b.x) < -MapGeom.EPS or minf(a.y, b.y) < -MapGeom.EPS:
		return refuse("hors du terrain : x et y doivent rester positifs", "off the board: x and y must stay positive")
	return {"ok": true}


## Mur courbe (arc en segments) : rayon d'un mètre au moins, ouverture de 5 à
## 360°, dans le terrain.
static func check_arc(o: Dictionary) -> Dictionary:
	var r := float(o.get("rayon", 0.0))
	if r < 1.0 - MapGeom.EPS:
		return refuse("mur courbe trop petit (1 m de rayon au moins)", "curved wall too small (at least 1 m radius)")
	if r > MapShapes.MAX_RADIUS:
		return refuse("mur courbe trop grand", "curved wall too large")
	var op := float(o.get("ouverture", 0.0))
	if op < 5.0 or op > 360.0:
		return refuse("ouverture du mur courbe : 5 à 360°", "curved wall opening: 5 to 360°")
	var bb := MapGeom.bbox(MapShapes.wall_arc(o))
	if bb.position.x < -MapGeom.EPS or bb.position.y < -MapGeom.EPS:
		return refuse("hors du terrain : x et y doivent rester positifs", "off the board: x and y must stay positive")
	return {"ok": true}


## Vérifie un élément déjà posé (dessin en rouge des éléments devenus invalides).
static func check_existing(doc: EditorMap, o: Dictionary) -> Dictionary:
	var k := int(o.get("etage", 0))
	var t := String(o.get("type", ""))
	if o.has("contour"):
		return check_room(doc, k, doc.room_poly(o), String(o.id))
	if t in ouvertures_types():
		var r := place_opening(doc, k, t, MapGeom.v2(o.position), opening_width(o), String(o.id))
		if r.ok and MapGeom.v2(r.position).distance_to(MapGeom.v2(o.position)) > 0.3:
			return refuse("n'est plus sur un mur valide", "is no longer on a valid wall")
		return r
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
			return place_floor_item(doc, k, o, MapGeom.v2(o.position), String(o.id), false)
		"rect":
			return check_rect(doc, k, t, MapGeom.rect_of(o.rect), String(o.id), MapGeom.rot_of(o))
		"wall":
			return check_wall(MapGeom.v2(o.a), MapGeom.v2(o.b))
		"arc":
			return check_arc(o)
	return {"ok": true}
