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


## Bords communs de deux pièces collées de l'étage : [{a, b, rooms: [id, id]}].
static func shared_edges(doc: EditorMap, k: int) -> Array:
	var out := []
	var rooms := doc.rooms_on(k)
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			for s in MapGeom.common_segments(doc.room_poly(rooms[i]), doc.room_poly(rooms[j])):
				out.append({"a": s[0], "b": s[1], "rooms": [String(rooms[i].id), String(rooms[j].id)]})
	return out


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
			for pc in pieces:
				var outside := _outside(poly, pc[0], pc[1])
				if voids.any(func(vp): return MapGeom.strictly_inside(vp, outside)):
					continue
				out.append({"a": pc[0], "b": pc[1], "room": String(r.id)})
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
## -> {ok, position, rooms, horizontal} ou {ok: false, fr, en}.
static func place_opening(doc: EditorMap, k: int, type: String, mouse: Vector2, width: float, ignore_id := "") -> Dictionary:
	var window := type == "fenetre"
	var cands := outer_edges(doc, k) if window else shared_edges(doc, k)
	var best = null
	var best_d := SNAP_DIST
	for e in cands:
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		if absf(a.x - b.x) > MapGeom.EPS and absf(a.y - b.y) > MapGeom.EPS:
			continue   # mur en biais : pas d'ouverture
		var d := MapGeom.dist_to_segment(mouse, a, b)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		if window:
			return refuse("une fenêtre se pose sur un mur extérieur droit d'une pièce (visez le bord de la pièce, côté dehors)",
				"a window goes on a straight outer wall of a room (aim at the room's edge, outside side)")
		if doc.rooms_on(k).size() < 2 or shared_edges(doc, k).is_empty():
			return refuse("une porte relie deux pièces : il faut deux pièces collées (un bord commun) à cet étage",
				"a door links two rooms: you need two touching rooms (a shared edge) on this floor")
		return refuse("visez le mur commun de deux pièces collées : une porte ne donne que sur une autre pièce",
			"aim at the shared wall of two touching rooms: a door only leads into another room")
	var a: Vector2 = best.a
	var b: Vector2 = best.b
	var horizontal := absf(a.y - b.y) < MapGeom.EPS
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
	var line := a.y if horizontal else a.x
	var pos := Vector2(along, line) if horizontal else Vector2(line, along)
	var span := Vector2(along - w * 0.5, along + w * 0.5)
	# Autres ouvertures du même mur : 0,5 m de mur entre deux ouvertures.
	for o in doc.openings_on(k):
		if String(o.id) == ignore_id:
			continue
		var op := MapGeom.v2(o.position)
		if absf((op.y if horizontal else op.x) - line) > MapGeom.EPS:
			continue
		var s := opening_span(o, horizontal)
		if s.x < span.y + END_MARGIN - MapGeom.EPS and s.y > span.x - END_MARGIN + MapGeom.EPS:
			var nm := _name(o)
			return refuse("trop près d'une autre ouverture (%s) : laissez 0,5 m de mur entre les deux" % nm[0].to_lower(),
				"too close to another opening (%s): leave 0.5 m of wall between them" % nm[1].to_lower())
	# Objets muraux contre ce mur à cet endroit.
	for o in doc.objects_on(k):
		if MapCatalog.tool_of(o) != "wall_item":
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
		return MapGeom.rect_of(o.rect)
	if t == "mur":
		var half := float(o.get("epaisseur", 0.5)) * 0.5
		return Rect2(MapGeom.v2(o.a), Vector2.ZERO).expand(MapGeom.v2(o.b)).grow(half)
	var fp := MapCatalog.footprint(o)
	var p := MapGeom.v2(o.get("position", [0, 0]))
	if MapCatalog.tool_of(o) == "wall_item":
		var d := MapGeom.dir_vec(String(o.get("mur", "n")))
		var along := fp.x * MapGeom.CELL
		var depth := fp.y * MapGeom.CELL
		# Face du mur à 0,25 m du trait, objet devant (côté intérieur).
		var face := p - d * MapGeom.CELL * 0.5
		var back := face - d * depth
		var lat := Vector2(absf(d.y), absf(d.x)) * along * 0.5
		return Rect2(face - lat, Vector2.ZERO).expand(back + lat)
	var s := fp.x * MapGeom.CELL
	return Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s))


## L'élément `o` couvre-t-il le point `p` (clic, gomme) ?
static func hit(doc: EditorMap, o: Dictionary, p: Vector2) -> bool:
	if o.has("contour"):
		return MapGeom.contains(doc.room_poly(o), p)
	if String(o.get("type", "")) == "mur":
		return MapGeom.dist_to_segment(p, MapGeom.v2(o.a), MapGeom.v2(o.b)) <= maxf(0.3, float(o.get("epaisseur", 0.5)) * 0.5)
	if o.has("position") and not o.has("rect") and ouvertures_types().has(String(o.get("type", ""))):
		return MapGeom.v2(o.position).distance_to(p) <= maxf(0.5, opening_width(o) * 0.5)
	return footprint_rect(o).grow(0.05).has_point(p)


static func ouvertures_types() -> Array:
	return ["porte", "debris", "porte_courant", "passage", "fenetre"]


