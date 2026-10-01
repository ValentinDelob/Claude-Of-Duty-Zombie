class_name CollabHistory
extends VBoxContainer
## PANNEAU HISTORIQUE (onglet des panneaux de droite, aussi ouvert par
## Collaboration > Historique ; docs/MAP_COLLAB.md § 4 et 6) : les dernières
## actions de la carte, la plus récente en haut — pastille de la couleur de
## l'auteur, libellé, auteur et heure ; actions annulées grisées ; bouton
## « Annuler cette action » sur les miennes et celles de mon Claude (même
## règle de conflit que Ctrl+Z, message sous le titre si des éléments ont été
## modifiés entre-temps) ; survol d'une ligne = éléments touchés surlignés
## sur le plan. Reconstruit seulement quand l'onglet est affiché.

## Lignes affichées au plus (les plus récentes).
const MAX_ROWS := 100

var ed: MapEditor
var _note: Label
var _conflict: Label
var _list: VBoxContainer
var _dirty := true
var _queued := false
var _hover_cid := ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", UiStyle.DIM)
	add_child(_note)
	_conflict = Label.new()
	_conflict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conflict.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
	_conflict.visible = false
	add_child(_conflict)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	add_child(_list)
	visibility_changed.connect(func():
		if is_visible_in_tree() and _dirty:
			_queue())


func setup(editor: MapEditor) -> void:
	ed = editor
	ed.collab.committed.connect(func(_c): mark_dirty())
	ed.collab.map_replaced.connect(mark_dirty)
	ed.collab.session_changed.connect(mark_dirty)
	ed.collab.peers_changed.connect(mark_dirty)
	mark_dirty()


## L'historique a changé : reconstruit en fin d'image si l'onglet est affiché,
## sinon à son prochain affichage.
func mark_dirty() -> void:
	_dirty = true
	if is_visible_in_tree():
		_queue()


func _queue() -> void:
	if not _queued:
		_queued = true
		rebuild.call_deferred()


## Contenu du panneau (le plus récent d'abord) : [{cid, label, author,
## author_name, color, time, active, can_undo, ids}].
func entries_view() -> Array:
	var out := []
	if ed == null:
		return out
	var h := ed.collab.history
	var list: Array = h.entries
	for i in range(list.size() - 1, maxi(-1, list.size() - 1 - MAX_ROWS), -1):
		var e: Dictionary = list[i]
		var author := String(e.author)
		var remote := bool(e.get("remote", false))
		out.append({"cid": String(e.cid), "label": String(e.label), "author": author, "author_name": ed.collab.peer_name(author),
			"color": ed.collab_view.peer_color(author) if ed.collab_view != null else Color.WHITE,
			"time": time_text(int(e.get("time", 0))), "active": bool(e.active) and not remote,
			"can_undo": not remote and bool(e.active) and h.owned_by(String(e.cid), ed.collab.my_id),
			"ids": [] if remote else MapOps.ids_of(e.get("ops", []))})
	return out


## Heure locale « 14:32 » d'un horodatage Unix.
static func time_text(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_time_string_from_unix_time(unix + bias * 60).left(5)


func rebuild() -> void:
	_queued = false
	_dirty = false
	if ed == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var view := entries_view()
	_note.text = Lang.t("Aucune action pour l'instant.", "No action yet.") if view.is_empty() else Lang.t(
		"Survolez une action pour voir les éléments touchés sur le plan.", "Hover an action to see the elements it touched on the plan.")
	for v in view:
		_list.add_child(_row(v))
	if _hover_cid != "" and not view.any(func(v): return v.cid == _hover_cid):
		_set_hover("", [])


func _row(v: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.name = "Row_" + String(v.cid).validate_node_name()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.03)
	sb.set_content_margin_all(4)
	sb.set_corner_radius_all(3)
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	row.add_child(h)
	var dot := Dot.new()
	dot.color = v.color
	dot.agent = MapHistory.is_agent(String(v.author))
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	h.add_child(col)
	var l := Label.new()
	l.text = String(v.label)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.tooltip_text = String(v.label)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.custom_minimum_size = Vector2(60, 0)
	col.add_child(l)
	var meta := HBoxContainer.new()
	col.add_child(meta)
	var m := Label.new()
	m.text = "%s · %s" % [String(v.author_name), String(v.time)] + ("" if v.active else Lang.t(" · annulée", " · undone"))
	m.add_theme_color_override("font_color", UiStyle.DIM)
	m.add_theme_font_size_override("font_size", 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	m.custom_minimum_size = Vector2(40, 0)
	meta.add_child(m)
	if v.can_undo:
		var b := Button.new()
		b.name = "Undo"
		b.text = Lang.t("Annuler cette action", "Undo this action")
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", UiStyle.GOLD)
		var cid := String(v.cid)
		b.pressed.connect(func(): undo(cid))
		meta.add_child(b)
	if not v.active:
		row.modulate = Color(1, 1, 1, 0.45)
	var ids: Array = v.ids
	var cid2 := String(v.cid)
	row.mouse_entered.connect(func(): _set_hover(cid2, ids))
	row.mouse_exited.connect(func():
		if _hover_cid == cid2 and not row.get_global_rect().has_point(row.get_global_mouse_position()):
			_set_hover("", []))
	return row


func _set_hover(cid: String, ids: Array) -> void:
	_hover_cid = cid
	if ed.collab_view != null:
		ed.collab_view.hover_ids = ids
		ed.canvas.queue_redraw()


## Bouton « Annuler cette action » : rend le résultat de MapEditor.undo_entry ;
## un conflit (éléments modifiés entre-temps par un autre) est écrit sous le titre.
func undo(cid: String) -> Dictionary:
	var r := ed.undo_entry(cid)
	var txt := ed.collab.conflict_text(r) if not r.is_empty() and not r.has("queued") else ""
	_conflict.text = txt
	_conflict.visible = txt != ""
	mark_dirty()
	return r


## Pastille de la couleur de l'auteur (Claude : son icône).
class Dot extends Control:
	var color := Color.WHITE
	var agent := false

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		if agent:
			CollabView.draw_claude_icon(self, size * 0.5, r, color, Color.WHITE)
		else:
			draw_circle(size * 0.5, r, color)
