class_name StationPanel
extends Control
## Interface de la station de construction (GAME_CONCEPT §4.11 ; maquette
## validée docs/hub_v2/Station.dc.html ; BuildStation, BuildRules), ouverte
## par [F] / X à la station, fermée par Échap / B (et la touche
## d'inventaire, lue par Hud._input). La partie continue pendant qu'elle est
## ouverte (même en solo) ; le joueur local ne bouge plus et ne tire plus
## (Game.menu_open) ; le HUD dessiné dessous est masqué (Hud._hud_under_menus).
##
## Voile radial sur la partie, en-tête (STATION DE CONSTRUCTION, ferraille),
## TON ARSENAL : armes du profil LOCAL (BuildRules.catalog) sur le rail des
## niveaux de l'ARSENAL du hub (Hub2ArsenalRail : colonnes par niveau, armes
## d'un même niveau empilées par prix décroissant, ‹ ›, ◄ ► niveau, ▲ ▼ même
## niveau), filtre CONSTRUCTIBLES (niveau atteint) / TOUTES (Tab / Y, clic) ;
## carte : rendu sur l'effet de rareté animé, nom, rareté, prix en ferraille
## (rouge si trop cher ; « NIV. N REQUIS » et carte à 50 % si le niveau
## manque) et durée. Fiche de 360 px : rareté · famille, nom, NIV., rendu,
## six statistiques (celles de l'arme construite : niveau et pièces
## compris), PIÈCES n / m, prix, manche où l'arme sera prête, CONSTRUIRE
## (gris si impossible) et « Il te restera X ferraille » ou la raison du
## refus (rouge). Bande MUNITIONS : arme en main, munitions, prix de la
## recharge, bouton « R · RECHARGER » (action « reload » réelle). Barre
## d'invites ; le recyclage se fait dans l'inventaire (aide).
##
## Construction du joueur (une à la fois) : plus de bande d'état ; la carte de
## l'arme montre « EN COURS » / « PRÊTE » à la place de sa durée, et sa fiche
## « EN CONSTRUCTION · MANCHE N » / « PRÊTE · [F] RÉCUPÉRER » à la place de
## CONSTRUIRE ; [F] (interact) dans l'interface la récupère. L'interface
## s'ouvre sur cette arme.
##
## Le serveur décide de tout (BuildStation.srv_build / srv_refill). Souris
## (clic : choisir ; CONSTRUIRE), manette / clavier (focus des cartes, A ou
## Entrée : construire).

const ASIDE_BG := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.72)
const ASIDE_W := 360.0
## Rail : flèches 32 px, padding 0 4, colonnes séparées de 12 px, cartes de
## 8 px ; largeur lisible d'une colonne (5 colonnes à 100 %, moins à 130 %).
const ARROW_W := 32.0
const RAIL_PAD := 4.0
const COL_GAP := 12.0
const COL_W := 125.0
const CARD_GAP := 8.0
## Filtres : niveau atteint / toutes.
const BUILDABLE := "buildable"
const ALL := "all"

var game: Game
var station: BuildStation
## Armes de la station (BuildRules.catalog, profil lu à l'ouverture).
var entries: Array[OwnedWeapon] = []
var filter := BUILDABLE
var rail := Hub2ArsenalRail.new()
var selected_uid := ""
var cards: Array = []  # StationDraw.Card
var col_heads: Array = []  # StationDraw.ColumnHead

var prompts: Hub2Prompts
var build_button: Hub2Button
var refill_button: Hub2Button
var chips: Dictionary = {}  # BUILDABLE / ALL -> StationDraw.Chip
var prev_button: Hub2Button
var next_button: Hub2Button
var note_label: Hub2Text
var build_label := ""
var _header: InventoryDraw.Header
var _arsenal_title: Hub2Text
var _arsenal_sub: Hub2Text
var _rail_area: Control
var _columns_box: HBoxContainer
var _ammo_title: Hub2Text
var _ammo_render: StationDraw.SmallRender
var _ammo_line: StationDraw.AmmoLine
var _ammo_price: Hub2Text
var _refill_text: Hub2Text
var _detail_head: InventoryDraw.DetailHead
var _render: StationDraw.FxImage
var _stats: Array[Hub2ArsenalStat] = []
var _parts_title: Hub2Text
var _parts_text: Hub2Text
var _price_label: Hub2Text
var _price_value: Hub2Text
var _ready_label: Hub2Text
var _ready_value: Hub2Text
var _build_face: Control
var _build_on := false
var _build_ready := false
var _aside_scroll: ScrollContainer
var _level := 1
var _scrap := 0
var _built_scale := -1.0
var _visible_cols := Hub2ArsenalRail.VISIBLE


