class_name Hub2Ui
extends RefCounted
## Petits morceaux d'interface du hub v2 partagés par JOUER (solo, coop) et
## le récapitulatif : libellé de section, étiquette encadrée, pastille de
## vague, liseré pointillé, champ de saisie, bouton contour, séparateurs.
## Valeurs de la maquette (100 %) passées par Hub2Style.px / fs.


## Libellé de section (« CARTES DU JEU ») : Chakra Petch 12 px 600,
## letter-spacing 0.18em, rgba(242, 240, 234, 0.55).
static func section(text: String, size := 12.0, weight := 600, alpha := 0.55, track := 0.18) -> Hub2Text:
	var t := Hub2Text.new()
	t.setup(text, Hub2Style.CHAKRA, weight, size, Hub2Style.text_a(alpha), track)
	return t


## Étiquette encadrée (« POUR LE FUN », « HÔTE », « NEUF ») : padding,
## liseré 1 px `line` (transparent : aucun), fond `bg`, texte Chakra Petch
## `size` px 700, letter-spacing `track`.
static func tag(text: String, color: Color, line: Color, bg := Color(0, 0, 0, 0), size := 11.0,
		track := 0.14, pad_v := 2.0, pad_h := 8.0) -> Hub2Box:
	var b := Hub2Box.new()
	b.flat(bg, line, 1.0 if line.a > 0.0 else 0.0)
	b.pad(pad_v, pad_h)
	var t := Hub2Text.new()
	t.setup(text, Hub2Style.CHAKRA, 700, size, color, track)
	b.add_child(t)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## Pastille d'une vague (« 5 Meute ») : inline-flex, padding `pad_v` `pad_h`,
