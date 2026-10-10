class_name MapTransform
extends RefCounted
## Rotations libres de l'éditeur de cartes (docs/MAP_AUTHORING.md, « Formes
## libres ») : une pièce tourne avec son contenu (ouvertures et objets muraux
## restent sur leur mur, décor et luminaires tournent avec elle), un pilier,
## un escalier, un piège, un décor ou un mur tourne autour de son centre ;
## pas de 15° par défaut (poignée de rotation), au degré près avec Alt ou dans
## les propriétés, 90° avec R. Régénération d'une forme de base posée
## (nombre de points d'un cercle, rayons, angle). Fonctions sur la carte
## (EditorMap), testées par tests/test_map_editor_freeform.gd.

## Pas de la poignée de rotation (degrés) ; Alt : au degré près.
const STEP := 15


## L'élément peut-il tourner (poignée, champ « angle », R) ? Les objets muraux
## suivent leur mur : ils tournent seulement avec leur pièce.
static func can_rotate(e: Dictionary) -> bool:
	var t := String(e.get("type", ""))
	return e.has("contour") or e.has("rect") or e.has("sommets") or t in ["mur", "mur_courbe"] or MapCatalog.rotates(e)


## Centre de rotation d'un élément : centre de sa forme, de son rectangle
## englobant (pièce), de son rectangle (pilier, escalier, piège), sa position
## (décor, luminaire), le milieu d'un mur, le centre d'un mur courbe.
static func pivot(doc: EditorMap, e: Dictionary) -> Vector2:
	if e.has("contour"):
		if e.has("forme") and MapShapes.valid(e.forme):
			return MapGeom.v2(e.forme.centre)
		return MapGeom.bbox(doc.room_poly(e)).get_center()
	if e.has("rect"):
		return MapGeom.rect_of(e.rect).get_center()
	if e.has("sommets"):
		# Barrière invisible en polygone (format 9) : centre de son rectangle englobant.
		return MapGeom.bbox(MapGeom.poly(e.sommets)).get_center()
	match String(e.get("type", "")):
		"mur":
			return (MapGeom.v2(e.a) + MapGeom.v2(e.b)) * 0.5
		"mur_courbe":
			return MapGeom.v2(e.centre)
	return MapGeom.v2(e.get("position", [0, 0]))


## Rotation propre de l'élément (degrés) affichée dans les propriétés : « rot »
## (décor, pilier...), l'angle de la forme d'une pièce, le début d'un mur
## courbe, la direction d'un mur ; 0 sinon.
static func angle_of(e: Dictionary) -> int:
	if e.has("contour"):
		return MapGeom.norm_deg(float(e.get("forme", {}).get("angle", 0.0))) if e.has("forme") else 0
	match String(e.get("type", "")):
		"mur_courbe":
			return MapGeom.norm_deg(float(e.get("debut", 0.0)))
		"mur":
			return MapGeom.norm_deg(MapGeom.dir_deg((MapGeom.v2(e.b) - MapGeom.v2(e.a)).normalized()))
	return MapGeom.rot_of(e)


