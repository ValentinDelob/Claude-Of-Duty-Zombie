class_name MapElevation
extends MapView
## Élévation de l'éditeur de cartes (docs/EDITOR_VIEWS.md, § 3.2) : vue de
## côté (Avant, Arrière, Gauche, Droite) ou de dessous. Tous les étages
## empilés, chaque élément projeté à sa vraie hauteur (MapElevationItems),
## dessinés du plus lointain au plus proche, les lointains estompés ; coupe
## facultative (tranche de profondeur) ; lignes et étiquettes de niveau ;
## choix au clic et survol (sélection commune à toutes les vues).
##
## Performances (§ 9, R2) : les boîtes de la carte sont calculées une fois
## par version de la carte (MapEditor.doc_version), projetées et triées une
## fois par plan ; les boîtes de même rectangle à l'écran ne sont dessinées
## qu'une fois (la plus proche). Trois couches : la grille (la vue), le
## CONTENU (couche `_layer`, redessinée seulement quand la carte, le zoom,
## la coupe ou l'étage changent ; un déplacement de la vue la décale sans la
## redessiner) et le DESSUS (`_over` : sélection, survol, règles, étiquettes
## de niveau, curseur ; redessiné au mouvement de la souris).

const COL_BG := Color("1A1B1D")
const COL_TERRAIN := Color("161719")
const COL_WALL := Color(158 / 255.0, 158 / 255.0, 168 / 255.0)
const COL_HOVER := Color(0.35, 0.9, 1.0)
const COL_LEVEL := Color(219 / 255.0, 209 / 255.0, 184 / 255.0)
const COL_GROUND := Color(230 / 255.0, 128 / 255.0, 77 / 255.0)
const COL_STAIRS := Color(140 / 255.0, 90 / 255.0, 165 / 255.0)
const COL_CLIP := Color(0.63, 0.42, 1.0)
const COL_SLAB := Color(200 / 255.0, 200 / 255.0, 210 / 255.0)
## Étages montrés (en-tête « étages : ») : tous, jusqu'à l'étage courant, l'étage courant.
enum Floors { ALL, UP_TO, ONLY }
## Estompage hors de la coupe (§ 3.2).
const OUT_OF_CUT := 0.15

var floors_mode := Floors.ALL
## Coupe : tranche [p0, p1] (m, vraie coordonnée de l'axe de la profondeur :
## Y en Avant / Arrière, X en Gauche / Droite) ; vide : aucune.
var coupe: Array = []
## Origine de la coupe : « aucune », « selection » (autour de la sélection,
## touche K), « perso » (traits glissés dans la vue Dessus).
var coupe_mode := "aucune"
## Libellé de la coupe (nom de l'élément autour duquel elle est prise).
var coupe_label := ""
## Élément survolé dans CETTE vue.
var hover := ""
## Durée du dernier dessin du contenu (µs, mesures et tests).
var last_draw_us := 0
## Dessins du contenu (tests : aucun au simple mouvement de la souris).
var content_draws := 0

var _proj_key := ""
## Éléments projetés, du plus lointain au plus proche : {it, k (type de
## boîte), f (étage), u0, u1, v0, v1 (m, écran), near, lo, hi (étendue sur
## l'axe de la profondeur), area, ab (opacité selon la profondeur), dup
## (même rectangle qu'une boîte plus proche : pas dessinée), poly (Dessous)}.
var _proj: Array = []
## Listes de dessin tirées de `_proj` : pièces, autres éléments (sans les
## doublons à l'écran), du plus lointain au plus proche.
var _rooms: Array = []
var _others: Array = []
var _dmin := 0.0
var _dmax := 1.0
## Pièces dont le nom est caché par une pièce plus proche qui les couvre.
var _hidden_names: Dictionary = {}
var _state := ""
var _layer: Control
var _over: Control
## Clé du dessin du contenu et origine (px) à laquelle il a été fait.
var _layer_key := ""
var _layer_origin := Vector2.ZERO


func _ready() -> void:
	clip_contents = true
	_layer = Control.new()
	_layer.name = "Content"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.draw.connect(_draw_content)
	add_child(_layer)
	_over = Control.new()
	_over.name = "Overlay"
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.draw.connect(_draw_overlay)
	add_child(_over)
	if offscreen:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		if hover != "":
			hover = ""
			ed.map_hovered(""))


func _process(_delta: float) -> void:
	if ed == null:
		return
	# Redessin seulement si ce que la vue montre a changé.
	var st := "%d|%s|%s|%d|%d" % [ed.doc_version, ed.selected, ed.hover_id, ed.floor_k, ed.views_stamp]
	if st != _state:
		_state = st
		queue_redraw()


## Redessine la vue : la grille ici ; le contenu seulement s'il a changé
## (sinon simplement décalé) ; le dessus toujours (léger).
func queue_redraw_all() -> void:
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW and _layer != null:
		_sync_layers()


