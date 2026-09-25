class_name RoundCounter
extends Control
## Compteur de manche en bas à gauche : bâtons de craie sanglants pour les
## manches 1 à 5, puis chiffres. Pulse au changement de manche.

var round_n := 0
var _label: Label
var _pulse := 0.0
var _blink := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(220, 110)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiStyle.label("", 92, UiStyle.BLOOD, "title")
	_label.position = Vector2(0, -8)
	add_child(_label)


func set_round(n: int, starting: bool) -> void:
	round_n = n
	if starting:
		_pulse = 1.0
	else:
		_blink = 3.0
	_label.text = str(n) if n > 5 else ""
	queue_redraw()


func _process(delta: float) -> void:
	if _pulse > 0.0 or _blink > 0.0:
		_pulse = maxf(_pulse - delta * 0.45, 0.0)
		_blink = maxf(_blink - delta, 0.0)
		var col := UiStyle.BLOOD.lerp(UiStyle.BONE, _pulse)
		if _blink > 0.0 and fmod(_blink, 0.5) < 0.25:
			col = UiStyle.BLOOD.darkened(0.6)
		modulate = Color(1, 1, 1, 1)
		self_modulate = col
		_label.add_theme_color_override("font_color", col)
		queue_redraw()


func _draw() -> void:
	if round_n <= 0 or round_n > 5:
		return
	var col := self_modulate if self_modulate != Color.WHITE else UiStyle.BLOOD
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in mini(round_n, 4):
		var x := 14.0 + i * 26.0
		var a := Vector2(x + rng.randf_range(-3, 3), 12)
		var b := Vector2(x + rng.randf_range(-4, 4), 96)
		draw_line(a, b, col, 9.0)
		draw_line(a + Vector2(3, 4), b + Vector2(2, -3), col.darkened(0.3), 3.0)
	if round_n == 5:
		draw_line(Vector2(2, 80), Vector2(118, 26), col, 9.0)
