extends MenuScreen
## Création d'une partie : nom, port, nombre maximum de joueurs.

var _name: LineEdit
var _port: LineEdit
var _max := Net.DEFAULT_MAX_PLAYERS
var _max_label: Label


func enter(_args := {}) -> void:
	var col := vbox(10)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -200
	add_child(col)
	col.add_child(title(Lang.t("HÉBERGER UNE PARTIE", "HOST A GAME"), 44))
	col.add_child(text("", 6))
	col.add_child(text(Lang.t("Nom du joueur", "Player name"), 18, UiStyle.DIM))
	_name = MenuStyle.line_edit(Settings.player_name, Lang.t("Survivant", "Survivor"), 16)
	col.add_child(_name)
	col.add_child(text("Port", 18, UiStyle.DIM))
	_port = MenuStyle.line_edit(str(Settings.last_port), "7777", 5)
	col.add_child(_port)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(text(Lang.t("Joueurs maximum :", "Max players:"), 20, UiStyle.DIM))
	_max_label = text(str(_max), 24)
	row.add_child(_max_label)
	row.add_child(button("-", func(): _set_max(_max - 1)))
	row.add_child(button("+", func(): _set_max(_max + 1)))
	col.add_child(text("", 6))
	var create := button(Lang.t("CRÉER LA PARTIE", "CREATE GAME"), _create)
	col.add_child(create)
	col.add_child(button(Lang.t("RETOUR", "BACK"), back))
	focus_later(create)


func _set_max(v: int) -> void:
	_max = clampi(v, 2, Net.MAX_SUPPORTED_PLAYERS)
	_max_label.text = str(_max)


func _create() -> void:
	var port := _port.text.strip_edges().to_int()
	@warning_ignore("static_called_on_instance")
	Settings.player_name = Net._clean_name(_name.text)
	if Net.host(port, _max, Settings.player_name) != OK:
		return  # le menu affiche l'erreur (Net.connection_error)
	Settings.last_port = port
	Settings.save_settings()
	GameState.set_state(GameState.State.LOBBY)
	menu.show_screen("lobby", {"host": true})


func back() -> void:
	menu.go_back()
