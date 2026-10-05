class_name MapViewPane
extends Control
## Fenêtre de vue de l'éditeur de cartes (docs/EDITOR_VIEWS.md, § 5) : un
## en-tête de 22 px (nom du plan, étages, axes de l'écran en couleurs, coupe,
## zoom, agrandir) au-dessus de sa vue (MapView). Vue active : en-tête plus
## clair et cadre or de 1 px.

const HEADER := 22.0
const COL_HEAD := Color("1C1D20")
const COL_HEAD_ACTIVE := Color("26272B")
const COL_HEAD_LINE := Color("2C2D31")
const COL_ACTIVE := Color("D99940")
const COL_CHIP := Color("2A2B2F")
const COL_CHIP_TXT := Color("CFC9B8")
const COL_CHIP_HL := Color("3a2f22")
const COL_CHIP_HL_TXT := Color("FFD9A0")
const COL_BONE := Color("DBD1B8")
const COL_DIM := Color("8C8575")

var layout: MapViewLayout
var view: MapView
## Plan d'origine de cette fenêtre (maison du ViewCube, réinitialisation).
var home_plane := "dessus"
var active := false
## Zones cliquables de l'en-tête : [{id, rect}].
var _hits: Array = []
var _hover_hit := ""
var _frame: Control
var _menu: PopupMenu


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_frame = Control.new()
	_frame.name = "ActiveFrame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.draw.connect(func():
		if active and layout != null and layout.pane_count() > 1:
			_frame.draw_rect(Rect2(Vector2(0.5, 0.5), _frame.size - Vector2.ONE), COL_ACTIVE, false, 1.0))
	add_child(_frame)
	mouse_exited.connect(func():
		_hover_hit = ""
		queue_redraw())


var _zoom_seen := -1.0
var _sub_seen := ""


## Le zoom de la vue et son sous-titre (niveau affiché, en 3D le mode de la
## caméra) sont écrits dans l'en-tête : redessiné quand ils changent.
func _process(_delta: float) -> void:
	if view == null:
		return
	if view.zoom != _zoom_seen:
		_zoom_seen = view.zoom
		queue_redraw()
	if view is MapView3D or view is MapCanvas:
		var sub := view.header_sub()
		if sub != _sub_seen:
			_sub_seen = sub
			queue_redraw()


func header_h() -> float:
	return EditorUi.px(HEADER)


## Place la vue sous l'en-tête.
func set_view(v: MapView) -> void:
	# L'élévation propre à la fenêtre reste son enfant, cachée (jamais orpheline).
	if view != null and view != v and view.get_parent() == self:
		if view is MapElevation or view is MapView3D:
			view.visible = false
		else:
			remove_child(view)
	view = v
	if v.get_parent() != self:
		if v.get_parent() != null:
			v.get_parent().remove_child(v)
		add_child(v)
	v.visible = true
	move_child(_frame, -1)
	v.setup_cube()
	v.place_cube()
	if v.cube != null:
		v.cube.active = active
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = header_h()
	queue_redraw()


func set_active(on: bool) -> void:
	if view != null and view.cube != null:
		view.cube.active = on
		view.cube.queue_redraw()
	if on == active:
		return
	active = on
	queue_redraw()
	_frame.queue_redraw()


## Taille de l'interface changée : hauteur de l'en-tête.
func ui_scale_changed() -> void:
	if view != null:
		view.offset_top = header_h()
	queue_redraw()


func plane() -> String:
	return view.plane if view != null else home_plane


# ------------------------------------------------------------------ en-tête

