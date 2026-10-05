class_name MapCanvas
extends MapView
## Vue de dessus de l'éditeur de cartes : grille de 1 m (règles en mètres),
## pièces, murs générés (grille du validateur), ouvertures, objets ; outils de
## pose avec aperçu vert / rouge et la raison d'un refus. Zoom : Ctrl + molette ;
## déplacement : clic milieu ou Espace + glisser ; aimantation (MapSnap) : grille
## 1 m, grille fine ou libre (touche G ; Maj inverse), aimants aux sommets et aux
## côtés en libre ; saisie au clavier de la longueur et de l'angle pendant le
## tracé ; formes de base (MapShapes) ; poignée de rotation (MapTransform) ;
## sélection multiple (Maj + clic, rectangle de gauche à droite : éléments
## dedans, de droite à gauche : éléments touchés) et glissement, rotation du
## groupe (MapGroup) ; clic droit : menu (MapContextMenu) ou annulation.
## Repères, zoom, grille et règles : MapView (plan « dessus »).

const HANDLE := 7.0
const COL_BG := Color(0.1, 0.105, 0.115)
const COL_TERRAIN := Color(0.135, 0.14, 0.15)
## Repère de l'origine (x = 0, y = 0) : discret.
const COL_ORIGIN := Color(0.9, 0.55, 0.35, 0.22)
const COL_WALL := Color(0.62, 0.62, 0.66)
const COL_VOID := Color(0.1, 0.16, 0.3, 0.55)
const COL_OK := Color(0.25, 0.95, 0.35)
const COL_BAD := Color(1.0, 0.25, 0.2)

## Opération de glissement en cours : {kind, start, ...}.
var drag: Dictionary = {}
## Points du polygone en cours de tracé.
var poly_pts := PackedVector2Array()
## Outils tracés en polygone, clic après clic : pièce polygone et objet
## polygone (format 9 : barrière invisible).
const POLY_TOOLS := ["room_poly", "poly"]
## Aperçu de pose (survol) : {ok, fr, en, obj}.
var preview: Dictionary = {}
## Message de refus affiché près du curseur.
var refusal := ""
## Zones d'un refus d'escalier (MapRules.check_stair) : [{floor, cells, role}].
var refusal_marks: Array = []
## Éléments d'une action de groupe refusée, à la place refusée (MapGroup.named) :
## entourés de rouge le temps du message.
var refusal_elems: Array = []
## Rectangle de sélection (docs/MAP_AUTHORING.md § 2) : à partir de ce nombre
## de pixels, un appui glissé trace un rectangle (sinon : un clic).
const BAND_PX := 4.0
const COL_WINDOW := Color(0.35, 0.65, 1.0)
const COL_CROSSING := Color(0.4, 0.95, 0.5)
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
## Format 14 : poignées d'échelle et anneau Z du décor choisi (MapGizmoTop).
var gizmo: MapGizmoTop
## Vue dessinée hors écran (capture du plan pour Claude, MapAgentLink,
## `offscreen` de MapView) : étage `floor_override` (-1 : celui de l'éditeur).
var floor_override := -1
## Souris sur la vue (Suppr n'agit sur un sommet que s'il est survolé).
var mouse_inside := false
## Élément choisi à l'appui précédent : le double-clic qui ajoute un point
## vise son contour (le premier clic a pu le désélectionner ou choisir le voisin).
var _prev_sel := ""
## Aide affichée au survol d'un sommet ou d'une poignée « + » ("vertex", "plus").
var _point_hint := ""


func _hsz() -> float:
	return EditorUi.px(HANDLE)


func _ready() -> void:
	clip_contents = true
	gizmo = MapGizmoTop.new(self)
	if offscreen:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		_hover_dirty = false
		mouse_inside = false
		ed.map_hovered(""))
	var m := String(MapEditor.pref("aimantation", "grille"))
	snap_mode = m if m in MapSnap.MODES else "grille"
	var fs := float(MapEditor.pref("pas_fin", 0.5))
	fine_step = fs if MapSnap.FINE_STEPS.any(func(x): return absf(float(x) - fs) < 0.001) else 0.5
	last_grid = "fine" if snap_mode == "fine" else "grille"


func _process(delta: float) -> void:
	if offscreen:
		return
	if _refusal_t > 0.0:
		_refusal_t -= delta
		if _refusal_t <= 0.0:
			refusal = ""
			refusal_marks = []
			refusal_elems = []
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


# ------------------------------------------------------------------ aimantation

## Maj imposée pour la sélection (tests) : Maj + clic, Maj + glisser.
var shift_select := false


## Maj tenue AU MOMENT DE L'APPUI : sélection multiple (Maj + clic : ajouter /
## retirer, Maj + glisser : rectangle qui ajoute). Pendant un glissement
## commencé sans Maj, Maj garde son rôle : inverser l'aimantation.
func shift_held() -> bool:
	return shift_select or Input.is_key_pressed(KEY_SHIFT)


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
	if tool in POLY_TOOLS and not poly_pts.is_empty():
		return snap_from(poly_pts[-1], mouse_m)
	if tool == "room_rect" and drag.get("kind", "") == "create" and ed.place_rot == 45:
		var b := snap(mouse_m)
		return rect45_end(drag.start, b) if mode_now() == "grille" else b
	return snap(mouse_m)


# ------------------------------------------------------------------ saisie au clavier

## Un tracé est-il en cours (saisie au clavier possible) ?
func tracing() -> bool:
	var tool := String(_item().get("tool", ""))
	if tool in POLY_TOOLS:
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
	@warning_ignore("incompatible_ternary")
	return float(s) if s.is_valid_float() else null


func _open_entry() -> void:
	entry = {"labels": entry_labels(), "values": ["", ""], "i": 0}


## Bout du tracé d'après les valeurs tapées (les champs vides suivent le curseur).
func _entry_end(tool: String, cursor: Vector2) -> Vector2:
	var v0: Variant = entry_value(0)
	var v1: Variant = entry_value(1)
	match tool:
		"wall", "room_poly", "poly":
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
## mur courbe), Suppr sur un sommet survolé ou saisi (ce point seul).
## -> true si la touche est prise.
func handle_key(k: InputEventKey) -> bool:
	if not k.pressed or k.ctrl_pressed or k.alt_pressed:
		return false
	# Format 14 : valeur tapée pendant un geste d'échelle ou de rotation.
	if drag.get("kind", "") in ["scale", "ring"]:
		return gizmo.key(k)
	# Suppr sur un sommet survolé ou saisi d'un contour libre : ce point seul.
	if k.keycode == KEY_DELETE and not k.echo and delete_point_key():
		return true
	# X / Y pendant un glissement : verrouille l'axe (la même touche le libère).
	if k.keycode in [KEY_X, KEY_Y] and drag.get("kind", "") in ["move", "gmove"] and entry.is_empty():
		var ax := "X" if k.keycode == KEY_X else "Y"
		drag["lock"] = "" if String(drag.get("lock", "")) == ax else ax
		_drag_update()
		queue_redraw()
		return true
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
	if tool in POLY_TOOLS:
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


## En-tête de la vue Dessus : l'étage affiché.
func header_sub() -> String:
	return Lang.t("Étage %d", "Floor %d") % ed.floor_k


## Puces : les coupes des élévations (traits pointillés de cette vue), le zoom.
func header_chips() -> Array:
	var out := []
	var cuts: Array = ed.views.cuts() if ed.views != null else []
	if cuts.is_empty():
		out.append({"id": "cuts", "text": Lang.t("Coupes : aucune", "Cuts: none")})
	else:
		var c: MapElevation = cuts[0]
		out.append({"id": "cuts", "text": Lang.t("Coupe %s : %s", "%s cut: %s") % [MapView.plane_name(c.plane), c.cut_text()], "hl": true})
	out.append_array(super())
	return out


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
	# Marge du bas : la barre rapide posée sur la vue (pas quand elle est ancrée).
	var docked := ed.views != null and ed.views.docked()
	var avail := size - Vector2(_ruler() + _u(20), _ruler() + _u(20 if docked else 90))
	zoom = clampf(minf(avail.x / maxf(bb.size.x, 1.0), avail.y / maxf(bb.size.y, 1.0)), MIN_ZOOM, 40.0)
	origin = Vector2.ONE * (_ruler() + _u(10)) + (avail - bb.size * zoom) * 0.5 - bb.position * zoom
	queue_redraw()


func show_refusal(r: Dictionary) -> void:
	refusal = MapRules.why(r)
	# Escalier : zones en cause (départ, arrivée, trémie, cases fautives).
	refusal_marks = r.get("marks", [])
	_refusal_t = 3.0
	ed.set_status(refusal, true)
	queue_redraw()


# ------------------------------------------------------------------ entrées

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		mouse_m = to_m(mm.position)
		mouse_inside = true
		if _pan:
			origin += mm.relative
		elif not drag.is_empty():
			_drag_update()
		else:
			_update_preview()
			_hover_dirty = true
			_update_point_hint()
		mouse_default_cursor_shape = cursor_at(mm.position)
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
			# Tracé, glissement, capture en cours : le clic droit les annule ;
			# sinon le menu du clic droit (MapContextMenu).
			if busy():
				cancel()
			elif not offscreen:
				# Sur un sommet ou un côté du contour choisi : « Supprimer ce
				# point », « Ajouter un point ici » en tête du menu.
				var pt := point_target(mouse_m)
				var eid := String(pt.id) if not pt.is_empty() else String(ed.element_at(mouse_m).get("id", ""))
				ed.open_context_menu(get_screen_position() + mb.position, mouse_m, eid, pt)
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


## Un tracé, un glissement, une saisie ou une capture est-il en cours ? (le
## clic droit les annule au lieu d'ouvrir le menu).
func busy() -> bool:
	return not drag.is_empty() or not poly_pts.is_empty() or not entry.is_empty() or (ed.prefab_tools != null and ed.prefab_tools.capturing)


## Annule le tracé ou le glissement en cours.
func cancel() -> void:
	if drag.get("kind", "") in ["scale", "ring"]:
		ed.panels.live_scale(false)
	if drag.get("kind", "") in ["move", "handle", "rotate", "gmove", "grotate", "scale", "ring"]:
		ed.send_live("")
		ed.doc.restore(drag.snap)
		ed.changed()
	drag = {}
	entry = {}
	_snap_exclude = ""
	poly_pts.clear()
	if ed.prefab_tools != null:
		ed.prefab_tools.cancel_capture()
	queue_redraw()


func _item() -> Dictionary:
	return ed.current_item()


