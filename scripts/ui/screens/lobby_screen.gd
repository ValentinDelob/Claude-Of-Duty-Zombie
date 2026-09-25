extends MenuScreen
## Salon d'avant-partie. Vue hôte : IP/port, joueurs, [DÉMARRER]. Vue client :
## serveur rejoint, joueurs, attente du lancement.

var is_host := false
var _list: VBoxContainer
var _start: Button
var _status: Label


func enter(args := {}) -> void:
	is_host = args.get("host", Net.mode == Net.Mode.HOST)
	var col := vbox(10)
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.offset_left = 110
	col.offset_top = -260
	add_child(col)
	col.add_child(title("CALL OF CLAUDE ZOMBIE", 40))
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
		_start = button("DÉMARRER", _on_start)
		col.add_child(_start)
	_status = text("" if is_host else "En attente du lancement...", 20, UiStyle.DIM)
	col.add_child(_status)
	var quit := button("QUITTER", back)
	col.add_child(quit)
	(_start if _start else quit).grab_focus.call_deferred()
	Net.players_changed.connect(_refresh)
	Net.player_left.connect(_on_left)
	_refresh()


func exit() -> void:
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


func _on_left(pid: int) -> void:
	if is_host:
		_status.text = "Un joueur est parti."


func _on_start() -> void:
	if not is_host or Net.players.is_empty():
		return
	_start.disabled = true
	_status.text = "Lancement..."
	Net.start_match(Game.requested_map())


func back() -> void:
	Net.leave()
	GameState.reset_to_menu()
	menu.show_screen("multiplayer", {}, false)
