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

## Règles (px à 100 % d'interface, maquette : 18 px).
const RULER := 18.0
const MIN_ZOOM := 4.0
const MAX_ZOOM := 120.0
const COL_GRID := Color(1, 1, 1, 0.045)
const COL_GRID5 := Color(1, 1, 1, 0.11)
const COL_RULER_BG := Color(18 / 255.0, 18 / 255.0, 20 / 255.0, 0.95)
const COL_RULER_CORNER := Color("0f0f11")
const COL_TICK := Color("77736a")
const COL_RULER_TXT := Color("a49d8c")
const COL_SEL := Color(1.0, 0.85, 0.3)
const COL_GOLD := Color("F2C759")
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
## Déplacement de la vue (clic milieu, Espace + glisser).
var _pan := false
@warning_ignore("unused_private_class_variable")
var _pan_from := Vector2.ZERO
var _space := false
## ViewCube de la vue (§ 4 ; null hors d'une fenêtre de la disposition).
var cube: MapViewCube
## Support des règles, du trièdre et du curseur (null : la vue ; une couche
## du dessus pour les élévations).
var _over_target: CanvasItem = null


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


## uv_of et depth_of d'un plan en produits scalaires (boucles chaudes : un
## appel par sommet sinon) : [u, v, profondeur], chacun `axe.dot(p)`.
static func plane_axes(pl: String) -> Array:
	match pl:
		"dessous":
			return [Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)]
		"avant":
			return [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)]
		"arriere":
			return [Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)]
		"droite":
			return [Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]
		"gauche":
			return [Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]
	return [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]


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


## Nom d'un plan en capitales, dans la langue du jeu (ViewCube, en-têtes).
static func plane_name(pl: String) -> String:
	match pl:
		"dessous":
			return Lang.t("DESSOUS", "BOTTOM")
		"avant":
			return Lang.t("AVANT", "FRONT")
		"arriere":
			return Lang.t("ARRIÈRE", "BACK")
		"gauche":
			return Lang.t("GAUCHE", "LEFT")
		"droite":
			return Lang.t("DROITE", "RIGHT")
		"3d":
			return "3D"
	return Lang.t("DESSUS", "TOP")


## Sens du regard d'une élévation (« regard vers le nord »).
static func look_text(pl: String) -> String:
	match pl:
		"avant":
			return Lang.t("regard vers le nord", "looking north")
		"arriere":
			return Lang.t("regard vers le sud", "looking south")
		"droite":
			return Lang.t("regard vers l'ouest", "looking west")
		"gauche":
			return Lang.t("regard vers l'est", "looking east")
		"dessous":
			return Lang.t("vu de dessous", "seen from below")
	return ""


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


## Où dessiner les règles, le trièdre et le curseur.
func _ci() -> CanvasItem:
	return _over_target if _over_target != null else self


## Taille de police (px) d'une taille de la maquette (décimales admises) à
## la taille de l'interface.
static func _fs(v: float) -> int:
	return maxi(EditorUi.MIN_FONT, roundi(v * EditorUi.factor()))


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


## Met en place le ViewCube de la vue (en haut à droite) ; ses clics vont à la
## disposition (MapViewLayout.cube_action).
func setup_cube() -> void:
	# La 3D a son cube isométrique sur l'aperçu (MapPreviewPanel).
	if cube != null or offscreen or plane == "3d":
		return
	cube = MapViewCube.new()
	cube.name = "ViewCube"
	add_child(cube)
	cube.target_clicked.connect(_on_cube)
	resized.connect(place_cube)
	place_cube()


func _on_cube(id: String) -> void:
	if ed != null and ed.views != null:
		ed.views.cube_action(self, id)


## Le ViewCube suit le plan de la vue et son coin haut droit (maquette : net à
## 82 px du bord droit, 24 px du haut en vue Dessus, 14 px sinon).
func place_cube() -> void:
	if cube == null:
		return
	cube.plane = plane
	cube.size = cube.wanted_size()
	var f := EditorUi.factor()
	cube.position = Vector2(size.x - 82.0 * f - 20.0 * f, (24.0 if plane == "dessus" else 14.0) * f - 10.0 * f)
	cube.queue_redraw()


