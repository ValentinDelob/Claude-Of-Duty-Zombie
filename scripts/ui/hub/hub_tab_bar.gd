class_name HubTabBar
extends Control
## Barre des onglets du hub (classe .tabs de la maquette, 46 px) : onglets à
## plat en Impact 18, l'onglet actif en jaune et 2 px plus haut, pastille
## rouge (nombre) en haut à droite d'un onglet ; à gauche et à droite, la
## touche de l'onglet précédent / suivant (Q / E au clavier, LB / RB à la
## manette). Un clic choisit l'onglet ; un clic sur Q / E fait défiler.

const HEIGHT := 46.0

## Libellés des onglets (déjà traduits).
var labels: PackedStringArray = []:
	set(v):
		labels = v
		queue_redraw()
var current := 0:
	set(v):
		current = v
		queue_redraw()
## Pastilles : index -> nombre (0 ou absent : aucune).
var badges: Dictionary = {}

signal tab_clicked(index: int)
## -1 : onglet précédent, +1 : suivant (clic sur Q / E).
signal step_clicked(dir: int)

var _tab_rects: Array[Rect2] = []
var _prev_rect := Rect2()
var _next_rect := Rect2()
var _hover := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, HubStyle.px(HEIGHT))
	Settings.input_device_changed.connect(func(_p): queue_redraw())


func set_badge(index: int, n: int) -> void:
	if n > 0:
		badges[index] = n
	else:
		badges.erase(index)
	queue_redraw()


func _font_size() -> int:
	return HubStyle.fs(18)


func _font() -> Font:
	return HubStyle.font("impact", HubStyle.em(0.05, _font_size()))


## Rectangle de l'onglet `i` (tests, souris).
func tab_rect(i: int) -> Rect2:
	_layout()
	return _tab_rects[i] if i >= 0 and i < _tab_rects.size() else Rect2()


func _layout() -> void:
	_tab_rects.clear()
	var b := HubStyle.px(2)
	var bottom := size.y - b
	var x := HubStyle.px(16)
	var kh := HubStyle.px(22)
	var ky := bottom - HubStyle.px(10) - kh
	var kw := _step_width(true)
	_prev_rect = Rect2(x, ky, kw, kh)
	x += kw + HubStyle.px(6) + HubStyle.px(4)
	var f := _font()
	var s := _font_size()
	var th := HubStyle.px(36)
	for i in labels.size():
		var w := HubStyle.text_width(labels[i], f, s) + HubStyle.px(15) * 2.0 + b * 2.0
		var h := th + (HubStyle.px(2) if i == current else 0.0)
		_tab_rects.append(Rect2(x, bottom - h, ceilf(w), h))
		x += ceilf(w) + HubStyle.px(4)
	x += HubStyle.px(6)
	_next_rect = Rect2(x, ky, _step_width(false), kh)


func _step_width(prev: bool) -> float:
	if Settings.using_pad:
		return HubKey.item_width("", JOY_BUTTON_LEFT_SHOULDER if prev else JOY_BUTTON_RIGHT_SHOULDER)
	return HubKey.item_width(HubPrompts.physical_key_name(KEY_Q if prev else KEY_E), -1)


func _draw() -> void:
	_layout()
	var r := Rect2(Vector2.ZERO, size)
	var b := HubStyle.px(2)
	draw_rect(r, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(0, r.size.y - b, r.size.x, b), HubStyle.BLACK)
	if Settings.using_pad:
		HubKey.draw_item(self, _prev_rect.position, "", JOY_BUTTON_LEFT_SHOULDER)
		HubKey.draw_item(self, _next_rect.position, "", JOY_BUTTON_RIGHT_SHOULDER)
	else:
		HubKey.draw_item(self, _prev_rect.position, HubPrompts.physical_key_name(KEY_Q), -1)
		HubKey.draw_item(self, _next_rect.position, HubPrompts.physical_key_name(KEY_E), -1)
	var f := _font()
	var s := _font_size()
	for i in _tab_rects.size():
		var tr := _tab_rects[i]
		var on := i == current
		# Contour noir sans bord bas, fond, biseau (inset 2px 2px).
		draw_rect(Rect2(tr.position, Vector2(tr.size.x, tr.size.y)), HubStyle.BLACK)
		var inner := Rect2(tr.position + Vector2(b, b), tr.size - Vector2(b * 2.0, b))
		var bg := HubStyle.YELLOW if on else (Color("33363A") if i == _hover else HubStyle.HEADER_BG)
		draw_rect(inner, bg)
		var hi := HubStyle.YELLOW_HI if on else HubStyle.PANEL_HI
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, b)), hi)
		draw_rect(Rect2(inner.position, Vector2(b, inner.size.y)), hi)
		if on:
			draw_rect(Rect2(inner.end.x - b, inner.position.y, b, inner.size.y), HubStyle.YELLOW_LO)
		var col := HubStyle.INK if on else (HubStyle.PLASTER if i == _hover else HubStyle.DIM)
		var tw := HubStyle.text_width(labels[i], f, s)
		# Texte : padding haut 7 px, bas 6 (8 pour l'onglet actif).
		var top := tr.position.y + b + HubStyle.px(7)
		var bottom_pad := HubStyle.px(8 if on else 6)
		draw_string(f, Vector2(tr.position.x + (tr.size.x - tw) * 0.5,
				HubStyle.baseline(f, s, top, tr.end.y - bottom_pad - top)), labels[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, s, col)
		if badges.get(i, 0) > 0:
			_draw_badge(tr, str(badges[i]))


## Pastille rouge (classe .badge : 20 px, à -6 / -8 du coin haut droit).
func _draw_badge(tr: Rect2, t: String) -> void:
	var f := HubStyle.font("bold")
	var s := HubStyle.fs(12)
	var w := maxf(HubStyle.px(20), HubStyle.text_width(t, f, s) + HubStyle.px(4) * 2.0 + HubStyle.px(4))
	var h := HubStyle.px(20)
	var r := Rect2(tr.end.x + HubStyle.px(6) - w, tr.position.y - HubStyle.px(8), w, h)
	HubStyle.draw_box(self, r, HubStyle.RED, HubStyle.px(2), 0.0)
	var tw := HubStyle.text_width(t, f, s)
	draw_string(f, Vector2(r.position.x + (w - tw) * 0.5, HubStyle.baseline(f, s, r.position.y, h)), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, s, Color.WHITE)


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var h := _index_at(mm.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 or _on_step(mm.position) != 0 else Control.CURSOR_ARROW
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var i := _index_at(mb.position)
		if i >= 0:
			accept_event()
			tab_clicked.emit(i)
			return
		var d := _on_step(mb.position)
		if d != 0:
			accept_event()
			step_clicked.emit(d)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


func _index_at(p: Vector2) -> int:
	_layout()
	for i in _tab_rects.size():
		if _tab_rects[i].has_point(p):
			return i
	return -1


func _on_step(p: Vector2) -> int:
	if _prev_rect.grow(HubStyle.px(4)).has_point(p):
		return -1
	if _next_rect.grow(HubStyle.px(4)).has_point(p):
		return 1
	return 0