## Élément tourné de `deg` degrés (sens horaire vu de dessus) autour de `c` :
## copie. Un quart de tour garde un rectangle de la grille sur la grille
## (rectangle et sens de montée tournés) ; sinon « rot » s'ajoute.
static func rotated(o: Dictionary, c: Vector2, deg: float) -> Dictionary:
	var d := MapGeom.norm_deg(deg)
	var e := o.duplicate(true)
	if d == 0:
		return e
	var quarter := d % 90 == 0
	# Format 20 : l'architecture tournée reste sur la grille des cubes de 5 cm
	# (sommets, bouts des murs, centre d'un mur courbe, coins d'un pilier ou
	# d'un escalier) ; le décor garde le millimètre.
	var archi := MapCubeSnap.is_architecture(e)
	var put := func(v: Vector2) -> Array: return MapGeom.cube_arr(v) if archi else MapGeom.arr(v)
	if e.has("contour"):
		var pts := []
		for p in e.contour:
			pts.append(put.call(MapGeom.rotate_about(MapGeom.v2(p), c, d)))
		e.contour = pts
		if e.has("forme"):
			if MapShapes.valid(e.forme):
				e.forme = MapShapes.rotated(e.forme, c, d)
			else:
				e.erase("forme")
	if e.has("sommets"):
		# Barrière invisible en polygone (format 9) : chaque sommet tourne.
		var pts := []
		for p in e.sommets:
			pts.append(MapGeom.arr(MapGeom.rotate_about(MapGeom.v2(p), c, d)))
		e.sommets = pts
	for key in ["position", "a", "b", "centre"]:
		if e.has(key):
			e[key] = put.call(MapGeom.rotate_about(MapGeom.v2(e[key]), c, d))
	if e.has("rect"):
		var r := MapGeom.rect_of(e.rect)
		if quarter and MapGeom.rot_of(e) == 0:
			# Quart de tour d'un rectangle droit : il reste droit (grille).
			var p0 := MapGeom.rotate_about(r.position, c, d)
			var p1 := MapGeom.rotate_about(r.end, c, d)
			if archi:
				p0 = MapGeom.round_cube(p0)
				p1 = MapGeom.round_cube(p1)
			e.rect = MapGeom.rect_arr(Rect2(p0, Vector2.ZERO).expand(p1))
			if e.has("monte"):
				@warning_ignore("integer_division")
				for i in d / 90:
					e["monte"] = MapGeom.dir_rot(String(e.monte))
		else:
			var nc := MapGeom.rotate_about(r.get_center(), c, d)
			var p0 := nc - r.size * 0.5
			if archi:
				# Coin au cube, taille gardée (un nombre entier de cubes).
				p0 = MapGeom.round_cube(p0)
			e.rect = MapGeom.rect_arr(Rect2(p0, r.size))
			e["rot"] = MapGeom.norm_deg(MapGeom.rot_of(e) + d)
			if int(e.rot) == 0:
				e.erase("rot")
	elif e.has("rot") or MapCatalog.floor_box(e):
		# Format 15 : une boîte au sol tourne même sans « rot » écrit (0).
		e["rot"] = MapGeom.norm_deg(MapGeom.rot_of(e) + d)
	if e.has("mur") and not e.has("rect"):
		# Objet mural (ou applique) : il reste collé à son mur, face vers l'intérieur.
		if quarter and not e.has("angle"):
			@warning_ignore("integer_division")
			for i in d / 90:
				e["mur"] = MapGeom.dir_rot(String(e.mur))
		else:
			var cur := float(e.angle) if e.has("angle") else MapGeom.dir_deg(MapGeom.dir_vec(String(e.mur)))
			var nd := fposmod(cur + d, 360.0)
			e["angle"] = snappedf(nd, 0.01)
			if quarter:
				@warning_ignore("integer_division")
				for i in d / 90:
					e["mur"] = MapGeom.dir_rot(String(e.mur))
			else:
				e["mur"] = MapGeom.cardinal_of(MapGeom.deg_dir(nd))
			if not MapGeom.item_oblique(e):
				e.erase("angle")
	if String(e.get("type", "")) == "mur_courbe":
		e["debut"] = snappedf(fposmod(float(e.get("debut", 0.0)) + d, 360.0), 0.01)
	return e