func _press(double: bool) -> void:
	var it := _item()
	var tool := String(it.get("tool", "select"))
	var k := ed.floor_k
	# Format 10 : rectangle autour du décor à grouper en prefab de la carte.
	if ed.prefab_tools != null and ed.prefab_tools.capturing:
		drag = {"kind": "capture", "start": mouse_m}
		return
	# Tracé commencé d'un simple clic (sans glisser) : ce clic le termine.
	if drag.get("kind", "") == "create" and drag.get("sticky", false):
		_finish_create(trace_end())
		return
	var p := snap(mouse_m)
	var prev_sel := _prev_sel
	if not double:
		_prev_sel = ed.selected
	match tool:
		"select":
			# Maj : un clic ajoute ou retire l'élément de la sélection, un glissé
			# trace un rectangle qui y ajoute (décidé au relâché / au mouvement).
			if shift_held():
				drag = {"kind": "band", "start": mouse_m, "add": true, "click": String(ed.element_at(mouse_m).get("id", ""))}
				return
			# Double-clic sur un côté du contour choisi : un point y est ajouté.
			if double and _double_click_insert([prev_sel, ed.selected]):
				return
			# Format 14 : poignées d'échelle, cadenas, anneau Z du décor choisi.
			if gizmo.press(to_px(mouse_m)):
				return
			# Poignée de rotation, poignées de l'élément choisi, puis l'élément sous le curseur.
			var rh := rot_handle()
			if not rh.is_empty() and rh.get("group", false) and to_px(rh.p).distance_to(to_px(mouse_m)) <= _hsz() + 4.0:
				# Groupe : rotation autour du centre du groupe (pas de 15°, Alt : au degré).
				drag = {"kind": "grotate", "c": rh.c, "a0": (mouse_m - Vector2(rh.c)).angle(), "snap": ed.doc.snapshot(),
					"all": MapGroup.movers(ed.doc, ed.group), "moved": false, "deg": 0}
				return
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
			# Poignée « + » au milieu d'un côté : glissée, elle ajoute un point.
			var ph := plus_at(mouse_m)
			if not ph.is_empty():
				_snap_exclude = ed.selected
				drag = {"kind": "handle", "insert": int(ph.edge), "raw": mouse_m, "snap": ed.doc.snapshot(),
					"orig": ed.doc.find(ed.selected).duplicate(true), "moved": false}
				return
			# Traits de coupe des élévations : leurs poignées (§ 3.2).
			var ch := _cut_handle_at(to_px(mouse_m))
			if not ch.is_empty():
				drag = {"kind": "cut", "ev": ch.ev, "i": ch.i}
				return
			# Flèches d'axe de l'élément choisi : glisser sur un seul axe (§ 6.1).
			var ax := arrow_at(to_px(mouse_m))
			if ax != "" and ed.group.size() >= 2:
				_begin_group_move("", ax)
				return
			if ax != "":
				var sel2 := ed.doc.find(ed.selected)
				_snap_exclude = ed.selected
				drag = {"kind": "move", "start": snap(mouse_m), "raw": mouse_m, "snap": ed.doc.snapshot(), "orig": sel2.duplicate(true), "moved": false,
					"attached": ed.attached_to(sel2), "lock": ax}
				return
			var e := ed.element_at(mouse_m)
			# Élément d'un groupe choisi : tout le groupe glisse (un simple clic
			# sans bouger le choisit seul, au relâché).
			if not e.is_empty() and ed.group.size() >= 2 and ed.group.has(String(e.id)):
				_begin_group_move(String(e.id), "")
				return
			# Appui sur le vide : rectangle de sélection (un simple clic désélectionne).
			if e.is_empty():
				drag = {"kind": "band", "start": mouse_m, "add": false, "click": ""}
				return
			# Reclic : un simple clic (sans glisser, pas un double-clic) sur
			# l'élément déjà choisi seul le désélectionne au relâché, comme
			# dans les élévations et la 3D ; glissé, il est déplacé.
			var reclick := not double and ed.selected == String(e.get("id", "")) and ed.group.is_empty()
			ed.select(String(e.get("id", "")))
			if not e.is_empty():
				_snap_exclude = String(e.id)
				drag = {"kind": "move", "start": snap(mouse_m), "raw": mouse_m, "snap": ed.doc.snapshot(), "orig": e.duplicate(true), "moved": false,
					"attached": ed.attached_to(e), "reclick": reclick}
		"erase":
			var e := ed.element_at(mouse_m)
			if not e.is_empty():
				ed.delete_element(String(e.id))
		"room_rect", "wall", "rect", "room_shape", "arc":
			drag = {"kind": "create", "start": p}
		"room_poly", "poly":
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


## Glissement du groupe choisi (MapGroup.move) : `click` : l'élément appuyé
## (choisi seul si le groupe n'a pas bougé au relâché) ; `lock` : flèche d'axe.
func _begin_group_move(click: String, lock: String) -> void:
	drag = {"kind": "gmove", "start": snap(mouse_m), "raw": mouse_m, "snap": ed.doc.snapshot(), "all": MapGroup.movers(ed.doc, ed.group),
		"ids": ed.group.duplicate(), "moved": false, "click": click, "lock": lock}


## Rectangle de sélection relâché (`r`, m) : de gauche à droite, les éléments
## entièrement dedans ; de droite à gauche, ceux qu'il touche ; Maj : ajoutés
## à la sélection. Rend les éléments pris.
func finish_band(r: Rect2, crossing: bool, add: bool) -> Array:
	var got := MapGroup.in_rect(ed.doc, ed.floor_k, r, crossing)
	var ids := ed.sel_ids() if add else []
	for id in got:
		if not ids.has(id):
			ids.append(id)
	ed.select_many(ids)
	if got.is_empty() and not add:
		ed.set_status(Lang.t("Rectangle : aucun élément %s", "Rectangle: no element %s") % (Lang.t("touché", "touched") if crossing else Lang.t("entièrement dedans", "entirely inside")))
	return got


## Un rectangle commencé en `start` prend-il les éléments touchés (tracé de
## droite à gauche jusqu'à la souris) ?
func band_crossing_from(start: Vector2) -> bool:
	return mouse_m.x < start.x


func _band_active() -> bool:
	return drag.get("kind", "") == "band" and to_px(mouse_m).distance_to(to_px(drag.start)) >= BAND_PX


func _release() -> void:
	if drag.is_empty():
		return
	var kind := String(drag.kind)
	if kind == "cut":
		drag = {}
		return
	if kind == "band":
		var d := drag
		var band := _band_active()
		drag = {}
		if band:
			finish_band(Rect2(d.start, Vector2.ZERO).expand(mouse_m), band_crossing_from(d.start), bool(d.add))
		elif bool(d.add):
			# Maj + clic : ajoute ou retire l'élément.
			ed.toggle_selected(String(d.click))
		else:
			ed.select("")
		queue_redraw()
		return
	if kind in ["gmove", "grotate"]:
		ed.send_live("")
		var click := String(drag.get("click", ""))
		var was_moved := bool(drag.moved)
		if was_moved:
			ed.push_undo_snapshot(drag.snap)
			ed.changed()
			var n := (drag.ids as Array).size() if drag.has("ids") else ed.group.size()
			ed.set_status(Lang.t("Groupe de %d éléments déplacé (Ctrl+Z : annuler)", "Group of %d elements moved (Ctrl+Z: undo)") % n if kind == "gmove"
				else Lang.t("Groupe pivoté de %d° (Ctrl+Z : annuler)", "Group rotated %d° (Ctrl+Z: undo)") % MapGeom.norm_deg(float(drag.deg)))
		drag = {}
		if kind == "gmove" and click != "" and not was_moved:
			ed.select(click)
		return
	if kind == "capture":
		var rc := Rect2(drag.start, Vector2.ZERO).expand(mouse_m)
		drag = {}
		ed.prefab_tools.finish_capture(rc)
		return
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
	elif kind in ["scale", "ring"]:
		gizmo.release()
	elif kind in ["move", "handle", "rotate"]:
		ed.send_live("")
		if drag.moved:
			ed.push_undo_snapshot(drag.snap)
			ed.changed()
		if drag.has("insert"):
			if drag.moved:
				ed.vertex_status(String(drag.orig.id), true)
			else:
				ed.set_status(Lang.t("Glissez le « + » pour ajouter un point (ou double-cliquez sur le côté)", "Drag the \"+\" to add a point (or double-click the side)"))
		# Reclic sans bouger (moins de 4 px) : l'élément est désélectionné.
		var unselect: bool = bool(drag.get("reclick", false)) and not drag.moved and to_px(mouse_m).distance_to(to_px(Vector2(drag.raw))) < 4.0
		drag = {}
		_snap_exclude = ""
		if unselect:
			ed.select("")


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
	var fk := int(res.get("floor", ed.floor_k))
	# Pièce tracée sur d'autres : confirmation, puis découpe (MapCarve).
	if res.has("carve"):
		ed.confirm_carve(res.obj, fk, res.carve)
		return
	ed.add_object(res.obj, fk)
	if fk != ed.floor_k:
		# Escalier qui descend : enregistré au niveau de son pied.
		var fr := not Lang.is_en()
		ed.set_status(Lang.t("Escalier qui descend posé : il relie %s (en bas) à %s (ici)", "Stairs going down placed: they link %s (below) to %s (here)") % [EditorMap.alt_text(ed.doc.level_alt(fk), fr), EditorMap.alt_text(ed.doc.level_alt(ed.floor_k), fr)])


## Élément créé par un glissement de `a` à `b` (pièce, mur, pilier, escalier, piège).
func _creation(it: Dictionary, a: Vector2, b: Vector2) -> Dictionary:
	var k := ed.floor_k
	match String(it.tool):
		"room_rect":
			var r := Rect2(a, Vector2.ZERO).expand(b)
			var poly := MapGeom.rect_poly(r) if ed.place_rot != 45 else rect45_poly(a, b)
			var res := room_check(k, poly)
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
				# Escalier qui descend : tracé du haut (ici) vers le bas, enregistré
				# à l'étage du dessous, montant jusqu'ici (aucun champ de plus).
				var down := bool(it.get("descend", false))
				o["monte"] = MapRules.stair_dir(a, b, down)
				# Type choisi avec V avant de poser (format 6).
				if ed.place_variant != "":
					MapCatalog.set_variant(o, ed.place_variant)
				var kk := k
				if down:
					# Pied : le premier niveau plus bas dont une pièce contient
					# l'escalier (niveaux libres : un demi-niveau à côté ne
					# compte pas) ; il monte jusqu'ici.
					kk = k - 1
					for j in range(k - 1, -1, -1):
						if not MapRules.room_at(ed.doc, j, r.get_center()).is_empty():
							kk = j
							break
					o["altitude_haut"] = ed.doc.level_alt(k)
				# Contrôlé à chaque image du tracé : les étages lus resservent tant
				# que la carte ne change pas (version de la carte).
				MapRules.stair_cache_tag = ed.doc_version
				var rs := MapRules.check_rect(ed.doc, kk, "escalier", r, "", 0, MapCatalog.stair_kind(o), o, down)
				MapRules.stair_cache_tag = -1
				rs["obj"] = o
				rs["floor"] = kk
				return rs
			var res := MapRules.check_rect(ed.doc, k, String(o.type), r, "", 0, MapCatalog.stair_kind(o))
			res["obj"] = o
			return res
		"room_shape":
			# Forme de base : un polygone éditable qui garde ses paramètres (« forme »).
			var forme := MapShapes.from_drag(String(it.make.get("forme", "cercle")), a, b, shape_points)
			if forme.is_empty() or float(forme.rx) < 0.05:
				return {"ok": false, "fr": "forme trop petite", "en": "shape too small"}
			var poly := MapShapes.outline(forme)
			var res := room_check(k, poly)
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
	var res := _poly_creation(_item(), poly)
	if not res.ok:
		show_refusal(res)
		return
	if res.has("carve"):
		ed.confirm_carve(res.obj, ed.floor_k, res.carve)
		return
	ed.add_object(res.obj, ed.floor_k)


## Pièce de contour `poly` posable à l'étage `k` ? Par-dessus d'autres pièces :
## oui si leur découpe est possible (MapCarve.plan, gardé tant que la carte et
## le contour ne changent pas) ; le résultat porte alors « carve » (aperçu
## hachuré, confirmation au relâcher).
func room_check(k: int, poly: PackedVector2Array) -> Dictionary:
	var res := MapRules.check_room(ed.doc, k, poly, "", true)
	if not res.ok:
		return res
	var key := "%d|%d|%s" % [ed.doc_version, k, str(poly)]
	if key != String(_carve_cache.get("key", "")):
		_carve_cache = {"key": key, "plan": MapCarve.plan(ed.doc, k, poly)}
	var pl: Dictionary = _carve_cache.plan
	if not pl.get("carve", false):
		return res
	if not pl.ok:
		return MapRules.refuse(String(pl.fr), String(pl.en))
	res["carve"] = pl
	return res


