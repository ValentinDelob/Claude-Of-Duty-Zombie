class_name Hud
extends CanvasLayer
## Interface en jeu. Aucune logique de gameplay : elle affiche l'état du joueur
## local (données serveur via Session, prédiction d'armes via WeaponController).

var player: Player
var game: Game
var _crosshair: Crosshair
var _debug: Label
var _ammo: Label
var _reserve: Label
var _weapon_name: Label
var _hint: Label


func _ready() -> void:
	layer = 10
	game = get_parent()
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_debug = UiStyle.label("", 13, Color(1, 1, 1, 0.5), "mono")
	_debug.position = Vector2(8, 6)
	add_child(_debug)

	var ammo_box := VBoxContainer.new()
	ammo_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_box.offset_right = -36
	ammo_box.offset_bottom = -26
	ammo_box.alignment = BoxContainer.ALIGNMENT_END
	ammo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ammo_box)
	_weapon_name = UiStyle.label("", 18, UiStyle.DIM, "impact")
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(_weapon_name)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_box.add_child(row)
	_ammo = UiStyle.label("0", 44, UiStyle.BONE, "impact")
	row.add_child(_ammo)
	_reserve = UiStyle.label("/ 0", 24, UiStyle.DIM, "impact")
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_reserve)

	_hint = UiStyle.label("", 22, UiStyle.BONE)
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(-300, 60)
	_hint.size = Vector2(600, 40)
	add_child(_hint)


func bind_player(p: Player) -> void:
	player = p


func _process(_delta: float) -> void:
	_debug.text = "%d FPS" % Engine.get_frames_per_second()
	if player == null:
		return
	_crosshair.spread = 0.0 if player.aiming else (18.0 if Vector2(player.velocity.x, player.velocity.z).length() > 1.0 else 10.0)
	_crosshair.visible = not player.sprinting and not player.aiming
	_crosshair.queue_redraw()
	var wc := player.weapons
	if wc:
		var w := wc.current()
		if not w.is_empty():
			var s := wc.current_stats()
			_weapon_name.text = s.name
			_ammo.text = str(w.mag)
			_reserve.text = " / %d" % w.reserve
			var low: bool = w.mag <= int(s.mag) / 4
			_ammo.add_theme_color_override("font_color", UiStyle.BLOOD_BRIGHT if low else UiStyle.BONE)
			if w.mag == 0 and w.reserve == 0:
				_hint.text = "PLUS DE MUNITIONS"
			elif wc.is_reloading():
				_hint.text = "RECHARGEMENT..."
			elif low and w.reserve > 0:
				_hint.text = "[R] RECHARGER"
			else:
				_hint.text = ""


class Crosshair extends Control:
	var spread := 10.0

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.9, 0.9, 0.85, 0.75)
		var l := 7.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
			draw_line(c + d * spread, c + d * (spread + l), col, 2.0)
		draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)
