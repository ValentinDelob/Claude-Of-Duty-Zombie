class_name MapCanvas
extends Control
## Vue de dessus de l'éditeur de cartes : grille de 1 m (règles en mètres),
## pièces, murs générés (grille du validateur), ouvertures, objets ; outils de
## pose avec aperçu vert / rouge et la raison d'un refus. Zoom : Ctrl + molette ;
## déplacement : clic milieu ou Espace + glisser ; aimantation (MapSnap) : grille
## 1 m, grille fine ou libre (touche G ; Maj inverse), aimants aux sommets et aux
## côtés en libre ; saisie au clavier de la longueur et de l'angle pendant le
## tracé ; formes de base (MapShapes) ; poignée de rotation (MapTransform).

const RULER := 20.0
const HANDLE := 7.0
const MIN_ZOOM := 4.0
const MAX_ZOOM := 120.0
const COL_BG := Color(0.1, 0.105, 0.115)
const COL_TERRAIN := Color(0.135, 0.14, 0.15)
const COL_GRID := Color(1, 1, 1, 0.045)
const COL_GRID5 := Color(1, 1, 1, 0.11)
const COL_WALL := Color(0.62, 0.62, 0.66)
const COL_VOID := Color(0.1, 0.16, 0.3, 0.55)
const COL_OK := Color(0.25, 0.95, 0.35)
const COL_BAD := Color(1.0, 0.25, 0.2)
const COL_SEL := Color(1.0, 0.85, 0.3)

var ed: MapEditor
var zoom := 18.0
var origin := Vector2(60, 50)
var mouse_m := Vector2.ZERO
var _pan := false
var _pan_from := Vector2.ZERO
var _space := false
## Opération de glissement en cours : {kind, start, ...}.
var drag: Dictionary = {}
## Points du polygone en cours de tracé.
var poly_pts := PackedVector2Array()
## Aperçu de pose (survol) : {ok, fr, en, obj}.
var preview: Dictionary = {}
## Message de refus affiché près du curseur.
var refusal := ""
var _refusal_t := 0.0
## Cases mises en évidence (problème choisi dans l'onglet Vérification).
var highlight: Array = []
var highlight_floor := -1
const COL_HOVER := Color(0.35, 0.9, 1.0)
## Survol à recalculer (une fois par image au plus, pas à chaque mouvement).
var _hover_dirty := false
## Aimantation (MapSnap) : mode (« grille », « fine », « libre »), pas de la
## grille fine, dernière grille utilisée (Maj en mode libre) ; mémorisés.
var snap_mode := "grille"
var fine_step := 0.5
var last_grid := "grille"
## Maj imposée (tests) : inverse le mode d'aimantation.
var invert_snap := false
## Nombre de points des cercles et ellipses, segments et ouverture du mur courbe.
var shape_points := MapShapes.DEFAULT_POINTS
var arc_segments := MapShapes.DEFAULT_SEGMENTS
var arc_opening := MapShapes.DEFAULT_OPENING
## Saisie au clavier pendant le tracé : {labels: [[fr, en], [fr, en]],
## values: ["", ""], i: champ courant}.
var entry: Dictionary = {}
## Élément modifié par le glissement en cours : exclu des aimants.
var _snap_exclude := ""
## Pixels de la poignée de rotation au-dessus de l'élément choisi.
const ROT_HANDLE_PX := 30.0


## Longueurs d'interface de la vue (règles, poignées, étiquettes, cotes) à la
## taille de l'interface de l'éditeur (EditorUi) ; le zoom du plan n'en dépend pas.
func _u(v: float) -> float:
	return EditorUi.px(v)


func _ruler() -> float:
	return EditorUi.px(RULER)


func _hsz() -> float:
	return EditorUi.px(HANDLE)


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		_hover_dirty = false
		ed.map_hovered(""))
	var m := String(MapEditor.pref("aimantation", "grille"))
	snap_mode = m if m in MapSnap.MODES else "grille"
	var fs := float(MapEditor.pref("pas_fin", 0.5))
	fine_step = fs if MapSnap.FINE_STEPS.any(func(x): return absf(float(x) - fs) < 0.001) else 0.5
	last_grid = "fine" if snap_mode == "fine" else "grille"


func _process(delta: float) -> void:
	if _refusal_t > 0.0:
		_refusal_t -= delta
		if _refusal_t <= 0.0:
			refusal = ""
			queue_redraw()
	if _hover_dirty:
		update_hover()


## Élément sous le curseur -> liste des objets (surlignée, bonne page).
## Seulement quand la liste est ouverte : sinon aucun coût.
func update_hover() -> void:
	_hover_dirty = false
	if not ed.object_list.expanded or _pan or not drag.is_empty():
		return
	var e := ed.element_at(mouse_m)
	ed.map_hovered(String(e.get("id", "")))


# ------------------------------------------------------------------ repères

func to_m(px: Vector2) -> Vector2:
	return (px - origin) / zoom


func to_px(m: Vector2) -> Vector2:
	return origin + m * zoom


## Mode d'aimantation appliqué maintenant (Maj inverse le mode choisi).
func mode_now() -> String:
	return MapSnap.effective(snap_mode, invert_snap or Input.is_key_pressed(KEY_SHIFT), last_grid)


func step() -> float:
	return MapSnap.step_of(mode_now(), fine_step)


## Rayon des aimants de la carte (m) : quelques pixels à l'écran.
func magnet_radius() -> float:
	return MapSnap.MAGNET_PX / zoom


## Point aimanté : grille du mode ; en libre, sommet ou côté proche d'une
## pièce, sinon le centimètre.
func snap(m: Vector2) -> Vector2:
	var mode := mode_now()
	if mode == "libre":
		var mg := MapSnap.magnet(ed.doc, ed.floor_k, m, magnet_radius(), _snap_exclude)
		return mg.p if not mg.is_empty() else MapGeom.round_cm(m)
	return MapSnap.on_step(m, mode, fine_step)


## G : mode d'aimantation suivant (grille 1 m -> fine -> libre), mémorisé.
func cycle_snap() -> void:
	set_snap_mode(MapSnap.next_mode(snap_mode))


## Maj+G : pas de la grille fine suivant (0,5 -> 0,25 -> 0,1 m).
func cycle_fine() -> void:
	fine_step = MapSnap.next_fine(fine_step)
	MapEditor.set_pref("pas_fin", fine_step)
	set_snap_mode("fine")


func set_snap_mode(mode: String) -> void:
	snap_mode = mode if mode in MapSnap.MODES else "grille"
	if snap_mode != "libre":
		last_grid = snap_mode
	MapEditor.set_pref("aimantation", snap_mode)
	ed.snap_changed()
	ed.set_status(Lang.t("Aimantation : %s (G pour changer ; Maj maintenu : inverse)", "Snapping: %s (G to change; hold Shift: invert)") % MapSnap.label(snap_mode, fine_step))
	_update_preview()
	queue_redraw()


## Angle libre (Alt maintenu, ou imposé par un test) : sinon les côtés et les
## murs tracés partent à 0, 45 ou 90°.
var free_angle := false


func angle_free() -> bool:
	return free_angle or Input.is_key_pressed(KEY_ALT)


## Point tracé depuis `from` (côté de polygone, mur) : sur la grille, sommet
## sur la grille et côté aimanté à un multiple de 45° sauf en angle libre ;
## sans grille, aimants de la carte puis côté à 15° près (Alt : libre).
func snap_from(from: Vector2, m: Vector2) -> Vector2:
	if mode_now() == "libre":
		return MapSnap.trace_free(ed.doc, ed.floor_k, from, m, magnet_radius(), angle_free(), _snap_exclude)
	return MapGeom.snap_angle(from, m, step(), angle_free())


## Bout du tracé en cours (mur au glisser, point suivant du polygone), ou le
## point saisi au clavier.
func trace_end() -> Vector2:
	var tool := String(_item().get("tool", ""))
	var p := _cursor_end(tool)
	if not entry.is_empty():
		return _entry_end(tool, p)
	return p


## Bout du tracé d'après le curseur seulement.
func _cursor_end(tool: String) -> Vector2:
	if tool == "wall" and drag.get("kind", "") == "create":
		return snap_from(drag.start, mouse_m)
	if tool == "room_poly" and not poly_pts.is_empty():
		return snap_from(poly_pts[-1], mouse_m)
	if tool == "room_rect" and drag.get("kind", "") == "create" and ed.place_rot == 45:
		var b := snap(mouse_m)
		return rect45_end(drag.start, b) if mode_now() == "grille" else b
	return snap(mouse_m)


