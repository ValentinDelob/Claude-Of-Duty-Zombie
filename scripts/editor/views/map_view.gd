class_name MapView
extends Control
## Vue orthographique générique de l'éditeur de cartes (docs/EDITOR_VIEWS.md,
## § 3) : un PLAN (Dessus, Dessous, Avant, Arrière, Gauche, Droite), son zoom
## et son déplacement, la transformation plan <-> écran, la grille, les
## règles (vraies coordonnées de l'axe montré, même de droite à gauche) et le
## trièdre. La vue Dessus (MapCanvas) et les élévations (MapElevation) en
## héritent.
##
## Repère de la carte : x vers l'est, y vers le sud, z vers le haut (m,
## altitude absolue). Coordonnées de l'écran (« uv », m) : u vers la droite,
## v vers le BAS. to_px / to_m passent de uv aux pixels ; project /
## unproject passent du repère de la carte aux pixels (profondeur : plus
## grande = plus près de la caméra).

const RULER := 20.0
const MIN_ZOOM := 4.0
const MAX_ZOOM := 120.0
const COL_GRID := Color(1, 1, 1, 0.045)
const COL_GRID5 := Color(1, 1, 1, 0.11)
const COL_RULER_BG := Color(0.07, 0.07, 0.08, 0.95)
## Plans, dans l'ordre du menu du ViewCube.
const PLANES := ["dessus", "dessous", "avant", "arriere", "gauche", "droite"]
const ELEVATIONS := ["avant", "arriere", "gauche", "droite"]
## Axes colorés (§ 8) : X rouge (est), Y vert (sud), Z bleu (haut).
const COL_X := Color("E5484D")
const COL_Y := Color("46A758")
const COL_Z := Color("3E7BFA")

var ed: MapEditor
## Plan montré (PLANES).
var plane := "dessus"
var zoom := 18.0
## Pixel de l'origine des coordonnées de l'écran (uv = 0).
var origin := Vector2(60, 50)
## Position de la souris (uv, m).
var mouse_m := Vector2.ZERO
## Vue dessinée hors écran (captures pour Claude) : ni outil, ni sélection,
## ni curseurs.
var offscreen := false


# ------------------------------------------------------------------ plans

## Point de la carte (x, y, z) -> coordonnées de l'écran (uv, m) d'un plan.
static func uv_of(pl: String, p: Vector3) -> Vector2:
	match pl:
		"dessous":
			return Vector2(-p.x, p.y)
		"avant":
			return Vector2(p.x, -p.z)
		"arriere":
			return Vector2(-p.x, -p.z)
		"droite":
			return Vector2(-p.y, -p.z)
		"gauche":
			return Vector2(p.y, -p.z)
	return Vector2(p.x, p.y)


## Profondeur d'un point dans un plan : plus grande = plus près de la caméra
## (Dessus : le haut ; Avant : le sud ; Droite : l'est...).
static func depth_of(pl: String, p: Vector3) -> float:
	match pl:
		"dessous":
			return -p.z
		"avant":
			return p.y
		"arriere":
			return -p.y
		"droite":
			return p.x
		"gauche":
			return -p.x
	return p.z


## Inverse de uv_of / depth_of : point de la carte d'un point de l'écran (uv,
## m) à la profondeur `depth`.
static func point_of(pl: String, uv: Vector2, depth: float) -> Vector3:
	match pl:
		"dessous":
			return Vector3(-uv.x, uv.y, -depth)
		"avant":
			return Vector3(uv.x, depth, -uv.y)
		"arriere":
			return Vector3(-uv.x, -depth, -uv.y)
		"droite":
			return Vector3(depth, -uv.x, -uv.y)
		"gauche":
			return Vector3(-depth, uv.x, -uv.y)
	return Vector3(uv.x, uv.y, depth)


## Élévation (vue de côté : axe vertical de l'écran = Z) ?
static func is_elevation(pl: String) -> bool:
	return pl in ELEVATIONS


## Axe horizontal de l'écran : [lettre, signe] (signe : sens de la vraie
## coordonnée quand on va vers la droite ; Droite : Y décroissant).
static func h_axis(pl: String) -> Array:
	match pl:
		"dessous", "arriere":
			return ["X", -1]
		"droite":
			return ["Y", -1]
		"gauche":
			return ["Y", 1]
	return ["X", 1]


## Axe vertical de l'écran : [lettre, signe] (signe : sens de la vraie
## coordonnée quand on MONTE à l'écran ; Dessus : le nord, Y décroissant).
static func v_axis(pl: String) -> Array:
	if is_elevation(pl):
		return ["Z", 1]
	return ["Y", -1]


## Axe de la profondeur (vers la caméra) : [lettre, signe].
static func depth_axis(pl: String) -> Array:
	match pl:
		"dessous":
			return ["Z", -1]
		"avant":
			return ["Y", 1]
		"arriere":
			return ["Y", -1]
		"droite":
			return ["X", 1]
		"gauche":
			return ["X", -1]
	return ["Z", 1]


## Couleur d'un axe (« X », « Y », « Z »).
static func axis_color(letter: String) -> Color:
	match letter:
		"Y":
			return COL_Y
		"Z":
			return COL_Z
	return COL_X


# ------------------------------------------------------------------ repères

