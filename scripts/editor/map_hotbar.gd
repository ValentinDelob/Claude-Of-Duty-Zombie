class_name MapHotbar
extends PanelContainer
## Barre rapide de l'éditeur de cartes (9 cases, touches 1 à 9, molette),
## au bas de la vue, comme dans Minecraft. Le nom de l'objet choisi s'affiche
## au-dessus. À gauche, une case fixe : la souris (outil Sélection, touche ²
## ou Échap), jamais remplacée par un objet de l'inventaire.

var ed: MapEditor
var slots: Array[MapSlot] = []
## Case fixe de la souris (à gauche des 9 cases).
var mouse_slot: MapSlot
var _gap: Control
var _name: Label


## Barre rapide relue (défaut, préférences, ancienne sauvegarde) : 9 cases,
## l'ancien outil « select » retiré (la souris a sa propre case), les objets
## inconnus vidés.
static func migrate(items: Array) -> Array:
	var out := []
	for i in 9:
		var id := String(items[i]) if i < items.size() and items[i] is String else ""
		out.append("" if id == "select" or MapCatalog.item(id).is_empty() else id)
	return out


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
	mouse_slot = MapSlot.new(SLOT)
	mouse_slot.ed = ed
	mouse_slot.fixed = true
	mouse_slot.key_label = "²"
	mouse_slot.set_item("select")
	mouse_slot.clicked.connect(func(_slot): ed.select_mouse())
	mouse_slot.set_meta(EditorUi.SKIP, true)
	h.add_child(mouse_slot)
	# Écart entre la souris et les 9 cases.
	_gap = Control.new()
	_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gap.set_meta(EditorUi.SKIP, true)
	h.add_child(_gap)
	for i in 9:
		var s := MapSlot.new(SLOT)
		s.index = i
		s.ed = ed
		s.clicked.connect(func(slot): ed.select_slot(slot.index))
		# Taille des cases calculée ici (_place), à la taille de l'interface.
		s.set_meta(EditorUi.SKIP, true)
		h.add_child(s)
		slots.append(s)
	queue_redraw_slots()
	get_parent().resized.connect(_place)
	resized.connect(_place)
	_place.call_deferred()


## Case à 100 % ; plus petite si la barre ne tient pas dans la vue (grande
## taille d'interface, liste des objets ouverte).
const SLOT := 50.0
## Écart (px à 100 %) entre la case de la souris et la case 1.
const GAP := 6.0


func _place() -> void:
	var p := get_parent() as Control
	var f := EditorUi.factor()
	_gap.custom_minimum_size = Vector2(EditorUi.px(GAP), 0)
	# Largeur de la barre hors cases : 10 séparations (souris, écart, 9 cases),
	# l'écart et les marges du cadre.
	var extra := EditorUi.px(3.0 * 10.0 + GAP + 2.0 * 4.0)
	var s := clampf(floorf((p.size.x - 16.0 - extra) / 10.0), 24.0, roundf(SLOT * f))
	var all := slots.duplicate()
	all.append(mouse_slot)
	for slot in all:
		if slot.custom_minimum_size.x != s:
			slot.custom_minimum_size = Vector2(s, s)
	var want := get_combined_minimum_size()
	if size != want:
		size = want
	position = Vector2((p.size.x - size.x) * 0.5, p.size.y - size.y - EditorUi.px(8.0))


## Taille de l'interface changée (MapEditor.apply_ui_scale).
func ui_scale_changed() -> void:
	_place.call_deferred()


func queue_redraw_slots() -> void:
	for i in slots.size():
		slots[i].set_item(String(ed.hotbar[i]) if i < ed.hotbar.size() else "")
		slots[i].selected = i == ed.hot_index
		slots[i].queue_redraw()
	if mouse_slot != null:
		mouse_slot.set_item("select")
		mouse_slot.selected = ed.hot_index < 0
	if _name != null:
		_name.text = MapCatalog.name_of(ed.current_item())