func setup(g: Game) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# Créé par Hud._ready, avant Game._ready (voir InventoryPanel.setup).
	var session := g.get_node("Session") as Session
	session.inventory_changed.connect(_on_data_changed)
	session.stats_changed.connect(_on_data_changed)
	Settings.input_device_changed.connect(func(_pad: bool): if visible: _refresh_prompts())
	visible = false


# --------------------------------------------------------------------------
# Construction (valeurs de la maquette, TAILLE DES MENUS)
# --------------------------------------------------------------------------

func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	cards.clear()
	col_heads.clear()
	_stats.clear()
	chips.clear()
	_built_scale = Hub2Style.factor()
	add_child(InventoryDraw.Veil.new(0.6, 0.88))
	add_child(Hub2Style.blur_barrier())

	_header = InventoryDraw.Header.new()
	_header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_header.offset_left = Hub2Style.px(40)
	_header.offset_right = -Hub2Style.px(40)
	_header.offset_top = Hub2Style.px(28)
	add_child(_header)

	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.offset_left = Hub2Style.px(40)
	main.offset_right = -Hub2Style.px(40)
	main.offset_top = Hub2Style.px(90)
	main.offset_bottom = -Hub2Style.px(64)
	main.add_theme_constant_override("separation", int(Hub2Style.px(24)))
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main)

	# <section> : TON ARSENAL, rail, MUNITIONS (gap 14).
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(section)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.add_child(head)
	_arsenal_title = Hub2Text.new()
	_arsenal_title.setup("", Hub2Style.CHAKRA, 700, 16, Hub2Style.TEXT, 0.16)
	head.add_child(_arsenal_title)
	_arsenal_sub = Hub2Text.new()
	_arsenal_sub.setup("", Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.55))
	head.add_child(_arsenal_sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var chip_box := HBoxContainer.new()
	chip_box.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	chip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(chip_box)
	for f in [BUILDABLE, ALL]:
		var ch := StationDraw.Chip.new()
		ch.pressed.connect(set_filter.bind(f))
		chip_box.add_child(ch)
		chips[f] = ch
	section.add_child(_build_rail_box())
	section.add_child(_build_ammo_strip())

	main.add_child(_build_aside())

	prompts = Hub2Prompts.new()
	prompts.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompts.offset_top = -Hub2Style.px(Hub2Prompts.H)
	prompts.prompt_clicked.connect(_on_prompt)
	add_child(prompts)


func _build_rail_box() -> Control:
	var box := Hub2Box.new()
	box.glass()
	box.pad(1)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	prev_button = _arrow("‹", -1)
	row.add_child(prev_button)
	_rail_area = StationDraw.RailArea.new()
	_rail_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail_area.clip_contents = true
	_rail_area.resized.connect(_on_rail_resized)
	row.add_child(_rail_area)
	_columns_box = HBoxContainer.new()
	_columns_box.add_theme_constant_override("separation", int(Hub2Style.px(COL_GAP)))
	_columns_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_columns_box.offset_left = Hub2Style.px(RAIL_PAD)
	_columns_box.offset_right = -Hub2Style.px(RAIL_PAD)
	_rail_area.add_child(_columns_box)
	next_button = _arrow("›", 1)
	row.add_child(next_button)
	return box


func _arrow(t: String, dir: int) -> Hub2Button:
	var b := Hub2Button.new()
	b.custom_minimum_size.x = Hub2Style.px(ARROW_W)
	b.focus_mode = Control.FOCUS_NONE
	var face := StationDraw.ArrowFace.new()
	face.glyph = t
	b.add_content(face)
	b.set_meta("face", face)
	b.pressed.connect(shift.bind(dir))
	return b


## Bande MUNITIONS : padding 12 16, gap 16, verre 0,62, liseré.
func _build_ammo_strip() -> Control:
	var box := Hub2Box.new()
	box.glass()
	box.pad(13, 17, 13, 17)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	_ammo_title = Hub2Text.new()
	_ammo_title.setup("", Hub2Style.CHAKRA, 700, 12, Hub2Style.text_a(0.6), 0.16)
	row.add_child(_ammo_title)
	_ammo_render = StationDraw.SmallRender.new()
	row.add_child(_ammo_render)
	_ammo_line = StationDraw.AmmoLine.new()
	_ammo_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ammo_line.size_flags_vertical = Control.SIZE_FILL
	row.add_child(_ammo_line)
	_ammo_price = Hub2Text.new()
	_ammo_price.setup("", Hub2Style.MONO, 700, 14, Hub2Style.TEXT)
	row.add_child(_ammo_price)
	refill_button = Hub2Button.new()
	refill_button.focus_mode = Control.FOCUS_NONE
	refill_button.show_focus = false
	refill_button.box.pad(0, 14)
	refill_button.custom_minimum_size.y = Hub2Style.px(32)
	refill_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_refill_text = Hub2Text.new()
	_refill_text.setup("", Hub2Style.CHAKRA, 700, 12, Hub2Style.TEXT, 0.12)
	refill_button.add_content(_refill_text)
	refill_button.pressed.connect(press_refill)
	row.add_child(refill_button)
	return box


## Fiche : 360 px, verre 0,72 ; le bas (prix, CONSTRUIRE) reste en bas
## (margin-top: auto), le haut défile si besoin (130 %).
func _build_aside() -> Control:
	var aside := Hub2Box.new()
	aside.glass(ASIDE_BG, Hub2Style.LINE)
	aside.pad(1)
	aside.custom_minimum_size = Vector2(Hub2Style.px(ASIDE_W + 2.0), 0)
	aside.size_flags_horizontal = Control.SIZE_SHRINK_END
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 0)
	aside.add_child(av)
	_aside_scroll = Hub2ItemsUi.scroller()
	_aside_scroll.follow_focus = false
	_aside_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	av.add_child(_aside_scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 0)
	_aside_scroll.add_child(inner)
	_detail_head = InventoryDraw.DetailHead.new()
	_detail_head.pad_bottom = 10.0
	inner.add_child(_detail_head)
	# Rendu : 96 px, margin 0 18, effet de rareté (rayons de 220 px).
	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_left", int(Hub2Style.px(18)))
	rm.add_theme_constant_override("margin_right", int(Hub2Style.px(18)))
	rm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(rm)
	_render = StationDraw.FxImage.new(StationDraw.RAYS_SHEET)
	_render.shadow_dy = 8.0
	_render.shadow_blur = 12.0
	_render.custom_minimum_size.y = Hub2Style.px(96)
	rm.add_child(_render)
	var stats_box := _section_box(12, 18, 12, 18)
	inner.add_child(stats_box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(Hub2Style.px(14)))
	grid.add_theme_constant_override("v_separation", int(Hub2Style.px(10)))
	stats_box.add_child(grid)
	for i in Hub2ArsenalView.STATS.size():
		var st := Hub2ArsenalStat.new()
		st.square = 28.0
		st.icon_size = 16.0
		st.value_size = 14.0
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(st)
		_stats.append(st)
	var parts_box := _section_box(10, 18, 10, 18)
	inner.add_child(parts_box)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parts_box.add_child(pv)
	_parts_title = Hub2Text.new()
	_parts_title.setup("", Hub2Style.CHAKRA, 600, 12, Hub2Style.text_a(0.55), 0.18)
	pv.add_child(_parts_title)
	_parts_text = Hub2Text.new()
	_parts_text.setup("", Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.55))
	pv.add_child(_parts_text)
	# Bas : prix, manche, CONSTRUIRE, note (padding 14 18, gap 10).
	var bottom := _section_box(14, 18, 14, 18)
	av.add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bv)
	var r1 := _pair_row()
	bv.add_child(r1[0])
	_price_label = r1[1]
	_price_value = r1[2]
	var r2 := _pair_row()
	bv.add_child(r2[0])
	_ready_label = r2[1]
	_ready_value = r2[2]
	build_button = Hub2Button.new()
	build_button.focus_mode = Control.FOCUS_NONE
	build_button.show_focus = false
	build_button.custom_minimum_size.y = Hub2Style.px(48)
	build_button.box.chamfer(12)
	_build_face = Control.new()
	_build_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_face.draw.connect(_draw_build_face)
	build_button.add_content(_build_face)
	build_button.pressed.connect(press_build)
	bv.add_child(build_button)
	note_label = Hub2Text.new()
	note_label.setup("", Hub2Style.BARLOW, 400, 12, Hub2Style.text_a(0.6))
	note_label.align = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(note_label)
	return aside


