class_name Hub2InventoryPanel
extends Hub2Panel
## INVENTAIRE (docs/hub_v2/Inventaire.dc.html) : échantillons groupés par
## ennemi (rendus 3D), fiche (où le trouver, demandé par).
##
## Gauche (section) : « ÉCHANTILLONS » + « N en réserve · K sortes connues
## sur M », puis un groupe par ennemi (losange à sa couleur, nom, filet) et
## une grille de 4 cartes par groupe : rendu 52 px (silhouette noire si la
## sorte est inconnue : « ??? », « jamais obtenu »), nom, demandes (« 2
## contrats · 1 échange »), quantité. Carte choisie : liseré et teinte jaunes.
## Droite (fiche, 384 px) : grand rendu, ennemi, nom, quantité, description,
## OÙ LA TROUVER (vague, manche, taux de LootRules), DEMANDÉE PAR (contrats
## en jaune, échanges en turquoise, possédé / demandé).
## Données : SampleCatalog (LootRules, CodexData, HubData, profil).
## Navigation : flèches / croix / stick entre les cartes (le focus choisit la
## carte), clic ; A / Entrée : le contrat (ou l'échange) qui la demande ;
## stick droit / molette : la fiche défile (130 %).

## Losange des groupes : couleurs de la maquette par ennemi (fiche du codex) ;
## un autre ennemi prend la couleur de sa famille (Hub2CodexPanel.FAMILY).
const GROUP_COLORS := {"dog": "C9C7BE", "brancardier": "4D9BFF", "nurse": "B56CFF", "surgeon": "FF9A1F"}
## Grille de la maquette : 4 cartes de 197,5 px, écart 10.
const COLUMNS := 4
const CARD_W := 197.5
const GAP := 10.0

var codex: CodexData
## Colonnes affichées (moins qu'à la maquette à une grande TAILLE DES MENUS).
var columns := COLUMNS
## Cellules des grilles (cartes et cases vides) : largeurs égales.
var _cells: Array = []
## Sorte choisie (fiche de droite).
var selected_id := ""
## Sorte -> Hub2Button (carte).
var cards: Dictionary = {}
var header_count: Hub2Text
var list_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var _list: VBoxContainer
var _detail: VBoxContainer
var _title: Hub2Text
var _mouse_down := false


func build() -> void:
	if codex == null:
		codex = CodexData.default()
	# <section> : 1280 − 2 × 28 − 20 − 384 = 820 px à 100 %.
	var w: float = hub.size.x if hub and hub.size.x > 0.0 else Hub2Style.SCREEN.x
	columns = Hub2ItemsUi.columns_for(COLUMNS, CARD_W, GAP, w - Hub2Style.px(2 * Hub2Style.SIDE) - Hub2Style.px(20) - Hub2Style.px(384))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Hub2Style.px(20)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_main(row)
	# <section> : titre puis groupes (défilent si la taille des menus l'exige).
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sec)
	sec.add_child(_header())
	list_scroll = Hub2ItemsUi.scroller()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sec.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(Hub2Style.px(18)))
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_scroll.add_child(_list)
	# <aside> : fiche, 384 px, verre plus opaque (0.7).
	var aside := Hub2Box.new()
	aside.glass(Hub2Style.GLASS_STRONG, Hub2Style.LINE, 1.0)
	aside.pad(1)
	aside.custom_minimum_size.x = Hub2Style.px(384)
	row.add_child(aside)
	detail_scroll = Hub2ItemsUi.scroller()
	aside.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 0)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_scroll.add_child(_detail)
	_fill()


## Titre « ÉCHANTILLONS » et compteur, alignés sur leur ligne de base
## (align-items: baseline, hauteur 34).
func _header() -> Control:
	var h := Control.new()
	h.custom_minimum_size.y = Hub2Style.px(34)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Hub2Text.new()
	_title.setup(Lang.t("ÉCHANTILLONS", "SAMPLES"), Hub2Style.CHAKRA, 700, 22, Hub2Style.TEXT, 0.06)
	h.add_child(_title)
	header_count = Hub2Text.new()
	header_count.setup("", Hub2Style.MONO, 500, 13, Hub2Style.text_a(0.55))
	h.add_child(header_count)
	var place := func() -> void:
		var ta := _title.get_font().get_ascent(_title.size_px())
		var ca := header_count.get_font().get_ascent(header_count.size_px())
		_title.position = Vector2.ZERO
		_title.size = _title.get_combined_minimum_size()
		header_count.position = Vector2(_title.size.x + Hub2Style.px(16), roundf(ta - ca))
		header_count.size = header_count.get_combined_minimum_size()
	h.resized.connect(place)
	header_count.minimum_size_changed.connect(place)
	return h


