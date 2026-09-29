extends MenuScreen
## Salon d'avant-partie. Vue hôte : IP/port, joueurs, [DÉMARRER]. Vue client :
## serveur rejoint, joueurs, attente du lancement.

var is_host := false
var _list: VBoxContainer
var _start: Button
var _status: Label
## Hôte : carte choisie (Settings.last_map) et sa ligne ◄ ►.
var map_id := ""
var map_row: MenuOptionRow
var _map_label: Label


func enter(args := {}) -> void:
	is_host = args.get("host", Net.mode == Net.Mode.HOST)
	var col := vbox(10)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -260
	add_child(col)
	col.add_child(title("CLAUDE OF DUTY ZOMBIE", 40))
	if is_host:
		col.add_child(text("PARTIE PRIVÉE", 26, UiStyle.BONE))
	else:
		col.add_child(text("CONNECTÉ À :", 18, UiStyle.DIM))
		col.add_child(text("%s:%d" % [Net.server_address, Net.port], 28))
	var panel := MenuStyle.panel()
	panel.custom_minimum_size = Vector2(520, 0)
	col.add_child(panel)
	var inner := vbox(6)
	panel.add_child(inner)
	inner.add_child(text("Joueurs :", 20, UiStyle.DIM))
	_list = vbox(4)
	inner.add_child(_list)
	if is_host:
		var ips := Net.local_ipv4_addresses()
		var ip_text := ips[0] if ips.size() > 0 else "127.0.0.1"
		inner.add_child(text("", 4))
		inner.add_child(text("IP : %s" % ip_text, 24, UiStyle.GOLD))
		if ips.size() > 1:
			inner.add_child(text("(autres : %s)" % ", ".join(ips.slice(1)), 16, UiStyle.DIM))
		inner.add_child(text("PORT : %d" % Net.port, 24, UiStyle.GOLD))
		# Choix de la carte (mémorisé, annoncé aux clients).
		var names := PackedStringArray()
		for id in Game.MENU_MAPS:
			names.append(MapPreview.map_def(id).display_name)
		map_id = Settings.last_map if Settings.last_map in Game.MENU_MAPS else Game.MENU_MAPS[0]
		map_row = MenuOptionRow.make_choice("CARTE", names, Game.MENU_MAPS.find(map_id))
		map_row.value_changed.connect(_on_map_changed)
		map_row.focus_entered.connect(func(): menu.set_hint("◄ ► : carte de la partie."))
		col.add_child(map_row)
		_start = button("DÉMARRER", _on_start)
		col.add_child(_start)
	else:
		_map_label = text("CARTE : %s" % _map_name(Net.lobby_map), 22, UiStyle.GOLD)
		col.add_child(_map_label)
		Net.lobby_map_changed.connect(_on_lobby_map)
	_status = text("" if is_host else "En attente du lancement...", 20, UiStyle.DIM)
	col.add_child(_status)
	var quit := button("QUITTER", back)
	col.add_child(quit)
	focus_later((_start if _start else quit))
	Net.players_changed.connect(_refresh)
	Net.player_left.connect(_on_left)
	_refresh()


func _map_name(id: String) -> String:
	var def := MapPreview.map_def(id)
	return def.display_name if def else "..."


func _on_map_changed(v: float) -> void:
	map_id = Game.MENU_MAPS[clampi(int(v), 0, Game.MENU_MAPS.size() - 1)]
	Settings.last_map = map_id
	Settings.save_settings()
	Net.set_lobby_map(map_id)


func _on_lobby_map(id: String) -> void:
	if _map_label:
		_map_label.text = "CARTE : %s" % _map_name(id)


func exit() -> void:
	if Net.lobby_map_changed.is_connected(_on_lobby_map):
		Net.lobby_map_changed.disconnect(_on_lobby_map)
	if Net.players_changed.is_connected(_refresh):
		Net.players_changed.disconnect(_refresh)
	if Net.player_left.is_connected(_on_left):
		Net.player_left.disconnect(_on_left)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var by_slot := {}
	for pid in Net.players:
		by_slot[Net.player_slot(pid)] = pid
	for slot in Net.max_players:
		var line: Label
		if by_slot.has(slot):
			var pid: int = by_slot[slot]
			var tags := []
			if pid == 1:
				tags.append("hôte")
			if pid == multiplayer.get_unique_id():
				tags.append("vous")
			var suffix := ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""
			line = text("%d. %s%s" % [slot + 1, Net.player_name(pid), suffix], 24, ScorePanel.slot_color(slot))
		else:
			line = text("%d. En attente..." % (slot + 1), 22, Color(0.4, 0.38, 0.35))
		_list.add_child(line)
	if _start:
		_status.text = "%d/%d joueurs" % [Net.players.size(), Net.max_players]
		# Nouveaux arrivants : ils reçoivent la carte choisie.
		Net.set_lobby_map(map_id)


func _on_left(pid: int) -> void:
	if is_host:
		_status.text = "Un joueur est parti."


func _on_start() -> void:
	if not is_host or Net.players.is_empty():
		return
	_start.disabled = true
	_status.text = "Lancement..."
	Net.start_match(map_id)


func back() -> void:
	Net.leave()
	GameState.reset_to_menu()
	menu.show_screen("multiplayer", {}, false)