## Éléments rattachés à une pièce (qui bougent et tournent avec elle) : les
## objets dont le centre est dans la pièce, les ouvertures sur son contour.
static func attached(doc: EditorMap, e: Dictionary) -> Array:
	var out := []
	if String(e.get("type", "")) in ["mur", "mur_courbe"]:
		return on_free_wall(doc, e)
	if not e.has("contour"):
		return out
	var poly := doc.room_poly(e)
	var k := doc.level_of(e)
	for o in doc.objects_on(k):
		var c := MapRules.footprint_rect(o).get_center()
		if String(o.type) == "mur":
			c = (MapGeom.v2(o.a) + MapGeom.v2(o.b)) * 0.5
		elif String(o.type) == "mur_courbe":
			var arc := MapShapes.wall_arc(o)
			@warning_ignore("integer_division")
			c = arc[arc.size() / 2]
		if MapGeom.contains(poly, c):
			out.append(String(o.id))
	for o in doc.openings_on(k):
		if MapGeom.on_boundary(poly, MapGeom.v2(o.position), MapGeom.JOIN_TOL):
			out.append(String(o.id))
	return out


## Escaliers dont l'ARRIVÉE est dans la pièce `room` (format 17, étape 5) :
## leur « altitude_haut » est celle de la pièce et une case d'arrivée
## (MapRules.stair_parts : exit) est à l'intérieur de son contour. Ils ne
## bougent pas avec elle dans le plan ; montée ou descendue, leur arrivée suit.
static func arrivals(doc: EditorMap, room: Dictionary) -> Array:
	var out := []
	if not room.has("contour"):
		return out
	var a := EditorMap.alt_of(room)
	var poly := doc.room_poly(room)
	var bb := MapGeom.bbox(poly).grow(1.0)
	for o in doc.objets:
		if String(o.get("type", "")) != "escalier" or absf(doc.stair_top_of(o) - a) > EditorMap.ALT_EQ:
			continue
		if not bb.intersects(MapRules.footprint_rect(o)):
			continue
		for c in MapRules.stair_parts(o).exit:
			if MapGeom.contains(poly, MapGeom.cell_center(c)):
				out.append(String(o.id))
				break
	return out


## Déplacement VERTICAL (format 17, étape 5) des éléments `direct` (choisis)
## et de ce qui les suit : {both, foot, top} (identifiants). « both » :
## altitude (et arrivée d'un escalier choisi lui-même) ; « foot » : escalier
## rattaché à une pièce par son pied (son pied suit, son arrivée reste) ;
## « top » : escalier dont l'arrivée est dans une pièce déplacée (seule son
## arrivée suit). Un escalier pied et arrivée dans deux pièces déplacées
## ensemble : « both ».
static func vertical_plan(doc: EditorMap, direct: Array) -> Dictionary:
	var both := {}
	var foot := {}
	var top := {}
	for id in direct:
		var e := doc.find(String(id))
		if e.is_empty():
			continue
		both[String(id)] = true
		if not e.has("contour"):
			for a in attached(doc, e):
				both[String(a)] = true
			continue
		for a in attached(doc, e):
			if String(doc.find(String(a)).get("type", "")) == "escalier":
				foot[String(a)] = true
			else:
				both[String(a)] = true
		for s in arrivals(doc, e):
			top[String(s)] = true
	for s in foot.keys():
		if top.has(s):
			both[s] = true
	for s in both:
		foot.erase(s)
		top.erase(s)
	return {"both": both.keys(), "foot": foot.keys(), "top": top.keys()}


## Applique un déplacement vertical de `dalt` m (vertical_plan) à la carte.
static func lift(doc: EditorMap, plan: Dictionary, dalt: float) -> void:
	if dalt == 0.0:
		return
	for id in plan.get("both", []):
		var e := doc.find(String(id))
		if not e.is_empty():
			EditorMap.shift_alt(e, dalt)
	for id in plan.get("foot", []):
		var e := doc.find(String(id))
		if not e.is_empty():
			e["altitude_haut"] = doc.stair_top_of(e)
			e["altitude"] = MapGeom.cube(EditorMap.alt_of(e) + dalt)
	for id in plan.get("top", []):
		var e := doc.find(String(id))
		if not e.is_empty():
			e["altitude_haut"] = MapGeom.cube(doc.stair_top_of(e) + dalt)


