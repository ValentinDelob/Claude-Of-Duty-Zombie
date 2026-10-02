class_name MapViewLayout
extends Control
## Zone des vues de l'éditeur de cartes (docs/EDITOR_VIEWS.md, § 5) :
## fenêtres de vue (MapViewPane) dans une disposition (1 vue, 2 côte à côte,
## 2 empilées, 3 : 1 + 2, 3 : 2 + 1, 4), séparateurs déplaçables, vue active,
## agrandissement d'une vue, barre rapide (posée sur la vue en 1 vue, ancrée
## dans une bande de 48 px sous les vues sinon) et inventaire.
##
## La vue Dessus est UNIQUE (MapCanvas, `ed.canvas` : elle porte les outils
## de pose) : la donner à une autre fenêtre échange les plans des deux
## fenêtres. Les élévations (MapElevation) sont propres à chaque fenêtre.

## Dispositions : identifiant -> plans par défaut des fenêtres.
const LAYOUTS := {"1": ["dessus"], "2h": ["dessus", "avant"], "2v": ["dessus", "avant"],
	"3a": ["dessus", "avant", "droite"], "3b": ["avant", "droite", "dessus"], "4": ["dessus", "avant", "avant", "droite"]}
const ORDER := ["1", "2h", "2v", "3a", "3b", "4"]
## Disposition au premier lancement (revue du 03/10/2026) : Dessus au-dessus d'Avant.
const DEFAULT := "2v"
## Séparateur (px), taille minimale d'une vue (px, à 100 %), bande de la barre rapide.
const SPLIT := 4.0
const MIN_VIEW := Vector2(220, 160)
const DOCK_H := 48.0
const COL_SPLIT := Color("0E0E10")
const COL_DOTS := Color("55555c")
const COL_DOCK := Color("18191B")
const COL_DOCK_LINE := Color("38383D")

var ed: MapEditor
var layout_id := DEFAULT
## Proportions des séparateurs (0 à 1) : vertical (x), horizontal (y).
var rx := 0.5
var ry := 0.5
var panes: Array[MapViewPane] = []
## Fenêtre agrandie à toute la zone (null : la disposition).
var maximized: MapViewPane
var active_pane: MapViewPane
## Séparateurs : contrôles (MapViewLayout.Split).
var _splits: Array = []
var _dock: Control


## Séparateur déplaçable : barre de 4 px, poignée de 3 points, curseur ↔ / ↕ ;
## double-clic : partage égal.
class Split extends Control:
	var layout: MapViewLayout
	## « x » : barre verticale (déplace rx) ; « y » : barre horizontale (ry).
	var axis := "x"
	var _drag := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_HSIZE if axis == "x" else Control.CURSOR_VSIZE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), MapViewLayout.COL_SPLIT)
		var c := size * 0.5
		var d := Vector2(0, EditorUi.px(6)) if axis == "x" else Vector2(EditorUi.px(6), 0)
		for i in [-1, 0, 1]:
			draw_circle(c + d * i, 1.5, MapViewLayout.COL_DOTS)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := event as InputEventMouseButton
			if mb.double_click:
				layout.set_ratio(axis, 0.5)
				_drag = false
			else:
				_drag = mb.pressed
			accept_event()
		elif event is InputEventMouseMotion and _drag:
			var p := layout.get_local_mouse_position()
			var area := layout.views_rect()
			if axis == "x":
				layout.set_ratio("x", (p.x - area.position.x) / maxf(area.size.x, 1.0))
			else:
				layout.set_ratio("y", (p.y - area.position.y) / maxf(area.size.y, 1.0))
			accept_event()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock = Control.new()
	_dock.name = "Dock"
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_dock.draw.connect(_draw_dock)
	add_child(_dock)
	resized.connect(_sort)


