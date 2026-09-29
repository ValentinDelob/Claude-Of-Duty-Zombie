class_name MenuOptionRow
extends Control
## Ligne d'option du menu : libellé à gauche, valeur à droite
## (« ◄  jauge  valeur  ► »). Clavier : ◄ / ► changent la valeur, Entrée
## bascule (interrupteurs, listes). Souris : clic sur les flèches, sur la jauge
## (position directe) ou n'importe où pour faire défiler un choix.

enum Kind { RANGE, TOGGLE, CHOICE }

signal value_changed(value: float)

const HEIGHT := 36.0
const VALUE_X := 430.0  # début de la zone de valeur
const ARROW_W := 34.0
const GAUGE_W := 190.0
const SEGMENTS := 20

var label_text := ""
var kind := Kind.RANGE
var value := 0.0
var min_value := 0.0
var max_value := 1.0
var step := 0.05
var choices: PackedStringArray = []
## func(value: float) -> String : texte affiché pour une valeur (RANGE).
var formatter: Callable
## Faux : la molette n'est pas consommée (page d'options qui défile).
var wheel_nudges := true

var _focus_t := 0.0  # 0..1, animation de surbrillance
var _flash := 0.0  # éclat bref à chaque changement
var _nudge := 0.0  # recul de la flèche actionnée (-1 / +1)


static func make_range(label: String, v: float, lo: float, hi: float, st: float, fmt: Callable) -> MenuOptionRow:
	var r := MenuOptionRow.new()
	r.label_text = label
	r.kind = Kind.RANGE
	r.min_value = lo
	r.max_value = hi
	r.step = st
	r.formatter = fmt
	r.value = clampf(v, lo, hi)
	return r


static func make_toggle(label: String, on: bool) -> MenuOptionRow:
	var r := MenuOptionRow.new()
	r.label_text = label
	r.kind = Kind.TOGGLE
	r.choices = PackedStringArray([Lang.t("NON", "NO"), Lang.t("OUI", "YES")])
	r.min_value = 0.0
	r.max_value = 1.0
	r.step = 1.0
	r.value = 1.0 if on else 0.0
	return r


static func make_choice(label: String, options: PackedStringArray, index: int) -> MenuOptionRow:
	var r := MenuOptionRow.new()
	r.label_text = label
	r.kind = Kind.CHOICE
	r.choices = options
	r.min_value = 0.0
	r.max_value = options.size() - 1
	r.step = 1.0
	r.value = clampi(index, 0, options.size() - 1)
	return r


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	# PASS : les événements non consommés (molette d'une page qui défile)
	# remontent au ScrollContainer.
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(VALUE_X + ARROW_W * 2.0 + GAUGE_W + 110.0, HEIGHT)
	mouse_entered.connect(func(): grab_focus())
	focus_entered.connect(func():
		Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
		set_process(true))
	focus_exited.connect(func(): set_process(true))


func _process(delta: float) -> void:
	var target := 1.0 if has_focus() else 0.0
	_focus_t = move_toward(_focus_t, target, delta * (7.0 if target > _focus_t else 4.0))
	_flash = maxf(_flash - delta * 3.0, 0.0)
	_nudge = move_toward(_nudge, 0.0, delta * 6.0)
	queue_redraw()
	if _focus_t == target and _flash == 0.0 and _nudge == 0.0:
		set_process(false)


## Change la valeur de `dir` pas (les choix bouclent, les jauges butent).
func nudge(dir: int) -> void:
	var v := value + dir * step
	if kind == Kind.RANGE:
		v = clampf(snappedf(v, step), min_value, max_value)
	else:
		var n := int(max_value) + 1
		v = float(posmod(int(value) + dir, n))
	_nudge = float(dir)
	_set_value(v)


func _set_value(v: float) -> void:
	if is_equal_approx(v, value):
		Audio.play_ui("ui_error", -14.0)
		return
	value = v
	_flash = 1.0
	set_process(true)
	Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE + 2.0)
	value_changed.emit(value)


