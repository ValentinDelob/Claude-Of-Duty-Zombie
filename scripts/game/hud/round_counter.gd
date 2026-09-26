class_name RoundCounter
extends Control
## Compteur de manche façon BO1, en bas à gauche : bâtons peints au sang pour
## les manches 1 à 5 (le 5e barre les quatre autres), puis chiffres peints à
## la main (dessin procédural, HudStyle.brush_stroke).
##
## Transitions (comme BO1) :
##   - fin de manche : le chiffre passe au blanc et pulse lentement
##     (blanc <-> rouge) pendant l'entracte ;
##   - début de manche : l'ancien chiffre s'efface, le nouveau apparaît en
##     blanc puis vire au rouge sang en pulsant ;
##   - manche de chiens : clignotement rouge braise tant qu'elle dure.

const HEIGHT := 112.0
const STROKE := 17.0
## Durées (s) de l'apparition d'une nouvelle manche : fondu, puis virage au rouge.
const INTRO_FADE := 0.7
const INTRO_TO_RED := 2.6
## Période de la pulsation de l'entracte.
const OUTRO_PERIOD := 1.6

enum Mode { IDLE, INTRO, OUTRO }

var round_n := 0
var special := false
var mode := Mode.IDLE
## Part de blanc dans la couleur (0 = rouge sang, 1 = blanc craie).
var whiteness := 0.0
var _t := 0.0
var _special_t := 0.0
var _shown := 0          # manche dessinée (l'ancienne pendant le fondu)
var _fade_old := 0.0     # fondu de sortie de l'ancienne manche


func _ready() -> void:
	custom_minimum_size = Vector2(300, HEIGHT + 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_round(n: int, starting: bool) -> void:
	if starting:
		_fade_old = 0.35 if _shown > 0 and _shown != n else 0.0
		round_n = n
		mode = Mode.INTRO
	else:
		round_n = n
		_shown = n
		mode = Mode.OUTRO
	_t = 0.0
	queue_redraw()


## Manche spéciale (chiens) : le compteur clignote tant qu'elle dure.
func set_special(on: bool) -> void:
	special = on
	_special_t = 0.0
	queue_redraw()


## Couleur courante (tests et dessin).
func current_color() -> Color:
	if special and mode == Mode.IDLE:
		var k := 0.5 + 0.5 * sin(_special_t * TAU * 0.8)
		return HudStyle.ROUND_RED.darkened(0.5).lerp(Color(1.0, 0.28, 0.08), k)
	return HudStyle.ROUND_RED.lerp(HudStyle.CHALK, whiteness)


func _process(delta: float) -> void:
	var animating := mode != Mode.IDLE or special
	if not animating:
		return
	_t += delta
	match mode:
		Mode.INTRO:
			if _fade_old > 0.0:
				# L'ancien chiffre s'efface d'abord (blanc).
				_fade_old = maxf(_fade_old - delta, 0.0)
				whiteness = 1.0
				modulate.a = _fade_old / 0.35
				if _fade_old <= 0.0:
					_t = 0.0
			else:
				_shown = round_n
				modulate.a = clampf(_t / INTRO_FADE, 0.0, 1.0)
				var k := clampf((_t - INTRO_FADE) / INTRO_TO_RED, 0.0, 1.0)
				# Pulsation qui s'éteint en virant au rouge.
				whiteness = (1.0 - k) * (0.75 + 0.25 * cos(_t * TAU * 1.2))
				if k >= 1.0:
					whiteness = 0.0
					mode = Mode.IDLE
		Mode.OUTRO:
			modulate.a = 1.0
			whiteness = 0.5 + 0.5 * cos(_t * TAU / OUTRO_PERIOD)
		Mode.IDLE:
			modulate.a = 1.0
			_special_t += delta
	queue_redraw()


func _draw() -> void:
	var n := _shown
	if n <= 0:
		return
	var col := current_color()
	var base_y := size.y - 6.0
	var top := base_y - HEIGHT
	if n <= 5:
		_draw_tallies(n, col, top, base_y)
	else:
		_draw_number(n, col, top)


## Bâtons : légèrement penchés et inégaux, le 5e en travers (BO1).
func _draw_tallies(n: int, col: Color, top: float, bottom: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in mini(n, 4):
		var x := 16.0 + i * 30.0
		var a := Vector2(x + rng.randf_range(-3.0, 4.0), top + rng.randf_range(0.0, 8.0))
		var b := Vector2(x + rng.randf_range(-7.0, 2.0), bottom - rng.randf_range(0.0, 6.0))
		HudStyle.brush_stroke(self, PackedVector2Array([a, a.lerp(b, 0.5) + Vector2(rng.randf_range(-2, 2), 0), b]), STROKE, col, 100 + i, 1.2)
	if n == 5:
		var a := Vector2(0.0, bottom - HEIGHT * 0.22)
		var b := Vector2(128.0, top + HEIGHT * 0.3)
		HudStyle.brush_stroke(self, PackedVector2Array([a, a.lerp(b, 0.5) + Vector2(0, 3), b]), STROKE * 1.05, col, 777, 0.6)


## Chiffres peints : chaque chiffre est une suite de traits de pinceau.
func _draw_number(n: int, col: Color, top: float) -> void:
	var digits := str(n)
	var h := HEIGHT
	var w := h * 0.62
	var x := 8.0
	for i in digits.length():
		var d := int(digits[i])
		var strokes: Array = HudStyle.digit_strokes(d)
		# Légère inclinaison et décalage propres à chaque chiffre.
		var skew := 0.06 + 0.02 * ((d * 7 + i) % 3)
		for s in strokes.size():
			var pts := PackedVector2Array()
			for p: Vector2 in strokes[s]:
				pts.append(Vector2(x + (p.x + (1.0 - p.y) * skew) * w, top + p.y * h))
			HudStyle.brush_stroke(self, pts, STROKE * 1.2, col, 31 * d + 7 * s + 1000 * i, 0.45)
		x += w + 12.0