func _sync_layers() -> void:
	var key := "%s|%d|%s|%.4f|%s|%d|%s|%d|%s" % [_proj_key_now(), floors_mode, str(coupe), zoom, str(size), ed.floor_k if ed != null else 0, plane, ed.views_stamp if ed != null else 0, str(Lang.is_en())]
	var shift := origin - _layer_origin
	# Le contenu est dessiné avec une marge d'une vue autour : un déplacement
	# plus petit que la marge le décale seulement.
	if key != _layer_key or absf(shift.x) > size.x * 0.9 or absf(shift.y) > size.y * 0.9:
		_layer_key = key
		_layer_origin = origin
		_layer.position = Vector2.ZERO
		_layer.size = size
		_layer.queue_redraw()
	else:
		_layer.position = shift
	_over.queue_redraw()


func _proj_key_now() -> String:
	return "%d|%s" % [ed.doc_version if ed != null else -1, plane]


# ------------------------------------------------------------------ cache

## Boîtes de la carte (une fois par version de la carte, partagées par les vues).
func items() -> Array:
	return ed.elevation_items() if ed != null else []


## Projection des boîtes sur le plan, triées du plus lointain au plus proche
## (une fois par version de la carte et par plan).
func projected() -> Array:
	var key := _proj_key_now()
	if key == _proj_key:
		return _proj
	_proj_key = key
	_proj = []
	_hidden_names = {}
	var dmin := INF
	var dmax := -INF
	var depth_y := String(depth_axis(plane)[0]) == "Y"
	var below := plane == "dessous"
	for it in items():
		var poly: PackedVector2Array = it.poly
		if poly.is_empty():
			continue
		var u0 := INF
		var u1 := -INF
		var near := -INF
		var lo := INF
		var hi := -INF
		var z0 := float(it.z0)
		var z1 := float(it.z1)
		var pts := PackedVector2Array()
		for q in poly:
			var p3 := Vector3(q.x, q.y, z0)
			var uv := uv_of(plane, p3)
			u0 = minf(u0, uv.x)
			u1 = maxf(u1, uv.x)
			near = maxf(near, depth_of(plane, p3))
			var real := q.y if depth_y else q.x
			lo = minf(lo, real)
			hi = maxf(hi, real)
			if below:
				pts.append(uv)
		var e := {"it": it, "k": String(it.kind), "f": int(it.floor), "u0": u0, "u1": u1, "v0": -z1, "v1": -z0, "near": near, "lo": lo, "hi": hi}
		if below:
			# Vu de dessous : le contour en miroir, le bas le plus près.
			var bb := MapGeom.bbox(pts)
			e.merge({"u0": bb.position.x, "u1": bb.end.x, "v0": bb.position.y, "v1": bb.end.y, "near": -z0, "lo": z0, "hi": z1, "poly": pts}, true)
		e["area"] = (float(e.u1) - float(e.u0)) * (float(e.v1) - float(e.v0))
		dmin = minf(dmin, float(e.near))
		dmax = maxf(dmax, float(e.near))
		_proj.append(e)
	_proj.sort_custom(func(a, b): return float(a.near) < float(b.near))
	_dmin = dmin if dmin != INF else 0.0
	_dmax = dmax if dmax != -INF else 1.0
	var span := maxf(_dmax - _dmin, 0.001)
	# Boîtes de même rectangle à l'écran : seule la plus proche est dessinée.
	var seen := {}
	for i in range(_proj.size() - 1, -1, -1):
		var e: Dictionary = _proj[i]
		e["ab"] = 0.38 + 0.62 * (float(e.near) - _dmin) / span
		var dk := "%s|%d|%d|%d|%d|%d|%s" % [e.k, e.f, roundi(float(e.u0) * 100.0), roundi(float(e.u1) * 100.0), roundi(float(e.v0) * 100.0), roundi(float(e.v1) * 100.0), String(e.it.e.get("type", ""))]
		e["dup"] = e.k != "room" and not below and seen.has(dk)
		seen[dk] = true
	_rooms = _proj.filter(func(x): return x.k == "room")
	_others = _proj.filter(func(x): return x.k != "room" and not bool(x.dup))
	# Nom d'une pièce caché par une pièce plus proche qui la couvre entièrement.
	for a in _rooms:
		for b in _rooms:
			if a == b or float(b.near) <= float(a.near):
				continue
			if float(b.u0) <= float(a.u0) + 0.01 and float(b.u1) >= float(a.u1) - 0.01 and float(b.v0) <= float(a.v0) + 0.01 and float(b.v1) >= float(a.v1) - 0.01:
				_hidden_names[String(a.it.id)] = true
				break
	return _proj


## Étage montré (réglage « étages : ») ?
func floor_shown(k: int) -> bool:
	match floors_mode:
		Floors.UP_TO:
			return k <= ed.floor_k
		Floors.ONLY:
			return k == ed.floor_k
	return true


