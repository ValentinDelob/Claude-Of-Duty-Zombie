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
	return e.has("contour") or e.has("rect") or t in ["mur", "mur_courbe"] or MapCatalog.rotates(e)


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
	if e.has("contour"):
		var pts := []
		for p in e.contour:
			pts.append(MapGeom.arr(MapGeom.rotate_about(MapGeom.v2(p), c, d)))
		e.contour = pts
		if e.has("forme"):
			if MapShapes.valid(e.forme):
				e.forme = MapShapes.rotated(e.forme, c, d)
			else:
				e.erase("forme")
	for key in ["position", "a", "b", "centre"]:
		if e.has(key):
			e[key] = MapGeom.arr(MapGeom.rotate_about(MapGeom.v2(e[key]), c, d))
	if e.has("rect"):
		var r := MapGeom.rect_of(e.rect)
		if quarter and MapGeom.rot_of(e) == 0:
			# Quart de tour d'un rectangle droit : il reste droit (grille).
			var p0 := MapGeom.rotate_about(r.position, c, d)
			var p1 := MapGeom.rotate_about(r.end, c, d)
			e.rect = MapGeom.rect_arr(Rect2(p0, Vector2.ZERO).expand(p1))
			if e.has("monte"):
				for i in d / 90:
					e["monte"] = MapGeom.dir_rot(String(e.monte))
		else:
			var nc := MapGeom.rotate_about(r.get_center(), c, d)
			e.rect = MapGeom.rect_arr(Rect2(nc - r.size * 0.5, r.size))
			e["rot"] = MapGeom.norm_deg(MapGeom.rot_of(e) + d)
			if int(e.rot) == 0:
				e.erase("rot")
	elif e.has("rot"):
		e["rot"] = MapGeom.norm_deg(MapGeom.rot_of(e) + d)
	if e.has("mur") and not e.has("rect"):
		# Objet mural (ou applique) : il reste collé à son mur, face vers l'intérieur.
		if quarter and not e.has("angle"):
			for i in d / 90:
				e["mur"] = MapGeom.dir_rot(String(e.mur))
		else:
			var cur := float(e.angle) if e.has("angle") else MapGeom.dir_deg(MapGeom.dir_vec(String(e.mur)))
			var nd := fposmod(cur + d, 360.0)
			e["angle"] = snappedf(nd, 0.01)
			if quarter:
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
	if not e.has("contour"):
		return out
	var poly := doc.room_poly(e)
	var k := int(e.get("etage", 0))
	for o in doc.objects_on(k):
		var c := MapRules.footprint_rect(o).get_center()
		if String(o.type) == "mur":
			c = (MapGeom.v2(o.a) + MapGeom.v2(o.b)) * 0.5
		elif String(o.type) == "mur_courbe":
			var arc := MapShapes.wall_arc(o)
			c = arc[arc.size() / 2]
		if MapGeom.contains(poly, c):
			out.append(String(o.id))
	for o in doc.openings_on(k):
		if MapGeom.on_boundary(poly, MapGeom.v2(o.position), MapGeom.JOIN_TOL):
			out.append(String(o.id))
	return out


## Emprise d'un objet au sol ré-aimantée sur la grille après un quart de tour
## (un décor 3 × 2 devient 2 × 3) ; tourné au degré près : position gardée.
static func resnap(o: Dictionary) -> void:
	if MapCatalog.tool_of(o) != "floor_item" or not o.has("position") or MapRaster.free_rot(o):
		return
	var n := MapCatalog.floor_size(o)
	var p := MapGeom.v2(o.position)
	o["position"] = MapGeom.arr(Vector2(MapGeom.snap_along(p.x, n.x), MapGeom.snap_along(p.y, n.y)))


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
static func apply(doc: EditorMap, orig: Dictionary, attached: Array, c: Vector2, deg: float, snap0: Dictionary) -> Dictionary:
	var cand := rotated(orig, c, deg)
	if String(orig.get("type", "")) != "" and not orig.has("contour"):
		resnap(cand)
	# État courant (le dernier valide) gardé en cas de refus.
	var before := doc.snapshot()
	doc.restore(snap0)
	replace(doc, cand)
	for aid in attached:
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
	var k := int(room.get("etage", 0))
	var poly := MapShapes.outline(forme)
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