# ------------------------------------------------------------------ saisie au clavier

## Un tracé est-il en cours (saisie au clavier possible) ?
func tracing() -> bool:
	var tool := String(_item().get("tool", ""))
	if tool == "room_poly":
		return not poly_pts.is_empty()
	return drag.get("kind", "") == "create" and tool in ["room_rect", "wall", "rect", "room_shape", "arc"]


## Champs de la saisie au clavier selon l'outil : [[fr, en], [fr, en]].
func entry_labels() -> Array:
	var it := _item()
	match String(it.get("tool", "")):
		"room_rect", "rect":
			return [["largeur", "width"], ["hauteur", "height"]]
		"room_shape":
			if String(it.make.get("forme", "")) == "cercle":
				return [["rayon", "radius"], ["points", "points"]]
			return [["largeur", "width"], ["hauteur", "height"]]
		"arc":
			return [["rayon", "radius"], ["ouverture", "opening"]]
	return [["longueur", "length"], ["angle", "angle"]]


## Valeur tapée du champ `i` (null si vide ou illisible).
func entry_value(i: int) -> Variant:
	if entry.is_empty() or i >= entry.values.size():
		return null
	var s := String(entry.values[i]).replace(",", ".")
	if s == "" or s == "-" or s == ".":
		return null
	return float(s) if s.is_valid_float() else null


func _open_entry() -> void:
	entry = {"labels": entry_labels(), "values": ["", ""], "i": 0}


## Bout du tracé d'après les valeurs tapées (les champs vides suivent le curseur).
func _entry_end(tool: String, cursor: Vector2) -> Vector2:
	var v0 = entry_value(0)
	var v1 = entry_value(1)
	match tool:
		"wall", "room_poly":
			var from: Vector2 = drag.start if tool == "wall" else poly_pts[-1]
			var d := cursor - from
			var length: float = absf(v0) if v0 != null else d.length()
			var ang: float = v1 if v1 != null else MapGeom.dir_angle(d)
			# Valeurs tapées : exactes (au millimètre ; 0° reste horizontal).
			return MapGeom.round_mm(MapGeom.polar(from, length, ang))
		"room_rect", "rect":
			var a: Vector2 = drag.start
			var d := cursor - a
			var sx := -1.0 if d.x < 0.0 else 1.0
			var sy := -1.0 if d.y < 0.0 else 1.0
			return a + Vector2(sx * (absf(v0) if v0 != null else absf(d.x)), sy * (absf(v1) if v1 != null else absf(d.y)))
		"room_shape":
			var a: Vector2 = drag.start
			var d := cursor - a
			if String(_item().make.get("forme", "")) == "cercle":
				if v1 != null:
					shape_points = clampi(roundi(v1), MapShapes.MIN_POINTS, MapShapes.MAX_POINTS)
				var r: float = absf(v0) if v0 != null else d.length()
				return a + (d.normalized() if d.length() > 0.001 else Vector2(1, 0)) * r
			var sx := -1.0 if d.x < 0.0 else 1.0
			var sy := -1.0 if d.y < 0.0 else 1.0
			return a + Vector2(sx * (absf(v0) if v0 != null else absf(d.x)), sy * (absf(v1) if v1 != null else absf(d.y)))
		"arc":
			var a: Vector2 = drag.start
			var d := cursor - a
			if v1 != null:
				arc_opening = clampf(absf(v1), 5.0, 360.0)
			var r: float = absf(v0) if v0 != null else d.length()
			return a + (d.normalized() if d.length() > 0.001 else Vector2(0, -1)) * r
	return cursor


## Caractère tapé (chiffre, virgule, point, moins) d'un évènement clavier, "" sinon.
static func _entry_char(k: InputEventKey) -> String:
	if k.unicode > 0:
		var ch := String.chr(k.unicode)
		return ch if ch in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ",", ".", "-"] else ""
	if k.keycode >= KEY_0 and k.keycode <= KEY_9:
		return str(k.keycode - KEY_0)
	if k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
		return str(k.keycode - KEY_KP_0)
	if k.keycode in [KEY_PERIOD, KEY_COMMA, KEY_KP_PERIOD]:
		return "."
	return ""


## Touche pendant l'édition (appelée par MapEditor avant ses raccourcis) :
## G (aimantation), saisie au clavier du tracé en cours (chiffres, Tab,
## Entrée, Retour arrière, Échap), + / - (points d'une forme, segments d'un
## mur courbe). -> true si la touche est prise.
func handle_key(k: InputEventKey) -> bool:
	if not k.pressed or k.ctrl_pressed or k.alt_pressed:
		return false
	if k.keycode == KEY_G and entry.is_empty():
		if k.shift_pressed:
			cycle_fine()
		else:
			cycle_snap()
		return true
	if not tracing():
		return false
	if entry.is_empty() and k.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT] and _adjusts_count():
		adjust_count(1 if k.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD] else -1)
		return true
	var ch := _entry_char(k)
	if ch == "-" and (entry.is_empty() or int(entry.i) == 0):
		ch = ""   # signe seulement dans le second champ (angle)
	if ch != "":
		if entry.is_empty():
			_open_entry()
		if ch == "." and String(entry.values[entry.i]).contains("."):
			return true
		entry.values[entry.i] = String(entry.values[entry.i]) + ch
		queue_redraw()
		return true
	match k.keycode:
		KEY_TAB:
			if entry.is_empty():
				_open_entry()
			entry.i = (int(entry.i) + 1) % 2
			queue_redraw()
			return true
		KEY_BACKSPACE:
			if entry.is_empty():
				return false
			var s := String(entry.values[entry.i])
			if s == "" and int(entry.i) > 0:
				entry.i = int(entry.i) - 1
			else:
				entry.values[entry.i] = s.left(s.length() - 1)
			queue_redraw()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if entry.is_empty():
				return false
			commit_entry()
			return true
		KEY_ESCAPE:
			if entry.is_empty():
				return false
			entry = {}
			queue_redraw()
			return true
	return false


## Entrée : le côté, le mur ou la forme tapés sont posés.
func commit_entry() -> void:
	var tool := String(_item().get("tool", ""))
	var end := trace_end()
	entry = {}
	if tool == "room_poly":
		if poly_pts.is_empty() or poly_pts[-1].distance_to(end) > 0.01:
			poly_pts.append(end)
		queue_redraw()
		return
	if drag.get("kind", "") == "create":
		_finish_create(end)


## Le nombre de points (formes) ou de segments (mur courbe) se règle-t-il ?
func _adjusts_count() -> bool:
	var it := _item()
	var tool := String(it.get("tool", ""))
	return tool == "arc" or (tool == "room_shape" and String(it.make.get("forme", "")) in ["cercle", "ellipse"])


## Molette ou + / - pendant le tracé : points d'un cercle ou d'une ellipse (3
## à 64), segments d'un mur courbe (1 à 64).
func adjust_count(d: int) -> void:
	if String(_item().get("tool", "")) == "arc":
		arc_segments = clampi(arc_segments + d, MapShapes.MIN_SEGMENTS, MapShapes.MAX_SEGMENTS)
		ed.set_status(Lang.t("Mur courbe : %d segments", "Curved wall: %d segments") % arc_segments)
	else:
		shape_points = clampi(shape_points + d, MapShapes.MIN_POINTS, MapShapes.MAX_POINTS)
		ed.set_status(Lang.t("Forme : %d points", "Shape: %d points") % shape_points)
	queue_redraw()