## Dans la coupe (ou pas de coupe) ?
func in_cut(e: Dictionary) -> bool:
	if coupe.size() != 2 or plane == "dessous":
		return true
	return not (float(e.hi) <= float(coupe[0]) + 0.001 or float(e.lo) >= float(coupe[1]) - 0.001)


## Opacité d'un élément projeté : de 100 % (le plus proche) à 38 % (le plus
## lointain), un peu moins sur un autre étage, 15 % hors de la coupe.
func alpha_of(e: Dictionary) -> float:
	if not in_cut(e):
		return OUT_OF_CUT
	var a := float(e.get("ab", 1.0))
	if int(e.f) != ed.floor_k:
		a *= 0.8
	return clampf(a, 0.0, 1.0)


## Rectangle (px) d'un élément projeté.
func rect_px(e: Dictionary) -> Rect2:
	var a := to_px(Vector2(float(e.u0), float(e.v0)))
	var b := to_px(Vector2(float(e.u1), float(e.v1)))
	return Rect2(a, Vector2.ZERO).expand(b)


# ------------------------------------------------------------------ cadrage

## Cadre toute la carte (largeur sur l'axe de l'écran, hauteur de tous les étages).
func frame_all() -> void:
	var u0 := INF
	var u1 := -INF
	var v0 := 0.0
	var v1 := 0.0
	for e in projected():
		if e.k != "room":
			continue
		u0 = minf(u0, float(e.u0))
		u1 = maxf(u1, float(e.u1))
		v0 = minf(v0, float(e.v0))
		v1 = maxf(v1, float(e.v1))
	if u0 == INF:
		u0 = 0.0
		u1 = 30.0
		v0 = -6.0
	var bb := Rect2(u0, v0, u1 - u0, v1 - v0).grow(2.0)
	var avail := size - Vector2(_ruler() + _u(20), _ruler() + _u(20))
	zoom = clampf(minf(avail.x / maxf(bb.size.x, 1.0), avail.y / maxf(bb.size.y, 1.0)), MIN_ZOOM, 40.0)
	origin = Vector2.ONE * (_ruler() + _u(10)) + (avail - bb.size * zoom) * 0.5 - bb.position * zoom
	queue_redraw()


# ------------------------------------------------------------------ choix

## Élément sous le point `m` (uv, m) : ouvertures, puis le plus petit objet,
## puis la pièce la plus proche ; hors de la coupe ou d'un étage masqué : rien.
func element_at(m: Vector2) -> Dictionary:
	var best := {}
	var best_area := INF
	var rooms := []
	var opening := {}
	var tol := 3.0 / zoom
	var list := projected()
	for i in range(list.size() - 1, -1, -1):
		var e: Dictionary = list[i]
		if not floor_shown(int(e.f)) or not in_cut(e):
			continue
		var r := Rect2(float(e.u0), float(e.v0), float(e.u1) - float(e.u0), float(e.v1) - float(e.v0)).grow(tol)
		if not r.has_point(m):
			continue
		if plane == "dessous" and e.has("poly") and (e.poly as PackedVector2Array).size() >= 3 and not Geometry2D.is_point_in_polygon(m, e.poly):
			continue
		match String(e.k):
			"room":
				rooms.append(e)
			"opening":
				if opening.is_empty():
					opening = e.it
			_:
				if float(e.area) < best_area:
					best_area = float(e.area)
					best = e.it
	# Pièces : la plus proche, sauf une pièce d'un autre étage dans son volume
	# (la passerelle dans l'entrepôt en double hauteur).
	var best_room := {}
	if not rooms.is_empty():
		var near: Dictionary = rooms[0]
		best_room = near.it
		for e in rooms:
			if int(e.f) != int(near.f) and float(e.u0) >= float(near.u0) - 0.01 and float(e.u1) <= float(near.u1) + 0.01 					and float(e.v0) >= float(near.v0) - 0.01 and float(e.v1) <= float(near.v1) + 0.01:
				best_room = e.it
				break
	var hit: Dictionary = opening if not opening.is_empty() else (best if not best.is_empty() else best_room)
	return hit.get("e", {}) if not hit.is_empty() else {}


## Élément projeté d'un identifiant ({} s'il n'est pas dans la vue).
func projected_of(eid: String) -> Dictionary:
	for e in projected():
		if String(e.it.id) == eid:
			return e
	return {}


