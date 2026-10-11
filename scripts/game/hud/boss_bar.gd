class_name BossBar
extends Control
## Jauge de vie d'un boss en haut de l'écran (HUD, vague de boss) : nom en
## police en cubes, rangée de CELLS cubes allumés selon les PV (dessinés comme
## ceux de l'écran de chargement, CubeFont.draw_cube), menthe des moniteurs
## puis orange d'alarme quand le boss enrage ; un cube qui vient de
## s'éteindre clignote. Valeurs reçues du serveur (SurgeonRound._cl_hp).

const CELLS := 40
const CELL := 12.0
const GAP := 2.0
const RAGE_COLOR := Color(1.0, 0.36, 0.2)

var fraction := 1.0
var rage := false
var _shown := 1.0
var _name: Label
var _bar: Control


func _init(title: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	var w := CELLS * (CELL + GAP)
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = 22.0
	offset_bottom = 22.0 + 30.0 + CELL + 6.0
	_name = HudStyle.label(title, 26, HudStyle.TITLE, "cube")
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(_name)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.position = Vector2(0.0, 34.0)
	_bar.size = Vector2(w, CELL)
	_bar.draw.connect(_draw_bar)
	add_child(_bar)


func set_fraction(f: float, enraged: bool) -> void:
	fraction = clampf(f, 0.0, 1.0)
	rage = enraged
	_bar.queue_redraw()


## Cubes allumés pour la fraction de PV `f` (au moins un tant qu'il vit).
static func lit_cells(f: float) -> int:
	if f <= 0.0:
		return 0
	return clampi(ceili(f * CELLS), 1, CELLS)


func _process(delta: float) -> void:
	if absf(_shown - fraction) > 0.001:
		_shown = move_toward(_shown, fraction, delta * 0.6)
		_bar.queue_redraw()


func _draw_bar() -> void:
	var lit := lit_cells(fraction)
	var ghost := lit_cells(_shown)
	var col := RAGE_COLOR if rage else HudStyle.ROUND
	for i in CELLS:
		var r := Rect2(i * (CELL + GAP), 0.0, CELL, CELL)
		if i < lit:
			CubeFont.draw_cube(_bar, r, col)
		elif i < ghost:
			CubeFont.draw_cube(_bar, r, HudStyle.TITLE.darkened(0.15))
		else:
			CubeFont.draw_cube(_bar, r, col.darkened(0.8))