## Rectangle à 45° : `b` décalé d'une demi-case si besoin pour que les quatre
## sommets tombent sur la grille de 0,5 m.
static func rect45_end(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	if absf(fposmod(d.x + d.y, 1.0)) > 0.01 and absf(fposmod(d.x + d.y, 1.0) - 1.0) > 0.01:
		b.x += 0.5
	return b


## Contour d'un rectangle tourné de 45° dont `a` et `b` sont deux coins opposés.
static func rect45_poly(a: Vector2, b: Vector2) -> PackedVector2Array:
	var d := b - a
	var s := (d.x + d.y) * 0.5
	var t := (d.x - d.y) * 0.5
	return PackedVector2Array([a, a + Vector2(s, s), b, a + Vector2(t, -t)])


## Centre la vue sur un point (m).
func center_on(m: Vector2) -> void:
	origin = size * 0.5 - m * zoom
	queue_redraw()


## Cadre toute la carte de l'étage dans la vue.
func frame_all() -> void:
	var bb := Rect2()
	var first := true
	for p in ed.doc.pieces:
		var r := MapGeom.bbox(ed.doc.room_poly(p))
		bb = r if first else bb.merge(r)
		first = false
	if first:
		bb = Rect2(0, 0, 30, 20)
	bb = bb.grow(3.0)
	var avail := size - Vector2(_ruler() + _u(20), _ruler() + _u(90))
	zoom = clampf(minf(avail.x / maxf(bb.size.x, 1.0), avail.y / maxf(bb.size.y, 1.0)), MIN_ZOOM, 40.0)
	origin = Vector2.ONE * (_ruler() + _u(10)) + (avail - bb.size * zoom) * 0.5 - bb.position * zoom
	queue_redraw()


func show_refusal(r: Dictionary) -> void:
	refusal = MapRules.why(r)
	_refusal_t = 3.0
	ed.set_status(refusal, true)
	queue_redraw()


# ------------------------------------------------------------------ entrées

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		mouse_m = to_m(mm.position)
		if _pan:
			origin += mm.relative
		elif not drag.is_empty():
			_drag_update()
		else:
			_update_preview()
			_hover_dirty = true
		ed.show_cursor(mouse_m)
		queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		mouse_m = to_m(mb.position)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				if mb.ctrl_pressed:
					_zoom_at(mb.position, 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
				elif tracing() and _adjusts_count():
					# Pendant le tracé d'une forme : nombre de points (segments d'un mur courbe).
					adjust_count(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
				else:
					ed.cycle_hotbar(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and _space):
			_pan = mb.pressed
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel()
			if ed.tool() == "select":
				ed.select("")
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# Aperçu 3D : Ctrl + double-clic y place la caméra (MapPreviewPanel).
			if ed.preview != null and ed.preview.canvas_click(mb, mouse_m):
				accept_event()
				return
			grab_focus()
			if mb.pressed:
				_press(mb.double_click)
			else:
				_release()
			accept_event()
			queue_redraw()


## Espace maintenu (déplacement de la vue) ; appelé par l'éditeur.
func set_space(on: bool) -> void:
	_space = on
	if not on:
		_pan = false


func _zoom_at(px: Vector2, f: float) -> void:
	var m := to_m(px)
	zoom = clampf(zoom * f, MIN_ZOOM, MAX_ZOOM)
	origin = px - m * zoom
	queue_redraw()


func zoom_by(f: float) -> void:
	_zoom_at(size * 0.5, f)


## Annule le tracé ou le glissement en cours.
func cancel() -> void:
	if drag.get("kind", "") in ["move", "handle", "rotate"]:
		ed.doc.restore(drag.snap)
		ed.changed()
	drag = {}
	entry = {}
	_snap_exclude = ""
	poly_pts.clear()
	queue_redraw()


func _item() -> Dictionary:
	return ed.current_item()


func _press(double: bool) -> void:
	var it := _item()
	var tool := String(it.get("tool", "select"))
	var k := ed.floor_k
	# Tracé commencé d'un simple clic (sans glisser) : ce clic le termine.
	if drag.get("kind", "") == "create" and drag.get("sticky", false):
		_finish_create(trace_end())
		return
	var p := snap(mouse_m)
	match tool:
		"select":
			# Poignée de rotation, poignées de l'élément choisi, puis l'élément sous le curseur.
			var rh := rot_handle()
			if not rh.is_empty() and to_px(rh.p).distance_to(to_px(mouse_m)) <= _hsz() + 4.0:
				var sel := ed.doc.find(ed.selected)
				drag = {"kind": "rotate", "c": rh.c, "a0": (mouse_m - Vector2(rh.c)).angle(), "snap": ed.doc.snapshot(),
					"orig": sel.duplicate(true), "attached": ed.attached_to(sel), "moved": false, "deg": 0}
				return
			var h := _handle_at(mouse_m)
			if h >= 0:
				_snap_exclude = ed.selected
				drag = {"kind": "handle", "handle": h, "snap": ed.doc.snapshot(), "orig": ed.doc.find(ed.selected).duplicate(true), "moved": false}
				return
			var e := ed.element_at(mouse_m)
			ed.select(String(e.get("id", "")))
			if not e.is_empty():
				_snap_exclude = String(e.id)
				drag = {"kind": "move", "start": snap(mouse_m), "raw": mouse_m, "snap": ed.doc.snapshot(), "orig": e.duplicate(true), "moved": false,
					"attached": ed.attached_to(e)}
		"erase":
			var e := ed.element_at(mouse_m)
			if not e.is_empty():
				ed.delete_element(String(e.id))
		"room_rect", "wall", "rect", "room_shape", "arc":
			drag = {"kind": "create", "start": p}
		"room_poly":
			if poly_pts.size() >= 3 and (double or to_px(p).distance_to(to_px(poly_pts[0])) < 10.0):
				_finish_poly()
				return
			if not poly_pts.is_empty():
				p = snap_from(poly_pts[-1], mouse_m)
			if poly_pts.is_empty() or poly_pts[-1].distance_to(p) > 0.01:
				poly_pts.append(p)
			entry = {}
		"opening", "wall_item", "floor_item":
			_update_preview()
			if preview.is_empty():
				return
			if not preview.ok:
				show_refusal(preview)
				return
			ed.add_object(preview.obj, k)


func _release() -> void:
	if drag.is_empty():
		return
	var kind := String(drag.kind)
	if kind == "create":
		if drag.get("sticky", false):
			return
		var end := trace_end()
		if entry.is_empty() and to_px(end).distance_to(to_px(drag.start)) < 4.0:
			# Simple clic : le tracé suit le curseur jusqu'au clic suivant (ou la
			# saisie au clavier : longueur, Tab, angle, Entrée).
			drag["sticky"] = true
			return
		if not entry.is_empty():
			return   # saisie au clavier en cours : Entrée termine
		_finish_create(end)
	elif kind in ["move", "handle", "rotate"]:
		if drag.moved:
			ed.push_undo_snapshot(drag.snap)
			ed.changed()
		drag = {}
		_snap_exclude = ""


## Termine le tracé en cours (glisser, clic-clic ou saisie au clavier) en `end`.
func _finish_create(end: Vector2) -> void:
	var it := _item()
	var res := _creation(it, drag.start, end)
	drag = {}
	entry = {}
	queue_redraw()
	if res.is_empty():
		return
	if not res.ok:
		show_refusal(res)
		return
	ed.add_object(res.obj, ed.floor_k)


## Élément créé par un glissement de `a` à `b` (pièce, mur, pilier, escalier, piège).
func _creation(it: Dictionary, a: Vector2, b: Vector2) -> Dictionary:
	var k := ed.floor_k
	match String(it.tool):
		"room_rect":
			var r := Rect2(a, Vector2.ZERO).expand(b)
			var poly := MapGeom.rect_poly(r) if ed.place_rot != 45 else rect45_poly(a, b)
			var res := MapRules.check_room(ed.doc, k, poly)
			res["obj"] = {"contour": MapGeom.poly_arr(poly)}
			return res
		"wall":
			var res := MapRules.check_wall(a, b)
			var o: Dictionary = it.make.duplicate(true)
			o["a"] = MapGeom.arr(a)
			o["b"] = MapGeom.arr(b)
			res["obj"] = o
			return res
		"rect":
			var r := Rect2(a, Vector2.ZERO).expand(b)
			var o: Dictionary = it.make.duplicate(true)
			o["rect"] = MapGeom.rect_arr(r)
			if o.type == "escalier":
				var d := b - a
				o["monte"] = ("e" if d.x > 0 else "o") if absf(d.x) > absf(d.y) else ("s" if d.y > 0 else "n")
			var res := MapRules.check_rect(ed.doc, k, String(o.type), r)
			res["obj"] = o
			return res
		"room_shape":
			# Forme de base : un polygone éditable qui garde ses paramètres (« forme »).
			var forme := MapShapes.from_drag(String(it.make.get("forme", "cercle")), a, b, shape_points)
			if forme.is_empty() or float(forme.rx) < 0.05:
				return {"ok": false, "fr": "forme trop petite", "en": "shape too small"}
			var poly := MapShapes.outline(forme)
			var res := MapRules.check_room(ed.doc, k, poly)
			res["obj"] = {"contour": MapGeom.poly_arr(poly), "forme": forme}
			return res
		"arc":
			var o := MapShapes.arc_from_drag(it.make, a, b, arc_segments, arc_opening)
			var res := MapRules.check_arc(o)
			res["obj"] = o
			return res
	return {}


func _finish_poly() -> void:
	var poly := poly_pts.duplicate()
	poly_pts.clear()
	var res := MapRules.check_room(ed.doc, ed.floor_k, poly)
	if not res.ok:
		show_refusal(res)
		return
	ed.add_object({"contour": MapGeom.poly_arr(poly)}, ed.floor_k)


## Fin du polygone au clavier (Entrée).
func finish_polygon() -> void:
	if poly_pts.size() >= 3:
		_finish_poly()


func undo_point() -> void:
	if not poly_pts.is_empty():
		poly_pts.remove_at(poly_pts.size() - 1)
		queue_redraw()


## Aperçu de pose au survol (ouvertures, objets muraux et au sol).
func _update_preview() -> void:
	preview = {}
	var it := _item()
	var tool := String(it.get("tool", ""))
	var k := ed.floor_k
	if not tool in ["opening", "wall_item", "floor_item"]:
		return
	var o: Dictionary = it.make.duplicate(true)
	if it.get("rotates", false):
		o["rot"] = ed.place_rot
	var res := {}
	match tool:
		"opening":
			# Mur trop court pour la largeur par défaut (côté d'un cercle...) :
			# la porte est réduite pour y tenir (1 m au moins).
			res = MapRules.place_opening(ed.doc, k, String(o.type), mouse_m, MapRules.opening_width(o), "", true)
			if res.ok:
				o["position"] = res.position
				if res.has("largeur"):
					o["largeur"] = float(res.largeur)
				if o.type in ["porte", "debris"]:
					o["prix"] = ed.default_door_price()
		"wall_item":
			res = MapRules.place_wall_item(ed.doc, k, o, mouse_m)
			if res.ok:
				o["position"] = res.position
				MapRules.apply_wall(o, res)
		"floor_item":
			# Sans grille : là où est le curseur (au centimètre).
			var free := mode_now() == "libre"
			res = MapRules.place_floor_item(ed.doc, k, o, MapGeom.round_cm(mouse_m) if free else mouse_m, "", not free)
			if res.ok:
				o["position"] = res.position
	if not res.ok:
		o["position"] = MapGeom.arr(snap(mouse_m))
		if tool == "wall_item":
			o["mur"] = "n"
			o.erase("angle")
	res["obj"] = o
	preview = res


# ------------------------------------------------------------------ glissements

func _drag_update() -> void:
	var kind := String(drag.kind)
	if kind == "create":
		return
	var orig: Dictionary = drag.orig
	var e := ed.doc.find(String(orig.id))
	if e.is_empty():
		drag = {}
		return
	if kind == "move":
		var delta := snap(mouse_m) - Vector2(drag.start)
		# Ouverture ou objet mural : il suit le curseur (déplacement depuis le
		# début du glisser, au centimètre) et s'aimante lui-même le long de son
		# mur ; un déplacement arrondi au mètre en x et en y l'écarterait du mur
		# (côté d'un cercle, mur en biais).
		var wall_bound := String(orig.get("type", "")) in MapRules.ouvertures_types() or MapCatalog.tool_of(orig) == "wall_item"
		if mode_now() == "libre" or wall_bound:
			# Sans grille : au centimètre ; une pièce se colle par un sommet au
			# sommet ou au côté d'une autre pièce (aimant).
			delta = MapGeom.round_cm(mouse_m - Vector2(drag.raw))
			if orig.has("contour"):
				delta = MapSnap.room_delta(ed.doc, ed.floor_k, MapGeom.poly(orig.contour), delta, magnet_radius(), String(orig.id))
		var res := ed.try_move(orig, drag.attached, delta, drag.snap)
		if res.ok:
			drag.moved = drag.moved or delta.length() > 0.001
		elif delta.length() > 0.001:
			refusal = MapRules.why(res)
			_refusal_t = 1.5
	elif kind == "handle":
		var res := ed.try_handle(orig, int(drag.handle), snap(mouse_m), drag.snap)
		if res.ok:
			drag.moved = true
		else:
			refusal = MapRules.why(res)
			_refusal_t = 1.5
	elif kind == "rotate":
		# Poignée de rotation : pas de 15°, au degré près avec Alt.
		var c: Vector2 = drag.c
		var deg := rad_to_deg(angle_difference(float(drag.a0), (mouse_m - c).angle()))
		deg = roundf(deg) if angle_free() else snappedf(deg, MapTransform.STEP)
		if absf(deg - float(drag.deg)) < 0.001:
			return
		var res := MapTransform.apply(ed.doc, orig, drag.attached, c, deg, drag.snap)
		if res.ok:
			drag.moved = true
			drag.deg = deg
			ed.moved_live()
			ed.set_status(Lang.t("Rotation : %d°", "Rotation: %d°") % MapGeom.norm_deg(deg))
		else:
			refusal = MapRules.why(res)
			_refusal_t = 1.5


## Poignées de l'élément choisi : points (m).
func handles() -> PackedVector2Array:
	var e := ed.doc.find(ed.selected)
	var out := PackedVector2Array()
	if e.is_empty() or int(e.get("etage", 0)) != ed.floor_k:
		return out
	if e.has("contour"):
		var poly := ed.doc.room_poly(e)
		if MapGeom.is_axis_rect(poly) and not e.has("forme"):
			var r := MapGeom.bbox(poly)
			return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
				Vector2(r.get_center().x, r.position.y), Vector2(r.end.x, r.get_center().y), Vector2(r.get_center().x, r.end.y), Vector2(r.position.x, r.get_center().y)])
		return poly
	if e.has("rect"):
		if MapGeom.rot_of(e) != 0:
			return MapRaster.rect_poly(e)
		var r := MapGeom.rect_of(e.rect)
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if String(e.get("type", "")) == "mur":
		return PackedVector2Array([MapGeom.v2(e.a), MapGeom.v2(e.b)])
	return out


## Poignée de rotation de l'élément choisi : {p (m), c (centre de rotation)},
## {} si l'élément ne tourne pas (objets muraux : ils suivent leur mur).
func rot_handle() -> Dictionary:
	var e := ed.doc.find(ed.selected)
	if e.is_empty() or int(e.get("etage", 0)) != ed.floor_k or not MapTransform.can_rotate(e):
		return {}
	var bb := MapGeom.bbox(ed.doc.room_poly(e)) if e.has("contour") else MapRules.footprint_rect(e)
	return {"p": Vector2(bb.get_center().x, bb.position.y - EditorUi.px(ROT_HANDLE_PX) / zoom), "c": MapTransform.pivot(ed.doc, e)}


func _handle_at(m: Vector2) -> int:
	var hs := handles()
	for i in hs.size():
		if to_px(hs[i]).distance_to(to_px(m)) <= _hsz() + 2.0:
			return i
	return -1


# ------------------------------------------------------------------ dessin

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var tl := to_px(Vector2.ZERO)
	draw_rect(Rect2(tl.max(Vector2.ZERO), size - tl.max(Vector2.ZERO)), COL_TERRAIN)
	_draw_grid()
	var doc := ed.doc
	var k := ed.floor_k
	var font := UiStyle.font("body")
	# Étage du dessous en transparence.
	if ed.ghost_below and k > 0:
		for p in doc.rooms_on(k - 1):
			var poly := _px_poly(doc.room_poly(p))
			_fill(poly, Color(0.6, 0.7, 1.0, 0.07))
			draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.6, 0.7, 1.0, 0.35), 1.0)
	# Pièces (couleur de leur zone).
	for p in doc.rooms_on(k):
		var poly := _px_poly(doc.room_poly(p))
		if poly.size() >= 3:
			_fill(poly, ed.zone_color(String(p.get("zone", ""))))
	# Grille du validateur : murs générés, vides, ouvertures.
	_draw_cells(k)
	# Escaliers de l'étage du dessous : ils arrivent ici.
	if k > 0:
		for o in doc.objects_on(k - 1):
			if String(o.get("type", "")) == "escalier":
				_draw_object(o, font, 0.45)
	# Objets.
	for o in doc.objects_on(k):
		_draw_object(o, font, 1.0)
	for o in doc.openings_on(k):
		_draw_opening(o, font)
	# Noms des pièces.
	if zoom >= 8.0:
		for p in doc.rooms_on(k):
			var poly := doc.room_poly(p)
			var c := to_px(MapGeom.centroid(poly))
			var nm := String(p.get("nom", ""))
			var fs := EditorUi.fs(13 if zoom < 20.0 else 15)
			var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, c + Vector2(-w * 0.5, -2), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, c + Vector2(-w * 0.5, -2), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
			var zn := ed.doc.zone_name(String(p.get("zone", "")))
			if zn != nm:
				var wz := font.get_string_size(zn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11)).x
				draw_string_outline(font, c + Vector2(-wz * 0.5, _u(13)), zn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), 3, Color(0, 0, 0, 0.8))
				draw_string(font, c + Vector2(-wz * 0.5, _u(13)), zn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), Color(1, 1, 1, 0.6))
	# Éléments devenus invalides (après un déplacement de pièce...).
	for eid in ed.invalid:
		var e := doc.find(eid)
		if e.is_empty() or int(e.get("etage", 0)) != k:
			continue
		var r := _elem_rect_px(e)
		draw_rect(r.grow(3), COL_BAD, false, 2.0)
		draw_string(font, r.position + Vector2(r.size.x + _u(4), _u(12)), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(16), COL_BAD)
	# Sélection et poignées.
	var sel := doc.find(ed.selected)
	if not sel.is_empty() and int(sel.get("etage", 0)) == k:
		var outline := _outline_of(sel)
		if not outline.is_empty():
			var poly := _px_poly(outline)
			draw_polyline(poly + PackedVector2Array([poly[0]]), COL_SEL, 2.5 if sel.has("contour") else 2.0)
		else:
			draw_rect(_elem_rect_px(sel).grow(3), COL_SEL, false, 2.0)
		for h in handles():
			draw_rect(Rect2(to_px(h) - Vector2.ONE * _hsz() * 0.5, Vector2.ONE * _hsz()), COL_SEL)
			draw_rect(Rect2(to_px(h) - Vector2.ONE * _hsz() * 0.5, Vector2.ONE * _hsz()), Color.BLACK, false, 1.0)
		# Poignée de rotation (pas de 15°, Alt : au degré près).
		var rh := rot_handle()
		if not rh.is_empty():
			var hp := to_px(rh.p)
			var bb := MapGeom.bbox(outline) if not outline.is_empty() else MapRules.footprint_rect(sel)
			draw_line(to_px(Vector2(bb.get_center().x, bb.position.y)), hp, Color(COL_SEL, 0.7), 1.0)
			draw_circle(hp, _hsz() * 0.8, COL_SEL)
			draw_arc(hp, _hsz() * 0.45, -PI * 0.8, PI * 0.5, 10, Color.BLACK, 1.5)
			if drag.get("kind", "") == "rotate":
				draw_circle(to_px(drag.c), 3.0, COL_SEL)
				_label_at(font, hp + Vector2(_u(12), -_u(6)), "%d°" % MapGeom.norm_deg(float(drag.get("deg", 0))))
	# Élément survolé (dans la liste des objets ou sur la carte) : contour lumineux.
	var hov := doc.find(ed.hover_id) if ed.hover_id != "" else {}
	if not hov.is_empty() and int(hov.get("etage", 0)) == k:
		_draw_glow(hov)
	# Problème choisi dans l'onglet Vérification.
	if highlight_floor == k:
		for c in highlight:
			var cp := to_px(MapGeom.cell_center(c))
			draw_rect(Rect2(cp - Vector2.ONE * zoom * 0.25, Vector2.ONE * zoom * 0.5).grow(1.0), Color(1, 0.2, 0.2, 0.9), false, 2.0)
	_draw_tool(font)
	# Aperçu 3D : repère de sa caméra (MapPreviewPanel).
	if ed.preview != null:
		ed.preview.draw_on_canvas(self)
	_draw_rulers(font)