# ------------------------------------------------------------------ entrées

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		mouse_m = to_m(mm.position)
		if _pan:
			origin += mm.relative
			queue_redraw()
		else:
			_update_hover()
			_over.queue_redraw()
		ed.show_cursor_view(self, mouse_m)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse_m = to_m(mb.position)
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if mb.pressed:
				if mb.ctrl_pressed:
					_zoom_at(mb.position, 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
				else:
					ed.cycle_hotbar(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and _space):
			_pan = mb.pressed
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			ed.canvas.cancel()
			if ed.tool() == "select":
				ed.select("")
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			grab_focus()
			_press()
			accept_event()
			_over.queue_redraw()


func _press() -> void:
	if ed.tool() != "select":
		# La pose reste en vue Dessus (D13).
		ed.set_status(Lang.t("La pose se fait en vue Dessus ; ici : choisir, déplacer, mesurer (la souris : ²)",
			"Placing is done in the Top view; here: pick, move, measure (the mouse: `)"))
		return
	var e := element_at(mouse_m)
	ed.select(String(e.get("id", "")))


func _update_hover() -> void:
	var eid := String(element_at(mouse_m).get("id", ""))
	if eid != hover:
		hover = eid
		ed.map_hovered(eid)


# ------------------------------------------------------------------ dessin

## La vue : fond et grille (le contenu et le dessus sont ses couches).
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if ed == null:
		return
	_draw_grid()


## Contenu (couche `_layer`), dessiné avec une marge d'une vue autour.
func _draw_content() -> void:
	if ed == null:
		return
	var t0 := Time.get_ticks_usec()
	content_draws += 1
	var c: CanvasItem = _layer
	var font := UiStyle.font("body")
	var list := projected()
	var area := Rect2(-size, size * 3.0)
	if plane == "dessous":
		_draw_below(c, list, font, area)
	else:
		_draw_side(c, list, font, area)
	last_draw_us = Time.get_ticks_usec() - t0


## Dessus (couche `_over`) : sélection, survol, règles, niveaux, curseur, trièdre.
func _draw_overlay() -> void:
	if ed == null:
		return
	var font := UiStyle.font("body")
	_draw_selection(_over)
	_over_rulers(font)


func _over_rulers(font: Font) -> void:
	# Les règles et le trièdre sont dessinés par MapView sur la vue elle-même :
	# ici, sur la couche du dessus (même code, autre support).
	_over_target = _over
	_draw_rulers(font)
	if is_elevation(plane):
		_draw_level_tags(_over)
	if not offscreen:
		_draw_ruler_cursor(mouse_m)
	_draw_triad(font)
	_over_target = null


## Vue de côté : terrain, pièces, éléments, niveaux, noms.
func _draw_side(c: CanvasItem, _list: Array, font: Font, area: Rect2) -> void:
	var y0 := to_px(Vector2(0, 0)).y
	if y0 < area.end.y:
		var tr := Rect2(area.position.x, maxf(y0, area.position.y), area.size.x, area.end.y - maxf(y0, area.position.y))
		c.draw_rect(tr, COL_TERRAIN)
		_hatch(tr, _u(6), Color(1, 1, 1, 0.07), 2.0, 1, c, area)
	var doc := ed.doc
	var k_cur := ed.floor_k
	var cut := coupe.size() == 2
	var shown := []
	for i in doc.floor_count():
		shown.append(floor_shown(i))
	# Pièces.
	for e in _rooms:
		if not shown[int(e.f)]:
			continue
		var r := rect_px(e)
		if r.intersects(area):
			_draw_room(c, e, r, _alpha(e, k_cur, cut), area)
	# Éléments (une fois par rectangle à l'écran).
	for e in _others:
		if not shown[int(e.f)]:
			continue
		var r := rect_px(e)
		if r.grow(16.0).intersects(area):
			_draw_item(c, e, r, _alpha(e, k_cur, cut))
	# Lignes de niveau : sols (pleins), plafonds d'étage (tirets).
	var x0 := maxf(area.position.x, _ruler())
	for i in doc.floor_count():
		var sol := doc.floor_sol(i)
		if i > 0:
			var ys := to_px(Vector2(0, -sol)).y
			c.draw_line(Vector2(x0, ys), Vector2(area.end.x, ys), Color(COL_LEVEL, 0.28), 1.0)
		var yc := to_px(Vector2(0, -(sol + doc.floor_height(i)))).y
		c.draw_dashed_line(Vector2(x0, yc), Vector2(area.end.x, yc), Color(COL_LEVEL, 0.22), 1.0, _u(6))
	c.draw_line(Vector2(area.position.x, y0), Vector2(area.end.x, y0), Color(COL_GROUND, 0.65), 1.0)
	# Noms des pièces (pas ceux cachés par une pièce plus proche, sauf coupe).
	var fs := EditorUi.fs(12)
	for e in _rooms:
		if not shown[int(e.f)]:
			continue
		var a := _alpha(e, k_cur, cut)
		if a < 0.2 or (_hidden_names.has(String(e.it.id)) and not (cut and in_cut(e))):
			continue
		var r := rect_px(e)
		var nm := String(e.it.get("name", ""))
		if nm == "" or not r.intersects(area):
			continue
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(r.get_center().x - w * 0.5, r.position.y + _u(15))
		c.draw_string_outline(font, at, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		c.draw_string(font, at, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.45 + 0.5 * a))


## Opacité (alpha_of sans appels : boucle de dessin).
func _alpha(e: Dictionary, k_cur: int, cut: bool) -> float:
	if cut and (float(e.hi) <= float(coupe[0]) + 0.001 or float(e.lo) >= float(coupe[1]) - 0.001):
		return OUT_OF_CUT
	var a := float(e.ab)
	return a * 0.8 if int(e.f) != k_cur else a


## Pièce : boîte du sol au plafond réel (couleur de sa zone), murs de profil
## aux deux bouts, dalle du plafond, dalle d'étage hachurée dessous.
func _draw_room(c: CanvasItem, e: Dictionary, r: Rect2, a: float, area: Rect2) -> void:
	var zc := ed.zone_color(String(e.it.get("zone", "")))
	c.draw_rect(r, Color(zc.r, zc.g, zc.b, 0.08 + 0.16 * a))
	c.draw_rect(r, Color(COL_WALL, 0.3 + 0.55 * a), false, 1.2)
	var half := MapGeom.WALL_HALF * zoom
	for x in [r.position.x, r.end.x]:
		c.draw_rect(Rect2(x - half, r.position.y, half * 2.0, r.size.y), Color(COL_WALL, 0.25 + 0.6 * a))
	c.draw_rect(Rect2(r.position.x - half, r.position.y - 0.12 * zoom, r.size.x + half * 2.0, 0.24 * zoom), Color(COL_WALL, 0.2 + 0.5 * a))
	if bool(e.it.get("slab", false)):
		var sol := -float(e.v1)
		var top := to_px(Vector2(0, -sol)).y
		var bot := to_px(Vector2(0, -(sol - MapVertical.DALLE))).y
		var sr := Rect2(r.position.x - half, top, r.size.x + half * 2.0, bot - top)
		_hatch(sr, _u(4), Color(COL_SLAB, 0.35), 1.2, -1, c, area)
		c.draw_rect(sr, Color(COL_SLAB, 0.3 + 0.5 * a), false, 1.0)


## Un élément (hors pièces) à son opacité `a`.
func _draw_item(c: CanvasItem, e: Dictionary, r: Rect2, a: float) -> void:
	var it: Dictionary = e.it
	var col: Color = it.get("col", Color.WHITE)
	match String(e.k):
		"pillar":
			c.draw_rect(r, Color(180 / 255.0, 180 / 255.0, 188 / 255.0, 0.35 + 0.6 * a))
			c.draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
		"wall":
			c.draw_rect(r, Color(COL_WALL, 0.35 + 0.6 * a))
			c.draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
		"stairs":
			_draw_stairs(c, e, r, a)
		"trap":
			c.draw_rect(r, Color(1.0, 0.3, 0.3, 0.12 * a))
			c.draw_rect(r, Color(1.0, 0.35, 0.3, 0.6 * a), false, 1.0)
		"clip":
			c.draw_rect(r, Color(COL_CLIP, 0.1 * a))
			_hatch(r, _u(6), Color(COL_CLIP, 0.4 * a), 1.0, 1, c, Rect2(-size, size * 3.0))
			c.draw_rect(r, Color(COL_CLIP, 0.85 * a), false, 1.2)
		"opening":
			var t := String(it.otype)
			c.draw_rect(r, Color(col, 0.7 if t == "passage" else 0.45 + 0.5 * a))
			if it.has("price") and a > 0.3:
				var s := str(int(it.price))
				var fs := EditorUi.fs(10) if (float(e.u1) - float(e.u0)) > 1.0 else _fs(9.5)
				var bf := bold_font()
				var w := bf.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var at := Vector2(r.get_center().x - w * 0.5, r.position.y - _u(4))
				c.draw_string_outline(bf, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
				c.draw_string(bf, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		"wobj":
			c.draw_rect(r, Color(30 / 255.0, 30 / 255.0, 32 / 255.0, 0.5 * a))
			c.draw_rect(r, Color(col, a), false, 1.4)
			_icon(c, it, r, a)
		"fobj":
			var t := String(it.e.get("type", ""))
			if t in ["depart", "apparition"] and r.size.y >= 10.0:
				_draw_person(c, r, Color(0.25, 0.95, 0.35, a) if t == "depart" else Color(0.75, 0.2, 0.18, a))
			else:
				c.draw_rect(r, Color(col.darkened(0.4), 0.45 * a))
				c.draw_rect(r, Color(col, a), false, 1.2)
				_icon(c, it, r, a)
		"decor":
			var block := MapCatalog.blocking(it.e)
			c.draw_rect(r, Color(col.darkened(0.35), (0.5 if block != "non" else 0.28) * a))
			c.draw_rect(r, Color(col.lightened(0.2), 0.9 * a), false, 1.4 if block != "non" else 1.0)
			_hook(c, it, r, a)
			_icon(c, it, r, a)
		"light", "effect":
			_draw_point(c, e, r, a)


## Silhouette (départ des joueurs, apparition) dans son rectangle.
func _draw_person(c: CanvasItem, r: Rect2, col: Color) -> void:
	var hh := r.size.y
	var x := r.get_center().x
	var y0 := r.end.y
	c.draw_circle(Vector2(x, y0 - hh + hh * 0.1), hh * 0.09, col)
	c.draw_rect(Rect2(x - hh * 0.12, y0 - hh * 0.78, hh * 0.24, hh * 0.42), col)
	c.draw_rect(Rect2(x - hh * 0.1, y0 - hh * 0.38, hh * 0.08, hh * 0.38), col)
	c.draw_rect(Rect2(x + hh * 0.02, y0 - hh * 0.38, hh * 0.08, hh * 0.38), col)


## Icône de l'inventaire au milieu d'une boîte assez grande.
func _icon(c: CanvasItem, it: Dictionary, r: Rect2, a: float) -> void:
	var s := minf(minf(r.size.x, r.size.y) * 0.9, _u(40))
	if s < _u(12) or a < 0.3:
		return
	MapIcons.draw(c, MapCatalog.item_for(it.e), Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)))


## Trait fin pointillé de l'élément à son point d'accroche (plafond, sol, meuble).
func _hook(c: CanvasItem, it: Dictionary, r: Rect2, a: float) -> void:
	var hook := float(it.get("hook", NAN))
	if is_nan(hook):
		return
	var y := to_px(Vector2(0, -hook)).y
	var x := r.get_center().x
	var from := r.position.y if y < r.position.y else r.end.y
	if absf(y - from) > 2.0:
		c.draw_dashed_line(Vector2(x, from), Vector2(x, y), Color(col_of(it), 0.7 * a), 1.0, _u(3))


func col_of(it: Dictionary) -> Color:
	return it.get("col", Color.WHITE)


## Luminaire, effet : zone en tirets (effet), icône à la hauteur de la lumière
## ou de l'effet, trait pointillé jusqu'au point d'accroche.
func _draw_point(c: CanvasItem, e: Dictionary, r: Rect2, a: float) -> void:
	var it: Dictionary = e.it
	var col := col_of(it)
	if e.k == "effect":
		c.draw_rect(r, Color(col, 0.1 * a))
		var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			c.draw_dashed_line(p[i], p[(i + 1) % 4], Color(col.lightened(0.25), 0.8 * a), 1.0, _u(4))
	var z := float(it.get("z", (float(it.z0) + float(it.z1)) * 0.5))
	var at := Vector2(r.get_center().x, to_px(Vector2(0, -z)).y)
	var hook := float(it.get("hook", NAN))
	if not is_nan(hook):
		var hy := to_px(Vector2(0, -hook)).y
		if absf(hy - at.y) > 2.0:
			c.draw_dashed_line(at, Vector2(at.x, hy), Color(col, 0.75 * a), 1.0, _u(3))
	var s := clampf(zoom * 0.9, _u(14), _u(26))
	if a >= 0.3:
		MapIcons.draw(c, MapCatalog.item_for(it.e), Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)))
	else:
		c.draw_circle(at, _u(3), Color(col, a))


