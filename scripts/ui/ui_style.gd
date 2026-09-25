class_name UiStyle
extends RefCounted
## Polices et couleurs de l'interface. Polices système (non redistribuées) avec
## repli : Bahnschrift (condensée, militaire), Impact, Stencil, puis sans-serif.

const BLOOD := Color(0.62, 0.05, 0.04)
const BLOOD_BRIGHT := Color(0.85, 0.1, 0.06)
const BONE := Color(0.86, 0.82, 0.72)
const DIM := Color(0.55, 0.52, 0.46)
const GOLD := Color(0.95, 0.78, 0.35)

static var _fonts: Dictionary = {}


static func font(kind := "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f := SystemFont.new()
	match kind:
		"title":
			f.font_names = PackedStringArray(["Stencil", "Impact", "Bahnschrift", "Arial Black", "sans-serif"])
		"stencil":
			f.font_names = PackedStringArray(["Stencil", "Impact", "sans-serif"])
		"impact":
			f.font_names = PackedStringArray(["Impact", "Bahnschrift", "Arial Black", "sans-serif"])
		"mono":
			f.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		_:
			f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "sans-serif"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_fonts[kind] = f
	return f


static func label(text: String, size: int, color := BONE, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
