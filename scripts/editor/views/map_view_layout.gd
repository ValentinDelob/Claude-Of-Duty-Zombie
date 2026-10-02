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
	"3a": ["dessus", "avant", "droite"], "3b": ["avant", "droite", "dessus"], "4": ["dessus", "3d", "avant", "droite"]}
## Plans uniques : la vue Dessus (outils de pose) et la 3D (un seul aperçu).
const UNIQUE := ["dessus", "3d"]
## Réglages mémorisés (_editeur.cfg).
const PREF_KEY := "vues"
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
## Vues liées (D7) : zoom commun, centre commun sur l'axe partagé.
var linked := true
## Coupe partagée entre les élévations de même direction.
var shared_cut := false
## État des vues à la dernière synchronisation (liaison) : vue -> [zoom, origine, taille].
var _link_seen: Dictionary = {}
var _save_t := -1.0
var _menu_ui: MapViewLayoutMenu
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
	# La vue Dessus et la 3D sont uniques : une seule de chaque dans la liste.
	var seen := {}
	var fixed := []
	for pl in want:
		var p := String(pl)
		if not (p in MapView.PLANES or p == "3d"):
			p = "avant"
		if p in UNIQUE:
			if seen.has(p):
				p = "avant"
			seen[p] = true
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
	_link_seen = {}
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
		_leave_3d(pn)
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
	if pl == "3d":
		var other3 := _pane_3d()
		if other3 != null and other3 != pn:
			var mine3 := pn.plane()
			_assign(other3, mine3 if mine3 != "3d" else "avant")
		var v3: MapView3D = pn.get_meta("v3d") if pn.has_meta("v3d") else null
		if v3 == null:
			v3 = MapView3D.new()
			v3.ed = ed
			v3.preview = ed.preview
			v3.name = "View3D"
			pn.set_meta("v3d", v3)
		if pn.view != null and pn.view != v3 and pn.view.plane != "3d":
			pn.set_meta("last_plane", pn.view.plane)
		pn.set_view(v3)
		v3.attach()
		return
	_leave_3d(pn)
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
	_leave_3d(pn)


## La fenêtre quitte la 3D : l'aperçu retourne à son panneau flottant.
func _leave_3d(pn: MapViewPane) -> void:
	if pn.view is MapView3D:
		(pn.view as MapView3D).detach()


## Fenêtre qui montre la 3D (null : aucune ; l'aperçu est le panneau flottant).
func _pane_3d() -> MapViewPane:
	for p in panes:
		if p.view is MapView3D:
			return p
	return null


## Fenêtre qui montre une vue (null : aucune).
func pane_of(v: MapView) -> MapViewPane:
	for p in panes:
		if p.view == v:
			return p
	return null


## Change le plan d'une fenêtre (ViewCube, menu) ; `animate` : transition
## de 180 ms (fondu croisé et glissement le long de l'axe qui change, § 4).
func set_pane_plane(pn: MapViewPane, pl: String, animate := false) -> void:
	if pn == null or pl == pn.plane():
		return
	var old := pn.plane()
	if animate and old != "3d" and pl != "3d":
		_transition(pn, old, pl)
	if pn.view == ed.canvas and pl != "dessus":
		_park_canvas()
	_assign(pn, pl)
	_sort()
	views_changed()
	save_soon()
	if pn.view is MapElevation and old != pl:
		_frame_like_top.call_deferred(pn.view)


## Transition (§ 4) : l'image d'avant se fond et glisse le long de l'axe qui
## change (l'axe commun aux deux plans reste fixe) ; 180 ms.
const TRANSITION := 0.18