## Découpe prévue du dernier contour essayé (room_check) : {key, plan}.
var _carve_cache: Dictionary = {}
## Découpe en attente de la réponse de l'utilisateur (MapEditor.confirm_carve) :
## {poly, plan}, dessinée tant que la boîte est ouverte.
var carve_pending: Dictionary = {}


## Élément tracé en polygone (`poly` : ses sommets) : une pièce, ou un objet
## polygone (format 9 : barrière invisible, posée n'importe où, MapRules.check_clip).
func _poly_creation(it: Dictionary, poly: PackedVector2Array) -> Dictionary:
	if String(it.get("tool", "")) == "poly":
		var o: Dictionary = it.make.duplicate(true)
		o["sommets"] = MapGeom.poly_arr(poly)
		var r := MapRules.check_clip(poly)
		r["obj"] = o
		return r
	var res := room_check(ed.floor_k, poly)
	res["obj"] = {"contour": MapGeom.poly_arr(poly)}
	return res


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
	if ed.place_variant != "":
		MapCatalog.set_variant(o, ed.place_variant)
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
			# Décor mural : au centimètre sans grille, au quart de mètre sinon.
			res = MapRules.place_wall_item(ed.doc, k, o, mouse_m, "", mode_now() != "libre")
			if res.ok:
				o["position"] = res.position
				MapRules.apply_wall(o, res)
		"floor_item":
			# Sans grille : là où est le curseur (au centimètre).
			var free := mode_now() == "libre"
			if it.get("wall_snap", false):
				# Boîte mystère (format 15) : au sol, ou collée au mur proche
				# face à la pièce (Alt : sans aimant).
				res = MapRules.place_box(ed.doc, k, o, MapGeom.round_cm(mouse_m) if free else mouse_m, "", not free, not angle_free())
				if res.ok:
					MapRules.apply_box(o, res)
			else:
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
	if kind == "create" or kind == "capture":
		return
	if kind == "cut":
		_drag_cut()
		return
	if kind == "band":
		return
	if kind == "gmove":
		_drag_group_move()
		return
	if kind == "grotate":
		_drag_group_rotate()
		return
	if kind in ["scale", "ring"]:
		gizmo.update()
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
		# Verrouillage d'axe (flèche, ou X / Y pendant le glissement).
		match String(drag.get("lock", "")):
			"X":
				delta.y = 0.0
			"Y":
				delta.x = 0.0
		var res := ed.try_move(orig, drag.attached, delta, drag.snap)
		if res.ok:
			drag.moved = drag.moved or delta.length() > 0.001
			drag["delta"] = delta
			ed.send_live(String(orig.id))
		elif delta.length() > 0.001:
			refusal = MapRules.why(res)
			refusal_marks = res.get("marks", [])
			_refusal_t = 1.5
	elif kind == "handle":
		if drag.has("insert") and not drag.moved and to_px(mouse_m).distance_to(to_px(Vector2(drag.raw))) < 3.0:
			return   # poignée « + » pas encore tirée : aucun point ajouté
		var res := ed.try_insert_vertex(orig, int(drag.insert), snap(mouse_m), drag.snap) if drag.has("insert") \
			else ed.try_handle(orig, int(drag.handle), snap(mouse_m), drag.snap)
		if res.ok:
			drag.moved = true
			ed.send_live(String(orig.id))
			if String(orig.get("type", "")) == "effet":
				ed.set_status(Lang.t("Zone : %s", "Zone: %s") % effect_zone_text(ed.doc.find(String(orig.id))))
		else:
			refusal = MapRules.why(res)
			refusal_marks = res.get("marks", [])
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
			ed.send_live(String(orig.id))
			ed.set_status(Lang.t("Rotation : %d°", "Rotation: %d°") % MapGeom.norm_deg(deg))
		else:
			refusal = MapRules.why(res)
			refusal_marks = res.get("marks", [])
			_refusal_t = 1.5


## Glissement du groupe : décalage au pas de l'aimantation (au centimètre sans
## grille), verrou d'axe (flèche, X / Y) ; tout le groupe validé à chaque pas
## (MapGroup.move) ; refusé : il reste à sa dernière place valide, l'élément
## fautif est nommé près du curseur.
func _drag_group_move() -> void:
	var delta := snap(mouse_m) - Vector2(drag.start)
	if mode_now() == "libre":
		delta = MapGeom.round_cm(mouse_m - Vector2(drag.raw))
	match String(drag.get("lock", "")):
		"X":
			delta.y = 0.0
		"Y":
			delta.x = 0.0
	if drag.has("delta") and (Vector2(drag.delta) - delta).length() < 0.0005:
		return
	var res := MapGroup.move(ed, drag.all, delta, 0, drag.snap)
	if res.ok:
		drag.moved = drag.moved or delta.length() > 0.001
		drag["delta"] = delta
		refusal_elems = []
		var live_id := String(drag.get("click", ""))
		ed.send_live(live_id if live_id != "" else String((drag.ids as Array)[0]))
	elif delta.length() > 0.001:
		refusal = MapRules.why(res)
		refusal_marks = res.get("marks", [])
		refusal_elems = [res.el] if res.get("el") is Dictionary else []
		_refusal_t = 1.5


## Poignée de rotation du groupe : pas de 15°, au degré près avec Alt, autour
## du centre du groupe (MapGroup.rotate).
func _drag_group_rotate() -> void:
	var c: Vector2 = drag.c
	var deg := rad_to_deg(angle_difference(float(drag.a0), (mouse_m - c).angle()))
	deg = roundf(deg) if angle_free() else snappedf(deg, MapTransform.STEP)
	if absf(deg - float(drag.deg)) < 0.001:
		return
	var res := MapGroup.rotate(ed, drag.all, c, deg, drag.snap)
	if res.ok:
		drag.moved = true
		drag.deg = deg
		refusal_elems = []
		ed.set_status(Lang.t("Rotation du groupe : %d°", "Group rotation: %d°") % MapGeom.norm_deg(deg))
	else:
		refusal = MapRules.why(res)
		refusal_marks = res.get("marks", [])
		refusal_elems = [res.el] if res.get("el") is Dictionary else []
		_refusal_t = 1.5


## Poignées de l'élément choisi : points (m).
func handles() -> PackedVector2Array:
	var e := ed.doc.find(ed.selected)
	var out := PackedVector2Array()
	if e.is_empty() or ed.doc.level_of(e) != ed.floor_k:
		return out
	if e.has("contour"):
		var poly := ed.doc.room_poly(e)
		if MapGeom.is_axis_rect(poly) and not e.has("forme"):
			var r := MapGeom.bbox(poly)
			return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
				Vector2(r.get_center().x, r.position.y), Vector2(r.end.x, r.get_center().y), Vector2(r.get_center().x, r.end.y), Vector2(r.position.x, r.get_center().y)])
		return poly
	if e.has("sommets"):
		# Barrière invisible en polygone (format 9) : une poignée par sommet.
		return MapGeom.poly(e.sommets)
	if e.has("rect"):
		if MapGeom.rot_of(e) != 0:
			return MapRaster.rect_poly(e)
		var r := MapGeom.rect_of(e.rect)
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if String(e.get("type", "")) == "mur":
		return PackedVector2Array([MapGeom.v2(e.a), MapGeom.v2(e.b)])
	if String(e.get("type", "")) == "effet":
		# Format 11 : zone de l'effet (coins et milieux ; mural : ses deux bouts).
		return MapTransform.effect_handles(e)
	return out


## Poignée de rotation de l'élément choisi : {p (m), c (centre de rotation)},
## {} si l'élément ne tourne pas (objets muraux : ils suivent leur mur).
## Groupe : au-dessus de son cadre, centre du groupe, « group » : true.
func rot_handle() -> Dictionary:
	if ed.group.size() >= 2:
		var gb := group_box()
		if gb.size == Vector2.ZERO:
			return {}
		return {"p": Vector2(gb.get_center().x, gb.position.y - EditorUi.px(ROT_HANDLE_PX) / zoom),
			"c": MapGroup.pivot(ed.doc, ed.group, mode_now() == "libre"), "group": true}
	var e := ed.doc.find(ed.selected)
	if e.is_empty() or ed.doc.level_of(e) != ed.floor_k or not MapTransform.can_rotate(e):
		return {}
	# Format 14 : le décor, les luminaires et les effets ont l'anneau Z (MapGizmoTop).
	if MapGizmoTop.RINGS and MapGizmoTop.has_ring(e):
		return {}
	var bb := MapGeom.bbox(ed.doc.room_poly(e)) if e.has("contour") else MapRules.footprint_rect(e)
	return {"p": Vector2(bb.get_center().x, bb.position.y - EditorUi.px(ROT_HANDLE_PX) / zoom), "c": MapTransform.pivot(ed.doc, e)}


func _handle_at(m: Vector2) -> int:
	var hs := handles()
	for i in hs.size():
		if to_px(hs[i]).distance_to(to_px(m)) <= _hsz() + 2.0:
			return i
	return -1


# ------------------------------------------------------------------ points d'un contour libre

## Élément choisi dont le contour s'édite point par point (pièce, barrière
## invisible : MapVertex) à l'étage affiché, outil Souris, seul ; {} sinon.
func _vertex_elem() -> Dictionary:
	if offscreen or ed.tool() != "select" or ed.group.size() >= 2:
		return {}
	var e := ed.doc.find(ed.selected)
	if e.is_empty() or ed.doc.level_of(e) != ed.floor_k or not MapVertex.editable(e):
		return {}
	return e


## Poignées « + » du contour choisi : [{p (m), edge}] ; seulement celles
## assez loin des autres poignées à l'écran (petit côté, zoom faible : aucune).
func plus_handles() -> Array:
	var e := _vertex_elem()
	if e.is_empty():
		return []
	var poly := MapVertex.poly_of(e)
	var gap := _hsz() * 1.5
	var out := []
	for ph in MapVertex.plus_handles(e):
		var a := to_px(poly[int(ph.edge)])
		var b := to_px(poly[(int(ph.edge) + 1) % poly.size()])
		var q := to_px(ph.p)
		if q.distance_to(a) >= gap and q.distance_to(b) >= gap and q.distance_to((a + b) * 0.5) >= (gap if MapVertex.is_rect_room(e) else 0.0):
			out.append(ph)
	return out


## Poignée « + » sous le point `m` (m) : {p, edge} ; {} sinon.
func plus_at(m: Vector2) -> Dictionary:
	for ph in plus_handles():
		if to_px(ph.p).distance_to(to_px(m)) <= _hsz() * 0.6 + 3.0:
			return ph
	return {}


## Sommet du contour choisi sous le point `m` : son indice dans le contour,
## -1 sinon (les milieux d'une pièce rectangle ne sont pas des sommets).
func vertex_at(m: Vector2) -> int:
	var e := _vertex_elem()
	if e.is_empty():
		return -1
	var h := _handle_at(m)
	return -1 if h < 0 else MapVertex.index_at(e, handles()[h])


## Sommet saisi par la poignée `h` du glissement en cours (indice du contour
## d'origine), -1 si la poignée n'est pas un sommet.
func _drag_vertex() -> int:
	if drag.get("kind", "") != "handle" or drag.has("insert"):
		return -1
	var orig: Dictionary = drag.orig
	if not MapVertex.editable(orig):
		return -1
	var h := int(drag.handle)
	if MapVertex.is_rect_room(orig):
		if h >= 4:
			return -1
		var r := MapGeom.bbox(MapVertex.poly_of(orig))
		return MapVertex.index_at(orig, [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)][h])
	return h


