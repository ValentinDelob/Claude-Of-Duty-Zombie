class_name Scoreboard
extends PanelContainer
## Tableau des scores ([Tab] maintenu, et écran de fin de partie).

var game: Game
var _grid: GridContainer
var _title: Label

const COLUMNS := ["JOUEUR", "POINTS", "TUÉS", "TÊTES", "RÉANIM.", "À TERRE"]


func setup(g: Game) -> void:
	game = g
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.015, 0.015, 0.86)
	sb.border_color = Color(0.4, 0.06, 0.05)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(24)
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -380
	offset_right = 380
	offset_top = -200
	offset_bottom = -60
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	_title = UiStyle.label("", 34, UiStyle.BLOOD, "title")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS.size()
	_grid.add_theme_constant_override("h_separation", 26)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)
	visible = false


func refresh(title_text := "") -> void:
	if title_text != "":
		_title.text = title_text
	else:
		_title.text = "MANCHE %d" % game.rounds.round_n if game.rounds.round_n > 0 else "PRÉPARATION"
	for c in _grid.get_children():
		c.queue_free()
	for h in COLUMNS:
		_grid.add_child(UiStyle.label(h, 18, UiStyle.DIM, "impact"))
	var ids := Net.sorted_peer_ids()
	if ids.is_empty():
		ids.assign(game.session.data.keys())
	for pid in ids:
		var pd := game.session.get_data(pid)
		if pd == null:
			continue
		var col := ScorePanel.slot_color(Net.player_slot(pid))
		var status := ""
		if pd.life == PlayerData.Life.DOWNED:
			status = " ✚"
		elif pd.life == PlayerData.Life.DEAD:
			status = " ✝"
		var cells := [Net.player_name(pid) + status, str(pd.points), str(pd.kills), str(pd.headshots), str(pd.revives), str(pd.downs)]
		for i in cells.size():
			var l := UiStyle.label(cells[i], 22, col if i == 0 else UiStyle.BONE)
			_grid.add_child(l)
