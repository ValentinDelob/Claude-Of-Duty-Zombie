extends Control
## Menu principal (version provisoire, remplacée par le menu « Black Ops »).

func _ready() -> void:
	GameState.reset_to_menu()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var title := Label.new()
	title.text = "CALL OF CLAUDE ZOMBIE"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.7, 0.08, 0.08))
	box.add_child(title)
	var solo := Button.new()
	solo.text = "SOLO"
	solo.pressed.connect(Router.start_solo)
	box.add_child(solo)
	var quit := Button.new()
	quit.text = "QUITTER"
	quit.pressed.connect(Router.quit_game)
	box.add_child(quit)
	box.position -= box.get_combined_minimum_size() * 0.5
	if Router.pending_message != "":
		var msg := Label.new()
		msg.text = Router.pending_message
		box.add_child(msg)
		Router.pending_message = ""
	solo.grab_focus()