## Bloc de la fiche : liseré haut 1 px rgba(255,255,255,.08), padding donné.
func _section_box(t: float, r: float, b: float, l: float) -> Hub2Box:
	var box := Hub2Box.new()
	box.flat(Color(0, 0, 0, 0), Hub2Style.LINE, 1.0)
	box.border = Vector4(0, 1, 0, 0)
	box.pad(t + 1.0, r, b, l)
	return box


## Ligne « libellé (Barlow 14, 70 %) … valeur (JetBrains Mono 14 700) ».
func _pair_row() -> Array:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Hub2Text.new()
	l.setup("", Hub2Style.BARLOW, 400, 14, Hub2Style.text_a(0.7))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Hub2Text.new()
	v.setup("", Hub2Style.MONO, 700, 14, Hub2Style.TEXT)
	row.add_child(v)
	return [row, l, v]


# --------------------------------------------------------------------------
# Ouverture, fermeture
# --------------------------------------------------------------------------

## Ouvre l'interface de la station `st` : arsenal du profil local relu, souris
## libérée, focus sur l'arme choisie (la construction en cours, sinon la plus
## chère du plus haut niveau atteint).
func open(st: BuildStation) -> void:
	if st != station:
		if station and station.builds_changed.is_connected(_on_builds_changed):
			station.builds_changed.disconnect(_on_builds_changed)
		station = st
		if station:
			station.builds_changed.connect(_on_builds_changed)
	if visible:
		refresh()
		return
	if not is_equal_approx(_built_scale, Hub2Style.factor()):
		_build()
	# Défi hebdomadaire (§4.18) : armes de base seulement (pas d'arsenal).
	entries = BuildRules.catalog(null if game.challenge else ProfileStore.load_profile())
	_read_player()
	var b := local_build()
	selected_uid = String(b.w.get("uid", "")) if not b.is_empty() else ""
	if _entry(selected_uid) != null and filter == BUILDABLE and not _passes(_entry(selected_uid), BUILDABLE):
		filter = ALL
	visible = true
	_reload(true)
	refresh()
	game.capture_mouse(false)
	var c := selected_card()
	if c:
		c.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f and is_ancestor_of(f):
		f.release_focus()
	if GameState.is_in_game():
		game.capture_mouse(true)


