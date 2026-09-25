class_name MenuActionButton
extends Button
## Bouton de menu dessiné en code : texte au pochoir, trait de sang qui
## s'étire au survol / focus, chevron, léger décalage et éclat à la validation.
## Garde l'API de Button (pressed, disabled, grab_focus...).

var label := ""
var hint := ""
var font_size := MenuStyle.BUTTON_SIZE

var _focus_t := 0.0
var _flash := 0.0


func _ready() -> void:
	text = ""
	flat = true
	focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(s, empty)
	var font := UiStyle.font("impact")
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	custom_minimum_size = Vector2(w + 90.0, font_size * 1.45)
	mouse_entered.connect(func():
		if not disabled:
			grab_focus())
	focus_entered.connect(func():
		Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
		set_process(true))
	focus_exited.connect(func(): set_process(true))
	set_process(false)


## Éclat bref (validation).
func flash() -> void:
	_flash = 1.0
	set_process(true)


func _process(delta: float) -> void:
	var target := 1.0 if has_focus() and not disabled else 0.0
	_focus_t = move_toward(_focus_t, target, delta * (6.0 if target > _focus_t else 3.5))
	_flash = maxf(_flash - delta * 2.5, 0.0)
	queue_redraw()
	if _focus_t == target and _flash == 0.0:
		set_process(false)


func _draw() -> void:
	var f := _focus_t
	var ease_f := f * f * (3.0 - 2.0 * f)
	var h := size.y
	if ease_f > 0.001:
		MenuStyle.draw_highlight(self, Rect2(0, 1, size.x * (0.25 + 0.75 * ease_f) + 40.0 * _flash, h - 2), ease_f)
	var font := UiStyle.font("impact")
	var x := 22.0 + 16.0 * ease_f
	var base_y := h * 0.5 + font_size * 0.36
	var col := MenuStyle.IDLE.lerp(MenuStyle.FOCUS_TEXT, ease_f)
	if disabled:
		col = MenuStyle.DISABLED
	col = col.lerp(Color(1, 0.75, 0.6), _flash)
	# Chevron.
	if ease_f > 0.01:
		var c := Vector2(10.0 + 6.0 * ease_f, h * 0.5)
		var s := 6.0 * ease_f
		draw_colored_polygon(PackedVector2Array([c + Vector2(s, 0), c + Vector2(-s * 0.6, -s), c + Vector2(-s * 0.6, s)]), Color(MenuStyle.HOVER, ease_f))
	draw_string_outline(font, Vector2(x, base_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(x, base_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