## Contour exact d'un élément quand il n'est pas un rectangle droit (pièce,
## rectangle ou décor tourné, objet contre un mur en biais) ; vide sinon.
func _outline_of(e: Dictionary) -> PackedVector2Array:
	if e.has("contour"):
		return ed.doc.room_poly(e)
	if e.has("rect") and MapGeom.rot_of(e) != 0:
		return MapRaster.rect_poly(e)
	var tool := MapCatalog.tool_of(e)
	if tool == "floor_item" and MapRaster.free_rot(e) and MapCatalog.rotates(e):
		return MapRaster.floor_poly(e)
	if tool == "wall_item" and MapGeom.item_oblique(e):
		return MapRules.wall_item_poly(e)
	return PackedVector2Array()


## Contour lumineux (halo en trois traits) d'un élément, sans bouger la vue.
func _draw_glow(e: Dictionary) -> void:
	var outline := _outline_of(e)
	for i in 3:
		var w := 7.0 - i * 2.5
		var a := 0.18 + i * 0.3
		if not outline.is_empty():
			var poly := _px_poly(outline)
			draw_polyline(poly + PackedVector2Array([poly[0]]), Color(COL_HOVER, a), w)
		else:
			draw_rect(_elem_rect_px(e).grow(4 + (2 - i) * 2), Color(COL_HOVER, a), false, w)
	var light := MapCatalog.light_mount(e)
	if light != "" and e.has("portee"):
		draw_arc(to_px(MapRules.footprint_rect(e).get_center()), float(e.portee) * zoom, 0, TAU, 48, Color(COL_HOVER, 0.35), 1.5)