# --------------------------------------------------------------------------
# Rail des niveaux
# --------------------------------------------------------------------------

## L'arme passe-t-elle le filtre ? CONSTRUCTIBLES : niveau atteint.
func _passes(o: OwnedWeapon, f: String) -> bool:
	return o != null and (f == ALL or o.level <= _level)


func _entry(uid: String) -> OwnedWeapon:
	for o in entries:
		if o.uid == uid:
			return o
	return null


## Armes du filtre courant.
func filtered() -> Array:
	return entries.filter(func(o: OwnedWeapon): return _passes(o, filter))


## Ordre dans une colonne : prix décroissant, puis comme l'ARSENAL.
static func weapon_before(a: OwnedWeapon, b: OwnedWeapon) -> bool:
	var pa := BuildRules.owned_price(a)
	var pb := BuildRules.owned_price(b)
	if pa != pb:
		return pa > pb
	return Hub2ArsenalView.weapon_before(a, b)


## Rail reconstruit (filtre, ouverture) ; `fresh` : fenêtre centrée sur
## l'arme choisie.
func _reload(fresh: bool) -> void:
	var old_start := rail.start
	rail.setup(filtered(), weapon_before)
	_visible_cols = _fit_columns()
	rail.visible = _visible_cols
	var found := selected_uid != "" and rail.select_uid(selected_uid)
	if not found:
		_default_selection()
	if fresh or not found:
		rail.center_on_selection()
	else:
		rail.start = old_start
		rail.ensure_visible()
	_store_selection()
	_build_columns()
	_apply_selection()


## Choix par défaut : la plus chère du plus haut niveau atteint.
func _default_selection() -> void:
	if rail.is_empty():
		return
	var best := 0
	for i in rail.levels.size():
		if rail.levels[i] <= _level:
			best = i
	rail.select_at(best, 0)


func _store_selection() -> void:
	var it: Variant = rail.selected()
	selected_uid = String(it.uid) if it != null else ""


## Colonnes visibles selon la largeur du rail (5 à 100 %).
func _fit_columns() -> int:
	var w := _rail_area.size.x if _rail_area and _rail_area.size.x > 0.0 else \
			get_viewport_rect().size.x - Hub2Style.px(80) - Hub2Style.px(24) - Hub2Style.px(ASIDE_W + 2.0) \
			- Hub2Style.px(2) - Hub2Style.px(ARROW_W) * 2.0
	return Hub2ArsenalRail.fit_visible(w - Hub2Style.px(RAIL_PAD) * 2.0, Hub2Style.px(COL_W), Hub2Style.px(COL_GAP))


func _on_rail_resized() -> void:
	if not visible:
		return
	var n := _fit_columns()
	if n != _visible_cols:
		var had := _focus_owner() is StationDraw.Card
		_visible_cols = n
		rail.visible = n
		rail.ensure_visible()
		_build_columns()
		_apply_selection()
		if had and selected_card():
			selected_card().grab_focus()


