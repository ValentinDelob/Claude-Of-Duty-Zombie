extends MenuScreen
## « Connexion au serveur... » pendant la poignée de main. En cas d'échec,
## MainMenu affiche le message d'erreur ; en cas de succès, le salon.

var _dots: Label
var _t := 0.0


func enter(args := {}) -> void:
	var col := vbox(12)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -100
	add_child(col)
	col.add_child(title(Lang.t("CONNEXION AU SERVEUR", "CONNECTING TO SERVER"), 44))
	col.add_child(text("%s:%d" % [args.ip, args.port], 26))
	_dots = text("", 26, UiStyle.DIM)
	col.add_child(_dots)
	var cancel := button(Lang.t("ANNULER", "CANCEL"), back)
	col.add_child(cancel)
	focus_later(cancel)
	GameState.set_state(GameState.State.CONNECTING)
	if Net.join(args.ip, args.port, Settings.player_name) != OK:
		return  # l'erreur est déjà signalée par Net.connection_error


func _process(delta: float) -> void:
	_t += delta
	_dots.text = Lang.t("Connexion", "Connecting") + ".".repeat(1 + int(_t * 2.0) % 3)


func back() -> void:
	Net.leave()
	GameState.reset_to_menu()
	menu.show_screen("join", {}, false)