## Objets muraux accrochés à un mur libre `e` (outil Mur, mur courbe) : leur
## trait est sur une face du mur, parallèle à lui ; ils bougent et tournent avec
## lui.
static func on_free_wall(doc: EditorMap, e: Dictionary) -> Array:
	var out := []
	var half := float(e.get("epaisseur", 0.5)) * 0.5
	var off := half - MapGeom.WALL_HALF
	var segs := MapShapes.arc_segments(e) if String(e.get("type", "")) == "mur_courbe" else [[MapGeom.v2(e.a), MapGeom.v2(e.b)]]
	for o in doc.objects_on(doc.level_of(e)):
		if MapCatalog.tool_of(o) != "wall_item":
			continue
		var p := MapGeom.v2(o.get("position", [0, 0]))
		var dv := MapGeom.item_wall_dir(o)
		for s in segs:
			var a: Vector2 = s[0]
			var b: Vector2 = s[1]
			if a.distance_to(b) < 0.01:
				continue
			var t := (b - a).normalized()
			if absf(dv.dot(t)) < 0.05 and absf(MapGeom.dist_to_segment(p, a, b) - off) < 0.02 \
					and MapGeom.dist_to_segment(p + dv * off, a, b) < 0.02:
				out.append(String(o.id))
				break
	return out


## Emprise d'un objet au sol ré-aimantée sur la grille après un quart de tour
## (un décor 3 × 2 devient 2 × 3) ; tourné au degré près : position gardée.
static func resnap(o: Dictionary) -> void:
	if MapCatalog.tool_of(o) != "floor_item" or not o.has("position") or MapRaster.free_rot(o) or String(o.get("type", "")) == "effet":
		return
	var n := MapCatalog.floor_size(o)
	var p := MapGeom.v2(o.position)
	o["position"] = MapGeom.arr(Vector2(MapGeom.snap_along(p.x, n.x), MapGeom.snap_along(p.y, n.y)))


## Élément déplacé de `delta` (m, dans le plan) : copie (contour, forme,
## sommets, position, a, b, centre, rectangle). `snap` : coordonnées au
## millimètre (MapGeom.arr, déplacements de l'éditeur) ; sinon exactes (copie
## décalée du raster : mêmes cases à un multiple de 0,5 m près).
static func shifted(o: Dictionary, delta: Vector2, snap := true) -> Dictionary:
	var e := o.duplicate(true)
	# Format 20 : l'architecture déplacée par l'éditeur reste sur la grille des
	# cubes de 5 cm (le décor garde le millimètre).
	var archi := snap and MapCubeSnap.is_architecture(e)
	var pt := func(p: Array) -> Array:
		if archi:
			return MapGeom.cube_arr(MapGeom.v2(p) + delta)
		return MapGeom.arr(MapGeom.v2(p) + delta) if snap else [float(p[0]) + delta.x, float(p[1]) + delta.y]
	if e.get("contour") is Array:
		var pts := []
		for p in e.contour:
			pts.append(pt.call(p))
		e.contour = pts
		if e.has("forme") and MapShapes.valid(e.forme):
			e.forme = MapShapes.shifted(e.forme, delta)
	if e.get("sommets") is Array:
		# Barrière invisible en polygone (format 9).
		var pts := []
		for p in e.sommets:
			pts.append(pt.call(p))
		e.sommets = pts
	for key in ["position", "a", "b", "centre"]:
		if e.get(key) is Array and (e[key] as Array).size() >= 2:
			e[key] = pt.call(e[key])
	if e.get("rect") is Array and (e.rect as Array).size() == 4:
		if snap:
			var r := MapGeom.rect_of(e.rect)
			r.position += delta
			if archi:
				r = Rect2(MapGeom.round_cube(r.position), Vector2.ZERO).expand(MapGeom.round_cube(r.end))
			e.rect = MapGeom.rect_arr(r)
		else:
			var a: Array = e.rect
			e.rect = [float(a[0]) + delta.x, float(a[1]) + delta.y, float(a[2]) + delta.x, float(a[3]) + delta.y]
	return e