## Sommet ou côté du contour choisi sous le point `m` (clic droit) : {id,
## vertex} ou {id, edge, p} (point posé sur le côté) ; {} ailleurs.
func point_target(m: Vector2) -> Dictionary:
	var e := _vertex_elem()
	if e.is_empty():
		return {}
	var vi := vertex_at(m)
	if vi >= 0:
		return {"id": String(e.id), "vertex": vi}
	if _handle_at(m) >= 0:
		return {}
	var poly := MapVertex.poly_of(e)
	var hit := MapVertex.edge_at(poly, m, (_hsz() * 0.5 + 3.0) / zoom)
	if hit.is_empty():
		return {}
	return {"id": String(e.id), "edge": int(hit.edge), "p": MapVertex.point_on_edge(poly, int(hit.edge), m, snap(m))}


## Double-clic : ajoute un point sur le côté visé du contour du premier
## élément de `ids` touché (choisi avant le premier clic du double-clic, ou
## maintenant). -> true si le double-clic visait un côté.
func _double_click_insert(ids: Array) -> bool:
	for id in ids:
		var e := ed.doc.find(String(id))
		if String(id) == "" or e.is_empty() or ed.doc.level_of(e) != ed.floor_k or not MapVertex.editable(e):
			continue
		var poly := MapVertex.poly_of(e)
		# Sur un sommet : pas de point ajouté (la poignée se glisse).
		var on_vertex := false
		for v in poly:
			on_vertex = on_vertex or to_px(v).distance_to(to_px(mouse_m)) <= _hsz() + 2.0
		if on_vertex:
			continue
		var hit := MapVertex.edge_at(poly, mouse_m, (_hsz() * 0.5 + 3.0) / zoom)
		if hit.is_empty():
			continue
		if ed.selected != String(id):
			ed.select(String(id))
		_snap_exclude = String(id)
		var p := MapVertex.point_on_edge(poly, int(hit.edge), mouse_m, snap(mouse_m))
		_snap_exclude = ""
		ed.insert_vertex(String(id), int(hit.edge), p)
		return true
	return false


## Suppr : le sommet saisi (glissement en cours) ou survolé du contour choisi
## est supprimé. -> true si la touche est prise (sinon Suppr supprime
## l'élément choisi, comme avant).
func delete_point_key() -> bool:
	if not entry.is_empty() or not poly_pts.is_empty():
		return false
	var vi := _drag_vertex()
	if vi >= 0:
		var eid := String(drag.orig.id)
		cancel()
		ed.remove_vertex(eid, vi)
		return true
	if not drag.is_empty() or not mouse_inside:
		return false
	vi = vertex_at(mouse_m)
	if vi < 0:
		return false
	ed.remove_vertex(ed.selected, vi)
	return true


## Poignées « + » du contour choisi (petits ronds discrets, pleins au
## survol) et sommet survolé (cerclé : Suppr le supprime).
func _draw_point_handles() -> void:
	if not drag.is_empty() or _vertex_elem().is_empty():
		return
	var r := _hsz() * 0.6
	var hot := plus_at(mouse_m) if mouse_inside else {}
	for ph in plus_handles():
		var c := to_px(ph.p)
		var on: bool = not hot.is_empty() and int(hot.edge) == int(ph.edge) and Vector2(hot.p).is_equal_approx(ph.p)
		draw_circle(c, r + (1.5 if on else 0.0), COL_SEL if on else Color(0.08, 0.09, 0.1, 0.85))
		draw_arc(c, r + (1.5 if on else 0.0), 0.0, TAU, 16, COL_SEL, 1.0, true)
		var col := Color.BLACK if on else COL_SEL
		draw_line(c - Vector2(r * 0.6, 0), c + Vector2(r * 0.6, 0), col, 1.5)
		draw_line(c - Vector2(0, r * 0.6), c + Vector2(0, r * 0.6), col, 1.5)
	if mouse_inside:
		var vi := vertex_at(mouse_m)
		if vi >= 0:
			draw_arc(to_px(MapVertex.poly_of(_vertex_elem())[vi]), _hsz() * 0.9, 0.0, TAU, 20, Color.WHITE, 1.5, true)


## Aide de la barre d'état au survol d'un sommet ou d'une poignée « + »
## (une fois par entrée sur la poignée).
func _update_point_hint() -> void:
	var hint := ""
	if not _vertex_elem().is_empty():
		if vertex_at(mouse_m) >= 0:
			hint = "vertex"
		elif not plus_at(mouse_m).is_empty():
			hint = "plus"
	if hint == _point_hint:
		return
	_point_hint = hint
	if hint == "vertex":
		ed.set_status(Lang.t("Sommet : glissez-le pour le déplacer ; Suppr ou clic droit pour le supprimer", "Corner: drag it to move it; Del or right-click to delete it"))
	elif hint == "plus":
		ed.set_status(Lang.t("« + » : glissez pour ajouter un point (ou double-cliquez sur un côté)", "\"+\": drag to add a point (or double-click a side)"))


# ------------------------------------------------------------------ dessin

func _draw() -> void:
	# Niveaux figés pendant le dessin (rooms_on, objects_on, level_of de chaque
	# élément : EditorMap.levels relirait toutes les pièces) ; rien n'y change.
	var doc := ed.doc
	doc.freeze_levels()
	_draw_map()
	doc.thaw_levels()


func _draw_map() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	# Format 17 : coordonnées libres (négatives comprises), terrain partout.
	draw_rect(Rect2(Vector2.ZERO, size), COL_TERRAIN)
	_draw_grid()
	var doc := ed.doc
	var k := ed.floor_k if floor_override < 0 else floor_override
	var font := UiStyle.font("body")
	# Éléments d'un lot de Claude pas encore apparus (CollabView) : pas dessinés.
	var hid: Dictionary = ed.collab_view.hidden if ed.collab_view != null and not offscreen else {}
	# Étage du dessous en transparence.
	if ed.ghost_below and k > 0:
		for p in doc.rooms_on(k - 1):
			var poly := _px_poly(doc.room_poly(p))
			_fill(poly, Color(0.6, 0.7, 1.0, 0.07))
			draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0.6, 0.7, 1.0, 0.35), 1.0)
	# Pièces (couleur de leur zone).
	for p in doc.rooms_on(k):
		if hid.has(String(p.id)):
			continue
		var poly := _px_poly(doc.room_poly(p))
		if poly.size() >= 3:
			_fill(poly, ed.zone_color(String(p.get("zone", ""))))
	# Grille du validateur : murs générés, vides, ouvertures.
	_draw_cells(k)
	if not hid.is_empty():
		_mask_hidden(hid, k)
	# Escaliers d'un niveau plus bas qui arrivent ici (trémie ; format 17 :
	# n'importe quel niveau). Vus d'en haut, ils descendent : « descend à 0 m ».
	if k > 0:
		var here := doc.level_alt(k)
		for o in doc.objets:
			if String(o.get("type", "")) == "escalier" and not hid.has(String(o.get("id", ""))) and EditorMap.alt_of(o) < here - EditorMap.ALT_EQ \
					and absf(doc.stair_top_of(o) - here) <= EditorMap.ALT_EQ:
				_draw_object(o, font, 0.45)
				_stair_floor_label(font, o, Lang.t("descend à %s", "down to %s") % EditorMap.alt_text(EditorMap.alt_of(o), not Lang.is_en()), Color(0.75, 0.85, 1.0))
	# Objets.
	for o in doc.objects_on(k):
		if not hid.has(String(o.id)):
			_draw_object(o, font, 1.0)
			if String(o.get("type", "")) == "escalier":
				_stair_floor_label(font, o, Lang.t("monte à %s", "up to %s") % EditorMap.alt_text(doc.stair_top_of(o), not Lang.is_en()), Color(0.95, 0.85, 1.0))
	for o in doc.openings_on(k):
		if not hid.has(String(o.id)):
			_draw_opening(o, font)
	# Noms des pièces.
	if zoom >= 8.0:
		for p in doc.rooms_on(k):
			if hid.has(String(p.id)):
				continue
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
	# Éléments par identifiant (doc.find relirait toute la carte pour chacun).
	var by_id := {}
	if not ed.invalid.is_empty():
		for list in [doc.pieces, doc.ouvertures, doc.objets]:
			for e in list:
				var eid := String(e.get("id", ""))
				if not by_id.has(eid):
					by_id[eid] = e
	for eid in ed.invalid:
		var e: Dictionary = by_id.get(eid, {})
		if e.is_empty() or ed.doc.level_of(e) != k or hid.has(String(eid)):
			continue
		var r := _elem_rect_px(e)
		draw_rect(r.grow(3), COL_BAD, false, 2.0)
		draw_string(font, r.position + Vector2(r.size.x + _u(4), _u(12)), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(16), COL_BAD)
	# Refus d'un escalier : départ, arrivée, trémie et cases fautives.
	if not refusal_marks.is_empty():
		_draw_stair_marks(font, refusal_marks)
	if offscreen:
		_draw_rulers(font)
		return
	# Sélection et poignées.
	var sel := doc.find(ed.selected)
	# Un escalier se voit choisi aussi depuis l'étage où il arrive.
	var sel_k := ed.doc.level_of(sel) + (1 if String(sel.get("type", "")) == "escalier" and ed.doc.level_of(sel) == k - 1 else 0)
	if not sel.is_empty() and sel_k == k:
		var outline := _outline_of(sel)
		if not outline.is_empty():
			var poly := _px_poly(outline)
			draw_polyline(poly + PackedVector2Array([poly[0]]), COL_SEL, 2.5 if sel.has("contour") else 2.0)
		else:
			draw_rect(_elem_rect_px(sel).grow(3), COL_SEL, false, 2.0)
		for h in handles():
			draw_rect(Rect2(to_px(h) - Vector2.ONE * _hsz() * 0.5, Vector2.ONE * _hsz()), COL_SEL)
			draw_rect(Rect2(to_px(h) - Vector2.ONE * _hsz() * 0.5, Vector2.ONE * _hsz()), Color.BLACK, false, 1.0)
		_draw_point_handles()
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
	# Format 14 : poignées d'échelle et anneau Z du décor choisi.
	if not sel.is_empty() and sel_k == k:
		gizmo.draw(font)
	# Sélection multiple : chaque élément, cadre du groupe et sa poignée.
	_draw_group(font, k)
	# Action de groupe refusée : l'élément fautif, à la place refusée.
	for el in refusal_elems:
		if ed.doc.level_of(el) == k:
			outline_elem(el, COL_BAD, 3.0, 3.0)
			fill_elem(el, Color(COL_BAD, 0.18))
	# Élément survolé (dans la liste des objets ou sur la carte) : contour lumineux.
	var hov := doc.find(ed.hover_id) if ed.hover_id != "" else {}
	if not hov.is_empty() and ed.doc.level_of(hov) == k:
		_draw_glow(hov)
	# Problème choisi dans l'onglet Vérification.
	if highlight_floor == k:
		for c in highlight:
			var cp := to_px(MapGeom.cell_center(c))
			draw_rect(Rect2(cp - Vector2.ONE * zoom * 0.25, Vector2.ONE * zoom * 0.5).grow(1.0), Color(1, 0.2, 0.2, 0.9), false, 2.0)
	_draw_cuts(font)
	_draw_axis_arrows(font)
	_draw_tool(font)
	# Aperçu 3D : repère de sa caméra (MapPreviewPanel).
	if ed.preview != null:
		ed.preview.draw_on_canvas(self)
	_draw_peers(font, k)
	_draw_rulers(font)
	_draw_triad(font)


# ------------------------------------------------------------------ sélection multiple (MapGroup)

## Cadre (m) des éléments du groupe sur l'étage affiché ; vide sans groupe.
func group_box() -> Rect2:
	var k := ed.floor_k if floor_override < 0 else floor_override
	var bb := Rect2()
	var first := true
	for id in ed.group:
		var e := ed.doc.find(String(id))
		if e.is_empty() or ed.doc.level_of(e) != k:
			continue
		var r := elem_rect_m(e)
		bb = r if first else bb.merge(r)
		first = false
	return bb


