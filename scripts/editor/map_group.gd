class_name MapGroup
extends RefCounted
## SÉLECTION MULTIPLE de l'éditeur de cartes (docs/MAP_AUTHORING.md, § 2,
## « Sélection multiple et groupes ») : les actions sur plusieurs éléments à
## la fois — déplacer (aussi d'étage, dans les élévations), pivoter autour du
## centre du groupe, supprimer, copier / coller, dupliquer — et le choix par
## rectangle.
##
## Chaque action est validée EN ENTIER par les règles de pose sur la carte
## modifiée (MapRules.check_existing : les éléments du groupe se voient les uns
## les autres à leur nouvelle place) : un seul élément refusé et rien ne
## change ; le refus nomme l'élément et donne la raison (« el » : l'élément à
## la place refusée, mis en évidence sur le plan). Les éléments rattachés
## (contenu d'une pièce, portes sur ses bords, objets d'un mur libre :
## MapTransform.attached) suivent comme pour un seul élément. Une action =
## une étape d'annulation (MapEditor.push_undo_snapshot puis changed : un seul
## lot d'opérations envoyé à la session).


## Éléments qui bougent avec le groupe `ids` : eux et leurs rattachés, sans
## doublon (identifiants des éléments de la carte, jamais des zones).
static func movers(doc: EditorMap, ids: Array) -> Array:
	var out := []
	for id in ids:
		var e := doc.find(String(id))
		if e.is_empty() or _is_zone(doc, String(id)):
			continue
		if not out.has(String(id)):
			out.append(String(id))
		for a in MapTransform.attached(doc, e):
			if not out.has(String(a)):
				out.append(String(a))
	return out


static func _is_zone(doc: EditorMap, eid: String) -> bool:
	return not doc.zone(eid).is_empty()


## Identifiants d'éléments de la carte (pièces, ouvertures, objets) parmi
## `ids`, sans doublon ni zone, dans l'ordre.
static func clean_ids(doc: EditorMap, ids: Array) -> Array:
	var out := []
	for x in ids:
		if x is String and not out.has(x) and not doc.find(x).is_empty() and not _is_zone(doc, x):
			out.append(x)
	return out


## Rectangle (m) d'un élément : pièce (rectangle englobant), ouverture (carré
## de sa largeur), objet (emprise).
static func rect_m(doc: EditorMap, e: Dictionary) -> Rect2:
	if e.has("contour"):
		return MapGeom.bbox(doc.room_poly(e))
	if String(e.get("type", "")) in MapRules.ouvertures_types():
		var p := MapGeom.v2(e.position)
		var w := MapRules.opening_width(e)
		return Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w))
	return MapRules.footprint_rect(e)


## Rectangle englobant (m) d'éléments (dictionnaires).
static func bounds_of(doc: EditorMap, els: Array) -> Rect2:
	var bb := Rect2()
	var first := true
	for e in els:
		var r := rect_m(doc, e)
		bb = r if first else bb.merge(r)
		first = false
	return bb


## Rectangle englobant (m) des éléments `ids` de la carte.
static func bounds(doc: EditorMap, ids: Array) -> Rect2:
	var els := []
	for id in ids:
		var e := doc.find(String(id))
		if not e.is_empty():
			els.append(e)
	return bounds_of(doc, els)


## Centre de rotation du groupe : milieu de son rectangle englobant, sur la
## grille de 0,5 m (sauf aimantation libre) : un quart de tour garde alors
## les sommets sur la grille.
static func pivot(doc: EditorMap, ids: Array, free := false) -> Vector2:
	var c := bounds(doc, ids).get_center()
	return c if free else Vector2(snappedf(c.x, 0.5), snappedf(c.y, 0.5))


## Nom d'un élément pour les messages : [fr, en].
static func name_of(e: Dictionary) -> Array:
	return MapRules._name(e)


## Refus `r` de l'élément `e`, nommé (« « Table » : chevauche… ») ; « bad » :
## son identifiant, « el » : l'élément à la place refusée (mis en évidence).
static func named(e: Dictionary, r: Dictionary) -> Dictionary:
	var n := name_of(e)
	var out := MapRules.refuse("« %s » : %s" % [n[0], String(r.get("fr", ""))], "\"%s\": %s" % [n[1], String(r.get("en", ""))])
	out["bad"] = [String(e.get("id", ""))]
	out["el"] = e.duplicate(true)
	if r.has("marks"):
		out["marks"] = r.marks
	return out