## Carte décalée de `delta` (m) pour le raster (coordonnées négatives,
## MapRaster) : pièces, ouvertures et objets copiés et déplacés exactement ;
## le reste (réglages, zones, prefabs, textures) partagé, en lecture seule.
static func shifted_map(doc: EditorMap, delta: Vector2) -> EditorMap:
	var m := EditorMap.new()
	m.carte = doc.carte
	m.zones = doc.zones
	m.depart = doc.depart
	m.prefabs = doc.prefabs
	m.models = doc.models
	m.textures = doc.textures
	m.texture_files = doc.texture_files
	m.view_levels = doc.view_levels
	for pair in [[doc.pieces, m.pieces], [doc.ouvertures, m.ouvertures], [doc.objets, m.objets]]:
		for e in pair[0]:
			(pair[1] as Array).append(shifted(e, delta, false) if e is Dictionary else e)
	return m


## Remplace dans la carte l'élément de même identifiant.
static func replace(doc: EditorMap, e: Dictionary) -> void:
	var list := doc.list_of(String(e.id))
	for i in list.size():
		if String(list[i].id) == String(e.id):
			list[i] = e
			return


## Tourne `orig` (et les éléments `attached`, identifiants) de `deg` degrés
## autour de `c`, depuis la carte `snap0` ; appliqué seulement si l'élément
## tourné est valide. -> {ok, ...} (raison sinon).
static func apply(doc: EditorMap, orig: Dictionary, attached_ids: Array, c: Vector2, deg: float, snap0: Dictionary) -> Dictionary:
	var cand := rotated(orig, c, deg)
	if String(orig.get("type", "")) != "" and not orig.has("contour"):
		resnap(cand)
	# État courant (le dernier valide) gardé en cas de refus.
	var before := doc.snapshot()
	doc.restore(snap0)
	replace(doc, cand)
	for aid in attached_ids:
		var a := doc.find(aid)
		if not a.is_empty():
			var ra := rotated(a, c, deg)
			resnap(ra)
			replace(doc, ra)
	var res := MapRules.check_existing(doc, doc.find(String(orig.id)))
	if not res.ok:
		doc.restore(before)
		return res
	return {"ok": true}


## Forme posée régénérée avec les paramètres `forme` (nombre de points,
## rayons, angle...) : nouveau contour, ouvertures et objets muraux de la pièce
## raccrochés au mur le plus proche. -> {ok} ou la raison du refus (carte
## inchangée).
static func regenerate(doc: EditorMap, room: Dictionary, forme: Dictionary) -> Dictionary:
	if not MapShapes.valid(forme):
		return MapRules.refuse("forme invalide", "invalid shape")
	var k := doc.level_of(room)
	# Format 20 : sommets sur la grille des cubes de 5 cm.
	var poly := MapGeom.cube_poly(MapShapes.outline(forme))
	var res := MapRules.check_room(doc, k, poly, String(room.id))
	if not res.ok:
		return res
	var old := doc.room_poly(room)
	var before := doc.snapshot()
	var openings := doc.openings_on(k).filter(func(o): return MapGeom.on_boundary(old, MapGeom.v2(o.position), MapGeom.JOIN_TOL))
	var items := doc.objects_on(k).filter(func(o): return MapCatalog.tool_of(o) == "wall_item" and MapGeom.contains(old, MapRules.footprint_rect(o).get_center()))
	room["contour"] = MapGeom.poly_arr(poly)
	room["forme"] = forme.duplicate(true)
	for o in openings:
		var r := MapRules.place_opening(doc, k, String(o.type), MapGeom.v2(o.position), MapRules.opening_width(o), String(o.id))
		if r.ok:
			o["position"] = r.position
	for o in items:
		var r := MapRules.place_wall_item(doc, k, o, MapGeom.v2(o.position) - MapGeom.item_wall_dir(o) * 0.6, String(o.id))
		if r.ok:
			o["position"] = r.position
			MapRules.apply_wall(o, r)
	if doc.find(String(room.id)).is_empty():
		doc.restore(before)
		return MapRules.refuse("pièce introuvable", "room not found")
	return {"ok": true}