## Groupe choisi (au moins deux éléments) : chaque élément entouré, cadre du
## groupe en tirets (marges de 0,25 m) avec ses coins, nombre d'éléments, poignée
## de rotation ronde au-dessus (le centre marqué pendant la rotation).
func _draw_group(font: Font, k: int) -> void:
	if ed.group.size() < 2 or offscreen:
		return
	var n_here := 0
	for id in ed.group:
		var e := ed.doc.find(String(id))
		if e.is_empty() or ed.doc.level_of(e) != k:
			continue
		n_here += 1
		fill_elem(e, Color(COL_SEL, 0.1))
		outline_elem(e, COL_SEL, 2.0, 3.0)
	if n_here == 0:
		return
	var gb := group_box()
	var r := Rect2(to_px(gb.position), gb.size * zoom).grow(_u(8))
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_dashed_line(pts[i], pts[(i + 1) % 4], Color(COL_SEL, 0.85), 1.5, _u(6))
	# Coins du cadre (repères, comme une sélection de logiciel de dessin).
	var cl := _u(10)
	for i in 4:
		var p: Vector2 = pts[i]
		var a: Vector2 = pts[(i + 1) % 4]
		var b: Vector2 = pts[(i + 3) % 4]
		draw_line(p, p + (a - p).normalized() * cl, COL_SEL, 2.5)
		draw_line(p, p + (b - p).normalized() * cl, COL_SEL, 2.5)
	var lbl := Lang.t("%d éléments", "%d elements") % ed.group.size()
	if n_here < ed.group.size():
		lbl += Lang.t(" (%d à cet étage)", " (%d on this floor)") % n_here
	var fs := EditorUi.fs(12)
	var bf := MapView.bold_font(600)
	var tw := bf.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	# Sous le cadre, à gauche (la poignée de rotation est au-dessus).
	var lr := Rect2(Vector2(r.position.x, r.end.y + _u(4)), Vector2(tw + _u(12), _u(18)))
	MapElevation._round_rect(self, lr, Color("2b2410"), COL_SEL)
	draw_string(bf, lr.position + Vector2(_u(6), _u(13)), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_SEL)
	var rh := rot_handle()
	if not rh.is_empty():
		var hp := to_px(rh.p)
		draw_line(Vector2(hp.x, r.position.y), hp, Color(COL_SEL, 0.7), 1.0)
		draw_circle(hp, _hsz() * 0.8, COL_SEL)
		draw_arc(hp, _hsz() * 0.45, -PI * 0.8, PI * 0.5, 10, Color.BLACK, 1.5)
		if drag.get("kind", "") == "grotate":
			var cp := to_px(drag.c)
			draw_circle(cp, 3.5, COL_SEL)
			draw_arc(cp, _u(9), 0, TAU, 20, Color(COL_SEL, 0.6), 1.0)
			_label_at(font, hp + Vector2(_u(12), -_u(6)), "%d°" % MapGeom.norm_deg(float(drag.get("deg", 0))))


## Rectangle de sélection en cours : de gauche à droite, cadre bleu plein
## (éléments entièrement dedans) ; de droite à gauche, cadre vert en tirets
## (éléments touchés) ; les éléments qu'il prendrait sont entourés.
func _draw_band(font: Font) -> void:
	if not _band_active():
		return
	var crossing := band_crossing_from(drag.start)
	var col := COL_CROSSING if crossing else COL_WINDOW
	var rm := Rect2(drag.start, Vector2.ZERO).expand(mouse_m)
	var r := Rect2(to_px(rm.position), rm.size * zoom)
	draw_rect(r, Color(col, 0.1))
	if crossing:
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			draw_dashed_line(pts[i], pts[(i + 1) % 4], col, 1.5, _u(6))
	else:
		draw_rect(r, col, false, 1.5)
	var got := MapGroup.in_rect(ed.doc, ed.floor_k, rm, crossing)
	for id in got:
		var e := ed.doc.find(String(id))
		if not e.is_empty():
			outline_elem(e, col, 2.0, 2.0)
	var lbl := (Lang.t("Touchés : %d", "Touched: %d") if crossing else Lang.t("Entièrement dedans : %d", "Entirely inside: %d")) % got.size()
	if bool(drag.get("add", false)):
		lbl += Lang.t(" (ajoutés)", " (added)")
	_label_at(font, to_px(mouse_m) + Vector2(_u(14), _u(20)), lbl)


# ------------------------------------------------------------------ flèches d'axe, coupes (vues multiples)

## Curseur de la souris selon ce qui est dessous (docs/EDITOR_VIEWS.md § 6.3) :
## main fermée (vue déplacée), ↔ / ↕ (flèche d'axe, trait de coupe),
## redimensionnement orienté (poignée), déplacement (élément déplaçable).
func cursor_at(px: Vector2) -> Control.CursorShape:
	if _pan:
		return Control.CURSOR_DRAG
	if not drag.is_empty():
		match String(drag.get("kind", "")):
			"move", "gmove":
				return Control.CURSOR_HSIZE if drag.get("lock", "") == "X" else (Control.CURSOR_VSIZE if drag.get("lock", "") == "Y" else Control.CURSOR_MOVE)
			"band":
				return Control.CURSOR_CROSS
			"handle", "cut":
				return mouse_default_cursor_shape
		return Control.CURSOR_ARROW
	if offscreen or ed.tool() != "select":
		return Control.CURSOR_ARROW
	var gc := gizmo.cursor(px)
	if gc >= 0:
		return gc as Control.CursorShape
	var m := to_m(px)
	var rh := rot_handle()
	if not rh.is_empty() and to_px(rh.p).distance_to(px) <= _hsz() + 4.0:
		return Control.CURSOR_POINTING_HAND
	var h := _handle_at(m)
	if h >= 0:
		var sel := ed.doc.find(ed.selected)
		if sel.has("contour") and handles().size() == 8:
			return [Control.CURSOR_FDIAGSIZE, Control.CURSOR_BDIAGSIZE, Control.CURSOR_FDIAGSIZE, Control.CURSOR_BDIAGSIZE,
				Control.CURSOR_VSIZE, Control.CURSOR_HSIZE, Control.CURSOR_VSIZE, Control.CURSOR_HSIZE][h]
		return Control.CURSOR_FDIAGSIZE
	if not plus_at(m).is_empty():
		return Control.CURSOR_CROSS
	var ch := _cut_handle_at(px)
	if not ch.is_empty():
		return Control.CURSOR_VSIZE if String(MapView.depth_axis((ch.ev as MapElevation).plane)[0]) == "Y" else Control.CURSOR_HSIZE
	match arrow_at(px):
		"X":
			return Control.CURSOR_HSIZE
		"Y":
			return Control.CURSOR_VSIZE
	if not ed.element_at(m).is_empty():
		return Control.CURSOR_MOVE
	return Control.CURSOR_ARROW


## Centre (px) des flèches d'axe de l'élément choisi ; Vector2.INF sans flèches.
func arrows_origin() -> Vector2:
	if offscreen or ed.tool() != "select":
		return Vector2.INF
	if ed.group.size() >= 2:
		var gb := group_box()
		return to_px(gb.get_center()) if gb.size != Vector2.ZERO else Vector2.INF
	var e := ed.doc.find(ed.selected)
	if e.is_empty() or ed.doc.level_of(e) != ed.floor_k:
		return Vector2.INF
	if e.has("position") and not e.has("rect"):
		return to_px(MapGeom.v2(e.position))
	return to_px(elem_rect_m(e).get_center() if not e.has("contour") else MapGeom.centroid(ed.doc.room_poly(e)))


## Axes sur lesquels l'élément choisi glisse : un objet mural ou une ouverture
## suit son mur (seulement l'axe du mur).
func arrow_axes() -> Array:
	if ed.group.size() >= 2:
		return ["X", "Y"]
	var e := ed.doc.find(ed.selected)
	var t := String(e.get("type", ""))
	if t in MapRules.ouvertures_types() or MapCatalog.tool_of(e) == "wall_item":
		if t in MapRules.ouvertures_types():
			var poly := MapElevationItems.opening_poly(ed.doc, e)
			var d := (poly[1] - poly[0]).normalized()
			return ["X"] if absf(d.x) > 0.9 else (["Y"] if absf(d.y) > 0.9 else [])
		var dv := MapGeom.item_wall_dir(e)
		return ["Y"] if absf(dv.x) > 0.9 else (["X"] if absf(dv.y) > 0.9 else [])
	return ["X", "Y"]


## Flèche sous le pixel : « X », « Y » ; "" sinon.
func arrow_at(px: Vector2) -> String:
	var o := arrows_origin()
	if o == Vector2.INF:
		return ""
	var axes := arrow_axes()
	if "X" in axes and Rect2(o + Vector2(_u(14), -_u(5)), Vector2(_u(34), _u(10))).has_point(px):
		return "X"
	if "Y" in axes and Rect2(o + Vector2(-_u(5), _u(14)), Vector2(_u(10), _u(34))).has_point(px):
		return "Y"
	return ""