## Polygone rempli seulement s'il se découpe en triangles (un tracé en cours
## aplati, un losange de taille nulle : rien, sans erreur du moteur).
func _fill(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
		draw_colored_polygon(pts, col)


func _px_poly(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		out.append(to_px(v))
	return out


func _elem_rect_px(e: Dictionary) -> Rect2:
	var r := Rect2()
	if e.has("contour"):
		r = MapGeom.bbox(ed.doc.room_poly(e))
	elif String(e.get("type", "")) in MapRules.ouvertures_types():
		var p := MapGeom.v2(e.position)
		var w := MapRules.opening_width(e)
		r = Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w))
	else:
		r = MapRules.footprint_rect(e)
	return Rect2(to_px(r.position), r.size * zoom)


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
	# Grille fine (mode « fine ») : traits légers au pas choisi, si lisibles.
	if snap_mode == "fine" and fine_step * zoom >= 8.0 and fine_step < 0.99:
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
	# Axes : bord du terrain (x = 0, y = 0).
	var o := to_px(Vector2.ZERO)
	draw_line(Vector2(o.x, 0), Vector2(o.x, size.y), Color(0.9, 0.5, 0.3, 0.5), 1.5)
	draw_line(Vector2(0, o.y), Vector2(size.x, o.y), Color(0.9, 0.5, 0.3, 0.5), 1.5)


func _draw_rulers(font: Font) -> void:
	draw_rect(Rect2(0, 0, size.x, _ruler()), Color(0.07, 0.07, 0.08, 0.95))
	draw_rect(Rect2(0, 0, _ruler(), size.y), Color(0.07, 0.07, 0.08, 0.95))
	var every := 1.0
	for e in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0]:
		every = e
		if e * zoom >= _u(34.0):
			break
	var m0 := to_m(Vector2.ZERO)
	var m1 := to_m(size)
	var x := floorf(m0.x / every) * every
	while x <= m1.x:
		var px := to_px(Vector2(x, 0)).x
		if px > _ruler():
			draw_line(Vector2(px, _ruler() - _u(6)), Vector2(px, _ruler()), Color(1, 1, 1, 0.5), 1.0)
			draw_string(font, Vector2(px + 2, _u(13)), "%d" % roundi(x), HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), Color(1, 1, 1, 0.65))
		x += every
	var y := floorf(m0.y / every) * every
	while y <= m1.y:
		var py := to_px(Vector2(0, y)).y
		if py > _ruler():
			draw_line(Vector2(_ruler() - _u(6), py), Vector2(_ruler(), py), Color(1, 1, 1, 0.5), 1.0)
			draw_string(font, Vector2(1, py - 2), "%d" % roundi(y), HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), Color(1, 1, 1, 0.65))
		y += every
	draw_rect(Rect2(0, 0, _ruler(), _ruler()), Color(0.07, 0.07, 0.08))
	draw_string(font, Vector2(_u(3), _u(13)), "m", HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(11), Color(1, 1, 1, 0.5))
	# Position du curseur sur les règles.
	var cp := to_px(mouse_m)
	draw_line(Vector2(cp.x, 0), Vector2(cp.x, _ruler()), COL_SEL, 1.0)
	draw_line(Vector2(0, cp.y), Vector2(_ruler(), cp.y), COL_SEL, 1.0)


