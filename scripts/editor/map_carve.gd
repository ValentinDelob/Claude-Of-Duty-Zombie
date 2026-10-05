class_name MapCarve
extends RefCounted
## DÉCOUPE DES PIÈCES de l'éditeur de cartes (docs/MAP_AUTHORING.md § 3,
## « Pièce tracée sur une autre ») : une pièce tracée (rectangle, polygone,
## forme) PAR-DESSUS une ou plusieurs pièces du même étage les « grignote » :
## chaque pièce recouverte perd la partie sous la nouvelle (soustraction de
## polygones, Geometry2D.clip_polygons), après confirmation de l'utilisateur.
## Le format n'a PAS de trou (un contour simple par pièce) :
##   - nouvelle pièce entièrement dedans (l'ancienne ferait un anneau) :
##     l'ancienne est coupée en deux par une ligne de la grille qui traverse
##     la nouvelle (la moins gênante : place pour un passage des deux côtés,
##     aucun objet coupé, au plus près du milieu) ; les deux morceaux gardent
##     la même zone, reliés par un PASSAGE LIBRE sur chaque bord commun ;
##   - ancienne pièce coupée en plusieurs morceaux : une pièce par morceau
##     (mêmes réglages, noms « Atelier », « Atelier (2) »…) ; le plus grand
##     garde l'identifiant ; un morceau qui ne touche pas les autres (ou sans
##     place pour un passage) a sa PROPRE zone, copiée de l'ancienne ;
##   - morceau trop petit (MapRules : 1,5 m de côté, 2 m²) ou trop mince
##     (moins de 0,6 m de large en moyenne) : retiré ; plus aucun morceau :
##     l'ancienne pièce est supprimée.
## La nouvelle pièce garde SA zone (une zone par pièce, comme toute pièce
## posée ; outil ou MCP : celle qu'elle porte). Le contenu (objets, décor,
## effets, luminaires) suit sa position : celui de la partie découpée est
## désormais dans la nouvelle pièce ; celui d'un morceau retiré, hors de toute
## pièce, est supprimé. Ouvertures dont le mur disparaît : déplacées sur le
## bord commun le plus proche qui relie les mêmes zones, sinon retirées.
## Escalier rendu invalide (pied, arrivée, trémie) : découpe REFUSÉE. Autres
## éléments devenus invalides : gardés, listés « à revoir ».

## Aire (m²) sous laquelle un morceau est un reste d'arrondi (ignoré).
const MIN_PART_AREA := 0.01
## Largeur moyenne (2 × aire / périmètre, m) sous laquelle un morceau est retiré.
const MIN_PART_WIDTH := 0.6
## Bord commun minimal pour un passage libre de 1 m (0,5 m de mur de chaque côté).
const PASSAGE_EDGE := 2.0
const PASSAGE_MAX := 20.0
## Marge (m) autour des pièces touchées où les éléments sont revérifiés (cour
## des zombies d'une fenêtre : 2,75 m).
const REGION_MARGIN := 4.0
## Types jamais supprimés avec un morceau retiré (posés n'importe où).
const FREE_TYPES := ["bloc_invisible", "mur", "mur_courbe"]


# ------------------------------------------------------------------ géométrie

## Pièces de l'étage `k` que le contour `poly` recouvre (plus que les toucher).
static func overlaps(doc: EditorMap, k: int, poly: PackedVector2Array, ignore_id := "") -> Array:
	var out := []
	for p in doc.rooms_on(k):
		if String(p.get("id", "")) != ignore_id and MapGeom.overlap(poly, doc.room_poly(p)):
			out.append(p)
	return out


## Parties recouvertes (aperçu hachuré) : [{id, nom, parts: [poly], area}].
static func covered(doc: EditorMap, k: int, poly: PackedVector2Array, ignore_id := "") -> Array:
	var out := []
	for p in overlaps(doc, k, poly, ignore_id):
		var parts := []
		var s := 0.0
		for part in Geometry2D.intersect_polygons(doc.room_poly(p), poly):
			var a := MapGeom.area(part)
			if a > MIN_PART_AREA:
				parts.append(part)
				s += a
		out.append({"id": String(p.id), "nom": String(p.get("nom", p.id)), "parts": parts, "area": s})
	return out