## Vérifie les éléments `ids` dans la carte telle qu'elle est (MapRules) :
## {ok: true}, ou le refus nommé du premier élément invalide.
static func check(doc: EditorMap, ids: Array) -> Dictionary:
	var res := {"ok": true}
	MapRules.begin_batch(doc)
	for id in ids:
		var e := doc.find(String(id))
		if e.is_empty():
			continue
		var k := doc.level_of(e)
		var r := {"ok": true}
		if k < 0 or k >= doc.level_count():
			r = MapRules.refuse("pas de pièce à cette altitude", "no room at that altitude")
		elif String(e.get("type", "")) == "escalier" and k >= doc.level_count() - 1:
			r = MapRules.refuse("un escalier ne peut pas aller sur le dernier niveau", "stairs cannot go on the top level")
		else:
			r = MapRules.check_existing(doc, e)
		if not r.ok:
			res = named(e, r)
			break
	MapRules.end_batch()
	return res


## Décors bloquants posés sur l'un des éléments `all` sans en faire partie
## (§ 7 : ils tomberaient en l'air si le groupe bougeait sans eux).
static func held_on(doc: EditorMap, all: Array) -> Array:
	var out := []
	for id in all:
		var e := doc.find(String(id))
		if e.is_empty():
			continue
		for q in MapVertical.resting_on(doc, e, all):
			if not out.has(q):
				out.append(q)
	return out


## Annule une tentative refusée : la carte revient à `last` (la dernière
## place valide), le refus `r` est rendu.
static func _back(ed: MapEditor, last: Dictionary, r: Dictionary) -> Dictionary:
	ed.doc.restore(last)
	ed.moved_live()
	return r


# ------------------------------------------------------------------ déplacer, pivoter

## Déplace le groupe : `all` (movers, calculés au début du glissement) décalés
## de `delta` (m, dans le plan) et de `dk` étages ; `dz` (m ; NAN : aucun)
## ajouté à la hauteur de pose de départ `z0` (id -> m au-dessus du sol) des
## éléments posés. Depuis la carte `snap0`. Refusé : la carte reste à sa
## dernière place valide et le refus nommé est rendu.
static func move(ed: MapEditor, all: Array, delta: Vector2, dk: int, snap0: Dictionary, dz := NAN, z0 := {}) -> Dictionary:
	var doc := ed.doc
	var last := doc.snapshot()
	doc.restore(snap0)
	var held := held_on(doc, all)
	# Niveaux relevés avant le déplacement (déplacer des pièces les change).
	var lv := doc.levels().duplicate()
	for id in all:
		var e := doc.find(String(id))
		if e.is_empty():
			continue
		var c := MapEditor._shift(e, delta)
		EditorMap.shift_levels(c, lv, dk)
		MapTransform.replace(doc, c)
	if not is_nan(dz) and not z0.is_empty():
		ed._raster_dirty = true
		var v := ed.raster().v
		for id in z0:
			var e := doc.find(String(id))
			if e.is_empty():
				continue
			MapVertical.set_pose_z(doc, v, e, float(z0[id]) + dz)
			var chk := MapVertical.check_pose(doc, v, e)
			if not chk.ok:
				return _back(ed, last, named(e, chk))
	var res := check(doc, all)
	if res.ok:
		res = MapVertical.check_rests(doc, held)
	if not res.ok:
		return _back(ed, last, res)
	ed.moved_live()
	return {"ok": true}


## Pivote le groupe `all` de `deg` degrés (sens horaire vu de dessus) autour
## de `c`, depuis la carte `snap0` (un décor au sol tourné d'un quart de tour
## est ré-aimanté sur la grille, MapTransform.resnap). Refusé : dernière place
## valide gardée.
static func rotate(ed: MapEditor, all: Array, c: Vector2, deg: float, snap0: Dictionary) -> Dictionary:
	var doc := ed.doc
	var last := doc.snapshot()
	doc.restore(snap0)
	var held := held_on(doc, all)
	for id in all:
		var e := doc.find(String(id))
		if e.is_empty():
			continue
		var r := MapTransform.rotated(e, c, deg)
		if not e.has("contour"):
			MapTransform.resnap(r)
		MapTransform.replace(doc, r)
	var res := check(doc, all)
	if res.ok:
		res = MapVertical.check_rests(doc, held)
	if not res.ok:
		return _back(ed, last, res)
	ed.moved_live()
	return {"ok": true}


