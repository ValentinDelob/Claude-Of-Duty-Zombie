class_name RoundCounter
extends Control
## Compteur de manche, en bas à gauche : le numéro de la manche en chiffres
## de cubes (CubeFont, 5 x 7 cubes par chiffre), couleur menthe des moniteurs
## du laboratoire, dès la manche 1.
##
## Transitions (propres au jeu) :
##   - début de manche : les cubes de l'ancien numéro tombent et s'éteignent,
##     puis ceux du nouveau tombent en place rangée par rangée, du bas vers le
##     haut, chauffés à blanc, et refroidissent vers la menthe ;
##   - fin de manche : le numéro passe en veille, une ligne de balayage le
##     parcourt et il pulse (menthe <-> blanc) pendant l'entracte ;
##   - vague spéciale : les cubes passent à l'orange d'alarme, rayés de bandes
##     de danger qui défilent, tant qu'elle dure.

## Côté d'un cube (px, base 1280 x 720) : un chiffre fait 98 px de haut.
const CUBE := 14.0
const HEIGHT := CUBE * CubeFont.CAP_ROWS
## Chute de l'ancien numéro (s).
const FALL_TIME := 0.4
## Construction du nouveau : retard par rangée et par colonne, durée de chute
## d'un cube, hauteur de chute (px).
const ROW_DELAY := 0.07
const COL_DELAY := 0.018
const DROP_TIME := 0.2
const DROP_HEIGHT := 46.0
## Refroidissement (blanc -> menthe) après la construction.
const COOL_TIME := 1.8
## Période de la pulsation de l'entracte.
const OUTRO_PERIOD := 1.6

enum Mode { IDLE, INTRO, OUTRO }

var round_n := 0
var special := false
var mode := Mode.IDLE
## Part de blanc dans la couleur des cubes (0 = menthe, 1 = chauffé à blanc).
var heat := 0.0
var _t := 0.0
var _special_t := 0.0
var _shown := 0          # manche dessinée (l'ancienne pendant sa chute)
var _fall := 0.0         # avancement de la chute de l'ancienne manche (0..1)
var _falling := false
var _build_t := -1.0     # temps depuis le début de la construction (-1 : construit)


func _ready() -> void:
	custom_minimum_size = Vector2(300, HEIGHT + 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_round(n: int, starting: bool) -> void:
	if starting:
		_falling = _shown > 0 and _shown != n
		_fall = 0.0
		round_n = n
		mode = Mode.INTRO
		if not _falling:
			_start_build()
	else:
		round_n = n
		_shown = n
		_falling = false
		_build_t = -1.0
		mode = Mode.OUTRO
	_t = 0.0
	queue_redraw()


## Vague spéciale : le compteur passe en alerte tant qu'elle dure.
func set_special(on: bool) -> void:
	special = on
	_special_t = 0.0
	queue_redraw()


## Couleur de base courante des cubes (tests et dessin).
func current_color() -> Color:
	if special and mode == Mode.IDLE:
		var k := 0.5 + 0.5 * sin(_special_t * TAU * 1.6)
		return HudStyle.ALERT.darkened(0.35).lerp(HudStyle.ALERT, k)
	return HudStyle.ROUND.lerp(HudStyle.TITLE, heat)


## Durée totale de la construction d'un numéro de `digits` chiffres.
static func build_time(digits: int) -> float:
	return (CubeFont.CAP_ROWS - 1) * ROW_DELAY + (digits * 6 - 1) * COL_DELAY + DROP_TIME


func _start_build() -> void:
	_shown = round_n
	_build_t = 0.0
	heat = 1.0
	modulate.a = 1.0


func _process(delta: float) -> void:
	var animating := mode != Mode.IDLE or special
	if not animating:
		return
	_t += delta
	match mode:
		Mode.INTRO:
			if _falling:
				_fall = minf(_fall + delta / FALL_TIME, 1.0)
				heat = 0.0
				if _fall >= 1.0:
					_falling = false
					_t = 0.0
					_start_build()
			else:
				_build_t += delta
				var built := build_time(str(_shown).length())
				if _build_t < built:
					heat = 1.0
				else:
					var k := clampf((_build_t - built) / COOL_TIME, 0.0, 1.0)
					# Refroidissement avec un léger scintillement qui s'éteint.
					heat = (1.0 - k) * (0.8 + 0.2 * cos(_build_t * TAU * 3.0))
					if k >= 1.0:
						heat = 0.0
						_build_t = -1.0
						mode = Mode.IDLE
		Mode.OUTRO:
			heat = 0.5 - 0.5 * cos(_t * TAU / OUTRO_PERIOD)
		Mode.IDLE:
			_special_t += delta
	queue_redraw()


func _draw() -> void:
	var n := _shown
	if n <= 0:
		return
	var col := current_color()
	var top := size.y - 6.0 - HEIGHT
	var digits := str(n)
	var cubes: Array = []  # [rect, rangée, colonne globale]
	for i in digits.length():
		var g := CubeFont.glyph(digits[i])
		var x0 := 8.0 + i * 6.0 * CUBE
		for row in CubeFont.CAP_ROWS:
			var line: String = g[CubeFont.ACCENT_ROWS + row]
			for c in line.length():
				if line[c] == "#":
					cubes.append([Rect2(x0 + c * CUBE, top + row * CUBE, CUBE, CUBE), row, i * 6 + c])
	# Liseré sombre sous tous les cubes en place (lisible sur le décor).
	for e in cubes:
		var r := _placed(e)
		if r.size.x > 0.0:
			draw_rect(r.grow(2.0), Color(0.0, 0.03, 0.04, 0.8 * r.size.x / CUBE))
	var scan_row := -1
	if mode == Mode.OUTRO:
		scan_row = int(fmod(_t / OUTRO_PERIOD, 1.0) * (CubeFont.CAP_ROWS + 3)) - 1
	for e in cubes:
		var r := _placed(e)
		if r.size.x <= 0.0:
			continue
		var c := col
		if special and mode == Mode.IDLE:
			# Bandes de danger en diagonale qui défilent.
			var band := int(floor((float(e[2]) + float(e[1]) - _special_t * 6.0) / 2.0))
			if posmod(band, 2) == 0:
				c = c.darkened(0.45)
		if int(e[1]) == scan_row:
			c = c.lerp(HudStyle.TITLE, 0.6)
		CubeFont.draw_cube(self, r, c)


## Rectangle d'un cube selon l'animation : chute de l'ancien numéro, ou chute
## en place pendant la construction (taille nulle : pas encore apparu).
func _placed(e: Array) -> Rect2:
	var r: Rect2 = e[0]
	if _falling:
		# Chaque colonne tombe avec un léger décalage, et s'éteint.
		var k := clampf(_fall * 1.4 - float(e[2]) * 0.03, 0.0, 1.0)
		if k >= 1.0:
			return Rect2()
		var s := CUBE * (1.0 - 0.5 * k)
		return Rect2(r.position + Vector2((CUBE - s) * 0.5, k * k * 70.0), Vector2(s, s))
	if _build_t >= 0.0:
		var start := float(CubeFont.CAP_ROWS - 1 - int(e[1])) * ROW_DELAY + float(e[2]) * COL_DELAY
		var k := (_build_t - start) / DROP_TIME
		if k <= 0.0:
			return Rect2()
		k = minf(k, 1.0)
		return Rect2(r.position - Vector2(0.0, (1.0 - k * k) * DROP_HEIGHT), r.size)
	return r