## Contour nettoyé : sommets au millimètre, sans doublon ni sommet aligné.
static func clean(p: PackedVector2Array) -> PackedVector2Array:
	var pts := []
	for v in p:
		pts.append(Vector2(snappedf(v.x, 0.001), snappedf(v.y, 0.001)))
	var again := true
	while again and pts.size() > 3:
		again = false
		var n := pts.size()
		for i in n:
			var a: Vector2 = pts[(i - 1 + n) % n]
			var v: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			if v.distance_to(a) < 0.002 or MapGeom.dist_to_segment(v, a, b) < 0.002:
				pts.remove_at(i)
				again = true
				break
	return PackedVector2Array(pts)


## `a` moins `b` en contours SIMPLES (sans trou) : [poly, ...] ; null si la
## découpe n'aboutit pas. Un anneau (b dans a) est d'abord coupé en deux par
## une ligne de la grille qui traverse b (_best_cut ; `objs` : objets à ne pas
## couper).
static func subtract(a: PackedVector2Array, b: PackedVector2Array, objs := [], depth := 0) -> Variant:
	var parts := []
	for part in Geometry2D.clip_polygons(a, b):
		if MapGeom.area(part) > MIN_PART_AREA:
			parts.append(part)
	if parts.is_empty():
		return []
	var hole := _hole(parts)
	if hole.is_empty():
		return parts.map(func(q): return clean(q))
	if depth >= 3:
		return null
	var cut := _best_cut(a, b, hole, objs)
	var out := []
	for half in _split(a, cut):
		var sub: Variant = subtract(half, b, objs, depth + 1)
		if sub == null:
			return null
		out.append_array(sub)
	return out


## Trou du résultat d'une soustraction (orientation inverse de la plus grande
## partie, et dedans) ; vide s'il n'y en a pas.
static func _hole(parts: Array) -> PackedVector2Array:
	var big: PackedVector2Array = parts[0]
	for q in parts:
		if MapGeom.area(q) > MapGeom.area(big):
			big = q
	var cw := Geometry2D.is_polygon_clockwise(big)
	for q in parts:
		if q == big or Geometry2D.is_polygon_clockwise(q) == cw:
			continue
		for other in parts:
			if other != q and Geometry2D.is_polygon_clockwise(other) == cw and MapGeom.contains(other, MapGeom.centroid(q)):
				return q
	return PackedVector2Array()


## Ligne de coupe d'un anneau : {vertical, c}. Lignes de la grille de 0,5 m
## qui traversent le trou ; la meilleure : le plus de bords assez longs pour un
## passage, le moins d'objets coupés, la plus proche du milieu.
static func _best_cut(a: PackedVector2Array, b: PackedVector2Array, hole: PackedVector2Array, objs: Array) -> Dictionary:
	var hb := MapGeom.bbox(hole)
	var best := {}
	var best_score := []
	for vertical in [true, false]:
		var lo: float = hb.position.x if vertical else hb.position.y
		var hi: float = hb.end.x if vertical else hb.end.y
		var mid := (lo + hi) * 0.5
		var cands := []
		var c := ceilf((lo + 0.25) / MapGeom.CELL) * MapGeom.CELL
		while c <= hi - 0.25 + MapGeom.EPS and cands.size() < 200:
			cands.append(c)
			c += MapGeom.CELL
		if cands.is_empty():
			cands.append(mid)
		for cc in cands:
			var segs := cut_segments(a, b, vertical, cc)
			if segs.is_empty():
				continue
			var n_ok := 0
			var crossed := 0
			for s in segs:
				if s[0].distance_to(s[1]) >= PASSAGE_EDGE:
					n_ok += 1
				for o in objs:
					var r := MapRules.footprint_rect(o).grow(MapGeom.WALL_HALF)
					if Geometry2D.segment_intersects_segment(s[0], s[1], r.position, r.end) != null \
							or Geometry2D.segment_intersects_segment(s[0], s[1], Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)) != null:
						crossed += 1
			var score := [float(mini(n_ok, 2)), float(-crossed), -absf(float(cc) - mid)]
			if best_score.is_empty() or score > best_score:
				best_score = score
				best = {"vertical": vertical, "c": cc}
	if best.is_empty():
		best = {"vertical": true, "c": hb.get_center().x}
	return best


## Morceaux de la ligne de coupe (x = c ou y = c) dans `a` et hors de `b`.
static func cut_segments(a: PackedVector2Array, b: PackedVector2Array, vertical: bool, c: float) -> Array:
	var bb := MapGeom.bbox(a).grow(1.0)
	var line := PackedVector2Array([Vector2(c, bb.position.y), Vector2(c, bb.end.y)]) if vertical \
		else PackedVector2Array([Vector2(bb.position.x, c), Vector2(bb.end.x, c)])
	var out := []
	for inside in Geometry2D.intersect_polyline_with_polygon(line, a):
		for s in Geometry2D.clip_polyline_with_polygon(inside, b):
			if s.size() >= 2 and s[0].distance_to(s[s.size() - 1]) > 0.05:
				out.append([s[0], s[s.size() - 1]])
	return out


