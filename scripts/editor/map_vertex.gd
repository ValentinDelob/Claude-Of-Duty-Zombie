class_name MapVertex
extends RefCounted
## Sommets ajoutés ou retirés d'un contour libre dans l'éditeur de cartes
## (docs/MAP_AUTHORING.md § 2, « Ajouter ou retirer un point ») : contour
## d'une pièce (« contour », un rectangle donne ses 4 coins) et barrière
## invisible en polygone (« sommets », format 9). Poignées « + » au milieu des
## côtés (au quart et aux trois quarts d'une pièce rectangle, dont le milieu
## porte déjà la poignée de redimensionnement), point posé sur un côté,
## contour candidat contrôlé par les mêmes règles qu'un sommet déplacé
## (MapRules.check_room, MapRules.check_clip). Fonctions pures ; MapEditor
## (try_insert_vertex, try_remove_vertex) les applique en une étape
## d'annulation. Testées par tests/test_map_vertex_edit.gd.

## Sommets au moins d'un contour (une pièce, une barrière).
const MIN_POINTS := 3


## L'élément a-t-il un contour éditable point par point ?
static func editable(e: Dictionary) -> bool:
	return e.has("contour") or e.get("sommets") is Array


## Contour éditable de `e` (m) ; vide si l'élément n'en a pas.
static func poly_of(e: Dictionary) -> PackedVector2Array:
	if e.has("contour"):
		return MapGeom.poly(e.contour)
	if e.get("sommets") is Array:
		return MapGeom.poly(e.sommets)
	return PackedVector2Array()


## Pièce rectangle droite sans forme de base : 8 poignées de redimensionnement
## (MapCanvas.handles) tant qu'aucun point n'a été ajouté.
static func is_rect_room(e: Dictionary) -> bool:
	return e.has("contour") and not e.has("forme") and MapGeom.is_axis_rect(poly_of(e))


## Sommets au plus du contour de `e`.
static func max_points(e: Dictionary) -> int:
	return CustomMapGuard.MAX_VERTICES if e.has("contour") else int(MapCatalog.CLIP_POINTS[1])


## Poignées « + » de `e` : [{p (m), edge}] ; `edge` : indice du côté (du
## sommet `edge` au suivant). Aucune quand le contour est au maximum de points.
static func plus_handles(e: Dictionary) -> Array:
	var poly := poly_of(e)
	var out := []
	if poly.size() < MIN_POINTS or poly.size() >= max_points(e):
		return out
	var fracs := [0.25, 0.75] if is_rect_room(e) else [0.5]
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for f in fracs:
			out.append({"p": a.lerp(b, f), "edge": i})
	return out


## Côté de `poly` le plus proche de `m` à moins de `tol` (m) : {edge, p (point
## du côté le plus proche)} ; {} sinon.
static func edge_at(poly: PackedVector2Array, m: Vector2, tol: float) -> Dictionary:
	var best := {}
	var best_d := tol
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var q := Geometry2D.get_closest_point_to_segment(m, a, b)
		var d := q.distance_to(m)
		if d <= best_d:
			best_d = d
			best = {"edge": i, "p": q}
	return best


## Point posé sur le côté `edge` de `poly` : `snapped` (point aimanté) s'il
## tombe sur le côté, sinon le point du côté le plus proche de `raw`, au
## centimètre (un côté en biais ne passe pas par la grille).
static func point_on_edge(poly: PackedVector2Array, edge: int, raw: Vector2, snapped: Vector2) -> Vector2:
	var a := poly[edge]
	var b := poly[(edge + 1) % poly.size()]
	if MapGeom.dist_to_segment(snapped, a, b) < 0.01:
		return snapped
	return MapGeom.round_cm(Geometry2D.get_closest_point_to_segment(raw, a, b))


## Contour `poly` avec le point `p` inséré après le sommet `edge`.
static func inserted(poly: PackedVector2Array, edge: int, p: Vector2) -> PackedVector2Array:
	var np := poly.duplicate()
	np.insert(edge + 1, p)
	return np


## Contour `poly` sans le sommet `i`.
static func removed(poly: PackedVector2Array, i: int) -> PackedVector2Array:
	var np := poly.duplicate()
	np.remove_at(i)
	return np


## Sommet de `e` placé en `p` (à 1 cm près) : son indice, -1 sinon.
static func index_at(e: Dictionary, p: Vector2) -> int:
	var poly := poly_of(e)
	for i in poly.size():
		if poly[i].distance_to(p) < 0.01:
			return i
	return -1


## Élément `orig` avec le contour `np` : {res (MapRules), cand (l'élément
## modifié)}. Une pièce perd sa forme de base (elle ne se régénère plus).
static func with_poly(doc: EditorMap, orig: Dictionary, np: PackedVector2Array) -> Dictionary:
	var cand := orig.duplicate(true)
	var res := {"ok": true}
	if np.size() < MIN_POINTS:
		res = MapRules.refuse("3 sommets au moins : ce point ne peut pas être supprimé", "3 corners at least: this point cannot be deleted")
	elif orig.has("contour"):
		cand.contour = MapGeom.poly_arr(np)
		cand.erase("forme")
		res = MapRules.check_room(doc, doc.level_of(orig), np, String(orig.id))
	elif orig.get("sommets") is Array:
		cand.sommets = MapGeom.poly_arr(np)
		res = MapRules.check_clip(np)
	else:
		res = MapRules.refuse("cet élément n'a pas de contour libre", "this element has no free outline")
	return {"res": res, "cand": cand}
