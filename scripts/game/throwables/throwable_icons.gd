class_name ThrowableIcons
extends Control
## HUD : petites icônes des grenades et des singes à gauche du compteur de
## munitions (comme BO1). Lit la réserve répliquée du joueur local.

const SLOT := 22.0
const ICON_SCALE := 1.35

var game: Game
var _frags := -1
var _monkeys := -1
var _has_monkeys := false


func _init(g: Game = null) -> void:
	game = g
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SLOT * 4 + 12, 46)
	size_flags_vertical = Control.SIZE_SHRINK_END


func _process(_delta: float) -> void:
	if game == null:
		return
	var pd := game.session.local_data()
	if pd == null:
		return
	if pd.grenades != _frags or pd.monkeys != _monkeys or pd.has_monkeys != _has_monkeys:
		_frags = pd.grenades
		_monkeys = pd.monkeys
		_has_monkeys = pd.has_monkeys
		custom_minimum_size.x = SLOT * (4 + (3 if _has_monkeys else 0)) + (22 if _has_monkeys else 12)
		queue_redraw()


func _draw() -> void:
	var y := size.y - 16.0
	var x := size.x - 16.0
	# De droite à gauche : grenades (près des munitions), puis singes.
	for i in maxi(_frags, 0):
		_draw_frag(Vector2(x - i * SLOT, y))
	if _has_monkeys:
		var mx := x - ThrowableRules.FRAG_MAX * SLOT - 14.0
		for i in ThrowableRules.MONKEY_MAX:
			_draw_monkey(Vector2(mx - i * SLOT, y), i < _monkeys)


func _draw_frag(at_pos: Vector2) -> void:
	draw_set_transform(at_pos, 0.0, Vector2.ONE * ICON_SCALE)
	var c := Vector2.ZERO
	var body := Color(0.52, 0.58, 0.36, 0.95)
	var dark := Color(0.08, 0.09, 0.05, 0.9)
	draw_circle(c + Vector2(0, 2), 6.6, dark)
	draw_circle(c + Vector2(0, 2), 5.6, body)
	draw_rect(Rect2(c + Vector2(-2.5, -7), Vector2(5, 4)), body)
	# Cuillère et anneau.
	draw_line(c + Vector2(2.5, -6), c + Vector2(6, 3), Color(0.8, 0.8, 0.75, 0.9), 1.6)
	draw_arc(c + Vector2(-4.5, -6.5), 2.4, 0.0, TAU, 10, Color(0.8, 0.8, 0.75, 0.9), 1.2)


func _draw_monkey(at_pos: Vector2, full: bool) -> void:
	draw_set_transform(at_pos, 0.0, Vector2.ONE * ICON_SCALE)
	var c := Vector2.ZERO
	var a := 0.95 if full else 0.22
	var fur := Color(0.55, 0.34, 0.16, a)
	draw_circle(c + Vector2(0, 1), 6.0, Color(0.05, 0.04, 0.03, a * 0.9))
	draw_circle(c + Vector2(0, 1), 5.0, fur)
	draw_circle(c + Vector2(0, 3), 2.6, Color(0.85, 0.7, 0.5, a))
	draw_rect(Rect2(c + Vector2(-3, -8), Vector2(6, 4)), Color(0.8, 0.1, 0.06, a))
	for s in [-1.0, 1.0]:
		draw_circle(c + Vector2(s * 7.5, 2), 2.8, Color(0.95, 0.75, 0.25, a))