## `a` coupé en deux par la ligne `cut` ({vertical, c}).
static func _split(a: PackedVector2Array, cut: Dictionary) -> Array:
	var bb := MapGeom.bbox(a).grow(1.0)
	var c := float(cut.c)
	var r1: Rect2
	var r2: Rect2
	if cut.vertical:
		r1 = Rect2(bb.position, Vector2(c - bb.position.x, bb.size.y))
		r2 = Rect2(Vector2(c, bb.position.y), Vector2(bb.end.x - c, bb.size.y))
	else:
		r1 = Rect2(bb.position, Vector2(bb.size.x, c - bb.position.y))
		r2 = Rect2(Vector2(bb.position.x, c), Vector2(bb.size.x, bb.end.y - c))
	var out := []
	for r in [r1, r2]:
		for q in Geometry2D.intersect_polygons(a, MapGeom.rect_poly(r)):
			if MapGeom.area(q) > MIN_PART_AREA:
				out.append(clean(q))
	return out


## Morceau gardé ? "" : oui ; "small" : trop petit ou trop mince (retiré) ;
## sinon la raison du refus (contour invalide).
static func _piece_check(doc: EditorMap, k: int, pc: PackedVector2Array) -> Dictionary:
	var bb := MapGeom.bbox(pc)
	var a := MapGeom.area(pc)
	if bb.size.x < MapRules.MIN_ROOM_SIDE or bb.size.y < MapRules.MIN_ROOM_SIDE or a < 2.0 \
			or 2.0 * a / maxf(MapGeom.perimeter(pc), MapGeom.EPS) < MIN_PART_WIDTH:
		return {"ok": false, "small": true}
	return MapRules.check_room(doc, k, pc, "", true)


# ------------------------------------------------------------------ plan et découpe

## Copie de travail de la carte (sans toucher au catalogue des prefabs).
static func copy_doc(doc: EditorMap) -> EditorMap:
	var s := doc.to_dict().duplicate(true)
	var m := EditorMap.new()
	m.carte = s.carte
	m.pieces = s.pieces
	m.ouvertures = s.ouvertures
	m.objets = s.objets
	m.zones = s.zones
	m.depart = String(s.depart)
	m.prefabs = doc.prefabs
	m.models = doc.models
	m.textures = doc.textures
	m.texture_files = doc.texture_files
	m.view_levels = doc.view_levels.duplicate()
	return m


## Découpe PRÉVUE d'une pièce de contour `poly` tracée à l'étage `k` (rien
## n'est modifié) : {carve: false} si elle ne recouvre rien ; sinon le
## résultat de carve() sur une copie (ok, victims… ou refus fr / en), plus
## `cut` (covered : les parties hachurées) et `doc` (la copie découpée).
## `room` : la pièce (nom, zone…), facultative.
static func plan(doc: EditorMap, k: int, poly: PackedVector2Array, room := {}) -> Dictionary:
	var hits := covered(doc, k, poly)
	if hits.is_empty():
		return {"ok": true, "carve": false}
	var m := copy_doc(doc)
	var r: Dictionary = room.duplicate(true)
	r["contour"] = MapGeom.poly_arr(poly)
	doc.set_level(r, k)
	new_room(m, r)
	var rep := carve(m, r)
	rep["carve"] = true
	rep["cut"] = hits
	rep["doc"] = m
	return rep


## Pièce `e` ajoutée à `doc` EXACTEMENT comme la pose de l'éditeur
## (MapEditor.insert_element) : identifiant neuf, nom « Pièce N » par défaut,
## sa propre zone (même nom) si elle n'en a pas. L'aperçu (plan) annonce ainsi
## ce que fera la découpe (zone de départ comprise) ; tests/test_map_carve.gd
## vérifie que les deux donnent la même carte.
static func new_room(doc: EditorMap, e: Dictionary) -> void:
	e["id"] = doc.new_id("p")
	var n := doc.pieces.size() + 1
	var named := e.has("nom")
	if not named:
		e["nom"] = Lang.t("Pièce %d", "Room %d") % n
	if doc.zone(String(e.get("zone", ""))).is_empty():
		var z := doc.add_zone(String(e.nom) if named else "Pièce %d" % n, String(e.nom) if named else "Room %d" % n)
		e["zone"] = String(z.id)
	doc.pieces.append(e)