## Escalier : profil en marches vu de côté, bandes de contremarches vu de face.
func _draw_stairs(c: CanvasItem, e: Dictionary, r: Rect2, a: float) -> void:
	var it: Dictionary = e.it
	var up: Vector2 = it.get("up", Vector2.UP)
	var along := up.dot(_right_dir())
	var n := maxi(2, int(it.get("steps", 18)))
	if absf(along) < 0.5:
		c.draw_rect(r, Color(COL_STAIRS, 0.25 + 0.4 * a))
		c.draw_rect(r, Color(190 / 255.0, 140 / 255.0, 215 / 255.0, a), false, 1.0)
		for i in range(1, n):
			var y := r.end.y - r.size.y * i / n
			c.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(220 / 255.0, 190 / 255.0, 235 / 255.0, 0.35 * a), 1.0)
		return
	# Profil : du pied (côté opposé à la montée) au palier du haut.
	var pts := PackedVector2Array()
	var w := r.size.x
	var h := r.size.y
	var run := w / n
	var rise := h / n
	var sx := 1.0 if along > 0.0 else -1.0
	var x0 := r.position.x if sx > 0.0 else r.end.x
	var yb := r.end.y
	pts.append(Vector2(x0, yb))
	for i in n:
		pts.append(Vector2(x0 + sx * i * run, yb - (i + 1) * rise))
		pts.append(Vector2(x0 + sx * (i + 1) * run, yb - (i + 1) * rise))
	pts.append(Vector2(x0 + sx * w, yb - h + minf(0.3 * zoom, h * 0.5)))
	pts.append(Vector2(x0 + sx * minf(0.5 * zoom, w * 0.5), yb))
	if Geometry2D.triangulate_polygon(pts).size() > 0:
		c.draw_colored_polygon(pts, Color(COL_STAIRS, 0.3 + 0.45 * a))
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(200 / 255.0, 150 / 255.0, 225 / 255.0, a), 1.0)


