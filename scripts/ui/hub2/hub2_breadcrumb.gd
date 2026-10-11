class_name Hub2Breadcrumb
extends Control
## Fil d'Ariane des sous-écrans du hub v2 (Contrats.dc.html, Echanges.dc.html) :
## « ‹ LABO » (rgba(242, 240, 234, 0.6), cliquable : retour), « / » (30 %),
## titre de l'écran (#F2F0EA) ; Chakra Petch 14 px 600, letter-spacing 0.12em,
## écart 10 px. Posé par Hub2Screen en (28, 92).

const SIZE := 14.0
const TRACKING := 0.12
const GAP := 10.0

var parent_label := "":
	set(v):
		parent_label = v
		_changed()
var title := "":
	set(v):
		title = v
		_changed()

signal parent_clicked


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	_changed()


func _font() -> Font:
	return Hub2Style.font(Hub2Style.CHAKRA, 600)


func _parts() -> Array:
	return ["‹ " + parent_label, "/", title]


func _w(t: String) -> float:
	var s := Hub2Style.fs(SIZE)
	return Hub2Style.text_width(t, _font(), s, Hub2Style.tracking_px(TRACKING, s))


func _changed() -> void:
	var p := _parts()
	var w := _w(p[0]) + _w(p[1]) + _w(p[2]) + Hub2Style.px(GAP) * 2.0
	custom_minimum_size = Vector2(ceilf(w), ceilf(Hub2Style.line_height(_font(), Hub2Style.fs(SIZE))))
	update_minimum_size()
	queue_redraw()


## Rectangle cliquable de « ‹ LABO ».
func parent_rect() -> Rect2:
	return Rect2(0, 0, _w(_parts()[0]), size.y)


func _draw() -> void:
	var f := _font()
	var s := Hub2Style.fs(SIZE)
	var tr := Hub2Style.tracking_px(TRACKING, s)
	var y := Hub2Style.baseline(f, s, 0.0, size.y)
	var cols := [Hub2Style.text_a(0.6), Hub2Style.text_a(0.3), Hub2Style.TEXT]
	var x := 0.0
	var p := _parts()
	for i in 3:
		x += Hub2Style.draw_text(self, f, Vector2(x, y), p[i], s, cols[i], tr) + Hub2Style.px(GAP)


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if parent_rect().has_point(mm.position) else Control.CURSOR_ARROW
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and parent_rect().has_point(mb.position):
		accept_event()
		parent_clicked.emit()