func _build_columns() -> void:
	for c in _columns_box.get_children():
		_columns_box.remove_child(c)
		c.queue_free()
	cards.clear()
	col_heads.clear()
	var vis := rail.visible_cols()
	for k in rail.visible:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_columns_box.add_child(col)
		if k >= vis.size():
			continue
		var i: int = vis[k]
		var items := rail.column(i)
		var head := StationDraw.ColumnHead.new()
		head.level = rail.levels[i]
		head.count = items.size()
		head.over = rail.levels[i] > _level
		col.add_child(head)
		col_heads.append(head)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		sc.follow_focus = true
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(sc)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", int(Hub2Style.px(CARD_GAP)))
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sc.add_child(list)
		for r in items.size():
			var card := StationDraw.Card.new()
			var o: OwnedWeapon = items[r]
			card.uid = o.uid
			card.level = o.level
			card.set_meta("col", i)
			card.set_meta("row", r)
			card.setup(card_data(o))
			card.focus_entered.connect(_on_card_focus.bind(card))
			card.pressed.connect(_on_card_pressed.bind(card))
			card.nav.connect(_on_card_nav)
			list.add_child(card)
			cards.append(card)
	_update_arrows()


func card_at(i: int, r: int) -> StationDraw.Card:
	for c in cards:
		if int(c.get_meta("col")) == i and int(c.get_meta("row")) == r:
			return c
	return null


func selected_card() -> StationDraw.Card:
	return card_at(rail.sel_col, rail.sel_row)


func card_of(uid: String) -> StationDraw.Card:
	for c in cards:
		if c.uid == uid:
			return c
	return null


func selected_weapon() -> OwnedWeapon:
	return rail.selected() as OwnedWeapon


func _update_arrows() -> void:
	for pair in [[prev_button, -1], [next_button, 1]]:
		var b: Hub2Button = pair[0]
		var on := rail.can_shift(int(pair[1]))
		(b.get_meta("face") as StationDraw.ArrowFace).enabled = on
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW


## ‹ › : fenêtre décalée d'un niveau (la sélection ne change pas ; si sa
## carte sort de la fenêtre avec le focus, le focus va à la colonne visible la
## plus proche).
func shift(dir: int) -> void:
	if not rail.shift(dir):
		return
	var had := _focus_owner() is StationDraw.Card
	_build_columns()
	_apply_selection()
	if had:
		var c := selected_card()
		if c == null:
			c = card_at(clampi(rail.sel_col, rail.start, rail.start + rail.visible - 1), 0)
		if c:
			c.grab_focus()


## Choisit l'arme `uid` (tests, clic) ; faux si elle n'est pas dans le rail.
func select_uid(uid: String) -> bool:
	if not rail.select_uid(uid):
		return false
	var old := rail.start
	rail.ensure_visible()
	_store_selection()
	if rail.start != old:
		_build_columns()
	_apply_selection()
	return true


func set_filter(f: String) -> void:
	if f == filter:
		return
	filter = f
	var had := _focus_owner() is StationDraw.Card
	_reload(false)
	refresh()
	if had and selected_card():
		selected_card().grab_focus()


func toggle_filter() -> void:
	set_filter(ALL if filter == BUILDABLE else BUILDABLE)


func _on_card_focus(card: StationDraw.Card) -> void:
	var i := int(card.get_meta("col"))
	var r := int(card.get_meta("row"))
	if i != rail.sel_col or r != rail.sel_row:
		rail.select_at(i, r)
		_store_selection()
		_apply_selection()


func _on_card_pressed(card: StationDraw.Card) -> void:
	var mouse := card.pressed_by_mouse
	card.pressed_by_mouse = false
	_on_card_focus(card)
	if not mouse:
		press_build()


## ◄ ► ▲ ▼ sur une carte.
func _on_card_nav(dir: Vector2i) -> void:
	if dir.x != 0:
		var old := rail.start
		if not rail.move_col(dir.x):
			return
		if rail.start != old:
			_build_columns()
	elif not rail.move_row(dir.y):
		return
	Audio.play_ui(MenuStyle.SND_MOVE, MenuStyle.VOL_MOVE)
	_store_selection()
	var c := selected_card()
	if c:
		c.grab_focus()
	_apply_selection()


func _apply_selection() -> void:
	for c in cards:
		(c as StationDraw.Card).selected = int(c.get_meta("col")) == rail.sel_col and int(c.get_meta("row")) == rail.sel_row
	var sl := rail.selected_level()
	for h in col_heads:
		(h as StationDraw.ColumnHead).on = (h as StationDraw.ColumnHead).level == sl
		(h as StationDraw.ColumnHead).queue_redraw()
	_update_arrows()
	if visible:
		_refresh_sheet()


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner() if is_inside_tree() else null


