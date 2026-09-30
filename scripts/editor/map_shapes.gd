class_name MapShapes
extends RefCounted
## Formes de base de l'éditeur de cartes (docs/MAP_AUTHORING.md, « Formes
## libres ») : cercle ou polygone régulier (nombre de points réglable, 3 à 64),
## ellipse, triangle, pièce en L, et mur courbe (arc de cercle en N segments).
## Une pièce posée reste un polygone éditable (clé « contour ») ; la clé
## facultative « forme » garde le type et les paramètres d'origine pour la
## régénérer (changer le nombre de points d'un cercle posé, son rayon...).
##
## « forme » d'une pièce (pieces.json, format 4) :
##   {"type": "cercle" | "ellipse" | "triangle" | "l", "centre": [x, y],
##    "rx": demi-largeur (m), "ry": demi-hauteur (m), "points": 3 à 64
##    (cercle, ellipse), "angle": rotation (degrés, sens horaire vu de dessus),
##    "bras": épaisseur des branches du L (fraction 0,2 à 0,8)}
## Mur courbe (objets.json, type « mur_courbe ») : {"centre", "rayon",
##   "debut" (direction du premier bout, degrés dans le sens horaire depuis le
##   nord), "ouverture" (degrés), "segments" (1 à 64), "epaisseur"}.
## Fonctions pures, testées par tests/test_map_editor_freeform.gd.

const TYPES := ["cercle", "ellipse", "triangle", "l"]
const MIN_POINTS := 3
const MAX_POINTS := 64
const DEFAULT_POINTS := 24
const MIN_SEGMENTS := 1
const MAX_SEGMENTS := 64
const DEFAULT_SEGMENTS := 8
const DEFAULT_OPENING := 90.0
## Rayon (ou demi-côté) maximal d'une forme (m).
const MAX_RADIUS := 128.0


## Polygone régulier (cercle à `n` points) de centre `c`, de rayons `rx`, `ry`
## (ellipse si différents), tourné de `angle` degrés. À angle 0, un côté est à
## plat en bas (au sud) ; avec un nombre de points multiple de 4, les côtés
## nord, est, ouest et sud sont droits (une pièce rectangle s'y colle).
static func regular(c: Vector2, rx: float, ry: float, n: int, angle := 0.0) -> PackedVector2Array:
	n = clampi(n, MIN_POINTS, MAX_POINTS)
	var out := PackedVector2Array()
	for i in n:
		var phi := PI * 0.5 + PI / n + TAU * i / n
		var q := Vector2(rx * cos(phi), ry * sin(phi))
		out.append(c + q.rotated(deg_to_rad(angle)))
	return out