## Cadre la carte dans la vue (Origine).
func frame_all() -> void:
	pass


# ------------------------------------------------------------------ en-tête (MapViewPane)

## Texte de l'en-tête après le nom du plan (étage, sens du regard, étages montrés).
func header_sub() -> String:
	return ""


## Puces de l'en-tête, à droite : [{id, text, hl}] (zoom en dernier).
func header_chips() -> Array:
	return [{"id": "zoom", "text": "%d %%" % zoom_percent()}]


## Menu d'une puce : [{id, text} | {id, text, radio} | {sep}].
func header_menu(id: String) -> Array:
	if id == "zoom":
		return [{"id": 0, "text": Lang.t("Recadrer sur la carte (Origine)", "Frame the map (Home)")},
			{"id": 1, "text": Lang.t("Zoom à 100 %", "Zoom to 100%")}]
	return []


func header_menu_pressed(id: String, i: int) -> void:
	if id == "zoom":
		if i == 0:
			frame_all()
		else:
			_zoom_at(size * 0.5, 15.0 / zoom)


## Espace maintenu (déplacement de la vue) ; appelé par l'éditeur.
func set_space(on: bool) -> void:
	_space = on
	if not on:
		_pan = false


## Zoom en pourcentage (100 % : 15 px par mètre, comme la maquette).
func zoom_percent() -> int:
	return roundi(zoom / 15.0 * 100.0)


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


## Pas des graduations (m) et des chiffres des règles au zoom courant.
func ruler_steps() -> Vector2:
	var tick := 1.0 if zoom >= 6.0 else 5.0
	var lab := 2.0 if zoom >= 20.0 else (5.0 if zoom >= 9.0 else (10.0 if zoom >= 4.5 else 20.0))
	return Vector2(tick, lab)


## Nombre écrit à la française (virgule, vrai signe moins) ou à l'anglaise.
static func num(v: float, decimals := 0) -> String:
	var s := ("%." + str(decimals) + "f") % v
	if s.begins_with("-") and absf(v) < pow(10.0, -decimals) * 0.5:
		s = s.substr(1)
	if not Lang.is_en():
		s = s.replace(".", ",")
	return s.replace("-", "−")


static var _bold: Dictionary = {}


## Police du corps en gras (titres de vue, prix, étiquettes de niveau).
static func bold_font(weight := 700) -> Font:
	if not _bold.has(weight):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
		f.font_weight = weight
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_bold[weight] = f
	return _bold[weight]


## Règles (maquette, § 8) : fond sombre, graduations à chaque pas, chiffres
## (vraies coordonnées de l'axe montré, même de droite à gauche), lettres des
## axes en couleur dans le coin.
func _draw_rulers(font: Font) -> void:
	var ci := _ci()
	var r := _ruler()
	ci.draw_rect(Rect2(0, 0, size.x, r), COL_RULER_BG)
	ci.draw_rect(Rect2(0, 0, r, size.y), COL_RULER_BG)
	var st := ruler_steps()
	var hs := float(h_axis(plane)[1])
	var vs := -float(v_axis(plane)[1])
	var fs := EditorUi.fs(10)
	var m0 := to_m(Vector2(r, r))
	var m1 := to_m(size)
	var x := ceilf(m0.x / st.x) * st.x
	while x <= m1.x:
		var px := to_px(Vector2(x, 0)).x
		var big := absf(fposmod(x, st.y)) < 0.001 or absf(fposmod(x, st.y) - st.y) < 0.001
		ci.draw_line(Vector2(px, _u(8) if big else _u(13)), Vector2(px, r), COL_TICK, 1.0)
		if big:
			ci.draw_string(font, Vector2(px + 2, _u(10)), num(x * hs), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_RULER_TXT)
		x += st.x
	var y := ceilf(m0.y / st.x) * st.x
	while y <= m1.y:
		var py := to_px(Vector2(0, y)).y
		var big := absf(fposmod(y, st.y)) < 0.001 or absf(fposmod(y, st.y) - st.y) < 0.001
		ci.draw_line(Vector2(_u(8) if big else _u(13), py), Vector2(r, py), COL_TICK, 1.0)
		if big:
			ci.draw_string(font, Vector2(2, py - 2), num(y * vs), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_RULER_TXT)
		y += st.x
	ci.draw_rect(Rect2(0, 0, r, r), COL_RULER_CORNER)
	var bf := bold_font()
	var ha := h_axis(plane)
	var va := v_axis(plane)
	ci.draw_string(bf, Vector2(_u(2), _u(9)), String(ha[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(9), axis_color(String(ha[0])))
	ci.draw_string(bf, Vector2(_u(9), _u(16)), String(va[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(9), axis_color(String(va[0])))


## Repère du curseur sur les règles : petits triangles or.
func _draw_ruler_cursor(m: Vector2) -> void:
	var ci := _ci()
	var p := to_px(m)
	var r := _ruler()
	if p.x > r and p.x < size.x:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(p.x - _u(4), 0), Vector2(p.x + _u(4), 0), Vector2(p.x, _u(7))]), COL_SEL)
	if p.y > r and p.y < size.y:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(0, p.y - _u(4)), Vector2(0, p.y + _u(4)), Vector2(_u(7), p.y)]), COL_SEL)