# --------------------------------------------------------------------------
# Actions (clic, A, Entrée, R, [F] ; les tests les appellent directement)
# --------------------------------------------------------------------------

## Construction du joueur local ({} : aucune).
func local_build() -> Dictionary:
	return station.local_build() if station else {}


## CONSTRUIRE l'arme choisie (rien si elle ne peut pas l'être : niveau,
## station occupée, ferraille ; le serveur vérifie tout de nouveau).
func press_build() -> void:
	var o := selected_weapon()
	if station == null or o == null or not can_build(o):
		return
	station.request_build(o)


## L'arme `o` peut-elle être construite maintenant (niveau, une construction
## à la fois, ferraille) ?
func can_build(o: OwnedWeapon) -> bool:
	return o != null and refusal(o, _level, _scrap, not local_build().is_empty()) == ""


func press_refill() -> void:
	if station:
		station.request_refill()


## [F] dans l'interface : récupère l'arme prête (le serveur décide ; sac
## plein : refus et message).
func collect() -> void:
	var b := local_build()
	if not b.is_empty() and bool(b.ready) and game.interact:
		game.interact.srv_interact.rpc_id(1, BuildStation.ID)


func _on_prompt(id: String) -> void:
	match id:
		Hub2Input.ACCEPT:
			press_build()
		"reload":
			press_refill()
		"close":
			close()


## R (action « reload ») : recharger ; Tab / Y : filtre ; [F] (« interact ») :
## récupérer l'arme prête. Échap / B / [I] : Hud.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var jb := event as InputEventJoypadButton
	if event.is_action_pressed("reload"):
		press_refill()
		get_viewport().set_input_as_handled()
	elif (jb and jb.pressed and jb.button_index == JOY_BUTTON_Y) or Hub2Input.is_key(event, KEY_TAB):
		toggle_filter()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		collect()
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Affichage
# --------------------------------------------------------------------------

func _on_data_changed(pid: int) -> void:
	if visible and pid == multiplayer.get_unique_id():
		refresh()


func _on_builds_changed() -> void:
	if visible:
		refresh()


func _read_player() -> void:
	var pd := game.session.local_data()
	_level = pd.level if pd else 1
	_scrap = pd.points if pd else 0


func refresh() -> void:
	if not visible:
		return
	_read_player()
	_header.set_texts(Lang.t("STATION DE CONSTRUCTION", "CONSTRUCTION STATION"), Hub2Style.num(_scrap), Lang.t("ferraille", "scrap"), "")
	_arsenal_title.text = Lang.t("TON ARSENAL", "YOUR ARSENAL")
	_arsenal_sub.text = Lang.t("Trié par niveau", "Sorted by level")
	(chips[BUILDABLE] as StationDraw.Chip).set_label(Lang.t("CONSTRUCTIBLES", "BUILDABLE"))
	(chips[ALL] as StationDraw.Chip).set_label(Lang.t("TOUTES", "ALL"))
	for f in chips:
		(chips[f] as StationDraw.Chip).on = f == filter
	for c in cards:
		var o := _entry((c as StationDraw.Card).uid)
		if o:
			(c as StationDraw.Card).setup(card_data(o))
	_refresh_ammo()
	_refresh_sheet()
	_refresh_prompts()


## Données d'une carte (maquette : cards).
func card_data(o: OwnedWeapon) -> Dictionary:
	var price := BuildRules.owned_price(o)
	var lock := o.level > _level
	var b := local_build()
	var mine := not b.is_empty() and String(b.w.get("uid", "")) == o.uid
	var rounds := BuildRules.rounds_text(BuildRules.rounds(price))
	var rc := Hub2Style.text_a(0.6)
	if mine:
		rounds = Lang.t("PRÊTE", "READY") if bool(b.ready) else Lang.t("EN COURS", "BUILDING")
		rc = Hub2Style.TEAL
	return {"name": HubGear.weapon_name(o.weapon_id), "color": Hub2Style.rarity_color(o.rarity), "rarity": int(o.rarity),
		"rarity_name": GameWeapon.rarity_name(o.rarity), "img": HubRenders.weapon(o.weapon_id), "locked": lock,
		"price": Hub2ArsenalView.required_text(o.level) if lock else Hub2Style.num(price), "price_bad": lock or price > _scrap,
		"rounds": rounds, "rounds_color": rc}


## Raison pour laquelle `o` ne se construit pas ("" : constructible), dans
## l'ordre de la maquette : niveau, station occupée, ferraille. Pure (tests).
static func refusal(o: OwnedWeapon, player_level: int, scrap: int, busy: bool) -> String:
	if o.level > player_level:
		return Hub2ArsenalView.required_text(o.level)
	if busy:
		return Lang.t("STATION OCCUPÉE", "STATION BUSY")
	var p := BuildRules.owned_price(o)
	if p > scrap:
		return Lang.t("IL MANQUE %s", "%s SHORT") % Hub2Style.num(p - scrap)
	return ""


