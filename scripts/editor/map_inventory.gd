class_name MapInventory
extends PanelContainer
## Inventaire complet de l'éditeur de cartes (touche E ou Tab), rangé par
## catégories (MapCatalog.CATEGORIES) : cliquer un objet le met dans la case
## choisie de la barre rapide ; on peut aussi le glisser sur une case.

var ed: MapEditor
var cat := "construction"
var _grid: GridContainer
var _cats: VBoxContainer
var _title: Label
var cells: Array[MapSlot] = []


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.11, 0.97)
	sb.border_color = Color(0.5, 0.4, 0.25)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	add_child(v)
	_title = UiStyle.label(Lang.t("INVENTAIRE", "INVENTORY"), 22, UiStyle.GOLD, "impact")
	v.add_child(_title)
	var hint := Label.new()
	hint.text = Lang.t("Cliquez un objet pour le mettre dans la case choisie de la barre rapide, ou glissez-le sur une case. E ou Tab : fermer.",
		"Click an item to put it in the selected hotbar slot, or drag it onto a slot. E or Tab: close.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UiStyle.DIM)
	v.add_child(hint)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	# Catégories : défilent si la vue est trop basse (grande taille d'interface).
	var cscroll := ScrollContainer.new()
	cscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(cscroll)
	_cats = VBoxContainer.new()
	_cats.custom_minimum_size = Vector2(CATS_W, 0)
	cscroll.add_child(_cats)
	for c in MapCatalog.CATEGORIES:
		var b := Button.new()
		b.text = Lang.t(c[1], c[2])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.name = String(c[0])
		b.pressed.connect(show_category.bind(String(c[0])))
		_cats.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	show_category(cat)
	get_parent().resized.connect(_place)


## Taille à 100 % ; réduite (moins de colonnes, défilement) si la vue est plus
## petite, à grande taille d'interface.
const SIZE := Vector2(700, 430)
const CATS_W := 176.0
const COLUMNS := 5


func _place() -> void:
	var p := get_parent() as Control
	var want := (SIZE * EditorUi.factor()).round().min(p.size - Vector2(16, 16))
	# Autant de colonnes que la largeur en laisse à côté des catégories.
	_grid.columns = COLUMNS
	while _grid.columns > 1 and get_combined_minimum_size().x > want.x:
		_grid.columns -= 1
	size = want
	# Centré un peu au-dessus de la barre rapide, toujours dans la vue.
	var free := (p.size - size).max(Vector2.ZERO)
	position = ((p.size - size) * 0.5 - Vector2(0, EditorUi.px(40.0))).clamp(free.min(Vector2(8, 8)), free)


## Taille de l'interface changée (MapEditor.apply_ui_scale).
func ui_scale_changed() -> void:
	_place.call_deferred()


func open() -> void:
	show_category(cat)
	_place.call_deferred()


func show_category(c: String) -> void:
	cat = c
	for b in _cats.get_children():
		(b as Button).button_pressed = b.name == c
	for n in _grid.get_children():
		n.queue_free()
	cells.clear()
	for it in MapCatalog.in_category(c):
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(84, 0)
		box.add_theme_constant_override("separation", 2)
		var s := MapSlot.new(60.0)
		s.ed = ed
		s.set_item(String(it.id))
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		s.clicked.connect(_pick)
		box.add_child(s)
		var l := Label.new()
		l.text = MapCatalog.name_of(it)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(84, 0)
		l.add_theme_font_size_override("font_size", 11)
		box.add_child(l)
		_grid.add_child(box)
		cells.append(s)


## Case cliquée : l'objet va dans la case choisie de la barre rapide.
func _pick(s: MapSlot) -> void:
	ed.set_hotbar(ed.hot_index, s.item_id)
	ed.toggle_inventory()