func refresh() -> void:
	if not built:
		return
	var had := _focused_id()
	_fill()
	if had != "" and cards.has(had) and is_visible_in_tree() and hub:
		hub.call("focus_later", cards[had])


func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	cards.clear()
	_cells.clear()
	var pr := profile()
	header_count.text = Lang.t("%s en réserve · %d sortes connues sur %d", "%s in stock · %d of %d kinds known") \
			% [Hub2Style.num(SampleCatalog.total(pr)), SampleCatalog.known_count(pr, codex), SampleCatalog.ids().size()]
	var rows := []
	for kind in LootRules.SAMPLES:
		var ids := PackedStringArray()
		var group_cards := []
		for s in LootRules.SAMPLES[kind]:
			ids.append(String(s[0]))
		_list.add_child(_group(ids))
		for id in ids:
			group_cards.append(cards[id])
		rows.append_array(Hub2ItemsUi.rows_of(group_cards, columns))
	Hub2ItemsUi.link_rows(rows)
	Hub2ItemsUi.equal_columns(list_scroll, _cells, columns, GAP)
	if selected_id == "" or not cards.has(selected_id):
		selected_id = _default_selection()
	_show_selection()


## Première sorte en réserve (sinon connue, sinon la première).
func _default_selection() -> String:
	var pr := profile()
	var known := ""
	for id in SampleCatalog.ids():
		if pr and pr.sample_count(id) > 0:
			return id
		if known == "" and SampleCatalog.is_known(pr, id, codex):
			known = id
	if known != "":
		return known
	var all := SampleCatalog.ids()
	return all[0] if not all.is_empty() else ""


## Groupe d'un ennemi : en-tête (losange, nom, filet) et grille de cartes.
func _group(ids: PackedStringArray) -> Control:
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var e := SampleCatalog.enemy_of(ids[0], codex) if not ids.is_empty() else {}
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(head)
	var diamond := Control.new()
	diamond.custom_minimum_size = Hub2Style.pxv(7, 7)
	diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := group_color(e)
	diamond.draw.connect(func():
		var c := diamond.size * 0.5
		var r := diamond.size.x * 0.5 * sqrt(2.0)
		diamond.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col))
	head.add_child(diamond)
	var name_t := Hub2ItemsUi.kicker(HubData.text_of(e.name).to_upper() if not e.is_empty() else "?", 13, 600, Hub2Style.text_a(0.7), 0.18)
	name_t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(name_t)
	var line := Control.new()
	line.custom_minimum_size.y = maxf(Hub2Style.px(1), 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func(): line.draw_rect(Rect2(Vector2.ZERO, line.size), Hub2Style.LINE))
	head.add_child(line)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", int(Hub2Style.px(GAP)))
	grid.add_theme_constant_override("v_separation", int(Hub2Style.px(GAP)))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(grid)
	for id in ids:
		var c := _card(id)
		grid.add_child(c)
		_cells.append(c)
	# Cellules vides : colonnes égales même pour un groupe de 2 ou 3.
	var n := ids.size()
	while n % columns != 0:
		var pad := Control.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(pad)
		_cells.append(pad)
		n += 1
	return g


## Couleur du losange d'un groupe (maquette, sinon famille de l'ennemi).
static func group_color(e: Dictionary) -> Color:
	var id := String(e.get("id", ""))
	if GROUP_COLORS.has(id):
		return Color(GROUP_COLORS[id])
	return Hub2CodexPanel.family_color(CodexData.category(e)) if not e.is_empty() else Hub2Style.text_a(0.55)