## Manche à la fin de laquelle l'arme lancée maintenant serait prête.
func ready_round_of(o: OwnedWeapon) -> int:
	var r: RoundManager = game.rounds
	var n := r.round_n if r else 0
	var active := r != null and r.phase == RoundManager.Phase.ACTIVE
	return BuildRules.ready_round(n, active, BuildRules.owned_price(o))


func _refresh_sheet() -> void:
	var o := selected_weapon()
	if o == null:
		_detail_head.set_data(Hub2Style.text_a(0.3), "", "—", "", Hub2Style.text_a(0.7), [])
		_render.set_data(null, 0)
		for st in _stats:
			st.line = {}
		_parts_title.text = ""
		_parts_text.text = Lang.t("Aucune arme ne correspond au filtre.", "No weapon matches the filter.")
		_price_label.text = ""
		_price_value.text = ""
		_ready_label.text = ""
		_ready_value.text = ""
		build_label = Lang.t("CONSTRUIRE", "BUILD")
		_set_build_look(false, false)
		note_label.text = ""
		return
	var w := GameWeapon.from_owned(o)
	_detail_head.set_data(Hub2Style.rarity_color(o.rarity), "%s · %s" % [GameWeapon.rarity_name(o.rarity), Hub2ArsenalView.class_name_of(o.weapon_id)],
			HubGear.weapon_name(o.weapon_id), Hub2ArsenalView.level_text(o.level), Hub2Style.text_a(0.7), [])
	_render.set_data(HubRenders.weapon(o.weapon_id), int(o.rarity))
	var lines := InventoryPanel.compare_lines(w, {})
	for i in _stats.size():
		_stats[i].line = lines[i] if i < lines.size() else {}
	_parts_title.text = Lang.t("PIÈCES · %d / %d", "PARTS · %d / %d") % [mini(o.parts.size(), o.slot_count()), o.slot_count()]
	var has_parts := not o.parts.is_empty()
	_parts_text.text = Lang.t("Construite avec ses pièces de l’arsenal", "Built with its arsenal parts") if has_parts \
			else Lang.t("Aucune pièce montée", "No part mounted")
	_parts_text.color = Hub2Style.TEAL if has_parts else Hub2Style.text_a(0.55)
	var price := BuildRules.owned_price(o)
	_price_label.text = Lang.t("Prix", "Price")
	_price_value.text = Lang.t("%s ferraille", "%s scrap") % Hub2Style.num(price)
	_price_value.color = Hub2Style.BAD if price > _scrap else Hub2Style.TEXT
	_ready_label.text = Lang.t("Prête à la fin de la manche", "Ready at the end of round")
	var b := local_build()
	var mine := not b.is_empty() and String(b.w.get("uid", "")) == o.uid
	_ready_value.text = str(int(b["round"]) if mine else ready_round_of(o))
	if mine and bool(b.ready):
		build_label = Lang.t("PRÊTE · %s RÉCUPÉRER", "READY · %s COLLECT") % Settings.action_label("interact")
		_set_build_look(false, true)
		note_label.text = Lang.t("Une place libre dans le sac est nécessaire", "A free backpack slot is needed")
		note_label.color = Hub2Style.text_a(0.6)
		return
	if mine:
		build_label = Lang.t("EN CONSTRUCTION · MANCHE %d", "BUILDING · ROUND %d") % int(b["round"])
		_set_build_look(false, false)
		note_label.text = Lang.t("Une construction à la fois", "One build at a time")
		note_label.color = Hub2Style.text_a(0.6)
		return
	var why := refusal(o, _level, _scrap, not b.is_empty())
	build_label = Lang.t("CONSTRUIRE", "BUILD")
	_set_build_look(why == "", false)
	if why == "":
		note_label.text = Lang.t("Il te restera %s ferraille", "You will have %s scrap left") % Hub2Style.num(_scrap - price)
		note_label.color = Hub2Style.text_a(0.6)
	else:
		note_label.text = why
		note_label.color = Hub2Style.BAD


## CONSTRUIRE : jaune (#F5C542, texte #0B0B0C) si possible, sinon gris
## (rgba(255,255,255,.08), texte 40 %) ; arme prête : turquoise.
func _set_build_look(can: bool, ready: bool) -> void:
	_build_on = can
	_build_ready = ready
	if ready:
		build_button.box.flat(Hub2Style.TEAL)
	elif can:
		build_button.box.flat(Hub2Style.YELLOW)
	else:
		build_button.box.flat(Hub2Style.white_a(0.08))
	build_button.box.chamfer(12)
	build_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can else Control.CURSOR_FORBIDDEN
	_build_face.queue_redraw()