## Découpe les pièces que recouvre `room` (déjà dans `doc` ou non : elle y est
## ajoutée), sur place. Rend {ok: true, room, victims: [{id, nom, removed,
## deleted, pieces: [noms], own_zone: [noms], passages}], moved, removed,
## removed_objects, warn} ou {ok: false, fr, en} (la carte est alors dans un
## état intermédiaire : travailler sur une copie, ou la restaurer).
static func carve(doc: EditorMap, room: Dictionary) -> Dictionary:
	var k := doc.level_of(room)
	var rid := String(room.get("id", ""))
	var idx := -1
	for i in doc.pieces.size():
		if String(doc.pieces[i].get("id", "")) == rid:
			idx = i
	if idx >= 0:
		doc.pieces.remove_at(idx)
	var poly := doc.room_poly(room)
	var victims := overlaps(doc, k, poly)
	var rep := {"ok": true, "room": rid, "victims": [], "moved": [], "removed": [], "removed_ids": [], "relinked": [], "removed_objects": 0, "warn": []}
	if victims.is_empty():
		if idx >= 0:
			doc.pieces.insert(idx, room)
		else:
			doc.pieces.append(room)
		return rep
	# Seuls les éléments proches peuvent changer (aperçu fluide sur une grande
	# carte) : les pièces touchées et la nouvelle, plus la cour d'une fenêtre.
	var region := MapGeom.bbox(poly)
	var vpolys := {}
	for v in victims:
		vpolys[String(v.id)] = doc.room_poly(v)
		region = region.merge(MapGeom.bbox(vpolys[String(v.id)]))
	region = region.grow(REGION_MARGIN)
	var before_bad := _invalid(doc, k, region)
	var znames := _names_of(doc)
	var zones_before := {}
	for o in doc.openings_on(k):
		if not before_bad.has(String(o.id)) and region.has_point(MapGeom.v2(o.position)):
			zones_before[String(o.id)] = _opening_zones(doc, k, o)
	if idx >= 0:
		doc.pieces.insert(idx, room)
	else:
		doc.pieces.append(room)
	var groups := []
	for v in victims:
		var vp: PackedVector2Array = vpolys[String(v.id)]
		var nom := String(v.get("nom", v.id))
		var sub: Variant = subtract(vp, poly, doc.objects_on(k))
		if sub == null:
			return MapRules.refuse("la pièce « %s » ne peut pas être découpée ainsi : tracez la nouvelle pièce autrement" % nom,
				"room \"%s\" cannot be cut this way: draw the new room differently" % nom)
		var good := []
		for pc in sub:
			var chk := _piece_check(doc, k, pc)
			if chk.ok:
				good.append(pc)
			elif not chk.get("small", false):
				return MapRules.refuse("la découpe de « %s » laisserait un contour invalide (%s) : déplacez un peu la nouvelle pièce" % [nom, String(chk.fr)],
					"cutting \"%s\" would leave an invalid outline (%s): move the new room a little" % [nom, String(chk.en)])
		good.sort_custom(func(x, y): return MapGeom.area(x) > MapGeom.area(y))
		var kept := 0.0
		for pc in good:
			kept += MapGeom.area(pc)
		var entry := {"id": String(v.id), "nom": nom, "removed": maxf(0.0, MapGeom.area(vp) - kept), "deleted": good.is_empty(),
			"pieces": [], "own_zone": [], "passages": 0}
		rep.victims.append(entry)
		if good.is_empty():
			doc.remove(String(v.id))
			continue
		v["contour"] = MapGeom.poly_arr(good[0])
		v.erase("forme")
		entry.pieces.append(nom)
		var parts := [v]
		var base := _base_name(nom)
		for i in range(1, good.size()):
			var c: Dictionary = v.duplicate(true)
			c["id"] = doc.new_id("p")
			c["nom"] = _free_name(doc, base)
			c["contour"] = MapGeom.poly_arr(good[i])
			doc.pieces.append(c)
			parts.append(c)
			entry.pieces.append(String(c.nom))
		groups.append({"entry": entry, "parts": parts})
	# Contenu laissé hors de toute pièce (morceau retiré) : supprimé.
	var room_polys := doc.rooms_on(k).map(func(p): return doc.room_poly(p))
	for o in doc.objects_on(k):
		if String(o.get("type", "")) in FREE_TYPES:
			continue
		var c := _center(o)
		if not vpolys.values().any(func(vp): return MapGeom.contains(vp, c)):
			continue
		if not room_polys.any(func(rp): return MapGeom.contains(rp, c)):
			doc.remove(String(o.id))
			rep.removed_objects += 1
	# Morceaux d'une même pièce : un passage libre sur leurs bords communs, sinon
	# chacun sa zone.
	for g in groups:
		_link_parts(doc, k, g.parts, g.entry)
	# Ouvertures dont le mur a disparu : déplacées (mêmes zones reliées) ou retirées.
	for o in doc.openings_on(k):
		var oid := String(o.id)
		if before_bad.has(oid) or not zones_before.has(oid):
			continue
		MapRules.begin_batch(doc)
		var ok: bool = MapRules.check_existing(doc, o).ok
		MapRules.end_batch()
		var nm := MapRules._name(o)
		if o.has("prix"):
			nm = ["%s %d" % [nm[0], int(o.prix)], "%s %d" % [nm[1], int(o.prix)]]
		if ok:
			# Toujours valide, mais elle relie d'autres zones qu'avant (A ↔ B
			# devient Nouvelle ↔ B) : gardée, signalée dans la confirmation.
			var now := _opening_zones(doc, k, o)
			if now != zones_before[oid]:
				rep.relinked.append({"name": nm, "before": _zone_names(znames, zones_before[oid]), "after": _zone_names(_names_of(doc), now)})
			continue
		if _relocate(doc, k, o, zones_before[oid]):
			rep.moved.append(nm)
		else:
			doc.remove(oid)
			rep.removed.append(nm)
			rep.removed_ids.append(oid)
	# Escaliers rendus invalides : refus ; le reste : à revoir.
	var after := _invalid(doc, k, region)
	for eid in after:
		if before_bad.has(eid):
			continue
		var e := doc.find(eid)
		if String(e.get("type", "")) == "escalier":
			var why: Dictionary = after[eid]
			return MapRules.refuse("l'escalier en %s deviendrait invalide (%s) : la découpe est refusée, déplacez l'escalier ou tracez la pièce autrement" % [_where(e), String(why.get("fr", ""))],
				"the stairs at %s would become invalid (%s): the cut is refused, move the stairs or draw the room differently" % [_where(e), String(why.get("en", ""))])
		if e.has("contour"):
			var why2: Dictionary = after[eid]
			return MapRules.refuse("la pièce « %s » deviendrait invalide (%s)" % [e.get("nom", eid), String(why2.get("fr", ""))],
				"room \"%s\" would become invalid (%s)" % [e.get("nom", eid), String(why2.get("en", ""))])
		rep.warn.append(MapRules._name(e))
	# Zone de départ vidée (pièce avalée) : celle de la nouvelle pièce.
	if doc.depart != "" and doc.rooms_of_zone(doc.depart).is_empty() and not doc.zone(String(room.get("zone", ""))).is_empty():
		doc.depart = String(room.zone)
		rep["start_moved"] = true
	doc.tidy_zones()
	# Plafonds de la carte (MapOps.MAX_COUNT) : morceaux, passages et zones
	# ajoutés compris.
	for coll in ["pieces", "ouvertures", "zones"]:
		if MapOps.list(doc, coll).size() > int(MapOps.MAX_COUNT[coll]):
			return MapRules.refuse("la découpe dépasserait le nombre maximal de %s (%d au plus)" % [{"pieces": "pièces", "ouvertures": "ouvertures", "zones": "zones"}[coll], int(MapOps.MAX_COUNT[coll])],
				"the cut would exceed the maximum number of %s (at most %d)" % [{"pieces": "rooms", "ouvertures": "openings", "zones": "zones"}[coll], int(MapOps.MAX_COUNT[coll])])
	return rep


