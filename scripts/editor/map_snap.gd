class_name MapSnap
extends RefCounted
## Aimantation de l'éditeur de cartes (docs/MAP_AUTHORING.md, « Formes
## libres ») : trois modes, choisis avec la touche G (réglage mémorisé) :
##   grille  pas de 1 m (côtés à 0, 45 ou 90°, Alt : angle libre) ;
##   fine    pas de 0,5, 0,25 ou 0,1 m (Maj+G change le pas) ;
##   libre   sans grille : coordonnées au centimètre, côtés à 15° près (Alt :
##           angle libre), aimantation aux sommets et aux côtés des pièces
##           existantes (pour coller deux pièces).
## Maj maintenu inverse le mode courant (grille ou fine <-> libre).
## Fonctions pures, testées par tests/test_map_editor_freeform.gd.

const MODES := ["grille", "fine", "libre"]
const FINE_STEPS := [0.5, 0.25, 0.1]
## Rayon de l'aimant aux sommets et aux côtés (pixels à l'écran).
const MAGNET_PX := 10.0
## Pas des angles sans grille (degrés).
const FREE_ANGLE_STEP := 15.0


## Mode réellement appliqué : Maj inverse le mode (grille ou fine -> libre ;
## libre -> la dernière grille utilisée).
static func effective(mode: String, invert: bool, last_grid: String) -> String:
	if not invert:
		return mode
	return last_grid if mode == "libre" else "libre"


## Pas de la grille d'un mode (m) ; libre : le centimètre.
static func step_of(mode: String, fine_step: float) -> float:
	match mode:
		"fine":
			return fine_step
		"libre":
			return 0.01
	return 1.0


## Point aimanté sur la grille du mode (sans les aimants de la carte).
static func on_step(m: Vector2, mode: String, fine_step: float) -> Vector2:
	if mode == "libre":
		return MapGeom.round_cm(m)
	var s := step_of(mode, fine_step)
	return Vector2(roundf(m.x / s) * s, roundf(m.y / s) * s)


## Nom affiché d'un mode (« grille 1 m », « grille fine 0,25 m », « libre »).
static func label(mode: String, fine_step: float) -> String:
	match mode:
		"fine":
			return Lang.t("grille fine %s m", "fine grid %s m") % MapRules._m(fine_step, not Lang.is_en())
		"libre":
			return Lang.t("libre (sans grille)", "free (no grid)")
	return Lang.t("grille 1 m", "1 m grid")


## Mode suivant (touche G) et pas fin suivant (Maj+G).
static func next_mode(mode: String) -> String:
	return MODES[(MODES.find(mode) + 1) % MODES.size()]


static func next_fine(step: float) -> float:
	var i := 0
	for j in FINE_STEPS.size():
		if absf(float(FINE_STEPS[j]) - step) < 0.001:
			i = j
	return FINE_STEPS[(i + 1) % FINE_STEPS.size()]


## Aimant de la carte près de `m` (étage k, rayon `radius` m) : un sommet de
## pièce ou un bout de mur, sinon un point d'un côté de pièce (projection).
## `exclude` : identifiant de l'élément en cours de modification. Format 17 :
## `ghost` (indice d'un niveau, -1 : aucun) : les sommets des pièces de ce
## niveau (fantôme du niveau du dessous) aimantent aussi (« fantome »).
## -> {"p": point, "kind": "sommet" | "fantome" | "cote", "a", "b" (côté)} ou {}.
static func magnet(doc: EditorMap, k: int, m: Vector2, radius: float, exclude := "", ghost := -1) -> Dictionary:
	var best := {}
	var best_d := radius
	var edges := []
	if ghost >= 0 and ghost != k:
		for r in doc.rooms_on(ghost):
			var gp := doc.room_poly(r)
			if not MapGeom.bbox(gp).grow(radius).has_point(m):
				continue
			for q in gp:
				if q.distance_to(m) < best_d:
					best_d = q.distance_to(m)
					best = {"p": q, "kind": "fantome"}
	for r in doc.rooms_on(k):
		if String(r.get("id", "")) == exclude:
			continue
		var poly := doc.room_poly(r)
		if not MapGeom.bbox(poly).grow(radius).has_point(m):
			continue
		for i in poly.size():
			var d := poly[i].distance_to(m)
			if d < best_d:
				best_d = d
				best = {"p": poly[i], "kind": "sommet"}
			edges.append([poly[i], poly[(i + 1) % poly.size()]])
	for o in doc.objects_on(k):
		if String(o.get("type", "")) != "mur" or String(o.get("id", "")) == exclude:
			continue
		for key in ["a", "b"]:
			var p := MapGeom.v2(o[key])
			if p.distance_to(m) < best_d:
				best_d = p.distance_to(m)
				best = {"p": p, "kind": "sommet"}
	if not best.is_empty():
		return best
	for e in edges:
		var q := Geometry2D.get_closest_point_to_segment(m, e[0], e[1])
		var d := q.distance_to(m)
		if d < best_d:
			best_d = d
			best = {"p": Vector2(snappedf(q.x, 0.001), snappedf(q.y, 0.001)), "kind": "cote", "a": e[0], "b": e[1]}
	return best


## Point suivant d'un tracé sans grille depuis `from` : aimant d'abord (un
## sommet ; sur un côté, là où le trait à 15° le croise s'il y arrive), sinon
## angle aimanté à 15° (libre avec `free_angle`) et centimètre.
static func trace_free(doc: EditorMap, k: int, from: Vector2, m: Vector2, radius: float, free_angle: bool, exclude := "", ghost := -1) -> Vector2:
	var mg := magnet(doc, k, m, radius, exclude, ghost)
	var ang := MapGeom.snap_angle_free(from, m, FREE_ANGLE_STEP, free_angle)
	if mg.is_empty():
		return ang
	if String(mg.kind) == "cote" and not free_angle and from.distance_to(m) > 0.05:
		# Le côté à 15° prolongé jusqu'au côté aimanté, s'il le croise près du curseur.
		var dir := (ang - from).normalized()
		var hit: Variant = Geometry2D.segment_intersects_segment(from, from + dir * (from.distance_to(m) + radius * 4.0), mg.a, mg.b)
		if hit != null and (hit as Vector2).distance_to(m) < radius * 2.0:
			return Vector2(snappedf(hit.x, 0.001), snappedf(hit.y, 0.001))
	return mg.p


## Décalage d'une pièce déplacée sans grille, aimanté : le sommet de la pièce
## le plus proche d'un sommet ou d'un côté d'une autre pièce s'y colle.
static func room_delta(doc: EditorMap, k: int, poly: PackedVector2Array, delta: Vector2, radius: float, exclude: String, ghost := -1) -> Vector2:
	var best := delta
	var best_d := radius
	for v in poly:
		var target := v + delta
		var mg := magnet(doc, k, target, radius, exclude, ghost)
		if mg.is_empty():
			continue
		var d := Vector2(mg.p).distance_to(target)
		if d < best_d:
			best_d = d
			best = delta + (Vector2(mg.p) - target)
	return Vector2(snappedf(best.x, 0.001), snappedf(best.y, 0.001))
