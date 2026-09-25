class_name Hud
extends CanvasLayer
## Interface en jeu. Ne contient aucune logique de gameplay : elle affiche
## l'état du joueur local.

var player: Player
var _crosshair: Control
var _debug: Label


func _ready() -> void:
	layer = 10
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	_debug = Label.new()
	_debug.position = Vector2(8, 6)
	_debug.add_theme_font_size_override("font_size", 13)
	_debug.modulate = Color(1, 1, 1, 0.55)
	add_child(_debug)


func bind_player(p: Player) -> void:
	player = p


func _process(_delta: float) -> void:
	_debug.text = "%d FPS" % Engine.get_frames_per_second()
	if player:
		_crosshair.spread = 0.0 if player.aiming else (18.0 if player.sprinting else 10.0)
		_crosshair.visible = not player.sprinting
		_crosshair.queue_redraw()


class Crosshair extends Control:
	var spread := 10.0

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.9, 0.9, 0.85, 0.75)
		var l := 7.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			draw_line(c + d * spread, c + d * (spread + l), col, 2.0)
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)