## Noms FR / EN des zones de la carte : id -> [fr, en].
static func _names_of(doc: EditorMap) -> Dictionary:
	var out := {}
	for z in doc.zones:
		var n: Dictionary = z.get("nom", {}) if z.get("nom") is Dictionary else {}
		out[String(z.id)] = [String(n.get("fr", z.id)), String(n.get("en", n.get("fr", z.id)))]
	return out


## « Atelier ↔ Couloir » en français et en anglais : [fr, en].
static func _zone_names(names: Dictionary, zs: Array) -> Array:
	var fr := PackedStringArray()
	var en := PackedStringArray()
	for zid in zs:
		var n: Array = names.get(String(zid), [String(zid), String(zid)])
		fr.append(n[0])
		en.append(n[1])
	return [" ↔ ".join(fr), " ↔ ".join(en)]


## Relie les morceaux `parts` d'une pièce coupée (le premier : l'original) :
## passages libres sur leurs bords communs ; un morceau qui n'en reçoit aucun
## a sa propre zone (copie de celle de la pièce).
static func _link_parts(doc: EditorMap, k: int, parts: Array, entry: Dictionary) -> void:
	if parts.size() < 2:
		return
	var linked := [parts[0]]
	var rest := parts.slice(1)
	var progress := true
	while progress and not rest.is_empty():
		progress = false
		for pc in rest.duplicate():
			for q in linked:
				var n := _add_passages(doc, k, q, pc)
				if n > 0:
					entry.passages += n
					linked.append(pc)
					rest.erase(pc)
					progress = true
					break
	for pc in rest:
		var z: Dictionary = doc.zone(String(pc.get("zone", ""))).duplicate(true)
		z["id"] = doc.new_id("z")
		z["nom"] = {"fr": String(pc.nom), "en": String(pc.nom)}
		doc.zones.append(z)
		pc["zone"] = String(z.id)
		entry.own_zone.append(String(pc.nom))