## Chevauchement avec les objets de l'étage (lampes : au plafond, jamais).
static func _overlaps(doc: EditorMap, k: int, r: Rect2, ignore_id: String, skip_lamps := true) -> Dictionary:
	for o in doc.objects_on(k):
		if String(o.id) == ignore_id or String(o.type) == "mur":
			continue
		if skip_lamps and String(o.type) == "lampe":
			continue
		if footprint_rect(o).grow(-0.01).intersects(r.grow(-0.01)):
			return o
	return {}


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
		if absf(a.x - b.x) > MapGeom.EPS and absf(a.y - b.y) > MapGeom.EPS:
			continue
		var d := MapGeom.dist_to_segment(mouse, a, b)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return refuse("rapprochez-vous d'un mur droit : %s se pose contre un mur" % nm[0].to_lower(), "move closer to a straight wall: %s stands against a wall" % nm[1].to_lower())
	var a := poly[best]
	var b := poly[(best + 1) % poly.size()]
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
	var span := Vector2(along - w * 0.5, along + w * 0.5)
	for o in doc.openings_on(k):
		var op := MapGeom.v2(o.position)
		if absf((op.y if horizontal else op.x) - line) > MapGeom.EPS:
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
	var other := _overlaps(doc, k, fr, ignore_id)
	if not other.is_empty():
		var on := _name(other)
		return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	return {"ok": true, "position": obj.position, "mur": dir, "room": String(room.id)}


## Pose d'un objet au sol (départ, apparition, téléporteur, lampe, caisse...).
static func place_floor_item(doc: EditorMap, k: int, tmpl: Dictionary, mouse: Vector2, ignore_id := "") -> Dictionary:
	var n := MapCatalog.footprint(tmpl).x
	var pos := Vector2(MapGeom.snap_along(mouse.x, n), MapGeom.snap_along(mouse.y, n))
	var obj := tmpl.duplicate()
	obj["position"] = MapGeom.arr(pos)
	var nm := _name(tmpl)
	var room := room_at(doc, k, pos)
	if room.is_empty():
		return refuse("%s se pose à l'intérieur d'une pièce" % nm[0], "%s goes inside a room" % nm[1])
	var inner := {}
	for c in MapRaster.room_cells(doc.room_poly(room))[1]:
		inner[c] = true
	for c in MapRaster._square(obj, n):
		if not inner.has(c):
			return refuse("%s touche un mur : posez-le plus au milieu de la pièce" % nm[0], "%s touches a wall: place it further inside the room" % nm[1])
	if String(tmpl.get("type", "")) != "lampe":
		var fr := footprint_rect(obj)
		var other := _overlaps(doc, k, fr, ignore_id)
		if not other.is_empty():
			var on := _name(other)
			return refuse("chevauche %s" % on[0].to_lower(), "overlaps %s" % on[1].to_lower())
	return {"ok": true, "position": obj.position, "room": String(room.id)}


## Rectangle au sol (pilier, escalier, piège) : dans une seule pièce, sans chevauchement.
static func check_rect(doc: EditorMap, k: int, type: String, r: Rect2, ignore_id := "") -> Dictionary:
	var o := {"type": type}
	var nm := _name(o)
	if r.size.x < MapGeom.CELL * 2 - MapGeom.EPS or r.size.y < MapGeom.CELL * 2 - MapGeom.EPS:
		return refuse("%s trop petit (1 m de côté au moins)" % nm[0], "%s too small (at least 1 m per side)" % nm[1])
	var room := room_at(doc, k, r.get_center())
	if room.is_empty():
		return refuse("%s se pose à l'intérieur d'une pièce" % nm[0], "%s goes inside a room" % nm[1])
	var poly := doc.room_poly(room)
	for c in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
		if not MapGeom.contains(poly, c.lerp(r.get_center(), 0.01)) and not MapGeom.on_boundary(poly, c, 0.01):
			return refuse("%s déborde de la pièce « %s »" % [nm[0], room.get("nom", room.id)], "%s sticks out of room \"%s\"" % [nm[1], room.get("nom", room.id)])
	if type == "escalier":
		if k >= doc.floor_count() - 1:
			return refuse("un escalier monte à l'étage du dessus : ajoutez d'abord un étage (onglet Étages)", "stairs go up to the floor above: add a floor first (Floors tab)")
		if minf(r.size.x, r.size.y) < 1.5 - MapGeom.EPS:
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
			var r := place_wall_item(doc, k, o, MapGeom.v2(o.position) - MapGeom.dir_vec(String(o.get("mur", "n"))) * 0.6, String(o.id))
			if r.ok and (MapGeom.v2(r.position).distance_to(MapGeom.v2(o.position)) > 0.3 or String(r.mur) != String(o.get("mur", ""))):
				return refuse("n'est plus contre un mur", "is no longer against a wall")
			return r
		"floor_item":
			return place_floor_item(doc, k, o, MapGeom.v2(o.position), String(o.id))
		"rect":
			return check_rect(doc, k, t, MapGeom.rect_of(o.rect), String(o.id))
		"wall":
			return check_wall(MapGeom.v2(o.a), MapGeom.v2(o.b))
	return {"ok": true}