## Longueurs d'interface de la vue (règles, poignées, étiquettes, cotes) à la
## taille de l'interface de l'éditeur (EditorUi) ; le zoom du plan n'en dépend pas.
func _u(v: float) -> float:
	return EditorUi.px(v)


func _ruler() -> float:
	return EditorUi.px(RULER)


func to_m(px: Vector2) -> Vector2:
	return (px - origin) / zoom


func to_px(m: Vector2) -> Vector2:
	return origin + m * zoom


## Point de la carte -> pixel de la vue.
func project(p: Vector3) -> Vector2:
	return to_px(uv_of(plane, p))


## Pixel de la vue -> point de la carte à la profondeur `depth`.
func unproject(px: Vector2, depth := 0.0) -> Vector3:
	return point_of(plane, to_m(px), depth)


## Centre la vue sur un point (uv, m).
func center_on(m: Vector2) -> void:
	origin = size * 0.5 - m * zoom
	queue_redraw()


func _zoom_at(px: Vector2, f: float) -> void:
	var m := to_m(px)
	zoom = clampf(zoom * f, MIN_ZOOM, MAX_ZOOM)
	origin = px - m * zoom
	queue_redraw()


func zoom_by(f: float) -> void:
	_zoom_at(size * 0.5, f)


# ------------------------------------------------------------------ grille et règles

## Mode de la grille fine affichée ("" : aucune) et son pas (MapCanvas, élévations).
func _fine_grid() -> float:
	return 0.0


func _draw_grid() -> void:
	var m0 := to_m(Vector2.ZERO)
	var m1 := to_m(size)
	var fine := 1.0 if zoom >= 9.0 else 5.0
	var x := floorf(m0.x / fine) * fine
	while x <= m1.x:
		var major := is_equal_approx(fmod(absf(x), 5.0), 0.0)
		draw_line(Vector2(to_px(Vector2(x, 0)).x, 0), Vector2(to_px(Vector2(x, 0)).x, size.y), COL_GRID5 if major else COL_GRID, 1.0)
		x += fine
	var y := floorf(m0.y / fine) * fine
	while y <= m1.y:
		var major := is_equal_approx(fmod(absf(y), 5.0), 0.0)
		draw_line(Vector2(0, to_px(Vector2(0, y)).y), Vector2(size.x, to_px(Vector2(0, y)).y), COL_GRID5 if major else COL_GRID, 1.0)
		y += fine
	# Grille fine : traits légers au pas choisi, si lisibles.
	var fine_step := _fine_grid()
	if fine_step > 0.0 and fine_step * zoom >= 8.0 and fine_step < 0.99:
		var fx := floorf(m0.x / fine_step) * fine_step
		while fx <= m1.x:
			if absf(fx - roundf(fx)) > 0.001:
				draw_line(Vector2(to_px(Vector2(fx, 0)).x, 0), Vector2(to_px(Vector2(fx, 0)).x, size.y), Color(1, 1, 1, 0.022), 1.0)
			fx += fine_step
		var fy := floorf(m0.y / fine_step) * fine_step
		while fy <= m1.y:
			if absf(fy - roundf(fy)) > 0.001:
				draw_line(Vector2(0, to_px(Vector2(0, fy)).y), Vector2(size.x, to_px(Vector2(0, fy)).y), Color(1, 1, 1, 0.022), 1.0)
			fy += fine_step


## Pas des chiffres des règles (m) au zoom courant.
func ruler_every() -> float:
	var every := 1.0
	for e in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0]:
		every = e
		if e * zoom >= _u(34.0):
			break
	return every


## Règles : graduations et vraies coordonnées des deux axes de l'écran.
func _draw_rulers(font: Font) -> void:
	draw_rect(Rect2(0, 0, size.x, _ruler()), COL_RULER_BG)
	draw_rect(Rect2(0, 0, _ruler(), size.y), COL_RULER_BG)
	var every := ruler_every()
	var hs := float(h_axis(plane)[1])
	var vs := -float(v_axis(plane)[1])
	var m0 := to_m(Vector2.ZERO)
	var m1 := to_m(size)
	var x := floorf(m0.x / every) * every
	while x <= m1.x:
		var px := to_px(Vector2(x, 0)).x
		if px > _ruler():
			draw_line(Vector2(px, _ruler() - _u(6)), Vector2(px, _ruler()), Color(1, 1, 1, 0.5), 1.0)
			draw_string(font, Vector2(px + 2, _u(13)), "%d" % roundi(x * hs), HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), Color(1, 1, 1, 0.65))
		x += every
	var y := floorf(m0.y / every) * every
	while y <= m1.y:
		var py := to_px(Vector2(0, y)).y
		if py > _ruler():
			draw_line(Vector2(_ruler() - _u(6), py), Vector2(_ruler(), py), Color(1, 1, 1, 0.5), 1.0)
			draw_string(font, Vector2(1, py - 2), "%d" % roundi(y * vs), HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), Color(1, 1, 1, 0.65))
		y += every
	draw_rect(Rect2(0, 0, _ruler(), _ruler()), Color(0.07, 0.07, 0.08))
	draw_string(font, Vector2(_u(3), _u(13)), "m", HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), Color(1, 1, 1, 0.5))
