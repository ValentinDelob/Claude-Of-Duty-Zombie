class_name HubBox
extends Container
## Panneau du hub (classe .pnl de la maquette) : fond sombre, contour noir de
## 2 px, biseau intérieur, ombre pleine décalée de 4 px ; en-tête facultatif
## (.ph : titre en Impact, texte à droite ; variante rouge) ; contenu dans
## `content` (VBoxContainer), qui défile quand il dépasse (taille des menus à
## 130 % : « les listes défilent, rien ne sort de l'écran », HUB_PLAN §4.2).
##
## Les enfants ajoutés par le code vont dans `content` ; `header` et le
## défilement sont gérés ici.

const STYLE_PANEL := "panel"
## Carte de contrat (.card : fond plus clair, pas de biseau bas).
const STYLE_CARD := "card"
## Encadré enfoncé (.slot, aperçu : fond très sombre, pas d'ombre).
const STYLE_INSET := "inset"

var style := STYLE_PANEL:
	set(v):
		style = v
		queue_redraw()
var header: Control
var title_label: Label
var right_label: Label
var scroll: ScrollContainer
## Conteneur du contenu (séparation 0 : la maquette espace par marges).
var content: VBoxContainer


## `title` vide : pas d'en-tête. `red` : en-tête rouge (LE SCIENTIFIQUE).
## `scrolls` : le contenu défile s'il dépasse la hauteur du panneau.
func _init(title := "", right := "", red := false, scrolls := true) -> void:
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_PASS
	if title != "":
		header = Control.new()
		header.custom_minimum_size = Vector2(0, HubStyle.px(30))
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.draw.connect(_draw_header.bind(red))
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = HubStyle.px(10)
		row.offset_right = -HubStyle.px(10)
		row.offset_bottom = -HubStyle.px(2)
		row.add_theme_constant_override("separation", int(HubStyle.px(8)))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(row)
		title_label = HubStyle.label(title, 15, HubStyle.HEADER_RED_TEXT if red else HubStyle.PLASTER, "impact", false, 0.06)
		title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title_label.size_flags_vertical = Control.SIZE_FILL
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_label.clip_text = true
		row.add_child(title_label)
		right_label = HubStyle.label(right, 13, HubStyle.HEADER_RED_TEXT if red else HubStyle.DIM)
		right_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		right_label.size_flags_vertical = Control.SIZE_FILL
		row.add_child(right_label)
		add_child(header)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if scrolls:
		scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.add_child(content)
		HubBox.style_scrollbar(scroll.get_v_scroll_bar())
		add_child(scroll)
	else:
		add_child(content)


## Texte à droite de l'en-tête.
func set_right(t: String) -> void:
	if right_label:
		right_label.text = t


func _border() -> float:
	return HubStyle.px(2)


func _get_minimum_size() -> Vector2:
	var b := _border() * 2.0
	var h := b
	var w := 0.0
	if header:
		h += header.get_combined_minimum_size().y
	var body: Control = scroll if scroll else content
	var bm := body.get_combined_minimum_size()
	h += bm.y
	w = maxf(w, bm.x)
	return Vector2(w + b, h)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var b := _border()
		var y := b
		var w := size.x - b * 2.0
		if header:
			var hh := header.get_combined_minimum_size().y
			fit_child_in_rect(header, Rect2(b, y, w, hh))
			y += hh
		var body: Control = scroll if scroll else content
		fit_child_in_rect(body, Rect2(b, y, w, maxf(size.y - y - b, 0.0)))


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match style:
		STYLE_CARD:
			HubStyle.draw_box(self, r, Color("1F2022"), _border(), HubStyle.px(4), HubStyle.PANEL_HI, Color(0, 0, 0, 0), HubStyle.px(2))
		STYLE_INSET:
			HubStyle.draw_box(self, r, HubStyle.GROUP_BG, _border(), 0.0, HubStyle.HEADER_BG, Color(0, 0, 0, 0), HubStyle.px(2))
		_:
			HubStyle.draw_box(self, r, HubStyle.PANEL_BG, _border(), HubStyle.px(4), HubStyle.PANEL_HI, HubStyle.PANEL_LO, HubStyle.px(2))


func _draw_header(red: bool) -> void:
	var r := Rect2(Vector2.ZERO, header.size)
	header.draw_rect(r, HubStyle.HEADER_RED_BG if red else HubStyle.HEADER_BG)
	header.draw_rect(Rect2(0, r.size.y - _border(), r.size.x, _border()), HubStyle.BLACK)


## Barre de défilement discrète, dans la palette du hub.
static func style_scrollbar(bar: ScrollBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	bg.content_margin_left = HubStyle.px(3)
	bg.content_margin_right = HubStyle.px(3)
	bar.add_theme_stylebox_override("scroll", bg)
	var grab := StyleBoxFlat.new()
	grab.bg_color = HubStyle.ASH
	bar.add_theme_stylebox_override("grabber", grab)
	var hi := grab.duplicate()
	hi.bg_color = HubStyle.YELLOW
	bar.add_theme_stylebox_override("grabber_highlight", hi)
	bar.add_theme_stylebox_override("grabber_pressed", hi)


## Marges autour d'un contrôle (padding de la maquette, à 100 %).
static func pad(c: Control, l: float, t: float, r: float, b: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(HubStyle.px(l)))
	m.add_theme_constant_override("margin_top", int(HubStyle.px(t)))
	m.add_theme_constant_override("margin_right", int(HubStyle.px(r)))
	m.add_theme_constant_override("margin_bottom", int(HubStyle.px(b)))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(c)
	return m


## Boîte horizontale ou verticale avec séparation à 100 %.
static func hbox(sep := 0.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(HubStyle.px(sep)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(sep := 0.0) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(HubStyle.px(sep)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


## Espace extensible (pousse la suite en bas ou à droite).
static func spring(vertical := true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Espace fixe (à 100 %).
static func gap(w: float, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = HubStyle.pxv(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