## Triangle isocèle dans le rectangle de demi-côtés rx, ry (pointe au nord à
## angle 0), tourné de `angle` degrés.
static func triangle(c: Vector2, rx: float, ry: float, angle := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in [Vector2(0, -ry), Vector2(rx, ry), Vector2(-rx, ry)]:
		out.append(c + (q as Vector2).rotated(deg_to_rad(angle)))
	return out


## Pièce en L dans le rectangle de demi-côtés rx, ry : l'angle rentrant est au
## nord-est à angle 0 ; `bras` = épaisseur des branches (fraction des côtés).
static func l_shape(c: Vector2, rx: float, ry: float, bras := 0.5, angle := 0.0) -> PackedVector2Array:
	var b := clampf(bras, 0.2, 0.8)
	var wx := 2.0 * rx * b
	var wy := 2.0 * ry * b
	var out := PackedVector2Array()
	for q in [Vector2(-rx, -ry), Vector2(-rx + wx, -ry), Vector2(-rx + wx, ry - wy), Vector2(rx, ry - wy), Vector2(rx, ry), Vector2(-rx, ry)]:
		out.append(c + (q as Vector2).rotated(deg_to_rad(angle)))
	return out


## Contour d'une forme (clé « forme » d'une pièce), sommets arrondis au mm.
static func outline(f: Dictionary) -> PackedVector2Array:
	var c := MapGeom.v2(f.get("centre", [0, 0]))
	var rx := float(f.get("rx", 1.0))
	var ry := float(f.get("ry", rx))
	var a := float(f.get("angle", 0.0))
	var p := PackedVector2Array()
	match String(f.get("type", "")):
		"cercle":
			p = regular(c, rx, rx, int(f.get("points", DEFAULT_POINTS)), a)
		"ellipse":
			p = regular(c, rx, ry, int(f.get("points", DEFAULT_POINTS)), a)
		"triangle":
			p = triangle(c, rx, ry, a)
		"l":
			p = l_shape(c, rx, ry, float(f.get("bras", 0.5)), a)
	for i in p.size():
		p[i] = Vector2(snappedf(p[i].x, 0.001), snappedf(p[i].y, 0.001))
	return p


## Forme tracée au glisser de `a` à `b` avec l'outil `kind` (cercle : du centre
## au rayon ; ellipse, triangle, L : d'un coin à l'autre) et `n` points.
static func from_drag(kind: String, a: Vector2, b: Vector2, n: int) -> Dictionary:
	match kind:
		"cercle":
			return {"type": "cercle", "centre": MapGeom.arr(a), "rx": snappedf(a.distance_to(b), 0.001), "points": clampi(n, MIN_POINTS, MAX_POINTS), "angle": 0}
		"ellipse":
			var e := (b - a).abs() * 0.5
			return {"type": "ellipse", "centre": MapGeom.arr((a + b) * 0.5), "rx": snappedf(e.x, 0.001), "ry": snappedf(e.y, 0.001),
				"points": clampi(n, MIN_POINTS, MAX_POINTS), "angle": 0}
		"triangle":
			var e := (b - a).abs() * 0.5
			# Glissé vers le haut : la pointe au sud.
			return {"type": "triangle", "centre": MapGeom.arr((a + b) * 0.5), "rx": snappedf(e.x, 0.001), "ry": snappedf(e.y, 0.001),
				"angle": 180 if b.y < a.y else 0}
		"l":
			var e := (b - a).abs() * 0.5
			return {"type": "l", "centre": MapGeom.arr((a + b) * 0.5), "rx": snappedf(e.x, 0.001), "ry": snappedf(e.y, 0.001), "bras": 0.5, "angle": 0}
	return {}


## La forme a-t-elle un nombre de points réglable ?
static func has_points(f: Dictionary) -> bool:
	return String(f.get("type", "")) in ["cercle", "ellipse"]


## Nom affiché d'une forme.
static func name_of(f: Dictionary) -> String:
	match String(f.get("type", "")):
		"cercle":
			return Lang.t("Cercle / polygone régulier", "Circle / regular polygon")
		"ellipse":
			return Lang.t("Ellipse", "Ellipse")
		"triangle":
			return Lang.t("Triangle", "Triangle")
		"l":
			return Lang.t("Pièce en L", "L-shaped room")
	return Lang.t("Polygone", "Polygon")


## Forme valide (types et bornes) ? Sert à la lecture d'un fichier écrit à la
## main (EditorMap._normalize) ; le contrôle des cartes reçues est fait par
## CustomMapGuard.
static func valid(f: Variant) -> bool:
	if not f is Dictionary or not String(f.get("type", "")) in TYPES:
		return false
	for k in ["rx", "ry", "angle", "bras", "points"]:
		if f.has(k) and not ((f[k] is float or f[k] is int) and is_finite(float(f[k]))):
			return false
	var c = f.get("centre")
	if not (c is Array and c.size() == 2 and (c[0] is float or c[0] is int) and (c[1] is float or c[1] is int)
			and is_finite(float(c[0])) and is_finite(float(c[1]))):
		return false
	return float(f.get("rx", 0.0)) > 0.0 and float(f.get("ry", f.get("rx", 0.0))) > 0.0


## Forme déplacée de `delta`.
static func shifted(f: Dictionary, delta: Vector2) -> Dictionary:
	var g := f.duplicate(true)
	g["centre"] = MapGeom.arr(MapGeom.v2(f.centre) + delta)
	return g


## Forme tournée de `deg` degrés autour de `c`.
static func rotated(f: Dictionary, c: Vector2, deg: float) -> Dictionary:
	var g := f.duplicate(true)
	g["centre"] = MapGeom.arr(MapGeom.rotate_about(MapGeom.v2(f.centre), c, deg))
	g["angle"] = MapGeom.norm_deg(float(f.get("angle", 0.0)) + deg)
	return g


# ------------------------------------------------------------------ mur courbe

## Points d'un arc (segments + 1 points), de la direction `debut` (degrés,
## sens horaire depuis le nord) sur `ouverture` degrés dans le sens horaire.
static func arc_points(c: Vector2, radius: float, debut: float, ouverture: float, segments: int) -> PackedVector2Array:
	var n := clampi(segments, MIN_SEGMENTS, MAX_SEGMENTS)
	var out := PackedVector2Array()
	for i in n + 1:
		var q := c + MapGeom.deg_dir(debut + ouverture * i / n) * radius
		out.append(Vector2(snappedf(q.x, 0.001), snappedf(q.y, 0.001)))
	return out


## Points d'un mur courbe posé (objets.json).
static func wall_arc(o: Dictionary) -> PackedVector2Array:
	return arc_points(MapGeom.v2(o.get("centre", [0, 0])), float(o.get("rayon", 1.0)), float(o.get("debut", 0.0)),
		float(o.get("ouverture", DEFAULT_OPENING)), int(o.get("segments", DEFAULT_SEGMENTS)))


## Segments d'un mur courbe : [[a, b], ...].
static func arc_segments(o: Dictionary) -> Array:
	var p := wall_arc(o)
	var out := []
	for i in p.size() - 1:
		out.append([p[i], p[i + 1]])
	return out


## Mur courbe tracé au glisser du centre `a` au premier bout `b`.
static func arc_from_drag(make: Dictionary, a: Vector2, b: Vector2, segments: int, ouverture := DEFAULT_OPENING) -> Dictionary:
	var o := make.duplicate(true)
	o["centre"] = MapGeom.arr(a)
	o["rayon"] = snappedf(a.distance_to(b), 0.001)
	o["debut"] = snappedf(MapGeom.dir_deg((b - a).normalized()) if a.distance_to(b) > 0.001 else 0.0, 0.01)
	o["ouverture"] = ouverture
	o["segments"] = clampi(segments, MIN_SEGMENTS, MAX_SEGMENTS)
	return o