## Texte du bouton : Chakra Petch 18 px 700 0,14em, centré ; rapetisse s'il
## ne tient pas (jamais coupé).
func _draw_build_face() -> void:
	var col := Hub2Style.INK if (_build_on or _build_ready) else Hub2Style.text_a(0.4)
	var room := _build_face.size.x - Hub2Style.px(16)
	var sz := 18.0
	while sz > 11.0:
		var s := Hub2Style.fs(sz)
		if Hub2Style.text_width(build_label, Hub2Style.font(Hub2Style.CHAKRA, 700), s, Hub2Style.tracking_px(0.14, s)) <= room:
			break
		sz -= 0.5
	Hub2ArsenalDraw.text(_build_face, build_label, Hub2Style.CHAKRA, 700, sz, col, 0.14, 0.0,
			Hub2ArsenalDraw.baseline(Hub2Style.CHAKRA, 700, sz, 0.0, _build_face.size.y), _build_face.size.x, HORIZONTAL_ALIGNMENT_CENTER)


## Bande MUNITIONS : arme en main, chargeur / réserve, prix de la recharge
## (rouge si trop cher), « R · RECHARGER » (grisé si rien à recharger).
func _refresh_ammo() -> void:
	_ammo_title.text = Lang.t("MUNITIONS", "AMMO")
	var pd := game.session.local_data()
	var held: Dictionary = pd.current_weapon() if pd else {}
	var key := Settings.action_label("reload")
	_refill_text.text = "%s · %s" % [key, Lang.t("RECHARGER", "REFILL")]
	if held.is_empty():
		_ammo_render.tex = null
		_ammo_line.set_texts(Lang.t("Aucune arme en main", "No weapon in hand"), "")
		_ammo_price.text = ""
		_set_refill_look(false)
	else:
		_ammo_render.tex = HubRenders.weapon(String(held.get("id", "")))
		var s := GameWeapon.stats(held)
		var count := ""
		if int(s.get("mag", 0)) > 0:
			count = "%d / %d" % [int(held.get("mag", 0)), int(held.get("reserve", 0))]
		_ammo_line.set_texts(Lang.t("%s en main · ", "%s in hand · ") % InventoryPanel.weapon_title(held) if count != "" \
				else Lang.t("%s en main", "%s in hand") % InventoryPanel.weapon_title(held), count)
		var cost := BuildRules.refill_price(held)
		var full := BuildRules.ammo_full(held)
		_ammo_price.text = "" if full and count == "" else Hub2Style.num(cost)
		_ammo_price.color = Hub2Style.BAD if cost > _scrap and not full else Hub2Style.TEXT
		_set_refill_look(not full)
	_ammo_render.queue_redraw()


## « R · RECHARGER » : liseré 1 px rgba(242,240,234,.5), texte #F2F0EA ;
## grisé (munitions pleines, mêlée, rien en main).
func _set_refill_look(on: bool) -> void:
	refill_button.box.flat(Color(0, 0, 0, 0), Hub2Style.text_a(0.5 if on else 0.2), 1.0)
	refill_button.box.pad(0, 14)
	_refill_text.color = Hub2Style.TEXT if on else Hub2Style.text_a(0.4)
	refill_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW


## Invites : ◄ ► NIVEAU, ▲ ▼ MÊME NIVEAU, A / Entrée CONSTRUIRE, R RECHARGER
## (touche réelle de « reload »), Échap / B FERMER ; aide : recycler dans
## l'inventaire (touche réelle de « inventory »).
func _refresh_prompts() -> void:
	prompts.set_items([["level", Lang.t("Niveau", "Level"), PackedStringArray(["◄ ►"]), []],
		["same", Lang.t("Même niveau", "Same level"), PackedStringArray(["▲ ▼"]), []],
		[Hub2Input.ACCEPT, Lang.t("Construire", "Build")],
		["reload", Lang.t("Recharger", "Refill"), PackedStringArray([Settings.action_label("reload")]), []],
		["close", Lang.t("Fermer", "Close"), PackedStringArray([Settings.code_label(Settings.binding("pause")) if Settings.binding("pause") != "" else Lang.t("Échap", "Esc")]), [JOY_BUTTON_B]]])
	prompts.help = Lang.t("Pour recycler une arme, ouvre l’inventaire (%s).", "To recycle a weapon, open the inventory (%s).") \
			% Settings.action_label("inventory")