## Passages libres (aussi larges que possible) sur les bords communs de deux
## morceaux ; rend leur nombre.
static func _add_passages(doc: EditorMap, k: int, a: Dictionary, b: Dictionary) -> int:
	var n := 0
	for s in MapGeom.common_segments(doc.room_poly(a), doc.room_poly(b)):
		var p: Vector2 = s[0]
		var q: Vector2 = s[1]
		var length := p.distance_to(q)
		if length < PASSAGE_EDGE - MapGeom.EPS:
			continue
		var w := minf(floorf((length - 2.0 * MapRules.END_MARGIN + MapGeom.EPS) / MapGeom.CELL) * MapGeom.CELL, PASSAGE_MAX)
		while w >= 1.0 - MapGeom.EPS:
			var r := MapRules.place_opening(doc, k, "passage", (p + q) * 0.5, w)
			if r.ok:
				# Revérifié posé (une largeur paire de demi-mètres se centre à
				# 0,25 m de la grille : elle peut ne pas tenir là où l'impaire tient).
				var o := {"id": doc.new_id("o"), "type": "passage", "altitude": doc.level_alt(k), "position": r.position, "largeur": w}
				doc.ouvertures.append(o)
				MapRules.begin_batch(doc)
				var ok: bool = MapRules.check_existing(doc, o).ok
				MapRules.end_batch()
				if ok:
					n += 1
					break
				doc.ouvertures.erase(o)
			w -= MapGeom.CELL
	return n


## Zones (triées) que relie une ouverture posée, [] si elle n'est sur aucun mur.
static func _opening_zones(doc: EditorMap, k: int, o: Dictionary) -> Array:
	var r := MapRules.place_opening(doc, k, String(o.type), MapGeom.v2(o.position), MapRules.opening_width(o), String(o.id))
	if not r.ok:
		return []
	var zs := []
	for rid in r.get("rooms", []):
		zs.append(String(doc.find(String(rid)).get("zone", "")))
	zs.sort()
	return zs


## Ouverture recalée sur le bord le plus proche s'il relie les mêmes zones.
static func _relocate(doc: EditorMap, k: int, o: Dictionary, zones: Array) -> bool:
	if zones.is_empty():
		return false
	var r := MapRules.place_opening(doc, k, String(o.type), MapGeom.v2(o.position), MapRules.opening_width(o), String(o.id))
	if not r.ok:
		return false
	var old: Variant = o.position
	o["position"] = r.position
	if _opening_zones(doc, k, o) == zones:
		MapRules.begin_batch(doc)
		var ok: bool = MapRules.check_existing(doc, o).ok
		MapRules.end_batch()
		if ok:
			return true
	o["position"] = old
	return false


## Éléments invalides des étages k - 1 à k + 1 qui touchent `region` : id ->
## refus {fr, en}.
static func _invalid(doc: EditorMap, k: int, region: Rect2) -> Dictionary:
	var out := {}
	MapRules.begin_batch(doc)
	for list in [doc.pieces, doc.ouvertures, doc.objets]:
		for e in list:
			if doc.level_of(e) < 0 or absi(doc.level_of(e) - k) > 1 or not _rect_of(doc, e).intersects(region, true):
				continue
			var r := MapRules.check_existing(doc, e)
			if not r.ok:
				out[String(e.id)] = r
	MapRules.end_batch()
	return out


## Emprise (m) d'un élément : contour d'une pièce, point d'une ouverture,
## emprise d'un objet.
static func _rect_of(doc: EditorMap, e: Dictionary) -> Rect2:
	if e.has("contour"):
		return MapGeom.bbox(doc.room_poly(e))
	if e.has("position") and String(e.get("type", "")) in MapRules.ouvertures_types():
		return Rect2(MapGeom.v2(e.position), Vector2.ZERO)
	return MapRules.footprint_rect(e)


