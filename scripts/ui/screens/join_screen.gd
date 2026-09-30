extends MenuScreen
## Rejoindre une partie par adresse IPv4 et port.

var _name: LineEdit
var _ip: LineEdit
var _port: LineEdit
var _error: Label


func enter(_args := {}) -> void:
	var col := vbox(10)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -230
	add_child(col)
	col.add_child(title(Lang.t("REJOINDRE UNE PARTIE", "JOIN A GAME"), 44))
	col.add_child(text("", 6))
	col.add_child(text(Lang.t("Nom du joueur", "Player name"), 18, UiStyle.DIM))
	_name = MenuStyle.line_edit(Settings.player_name, Lang.t("Survivant", "Survivor"), 16)
	col.add_child(_name)
	col.add_child(text(Lang.t("Adresse IP :", "IP address:"), 18, UiStyle.DIM))
	_ip = MenuStyle.line_edit(Settings.last_ip, "192.168.1.25", 15)
	col.add_child(_ip)
	col.add_child(text(Lang.t("Port :", "Port:"), 18, UiStyle.DIM))
	_port = MenuStyle.line_edit(str(Settings.last_port), "7777", 5)
	col.add_child(_port)
	_error = text("", 18, UiStyle.BLOOD_BRIGHT)
	col.add_child(_error)
	var join := button(Lang.t("REJOINDRE", "JOIN"), _join)
	col.add_child(join)
	col.add_child(button(Lang.t("RETOUR", "BACK"), back))
	_ip.text_submitted.connect(func(_t): _join())
	_port.text_submitted.connect(func(_t): _join())
	focus_later(join)


func _join() -> void:
	var ip := _ip.text.strip_edges()
	var port_txt := _port.text.strip_edges()
	@warning_ignore("static_called_on_instance")
	if not Net.is_valid_ipv4(ip):
		_error.text = Lang.t("Adresse IPv4 invalide (exemple : 192.168.1.25).", "Invalid IPv4 address (example: 192.168.1.25).")
		Audio.play_ui("ui_error", -6.0)
		return
	@warning_ignore("static_called_on_instance")
	if not port_txt.is_valid_int() or not Net.is_valid_port(port_txt.to_int()):
		_error.text = Lang.t("Port invalide (1024 à 65535).", "Invalid port (1024 to 65535).")
		Audio.play_ui("ui_error", -6.0)
		return
	@warning_ignore("static_called_on_instance")
	Settings.player_name = Net._clean_name(_name.text)
	Settings.last_ip = ip
	Settings.last_port = port_txt.to_int()
	Settings.save_settings()
	menu.show_screen("connecting", {"ip": ip, "port": port_txt.to_int()})


func back() -> void:
	menu.go_back()