## écart `gap`, police `size` px, fond rgba(10, 11, 13, 0.7), liseré 1 px de
## la couleur du type ; manche en JetBrains Mono 700.
static func wave_chip(round_n: int, name: String, col: Color, size := 13.0, pad_v := 4.0, pad_h := 10.0,
		gap := 8.0) -> Hub2Box:
	var b := Hub2Box.new()
	b.flat(Hub2Style.GLASS_STRONG, col, 1.0)
	b.pad(pad_v, pad_h)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(Hub2Style.px(gap)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var r := Hub2Text.new()
	r.setup(str(round_n), Hub2Style.MONO, 700, size, Hub2Style.TEXT)
	h.add_child(r)
	var n := Hub2Text.new()
	n.setup(name, Hub2Style.BARLOW, 400, size, Hub2Style.TEXT)
	h.add_child(n)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## Rangée de pastilles des vagues de la carte `def` (Hub2PlayData.map_waves).
static func fill_waves(row: Container, def: MapDef, size := 13.0, pad_v := 4.0, pad_h := 10.0, gap := 8.0) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	for w in Hub2PlayData.map_waves(def):
		row.add_child(wave_chip(int(w.round), Hub2PlayData.wave_name(String(w.type)), Hub2PlayData.wave_color(String(w.type)),
				size, pad_v, pad_h, gap))


## Liseré pointillé (border: 1px dashed) dessiné sur `ci` autour de `r`.
static func draw_dashed(ci: CanvasItem, r: Rect2, col: Color, width := 1.0) -> void:
	var w := maxf(Hub2Style.px(width), 1.0)
	var dash := w * 3.0
	var x := r.position.x
	while x < r.end.x:
		var l := minf(dash, r.end.x - x)
		ci.draw_rect(Rect2(x, r.position.y, l, w), col)
		ci.draw_rect(Rect2(x, r.end.y - w, l, w), col)
		x += dash * 2.0
	var y := r.position.y + w
	while y < r.end.y - w:
		var l2 := minf(dash, r.end.y - w - y)
		ci.draw_rect(Rect2(r.position.x, y, w, l2), col)
		ci.draw_rect(Rect2(r.end.x - w, y, w, l2), col)
		y += dash * 2.0


## Contrôle qui dessine un liseré pointillé à sa taille (placé dans un
## conteneur, sous le contenu).
static func dashed_frame(col: Color, width := 1.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(func(): draw_dashed(c, Rect2(Vector2.ZERO, c.size), col, width))
	c.resized.connect(c.queue_redraw)
	return c


## Bouton contour (COPIER L'ADRESSE, CHANGER DE CARTE) : hauteur 36,
## padding 0 `pad_h`, liseré 1 px `line`, fond `bg`, texte Chakra Petch 13 px
## 700, letter-spacing 0.12em.
static func outline_button(text: String, color: Color, line: Color, bg: Color, pad_h := 16.0,
		size := 13.0, weight := 700, track := 0.12, h := 36.0) -> Hub2Button:
	var b := Hub2Button.new()
	b.box.flat(bg, line, 1.0)
	b.box.pad(0, pad_h)
	var t := Hub2Text.new()
	t.setup(text, Hub2Style.CHAKRA, weight, size, color, track)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.align = HORIZONTAL_ALIGNMENT_CENTER
	b.add_content(t)
	b.custom_minimum_size.y = Hub2Style.px(h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## Texte d'un Hub2Button construit par outline_button.
static func button_text(b: Hub2Button) -> Hub2Text:
	return b.box.get_child(0) as Hub2Text


## Champ de saisie : fond rgba(255, 255, 255, 0.05), liseré 1 px
## rgba(255, 255, 255, 0.18) (focus : jaune), Barlow 15 px, hauteur 36.
static func line_edit(value: String, placeholder: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, Hub2Style.px(36))
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_override("font", Hub2Style.font(Hub2Style.BARLOW, 500))
	e.add_theme_font_size_override("font_size", Hub2Style.fs(15))
	e.add_theme_color_override("font_color", Hub2Style.TEXT)
	e.add_theme_color_override("font_placeholder_color", Hub2Style.text_a(0.35))
	e.add_theme_color_override("caret_color", Hub2Style.YELLOW)
	e.add_theme_color_override("selection_color", Hub2Style.yellow_a(0.35))
	var n := StyleBoxFlat.new()
	n.bg_color = Hub2Style.white_a(0.05)
	n.border_color = Hub2Style.white_a(0.18)
	n.set_border_width_all(int(maxf(Hub2Style.px(1), 1.0)))
	n.content_margin_left = Hub2Style.px(12)
	n.content_margin_right = Hub2Style.px(12)
	e.add_theme_stylebox_override("normal", n)
	var f := n.duplicate() as StyleBoxFlat
	f.border_color = Hub2Style.YELLOW
	f.set_border_width_all(int(maxf(Hub2Style.px(2), 1.0)))
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_stylebox_override("read_only", n)
	return e


## Conteneur vertical / horizontal à écart `gap` (px de la maquette), souris
## ignorée.
static func vbox(gap: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(gap)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func hbox(gap: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(Hub2Style.px(gap)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


## Texte coupé à la largeur donnée par son conteneur (overflow: hidden) :
## un Hub2Text garde sinon la largeur de son texte comme minimum (TAILLE DES
## MENUS 130 % : colonnes plus étroites que le texte).
static func clipped(t: Hub2Text) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.clip_contents = true
	c.custom_minimum_size.y = t.get_combined_minimum_size().y
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(t)
	t.minimum_size_changed.connect(func(): c.custom_minimum_size.y = t.get_combined_minimum_size().y)
	return c


## <span style="flex: 1"> : ressort horizontal.
static func spring() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Paragraphe (Barlow) qui revient à la ligne, interligne `line_height`
## (1.35 : line-height de la maquette).
static func paragraph(text: String, size := 13.0, alpha := 0.6, line_height := 1.35, weight := 400) -> Label:
	var l := Hub2Style.label(text, Hub2Style.BARLOW, weight, size, Hub2Style.text_a(alpha))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var f := Hub2Style.font(Hub2Style.BARLOW, weight)
	var s := Hub2Style.fs(size)
	var natural := Hub2Style.line_height(f, s)
	l.add_theme_constant_override("line_spacing", int(roundf(s * line_height - natural)))
	l.custom_minimum_size.x = Hub2Style.px(60)
	return l