static func _center(o: Dictionary) -> Vector2:
	return MapRules.footprint_rect(o).get_center()


static func _where(e: Dictionary) -> String:
	var c := _center(e)
	return "(%s ; %s)" % [MapRules._m(c.x), MapRules._m(c.y)]


## Nom sans suffixe « (n) » : « Atelier (2) » -> « Atelier ».
static func _base_name(nom: String) -> String:
	var re := RegEx.create_from_string("^(.*) \\(\\d+\\)$")
	var m := re.search(nom)
	return m.get_string(1) if m != null else nom


## Premier nom « base (n) » (n ≥ 2) libre parmi les pièces.
static func _free_name(doc: EditorMap, base: String) -> String:
	var used := {}
	for p in doc.pieces:
		used[String(p.get("nom", ""))] = true
	var n := 2
	while used.has("%s (%d)" % [base, n]):
		n += 1
	return "%s (%d)" % [base, n]


# ------------------------------------------------------------------ textes

## Texte de la confirmation (langue du jeu) : pièces découpées, coupées,
## supprimées ; ouvertures déplacées ou retirées ; objets supprimés ; à revoir.
static func describe(rep: Dictionary, fr := not Lang.is_en()) -> String:
	var lines := PackedStringArray()
	for v in rep.get("victims", []):
		var nom := String(v.nom)
		var area := MapRules._m(snappedf(float(v.removed), 0.1), fr)
		if v.deleted:
			lines.append(("La pièce « %s » sera supprimée (entièrement recouverte, ou ce qui en reste est trop petit)." if fr
				else "Room \"%s\" will be deleted (fully covered, or what is left is too small).") % nom)
		elif (v.pieces as Array).size() > 1:
			var names := ", ".join((v.pieces as Array).map(func(s): return ("« %s »" if fr else "\"%s\"") % s))
			lines.append(("La pièce « %s » sera coupée en %d pièces : %s (%s m² retirés)." if fr
				else "Room \"%s\" will be split into %d rooms: %s (%s m² removed).") % [nom, (v.pieces as Array).size(), names, area])
			if int(v.passages) > 0:
				lines.append(("  Ses morceaux gardent la même zone, reliés par %d passage(s) libre(s)." if fr
					else "  Its parts keep the same zone, linked by %d open passage(s).") % int(v.passages))
			for s in v.own_zone:
				lines.append(("  « %s » ne touche plus le reste : elle a sa propre zone." if fr
					else "  \"%s\" no longer touches the rest: it gets its own zone.") % s)
		else:
			lines.append(("La pièce « %s » sera découpée (%s m² retirés)." if fr else "Room \"%s\" will be cut (%s m² removed).") % [nom, area])
	var idx := 0 if fr else 1
	if not (rep.get("moved", []) as Array).is_empty():
		lines.append(("Ouvertures déplacées sur le mur commun le plus proche : %s." if fr else "Openings moved to the nearest shared wall: %s.")
			% ", ".join((rep.moved as Array).map(func(n): return String(n[idx]))))
	if not (rep.get("removed", []) as Array).is_empty():
		lines.append(("Ouvertures retirées (leur mur disparaît) : %s." if fr else "Openings removed (their wall disappears): %s.")
			% ", ".join((rep.removed as Array).map(func(n): return String(n[idx]))))
	for r in rep.get("relinked", []):
		lines.append(("« %s » (%s) donnera désormais sur : %s." if fr else "\"%s\" (%s) will now lead to: %s.")
			% [String(r.name[idx]), String(r.before[idx]), String(r.after[idx])])
	if rep.get("start_moved", false):
		lines.append("La zone de départ devient celle de la nouvelle pièce." if fr else "The start zone becomes the new room's zone.")
	if int(rep.get("removed_objects", 0)) > 0:
		lines.append(("%d objet(s) laissé(s) hors de toute pièce seront supprimés." if fr else "%d object(s) left outside every room will be deleted.")
			% int(rep.removed_objects))
	if not (rep.get("warn", []) as Array).is_empty():
		var names2: Array = (rep.warn as Array).map(func(n): return String(n[idx]))
		lines.append(("À revoir après la découpe (en rouge) : %s." if fr else "To check after the cut (in red): %s.") % ", ".join(names2.slice(0, 8))
			+ (" …" if names2.size() > 8 else ""))
	lines.append("Le contenu de la partie découpée passe à la nouvelle pièce. Une seule annulation (Ctrl+Z) défait tout." if fr
		else "The content of the cut part goes to the new room. A single undo (Ctrl+Z) reverts everything.")
	return "\n".join(lines)