## Met en place une disposition et les plans de ses fenêtres (`planes` vide :
## ceux par défaut).
func setup(id: String, planes: Array = []) -> void:
	if not LAYOUTS.has(id):
		id = DEFAULT
	layout_id = id
	maximized = null
	var want: Array = planes if planes.size() == (LAYOUTS[id] as Array).size() else LAYOUTS[id]
	# La vue Dessus est unique : un seul « dessus » dans la liste.
	var seen_top := false
	var fixed := []
	for pl in want:
		var p := String(pl)
		if not p in MapView.PLANES:
			p = "avant"
		if p == "dessus":
			if seen_top:
				p = "avant"
			seen_top = true
		fixed.append(p)
	while panes.size() > fixed.size():
		var old: MapViewPane = panes.pop_back()
		_release(old)
		old.queue_free()
	while panes.size() < fixed.size():
		var pn := MapViewPane.new()
		pn.name = "Pane%d" % panes.size()
		pn.layout = self
		add_child(pn)
		move_child(pn, 0)
		panes.append(pn)
	for i in panes.size():
		panes[i].home_plane = String((LAYOUTS[id] as Array)[i])
	# La vue Dessus d'abord (elle peut quitter une autre fenêtre).
	for i in panes.size():
		_assign(panes[i], String(fixed[i]))
	if not fixed.has("dessus"):
		_park_canvas()
	if active_pane == null or not panes.has(active_pane):
		active_pane = panes[0]
	for p in panes:
		p.set_active(p == active_pane)
	_rebuild_splits()
	_sort()
	views_changed()


## Donne le plan `pl` à la fenêtre `pn` (Dessus : la vue unique, échangée
## avec la fenêtre qui l'avait).
func _assign(pn: MapViewPane, pl: String) -> void:
	if pl == "dessus":
		if pn.view == ed.canvas:
			return
		var other := pane_of(ed.canvas)
		if other != null and other != pn:
			var mine := pn.plane()
			pn.set_view(ed.canvas)
			_assign(other, mine if mine != "dessus" else "avant")
		else:
			pn.set_view(ed.canvas)
		ed.canvas.visible = true
		return
	var ev: MapElevation = pn.get_meta("elev") if pn.has_meta("elev") else null
	if ev == null:
		ev = MapElevation.new()
		ev.ed = ed
		ev.name = "Elevation"
		ev.zoom = ed.canvas.zoom
		pn.set_meta("elev", ev)
	var first := ev.get_parent() == null
	ev.plane = pl
	ev.visible = true
	pn.set_view(ev)
	if first:
		_frame_like_top.call_deferred(ev)


## La vue Dessus hors de toute fenêtre : gardée dans l'arbre, cachée (ses
## outils, son aimantation et son état restent ceux de l'éditeur).
func _park_canvas() -> void:
	var c := ed.canvas
	if c.get_parent() != self:
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
		add_child(c)
		move_child(c, 0)
	c.visible = false


func _release(pn: MapViewPane) -> void:
	if pn.view == ed.canvas:
		_park_canvas()


## Fenêtre qui montre une vue (null : aucune).
func pane_of(v: MapView) -> MapViewPane:
	for p in panes:
		if p.view == v:
			return p
	return null


## Change le plan d'une fenêtre (ViewCube, menu).
func set_pane_plane(pn: MapViewPane, pl: String) -> void:
	if pn == null or pl == pn.plane():
		return
	if pn.view == ed.canvas and pl != "dessus":
		_park_canvas()
	_assign(pn, pl)
	_sort()
	views_changed()


func pane_count() -> int:
	return panes.size()


## Vues des fenêtres, dans l'ordre.
func views() -> Array[MapView]:
	var out: Array[MapView] = []
	for p in panes:
		if p.view != null:
			out.append(p.view)
	return out


## Élévations des fenêtres.
func elevations() -> Array:
	return views().filter(func(v): return v is MapElevation)


## Élévations qui ont une coupe.
func cuts() -> Array:
	return elevations().filter(func(v): return (v as MapElevation).coupe.size() == 2)


func active_view() -> MapView:
	return active_pane.view if active_pane != null else ed.canvas


func set_active_pane(pn: MapViewPane) -> void:
	if pn == active_pane or pn == null:
		return
	active_pane = pn
	for p in panes:
		p.set_active(p == pn)


## Ce que montrent les vues a changé (coupe, étages, plan) : en-têtes et vues
## redessinés.
func views_changed() -> void:
	if ed == null:
		return
	ed.views_stamp += 1
	for p in panes:
		p.queue_redraw()
	if ed.canvas != null:
		ed.canvas.queue_redraw()
	_dock.queue_redraw()


## Espace maintenu : toutes les vues.
func set_space(on: bool) -> void:
	for v in views():
		v.set_space(on)
	if ed.canvas != null:
		ed.canvas.set_space(on)


# ------------------------------------------------------------------ disposition

func dock_h() -> float:
	return EditorUi.px(DOCK_H) if docked() else 0.0


## La barre rapide est-elle ancrée sous les vues (2 vues ou plus) ?
func docked() -> bool:
	return panes.size() > 1


