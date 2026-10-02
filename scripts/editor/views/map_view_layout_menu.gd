class_name MapViewLayoutMenu
extends PopupPanel
## Menu Disposition (docs/EDITOR_VIEWS.md, § 5 ; maquette, écran 4) : six
## vignettes dessinées à l'échelle de la disposition (1 vue, 2 côte à côte,
## 2 empilées, 3 : 1 + 2, 3 : 2 + 1, 4 vues · Ctrl+Alt+Q), la disposition en
## cours encadrée ; options : lier les vues, coupe partagée entre
## élévations, agrandir la vue active (Ctrl+Espace), réinitialiser.

var layout: MapViewLayout
var _grid: Control
var _rows: VBoxContainer
var _hover := -1
var _link: CheckBox
var _cut: CheckBox

const CELL := Vector2(96, 64)
const GAP := 6.0


func _init() -> void:
	name = "LayoutMenu"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1A1A1C")
	sb.border_color = Color("38383D")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 12
	add_theme_stylebox_override("panel", sb)


func _ready() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	var h4 := Label.new()
	h4.text = Lang.t("DISPOSITION DES VUES", "VIEW LAYOUT")
	h4.add_theme_color_override("font_color", Color("8C8575"))
	h4.add_theme_font_override("font", MapView.bold_font(600))
	h4.add_theme_font_size_override("font_size", 12)
	v.add_child(h4)
	_grid = Control.new()
	_grid.name = "Layouts"
	_grid.custom_minimum_size = Vector2(CELL.x * 3 + GAP * 2, CELL.y * 2 + GAP)
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_grid_input)
	_grid.mouse_exited.connect(func():
		_hover = -1
		_grid.queue_redraw())
	v.add_child(_grid)
	v.add_child(HSeparator.new())
	_link = CheckBox.new()
	_link.text = Lang.t("Lier les vues (axes communs)", "Link the views (shared axes)")
	_link.tooltip_text = Lang.t("Zoom commun et centre commun sur l'axe partagé (X entre Dessus et Avant, Z entre Avant et Droite)",
		"Shared zoom and shared centre on the common axis (X between Top and Front, Z between Front and Right)")
	_link.toggled.connect(func(on): layout.set_linked(on))
	_flat_check(_link)
	v.add_child(_link)
	_cut = CheckBox.new()
	_cut.text = Lang.t("Coupe partagée entre élévations", "Cut shared between elevations")
	_cut.tooltip_text = Lang.t("Une seule tranche pour toutes les élévations de même direction", "A single slice for all elevations of the same direction")
	_cut.toggled.connect(func(on): layout.set_shared_cut(on))
	_flat_check(_cut)
	v.add_child(_cut)
	var mx := _item(v, Lang.t("Agrandir la vue active", "Maximize the active view"), "Ctrl+Espace" if not Lang.is_en() else "Ctrl+Space")
	mx.pressed.connect(func():
		hide()
		layout.toggle_maximized(layout.active_pane))
	v.add_child(HSeparator.new())
	var rs := _item(v, Lang.t("Réinitialiser la disposition", "Reset the layout"), "")
	rs.pressed.connect(func():
		hide()
		layout.reset_layout())


## Case à cocher sans fond coloré (ligne de menu de la maquette).
static func _flat_check(c: CheckBox) -> void:
	for st in ["normal", "pressed", "hover", "hover_pressed", "focus"]:
		c.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	c.focus_mode = Control.FOCUS_NONE


## Ligne de menu : texte à gauche, raccourci à droite.
func _item(box: Container, text: String, kbd: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if kbd != "":
		var l := Label.new()
		l.text = kbd
		l.add_theme_color_override("font_color", Color("8C8575"))
		l.add_theme_font_override("font", UiStyle.font("mono"))
		l.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		l.position.x -= 4
		b.add_child(l)
		b.custom_minimum_size.x = 260
	box.add_child(b)
	return b


func open_at(p: Vector2) -> void:
	_link.set_pressed_no_signal(layout.linked)
	_cut.set_pressed_no_signal(layout.shared_cut)
	reset_size()
	position = Vector2i(p)
	popup()


func _cell_rect(i: int) -> Rect2:
	var f := EditorUi.factor()
	@warning_ignore("integer_division")
	return Rect2(Vector2((i % 3) * (CELL.x + GAP), (i / 3) * (CELL.y + GAP)) * f, CELL * f)


func _grid_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := -1
		for i in 6:
			if _cell_rect(i).has_point((event as InputEventMouseMotion).position):
				h = i
		if h != _hover:
			_hover = h
			_grid.tooltip_text = _label(h) if h >= 0 else ""
			_grid.queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for i in 6:
			if _cell_rect(i).has_point((event as InputEventMouseButton).position):
				hide()
				layout.set_layout(MapViewLayout.ORDER[i])
				return


static func _label(i: int) -> String:
	return [Lang.t("1 vue", "1 view"), Lang.t("2 côte à côte", "2 side by side"), Lang.t("2 empilées", "2 stacked"),
		"3 : 1 + 2" if not Lang.is_en() else "3: 1 + 2", "3 : 2 + 1" if not Lang.is_en() else "3: 2 + 1",
		Lang.t("4 vues · Ctrl+Alt+Q", "4 views · Ctrl+Alt+Q")][i]


## Rectangles (unités de la vignette 54 × 34) de chaque disposition.
const THUMBS := [
	[[1, 1, 52, 32]],
	[[1, 1, 25.5, 32], [27.5, 1, 25.5, 32]],
	[[1, 1, 52, 15.5], [1, 17.5, 52, 15.5]],
	[[1, 1, 30, 32], [32, 1, 21, 15.5], [32, 17.5, 21, 15.5]],
	[[1, 1, 25.5, 15.5], [27.5, 1, 25.5, 15.5], [1, 17.5, 52, 15.5]],
	[[1, 1, 25.5, 15.5], [27.5, 1, 25.5, 15.5], [1, 17.5, 25.5, 15.5], [27.5, 17.5, 25.5, 15.5]],
]


func _draw_grid() -> void:
	var f := EditorUi.factor()
	var font := UiStyle.font("body")
	var fs := MapView._fs(11.5)
	for i in 6:
		var r := _cell_rect(i)
		var sel: bool = MapViewLayout.ORDER[i] == layout.layout_id
		var bg := Color("2b2621") if sel else (Color("4D4233") if i == _hover else Color("222326"))
		_grid.draw_rect(r, bg)
		_grid.draw_rect(r.grow(-0.5), Color("D99940") if sel else Color("333338"), false, 1.0)
		var o := r.position + Vector2((r.size.x - 54.0 * f) * 0.5, 6.0 * f)
		for q in THUMBS[i]:
			var rr := Rect2(o + Vector2(q[0], q[1]) * f, Vector2(q[2], q[3]) * f)
			_grid.draw_rect(rr, Color("4a3a24") if sel else Color("2e2f33"))
			_grid.draw_rect(rr, Color("D99940") if sel else Color("6a6a72"), false, 1.0)
		var t := _label(i)
		var col := Color("FFE2B5") if sel else Color("CFC9B8")
		# Deux lignes au besoin (« 4 vues · Ctrl+Alt+Q »).
		var parts := t.split(" · ")
		var y := o.y + 34.0 * f + fs + 2.0 * f
		for ptxt in parts:
			var w := font.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_grid.draw_string(font, Vector2(r.position.x + (r.size.x - w) * 0.5, y), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			y += fs + 1.0