## Flèches X (rouge) et Y (vert) sur l'élément choisi, puce Z (hauteur de
## pose ou étage), Δ en or et trait de guide pendant un glissement (§ 3.3).
func _draw_axis_arrows(font: Font) -> void:
	var o := arrows_origin()
	if o == Vector2.INF:
		return
	var lock := String(drag.get("lock", "")) if drag.get("kind", "") in ["move", "gmove"] else ""
	var axes := arrow_axes()
	if lock == "X":
		draw_dashed_line(Vector2(_ruler(), o.y), Vector2(size.x, o.y), Color(COL_X, 0.35), 1.0, _u(8))
	elif lock == "Y":
		draw_dashed_line(Vector2(o.x, _ruler()), Vector2(o.x, size.y), Color(COL_Y, 0.35), 1.0, _u(8))
	# Format 14 : estompées (25 %) pendant un geste d'échelle (MapGizmoTop).
	var fade := 0.25 if gizmo != null and gizmo.busy_scale() else 1.0
	if "X" in axes:
		var a := (0.5 if lock == "Y" else 1.0) * fade
		draw_line(o, o + Vector2(_u(40), 0), Color(COL_X, a), 3.0 if lock == "X" else 2.0)
		var tip := o + Vector2(_u(46), 0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-_u(7), -_u(4)), tip + Vector2(-_u(7), _u(4))]), Color(COL_X, a))
	if "Y" in axes:
		var a := (0.5 if lock == "X" else 1.0) * fade
		draw_line(o, o + Vector2(0, _u(40)), Color(COL_Y, a), 3.0 if lock == "Y" else 2.0)
		var tip := o + Vector2(0, _u(46))
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-_u(4), -_u(7)), tip + Vector2(_u(4), -_u(7))]), Color(COL_Y, a))
	# Puce Z : hauteur de pose (m au-dessus du sol) ; « É1 » pour un étage.
	var e := ed.doc.find(ed.selected)
	var zt := ""
	if e.is_empty():
		zt = ""
	elif MapVertical.pose_kind(e) == "pose":
		zt = "Z %s m" % MapView.num(MapVertical.pose_z(ed.doc, ed.raster().v, e), 2)
	elif ed.doc.floor_count() > 1:
		zt = "Z %s" % EditorMap.alt_text(EditorMap.alt_of(e), not Lang.is_en())
	if zt != "":
		var bf := MapView.bold_font(600)
		var fs := EditorUi.fs(11)
		var w := bf.get_string_size(zt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + _u(10)
		var r := Rect2(o + Vector2(_u(12), _u(10)), Vector2(w, _u(17)))
		MapElevation._round_rect(self, r, Color("121214"), COL_Z)
		draw_string(bf, r.position + Vector2(_u(5), _u(12)), zt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("cfe0ff"))
	# Écart pendant le glissement, en or.
	if drag.get("kind", "") in ["move", "gmove"] and drag.get("moved", false) and drag.has("delta"):
		var d: Vector2 = drag.delta
		var parts := []
		if absf(d.x) > 0.0005:
			parts.append("ΔX %s m" % MapElevationTools._signed(d.x))
		if absf(d.y) > 0.0005:
			parts.append("ΔY %s m" % MapElevationTools._signed(d.y))
		if not parts.is_empty():
			var t := " · ".join(parts)
			var bf7 := MapView.bold_font(700)
			var fs := EditorUi.fs(12)
			var tw := bf7.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := to_px(mouse_m) + Vector2(_u(18), -_u(26))
			MapElevation._round_rect(self, Rect2(at - Vector2(0, _u(13)), Vector2(tw + _u(14), _u(19))), Color("2b2410"), Color("F2C759"))
			draw_string(bf7, at + Vector2(_u(6), _u(1)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("F2C759"))


## Poignées des traits de coupe : [{ev, i (0 : début, 1 : fin), rect (px)}].
func _cut_handles() -> Array:
	var out := []
	if ed.views == null or offscreen:
		return out
	for ev: MapElevation in ed.views.cuts():
		var across := String(MapView.depth_axis(ev.plane)[0]) == "Y"
		for i in 2:
			var c := float(ev.coupe[i])
			if across:
				var y := to_px(Vector2(0, c)).y
				out.append({"ev": ev, "i": i, "rect": Rect2(size.x - _u(58), y - _u(7), _u(10), _u(14))})
			else:
				var x := to_px(Vector2(c, 0)).x
				out.append({"ev": ev, "i": i, "rect": Rect2(x - _u(7), size.y - _u(58), _u(14), _u(10))})
	return out


func _cut_handle_at(px: Vector2) -> Dictionary:
	for h in _cut_handles():
		if (h.rect as Rect2).grow(3.0).has_point(px):
			return h
	return {}


## Trait de coupe glissé : la coupe devient « personnalisée ».
func _drag_cut() -> void:
	var ev: MapElevation = drag.ev
	if not is_instance_valid(ev) or ev.coupe.size() != 2:
		drag = {}
		return
	var across := String(MapView.depth_axis(ev.plane)[0]) == "Y"
	var v := snappedf(mouse_m.y if across else mouse_m.x, step() if mode_now() != "libre" else 0.01)
	var c := ev.coupe.duplicate()
	# Un trait s'arrête avant l'autre (écart minimal) : la coupe ne s'inverse pas.
	if int(drag.i) == 0:
		v = minf(v, float(c[1]) - MapElevation.CUT_MIN)
	else:
		v = maxf(v, float(c[0]) + MapElevation.CUT_MIN)
	c[int(drag.i)] = v
	ev.set_cut(c, "perso")
	ed.set_status(Lang.t("Coupe %s : %s (personnalisée)", "%s cut: %s (custom)") % [MapView.plane_name(ev.plane), ev.cut_text()])


## Coupes des élévations (docs/EDITOR_VIEWS.md, § 3.2) : tranche teintée,
## deux traits pointillés or et le nom de l'élévation.
func _draw_cuts(font: Font) -> void:
	if ed.views == null:
		return
	var col := Color("D99940")
	for ev: MapElevation in ed.views.cuts():
		var c0 := float(ev.coupe[0])
		var c1 := float(ev.coupe[1])
		var across := String(MapView.depth_axis(ev.plane)[0]) == "Y"
		var a := to_px(Vector2(0, c0) if across else Vector2(c0, 0))
		var b := to_px(Vector2(0, c1) if across else Vector2(c1, 0))
		var lbl := Lang.t("coupe %s", "%s cut") % MapView.plane_name(ev.plane)
		if across:
			draw_rect(Rect2(_ruler(), a.y, size.x - _ruler(), b.y - a.y), Color(col, 0.07))
			for y in [a.y, b.y]:
				draw_dashed_line(Vector2(_ruler(), y), Vector2(size.x, y), Color(col, 0.8), 1.2, _u(6))
			draw_string(font, Vector2(_ruler() + _u(4), a.y + _u(13)), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), Color("e8b46a"))
			for y in [a.y, b.y]:
				draw_rect(Rect2(size.x - _u(58), y - _u(7), _u(10), _u(14)), col)
		else:
			draw_rect(Rect2(a.x, _ruler(), b.x - a.x, size.y - _ruler()), Color(col, 0.07))
			for x in [a.x, b.x]:
				draw_dashed_line(Vector2(x, _ruler()), Vector2(x, size.y), Color(col, 0.8), 1.2, _u(6))
			draw_string(font, Vector2(a.x + _u(4), _ruler() + _u(12)), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), Color("e8b46a"))
			for x in [a.x, b.x]:
				draw_rect(Rect2(x - _u(7), size.y - _u(58), _u(14), _u(10)), col)


## Rendu de la collaboration par-dessus le plan (CollabView) : aperçus en
## direct et sélections des autres, clignotements, lots et highlight de
## Claude, survol du panneau Historique, curseurs, bulle.
func _draw_peers(font: Font, k: int) -> void:
	if ed.collab_view != null:
		ed.collab_view.draw_on(self, font, k)


## Murs générés (grille du validateur) des pièces d'un lot de Claude pas
## encore apparues : recouverts par le terrain le temps de l'apparition.
func _mask_hidden(hid: Dictionary, k: int) -> void:
	for p in ed.doc.rooms_on(k):
		if not hid.has(String(p.id)):
			continue
		for poly in Geometry2D.offset_polygon(ed.doc.room_poly(p), MapGeom.CELL * 0.5 + 0.01, Geometry2D.JOIN_MITER):
			_fill(_px_poly(poly), COL_TERRAIN)


## Rectangle (m) d'un élément : pièce, ouverture (carré de sa largeur) ou objet.
func elem_rect_m(e: Dictionary) -> Rect2:
	if e.has("contour"):
		return MapGeom.bbox(ed.doc.room_poly(e))
	if String(e.get("type", "")) in MapRules.ouvertures_types():
		var p := MapGeom.v2(e.position)
		var w := MapRules.opening_width(e)
		return Rect2(p - Vector2(w, w) * 0.5, Vector2(w, w))
	return MapRules.footprint_rect(e)


## Contour d'un élément (forme exacte, sinon son rectangle) de `width` px,
## écarté de `grow` px pour un rectangle.
func outline_elem(e: Dictionary, col: Color, width: float, grow: float) -> void:
	var outline := _outline_of(e)
	if outline.size() >= 2:
		var poly := _px_poly(outline)
		draw_polyline(poly + PackedVector2Array([poly[0]]), col, width)
	else:
		draw_rect(_elem_rect_px(e).grow(grow), col, false, width)


## Élément rempli (silhouette d'un aperçu en direct, clignotement).
func fill_elem(e: Dictionary, col: Color) -> void:
	var outline := _outline_of(e)
	if outline.size() >= 3:
		_fill(_px_poly(outline), col)
	else:
		draw_rect(_elem_rect_px(e), col)


## Contour exact d'un élément quand il n'est pas un rectangle droit (pièce,
## rectangle ou décor tourné, objet contre un mur en biais) ; vide sinon.
func _outline_of(e: Dictionary) -> PackedVector2Array:
	if e.has("contour"):
		return ed.doc.room_poly(e)
	if String(e.get("type", "")) == "bloc_invisible":
		return MapRaster.clip_poly(e)
	if String(e.get("type", "")) == "effet":
		return MapRules.effect_poly(e)
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
	var r := elem_rect_m(e)
	return Rect2(to_px(r.position), r.size * zoom)


## Grille fine (mode « fine ») : au pas choisi.
func _fine_grid() -> float:
	return fine_step if snap_mode == "fine" else 0.0


func _draw_grid() -> void:
	super()
	# Origine (x = 0, y = 0) : simple repère discret, pas un bord (format 17 :
	# coordonnées négatives admises).
	var o := to_px(Vector2.ZERO)
	draw_line(Vector2(o.x, 0), Vector2(o.x, size.y), COL_ORIGIN, 1.0)
	draw_line(Vector2(0, o.y), Vector2(size.x, o.y), COL_ORIGIN, 1.0)
	if o.x > -8.0 and o.y > -8.0 and o.x < size.x + 8.0 and o.y < size.y + 8.0:
		draw_arc(o, _u(4), 0.0, TAU, 16, Color(COL_ORIGIN, 0.6), 1.0)


func _draw_rulers(font: Font) -> void:
	super(font)
	if offscreen:
		return
	# Position du curseur sur les règles.
	_draw_ruler_cursor(mouse_m)


func _draw_cells(k: int) -> void:
	var r := ed.raster()
	if r == null or k >= r.v.floors.size():
		return
	var f: MapValidator.Floor = r.v.floors[k]
	# Vue (m, éditeur) -> cases de la grille (repère décalé des coordonnées
	# négatives : r.v.shift) ; chaque case est redessinée à sa place dans l'éditeur.
	var sc := r.v.shift_cells()
	var m0 := to_m(Vector2.ZERO)
	var m1 := to_m(size)
	var i0 := maxi(0, floori(m0.x / MapGeom.CELL) - 1 + sc.x)
	var i1 := mini(f.w - 1, ceili(m1.x / MapGeom.CELL) + 1 + sc.x)
	var j0 := maxi(0, floori(m0.y / MapGeom.CELL) - 1 + sc.y)
	var j1 := mini(f.h - 1, ceili(m1.y / MapGeom.CELL) + 1 + sc.y)
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
					var p := to_px(MapGeom.cell_center(Vector2i(run_start, j) - sc)) - Vector2.ONE * cs * 0.5
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
	# Murs du repère de la grille (décalé si coordonnées négatives) -> éditeur.
	var sh := v.shift
	for w in v.oblique_walls[k]:
		var poly := _slab_px(w.a - sh, w.b - sh, float(w.half))
		if not MapGeom.bbox(poly).intersects(view):
			continue
		_fill(poly, COL_WALL)
		if String(w.get("kind", "")) == "pilier":
			continue   # pilier tourné : pavé plein, sans bouts arrondis
		for e in [w.a, w.b]:
			draw_circle(to_px(e - sh), float(w.half) * zoom, COL_WALL)
	for key in v.diag_open:
		var o: Dictionary = v.diag_open[key]
		if int(o.floor) != k:
			continue
		var p: Vector2 = o.p - sh
		var t: Vector2 = o.t
		var hw := float(o.w) * 0.5
		var poly := _slab_px(p - t * hw, p + t * hw, float(o.half) + 0.02)
		_fill(poly, OPENING_COLORS.get(String(o.type), COL_OK))


func _draw_object(o: Dictionary, _font: Font, alpha: float) -> void:
	var t := String(o.get("type", ""))
	var it := MapCatalog.item_for(o)
	var r := MapRules.footprint_rect(o)
	var rp := Rect2(to_px(r.position), r.size * zoom)
	# Hors de la vue : rien à dessiner (cartes de 2000 objets).
	if not rp.grow(8.0).intersects(Rect2(Vector2.ZERO, size)):
		return
	if t == "bloc_invisible":
		_draw_clip(o, it, alpha)
		return
	if t == "escalier" and MapCatalog.stair_kind(o) != StairGen.DEFAULT_KIND:
		_draw_stair_plan(o, alpha)
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
	if t == "effet":
		_draw_effect(o, it, col, rp, alpha)
		return
	if MapCatalog.floor_box(o):
		_draw_floor_box(o, it, col, alpha)
		return
	var mount := MapCatalog.light_mount(o)
	if t in ["prefab", "luminaire"] and mount != "mur" and MapRaster.free_rot(o):
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
	if t in ["prefab", "luminaire"] and mount != "mur":
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
	if t == "arme" and MapCatalog.variant_of(o) == "planche":
		# Variante « planche » : la craie sur une planche (fond bois).
		draw_rect(rp.grow(-1.0), Color(0.45, 0.3, 0.16, 0.75 * alpha))
	var s := maxf(12.0, minf(rp.size.x, rp.size.y) * 1.1)
	if t == "lampe" or t == "luminaire":
		s = maxf(14.0, zoom * 0.9)
	MapIcons.draw(self, it, Rect2(rp.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)))
	draw_rect(rp, Color(col, 0.8 * alpha), false, 1.0)
	if t == "luminaire" and o.get("id", "") == ed.selected:
		draw_arc(rp.get_center(), float(o.get("portee", 8.0)) * zoom, 0, TAU, 48, Color(col, 0.4), 1.0)