## Carte d'une sorte (button de la maquette).
func _card(id: String) -> Hub2Button:
	var pr := profile()
	var known := SampleCatalog.is_known(pr, id, codex)
	var qty := pr.sample_count(id) if pr else 0
	var b := Hub2Button.new()
	b.name = "Sample_" + id
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.box.pad(9, 13)  # border 1 px + padding 8 12
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Hub2Style.px(12)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(row)
	var img := Hub2ShadowRender.new()
	img.texture = HubRenders.sample(id)
	img.custom_minimum_size = Hub2Style.pxv(52, 52)
	img.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if known:
		img.drop_shadow(4, 6, 0.5)
	else:
		img.silhouette = 0.5
	row.add_child(img)
	var col := Hub2Style.text_a(0.45) if not known or qty == 0 else Hub2Style.TEXT
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(2)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	# Nom toujours lisible en entier : il passe à la ligne (jamais de « … »).
	var n := Hub2Style.label(SampleCatalog.display_name(id) if known else "???", Hub2Style.CHAKRA, 600, 15, col, 0.02)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_constant_override("line_spacing", roundi(Hub2Style.px(15 * 1.15) - Hub2Style.line_height(Hub2Style.font(Hub2Style.CHAKRA, 600), Hub2Style.fs(15))))
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.name = "Name"
	v.add_child(n)
	var use_text := Lang.t("jamais obtenu", "never obtained")
	if known:
		use_text = SampleCatalog.use_line(_uses(id))
	var u := Hub2ItemsUi.para(use_text, 12, Hub2Style.text_a(0.55))
	u.name = "Use"
	v.add_child(u)
	var q := Hub2Text.new()
	q.setup(Hub2Style.num(qty) if known else "–", Hub2Style.MONO, 700, 22, col)
	q.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	q.name = "Qty"
	row.add_child(q)
	b.set_meta("sample", id)
	b.focus_entered.connect(_select.bind(id))
	b.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_mouse_down = true)
	b.pressed.connect(_on_card_pressed.bind(id))
	cards[id] = b
	return b


func _uses(id: String) -> Array:
	return SampleCatalog.uses(profile(), id, HubContractsView.data(), HubContractsView.today())


func _on_card_pressed(id: String) -> void:
	if _mouse_down:
		# Clic : la carte est choisie (focus), sans quitter l'écran.
		_mouse_down = false
		_select(id)
		return
	open_request(id)


## A / Entrée sur une carte : l'écran du contrat qui la demande (sinon celui
## des échanges, sinon les contrats).
func open_request(id: String) -> void:
	if hub == null:
		return
	var list := _uses(id)
	var target := "contracts"
	var target_id := ""
	for u in list:
		if u.kind == SampleCatalog.CONTRACT:
			target_id = u.id
			break
	if target_id == "" and not list.is_empty():
		target = "exchanges"
		target_id = list[0].id
	hub.call("open", target)
	var p: Variant = hub.get("panels").get(target)
	if target_id != "" and p is Object and (p as Object).has_method("select_item"):
		p.call("select_item", target_id)


func _select(id: String) -> void:
	if id == selected_id:
		return
	selected_id = id
	_show_selection()


## Liseré et teinte de la carte choisie, puis la fiche.
func _show_selection() -> void:
	for id in cards:
		var on: bool = id == selected_id
		var b: Hub2Button = cards[id]
		b.box.glass(Hub2Style.yellow_a(0.12) if on else Hub2Style.GLASS, Hub2Style.YELLOW if on else Hub2Style.LINE, 1.0)
	_show_detail(selected_id)