func _draw_cells(k: int) -> void:
	var r := ed.raster()
	if r == null or k >= r.v.floors.size():
		return
	var f: MapValidator.Floor = r.v.floors[k]
	var m0 := to_m(Vector2.ZERO)
	var m1 := to_m(size)
	var i0 := maxi(0, floori(m0.x / MapGeom.CELL) - 1)
	var i1 := mini(f.w - 1, ceili(m1.x / MapGeom.CELL) + 1)
	var j0 := maxi(0, floori(m0.y / MapGeom.CELL) - 1)
	var j1 := mini(f.h - 1, ceili(m1.y / MapGeom.CELL) + 1)
	var cs := zoom * MapGeom.CELL
	var dc: Dictionary = r.v.diag_cells[k] if k < r.v.diag_cells.size() else {}
	for j in range(j0, j1 + 1):
		var run_kind := -1
		var run_start := 0
		for i in range(i0, i1 + 2):
			var kd := f.kind[j * f.w + i] if i <= i1 else -1
			var shown := kd if kd in [MapValidator.K.MUR, MapValidator.K.TREMIE, MapValidator.K.PORTE, MapValidator.K.DEBRIS, MapValidator.K.FENETRE] else -1
			if shown == MapValidator.K.MUR and f.key[j * f.w + i].begins_with("decor#"):
				shown = -1
			if shown >= 0 and dc.has(Vector2i(i, j)):
				shown = -1   # mur en biais : dessiné en vrai mur oblique (plus bas)
			if shown != run_kind:
				if run_kind >= 0:
					var p := to_px(MapGeom.cell_center(Vector2i(run_start, j))) - Vector2.ONE * cs * 0.5
					var rect := Rect2(p, Vector2(cs * (i - run_start), cs))
					match run_kind:
						MapValidator.K.MUR:
							draw_rect(rect, COL_WALL)
						MapValidator.K.TREMIE:
							draw_rect(rect, COL_VOID)
						MapValidator.K.PORTE:
							draw_rect(rect, Color(1.0, 0.67, 0.0))
						MapValidator.K.DEBRIS:
							draw_rect(rect, Color(0.67, 0.4, 0.15))
						MapValidator.K.FENETRE:
							draw_rect(rect, Color(0.1, 0.45, 1.0))
				run_kind = shown
				run_start = i
	_draw_obliques(r.v, k)


## Couleur d'une ouverture dessinée (porte, débris, fenêtre, passage).
const OPENING_COLORS := {"porte": Color(1.0, 0.67, 0.0), "porte_courant": Color(1.0, 0.67, 0.0), "debris": Color(0.67, 0.4, 0.15),
	"fenetre": Color(0.1, 0.45, 1.0), "passage": Color(0.16, 0.17, 0.19)}


## Pavé d'un mur (ou d'une ouverture) en biais, en pixels.
func _slab_px(a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var t := (b - a).normalized()
	var n := Vector2(-t.y, t.x) * half
	return _px_poly(PackedVector2Array([a + n, b + n, b - n, a - n]))


## Murs en biais de l'étage : vrais murs obliques (comme en jeu), jonctions
## arrondies, ouvertures posées dessus.
func _draw_obliques(v: MapValidator, k: int) -> void:
	if k >= v.oblique_walls.size():
		return
	var view := Rect2(Vector2.ZERO, size).grow(zoom)
	for w in v.oblique_walls[k]:
		var poly := _slab_px(w.a, w.b, float(w.half))
		if not MapGeom.bbox(poly).intersects(view):
			continue
		_fill(poly, COL_WALL)
		if String(w.get("kind", "")) == "pilier":
			continue   # pilier tourné : pavé plein, sans bouts arrondis
		for e in [w.a, w.b]:
			draw_circle(to_px(e), float(w.half) * zoom, COL_WALL)
	for key in v.diag_open:
		var o: Dictionary = v.diag_open[key]
		if int(o.floor) != k:
			continue
		var p: Vector2 = o.p
		var t: Vector2 = o.t
		var hw := float(o.w) * 0.5
		var poly := _slab_px(p - t * hw, p + t * hw, float(o.half) + 0.02)
		_fill(poly, OPENING_COLORS.get(String(o.type), COL_OK))


func _draw_object(o: Dictionary, font: Font, alpha: float) -> void:
	var t := String(o.get("type", ""))
	var it := MapCatalog.item_for(o)
	var r := MapRules.footprint_rect(o)
	var rp := Rect2(to_px(r.position), r.size * zoom)
	# Hors de la vue : rien à dessiner (cartes de 2000 objets).
	if not rp.grow(8.0).intersects(Rect2(Vector2.ZERO, size)):
		return
	if t in ["escalier", "piege"] and MapGeom.rot_of(o) != 0:
		_draw_rot_rect(o, it, alpha)
		return
	match t:
		"pilier", "mur", "mur_courbe":
			return   # dessinés par les cases de mur (vrais murs obliques hors de la grille)
		"escalier":
			draw_rect(rp, Color(0.55, 0.35, 0.65, 0.55 * alpha))
			var d := MapGeom.dir_vec(String(o.get("monte", "n")))
			var along := absf(d.x) > 0.5
			var n := maxi(2, int((r.size.x if along else r.size.y) / 0.3))
			for i in n + 1:
				var f := float(i) / n
				if along:
					draw_line(Vector2(rp.position.x + rp.size.x * f, rp.position.y), Vector2(rp.position.x + rp.size.x * f, rp.end.y), Color(1, 1, 1, 0.35 * alpha), 1.0)
				else:
					draw_line(Vector2(rp.position.x, rp.position.y + rp.size.y * f), Vector2(rp.end.x, rp.position.y + rp.size.y * f), Color(1, 1, 1, 0.35 * alpha), 1.0)
			var c := rp.get_center()
			var half := (rp.size.x if along else rp.size.y) * 0.4
			draw_line(c - d * half, c + d * half, Color(1, 1, 1, 0.9 * alpha), 2.0)
			draw_line(c + d * half, c + d * half - d.rotated(0.5) * 8.0, Color(1, 1, 1, 0.9 * alpha), 2.0)
			draw_line(c + d * half, c + d * half - d.rotated(-0.5) * 8.0, Color(1, 1, 1, 0.9 * alpha), 2.0)
			return
		"piege":
			draw_rect(rp, Color(1.0, 0.3, 0.3, 0.22 * alpha))
			draw_rect(rp, Color(1.0, 0.35, 0.3, 0.8 * alpha), false, 1.5)
			var s := minf(minf(rp.size.x, rp.size.y), 48.0)
			MapIcons.draw(self, it, Rect2(rp.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)))
			return
	var col: Color = it.get("color", Color.WHITE)
	var mount := MapCatalog.light_mount(o)
	if (t == "prefab" or (t == "luminaire" and mount != "mur")) and MapRaster.free_rot(o):
		# Décor tourné au degré près : emprise tournée, icône, flèche du devant.
		var poly := _px_poly(MapRaster.floor_poly(o))
		var block := MapCatalog.blocking(o)
		_fill(poly, Color(col.darkened(0.35), (0.55 if block != "non" else 0.3) * alpha))
		var c := MapGeom.centroid(poly)
		var si := maxf(12.0, minf(rp.size.x, rp.size.y) * 0.7)
		MapIcons.draw(self, it, Rect2(c - Vector2(si, si) * 0.5, Vector2(si, si)))
		draw_polyline(poly + PackedVector2Array([poly[0]]), Color(col.lightened(0.2), 0.9 * alpha), 1.5 if block != "non" else 1.0)
		if zoom >= 8.0:
			var dv := Vector2(0, 1).rotated(deg_to_rad(float(MapGeom.rot_of(o))))
			var edge := (poly[2] + poly[3]) * 0.5
			draw_line(edge - dv * 7.0, edge, Color(1, 1, 1, 0.8 * alpha), 2.0)
			draw_line(edge, edge - dv.rotated(0.6) * 5.0, Color(1, 1, 1, 0.8 * alpha), 2.0)
			draw_line(edge, edge - dv.rotated(-0.6) * 5.0, Color(1, 1, 1, 0.8 * alpha), 2.0)
		if t == "luminaire" and o.get("id", "") == ed.selected:
			draw_arc(c, float(o.get("portee", 8.0)) * zoom, 0, TAU, 48, Color(col, 0.4), 1.0)
		return
	if t == "prefab" or (t == "luminaire" and mount != "mur"):
		# Empreinte au sol (couleur du prefab, hachures s'il bloque), icône et
		# flèche du devant (rotation R).
		var block := MapCatalog.blocking(o)
		draw_rect(rp, Color(col.darkened(0.35), (0.55 if block != "non" else 0.3) * alpha))
		if block == "solide" and zoom >= 10.0:
			var step_px := maxf(6.0, zoom * 0.35)
			var x := rp.position.x - rp.size.y
			while x < rp.end.x:
				var a := Vector2(maxf(x, rp.position.x), rp.position.y + maxf(0.0, rp.position.x - x))
				var b := Vector2(minf(x + rp.size.y, rp.end.x), rp.position.y + minf(rp.size.y, rp.end.x - x))
				draw_line(a, b, Color(0, 0, 0, 0.25 * alpha), 1.0)
				x += step_px
		if mount == "plafond":
			draw_circle(rp.get_center(), maxf(4.0, minf(rp.size.x, rp.size.y) * 0.45), Color(col, 0.25 * alpha))
		var si := maxf(12.0, minf(minf(rp.size.x, rp.size.y) * 0.9, 56.0))
		MapIcons.draw(self, it, Rect2(rp.get_center() - Vector2(si, si) * 0.5, Vector2(si, si)))
		draw_rect(rp, Color(col.lightened(0.2), 0.9 * alpha), false, 1.5 if block != "non" else 1.0)
		if MapCatalog.rotates(o) and zoom >= 8.0:
			# Devant de l'objet : côté +y (sud) à rot = 0, tourné avec lui.
			var dv := Vector2(0, 1).rotated(deg_to_rad(float(o.get("rot", 0))))
			var edge := rp.get_center() + dv * Vector2(rp.size.x, rp.size.y) * 0.5
			draw_line(edge - dv * 7.0, edge, Color(1, 1, 1, 0.8 * alpha), 2.0)
			draw_line(edge, edge - dv.rotated(0.6) * 5.0, Color(1, 1, 1, 0.8 * alpha), 2.0)
			draw_line(edge, edge - dv.rotated(-0.6) * 5.0, Color(1, 1, 1, 0.8 * alpha), 2.0)
		if t == "luminaire" and o.get("id", "") == ed.selected:
			draw_arc(rp.get_center(), float(o.get("portee", 8.0)) * zoom, 0, TAU, 48, Color(col, 0.4), 1.0)
		return
	# Objet contre un mur en biais : emprise tournée comme le mur.
	if MapGeom.item_oblique(o) and MapCatalog.tool_of(o) == "wall_item":
		var poly := _px_poly(MapRules.wall_item_poly(o))
		_fill(poly, Color(0, 0, 0, 0.35 * alpha))
		var c := MapGeom.centroid(poly)
		var so := maxf(12.0, minf(rp.size.x, rp.size.y) * 0.8)
		if t == "luminaire":
			so = maxf(14.0, zoom * 0.9)
		MapIcons.draw(self, it, Rect2(c - Vector2(so, so) * 0.5, Vector2(so, so)))
		draw_polyline(poly + PackedVector2Array([poly[0]]), Color(col, 0.8 * alpha), 1.0)
		if t == "luminaire" and o.get("id", "") == ed.selected:
			draw_arc(c, float(o.get("portee", 8.0)) * zoom, 0, TAU, 48, Color(col, 0.4), 1.0)
		return
	# Objets muraux et au sol : icône dans leur emprise.
	draw_rect(rp, Color(0, 0, 0, 0.35 * alpha))
	var s := maxf(12.0, minf(rp.size.x, rp.size.y) * 1.1)
	if t == "lampe" or t == "luminaire":
		s = maxf(14.0, zoom * 0.9)
	MapIcons.draw(self, it, Rect2(rp.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)))
	draw_rect(rp, Color(col, 0.8 * alpha), false, 1.0)
	if t == "luminaire" and o.get("id", "") == ed.selected:
		draw_arc(rp.get_center(), float(o.get("portee", 8.0)) * zoom, 0, TAU, 48, Color(col, 0.4), 1.0)


