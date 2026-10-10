class_name HubChip
extends Control
## Puce de filtre du hub (classe .chip de la maquette) : texte semi-gras de
## 13 px dans un pavé à contour noir ; puce active : fond brun, texte jaune,
## liseré jaune de 3 px en bas. Se clique à la souris ; au clavier et à la
## manette, le filtre change par Tab / Y (le panneau), sans focus.

signal clicked

var text := "":
	set(v):
		text = v
		_resize()
var on := false:
	set(v):
		on = v
		queue_redraw()


static func make(t: String, active := false) -> HubChip:
	var c := HubChip.new()
	c.text = t
	c.on = active
	return c


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_resize()


func _fsize() -> int:
	return HubStyle.fs(13)


func _font() -> Font:
	return HubStyle.font("semi")


func _resize() -> void:
	var w := HubStyle.text_width(text, _font(), _fsize()) + HubStyle.px(9) * 2.0 + HubStyle.px(2) * 2.0
	var h := ceilf(_fsize() * 1.25) + HubStyle.px(3) * 2.0 + HubStyle.px(2) * 2.0
	custom_minimum_size = Vector2(ceilf(w), h)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	HubStyle.draw_box(self, r, Color("4A4126") if on else HubStyle.HEADER_BG, HubStyle.px(2), 0.0)
	if on:
		var b := HubStyle.px(2)
		draw_rect(Rect2(b, r.size.y - b - HubStyle.px(3), r.size.x - b * 2.0, HubStyle.px(3)), HubStyle.YELLOW)
	var f := _font()
	var s := _fsize()
	var tw := HubStyle.text_width(text, f, s)
	draw_string(f, Vector2((r.size.x - tw) * 0.5, HubStyle.baseline(f, s, 0.0, r.size.y - (HubStyle.px(2) if on else 0.0))),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, HubStyle.YELLOW_HI if on else HubStyle.DIM)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
		clicked.emit()


## Barre de filtres d'une liste (maquette : puces à gauche, « Tri : SCORE » à
## droite, liseré noir en bas). Clic sur une puce : `chip_clicked(i)` ; clic
## sur le tri : `sort_clicked`.
class FilterBar extends MarginContainer:
	signal chip_clicked(i: int)
	signal sort_clicked

	var chips: Array = []
	var sort_label: RichTextLabel
	var _row: HBoxContainer

	func _init(names: Array) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("margin_left", int(HubStyle.px(10)))
		add_theme_constant_override("margin_right", int(HubStyle.px(10)))
		add_theme_constant_override("margin_top", int(HubStyle.px(8)))
		add_theme_constant_override("margin_bottom", int(HubStyle.px(8) + HubStyle.px(2)))
		_row = HubBox.hbox(10)
		add_child(_row)
		# Les puces passent à la ligne s'il manque de place (130 %).
		var cs := HFlowContainer.new()
		cs.add_theme_constant_override("h_separation", int(HubStyle.px(6)))
		cs.add_theme_constant_override("v_separation", int(HubStyle.px(6)))
		cs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(cs)
		for i in names.size():
			var c := HubChip.make(String(names[i]))
			c.clicked.connect(func(): chip_clicked.emit(i))
			cs.add_child(c)
			chips.append(c)
		sort_label = RichTextLabel.new()
		sort_label.bbcode_enabled = true
		sort_label.fit_content = true
		sort_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		sort_label.scroll_active = false
		sort_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sort_label.mouse_filter = Control.MOUSE_FILTER_STOP
		sort_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		sort_label.add_theme_font_override("normal_font", HubStyle.font("ui"))
		sort_label.add_theme_font_override("bold_font", HubStyle.font("bold"))
		sort_label.add_theme_font_size_override("normal_font_size", HubStyle.fs(13))
		sort_label.add_theme_font_size_override("bold_font_size", HubStyle.fs(13))
		sort_label.add_theme_color_override("default_color", HubStyle.DIM)
		sort_label.gui_input.connect(_on_sort_input)
		_row.add_child(sort_label)

	func _on_sort_input(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
			sort_clicked.emit()

	## Puce active `active` et tri affiché `sort_name` (vide : pas de tri).
	func set_state(active: int, sort_name: String) -> void:
		for i in chips.size():
			(chips[i] as HubChip).on = i == active
		sort_label.text = "" if sort_name == "" else Lang.t("Tri : [b][color=#E0B31F]%s[/color][/b]",
				"Sort: [b][color=#E0B31F]%s[/color][/b]") % sort_name

	func _draw() -> void:
		draw_rect(Rect2(0, size.y - HubStyle.px(2), size.x, HubStyle.px(2)), HubStyle.BLACK)