func _draw() -> void:
	var h := header_h()
	draw_rect(Rect2(0, 0, size.x, h), COL_HEAD_ACTIVE if active else COL_HEAD)
	draw_rect(Rect2(0, h - 1, size.x, 1), COL_HEAD_LINE)
	_hits = []
	if view == null:
		return
	var font := UiStyle.font("body")
	var fs := EditorUi.fs(12)
	var base := h * 0.5 + fs * 0.36
	var x := EditorUi.px(6)
	var gap := EditorUi.px(8)
	# Nom du plan : capitales espacées (+0,06 em), gras.
	var pl := view.plane
	x = _spaced(MapView.bold_font(), Vector2(x, base), MapView.plane_name(pl), fs, COL_BONE, fs * 0.06) + gap
	# Étages, sens du regard (élévations : clic, menu des étages).
	var sub := view.header_sub()
	# Fenêtre étroite : le texte des étages laisse la place aux axes et à ⛶.
	var axes_w := MapView.bold_font(600).get_string_size("X → · Z ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if pl != "3d" else 0.0
	if sub != "" and x + font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap + axes_w > size.x - EditorUi.px(30):
		sub = ""
	if sub != "":
		var w := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(x - 2, 2, w + 4, h - 4)
		if view.has_method("floors_menu_items"):
			_hits.append({"id": "floors", "rect": r})
			if _hover_hit == "floors":
				draw_rect(r, COL_CHIP)
		draw_string(font, Vector2(x, base), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_DIM)
		x += w + gap
	# Axes de l'écran, en couleurs (pas en 3D).
	if pl == "3d":
		_draw_right(font, fs, base, x, gap)
		return
	var ha := MapView.h_axis(pl)
	var va := MapView.v_axis(pl)
	var sf := MapView.bold_font(600)
	var t1 := "%s %s" % [String(ha[0]), "→" if int(ha[1]) > 0 else "←"]
	# Vertical : Z monte en élévation ; Y descend (le sud en bas) en Dessus et Dessous.
	var t2 := "Z ↑" if MapView.is_elevation(pl) else "Y ↓"
	draw_string(sf, Vector2(x, base), t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MapView.axis_color(String(ha[0])))
	x += sf.get_string_size(t1, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(sf, Vector2(x, base), " · ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_BONE)
	x += sf.get_string_size(" · ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(sf, Vector2(x, base), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MapView.axis_color(String(va[0])))
	x += sf.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_draw_right(font, fs, base, x, gap)


## Partie droite de l'en-tête : agrandir, puis les puces (de droite à gauche).
func _draw_right(font: Font, fs: int, base: float, x: float, gap: float) -> void:
	var h := header_h()
	# À droite : agrandir, puis les puces (de droite à gauche).
	var right := size.x - EditorUi.px(6)
	var iw := EditorUi.px(18)
	var ir := Rect2(right - iw, 2, iw, h - 4)
	if _hover_hit == "max":
		draw_rect(ir, COL_CHIP)
	_draw_max_icon(ir.get_center(), EditorUi.px(5), COL_CHIP_TXT)
	_hits.append({"id": "max", "rect": ir})
	right -= iw + gap
	var chips: Array = view.header_chips()
	for i in range(chips.size() - 1, -1, -1):
		var c: Dictionary = chips[i]
		var txt := String(c.text)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + EditorUi.px(12)
		if right - w < x + gap:
			break
		var cr := Rect2(right - w, (h - EditorUi.px(17)) * 0.5, w, EditorUi.px(17))
		var hl := bool(c.get("hl", false))
		var bg := COL_CHIP_HL if hl else COL_CHIP
		if _hover_hit == String(c.id):
			bg = Color("4D4233")
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(2)
		draw_style_box(sb, cr)
		draw_string(font, Vector2(cr.position.x + EditorUi.px(6), base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_CHIP_HL_TXT if hl else COL_CHIP_TXT)
		_hits.append({"id": String(c.id), "rect": cr})
		right -= w + gap


## Texte aux lettres espacées ; rend l'abscisse de sa fin.
func _spaced(font: Font, at: Vector2, txt: String, fs: int, col: Color, spacing: float) -> float:
	var x := at.x
	for ch in txt:
		draw_string(font, Vector2(x, at.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + spacing
	return x - spacing


## Icône ⛶ (quatre coins) dessinée.
func _draw_max_icon(c: Vector2, s: float, col: Color) -> void:
	var l := s * 0.7
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx, sy) * s
			draw_line(p, p - Vector2(sx * l, 0), col, 1.0)
			draw_line(p, p - Vector2(0, sy * l), col, 1.0)


func _hit_at(p: Vector2) -> String:
	for h in _hits:
		if (h.rect as Rect2).has_point(p):
			return String(h.id)
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hh := _hit_at((event as InputEventMouseMotion).position)
		if hh != _hover_hit:
			_hover_hit = hh
			queue_redraw()
		if layout != null:
			layout.set_active_pane(self)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		if layout != null:
			layout.set_active_pane(self)
		var id := _hit_at(mb.position)
		if mb.double_click and id == "" and mb.position.y < header_h():
			layout.toggle_maximized(self)
		elif id == "max":
			layout.toggle_maximized(self)
		elif id != "":
			_open_menu(id, mb.position)
		accept_event()


## Menu d'une puce de l'en-tête (coupe, étages, zoom).
func _open_menu(id: String, at: Vector2) -> void:
	var items: Array = view.header_menu(id)
	if items.is_empty():
		# Puce sans menu (« ⌖ Sélection », « Affichage ▾ » de la 3D) : action directe.
		view.header_menu_pressed(id, -1)
		return
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.name = "HeaderMenu"
		add_child(_menu)
		_menu.id_pressed.connect(func(i): view.header_menu_pressed(String(_menu.get_meta("chip", "")), i))
	_menu.clear()
	_menu.set_meta("chip", id)
	for it in items:
		if it.has("sep"):
			_menu.add_separator(String(it.sep))
		elif it.has("radio"):
			_menu.add_radio_check_item(String(it.text), int(it.id))
			_menu.set_item_checked(_menu.get_item_count() - 1, bool(it.radio))
		else:
			_menu.add_item(String(it.text), int(it.id))
			if bool(it.get("disabled", false)):
				_menu.set_item_disabled(_menu.get_item_count() - 1, true)
	_menu.reset_size()
	_menu.position = Vector2i(get_screen_position() + at + Vector2(0, EditorUi.px(12)))
	_menu.popup()