## Escalier ou zone de piège tournés : contour, marches et flèche de montée
## (escalier) ou éclair (piège) dans le repère du rectangle.
func _draw_rot_rect(o: Dictionary, it: Dictionary, alpha: float) -> void:
	var poly := MapRaster.rect_poly(o)
	var px := _px_poly(poly)
	var rot := deg_to_rad(float(MapGeom.rot_of(o)))
	var r := MapGeom.rect_of(o.rect)
	var c := r.get_center()
	if String(o.type) == "piege":
		_fill(px, Color(1.0, 0.3, 0.3, 0.22 * alpha))
		draw_polyline(px + PackedVector2Array([px[0]]), Color(1.0, 0.35, 0.3, 0.8 * alpha), 1.5)
		var s := minf(minf(r.size.x, r.size.y) * zoom, 48.0)
		MapIcons.draw(self, it, Rect2(to_px(c) - Vector2(s, s) * 0.5, Vector2(s, s)))
		return
	_fill(px, Color(0.55, 0.35, 0.65, 0.55 * alpha))
	var d := MapGeom.dir_vec(String(o.get("monte", "n")))
	var along := absf(d.x) > 0.5
	var length := r.size.x if along else r.size.y
	var n := maxi(2, int(length / 0.3))
	var u := (Vector2(1, 0) if along else Vector2(0, 1)).rotated(rot)
	var lat := (Vector2(0, 1) if along else Vector2(1, 0)).rotated(rot) * ((r.size.y if along else r.size.x) * 0.5)
	for i in n + 1:
		var q := c + u * (-length * 0.5 + length * i / n)
		draw_line(to_px(q - lat), to_px(q + lat), Color(1, 1, 1, 0.35 * alpha), 1.0)
	var dv := d.rotated(rot)
	var half := length * 0.4
	var a := to_px(c - dv * half)
	var b := to_px(c + dv * half)
	var dp := (b - a).normalized()
	draw_line(a, b, Color(1, 1, 1, 0.9 * alpha), 2.0)
	draw_line(b, b - dp.rotated(0.5) * 8.0, Color(1, 1, 1, 0.9 * alpha), 2.0)
	draw_line(b, b - dp.rotated(-0.5) * 8.0, Color(1, 1, 1, 0.9 * alpha), 2.0)


func _draw_opening(o: Dictionary, font: Font) -> void:
	var t := String(o.get("type", ""))
	if not t in ["porte", "debris"] or zoom < 10.0:
		if t == "porte_courant" and zoom >= 10.0:
			var p := to_px(MapGeom.v2(o.position))
			MapIcons._bolt(self, p, _u(14.0), Color(0.1, 0.1, 0.1))
		return
	var p := to_px(MapGeom.v2(o.position))
	var s := str(int(o.get("prix", 0)))
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(12)).x
	draw_string_outline(font, p + Vector2(-w * 0.5, _u(4)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(12), 4, Color(0, 0, 0, 0.9))
	draw_string(font, p + Vector2(-w * 0.5, _u(4)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(12), Color(1.0, 0.9, 0.5))


## Étiquette sur fond sombre (mesures du tracé).
func _label_at(font: Font, p: Vector2, lbl: String) -> void:
	draw_string_outline(font, p, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), 4, Color.BLACK)
	draw_string(font, p, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), Color.WHITE)


## Longueur et direction du côté ou du mur en cours de tracé (« 4,24 m · 45° » :
## degrés depuis l'est, dans le sens trigonométrique, comme à la saisie au
## clavier), avec « angle libre » quand Alt est maintenu.
func _trace_label(font: Font, a: Vector2, b: Vector2) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var fr := not Lang.is_en()
	var lbl := "%s m · %s°" % [MapRules._m(snappedf(d.length(), 0.01), fr), MapRules._m(snappedf(MapGeom.dir_angle(d), 0.1), fr)]
	if angle_free():
		lbl += Lang.t(" (angle libre)", " (free angle)")
	_label_at(font, to_px(b) + Vector2(_u(12), -_u(10)), lbl)


## Champ de saisie au clavier près du curseur : « longueur [4,5] · angle [30] ».
func _draw_entry(font: Font) -> void:
	if entry.is_empty():
		return
	var fr := not Lang.is_en()
	var parts := PackedStringArray()
	for i in 2:
		var lb: Array = entry.labels[i]
		var val := String(entry.values[i])
		if fr:
			val = val.replace(".", ",")
		parts.append("%s %s" % [String(lb[0] if fr else lb[1]), ("[%s▏]" % val) if i == int(entry.i) else ("[%s]" % val)])
	var txt := "  ·  ".join(parts) + Lang.t("   (Tab : champ suivant, Entrée : poser, Échap)", "   (Tab: next field, Enter: place, Esc)")
	var p := to_px(mouse_m) + Vector2(_u(16), -_u(30))
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13)).x
	p.x = minf(p.x, size.x - w - _u(12))
	p.y = maxf(p.y, _ruler() + _u(18))
	draw_rect(Rect2(p + Vector2(-_u(6), -_u(15)), Vector2(w + _u(12), _u(21))), Color(0.05, 0.08, 0.12, 0.94))
	draw_rect(Rect2(p + Vector2(-_u(6), -_u(15)), Vector2(w + _u(12), _u(21))), COL_SEL, false, 1.0)
	draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), Color(1, 0.95, 0.8))