# ------------------------------------------------------------------ supprimer

## Supprime le groupe `ids` et ses rattachés, en une étape d'annulation. Un
## décor qui en porte un autre hors du groupe refuse tout (§ 7). -> {ok, n}
## ou le refus nommé.
static func delete_ids(ed: MapEditor, ids: Array) -> Dictionary:
	var doc := ed.doc
	var all := movers(doc, ids)
	if all.is_empty():
		return MapRules.refuse("rien à supprimer", "nothing to delete")
	for id in all:
		var e := doc.find(String(id))
		if not MapVertical.resting_on(doc, e, all).is_empty():
			return named(e, MapRules.refuse("un décor est posé dessus : sélectionnez-le aussi, ou supprimez-le d'abord",
				"a prop stands on it: select it too, or delete it first"))
	ed.push_undo()
	for id in all:
		doc.remove(String(id))
	doc.tidy_zones()
	ed.group = []
	ed.selected = ""
	ed.changed()
	return {"ok": true, "n": all.size()}


# ------------------------------------------------------------------ copier, coller, dupliquer

## Copies indépendantes des éléments `ids` (exactement ceux choisis : le
## contenu d'une pièce n'est copié que s'il est choisi aussi).
static func copies(doc: EditorMap, ids: Array) -> Array:
	var out := []
	for id in clean_ids(doc, ids):
		out.append(doc.find(id).duplicate(true))
	return out


## Niveau d'un élément copié : celui de son altitude, sinon le plus proche
## (copie venue d'une autre carte).
static func level_near(doc: EditorMap, e: Dictionary) -> int:
	var k := doc.level_of(e)
	return k if k >= 0 else doc.nearest_level(EditorMap.alt_of(e))


## Pose des copies de `items` décalées de `delta` (m) et de `dk` étages, en
## une étape d'annulation : identifiants neufs, pièces renommées (« Pièce N »)
## avec une zone neuve par zone d'origine, boîte jamais « départ ». Tout est
## vérifié ensemble ; un refus laisse la carte intacte. -> {ok, ids} ou le
## refus nommé.
static func place_copies(ed: MapEditor, items: Array, delta: Vector2, dk: int) -> Dictionary:
	var doc := ed.doc
	if items.is_empty():
		return MapRules.refuse("rien à coller", "nothing to paste")
	var lv := doc.levels().duplicate()
	for it in items:
		var nk := level_near(doc, it) + dk
		if nk < 0 or nk >= doc.level_count():
			return MapRules.refuse("le groupe ne tient pas dans les niveaux de la carte (%d niveau(x))" % doc.level_count(),
				"the group does not fit in the map's levels (%d level(s))" % doc.level_count())
	var before := doc.snapshot()
	var zmap := {}
	var new_ids := []
	for it in items:
		var e := MapEditor._shift(it, delta)
		e.erase("id")
		var k0 := level_near(doc, it)
		var d0 := EditorMap.level_alt_in(lv, k0) - EditorMap.alt_of(it)
		EditorMap.shift_alt(e, d0)
		EditorMap.shift_levels(e, lv, dk)
		var oz := ""
		if e.has("contour"):
			e.erase("nom")
			oz = String(e.get("zone", ""))
			if zmap.has(oz):
				e["zone"] = zmap[oz]
			else:
				e.erase("zone")
		if String(e.get("type", "")) == "boite":
			e.erase("depart")
		ed.insert_element(e)
		if e.has("contour") and oz != "" and not zmap.has(oz):
			zmap[oz] = String(e.get("zone", ""))
		new_ids.append(String(e.id))
	var res := check(doc, new_ids)
	if not res.ok:
		doc.restore(before)
		ed.moved_live()
		return res
	ed.push_undo_snapshot(before)
	ed.changed()
	ed.select_many(new_ids)
	return {"ok": true, "ids": new_ids}


