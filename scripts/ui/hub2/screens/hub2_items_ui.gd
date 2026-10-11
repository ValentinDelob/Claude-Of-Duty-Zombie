class_name Hub2ItemsUi
extends RefCounted
## Petites briques communes à l'INVENTAIRE et au CODEX du hub v2
## (docs/hub_v2/Inventaire.dc.html, Codex.dc.html) : paragraphe à
## line-height, libellé de section, bloc à liseré du haut, zone qui défile
## (taille des menus 130 %), bordure en pointillés (fiche inconnue).


## Paragraphe Barlow qui revient à la ligne, `line-height` = `lh` × taille.
static func para(text: String, size: float, color: Color, lh := 1.2, weight := 400) -> Label:
	var l := Hub2Style.label(text, Hub2Style.BARLOW, weight, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var s := Hub2Style.fs(size)
	var normal := Hub2Style.line_height(Hub2Style.font(Hub2Style.BARLOW, weight), s)
	l.add_theme_constant_override("line_spacing", roundi(Hub2Style.px(size * lh) - normal))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Libellé de section en capitales espacées (Chakra Petch 12 / 600 / 0.18em,
## rgba(242, 240, 234, 0.55)).
static func kicker(text: String, size := 12.0, weight := 600, color := Hub2Style.text_a(0.55), tracking := 0.18) -> Hub2Text:
	var t := Hub2Text.new()
	t.setup(text, Hub2Style.CHAKRA, weight, size, color, tracking)
	return t


## Bloc `padding` + `border-top: 1px solid rgba(255, 255, 255, 0.08)` avec un
## VBox d'écart `gap` (rendu dans `box.get_child(0)`).
static func section(top: float, right: float, bottom: float, left: float, gap: float) -> Hub2Box:
	var b := Hub2Box.new()
	b.flat(Color(0, 0, 0, 0), Hub2Style.LINE, 0.0)
	b.border = Vector4(0, 1, 0, 0)
	b.pad(top, right, bottom, left)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(gap)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	return b


## Zone verticale qui défile (rien ne sort de l'écran à 130 %) : barre fine
## et discrète, suit le focus.
static func scroller() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	var bar := sc.get_v_scroll_bar()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Hub2Style.white_a(0.04)
	bg.content_margin_left = Hub2Style.px(2)
	bg.content_margin_right = Hub2Style.px(2)
	bar.add_theme_stylebox_override("scroll", bg)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Hub2Style.white_a(0.25)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(st, grab)
	return sc


## Défilement au stick droit de la manette (HUB_PLAN §4.1) : `dt` secondes.
static func pad_scroll(sc: ScrollContainer, dt: float) -> void:
	if sc == null or not sc.is_visible_in_tree():
		return
	var y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(y) > 0.25:
		sc.scroll_vertical += roundi(y * Hub2Style.px(900.0) * dt)


## Voisins de focus d'une grille (lignes de longueurs diverses, de haut en
## bas) : gauche / droite dans la ligne (sans boucler), haut / bas sur la même
## colonne de la ligne voisine (sa dernière carte si elle est plus courte).
static func link_rows(rows: Array) -> void:
	for r in rows.size():
		var row: Array = rows[r]
		for c in row.size():
			var b: Control = row[c]
			b.focus_neighbor_left = b.get_path_to(row[maxi(c - 1, 0)])
			b.focus_neighbor_right = b.get_path_to(row[mini(c + 1, row.size() - 1)])
			var up: Array = rows[r - 1] if r > 0 else row
			var down: Array = rows[r + 1] if r + 1 < rows.size() else row
			b.focus_neighbor_top = b.get_path_to(up[mini(c, up.size() - 1)] if r > 0 else b)
			b.focus_neighbor_bottom = b.get_path_to(down[mini(c, down.size() - 1)] if r + 1 < rows.size() else b)


## Colonnes de la grille : celles de la maquette (`design_cols` cartes de
## `design_w` px dans `design_avail` px à 100 %) ; à une TAILLE DES MENUS plus
## grande, moins de colonnes pour que les cartes gardent (à 10 % près) leur
## largeur de maquette mise à l'échelle (rien d'écrasé à 130 %).
static func columns_for(design_cols: int, design_w: float, gap: float, avail: float) -> int:
	var n := floori((avail + Hub2Style.px(gap)) / (Hub2Style.px(design_w) * 0.9 + Hub2Style.px(gap)))
	return clampi(n, 1, design_cols)


## Colonnes égales (grid-template-columns: repeat(n, minmax(0, 1fr))) : chaque
## cellule de `cells` prend la largeur d'une colonne de la zone `sc` (barre
## de défilement déduite quand elle est affichée), recalculée à chaque
## changement de taille.
static func equal_columns(sc: ScrollContainer, cells: Array, cols: int, gap: float) -> void:
	var fit := func() -> void:
		var w := sc.size.x
		var bar := sc.get_v_scroll_bar()
		if bar.visible:
			w -= bar.get_combined_minimum_size().x
		var cw := maxf(floorf((w - Hub2Style.px(gap) * (cols - 1)) / cols), 0.0)
		for c in cells:
			if is_instance_valid(c):
				(c as Control).custom_minimum_size.x = cw
	if sc.has_meta("fit_columns"):
		var old: Callable = sc.get_meta("fit_columns")
		if sc.resized.is_connected(old):
			sc.resized.disconnect(old)
			sc.get_v_scroll_bar().visibility_changed.disconnect(old)
	sc.set_meta("fit_columns", fit)
	sc.resized.connect(fit)
	sc.get_v_scroll_bar().visibility_changed.connect(fit)
	fit.call()


## Découpe une liste en lignes de `columns`.
static func rows_of(list: Array, columns: int) -> Array:
	var out := []
	for i in range(0, list.size(), columns):
		out.append(list.slice(i, i + columns))
	return out


## `border: 1px dashed color` sur `c` (traits de 3 px, comme Chrome pour 1 px).
static func draw_dashes(c: Control, color: Color, width := 1.0) -> void:
	var w := maxf(Hub2Style.px(width), 1.0)
	var dash := 3.0 * w
	var s := c.size
	var x := 0.0
	while x < s.x:
		var l := minf(dash, s.x - x)
		c.draw_rect(Rect2(x, 0, l, w), color)
		c.draw_rect(Rect2(x, s.y - w, l, w), color)
		x += dash * 2.0
	var y := 0.0
	while y < s.y:
		var l2 := minf(dash, s.y - y)
		c.draw_rect(Rect2(0, y, w, l2), color)
		c.draw_rect(Rect2(s.x - w, y, w, l2), color)
		y += dash * 2.0
