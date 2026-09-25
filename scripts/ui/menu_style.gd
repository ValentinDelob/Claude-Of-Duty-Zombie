class_name MenuStyle
extends RefCounted
## Style des menus : boutons « militaires » (texte seul, chevron et lueur
## rouge au survol), titres au pochoir, champs de saisie sobres.

const BUTTON_SIZE := 30
const HOVER := Color(0.92, 0.2, 0.12)
const IDLE := Color(0.72, 0.69, 0.62)
const DISABLED := Color(0.35, 0.33, 0.3)


static func title(text: String, size := 44) -> Label:
	var l := UiStyle.label(text, size, UiStyle.BLOOD, "title")
	return l


static func button(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "   " + label
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", UiStyle.font("impact"))
	b.add_theme_font_size_override("font_size", BUTTON_SIZE)
	for state in ["font_color", "font_pressed_color"]:
		b.add_theme_color_override(state, IDLE)
	b.add_theme_color_override("font_hover_color", HOVER)
	b.add_theme_color_override("font_focus_color", HOVER)
	b.add_theme_color_override("font_hover_pressed_color", HOVER)
	b.add_theme_color_override("font_disabled_color", DISABLED)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("outline_size", 6)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(s, empty)
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus())
	b.focus_entered.connect(func():
		b.text = "> " + label
		Audio.play_ui("ui_move", -8.0)
		var tw := b.create_tween()
		tw.tween_property(b, "position:x", 14.0, 0.12).set_trans(Tween.TRANS_QUAD))
	b.focus_exited.connect(func():
		b.text = "   " + label
		var tw := b.create_tween()
		tw.tween_property(b, "position:x", 0.0, 0.2).set_trans(Tween.TRANS_QUAD))
	b.pressed.connect(func():
		Audio.play_ui("ui_select", -3.0)
		cb.call())
	return b


static func line_edit(value: String, placeholder := "", max_len := 32) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(360, 44)
	e.add_theme_font_override("font", UiStyle.font("mono"))
	e.add_theme_font_size_override("font_size", 24)
	e.add_theme_color_override("font_color", UiStyle.BONE)
	e.add_theme_color_override("caret_color", HOVER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.03, 0.85)
	sb.border_color = Color(0.45, 0.08, 0.06)
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	e.add_theme_stylebox_override("normal", sb)
	var sbf := sb.duplicate()
	sbf.border_color = HOVER
	e.add_theme_stylebox_override("focus", sbf)
	return e


## Panneau sombre semi-transparent (encadrés du salon...).
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.02, 0.72)
	sb.border_color = Color(0.3, 0.06, 0.05, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", sb)
	return p
