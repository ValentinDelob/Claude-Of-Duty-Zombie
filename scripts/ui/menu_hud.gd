class_name MenuHud
extends Control
## Surimpression « caméra de surveillance » par-dessus le fond 3D : coins de
## cadrage, identifiant de caméra, voyant REC qui clignote, horodatage qui
## défile, niveau de signal. Discret : la scène doit rester le sujet.

const TEXT := Color(0.78, 0.76, 0.7, 0.55)
const REC := Color(0.9, 0.12, 0.08)

var _clock: Label
var _rec: Label
var _signal: Label
var _t := 0.0
var _start_sec := 3 * 3600 + 14 * 60 + 7


static func ocr_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["OCR A Extended", "OCR A", "Consolas", "monospace"])
	return f


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var font := ocr_font()
	var cam := _label(font, "CAM-07   SECTEUR K7   NIV. -3", 15, TEXT)
	cam.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cam.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cam.offset_left = -520
	cam.offset_right = -70
	cam.offset_top = 46
	_rec = _label(font, "● REC", 15, REC)
	_rec.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_rec.offset_left = -260
	_rec.offset_right = -190
	_rec.offset_top = 68
	_clock = _label(font, "", 15, TEXT)
	_clock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.offset_left = -190
	_clock.offset_right = -70
	_clock.offset_top = 68
	_signal = _label(font, "", 13, Color(TEXT, 0.4))
	_signal.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_signal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_signal.offset_left = -420
	_signal.offset_right = -70
	_signal.offset_top = -66
	var ver := _label(font, "v%s" % ProjectSettings.get_setting("application/config/version"), 13, Color(TEXT, 0.35))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.offset_left = -300
	ver.offset_right = -70
	ver.offset_top = -46
	resized.connect(queue_redraw)


func _label(font: Font, t: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(delta: float) -> void:
	_t += delta
	_rec.modulate.a = 1.0 if fmod(_t, 1.6) < 0.9 else 0.15
	var total := _start_sec + int(_t)
	var frames := int(fmod(_t, 1.0) * 25.0)
	_clock.text = "%02d:%02d:%02d:%02d" % [int(total / 3600.0) % 24, int(total / 60.0) % 60, total % 60, frames]
	var bars := 3 + int(1.5 + 1.5 * sin(_t * 0.7) * sin(_t * 1.9))
	_signal.text = "SIGNAL " + "▮".repeat(bars) + "▯".repeat(6 - bars)


func _draw() -> void:
	# Coins de cadrage.
	var m := 34.0
	var l := 46.0
	var c := Color(TEXT, 0.35)
	var r := Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
		draw_line(corner, corner + Vector2(l * sx, 0), c, 2.0)
		draw_line(corner, corner + Vector2(0, l * sy), c, 2.0)
