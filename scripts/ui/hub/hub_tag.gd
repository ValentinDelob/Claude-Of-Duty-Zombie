class_name HubTag
extends Control
## Pastille du hub (classe .tag de la maquette) : texte gras de 11 px dans un
## pavé à contour noir. Sortes : simple, NOUVEAU, BASE, PRÊT, date de fin,
## verrou (« NIV. 9 REQUIS »).

const PLAIN := "plain"
const NEW := "new"
const BASE := "base"
const READY := "ready"
const DATE := "date"
const LOCK := "lockt"

const LOOKS := {
	PLAIN: [Color("3D4042"), Color("DBD6C2")],
	NEW: [Color("B81A1A"), Color("FFFFFF")],
	BASE: [Color("457366"), Color("E6F2EC")],
	READY: [Color("3D7A2A"), Color("EAFFDE")],
	DATE: [Color("734024"), Color("FFE7D4")],
	LOCK: [Color("2A2C2E"), Color("8E8A7E")],
}

var text := "":
	set(v):
		text = v
		_resize()
var kind := PLAIN:
	set(v):
		kind = v
		queue_redraw()


static func make(t: String, k := PLAIN) -> HubTag:
	var g := HubTag.new()
	g.text = t
	g.kind = k
	return g


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_resize()


func _fsize() -> int:
	return HubStyle.fs(11)


func _font() -> Font:
	return HubStyle.font("bold", HubStyle.em(0.04, _fsize()))


func _resize() -> void:
	var w := HubStyle.text_width(text, _font(), _fsize()) + HubStyle.px(6) * 2.0 + HubStyle.px(2) * 2.0
	var h := ceilf(_fsize() * 1.25) + HubStyle.px(1) * 2.0 + HubStyle.px(2) * 2.0
	custom_minimum_size = Vector2(ceilf(w), h)
	queue_redraw()


func _draw() -> void:
	var look: Array = LOOKS.get(kind, LOOKS[PLAIN])
	HubStyle.draw_box(self, Rect2(Vector2.ZERO, size), look[0], HubStyle.px(2), 0.0)
	var f := _font()
	var s := _fsize()
	var tw := HubStyle.text_width(text, f, s)
	draw_string(f, Vector2((size.x - tw) * 0.5, HubStyle.baseline(f, s, 0.0, size.y)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, s, look[1])