func _transition(pn: MapViewPane, from: String, to: String) -> void:
	if DisplayServer.get_name() == "headless" or pn.view == null or not pn.is_visible_in_tree():
		return
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	var vr := Rect2i(pn.view.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if vr.size.x <= 0 or vr.size.y <= 0:
		return
	var tr := TextureRect.new()
	tr.name = "Transition"
	tr.texture = ImageTexture.create_from_image(img.get_region(vr))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.position = Vector2(0, pn.header_h())
	tr.size = Vector2(vr.size)
	pn.add_child(tr)
	# Axe commun : l'axe horizontal (Dessus <-> Avant : X) reste ; sinon l'autre.
	var same_h := String(MapView.h_axis(from)[0]) == String(MapView.h_axis(to)[0])
	var slide := Vector2(0, -EditorUi.px(28)) if same_h else Vector2(-EditorUi.px(28), 0)
	var tw := tr.create_tween().set_parallel(true)
	tw.tween_property(tr, "modulate:a", 0.0, TRANSITION)
	tw.tween_property(tr, "position", tr.position + slide, TRANSITION)
	tw.chain().tween_callback(tr.queue_free)


## Fenêtre sous la souris (null : aucune).
func hovered_pane() -> MapViewPane:
	if not is_visible_in_tree():
		return null
	var p := get_local_mouse_position()
	for pn in panes:
		if pn.visible and Rect2(pn.position, pn.size).has_point(p):
			return pn
	return null


## Pavé numérique (§ 4) quand la souris est sur une vue : 7 Dessus, 1 Avant,
## 3 Droite ; Ctrl : la vue opposée ; 5 : la 3D. Rend false sinon (les
## chiffres du pavé choisissent alors une case de la barre rapide).
func numpad(k: InputEventKey, pn: MapViewPane) -> bool:
	if pn == null or pn.view == null:
		return false
	var pl := ""
	match k.keycode:
		KEY_KP_7:
			pl = "dessous" if k.ctrl_pressed else "dessus"
		KEY_KP_1:
			pl = "arriere" if k.ctrl_pressed else "avant"
		KEY_KP_3:
			pl = "gauche" if k.ctrl_pressed else "droite"
		KEY_KP_5:
			# Bascule 3D / dernier plan de la fenêtre.
			if pn.plane() == "3d":
				set_pane_plane(pn, String(pn.get_meta("last_plane", pn.home_plane if pn.home_plane != "3d" else "avant")))
			else:
				var target := view_target(pn.view)
				var face := pn.plane()
				set_pane_plane(pn, "3d")
				show_3d_from(MapViewCube.target_dir(MapViewCube.net_corner(face, 1)), target)
			return true
		_:
			return false
	set_pane_plane(pn, pl, true)
	return true


## Centre de la carte (repère de la carte : pièces de tous les étages).
func map_center() -> Vector3:
	var bb := Rect2()
	var first := true
	for p in ed.doc.pieces:
		var r := MapGeom.bbox(ed.doc.room_poly(p))
		bb = r if first else bb.merge(r)
		first = false
	if first:
		bb = Rect2(0, 0, 20, 20)
	var top := ed.doc.floor_sol(ed.doc.floor_count() - 1) + ed.doc.floor_height(ed.doc.floor_count() - 1)
	return Vector3(bb.get_center().x, bb.get_center().y, top * 0.5)


## Point de la carte au milieu d'une vue (profondeur : le milieu de la carte).
func view_target(v: MapView) -> Vector3:
	var c := map_center()
	if v == null or v.plane == "3d":
		return c
	var p := MapView.point_of(v.plane, v.to_m(v.size * 0.5), MapView.depth_of(v.plane, c))
	if v.plane == "dessus":
		p.z = ed.doc.floor_sol(ed.floor_k)
	return p


## Clic sur le ViewCube d'une vue (§ 4) : face (bascule du plan), arête ou
## coin (la 3D vue de cette direction), maison, menu, façade suivante.
func cube_action(v: MapView, id: String) -> void:
	var pn := pane_of(v)
	if id.begins_with("f:"):
		if pn != null:
			set_pane_plane(pn, id.substr(2), true)
		return
	if id.begins_with("e:") or id.begins_with("c:"):
		show_3d_from(MapViewCube.target_dir(id), view_target(v))
		return
	match id:
		"home":
			if pn != null:
				set_pane_plane(pn, pn.home_plane, true)
				if pn.view is MapElevation:
					_frame_like_top.call_deferred(pn.view)
				elif pn.view == ed.canvas:
					ed.canvas.frame_all()
		"prev", "next":
			if pn != null:
				set_pane_plane(pn, MapViewCube.next_facade(pn.plane(), 1 if id == "next" else -1), true)
		"menu":
			if pn != null:
				_cube_menu(pn)


## La 3D vue de la direction `dir` (repère de la carte, vers la caméra),
## visant `target` : l'aperçu 3D (panneau flottant).
func show_3d_from(dir: Vector3, target: Vector3) -> void:
	var pv := ed.preview
	if pv == null:
		return
	# Une seule 3D : celle d'une fenêtre si elle existe, sinon le panneau flottant.
	if _pane_3d() == null and not pv.shown:
		pv.set_shown(true)
	var off := MapGeom.WORLD_OFFSET
	pv.world.rig.look_from(Vector3(dir.x, dir.z, dir.y), Vector3(target.x + off, target.z, target.y + off))
	pv._request_render()


var _menu: PopupMenu


## Menu ▾ du ViewCube : plan au choix, « Définir comme vue d'origine »,
## « Recadrer (Origine) ».
func _cube_menu(pn: MapViewPane) -> void:
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.name = "CubeMenu"
		add_child(_menu)
		_menu.id_pressed.connect(_on_cube_menu)
	_menu.clear()
	for i in MapView.PLANES.size():
		var pl: String = MapView.PLANES[i]
		_menu.add_radio_check_item(MapView.plane_name(pl), i)
		_menu.set_item_checked(i, pn.plane() == pl)
	_menu.add_radio_check_item("3D", 10)
	_menu.set_item_checked(_menu.get_item_index(10), pn.plane() == "3d")
	_menu.add_separator()
	_menu.add_item(Lang.t("Définir comme vue d'origine", "Set as home view"), 20)
	_menu.add_item(Lang.t("Recadrer (Origine)", "Frame (Home)"), 21)
	_menu.set_meta("pane", pn)
	_menu.reset_size()
	var c := pn.view.cube
	_menu.position = Vector2i(c.get_screen_position() + Vector2(c.size.x - _menu.size.x, c.size.y))
	_menu.popup()


func _on_cube_menu(i: int) -> void:
	var pn: MapViewPane = _menu.get_meta("pane")
	if not is_instance_valid(pn):
		return
	if i < MapView.PLANES.size():
		set_pane_plane(pn, MapView.PLANES[i], true)
	elif i == 10:
		set_pane_plane(pn, "3d")
	elif i == 20:
		pn.home_plane = pn.plane()
		ed.set_status(Lang.t("Vue d'origine de cette fenêtre : %s", "This window's home view: %s") % MapView.plane_name(pn.home_plane))
	elif i == 21:
		pn.view.frame_all()


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


## Touche pendant un glissement dans une élévation (verrou d'axe, valeur
## tapée, Échap). Vrai si prise.
func handle_drag_key(k: InputEventKey) -> bool:
	for v in elevations():
		var ev := v as MapElevation
		if ev.tools != null and ev.tools.dragging():
			return ev.tools.handle_key(k)
	return false


## Un glissement est-il en cours dans une élévation ?
func elevation_dragging() -> bool:
	return elevations().any(func(v): return (v as MapElevation).tools != null and (v as MapElevation).tools.dragging())


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
	save_soon()


## Rectangles des fenêtres et des séparateurs pour la disposition courante.
func compute() -> Dictionary:
	var a := views_rect()
	var g := SPLIT
	var mn := Vector2(EditorUi.px(MIN_VIEW.x), EditorUi.px(MIN_VIEW.y))
	var fx := clampf(rx, 0.0, 1.0)
	var fy := clampf(ry, 0.0, 1.0)
	# Bornes : chaque vue garde sa taille minimale (la moitié de la place si
	# elle manque).
	if a.size.x > g:
		var lo := minf((mn.x + g * 0.5) / a.size.x, 0.5)
		fx = clampf(fx, lo, 1.0 - lo)
	if a.size.y > g:
		var lo := minf((mn.y + g * 0.5) / a.size.y, 0.5)
		fy = clampf(fy, lo, 1.0 - lo)
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
	if panes.size() < 2 or pn == null:
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


# ------------------------------------------------------------------ dispositions, liaison, mémorisation

## Change de disposition (menu, Ctrl+Alt+Q) ; chaque fenêtre garde son plan
## si elle existe encore, les nouvelles prennent les plans par défaut.
func set_layout(id: String) -> void:
	if not LAYOUTS.has(id):
		return
	if id == layout_id:
		return
	setup(id)
	frame_all()
	save_soon()
	ed.set_status(Lang.t("Disposition : %s", "Layout: %s") % MapViewLayoutMenu._label(ORDER.find(id)))


## Réinitialiser : disposition par défaut, plans et proportions d'origine.
func reset_layout() -> void:
	rx = 0.5
	ry = 0.5
	for pn in panes:
		for v in elevations():
			(v as MapElevation).set_cut([], "aucune")
			(v as MapElevation).floors_mode = MapElevation.Floors.ALL
	var id := layout_id
	layout_id = ""
	setup(id)
	frame_all()
	save_soon()


func set_linked(on: bool) -> void:
	linked = on
	_link_seen = {}
	if on:
		_sync_from(active_view())
	_dock.queue_redraw()
	save_soon()


func set_shared_cut(on: bool) -> void:
	shared_cut = on
	save_soon()


## Coupe partagée : la même tranche pour les autres élévations de même direction.
func share_cut(src: MapElevation) -> void:
	if not shared_cut:
		return
	var axis := String(MapView.depth_axis(src.plane)[0])
	for v in elevations():
		var ev := v as MapElevation
		if ev != src and String(MapView.depth_axis(ev.plane)[0]) == axis and ev.plane != "dessous":
			ev.coupe = src.coupe.duplicate()
			ev.coupe_mode = src.coupe_mode
			ev.coupe_label = src.coupe_label
			ev.queue_redraw()


func _process(delta: float) -> void:
	if _save_t > 0.0:
		_save_t -= delta
		if _save_t <= 0.0:
			save_prefs()
	if linked:
		_link_step()


## Vues liées (D7) : la vue qui a bougé (zoom, déplacement) entraîne les
## autres vues orthographiques : même zoom, même centre sur l'axe partagé.
func _link_step() -> void:
	var list := views().filter(func(v): return v.plane != "3d" and v.is_visible_in_tree())
	var moved: MapView = null
	for v in list:
		var st := [v.zoom, v.origin, v.size]
		if _link_seen.get(v, []) != st:
			if _link_seen.has(v) and (moved == null or v == active_view()):
				moved = v
	if moved != null:
		_sync_from(moved)
	for v in list:
		_link_seen[v] = [v.zoom, v.origin, v.size]


func _sync_from(src: MapView) -> void:
	if src == null or src.plane == "3d" or src.size.x <= 0.0:
		return
	var c := MapView.point_of(src.plane, src.to_m(src.size * 0.5), 0.0)
	var shared := [String(MapView.h_axis(src.plane)[0]), String(MapView.v_axis(src.plane)[0])]
	for v in views():
		if v == src or v.plane == "3d" or v.size.x <= 0.0:
			continue
		var cur := MapView.point_of(v.plane, v.to_m(v.size * 0.5), 0.0)
		for axis in [String(MapView.h_axis(v.plane)[0]), String(MapView.v_axis(v.plane)[0])]:
			if axis in shared:
				match axis:
					"X":
						cur.x = c.x
					"Y":
						cur.y = c.y
					"Z":
						cur.z = c.z
		v.zoom = src.zoom
		v.origin = v.size * 0.5 - MapView.uv_of(v.plane, cur) * v.zoom
		v.queue_redraw()
		_link_seen[v] = [v.zoom, v.origin, v.size]


func save_soon() -> void:
	_save_t = 0.5


## État mémorisé (_editeur.cfg, clé « vues ») : disposition, plan et plan
## d'origine de chaque fenêtre, proportions, liaison, coupes, étages montrés.
## Ni le zoom ni le centre (chaque vue se recadre à l'ouverture d'une carte).
func state() -> Dictionary:
	var pl := []
	var homes := []
	var cuts := []
	var floors := []
	for pn in panes:
		pl.append(pn.plane())
		homes.append(pn.home_plane)
		var ev := pn.view as MapElevation
		cuts.append([ev.coupe.duplicate(), ev.coupe_mode] if ev != null and ev.coupe.size() == 2 else [])
		floors.append(int(ev.floors_mode) if ev != null else 0)
	return {"disposition": layout_id, "plans": pl, "origines": homes, "rx": snappedf(rx, 0.001), "ry": snappedf(ry, 0.001),
		"liees": linked, "coupe_partagee": shared_cut, "coupes": cuts, "etages": floors}


func save_prefs() -> void:
	_save_t = -1.0
	MapEditor.set_pref(PREF_KEY, state())


## Réglages relus (valeurs invalides ignorées) ; premier lancement : DEFAULT.
func apply_state(p: Dictionary) -> void:
	var id := String(p.get("disposition", DEFAULT))
	if not LAYOUTS.has(id):
		id = DEFAULT
	var num := func(v: Variant, d: float) -> float: return clampf(float(v), 0.05, 0.95) if (v is float or v is int) else d
	rx = num.call(p.get("rx"), 0.5)
	ry = num.call(p.get("ry"), 0.5)
	linked = bool(p.get("liees", true)) if p.get("liees") is bool else true
	shared_cut = bool(p.get("coupe_partagee", false)) if p.get("coupe_partagee") is bool else false
	var pl: Array = p.get("plans", []) if p.get("plans") is Array else []
	var planes := []
	for v in pl:
		planes.append(String(v) if v is String else "avant")
	layout_id = ""
	setup(id, planes)
	var homes: Array = p.get("origines", []) if p.get("origines") is Array else []
	for i in mini(homes.size(), panes.size()):
		if homes[i] is String and (String(homes[i]) in MapView.PLANES or homes[i] == "3d"):
			panes[i].home_plane = String(homes[i])
	var cuts: Array = p.get("coupes", []) if p.get("coupes") is Array else []
	var floors: Array = p.get("etages", []) if p.get("etages") is Array else []
	for i in panes.size():
		var ev := panes[i].view as MapElevation
		if ev == null:
			continue
		if i < cuts.size() and cuts[i] is Array and (cuts[i] as Array).size() == 2 and cuts[i][0] is Array and (cuts[i][0] as Array).size() == 2:
			var c: Array = cuts[i][0]
			if (c[0] is float or c[0] is int) and (c[1] is float or c[1] is int):
				ev.set_cut([float(c[0]), float(c[1])], String(cuts[i][1]) if cuts[i][1] is String else "perso")
		if i < floors.size() and (floors[i] is int or floors[i] is float):
			ev.floors_mode = clampi(int(floors[i]), 0, 2) as MapElevation.Floors
	_save_t = -1.0


## Bouton Disposition de la barre du haut : le menu, sous le bouton.
func open_menu(at: Vector2) -> void:
	if _menu_ui == null:
		_menu_ui = MapViewLayoutMenu.new()
		_menu_ui.layout = self
		add_child(_menu_ui)
		_menu_ui.popup_hide.connect(func():
			if ed.layout_button != null:
				ed.layout_button.set_pressed_no_signal(false))
	_menu_ui.open_at(at)


func menu_open() -> bool:
	return _menu_ui != null and _menu_ui.visible


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
	# Cadrage fait : rien à propager (liaison).
	for v in views():
		_link_seen[v] = [v.zoom, v.origin, v.size]


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
	if ev.plane == "avant" and absf(c.global_position.x - ev.global_position.x) < 1.0 and absf(c.size.x - ev.size.x) < 1.0:
		# Avant sous la vue Dessus : mêmes colonnes X à l'écran.
		ev.origin.x = c.origin.x
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
	t = t.left(1).to_upper() + t.substr(1)
	if linked and panes.size() > 1:
		t += Lang.t(" · vues liées", " · linked views")
	return t


func dock_redraw() -> void:
	if _dock != null:
		_dock.queue_redraw()