func index() -> int:
	return int(round(value))


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		nudge(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		nudge(1)
		accept_event()
	elif event.is_action_pressed("ui_accept") and kind != Kind.RANGE:
		nudge(1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if not wheel_nudges and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			nudge(1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			nudge(-1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_click(mb.position.x)
		accept_event()


func _click(x: float) -> void:
	grab_focus()
	var gx := VALUE_X + ARROW_W
	if x >= VALUE_X - 10.0 and x < gx:
		nudge(-1)
	elif kind != Kind.RANGE:
		nudge(1)  # clic sur le libellé ou la valeur : choix suivant
	elif x >= gx and x <= gx + GAUGE_W:
		var t := clampf((x - gx) / GAUGE_W, 0.0, 1.0)
		_set_value(clampf(snappedf(lerpf(min_value, max_value, t), step), min_value, max_value))
	elif x > gx + GAUGE_W:
		nudge(1)


func value_text() -> String:
	if kind == Kind.RANGE:
		return formatter.call(value) if formatter.is_valid() else str(value)
	return choices[clampi(index(), 0, choices.size() - 1)]


func _draw() -> void:
	var h := size.y
	var f := _focus_t
	# Bandeau de surbrillance : trait de sang qui s'étire depuis la gauche.
	if f > 0.001:
		MenuStyle.draw_highlight(self, Rect2(0, 2, size.x * (0.35 + 0.65 * f), h - 4), f)
	var font := UiStyle.font("impact")
	var col := MenuStyle.IDLE.lerp(MenuStyle.FOCUS_TEXT, f)
	var fs := 22
	var base_y := h * 0.5 + fs * 0.36
	draw_string_outline(font, Vector2(16 + 10 * f, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(16 + 10 * f, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# Flèches.
	var arrow_col := MenuStyle.DIM_TEXT.lerp(MenuStyle.HOVER, f)
	var ax := VALUE_X + ARROW_W * 0.5 + minf(_nudge, 0.0) * 5.0
	_arrow(Vector2(ax, h * 0.5), -1.0, arrow_col if _nudge >= 0.0 else MenuStyle.HOVER)
	var gx := VALUE_X + ARROW_W
	var vcol := UiStyle.BONE.lerp(Color(1, 0.55, 0.45), _flash)
	if kind == Kind.RANGE:
		# Jauge segmentée.
		var t := inverse_lerp(min_value, max_value, value)
		var seg_w := GAUGE_W / SEGMENTS
		var lit := int(round(t * SEGMENTS))
		for i in SEGMENTS:
			var r := Rect2(gx + i * seg_w + 1, h * 0.5 - 7, seg_w - 3, 14)
			if i < lit:
				var c := MenuStyle.GAUGE_ON.lerp(MenuStyle.HOVER, f * 0.5 + _flash * 0.5)
				draw_rect(r, c)
			else:
				draw_rect(r, Color(0.2, 0.18, 0.16, 0.6))
		var vt := value_text()
		draw_string(UiStyle.font("mono"), Vector2(gx + GAUGE_W + 12, base_y - 2), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, vcol)
		var rx := gx + GAUGE_W + 88.0 + maxf(_nudge, 0.0) * 5.0
		_arrow(Vector2(rx, h * 0.5), 1.0, arrow_col if _nudge <= 0.0 else MenuStyle.HOVER)
	else:
		var vt := value_text()
		var w := GAUGE_W + 88.0 - ARROW_W * 0.5
		draw_string_outline(font, Vector2(gx, base_y), vt, HORIZONTAL_ALIGNMENT_CENTER, w, 24, 5, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(gx, base_y), vt, HORIZONTAL_ALIGNMENT_CENTER, w, 24, vcol)
		# Petits repères : une case par choix.
		var n := choices.size()
		var pip := 10.0
		var start := gx + w * 0.5 - n * (pip + 4.0) * 0.5
		for i in n:
			var r := Rect2(start + i * (pip + 4.0), h - 7, pip, 3)
			draw_rect(r, MenuStyle.HOVER if i == index() else Color(0.3, 0.28, 0.25, 0.7))
		var rx := gx + w + ARROW_W * 0.5 + maxf(_nudge, 0.0) * 5.0
		_arrow(Vector2(rx, h * 0.5), 1.0, arrow_col if _nudge <= 0.0 else MenuStyle.HOVER)


func _arrow(c: Vector2, dir: float, col: Color) -> void:
	var s := 7.0
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(s * dir, 0), c + Vector2(-s * dir, -s), c + Vector2(-s * dir, s)]), col)
