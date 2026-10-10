class_name ScorePanel
extends VBoxContainer
## Ferraille (nom interne : points) de tous les joueurs, sous le libellé
## « FERRAILLE » / « SCRAP », en bas à droite au-dessus des munitions :
## un bandeau à la couleur du joueur (blanc, bleu, jaune, vert), le joueur
## local en plus grand, et des « +10 » dorés qui s'envolent vers la gauche.

## Compatibilité : couleurs des joueurs (voir HudStyle.PLAYER_COLORS).
const SLOT_COLORS := HudStyle.PLAYER_COLORS

var session: Session
var _rows: Dictionary = {}  # pid -> Label
static var _banners: Dictionary = {}  # couleur -> StyleBoxTexture


static func slot_color(slot: int) -> Color:
	return HudStyle.player_color(slot)


## Bandeau dégradé (transparent à gauche, couleur du joueur à droite), bord
## droit franc comme les cadres de points de BO1.
static func banner(col: Color) -> StyleBoxTexture:
	var key := col.to_html()
	if _banners.has(key):
		return _banners[key]
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_color(1, Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 0.62))
	g.add_point(0.55, Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 0.38))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 128
	tex.height = 4
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.content_margin_left = 70.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = -2.0
	sb.content_margin_bottom = -4.0
	_banners[key] = sb
	return sb


func bind(s: Session) -> void:
	session = s
	s.stats_changed.connect(func(_pid): refresh())
	s.points_event.connect(_on_points)
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Libellé de la monnaie au-dessus des montants : les « points » sont la
	# ferraille du joueur (GAME_CONCEPT §4.8).
	var title := HudStyle.label(Lang.t("FERRAILLE", "SCRAP"), 18, HudStyle.POINTS_GAIN, "condensed", 3)
	title.name = "ScrapTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(title)
	refresh()


func refresh() -> void:
	if session == null:
		return
	for pid in _rows.keys():
		if not session.data.has(pid):
			_rows[pid].queue_free()
			_rows.erase(pid)
	for pid in Net.sorted_peer_ids():
		var pd: PlayerData = session.data.get(pid)
		if pd == null:
			continue
		var col := slot_color(Net.player_slot(pid))
		if not _rows.has(pid):
			var l := HudStyle.label("", 30, HudStyle.TEXT, "condensed")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.add_theme_stylebox_override("normal", banner(col))
			add_child(l)
			_rows[pid] = l
		var row: Label = _rows[pid]
		var me := pid == multiplayer.get_unique_id()
		var dead := pd.life == PlayerData.Life.DEAD
		row.text = ("%s   %d" % [Net.player_name(pid), pd.points]) if Net.players.size() > 1 else str(pd.points)
		row.add_theme_font_size_override("font_size", 34 if me else 24)
		# Texte blanc, teinté par la couleur du joueur pour les coéquipiers.
		row.add_theme_color_override("font_color", HudStyle.TEXT if me else HudStyle.TEXT.lerp(col, 0.6))
		row.modulate = Color(1, 1, 1, 0.35 if dead else 1.0)


func _on_points(pid: int, delta: int) -> void:
	refresh()
	var row: Label = _rows.get(pid)
	if row == null or delta == 0:
		return
	var gain := delta > 0
	var pop := HudStyle.label(("+%d" % delta) if gain else str(delta), 26 if gain else 24,
			HudStyle.POINTS_GAIN if gain else HudStyle.POINTS_LOSS, "condensed", 3)
	get_parent().add_child(pop)
	# BO1 : le « +10 » naît près du score et s'envole vers la gauche en
	# s'éparpillant ; les dépenses tombent vers le bas.
	var start := row.global_position + Vector2(row.size.x - 150.0 - randf() * 30.0, randf_range(-10.0, 6.0))
	pop.global_position = start
	var drift := Vector2(-90.0 - randf() * 70.0, randf_range(-38.0, 14.0)) if gain else Vector2(-30.0, 34.0)
	var tw := pop.create_tween().set_parallel(true)
	tw.tween_property(pop, "global_position", start + drift, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pop, "modulate:a", 0.0, 0.7).set_delay(0.35)
	tw.chain().tween_callback(pop.queue_free)