## Zone des fenêtres (sans la bande de la barre rapide).
func views_rect() -> Rect2:
	return Rect2(0, 0, size.x, maxf(size.y - dock_h(), 0.0))


## Bande de la barre rapide.
func dock_rect() -> Rect2:
	var h := dock_h()
	return Rect2(0, size.y - h, size.x, h)


func set_ratio(axis: String, v: float) -> void:
	if axis == "x":
		rx = v
	else:
		ry = v
	_sort()


## Rectangles des fenêtres et des séparateurs pour la disposition courante.
func compute() -> Dictionary:
	var a := views_rect()
	var g := SPLIT
	var mn := Vector2(EditorUi.px(MIN_VIEW.x), EditorUi.px(MIN_VIEW.y))
	var fx := clampf(rx, 0.0, 1.0)
	var fy := clampf(ry, 0.0, 1.0)
	# Bornes : chaque vue garde sa taille minimale (si la place le permet).
	if a.size.x > mn.x * 2.0 + g:
		fx = clampf(fx, mn.x / a.size.x, 1.0 - (mn.x + g) / a.size.x)
	if a.size.y > mn.y * 2.0 + g:
		fy = clampf(fy, mn.y / a.size.y, 1.0 - (mn.y + g) / a.size.y)
	var xs := roundf(a.position.x + a.size.x * fx - g * 0.5)
	var ys := roundf(a.position.y + a.size.y * fy - g * 0.5)
	var left := Rect2(a.position, Vector2(xs - a.position.x, a.size.y))
	var right := Rect2(Vector2(xs + g, a.position.y), Vector2(a.end.x - xs - g, a.size.y))
	var top := Rect2(a.position, Vector2(a.size.x, ys - a.position.y))
	var bottom := Rect2(Vector2(a.position.x, ys + g), Vector2(a.size.x, a.end.y - ys - g))
	var vbar := Rect2(xs, a.position.y, g, a.size.y)
	var hbar := Rect2(a.position.x, ys, a.size.x, g)
	match layout_id:
		"2h":
			return {"panes": [left, right], "splits": [["x", vbar]]}
		"2v":
			return {"panes": [top, bottom], "splits": [["y", hbar]]}
		"3a":
			return {"panes": [left, Rect2(right.position, Vector2(right.size.x, ys - a.position.y)), Rect2(Vector2(right.position.x, ys + g), Vector2(right.size.x, a.end.y - ys - g))],
				"splits": [["x", vbar], ["y", Rect2(right.position.x, ys, right.size.x, g)]]}
		"3b":
			return {"panes": [Rect2(a.position, Vector2(xs - a.position.x, top.size.y)), Rect2(Vector2(xs + g, a.position.y), Vector2(a.end.x - xs - g, top.size.y)), bottom],
				"splits": [["y", hbar], ["x", Rect2(xs, a.position.y, g, top.size.y)]]}
		"4":
			return {"panes": [Rect2(a.position, Vector2(left.size.x, top.size.y)), Rect2(Vector2(xs + g, a.position.y), Vector2(right.size.x, top.size.y)),
				Rect2(Vector2(a.position.x, ys + g), Vector2(left.size.x, bottom.size.y)), Rect2(Vector2(xs + g, ys + g), Vector2(right.size.x, bottom.size.y))],
				"splits": [["x", vbar], ["y", hbar]]}
	return {"panes": [a], "splits": []}


func _rebuild_splits() -> void:
	for s in _splits:
		(s as Node).queue_free()
	_splits = []
	for sp in compute().splits:
		var s := Split.new()
		s.layout = self
		s.axis = String(sp[0])
		add_child(s)
		_splits.append(s)


func _sort() -> void:
	if panes.is_empty():
		return
	var c := compute()
	var rects: Array = c.panes
	for i in panes.size():
		var pn := panes[i]
		if maximized != null:
			pn.visible = pn == maximized
			if pn == maximized:
				pn.position = views_rect().position
				pn.size = views_rect().size
			continue
		pn.visible = true
		var r: Rect2 = rects[i] if i < rects.size() else Rect2()
		pn.position = r.position
		pn.size = r.size
	var sp: Array = c.splits
	for i in _splits.size():
		var s: Split = _splits[i]
		s.visible = maximized == null and i < sp.size()
		if i < sp.size():
			var r: Rect2 = sp[i][1]
			s.position = r.position
			s.size = r.size
			s.queue_redraw()
	_dock.visible = docked()
	_dock.position = dock_rect().position
	_dock.size = dock_rect().size
	_dock.queue_redraw()
	if ed != null and ed.hotbar_ui != null:
		ed.hotbar_ui.ui_scale_changed()


