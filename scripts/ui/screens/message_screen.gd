extends MenuScreen
## Message (erreur de connexion, déconnexion, fin de partie) + [RETOUR].

var _back_to := ""


func enter(args := {}) -> void:
	_back_to = args.get("back_to", "")
	var col := vbox(14)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -120
	add_child(col)
	col.add_child(title(args.get("title", ""), 44))
	var body := text(args.get("body", ""), 22)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(720, 0)
	col.add_child(body)
	col.add_child(text("", 10))
	var b := button("RETOUR", back)
	col.add_child(b)
	b.grab_focus.call_deferred()
	Audio.play_ui("ui_error", -4.0)


func back() -> void:
	if _back_to != "":
		menu.show_screen(_back_to, {}, false)
	else:
		menu.go_back()