## Boîte mystère au sol (format 15) : emprise tournée (2 × 1 m), icône, avant
## de la boîte (côté où s'ouvre le couvercle) en trait épais et flèche.
func _draw_floor_box(o: Dictionary, it: Dictionary, col: Color, alpha: float) -> void:
	var poly := _px_poly(MapRaster.floor_poly(o))
	_fill(poly, Color(0, 0, 0, 0.35 * alpha))
	var c := MapGeom.centroid(poly)
	var span := minf(poly[0].distance_to(poly[1]), poly[1].distance_to(poly[2]))
	var si := clampf(span * 1.1, 12.0, 56.0)
	MapIcons.draw(self, it, Rect2(c - Vector2(si, si) * 0.5, Vector2(si, si)))
	draw_polyline(poly + PackedVector2Array([poly[0]]), Color(col, 0.8 * alpha), 1.0)
	# Avant : côté +y à rot = 0 (MapGeom.rot_rect_poly : sommets 2 et 3).
	draw_line(poly[2], poly[3], Color(col.lightened(0.3), 0.95 * alpha), 3.0)
	if zoom >= 4.0:
		var dv := MapRules.box_front(o)
		var edge := (poly[2] + poly[3]) * 0.5
		var tip := edge + dv * maxf(6.0, zoom * 0.35)
		var w := Color(1, 1, 1, 0.9 * alpha)
		draw_line(edge, tip, w, 2.0)
		draw_line(tip, tip - dv.rotated(0.6) * 6.0, w, 2.0)
		draw_line(tip, tip - dv.rotated(-0.6) * 6.0, w, 2.0)


## Effet (format 10 ; zone : format 11) : sa ZONE réelle (polygone tourné)
## translucide de sa couleur, contour en tirets (il ne bloque rien), icône au
## milieu ; flèche du devant s'il pivote ; au plafond, des tirets croisés en
## plus ; mural, sur la face du mur ; choisi, ses dimensions écrites à côté.
func _draw_effect(o: Dictionary, it: Dictionary, col: Color, _rp: Rect2, alpha: float) -> void:
	var poly := _px_poly(MapRules.effect_poly(o))
	_fill(poly, Color(col, 0.16 * alpha))
	var dash := maxf(3.0, zoom * 0.15)
	for i in poly.size():
		draw_dashed_line(poly[i], poly[(i + 1) % poly.size()], Color(col.lightened(0.25), 0.85 * alpha), 1.2, dash)
	var c := MapGeom.centroid(poly)
	var span := minf(poly[0].distance_to(poly[1]), poly[1].distance_to(poly[2]))
	if MapCatalog.effect_mount(o) == "plafond":
		# Au plafond : diagonales en tirets (il pend au-dessus de la pièce).
		draw_dashed_line(poly[0], poly[2], Color(col, 0.45 * alpha), 1.0, dash)
		draw_dashed_line(poly[1], poly[3], Color(col, 0.45 * alpha), 1.0, dash)
	var si := clampf(span * 0.85, 14.0, 48.0)
	MapIcons.draw(self, it, Rect2(c - Vector2(si, si) * 0.5, Vector2(si, si)))
	if MapCatalog.rotates(o) and zoom >= 8.0 and poly.size() == 4:
		var dv := Vector2(0, 1).rotated(deg_to_rad(float(MapGeom.rot_of(o))))
		var edge := (poly[2] + poly[3]) * 0.5
		draw_line(edge - dv * 7.0, edge, Color(1, 1, 1, 0.8 * alpha), 2.0)
		draw_line(edge, edge - dv.rotated(0.6) * 5.0, Color(1, 1, 1, 0.8 * alpha), 2.0)
		draw_line(edge, edge - dv.rotated(-0.6) * 5.0, Color(1, 1, 1, 0.8 * alpha), 2.0)
	if String(o.get("id", "")) == ed.selected and not offscreen and zoom >= 6.0:
		var font := UiStyle.font("body")
		var bb := MapGeom.bbox(poly)
		_label_at(font, Vector2(bb.end.x + _u(6), bb.position.y + _u(2)), effect_zone_text(o))


## Dimensions de la zone d'un effet : « 3 × 2 m », volume « 4 × 4 × 0,6 m »,
## mural « 0,5 m × 0,4 m de haut ».
static func effect_zone_text(o: Dictionary) -> String:
	if o.is_empty():
		return ""
	var z := MapCatalog.effect_zone(o)
	var m := func(v: float) -> String: return MapCatalog.short_num(v).replace(",", ".") if Lang.is_en() else MapCatalog.short_num(v)
	if MapCatalog.effect_mount(o) == "mur":
		return Lang.t("%s m, %s m de haut", "%s m, %s m high") % [m.call(z.x), m.call(z.z)]
	if MapCatalog.effect_dims(String(o.get("effet", ""))).size() == 3:
		return "%s × %s × %s m" % [m.call(z.x), m.call(z.y), m.call(z.z)]
	return "%s × %s m" % [m.call(z.x), m.call(z.y)]


## Barrière invisible (format 9 : polygone) : surface translucide hachurée à
## 45°, contour en tirets, sommets marqués, icône au milieu (elle n'existe pas
## à l'œil en jeu), hauteur écrite à côté quand elle n'est pas « jusqu'au
## plafond ».
func _draw_clip(o: Dictionary, it: Dictionary, alpha: float) -> void:
	var poly := MapRaster.clip_poly(o)
	if poly.size() < 3:
		return
	var bb := MapGeom.bbox(poly)
	var col: Color = it.get("color", Color(0.35, 0.85, 1.0))
	var px := _px_poly(poly)
	_fill(px, Color(col, 0.16 * alpha))
	# Hachures à 45°, coupées au contour (polygone quelconque, même concave).
	var step := maxf(0.25, 7.0 / maxf(zoom, 0.01))
	var k := bb.position.x - bb.size.y + step * 0.5
	while k < bb.end.x:
		var line := PackedVector2Array([Vector2(k, bb.position.y), Vector2(k + bb.size.y, bb.end.y)])
		for seg: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(line, poly):
			if seg.size() >= 2:
				draw_line(to_px(seg[0]), to_px(seg[seg.size() - 1]), Color(col, 0.45 * alpha), 1.0)
		k += step
	for i in px.size():
		draw_dashed_line(px[i], px[(i + 1) % px.size()], Color(col.lightened(0.2), 0.95 * alpha), 1.5, 6.0)
	if zoom >= 10.0:
		for q in px:
			draw_circle(q, 2.0, Color(col.lightened(0.3), 0.9 * alpha))
	var c := MapGeom.centroid(poly)
	if not MapGeom.contains(poly, c):
		c = bb.get_center()
	var s := minf(minf(bb.size.x, bb.size.y) * zoom * 0.8, 40.0)
	if s >= 12.0:
		MapIcons.draw(self, it, Rect2(to_px(c) - Vector2(s, s) * 0.5, Vector2(s, s)))
	if o.has("hauteur") and zoom >= 14.0:
		var font := UiStyle.font("body")
		var lbl := "%s m" % MapRules._m(float(o.hauteur), not Lang.is_en())
		var p := to_px(c) + Vector2(-font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10)).x * 0.5, s * 0.5 + _u(12))
		draw_string_outline(font, p, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), 3, Color(0, 0, 0, 0.9))
		draw_string(font, p, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), Color(0.85, 0.95, 1.0, alpha))


## Escalier d'un type (format 6 : palier, L, U, colimaçon, rampe...) : son
## plan (StairGen, même géométrie que le jeu) : volées et leurs marches,
## paliers, colimaçon, flèches de montée et pointillés du couloir des zombies.
func _draw_stair_plan(o: Dictionary, alpha: float) -> void:
	var pl := MapRaster.stair_plan(o, 0.0, 3.5)
	var fill := Color(0.55, 0.35, 0.65, 0.55 * alpha)
	var line := Color(1, 1, 1, 0.35 * alpha)
	var arrow := Color(1, 1, 1, 0.9 * alpha)
	for poly: PackedVector2Array in pl.polys:
		var px := _px_poly(poly)
		_fill(px, fill)
		draw_polyline(px + PackedVector2Array([px[0]]), Color(0.85, 0.65, 0.95, 0.8 * alpha), 1.0)
	for l in pl.landings:
		_fill(_px_poly(l.poly), Color(0.7, 0.55, 0.8, 0.35 * alpha))
	var ramp: bool = pl.kind == "rampe"
	for f in pl.flights:
		var a := Vector2(f.a.x, f.a.z)
		var b := Vector2(f.b.x, f.b.z)
		var d := (b - a).normalized()
		var side := Vector2(-d.y, d.x) * (float(f.w) * 0.5)
		if not ramp:
			var n := StairGen.flight_steps(pl, float(f.b.y) - float(f.a.y))
			for i in n + 1:
				var q := a.lerp(b, float(i) / n)
				draw_line(to_px(q - side), to_px(q + side), line, 1.0)
		_arrow(to_px(a.lerp(b, 0.15)), to_px(a.lerp(b, 0.85)), arrow)
	var sp: Dictionary = pl.spiral
	if not sp.is_empty():
		var c: Vector2 = sp.c
		var e1: Vector2 = sp.e1
		var e2: Vector2 = sp.e2
		var pts := PackedVector2Array()
		for i in 33:
			var th := TAU * i / 32.0
			pts.append(to_px(c + (e1 * cos(th) + e2 * sin(th)) * float(sp.r_out)))
		draw_polyline(pts, Color(0.85, 0.65, 0.95, 0.9 * alpha), 1.5)
		for i in 16:
			var th := TAU * i / 16.0
			var dir := e1 * cos(th) + e2 * sin(th)
			draw_line(to_px(c + dir * float(sp.r_in)), to_px(c + dir * float(sp.r_out)), line, 1.0)
		draw_circle(to_px(c), maxf(float(sp.r_in) * zoom, 2.0), Color(0.3, 0.2, 0.35, 0.9 * alpha))
		var arc := PackedVector2Array()
		for i in 25:
			var th := TAU * 0.9 * i / 24.0
			arc.append(to_px(c + (e1 * cos(th) + e2 * sin(th)) * float(sp.rm)))
		draw_polyline(arc, arrow, 2.0)
		_arrow(arc[arc.size() - 2], arc[arc.size() - 1], arrow)
	# Couloir des zombies (ancres) en pointillés.
	if zoom >= 10.0:
		var prev := Vector2.INF
		for e in pl.lane:
			var q := to_px(Vector2(e[0].x, e[0].z))
			if prev != Vector2.INF:
				draw_dashed_line(prev, q, Color(1.0, 0.85, 0.3, 0.7 * alpha), 1.0, 4.0)
			prev = q
		var first: Vector3 = pl.lane[0][0]
		var last: Vector3 = pl.lane[pl.lane.size() - 1][0]
		draw_circle(to_px(Vector2(first.x, first.z)), 3.0, Color(1.0, 0.85, 0.3, 0.9 * alpha))
		draw_circle(to_px(Vector2(last.x, last.z)), 3.0, Color(1.0, 0.55, 0.2, 0.9 * alpha))