## Trièdre (§ 8) en bas à gauche : les deux axes de l'écran en flèches de
## couleur, un point pour l'axe de la profondeur.
func _draw_triad(font: Font) -> void:
	var ci := _ci()
	var o := Vector2(_ruler() + _u(14), size.y - _u(14))
	var ha := h_axis(plane)
	var va := v_axis(plane)
	var da := depth_axis(plane)
	var hl := ("−" if int(ha[1]) < 0 else "") + String(ha[0])
	_triad_arrow(font, o, Vector2(1, 0), axis_color(String(ha[0])), hl)
	# Axe vertical : vers le haut s'il monte (Z), vers le bas sinon (Y au sud).
	var up := int(va[1]) > 0
	_triad_arrow(font, o, Vector2(0, -1) if up else Vector2(0, 1), axis_color(String(va[0])), String(va[0]))
	var dc := axis_color(String(da[0]))
	ci.draw_arc(o, _u(3.5), 0, TAU, 16, dc, 1.5)
	ci.draw_circle(o, _u(1.0), dc)


func _triad_arrow(_font: Font, o: Vector2, d: Vector2, col: Color, lbl: String) -> void:
	var ci := _ci()
	var e := o + d * _u(22)
	ci.draw_line(o, e, col, 2.0)
	var n := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([e + d * _u(5), e - n * _u(3.5), e + n * _u(3.5)]), col)
	var at := e + d * _u(9) + Vector2(-_u(3) + (_u(7) if d.y != 0.0 else 0.0), _u(4) + (-_u(6) if d.x != 0.0 else 0.0))
	ci.draw_string(bold_font(), at, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), col)


# ------------------------------------------------------------------ dessin

## Hachures à 45° (`dir` 1 : montantes, -1 : descendantes) dans un rectangle (px),
## traits espacés de `step` px, sur `ci` (la vue si null), coupées à `clip`
## (la vue si vide).
func _hatch(r: Rect2, step: float, col: Color, width := 1.0, dir := 1, ci: CanvasItem = null, clip := Rect2()) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var t: CanvasItem = ci if ci != null else self
	var view := r.intersection(clip if clip.size.x > 0.0 else Rect2(Vector2.ZERO, size))
	if view.size.x <= 0.0 or view.size.y <= 0.0:
		return
	# Traits à 45° coupés au rectangle (calcul direct, sans Geometry2D).
	var s := step * 1.41421356
	var h := view.size.y
	var c := view.position.x - h - fposmod(view.position.x - h, s)
	# Tous les traits en un seul appel (une vue en compte des centaines).
	var pts := PackedVector2Array()
	while c < view.end.x:
		var t0 := maxf(0.0, view.position.x - c)
		var t1 := minf(h, view.end.x - c)
		if t1 > t0:
			if dir > 0:
				pts.append(Vector2(c + t0, view.end.y - t0))
				pts.append(Vector2(c + t1, view.end.y - t1))
			else:
				pts.append(Vector2(c + t0, view.position.y + t0))
				pts.append(Vector2(c + t1, view.position.y + t1))
		c += s
	if not pts.is_empty():
		t.draw_multiline(pts, col, width)