func _draw_tool(font: Font) -> void:
	var it := _item()
	var tool := String(it.get("tool", "select"))
	var col := COL_OK
	var msg := ""
	if drag.get("kind", "") == "create":
		var end := trace_end()
		var res := _creation(it, drag.start, end)
		if not res.is_empty():
			col = COL_OK if res.ok else COL_BAD
			msg = "" if res.ok else MapRules.why(res)
			var a := to_px(drag.start)
			var b := to_px(end)
			if tool == "wall":
				draw_line(a, b, Color(col, 0.8), maxf(3.0, zoom * 0.5))
				_trace_label(font, drag.start, end)
			elif tool == "room_shape":
				# Aperçu de la forme (points réglables à la molette ou avec + / -).
				var forme: Dictionary = res.get("obj", {}).get("forme", {})
				var q := MapShapes.outline(forme) if not forme.is_empty() else PackedVector2Array()
				if q.size() >= 3:
					var pts := _px_poly(q)
					_fill(pts, Color(col, 0.2))
					draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.0)
					for v in pts:
						draw_circle(v, 2.5, col)
				var fr := not Lang.is_en()
				var lbl := ""
				match String(forme.get("type", "")):
					"cercle":
						draw_line(a, b, Color(col, 0.6), 1.0)
						lbl = Lang.t("rayon %s m · %d points", "radius %s m · %d points") % [MapRules._m(snappedf(float(forme.rx), 0.01), fr), int(forme.points)]
					"ellipse":
						lbl = Lang.t("%s × %s m · %d points", "%s × %s m · %d points") % [MapRules._m(float(forme.rx) * 2.0, fr), MapRules._m(float(forme.ry) * 2.0, fr), int(forme.points)]
					_:
						lbl = "%s × %s m" % [MapRules._m(float(forme.get("rx", 0.0)) * 2.0, fr), MapRules._m(float(forme.get("ry", 0.0)) * 2.0, fr)]
				_label_at(font, b + Vector2(_u(10), -_u(8)), lbl)
			elif tool == "arc":
				var o: Dictionary = res.get("obj", {})
				var q := MapShapes.wall_arc(o)
				var pts := _px_poly(q)
				draw_polyline(pts, Color(col, 0.85), maxf(3.0, zoom * float(o.get("epaisseur", 0.5))))
				draw_line(a, b, Color(col, 0.5), 1.0)
				var fr := not Lang.is_en()
				_label_at(font, b + Vector2(_u(10), -_u(8)), Lang.t("rayon %s m · %s° · %d segments", "radius %s m · %s° · %d segments") % [
					MapRules._m(snappedf(float(o.get("rayon", 0.0)), 0.01), fr), MapRules._m(float(o.get("ouverture", 0.0)), fr), int(o.get("segments", 1))])
			elif tool == "room_rect" and ed.place_rot == 45:
				var pts := _px_poly(rect45_poly(drag.start, end))
				_fill(pts, Color(col, 0.2))
				draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.0)
				var q := rect45_poly(drag.start, end)
				var lbl := "%s × %s m · 45°" % [MapRules._m(q[0].distance_to(q[1]), not Lang.is_en()), MapRules._m(q[0].distance_to(q[3]), not Lang.is_en())]
				_label_at(font, b + Vector2(_u(10), -_u(8)), lbl)
			else:
				var r := Rect2(a, Vector2.ZERO).expand(b)
				draw_rect(r, Color(col, 0.2))
				draw_rect(r, col, false, 2.0)
				var sz := (end - Vector2(drag.start)).abs()
				var lbl := "%s × %s m" % [MapRules._m(sz.x, not Lang.is_en()), MapRules._m(sz.y, not Lang.is_en())]
				_label_at(font, b + Vector2(_u(10), -_u(8)), lbl)
	elif tool == "room_poly" and not poly_pts.is_empty():
		var end := trace_end()
		var pts := _px_poly(poly_pts)
		pts.append(to_px(end))
		var test := poly_pts.duplicate()
		test.append(end)
		var res := MapRules.check_room(ed.doc, ed.floor_k, test) if test.size() >= 3 else {"ok": true}
		col = COL_OK if res.ok else COL_BAD
		if test.size() >= 3:
			_fill(pts, Color(col, 0.15))
		draw_polyline(pts, col, 2.0)
		for q in pts:
			draw_circle(q, 4.0, col)
		draw_arc(to_px(poly_pts[0]), 10.0, 0, TAU, 20, Color(1, 1, 1, 0.6), 1.5)
		_trace_label(font, poly_pts[-1], end)
	elif tool in ["opening", "wall_item", "floor_item"] and not preview.is_empty():
		var o: Dictionary = preview.obj
		col = COL_OK if preview.ok else COL_BAD
		if not preview.ok:
			msg = MapRules.why(preview)
		if tool == "opening" and preview.has("dir"):
			# Ouverture sur un mur en biais : tournée comme le mur.
			var t := MapGeom.v2(preview.dir)
			var p := MapGeom.v2(o.position)
			var hw := MapRules.opening_width(o) * 0.5
			var poly := _slab_px(p - t * hw, p + t * hw, MapGeom.WALL_HALF + 0.05)
			_fill(poly, Color(col, 0.55))
			draw_polyline(poly + PackedVector2Array([poly[0]]), col, 2.0)
		elif tool == "opening":
			var p := to_px(MapGeom.v2(o.position))
			var w := MapRules.opening_width(o) * zoom
			var horiz := bool(preview.get("horizontal", true))
			var r := Rect2(p - (Vector2(w, zoom * 0.5) if horiz else Vector2(zoom * 0.5, w)) * 0.5, Vector2(w, zoom * 0.5) if horiz else Vector2(zoom * 0.5, w))
			draw_rect(r.grow(2), Color(col, 0.55))
			draw_rect(r.grow(2), col, false, 2.0)
		elif MapGeom.item_oblique(o) and tool == "wall_item":
			_draw_object(o, font, 0.8)
			var poly := _px_poly(MapRules.wall_item_poly(o))
			draw_polyline(poly + PackedVector2Array([poly[0]]), col, 2.0)
		else:
			_draw_object(o, font, 0.8)
			var r := MapRules.footprint_rect(o)
			draw_rect(Rect2(to_px(r.position), r.size * zoom).grow(2), col, false, 2.0)
	if refusal != "" and msg == "":
		msg = refusal
		col = COL_BAD
	if msg != "":
		var p := to_px(mouse_m) + Vector2(_u(16), _u(22))
		var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13)).x
		p.x = minf(p.x, size.x - w - _u(12))
		draw_rect(Rect2(p + Vector2(-_u(6), -_u(15)), Vector2(w + _u(12), _u(21))), Color(0.15, 0.02, 0.02, 0.92))
		draw_rect(Rect2(p + Vector2(-_u(6), -_u(15)), Vector2(w + _u(12), _u(21))), COL_BAD, false, 1.0)
		draw_string(font, p, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), Color(1, 0.85, 0.8))
	# Curseur aimanté (bout du tracé en cours : grille et angle).
	var sp := to_px(trace_end())
	draw_line(sp - Vector2(6, 0), sp + Vector2(6, 0), Color(1, 1, 1, 0.5), 1.0)
	draw_line(sp - Vector2(0, 6), sp + Vector2(0, 6), Color(1, 1, 1, 0.5), 1.0)
	# Aimant de la carte (mode libre) : sommet (carré) ou côté (rond).
	if mode_now() == "libre" and entry.is_empty():
		var mg := MapSnap.magnet(ed.doc, ed.floor_k, mouse_m, magnet_radius(), _snap_exclude)
		if not mg.is_empty():
			var mp := to_px(mg.p)
			if String(mg.kind) == "sommet":
				draw_rect(Rect2(mp - Vector2(5, 5), Vector2(10, 10)), Color(0.35, 0.9, 1.0), false, 2.0)
			else:
				draw_arc(mp, 5.0, 0, TAU, 14, Color(0.35, 0.9, 1.0), 2.0)
	_draw_entry(font)