## Agrandit une fenêtre à toute la zone des vues ; une seconde fois : retour.
func toggle_maximized(pn: MapViewPane) -> void:
	if panes.size() < 2:
		return
	maximized = null if maximized == pn else pn
	if maximized != null:
		set_active_pane(maximized)
	_sort()
	views_changed()


## Taille de l'interface changée : en-têtes, bande, séparateurs.
func ui_scale_changed() -> void:
	for p in panes:
		p.ui_scale_changed()
	_sort()


## Vue active d'après la souris (survol) : clavier et molette y vont.
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or panes.size() < 2:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		return
	var p := get_local_mouse_position()
	for pn in panes:
		if pn.visible and Rect2(pn.position, pn.size).has_point(p):
			set_active_pane(pn)
			return


# ------------------------------------------------------------------ cadrage

## Cadre toutes les vues sur la carte ; une élévation prend le zoom et les
## colonnes de la vue Dessus quand elles partagent l'axe horizontal.
func frame_all() -> void:
	ed.canvas.frame_all()
	for v in elevations():
		_frame_like_top(v)


func _frame_like_top(ev: MapElevation) -> void:
	if not is_instance_valid(ev) or ev.size.x <= 0.0:
		return
	ev.frame_all()
	var c := ed.canvas
	if c.size.x <= 0.0 or not c.is_visible_in_tree() or ev.plane == "dessous":
		return
	# Même zoom que la vue Dessus, même centre sur l'axe commun ; Avant : mêmes
	# colonnes X à l'écran (vue placée sous la vue Dessus).
	var vmid := ev.to_m(ev.size * 0.5).y
	ev.zoom = c.zoom
	ev.origin.y = ev.size.y * 0.5 - vmid * ev.zoom
	if ev.plane == "avant":
		ev.origin.x = c.origin.x + c.global_position.x - ev.global_position.x
	else:
		var m := c.to_m(c.size * 0.5)
		var u := MapView.uv_of(ev.plane, Vector3(m.x, m.y, 0.0)).x
		ev.origin.x = ev.size.x * 0.5 - u * ev.zoom
	ev.queue_redraw()


# ------------------------------------------------------------------ bande de la barre rapide

func _draw_dock() -> void:
	var r := Rect2(Vector2.ZERO, _dock.size)
	_dock.draw_rect(r, COL_DOCK)
	_dock.draw_rect(Rect2(0, 0, r.size.x, 1), COL_DOCK_LINE)
	if ed == null or ed.hotbar_ui == null:
		return
	var font := UiStyle.font("body")
	var fs := EditorUi.fs(12)
	var hb := Rect2(ed.hotbar_ui.position - _dock.position, ed.hotbar_ui.size)
	var pad := EditorUi.px(10)
	var y := r.size.y * 0.5 + fs * 0.36
	var lw := hb.position.x - pad * 2.0
	var rw := r.size.x - hb.end.x - pad * 2.0
	if lw > 20.0:
		_dock.draw_string(font, Vector2(pad, y), dock_left(), HORIZONTAL_ALIGNMENT_LEFT, lw, fs, MapViewPane.COL_DIM, TextServer.JUSTIFICATION_NONE)
	if rw > 20.0:
		_dock.draw_string(font, Vector2(hb.end.x + pad, y), dock_right(), HORIZONTAL_ALIGNMENT_RIGHT, rw, fs, MapViewPane.COL_DIM, TextServer.JUSTIFICATION_NONE)


## Texte de gauche de la bande : l'outil en main et ce qu'il fait.
func dock_left() -> String:
	var it := ed.current_item()
	if String(it.get("id", "")) == "select":
		return Lang.t("Sélection — clic : choisir · glisser : déplacer dans le plan de la vue", "Select — click: pick · drag: move in the view's plane")
	return "%s — %s" % [MapCatalog.name_of(it), Lang.t(String(it.get("hint_fr", "")), String(it.get("hint_en", "")))]


## Texte de droite : l'aimantation.
func dock_right() -> String:
	var t := MapSnap.label(ed.canvas.snap_mode, ed.canvas.fine_step)
	return t.left(1).to_upper() + t.substr(1)


func dock_redraw() -> void:
	if _dock != null:
		_dock.queue_redraw()