## Fiche de droite (aside de la maquette).
func _show_detail(id: String) -> void:
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	if id == "":
		return
	var pr := profile()
	var known := SampleCatalog.is_known(pr, id, codex)
	var e := SampleCatalog.enemy_of(id, codex)
	# En-tête : padding 20, écart 16, liseré du haut 3 px à la couleur de la sorte.
	var head := Hub2Box.new()
	head.flat(Color(0, 0, 0, 0), SampleCatalog.color(id) if known else Hub2Style.white_a(0.2), 0.0)
	head.border = Vector4(0, 3, 0, 0)
	head.pad(23, 20, 20, 20)
	_detail.add_child(head)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hr)
	var img := Hub2ShadowRender.new()
	img.texture = HubRenders.sample(id)
	img.custom_minimum_size = Hub2Style.pxv(96, 96)
	img.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if known:
		img.drop_shadow(6, 10, 0.6)
	else:
		img.silhouette = 0.5
	hr.add_child(img)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hr.add_child(hv)
	hv.add_child(Hub2ItemsUi.kicker(HubData.text_of(e.name).to_upper() if not e.is_empty() else "?"))
	var title := Hub2ItemsUi.para(SampleCatalog.display_name(id) if known else "???", 28, Hub2Style.TEXT, 1.0)
	title.add_theme_font_override("font", Hub2Style.font(Hub2Style.CHAKRA, 700))
	title.add_theme_constant_override("line_spacing", roundi(Hub2Style.px(28) - Hub2Style.line_height(Hub2Style.font(Hub2Style.CHAKRA, 700), Hub2Style.fs(28))))
	title.name = "Title"
	hv.add_child(title)
	var qty := Hub2Text.new()
	var n := pr.sample_count(id) if pr else 0
	qty.setup(Lang.t("%s en réserve", "%s in stock") % Hub2Style.num(n) if known else Lang.t("Jamais obtenu", "Never obtained"),
			Hub2Style.MONO, 500, 14, Hub2Style.TEXT)
	qty.name = "Qty"
	hv.add_child(qty)
	# Description : padding 0 20 16, Barlow 15, line-height 1.45.
	var pm := MarginContainer.new()
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margins(pm, 0, 20, 16, 20)
	var text := SampleCatalog.description(id) if known else Lang.t("Personne ne l’a encore rapporté au labo.",
			"Nobody has brought one back to the lab yet.")
	var p := Hub2ItemsUi.para(text, 15, Hub2Style.text_a(0.78), 1.45)
	p.name = "Text"
	pm.add_child(p)
	_detail.add_child(pm)
	# OÙ LA TROUVER.
	var where := Hub2ItemsUi.section(14, 20, 14, 20, 6)
	where.get_child(0).add_child(Hub2ItemsUi.kicker(SampleCatalog.where_title(id)))
	var wt := Hub2ItemsUi.para(SampleCatalog.where_text(id, codex), 15, Hub2Style.TEXT)
	wt.name = "Where"
	where.get_child(0).add_child(wt)
	_detail.add_child(where)
	# DEMANDÉE PAR.
	var asked := Hub2ItemsUi.section(14, 20, 14, 20, 8)
	var av: VBoxContainer = asked.get_child(0)
	av.add_child(Hub2ItemsUi.kicker(SampleCatalog.asked_title(id)))
	var list := _uses(id)
	if list.is_empty():
		var none := Hub2ItemsUi.para(SampleCatalog.nobody_text(id), 14, Hub2Style.text_a(0.55))
		none.name = "Nobody"
		av.add_child(none)
	for u in list:
		av.add_child(_use_row(u))
	_detail.add_child(asked)


## Ligne d'une demande : CONTRAT (jaune) / ÉCHANGE (turquoise), titre,
## « possédé / demandé » (turquoise si atteint).
func _use_row(u: Dictionary) -> Control:
	var b := Hub2Box.new()
	b.flat(Hub2Style.white_a(0.04))
	b.pad(8, 12)
	b.name = "Use_" + String(u.id)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", int(Hub2Style.px(12)))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(r)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(1)))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(v)
	var contract: bool = u.kind == SampleCatalog.CONTRACT
	v.add_child(Hub2ItemsUi.kicker(Lang.t("CONTRAT", "CONTRACT") if contract else Lang.t("ÉCHANGE", "EXCHANGE"), 11, 600,
			Hub2Style.YELLOW if contract else Hub2Style.TEAL, 0.16))
	v.add_child(Hub2ItemsUi.para(String(u.title), 15, Hub2Style.TEXT, 1.2, 500))
	var c := Hub2Text.new()
	var ok: bool = int(u.have) >= int(u.need)
	c.setup("%s / %s" % [Hub2Style.num(int(u.have)), Hub2Style.num(int(u.need))], Hub2Style.MONO, 700, 13, Hub2Style.TEAL if ok else Hub2Style.TEXT)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.name = "Count"
	r.add_child(c)
	return b


static func _margins(m: MarginContainer, top: float, right: float, bottom: float, left: float) -> void:
	m.add_theme_constant_override("margin_top", int(Hub2Style.px(top)))
	m.add_theme_constant_override("margin_right", int(Hub2Style.px(right)))
	m.add_theme_constant_override("margin_bottom", int(Hub2Style.px(bottom)))
	m.add_theme_constant_override("margin_left", int(Hub2Style.px(left)))


func _focused_id() -> String:
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner() if vp else null
	return String(f.get_meta("sample", "")) if f and f.has_meta("sample") else ""


func _process(delta: float) -> void:
	if visible:
		Hub2ItemsUi.pad_scroll(detail_scroll, delta)


# --------------------------------------------------------------------------
# Hub2Panel
# --------------------------------------------------------------------------

func first_focus() -> Control:
	return cards.get(selected_id)


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Voir le contrat", "View contract")], [Hub2Input.BACK, Lang.t("Retour", "Back")]]


func help() -> String:
	return Lang.t("Les échantillons se gagnent en partie et se gardent en évacuant.",
			"Samples are earned in a game and kept by evacuating.")