# ------------------------------------------------------------------ zone d'un effet (format 11)

## Poignées de la zone d'un effet (m) : au sol et au plafond, les 4 coins
## (haut-gauche, haut-droit, bas-droit, bas-gauche dans le repère de
## l'effet) puis les 4 milieux (haut, droite, bas, gauche), tournés avec
## lui, comme une pièce rectangle ; mural, les 2 bouts de sa largeur sur la
## face du mur.
static func effect_handles(o: Dictionary) -> PackedVector2Array:
	var poly := MapRules.effect_poly(o)
	if MapCatalog.effect_mount(o) == "mur":
		return PackedVector2Array([poly[0], poly[1]])
	var out := poly.duplicate()
	for i in 4:
		out.append((poly[i] + poly[(i + 1) % 4]) * 0.5)
	return out


## Effet dont la poignée `h` (effect_handles) est tirée en `p` : le côté (ou
## le coin) opposé reste en place, chaque dimension bornée à celles de
## l'effet (jamais retournée) et arrondie à MapCatalog.ZONE_STEP ; copie.
static func effect_resized(o: Dictionary, h: int, p: Vector2) -> Dictionary:
	var e := o.duplicate(true)
	var fid := String(o.get("effet", ""))
	var z := MapCatalog.effect_zone(o)
	var c := MapGeom.v2(o.get("position", [0, 0]))
	if MapCatalog.effect_mount(o) == "mur":
		# Largeur le long du mur : l'autre bout reste en place, l'objet glisse le
		# long du mur (même trait, même direction).
		var dv := MapGeom.item_wall_dir(o)
		var t := Vector2(dv.y, -dv.x)   # sens de effect_poly : poly[0] = face - t × l/2
		var u := (p - c).dot(t)
		var lo := -z.x * 0.5
		var hi := z.x * 0.5
		var b := MapCatalog.effect_zone_bounds(fid, "l")
		if h == 0:
			lo = hi - _span(hi - u, b)
		else:
			hi = lo + _span(u - lo, b)
		z.x = hi - lo
		e["position"] = MapGeom.arr(MapGeom.round_mm(c + t * (lo + hi) * 0.5))
		MapCatalog.set_effect_zone(e, z)
		return e
	var rot := deg_to_rad(float(MapGeom.rot_of(o)))
	var local := (p - c).rotated(-rot)
	var x0 := -z.x * 0.5
	var x1 := z.x * 0.5
	var y0 := -z.y * 0.5
	var y1 := z.y * 0.5
	var bl := MapCatalog.effect_zone_bounds(fid, "l")
	var bp := MapCatalog.effect_zone_bounds(fid, "p")
	# Coins 0-3 (haut-gauche, haut-droit, bas-droit, bas-gauche), milieux 4-7 (haut, droite, bas, gauche).
	if h in [0, 3, 7]:
		x0 = x1 - _span(x1 - local.x, bl)
	if h in [1, 2, 5]:
		x1 = x0 + _span(local.x - x0, bl)
	if h in [0, 1, 4]:
		y0 = y1 - _span(y1 - local.y, bp)
	if h in [2, 3, 6]:
		y1 = y0 + _span(local.y - y0, bp)
	z.x = x1 - x0
	z.y = y1 - y0
	e["position"] = MapGeom.arr(MapGeom.round_mm(c + Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5).rotated(rot)))
	MapCatalog.set_effect_zone(e, z)
	return e


## Longueur tirée à la poignée, arrondie au pas de la zone et bornée.
static func _span(v: float, b: Array) -> float:
	return clampf(MapCatalog.snap_zone(v), float(b[0]), float(b[1]))