## Flèche de `a` à `b` (pixels).
func _arrow(a: Vector2, b: Vector2, col: Color) -> void:
	draw_line(a, b, col, 2.0)
	var d := (b - a).normalized()
	if d == Vector2.ZERO:
		return
	draw_line(b, b - d.rotated(0.5) * 8.0, col, 2.0)
	draw_line(b, b - d.rotated(-0.5) * 8.0, col, 2.0)


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
	if t == "fenetre" and zoom >= 14.0 and MapCatalog.barricade_kind(o) != "fenetre":
		# Porte à zombies (format 8) : son type écrit sur le plan.
		var pp := to_px(MapGeom.v2(o.position))
		var dn := Lang.t("PORTE", "DOOR") if MapCatalog.barricade_kind(o) == "porte" else Lang.t("DOUBLE PORTE", "DOUBLE DOOR")
		var dw := font.get_string_size(dn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10)).x
		draw_string_outline(font, pp + Vector2(-dw * 0.5, _u(4)), dn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), 3, Color(0, 0, 0, 0.9))
		draw_string(font, pp + Vector2(-dw * 0.5, _u(4)), dn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), Color(0.85, 0.95, 1.0))
		return
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
	# Aspect autre que celui par défaut (format 5) : son nom sous le prix.
	var va := MapCatalog.variant_of(o)
	if va != MapCatalog.default_variant(t) and zoom >= 14.0:
		var vn := MapCatalog.variant_name(t, va)
		var vw := font.get_string_size(vn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10)).x
		draw_string_outline(font, p + Vector2(-vw * 0.5, _u(16)), vn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), 3, Color(0, 0, 0, 0.9))
		draw_string(font, p + Vector2(-vw * 0.5, _u(16)), vn, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(10), Color(0.85, 0.95, 1.0))


## Étiquette sur fond sombre (mesures du tracé).
## Étage où mène un escalier, écrit sous sa flèche (zoom suffisant).
func _stair_floor_label(font: Font, o: Dictionary, lbl: String, col: Color) -> void:
	if zoom < 8.0:
		return
	var fs := EditorUi.fs(11)
	var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var fr := MapRules.footprint_rect(o)
	if lw > fr.size.x * zoom + _u(8):
		return   # trop serré : lisible en zoomant
	var lp := to_px(fr.get_center()) + Vector2(-lw * 0.5, _u(16))
	draw_string_outline(font, lp, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
	draw_string(font, lp, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Escalier tracé (posé à l'étage `k`, il monte à k + 1) : flèche de montée,
## cases du départ et de l'arrivée (MapRules.stair_parts), zones du refus.
func _draw_stair_trace(font: Font, o: Dictionary, k: int, res: Dictionary) -> void:
	var r := MapGeom.rect_of(o.rect)
	var d := MapGeom.dir_vec(String(o.get("monte", "n")))
	var half := (r.size.x if absf(d.x) > 0.5 else r.size.y) * 0.4
	var c := r.get_center()
	var col := Color(1, 1, 1, 0.95)
	var a := to_px(c - d * half)
	var b := to_px(c + d * half)
	draw_line(a, b, col, 3.0)
	draw_line(b, b - d.rotated(0.5) * 10.0, col, 3.0)
	draw_line(b, b - d.rotated(-0.5) * 10.0, col, 3.0)
	if res.ok and not res.has("marks"):
		var parts := MapRules.stair_parts(o)
		_draw_stair_marks(font, [{"floor": k, "cells": parts.foot.keys(), "role": "depart"},
			{"floor": int(res.get("to", k + 1)), "cells": parts.exit.keys(), "role": "arrivee"}], k)
	else:
		_draw_stair_marks(font, res.get("marks", []), k)


## Zones d'un escalier sur le plan : [{floor, cells, role}] ; role « depart »
## (vert), « arrivee » (bleu), « tremie » (contour violet), « faute » (rouge).
## Celles d'un autre étage que l'étage affiché : en pointillés, avec leur étage.
func _draw_stair_marks(font: Font, marks: Array, _k := -1) -> void:
	var cols := {"depart": Color(0.35, 0.95, 0.45), "arrivee": Color(0.35, 0.75, 1.0), "tremie": Color(0.8, 0.55, 0.95), "faute": COL_BAD}
	var names := {"depart": Lang.t("départ", "start"), "arrivee": Lang.t("arrivée", "arrival"), "tremie": Lang.t("trémie", "stairwell"), "faute": ""}
	for m: Dictionary in marks:
		var cells: Array = m.get("cells", [])
		if cells.is_empty():
			continue
		var role := String(m.get("role", "faute"))
		var here := int(m.get("floor", -1)) == ed.floor_k
		var col: Color = cols.get(role, COL_BAD)
		var bb := Rect2()
		for i in cells.size():
			var cr := Rect2(to_px((Vector2(cells[i]) - Vector2.ONE * 0.5) * MapGeom.CELL), Vector2.ONE * MapGeom.CELL * zoom)
			bb = cr if i == 0 else bb.merge(cr)
			if role == "faute":
				draw_rect(cr, Color(col, 0.55 if here else 0.3))
			elif role != "tremie":
				draw_rect(cr, Color(col, 0.22 if here else 0.1))
		if role == "faute":
			draw_rect(bb.grow(2), col, false, 2.5)
		elif here:
			draw_rect(bb, col, false, 2.0)
		else:
			var pts := [bb.position, Vector2(bb.end.x, bb.position.y), bb.end, Vector2(bb.position.x, bb.end.y)]
			for i in 4:
				draw_dashed_line(pts[i], pts[(i + 1) % 4], col, 1.5, 6.0)
		var nm := String(names.get(role, ""))
		if zoom >= 8.0 and nm != "":
			if not here:
				nm += Lang.t(" (étage %d)", " (floor %d)") % int(m.get("floor", 0))
			var fs := EditorUi.fs(11)
			var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			# Départ, arrivée : au-dessus de leur bande ; trémie : en son milieu.
			var p := Vector2(bb.get_center().x - w * 0.5, bb.get_center().y if role == "tremie" else bb.position.y - _u(4))
			draw_string_outline(font, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
			draw_string(font, p, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.3))


const COL_CARVE := Color(1.0, 0.62, 0.15)


## Découpe prévue pendant le tracé d'une pièce (MapCarve.plan) : la partie
## retirée de chaque pièce recouverte est hachurée en orange (en rouge : la
## pièce entière, qui sera supprimée), avec son nom et la surface retirée
## sous le curseur (`at`, px).
func _draw_carve(font: Font, pl: Dictionary, at: Vector2) -> void:
	var deleted := {}
	for v in pl.get("victims", []):
		if v.deleted:
			deleted[String(v.id)] = true
	var y := at.y + _u(14)
	for h in pl.get("cut", []):
		var gone := deleted.has(String(h.id))
		var col := COL_BAD if gone else COL_CARVE
		var polys: Array = h.parts
		if gone:
			var r := ed.doc.find(String(h.id))
			if not r.is_empty():
				polys = [ed.doc.room_poly(r)]
		for part in polys:
			var pts := _px_poly(part)
			_fill(pts, Color(col, 0.16))
			_carve_hatch(pts, Color(col, 0.85))
			draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.0)
		var fr := not Lang.is_en()
		var lbl := (Lang.t("« %s » sera supprimée", "\"%s\" will be deleted") % h.nom) if gone else \
			(Lang.t("découpe « %s » : −%s m²", "cut \"%s\": −%s m²") % [h.nom, MapRules._m(snappedf(float(h.area), 0.1), fr)])
		draw_string_outline(font, Vector2(at.x + _u(10), y), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), 4, Color.BLACK)
		draw_string(font, Vector2(at.x + _u(10), y), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, EditorUi.fs(13), col.lightened(0.3))
		y += _u(17)
	# Ouvertures qui seront retirées (leur mur disparaît) : entourées de rouge.
	for oid in pl.get("removed_ids", []):
		var o := ed.doc.find(String(oid))
		if not o.is_empty():
			outline_elem(o, COL_BAD, 2.5, 3.0)


## Hachures à 45° (tous les 8 px) dans le polygone `pts` (px).
func _carve_hatch(pts: PackedVector2Array, col: Color) -> void:
	var bb := MapGeom.bbox(pts)
	var step := maxf(_u(8), 4.0)
	var d := -bb.size.y
	while d < bb.size.x:
		var line := PackedVector2Array([Vector2(bb.position.x + d, bb.position.y), Vector2(bb.position.x + d + bb.size.y, bb.end.y)])
		for s in Geometry2D.intersect_polyline_with_polygon(line, pts):
			draw_polyline(s, col, 1.5)
		d += step


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
	if drag.get("kind", "") == "band":
		_draw_band(font)
		return
	if drag.get("kind", "") == "capture" or (ed.prefab_tools != null and ed.prefab_tools.capturing):
		# Format 10 : rectangle de capture du décor à grouper (prefab de la carte).
		if drag.get("kind", "") == "capture":
			var rc := Rect2(to_px(drag.start), Vector2.ZERO).expand(to_px(mouse_m))
			draw_rect(rc, Color(1.0, 0.85, 0.3, 0.12))
			draw_rect(rc, Color(1.0, 0.85, 0.3, 0.9), false, 2.0)
			for o in ed.prefab_tools.captured(Rect2(drag.start, Vector2.ZERO).expand(mouse_m)):
				outline_elem(o, Color(1.0, 0.85, 0.3), 2.0, 2.0)
		return
	# Découpe en attente de confirmation (boîte ouverte) : la pièce et les
	# parties retirées restent affichées.
	if not carve_pending.is_empty():
		var q: PackedVector2Array = carve_pending.poly
		var qp := _px_poly(q)
		_fill(qp, Color(COL_OK, 0.2))
		draw_polyline(qp + PackedVector2Array([qp[0]]), COL_OK, 2.0)
		_draw_carve(font, carve_pending.plan, to_px(MapGeom.bbox(q).end))
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
				var so: Dictionary = res.get("obj", {})
				if String(so.get("type", "")) == "escalier":
					# Escalier en cours de tracé : flèche, départ et arrivée (sur les
					# deux étages), et ce qui gêne s'il est refusé.
					_draw_stair_trace(font, so, int(res.get("floor", ed.floor_k)), res)
				var sz := (end - Vector2(drag.start)).abs()
				var lbl := "%s × %s m" % [MapRules._m(sz.x, not Lang.is_en()), MapRules._m(sz.y, not Lang.is_en())]
				_label_at(font, b + Vector2(_u(10), -_u(8)), lbl)
			if res.has("carve"):
				_draw_carve(font, res.carve, b)
	elif tool in POLY_TOOLS and not poly_pts.is_empty():
		var end := trace_end()
		var pts := _px_poly(poly_pts)
		pts.append(to_px(end))
		var test := poly_pts.duplicate()
		test.append(end)
		var res := _poly_creation(it, test) if test.size() >= 3 else {"ok": true}
		col = COL_OK if res.ok else COL_BAD
		if test.size() >= 3:
			_fill(pts, Color(col, 0.15))
		draw_polyline(pts, col, 2.0)
		for q in pts:
			draw_circle(q, 4.0, col)
		draw_arc(to_px(poly_pts[0]), 10.0, 0, TAU, 20, Color(1, 1, 1, 0.6), 1.5)
		_trace_label(font, poly_pts[-1], end)
		if res.has("carve"):
			_draw_carve(font, res.carve, to_px(end) + Vector2(0, _u(14)))
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
		elif MapGeom.item_oblique(o) and MapCatalog.tool_of(o) == "wall_item":
			_draw_object(o, font, 0.8)
			var poly := _px_poly(MapRules.wall_item_poly(o))
			draw_polyline(poly + PackedVector2Array([poly[0]]), col, 2.0)
		elif MapCatalog.floor_box(o):
			# Boîte au sol (format 15) : son emprise tournée exacte.
			_draw_object(o, font, 0.8)
			var poly := _px_poly(MapRaster.floor_poly(o))
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