## Direction de la carte (x, y) qui va vers la droite de l'écran.
func _right_dir() -> Vector2:
	var a := point_of(plane, Vector2(0, 0), 0.0)
	var b := point_of(plane, Vector2(1, 0), 0.0)
	return Vector2(b.x - a.x, b.y - a.y)


## Vue de dessous : l'étage courant vu par en dessous (plafonds compris).
func _draw_below(c: CanvasItem, list: Array, font: Font, area: Rect2) -> void:
	var k := ed.floor_k
	for e in list:
		if int(e.f) != k or not e.has("poly"):
			continue
		if not rect_px(e).intersects(area):
			continue
		var pts := PackedVector2Array()
		for q in (e.poly as PackedVector2Array):
			pts.append(to_px(q))
		if pts.size() < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
			continue
		var it: Dictionary = e.it
		match String(e.k):
			"room":
				var zc := ed.zone_color(String(it.get("zone", "")))
				c.draw_colored_polygon(pts, Color(zc.r, zc.g, zc.b, 0.22))
				c.draw_polyline(pts + PackedVector2Array([pts[0]]), COL_WALL, maxf(2.0, zoom * 0.5))
			"opening":
				c.draw_colored_polygon(pts, Color(col_of(it), 0.85))
			_:
				c.draw_colored_polygon(pts, Color(col_of(it).darkened(0.3), 0.55))
				c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col_of(it), 0.9), 1.0)
	var fs := EditorUi.fs(12)
	for e in list:
		if int(e.f) != k or e.k != "room":
			continue
		var r := rect_px(e)
		var nm := String(e.it.get("name", ""))
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string_outline(font, r.get_center() - Vector2(w * 0.5, 0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		c.draw_string(font, r.get_center() - Vector2(w * 0.5, 0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))


## Élément choisi (jaune) et survolé (halo bleu).
func _draw_selection(c: CanvasItem) -> void:
	if offscreen:
		return
	var hov := projected_of(ed.hover_id) if ed.hover_id != "" and ed.hover_id != ed.selected else {}
	if not hov.is_empty() and floor_shown(int(hov.f)):
		var r := rect_px(hov)
		for i in 3:
			c.draw_rect(r.grow(4 + (2 - i) * 2), Color(COL_HOVER, 0.18 + i * 0.3), false, 7.0 - i * 2.5)
	var sel := projected_of(ed.selected) if ed.selected != "" else {}
	if sel.is_empty() or not floor_shown(int(sel.f)):
		return
	var r := rect_px(sel)
	if plane == "dessous" and sel.has("poly"):
		var pts := PackedVector2Array()
		for q in (sel.poly as PackedVector2Array):
			pts.append(to_px(q))
		if pts.size() >= 2:
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), COL_SEL, 2.5)
		return
	c.draw_rect(r.grow(1.0), COL_SEL, false, 2.5)


