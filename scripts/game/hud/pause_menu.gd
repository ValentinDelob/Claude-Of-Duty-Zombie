class_name PauseMenu
extends Control
## Menu pause ([Échap]). En solo la partie est suspendue ; en multijoueur elle
## continue (les zombies ne vous attendent pas).

var game: Game
var _first: Button


func setup(g: Game) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = 110
	col.offset_top = -140
	add_child(col)
	col.add_child(MenuStyle.title("PAUSE", 54))
	var sub := UiStyle.label("La partie continue pour vos coéquipiers." if Net.is_online() else "Partie suspendue.", 18, UiStyle.DIM)
	col.add_child(sub)
	col.add_child(UiStyle.label("", 10))
	_first = MenuStyle.button("REPRENDRE", close)
	col.add_child(_first)
	col.add_child(MenuStyle.button("QUITTER LA PARTIE", _leave))
	col.add_child(MenuStyle.button("QUITTER LE JEU", Router.quit_game))
	visible = false


func open() -> void:
	visible = true
	game.capture_mouse(false)
	if not Net.is_online():
		get_tree().paused = true
	_first.grab_focus.call_deferred()


func close() -> void:
	visible = false
	get_tree().paused = false
	game.capture_mouse(true)


func _leave() -> void:
	get_tree().paused = false
	Router.back_to_menu()
