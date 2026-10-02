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
## Sous-onglets (MapCatalog.subs_of) : rangée de boutons au-dessus de la
## grille, montrée seulement pour une catégorie qui en a (Effets : flammes,
## fumées...). Sous-onglet choisi de chaque catégorie (gardé à la réouverture).
var _subs: HFlowContainer
var sub_of: Dictionary = {}


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
	# À droite : sous-onglets de la catégorie (s'il y en a) au-dessus de la grille.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_subs = HFlowContainer.new()
	_subs.add_theme_constant_override("h_separation", 4)
	_subs.add_theme_constant_override("v_separation", 4)
	_subs.visible = false
	right.add_child(_subs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
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
	# Prefabs de la carte (format 10) : cases « Créer… » et « Importer… » d'abord.
	var map_cat := c == MapCatalog.MAP_CAT and ed != null and ed.prefab_tools != null
	if map_cat:
		ed.prefab_tools.add_inventory_actions(_grid)
	for it in MapCatalog.in_category(c, _fill_subs(c)):
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
		if map_cat:
			# Renommer / régler, supprimer (MapPrefabTools).
			ed.prefab_tools.add_item_buttons(box, it)
		_grid.add_child(box)
		cells.append(s)


## Sous-onglets de la catégorie `c` (rangée cachée si elle n'en a pas) ;
## rend le sous-onglet montré ("" : tous les objets de la catégorie).
func _fill_subs(c: String) -> String:
	for n in _subs.get_children():
		_subs.remove_child(n)
		n.queue_free()
	var subs := MapCatalog.subs_of(c)
	_subs.visible = not subs.is_empty()
	if subs.is_empty():
		return ""
	var cur := String(sub_of.get(c, subs[0][0]))
	if not subs.any(func(s): return String(s[0]) == cur):
		cur = String(subs[0][0])
	sub_of[c] = cur
	for s in subs:
		var b := Button.new()
		b.text = Lang.t(String(s[1]), String(s[2]))
		b.toggle_mode = true
		b.button_pressed = String(s[0]) == cur
		b.name = String(s[0])
		b.pressed.connect(show_sub.bind(String(s[0])))
		_subs.add_child(b)
	return cur


## Montre le sous-onglet `s` de la catégorie ouverte.
func show_sub(s: String) -> void:
	sub_of[cat] = s
	show_category(cat)


## Case cliquée : l'objet va dans la case choisie de la barre rapide (souris
## en main : la première case vide, MapEditor.pick_item).
func _pick(s: MapSlot) -> void:
	ed.pick_item(s.item_id)
	ed.toggle_inventory()