## Colle `items` sous le point `at` (m) de l'étage courant : le centre de leur
## rectangle englobant va au point aimanté (le décalage garde la grille de
## 0,5 m sauf en aimantation libre) ; un groupe sur plusieurs étages garde ses
## écarts d'étage, son étage le plus bas va à l'étage courant.
static func paste(ed: MapEditor, items: Array, at: Vector2) -> Dictionary:
	if items.is_empty():
		return MapRules.refuse("rien à coller", "nothing to paste")
	var c := bounds_of(ed.doc, items).get_center()
	# Décalage en pas entiers de la grille (au centimètre sans grille) : les
	# éléments restent sur la grille, et coller au centre d'origine remet tout
	# en place.
	var delta := MapGeom.round_cm(at - c)
	if ed.canvas.mode_now() != "libre":
		var st := ed.canvas.step()
		delta = Vector2(snappedf(delta.x, st), snappedf(delta.y, st))
	var k0 := 1000
	for it in items:
		k0 = mini(k0, level_near(ed.doc, it))
	return place_copies(ed, items, delta, ed.floor_k - k0)


## Duplique les éléments `ids` à côté d'eux (même étage) : à droite (est),
## sinon dessous (sud), à gauche, dessus, sinon d'un pas en diagonale ; la
## première place où tout tient. -> {ok, ids, dir: [fr, en]} ou le refus
## de la dernière place essayée.
static func duplicate_ids(ed: MapEditor, ids: Array) -> Dictionary:
	var items := copies(ed.doc, ids)
	if items.is_empty():
		return MapRules.refuse("rien à dupliquer", "nothing to duplicate")
	var bb := bounds_of(ed.doc, items)
	var s := maxf(ed.canvas.step(), 0.5)
	var w := ceilf(bb.size.x / s - 0.001) * s
	var h := ceilf(bb.size.y / s - 0.001) * s
	var tries := [[Vector2(w, 0), ["à droite", "to the right"]], [Vector2(0, h), ["dessous", "below"]],
		[Vector2(-w, 0), ["à gauche", "to the left"]], [Vector2(0, -h), ["dessus", "above"]], [Vector2(s, s), ["en diagonale", "diagonally"]]]
	var res := {}
	for t in tries:
		if (t[0] as Vector2).length() < 0.001:
			continue
		res = place_copies(ed, items, t[0], 0)
		if res.ok:
			res["dir"] = t[1]
			return res
	return res


# ------------------------------------------------------------------ choix par rectangle

## Contour (m) d'un élément pour le choix par rectangle : sa forme exacte
## (pièce, objet tourné, barrière...), sinon les 4 coins de son rectangle.
static func outline_m(doc: EditorMap, e: Dictionary) -> PackedVector2Array:
	if e.has("contour"):
		return doc.room_poly(e)
	var t := String(e.get("type", ""))
	if t == "bloc_invisible":
		return MapRaster.clip_poly(e)
	if t == "effet":
		return MapRules.effect_poly(e)
	if e.has("rect") and MapGeom.rot_of(e) != 0:
		return MapRaster.rect_poly(e)
	return MapGeom.rect_poly(rect_m(doc, e))


## Éléments de l'étage `k` pris par le rectangle `r` (m) : ENTIÈREMENT dedans
## (`crossing` faux : rectangle tracé de gauche à droite) ou seulement
## TOUCHÉS (`crossing` vrai : de droite à gauche), comme dans les logiciels de
## CAO. Ouvertures, puis objets, puis pièces.
static func in_rect(doc: EditorMap, k: int, r: Rect2, crossing: bool) -> Array:
	var out := []
	var rp := MapGeom.rect_poly(r)
	for list in [doc.openings_on(k), doc.objects_on(k), doc.rooms_on(k)]:
		for e in list:
			var bb := rect_m(doc, e)
			var take := false
			if r.encloses(bb):
				take = true
			elif crossing and r.intersects(bb, true):
				var poly := outline_m(doc, e)
				take = poly.size() < 3 or not Geometry2D.intersect_polygons(poly, rp).is_empty()
			if take:
				out.append(String(e.id))
	return out