## Résumé court (barre d'état) : « Atelier découpée, Cagibi supprimée ».
static func short(rep: Dictionary) -> String:
	var parts := PackedStringArray()
	for v in rep.get("victims", []):
		if v.deleted:
			parts.append(Lang.t("« %s » supprimée", "\"%s\" deleted") % v.nom)
		elif (v.pieces as Array).size() > 1:
			parts.append(Lang.t("« %s » coupée en %d", "\"%s\" split in %d") % [v.nom, (v.pieces as Array).size()])
		else:
			parts.append(Lang.t("« %s » découpée", "\"%s\" cut") % v.nom)
	return ", ".join(parts)


## Résumé pour l'agent (MCP) : données et texte en français.
static func summary(rep: Dictionary) -> Dictionary:
	var vs := []
	for v in rep.get("victims", []):
		vs.append({"id": v.id, "nom": v.nom, "retire_m2": snappedf(float(v.removed), 0.01), "supprimee": v.deleted,
			"morceaux": v.pieces, "zone_propre": v.own_zone, "passages": v.passages})
	return {"piece": rep.get("room", ""), "decoupees": vs,
		"ouvertures_deplacees": (rep.get("moved", []) as Array).map(func(n): return n[0]),
		"ouvertures_retirees": (rep.get("removed", []) as Array).map(func(n): return n[0]),
		"ouvertures_reliees": (rep.get("relinked", []) as Array).map(func(r): return {"nom": r.name[0], "avant": r.before[0], "apres": r.after[0]}),
		"zone_depart_deplacee": bool(rep.get("start_moved", false)),
		"objets_supprimes": int(rep.get("removed_objects", 0)),
		"a_revoir": (rep.get("warn", []) as Array).map(func(n): return n[0]),
		"texte": describe(rep, true)}


# ------------------------------------------------------------------ lot de l'agent (MCP)

## Lot d'opérations (MapOps, ids déjà résolus) dont des pièces en recouvrent
## d'autres : `allowed` (« decouper »: true) -> {ok, ops (le lot complété des
## découpes), reports} ; sinon {ok: false, fr, en} qui explique quoi faire.
## Sans chevauchement : {ok: true, ops: le lot tel quel, reports: []}.
static func carve_ops(doc: EditorMap, ops: Array, allowed: bool) -> Dictionary:
	var m := copy_doc(doc)
	MapOps.apply(m, ops)
	var reps := []
	for op in ops:
		if String(op.get("op", "")) != "put" or String(op.get("coll", "")) != "pieces":
			continue
		var r := m.find(String((op.el as Dictionary).get("id", "")))
		if r.is_empty() or not r.has("contour"):
			continue
		var k := m.level_of(r)
		var hits := overlaps(m, k, m.room_poly(r), String(r.id))
		if hits.is_empty():
			continue
		var names := ", ".join(hits.map(func(p): return "« %s »" % p.get("nom", p.id)))
		if not allowed:
			return MapRules.refuse("lot refusé : la pièce « %s » recouvre %s. Pour découper les pièces existantes (la partie recouverte leur est retirée), renvoie le lot avec « decouper »: true ; sinon place la pièce à côté (deux pièces se touchent, jamais ne se recouvrent)" % [r.get("nom", r.id), names],
				"batch refused: room \"%s\" overlaps %s. To cut the existing rooms (the covered part is removed from them), send the batch again with \"decouper\": true; otherwise place the room next to them (rooms touch, never overlap)" % [r.get("nom", r.id), names.replace("« ", "\"").replace(" »", "\"")])
		# Mêmes contrôles que le tracé dans l'éditeur (contour simple, dans le
		# terrain, taille) : une pièce invalide ne découpe rien.
		var chk := MapRules.check_room(m, k, m.room_poly(r), String(r.id), true)
		if not chk.ok:
			return MapRules.refuse("lot refusé : la pièce « %s » ne peut pas découper (%s)" % [r.get("nom", r.id), String(chk.fr)],
				"batch refused: room \"%s\" cannot cut (%s)" % [r.get("nom", r.id), String(chk.en)])
		var rep := carve(m, r)
		if not rep.ok:
			return MapRules.refuse("découpe refusée : %s" % String(rep.fr), "cut refused: %s" % String(rep.en))
		reps.append(rep)
	if reps.is_empty():
		return {"ok": true, "ops": ops, "reports": []}
	return {"ok": true, "ops": MapOps.diff(doc, m), "reports": reps}
