class_name ScorePanel
extends VBoxContainer
## Points de tous les joueurs (en bas à droite) + « +10 » flottants.

const SLOT_COLORS := [
	Color(0.92, 0.9, 0.85), Color(0.45, 0.65, 1.0), Color(0.98, 0.82, 0.3), Color(0.5, 0.9, 0.45),
	Color(0.9, 0.5, 0.9), Color(0.5, 0.9, 0.9), Color(1.0, 0.6, 0.4), Color(0.7, 0.7, 0.7),
]

var session: Session
var _rows: Dictionary = {}  # pid -> Label


static func slot_color(slot: int) -> Color:
	return SLOT_COLORS[slot % SLOT_COLORS.size()]


func bind(s: Session) -> void:
	session = s
	s.stats_changed.connect(func(_pid): refresh())
	s.points_event.connect(_on_points)
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		if not _rows.has(pid):
			var l := UiStyle.label("", 26, slot_color(Net.player_slot(pid)), "impact")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			add_child(l)
			_rows[pid] = l
		var row: Label = _rows[pid]
		var me := pid == multiplayer.get_unique_id()
		var dead := pd.life == PlayerData.Life.DEAD
		row.text = ("%s   %d" % [Net.player_name(pid), pd.points]) if Net.players.size() > 1 else str(pd.points)
		row.add_theme_font_size_override("font_size", 30 if me else 22)
		row.modulate = Color(1, 1, 1, 0.35 if dead else 1.0)


func _on_points(pid: int, delta: int) -> void:
	refresh()
	var row: Label = _rows.get(pid)
	if row == null or delta == 0:
		return
	var pop := UiStyle.label(("+%d" % delta) if delta > 0 else str(delta), 22, UiStyle.GOLD if delta > 0 else UiStyle.BLOOD_BRIGHT, "impact")
	get_parent().add_child(pop)
	var start := row.global_position + Vector2(-70.0 - randf() * 40.0, randf_range(-16.0, 12.0))
	pop.global_position = start
	var tw := pop.create_tween().set_parallel(true)
	tw.tween_property(pop, "global_position", start + Vector2(-70.0 - randf() * 40.0, randf_range(-30.0, 10.0)), 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(pop, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(pop.queue_free)