## Étiquettes de niveau (§ 3.2) sur la règle Z : « É1 +3,50 », celle de
## l'étage courant en or.
func _draw_level_tags(c: CanvasItem) -> void:
	var doc := ed.doc
	var bf := bold_font(500)
	var bg := bold_font(700)
	var fs := _fs(10.5)
	for i in doc.floor_count():
		var sol := doc.floor_sol(i)
		var y := to_px(Vector2(0, -sol)).y
		if y < _ruler() or y > size.y:
			continue
		var cur := i == ed.floor_k
		var tag := Lang.t("É%d", "F%d") % i
		var lbl := tag if size.x < _u(400) else "%s  %s%s" % [tag, "+" if i > 0 and sol > 0.0 else "", num(sol, 2)]
		var f: Font = bg if cur else bf
		var w := f.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + _u(10)
		var r := Rect2(_ruler() + _u(2), y - _u(8), w, _u(15))
		_round_rect(c, r, Color("3a3020") if cur else Color("232427"), COL_GOLD if cur else Color("4D4D54"))
		c.draw_string(f, Vector2(r.position.x + _u(5), y + _u(3.5)), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_GOLD if cur else Color("CFC9B8"))


## Rectangle aux coins arrondis (2 px), rempli et bordé.
static func _round_rect(c: CanvasItem, r: Rect2, fill: Color, border: Color, radius := 2.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = false
	c.draw_style_box(sb, r)


# ------------------------------------------------------------------ en-tête, coupe, étages

func header_sub() -> String:
	if plane == "dessous":
		return Lang.t("Étage %d · vu de dessous", "Floor %d · seen from below") % ed.floor_k
	return "%s · %s" % [look_text(plane), floors_text()]


## « étages : tous », « étages : jusqu'à É1 », « étage : É1 ».
func floors_text() -> String:
	match floors_mode:
		Floors.UP_TO:
			return Lang.t("étages : jusqu'à É%d", "floors: up to F%d") % ed.floor_k
		Floors.ONLY:
			return Lang.t("étage : É%d", "floor: F%d") % ed.floor_k
	return Lang.t("étages : tous", "floors: all")


func header_chips() -> Array:
	var out := []
	if plane != "dessous":
		if coupe.size() == 2:
			var t := Lang.t("Coupe : %s", "Cut: %s") % cut_text()
			if coupe_label != "":
				t += " (%s)" % coupe_label
			out.append({"id": "coupe", "text": t + " ▾", "hl": true})
		else:
			out.append({"id": "coupe", "text": Lang.t("Coupe ▾", "Cut ▾")})
	out.append_array(super())
	return out


## Tranche de la coupe : « Y 4,5 → 17 ».
func cut_text() -> String:
	if coupe.size() != 2:
		return ""
	return "%s %s → %s" % [String(depth_axis(plane)[0]), MapCatalog.short_num(float(coupe[0])) if not Lang.is_en() else str(snappedf(float(coupe[0]), 0.01)),
		MapCatalog.short_num(float(coupe[1])) if not Lang.is_en() else str(snappedf(float(coupe[1]), 0.01))]


## Le menu des étages (MapViewPane : clic sur « étages : »).
func floors_menu_items() -> Array:
	return [{"id": 10 + Floors.ALL, "text": Lang.t("Étages : tous", "Floors: all"), "radio": floors_mode == Floors.ALL},
		{"id": 10 + Floors.UP_TO, "text": Lang.t("Jusqu'à l'étage courant", "Up to the current floor"), "radio": floors_mode == Floors.UP_TO},
		{"id": 10 + Floors.ONLY, "text": Lang.t("L'étage courant seulement", "The current floor only"), "radio": floors_mode == Floors.ONLY}]


func header_menu(id: String) -> Array:
	match id:
		"coupe":
			return [{"id": 0, "text": Lang.t("Coupe : aucune", "Cut: none"), "radio": coupe_mode == "aucune"},
				{"id": 1, "text": Lang.t("Autour de la sélection (K)", "Around the selection (K)"), "radio": coupe_mode == "selection"},
				{"id": 2, "text": Lang.t("Personnalisée (traits de la vue Dessus)", "Custom (lines in the Top view)"), "radio": coupe_mode == "perso"}]
		"floors":
			return floors_menu_items()
	return super(id)


func header_menu_pressed(id: String, i: int) -> void:
	match id:
		"coupe":
			match i:
				0:
					set_cut([], "aucune")
				1:
					cut_around_selection()
				2:
					var c := coupe.duplicate()
					if c.size() != 2:
						var mid := float(point_of(plane, to_m(size * 0.5), 0.0).y if String(depth_axis(plane)[0]) == "Y" else point_of(plane, to_m(size * 0.5), 0.0).x)
						var sel := projected_of(ed.selected)
						c = [float(sel.lo), float(sel.hi)] if not sel.is_empty() else [mid - 5.0, mid + 5.0]
					set_cut(c, "perso")
		"floors":
			floors_mode = clampi(i - 10, 0, 2) as Floors
			ed.views.views_changed()
			queue_redraw()
		_:
			super(id, i)


## Coupe [p0, p1] (vide : aucune), son origine et son libellé.
func set_cut(c: Array, mode: String, label := "") -> void:
	coupe = []
	if c.size() == 2:
		var a := minf(float(c[0]), float(c[1]))
		var b := maxf(float(c[0]), float(c[1]))
		if b - a >= 0.1:
			coupe = [snappedf(a, 0.01), snappedf(b, 0.01)]
	coupe_mode = mode if not coupe.is_empty() else "aucune"
	coupe_label = label if not coupe.is_empty() else ""
	if ed != null and ed.views != null:
		ed.views.views_changed()
	queue_redraw()


## Coupe autour de l'élément choisi (touche K, menu) ; rend false s'il n'y en a pas.
func cut_around_selection() -> bool:
	var sel := projected_of(ed.selected)
	if sel.is_empty() or plane == "dessous":
		ed.set_status(Lang.t("Coupe : choisissez d'abord un élément", "Cut: pick an element first"))
		return false
	var e: Dictionary = sel.it.get("e", {})
	var nm := String(e.get("nom", "")) if e.has("contour") else MapCatalog.name_of(MapCatalog.item_for(e))
	set_cut([float(sel.lo), float(sel.hi)], "selection", nm)
	ed.set_status(Lang.t("Coupe %s : %s (K : l'enlever)", "%s cut: %s (K: remove it)") % [plane_name(plane), cut_text()])
	return true
