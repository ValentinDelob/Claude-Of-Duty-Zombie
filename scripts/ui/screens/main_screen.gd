extends MenuScreen
## Écran principal : SOLO / MULTIJOUEUR / QUITTER.

var _first: Button


func enter(_args := {}) -> void:
	var col := vbox(6)
	col.position = Vector2(110, 0)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -150
	add_child(col)
	var t := title("CALL OF CLAUDE ZOMBIE", 58)
	col.add_child(t)
	col.add_child(text("", 12))
	_first = button("SOLO", func(): Router.start_solo())
	col.add_child(_first)
	col.add_child(button("MULTIJOUEUR", func(): menu.show_screen("multiplayer")))
	col.add_child(button("QUITTER", Router.quit_game))
	_first.grab_focus.call_deferred()


func back() -> void:
	pass
