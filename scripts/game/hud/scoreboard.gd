class_name Scoreboard
extends PanelContainer
## Tableau des scores ([Tab] maintenu, et écran de fin de partie) façon BO1 :
## panneau sombre translucide, titre, en-têtes discrets, une ligne par joueur
## sur un bandeau à sa couleur (le joueur local plus lumineux).

var game: Game
var _rows_box: VBoxContainer
var _title: Label
var _sub: Label
var _header: Control

## En-têtes [français, anglais] (voir columns()).
## NIV. : niveau du joueur ; PUISSANCE : somme des scores de ses armes en
## main (GAME_CONCEPT §4.13, jamais affichée au hub).
const COLUMNS := [["JOUEUR", "PLAYER"], ["NIV.", "LVL"], ["PUISSANCE", "POWER"], ["FERRAILLE", "SCRAP"],
	["TUÉS", "KILLS"], ["TÊTES", "HEADSHOTS"], ["RÉANIM.", "REVIVES"], ["À TERRE", "DOWNS"]]
const WIDTHS := [215, 60, 100, 110, 80, 90, 90, 90]


func setup(g: Game) -> void:
	game = g
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.015, 0.018, 0.82)
	sb.border_color = Color(0.5, 0.48, 0.44, 0.35)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.set_content_margin_all(20)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -455
	offset_right = 455
	offset_top = -210
	offset_bottom = -60
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = HudStyle.label("", 34, HudStyle.TEXT, "title")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = HudStyle.label("", 16, HudStyle.TEXT_DIM, "text", 2)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)
	_header = _row(columns(), HudStyle.TEXT_DIM, 16, null)
	box.add_child(_header)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 4)
	box.add_child(_rows_box)
	visible = false


func refresh(title_text := "") -> void:
	if title_text != "":
		_title.text = title_text
	else:
		_title.text = Lang.t("MANCHE %d", "ROUND %d") % game.rounds.round_n if game.rounds.round_n > 0 else Lang.t("PRÉPARATION", "GET READY")
	# En-têtes dans la langue courante (elle a pu changer depuis le menu pause).
	var heads := columns()
	var hb := _header.get_child(0)
	for i in mini(hb.get_child_count(), heads.size()):
		(hb.get_child(i) as Label).text = heads[i]
	_sub.text = game.map_def.display_name if game.map_def else ""
	for c in _rows_box.get_children():
		c.queue_free()
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
		var cells := [Net.player_name(pid) + status, str(pd.level), str(pd.power()), str(pd.points), str(pd.kills), str(pd.headshots), str(pd.revives), str(pd.downs)]
		var me := pid == multiplayer.get_unique_id()
		_rows_box.add_child(_row(cells, HudStyle.TEXT if me else HudStyle.TEXT.lerp(col, 0.5), 24, col, me))


## Ligne du tableau : cellules à largeur fixe ; bandeau coloré si `col`.
func _row(cells: Array, text_col: Color, font_size: int, col: Variant, me := false) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	if col == null:
		sb.bg_color = Color(0, 0, 0, 0)
	else:
		var c: Color = col
		sb.bg_color = Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, 0.55 if me else 0.35)
		sb.border_color = c
		sb.border_width_left = 5
	sb.content_margin_left = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hb)
	for i in cells.size():
		var l := HudStyle.label(str(cells[i]), font_size, text_col, "condensed" if i > 0 or col == null else "text", 2)
		l.custom_minimum_size = Vector2(WIDTHS[i], 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(l)
	return panel


## En-têtes des colonnes dans la langue du joueur.
static func columns() -> Array:
	return COLUMNS.map(func(c: Array) -> String: return Lang.t(c[0], c[1]))
