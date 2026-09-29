class_name MapHotbar
extends PanelContainer
## Barre rapide de l'éditeur de cartes (9 cases, touches 1 à 9, molette),
## au bas de la vue, comme dans Minecraft. Le nom de l'objet choisi s'affiche
## au-dessus.

var ed: MapEditor
var slots: Array[MapSlot] = []
var _name: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.8)
	sb.set_content_margin_all(4)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_color_override("font_color", UiStyle.GOLD)
	v.add_child(_name)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	v.add_child(h)
	for i in 9:
		var s := MapSlot.new(50.0)
		s.index = i
		s.ed = ed
		s.clicked.connect(func(slot): ed.select_slot(slot.index))
		h.add_child(s)
		slots.append(s)
	queue_redraw_slots()
	get_parent().resized.connect(_place)
	resized.connect(_place)
	_place.call_deferred()


func _place() -> void:
	var p := get_parent() as Control
	position = Vector2((p.size.x - size.x) * 0.5, p.size.y - size.y - 8)


func queue_redraw_slots() -> void:
	for i in slots.size():
		slots[i].set_item(String(ed.hotbar[i]) if i < ed.hotbar.size() else "")
		slots[i].selected = i == ed.hot_index
		slots[i].queue_redraw()
	if _name != null:
		_name.text = MapCatalog.name_of(ed.current_item())
