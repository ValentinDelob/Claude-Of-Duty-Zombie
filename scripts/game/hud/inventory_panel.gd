class_name InventoryPanel
extends Control
## Inventaire de partie (GAME_CONCEPT §4.12 ; maquette validée
## docs/hub_v2/InventaireJeu.dc.html), ouvert et fermé par l'action
## « inventory » ([I], croix haut à la manette, lue AVANT l'interface par
## Hud._input ; Échap / B ferment aussi).
##
## Voile radial sur la partie qui continue, en-tête (INVENTAIRE, ferraille,
## « LA PARTIE CONTINUE · MANCHE N »), EN MAIN (3 cases, touches 1 · 2 · 3),
## SAC À DOS (4 cases, NEUF sur une arme ramassée pas encore vue), PIÈCES
## TROUVÉES (pièces de la partie), fiche de 360 px à droite (rareté ·
## famille, nom, NIV., « Comparé à X (en main) » pour une arme du sac, six
## statistiques comme l'ARSENAL du hub avec l'écart à l'arme comparée, pièces
## n / m, valeur de recyclage), barre d'invites (A ÉQUIPER / ÉCHANGER,
## X RECYCLER, Y PIÈCES, I FERMER ; touches du périphérique utilisé).
##
## La fiche montre la case qui a le focus (clavier, manette, clic), sinon la
## case choisie, sinon l'arme tenue. Choisir une case d'une rangée puis une
## case de l'autre échange les deux armes (Combat.srv_swap, le serveur
## décide) ; une arme du sac choisie deux fois s'équipe (place libre en main,
## sinon à la place de l'arme tenue) ; une arme de niveau trop élevé est
## refusée (NIV. en rouge, message). Une pièce puis une arme (ou l'inverse) :
## montage demandé (LootSystem.srv_mount, règle OwnedWeapon.can_mount).
## Recycler (X, Suppr) : deux appuis, jamais la dernière arme.
##
## La partie continue pendant qu'il est ouvert (même en solo) ; le joueur
## local ne bouge plus et ne tire plus (Game.menu_open).

## Rangées de press() : en main, sac à dos, pièces.
const ROW_HANDS := 0
const ROW_BAG := 1
const ROW_PARTS := 2
## Fiche : rgba(10, 11, 13, 0.72), 360 px.
const ASIDE_BG := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.72)
const ASIDE_W := 360.0
## Message de refus (niveau, dernière arme) dans la barre d'invites (s).
const NOTICE_SEC := 2.5
## Largeur d'une case du sac (px de la maquette) sous laquelle le sac passe
## sur deux colonnes (194 px à 100 %).
const BAG_MIN_SLOT_W := 170.0

var game: Game
var hand_buttons: Array[InventorySlot] = []
var bag_buttons: Array[InventorySlot] = []
var part_buttons: Array[InventorySlot] = []
## Case choisie en attente de la seconde (-1 : aucune).
var selected_hand := -1
var selected_bag := -1
## Pièce choisie (indice dans LootSystem.my_parts, -1 : aucune).
var selected_part := -1
## Recyclage : premier appui fait sur la case `_recycle_slot`, le second
## confirme.
var _recycle_armed := false
var _recycle_slot: Array = []
## Armes déjà vues (uid) : une arme du sac absente est NEUVE.
var _seen: Dictionary = {}
var _notice := ""
var _notice_t := 0.0
var _loot_bound := false
var _built_scale := -1.0

var prompts: Hub2Prompts
var _header: InventoryDraw.Header
var _head_hands: InventoryDraw.SectionHead
var _head_bag: InventoryDraw.SectionHead
var _head_parts: InventoryDraw.SectionHead
var _parts_row: HBoxContainer
var _bag_grid: GridContainer
var _parts_scroll: ScrollContainer
var _left_scroll: ScrollContainer
var aside_box: Hub2Box
var _detail_head: InventoryDraw.DetailHead
var _stats: Array[Hub2ArsenalStat] = []
var _parts_title: Hub2Text
var _part_rows: VBoxContainer
var _recycle_box: Hub2Box
var recycle_label: Hub2Text
var recycle_value_label: Hub2Text


func setup(g: Game) -> void:
	game = g
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# Créé par Hud._ready, avant Game._ready : `game.session` (@onready) n'est
	# pas encore rempli, le nœud existe déjà.
	var session := g.get_node("Session") as Session
	session.inventory_changed.connect(_on_data_changed)
	session.stats_changed.connect(_on_data_changed)
	visible = false


# --------------------------------------------------------------------------
# Construction (valeurs de la maquette, TAILLE DES MENUS)
# --------------------------------------------------------------------------

func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	hand_buttons.clear()
	bag_buttons.clear()
	part_buttons.clear()
	_stats.clear()
	_built_scale = Hub2Style.factor()
	add_child(InventoryDraw.Veil.new())
	# Le verre des cases floute la partie déjà voilée (backdrop-filter).
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
	main.offset_top = Hub2Style.px(92)
	main.offset_bottom = -Hub2Style.px(64)
	main.add_theme_constant_override("separation", int(Hub2Style.px(24)))
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main)

	# Colonne de gauche (défile si elle ne tient pas : 130 %).
	_left_scroll = Hub2ItemsUi.scroller()
	_left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(_left_scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(Hub2Style.px(18)))
	_left_scroll.add_child(col)

	_head_hands = InventoryDraw.SectionHead.new()
	var hands := _grid_row(GameWeapon.HANDS, InventorySlot.Kind.HAND, ROW_HANDS, hand_buttons)
	col.add_child(_group(_head_hands, hands))
	_head_bag = InventoryDraw.SectionHead.new()
	_bag_grid = _grid_row(GameWeapon.BAG, InventorySlot.Kind.BAG, ROW_BAG, bag_buttons)
	col.add_child(_group(_head_bag, _bag_grid))
	_left_scroll.resized.connect(_fit_bag)
	_head_parts = InventoryDraw.SectionHead.new()
	_parts_scroll = ScrollContainer.new()
	_parts_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_parts_scroll.follow_focus = true
	_parts_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_parts_row = HBoxContainer.new()
	_parts_row.add_theme_constant_override("separation", int(Hub2Style.px(12)))
	_parts_scroll.add_child(_parts_row)
	col.add_child(_group(_head_parts, _parts_scroll))

	# Fiche (aside) : 360 px, verre 0.72, liseré 1 px ; le bas (recyclage)
	# reste en bas (margin-top: auto), le reste défile si besoin.
	var aside := Hub2Box.new()
	aside.glass(ASIDE_BG, Hub2Style.LINE)
	aside.pad(1)
	# width: 360px + liseré 1 px de chaque côté (content-box).
	aside.custom_minimum_size = Vector2(Hub2Style.px(ASIDE_W + 2.0), 0)
	aside.size_flags_horizontal = Control.SIZE_SHRINK_END
	main.add_child(aside)
	aside_box = aside
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 0)
	aside.add_child(av)
	var asc := Hub2ItemsUi.scroller()
	asc.follow_focus = false
	asc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	av.add_child(asc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 0)
	asc.add_child(inner)
	_detail_head = InventoryDraw.DetailHead.new()
	inner.add_child(_detail_head)
	var stats_box := _section_box()
	inner.add_child(stats_box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", int(Hub2Style.px(14)))
	grid.add_theme_constant_override("v_separation", int(Hub2Style.px(12)))
	stats_box.add_child(grid)
	for i in Hub2ArsenalView.STATS.size():
		var st := Hub2ArsenalStat.new()
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(st)
		_stats.append(st)
	var parts_box := _section_box()
	inner.add_child(parts_box)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	parts_box.add_child(pv)
	_parts_title = Hub2Text.new()
	_parts_title.setup("", Hub2Style.CHAKRA, 600, 12, Hub2Style.text_a(0.55), 0.18)
	pv.add_child(_parts_title)
	_part_rows = VBoxContainer.new()
	_part_rows.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	pv.add_child(_part_rows)
	_recycle_box = _section_box()
	_recycle_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_recycle_box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_recycle_box.gui_input.connect(_on_recycle_click)
	av.add_child(_recycle_box)
	var rh := HBoxContainer.new()
	rh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recycle_box.add_child(rh)
	recycle_label = Hub2Text.new()
	recycle_label.setup("", Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.65))
	recycle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(recycle_label)
	recycle_value_label = Hub2Text.new()
	recycle_value_label.setup("", Hub2Style.MONO, 700, 14, Hub2Style.TEXT)
	rh.add_child(recycle_value_label)

	prompts = Hub2Prompts.new()
	prompts.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompts.offset_top = -Hub2Style.px(Hub2Prompts.H)
	prompts.prompt_clicked.connect(_on_prompt)
	add_child(prompts)

	_refresh_parts([])


## Manette, flèches : d'une rangée à l'autre (sac sur 4 ou 2 colonnes ;
## pièces sous le sac s'il y en a).
func _set_neighbors(has_parts: bool) -> void:
	var cols := _bag_grid.columns
	for i in hand_buttons.size():
		hand_buttons[i].focus_neighbor_bottom = hand_buttons[i].get_path_to(bag_buttons[mini(i, cols - 1)])
	for i in bag_buttons.size():
		var b := bag_buttons[i]
		b.focus_neighbor_top = b.get_path_to(hand_buttons[mini(i, hand_buttons.size() - 1)] if i < cols else bag_buttons[i - cols])
		if i + cols < bag_buttons.size():
			b.focus_neighbor_bottom = b.get_path_to(bag_buttons[i + cols])
		elif has_parts:
			b.focus_neighbor_bottom = b.get_path_to(part_buttons[mini(i % cols, part_buttons.size() - 1)])
		else:
			b.focus_neighbor_bottom = NodePath("")
	for p in part_buttons:
		p.focus_neighbor_top = p.get_path_to(bag_buttons[bag_buttons.size() - cols])


## Groupe d'une section : titre puis contenu à 10 px.
func _group(head: Control, content: Control) -> VBoxContainer:
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(head)
	g.add_child(content)
	return g


## Grille d'une rangée (repeat(n, minmax(0, 1fr)), gap 12 px).
func _grid_row(n: int, kind: InventorySlot.Kind, row: int, into: Array[InventorySlot]) -> GridContainer:
	var hb := GridContainer.new()
	hb.columns = n
	hb.add_theme_constant_override("h_separation", int(Hub2Style.px(12)))
	hb.add_theme_constant_override("v_separation", int(Hub2Style.px(12)))
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in n:
		var b := InventorySlot.new()
		b.setup(kind)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.0
		b.pressed.connect(press.bind(row, i))
		hb.add_child(b)
		into.append(b)
	return hb


## SAC À DOS : quatre colonnes comme la maquette ; deux quand une case serait
## trop étroite pour ses textes (TAILLE DES MENUS au-delà de 105 %).
func _fit_bag() -> void:
	var gap := Hub2Style.px(12)
	var slot_w := (_left_scroll.size.x - gap * (GameWeapon.BAG - 1)) / float(GameWeapon.BAG)
	var cols := GameWeapon.BAG if slot_w >= Hub2Style.px(BAG_MIN_SLOT_W) else 2
	if _bag_grid.columns != cols:
		_bag_grid.columns = cols
		_set_neighbors(game != null and game.loot != null and not game.loot.my_parts.is_empty())


## Bloc de la fiche : liseré haut 1 px rgba(255,255,255,.08), padding 14 18.
func _section_box() -> Hub2Box:
	var b := Hub2Box.new()
	b.flat(Color(0, 0, 0, 0), Hub2Style.LINE, 1.0)
	b.border = Vector4(0, 1, 0, 0)
	b.pad(15, 18, 14, 18)
	return b


# --------------------------------------------------------------------------
# Ouverture, fermeture
# --------------------------------------------------------------------------

## Ouvre le panneau : souris libérée, focus sur la première arme NEUVE du
## sac, sinon sur l'arme tenue.
func open() -> void:
	if not is_equal_approx(_built_scale, Hub2Style.factor()):
		_build()
	selected_hand = -1
	selected_bag = -1
	_recycle_armed = false
	selected_part = -1
	_notice = ""
	if not _loot_bound and game.loot:
		_loot_bound = true
		game.loot.loot_changed.connect(func(): if visible: refresh())
	visible = true
	var vp := get_viewport()
	if vp and not vp.gui_focus_changed.is_connected(_on_focus):
		vp.gui_focus_changed.connect(_on_focus)
	refresh()
	game.capture_mouse(false)
	var pd := game.session.local_data()
	var target: InventorySlot = hand_buttons[0] if not hand_buttons.is_empty() else null
	if pd:
		var held := clampi(pd.slot, 0, GameWeapon.HANDS - 1)
		if held < pd.weapons.size():
			target = hand_buttons[held]
		for i in mini(pd.bag.size(), bag_buttons.size()):
			if bag_buttons[i].is_new:
				target = bag_buttons[i]
				break
	if target:
		target.grab_focus()
	_left_scroll.scroll_vertical = 0


func close() -> void:
	if not visible:
		return
	_mark_seen()
	visible = false
	selected_hand = -1
	selected_bag = -1
	selected_part = -1
	_recycle_armed = false
	var vp := get_viewport() if is_inside_tree() else null
	if vp and vp.gui_focus_changed.is_connected(_on_focus):
		vp.gui_focus_changed.disconnect(_on_focus)
	var f := vp.gui_get_focus_owner() if vp else null
	if f and is_ancestor_of(f):
		f.release_focus()
	if GameState.is_in_game():
		game.capture_mouse(true)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Armes vues : celles du joueur à la fermeture ne sont plus NEUVES.
func _mark_seen() -> void:
	var pd := game.session.local_data() if game and game.session else null
	if pd == null:
		return
	for w in pd.weapons + pd.bag:
		var uid := String(w.get("uid", ""))
		if uid != "":
			_seen[uid] = true


func _on_focus(_c: Control) -> void:
	if visible:
		refresh()


# --------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------

## Case `i` de la rangée `row` (0 : en main, 1 : sac, 2 : pièces) choisie
## (clic, A, Entrée ; les tests l'appellent directement). Deux cases de
## rangées d'armes différentes : échange demandé au serveur. Une pièce puis
## une arme (ou l'inverse) : montage demandé au serveur.
func press(row: int, i: int) -> void:
	_recycle_armed = false
	# La case choisie prend le focus (comme au clic) : la fiche la montre.
	var list: Array[InventorySlot] = hand_buttons if row == ROW_HANDS else (bag_buttons if row == ROW_BAG else part_buttons)
	if i >= 0 and i < list.size() and list[i].is_inside_tree() and list[i].focus_mode != Control.FOCUS_NONE \
			and not list[i].has_focus():
		list[i].grab_focus()
	if row == ROW_PARTS:
		var my_parts: Array = game.loot.my_parts if game.loot else []
		if i >= my_parts.size():
			return
		selected_part = -1 if selected_part == i else i
		var target := selected_hand if selected_hand >= 0 else selected_bag
		if selected_part >= 0 and target >= 0:
			request_mount(selected_part, ROW_HANDS if selected_hand >= 0 else ROW_BAG, target)
			_clear_selection()
		refresh()
		return
	if selected_part >= 0:
		request_mount(selected_part, row, i)
		_clear_selection()
		refresh()
		return
	# Arme du sac choisie seule, choisie à nouveau : elle s'équipe (place
	# libre en main, sinon à la place de l'arme tenue).
	if row == ROW_BAG and selected_bag == i and selected_hand < 0:
		equip_selected()
		return
	if row == ROW_HANDS:
		selected_hand = -1 if selected_hand == i else i
	else:
		selected_bag = -1 if selected_bag == i else i
	if selected_hand >= 0 and selected_bag >= 0:
		var pd := game.session.local_data()
		if pd and selected_bag < pd.bag.size() and not GameWeapon.can_equip(pd.bag[selected_bag], pd.level):
			_refuse_level(pd.bag[selected_bag])
		request_swap(selected_hand, selected_bag)
		selected_hand = -1
		selected_bag = -1
	refresh()


func request_swap(hand: int, bag: int) -> void:
	if game.combat:
		game.combat.srv_swap.rpc_id(1, hand, bag)


## Case choisie seule ([rangée, place]) ; vide si aucune ou deux.
func selected_slot() -> Array:
	if selected_hand >= 0 and selected_bag < 0:
		return [ROW_HANDS, selected_hand]
	if selected_bag >= 0 and selected_hand < 0:
		return [ROW_BAG, selected_bag]
	return []


## Case montrée par la fiche ([rangée, place], vide : aucune arme) : celle qui
## a le focus si elle porte une arme, sinon la case choisie, sinon l'arme
## tenue.
func inspected_slot() -> Array:
	var pd := game.session.local_data() if game and game.session else null
	if pd == null:
		return []
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f is InventorySlot:
		var hi := hand_buttons.find(f)
		if hi >= 0 and hi < pd.weapons.size():
			return [ROW_HANDS, hi]
		var bi := bag_buttons.find(f)
		if bi >= 0 and bi < pd.bag.size():
			return [ROW_BAG, bi]
	var s := selected_slot()
	if not s.is_empty() and not BuildRules.weapon_at(pd, s[0], s[1]).is_empty():
		return s
	if not pd.weapons.is_empty():
		return [ROW_HANDS, clampi(pd.slot, 0, pd.weapons.size() - 1)]
	if not pd.bag.is_empty():
		return [ROW_BAG, 0]
	return []


## Arme en main comparée à l'arme du sac montrée (place, -1 : aucune) :
## l'arme en main choisie, sinon l'arme tenue.
func compared_hand(insp: Array) -> int:
	var pd := game.session.local_data() if game and game.session else null
	if pd == null or insp.is_empty() or insp[0] != ROW_BAG:
		return -1
	if selected_hand >= 0 and selected_hand < pd.weapons.size():
		return selected_hand
	if pd.slot >= 0 and pd.slot < pd.weapons.size():
		return pd.slot
	return 0 if not pd.weapons.is_empty() else -1


## Emplacement en main où ÉQUIPER met une arme du sac : la première place
## libre, sinon celui de l'arme tenue (échange). Pure (tests).
static func equip_target(pd: PlayerData) -> int:
	if pd.weapons.size() < GameWeapon.HANDS:
		return pd.weapons.size()
	return clampi(pd.slot, 0, GameWeapon.HANDS - 1)


## Pourquoi l'arme du sac choisie seule ne s'équipe pas ("" : elle s'équipe ;
## aucune arme du sac choisie : « none »). Pure (tests).
static func equip_refusal(pd: PlayerData, bag: int) -> String:
	if pd == null or bag < 0 or bag >= pd.bag.size():
		return "none"
	if not GameWeapon.can_equip(pd.bag[bag], pd.level):
		return "level"
	return GameWeapon.swap_refusal(pd, equip_target(pd), bag)


## ÉQUIPER : l'arme du sac choisie seule passe en main (place libre, sinon
## échangée avec l'arme tenue ; Combat.srv_swap, le serveur décide) et
## devient l'arme tenue.
func equip_selected() -> void:
	var pd := game.session.local_data()
	var s := selected_slot()
	if pd == null or s.is_empty() or s[0] != ROW_BAG:
		return
	var why := equip_refusal(pd, s[1])
	if why == "level":
		_refuse_level(pd.bag[s[1]])
		refresh()
		return
	if why != "":
		return
	var target := equip_target(pd)
	_clear_selection()
	_recycle_armed = false
	request_swap(target, s[1])
	if target != pd.slot and game.local_player and game.local_player.weapons:
		game.local_player.weapons.request_switch(target)
	# Le focus suit l'arme équipée (fiche à jour une fois le serveur passé).
	if target < hand_buttons.size():
		hand_buttons[target].grab_focus()
	refresh()


func _refuse_level(w: Dictionary) -> void:
	_show_notice(Lang.t("Niveau %d requis pour cette arme", "Level %d required for this weapon") % GameWeapon.level_of(w))


func _show_notice(t: String) -> void:
	_notice = t
	_notice_t = NOTICE_SEC
	if game.hud:
		game.hud.flash_message(t)


## Recyclage de la case montrée par la fiche : Combat.srv_recycle (le
## serveur décide) ; premier appui, confirmation demandée ; second appui :
## demande envoyée. Dernière arme du joueur : refus immédiat (message), rien
## n'est envoyé.
func recycle_selected() -> void:
	var s := inspected_slot()
	var pd := game.session.local_data()
	if s.is_empty() or pd == null or BuildRules.weapon_at(pd, s[0], s[1]).is_empty():
		return
	var why := BuildRules.recycle_refusal(pd, s[0], s[1])
	if why == BuildRules.LAST_WEAPON:
		_recycle_armed = false
		_show_notice(BuildRules.recycle_refusal_text(BuildRules.LAST_WEAPON))
		refresh()
		return
	if bool(BuildRules.weapon_at(pd, s[0], s[1]).get("loaned", false)):
		return
	if not _recycle_armed or _recycle_slot != s:
		_recycle_armed = true
		_recycle_slot = s
		refresh()
		return
	_recycle_armed = false
	_clear_selection()
	if game.combat:
		game.combat.srv_recycle.rpc_id(1, s[0], s[1])
	refresh()


## PIÈCES (Y, Tab) : le focus passe sur la rangée des pièces, ou en revient.
func toggle_parts_focus() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f is InventorySlot and part_buttons.has(f):
		var pd := game.session.local_data()
		var held := clampi(pd.slot if pd else 0, 0, hand_buttons.size() - 1)
		hand_buttons[held].grab_focus()
	elif not part_buttons.is_empty() and not part_buttons[0].disabled:
		part_buttons[0].grab_focus()


## Montage de la pièce n° `part` (LootSystem.my_parts) sur l'arme `i` de la
## rangée `row` : demandé au serveur.
func request_mount(part: int, row: int, i: int) -> void:
	if game.loot and part < game.loot.my_parts.size():
		game.loot.request_mount(String(game.loot.my_parts[part].get("uid", "")), row, i)


func _clear_selection() -> void:
	selected_hand = -1
	selected_bag = -1
	selected_part = -1


func _on_data_changed(pid: int) -> void:
	if visible and pid == multiplayer.get_unique_id():
		refresh()


func _on_prompt(id: String) -> void:
	match id:
		Hub2Input.ACCEPT:
			var f := get_viewport().gui_get_focus_owner()
			if f is InventorySlot and is_ancestor_of(f):
				(f as InventorySlot).pressed.emit()
		Hub2Input.SECONDARY:
			recycle_selected()
		Hub2Input.FILTER:
			toggle_parts_focus()
		"close":
			close()


func _on_recycle_click(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		recycle_selected()
		accept_event()


## X / Suppr : recycler ; Y / Tab : pièces (la touche d'inventaire, elle,
## est lue par Hud._input).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var jb := event as InputEventJoypadButton
	if (jb and jb.pressed and jb.button_index == JOY_BUTTON_X) or Hub2Input.is_key(event, KEY_DELETE):
		recycle_selected()
		get_viewport().set_input_as_handled()
	elif (jb and jb.pressed and jb.button_index == JOY_BUTTON_Y) or Hub2Input.is_key(event, KEY_TAB):
		toggle_parts_focus()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or _notice == "":
		return
	_notice_t -= delta
	if _notice_t <= 0.0:
		_notice = ""
		refresh()


# --------------------------------------------------------------------------
# Affichage
# --------------------------------------------------------------------------

func refresh() -> void:
	var pd := game.session.local_data()
	var my_parts: Array = game.loot.my_parts if game.loot else []
	var round_n: int = game.rounds.round_n if game.rounds else 0
	_header.set_texts(Lang.t("INVENTAIRE", "INVENTORY"), Hub2Style.num(pd.points if pd else 0), Lang.t("ferraille", "scrap"),
			Lang.t("LA PARTIE CONTINUE · MANCHE %d", "THE MATCH GOES ON · ROUND %d") % maxi(round_n, 1))
	var keys := PackedStringArray()
	for i in GameWeapon.HANDS:
		keys.append(slot_key(i))
	_head_hands.set_texts(Lang.t("EN MAIN", "EQUIPPED"), Lang.t("Touches %s en partie", "Keys %s in a match") % " · ".join(keys))
	_head_bag.set_texts(Lang.t("SAC À DOS", "BACKPACK"),
			Lang.t("Armes ramassées · gardées si tu évacues", "Picked-up weapons · kept if you evacuate"))
	_head_parts.set_texts(Lang.t("PIÈCES TROUVÉES", "PARTS FOUND"),
			Lang.t("Choisis une pièce puis une arme pour la monter", "Pick a part, then a weapon to mount it on"))
	_refresh_parts(my_parts)
	if pd == null:
		return
	var insp := inspected_slot()
	var cmp := compared_hand(insp)
	if not _recycle_slot.is_empty() and _recycle_slot != insp:
		_recycle_armed = false
	for w in pd.weapons:
		var uid := String(w.get("uid", ""))
		if uid != "":
			_seen[uid] = true
	for i in hand_buttons.size():
		var w: Dictionary = pd.weapons[i] if i < pd.weapons.size() else {}
		var b := hand_buttons[i]
		b.key_text = slot_key(i)
		b.key_bright = i == pd.slot and not w.is_empty()
		var lk := InventorySlot.Look.NORMAL
		if i == selected_hand or insp == [ROW_HANDS, i]:
			lk = InventorySlot.Look.ON
		elif i == cmp:
			lk = InventorySlot.Look.COMPARED
		b.show_item(w, lk, false, not w.is_empty() and not GameWeapon.can_equip(w, pd.level))
	for i in bag_buttons.size():
		var w2: Dictionary = pd.bag[i] if i < pd.bag.size() else {}
		var lk2 := InventorySlot.Look.ON if (i == selected_bag or insp == [ROW_BAG, i]) else InventorySlot.Look.NORMAL
		var uid2 := String(w2.get("uid", ""))
		bag_buttons[i].show_item(w2, lk2, uid2 != "" and not _seen.has(uid2),
				not w2.is_empty() and not GameWeapon.can_equip(w2, pd.level))
	_refresh_detail(pd, insp, cmp)
	_refresh_prompts(pd, insp)


## Touche de l'emplacement en main `i` (action weapon_1 à 3, clavier).
static func slot_key(i: int) -> String:
	var code := Settings.binding("weapon_%d" % (i + 1))
	return Settings.code_label(code) if code != "" else str(i + 1)


## Nom affiché d'une arme de partie, en capitales.
static func weapon_title(w: Dictionary) -> String:
	return BuildStation.weapon_name(w).to_upper()


## Rangée des pièces : une case par pièce de la partie (recréées si leur
## nombre change), une case « aucune pièce » sinon.
func _refresh_parts(my_parts: Array) -> void:
	var n := maxi(my_parts.size(), 1)
	if selected_part >= my_parts.size():
		selected_part = -1
	while part_buttons.size() > n:
		var b: InventorySlot = part_buttons.pop_back()
		_parts_row.remove_child(b)
		b.queue_free()
	while part_buttons.size() < n:
		var b := InventorySlot.new()
		b.setup(InventorySlot.Kind.PART)
		b.pressed.connect(press.bind(ROW_PARTS, part_buttons.size()))
		_parts_row.add_child(b)
		part_buttons.append(b)
	for i in part_buttons.size():
		var b := part_buttons[i]
		if i < my_parts.size():
			b.disabled = false
			b.focus_mode = Control.FOCUS_ALL
			b.show_item(part_view(my_parts[i]), InventorySlot.Look.ON if i == selected_part else InventorySlot.Look.NORMAL)
		else:
			b.disabled = true
			b.focus_mode = Control.FOCUS_NONE
			b.show_item({}, InventorySlot.Look.NORMAL)
	_set_neighbors(not my_parts.is_empty())


## Pièce d'une partie (dictionnaire de LootSystem.my_parts / d'une arme) en
## WeaponPart (noms et effets du hub).
static func part_of(p: Dictionary) -> WeaponPart:
	var wp := WeaponPart.create(String(p.get("id", "part")), int(p.get("level", 1)), p.get("mods", {}))
	wp.uid = String(p.get("uid", ""))
	return wp


## Case d'une pièce : {name : « Ressort · niv. 3 », effects : [[texte, bonus]]}.
static func part_view(p: Dictionary) -> Dictionary:
	var wp := part_of(p)
	return {"name": Hub2ArsenalView.part_line_name(wp), "effects": Hub2ArsenalView.effects(wp)}


## Les six statistiques de la fiche de `w` (valeurs effectives : niveau et
## pièces compris) et l'écart à `vs` (arme en main comparée, {} : aucun) :
## « + N » vert si mieux, « − N » rouge sinon (recharge : plus court =
## mieux), sans unité ; mêmes icônes, libellés et formats que l'ARSENAL.
## Pure (tests).
static func compare_lines(w: Dictionary, vs: Dictionary) -> Array:
	var out := []
	if w.is_empty():
		return out
	var id := String(w.get("id", ""))
	var sw: Dictionary = GameWeapon.stats(w) if WeaponDB.exists(id) else {}
	var vid := String(vs.get("id", ""))
	var sv: Dictionary = GameWeapon.stats(vs) if not vs.is_empty() and WeaponDB.exists(vid) else {}
	for key in Hub2ArsenalView.STATS:
		var lbl: Array = Hub2ArsenalView.STAT_LABELS[key]
		var line := {"key": key, "label": Lang.t(lbl[0], lbl[1]), "icon": Hub2ArsenalView.ICONS[key], "value": "—",
			"mod": "", "good": true}
		if Hub2ArsenalView.has_stat(key, id, sw):
			var v := Hub2ArsenalView.stat_number(key, sw)
			line.value = Hub2ArsenalView.format_value(key, v)
			if Hub2ArsenalView.has_stat(key, vid, sv):
				var d := v - Hub2ArsenalView.stat_number(key, sv)
				line.mod = Hub2ArsenalView.format_mod(key, d)
				line.good = Hub2ArsenalView.mod_good(key, d)
		out.append(line)
	return out


func _refresh_detail(pd: PlayerData, insp: Array, cmp: int) -> void:
	var w: Dictionary = BuildRules.weapon_at(pd, insp[0], insp[1]) if not insp.is_empty() else {}
	var vs: Dictionary = pd.weapons[cmp] if cmp >= 0 and cmp < pd.weapons.size() else {}
	if w.is_empty():
		_detail_head.set_data(Hub2Style.text_a(0.3), "", "—", "", Hub2Style.text_a(0.7), [])
		for st in _stats:
			st.line = {}
		_parts_title.text = ""
		_set_part_rows([])
		recycle_label.text = ""
		recycle_value_label.text = ""
		return
	var r := GameWeapon.rarity_of(w)
	var id := String(w.get("id", ""))
	var high := not GameWeapon.can_equip(w, pd.level)
	var compare := []
	if not vs.is_empty():
		compare = [Lang.t("Comparé à ", "Compared to "), weapon_title(vs), Lang.t(" (en main)", " (equipped)")]
	var lvl := Hub2ArsenalView.required_text(GameWeapon.level_of(w)) if high else Hub2ArsenalView.level_text(GameWeapon.level_of(w))
	_detail_head.set_data(Hub2Style.rarity_color(r), "%s · %s" % [GameWeapon.rarity_name(r), Hub2ArsenalView.class_name_of(id)],
			weapon_title(w), lvl, Hub2Style.BAD_ALT if high else Hub2Style.text_a(0.7), compare)
	var lines := compare_lines(w, vs)
	for i in _stats.size():
		_stats[i].line = lines[i] if i < lines.size() else {}
	var ps: Array = w.get("parts", [])
	var n: int = OwnedWeapon.SLOTS[clampi(r, 0, OwnedWeapon.SLOTS.size() - 1)]
	_parts_title.text = Lang.t("PIÈCES · %d / %d", "PARTS · %d / %d") % [mini(ps.size(), n), n]
	var rows := []
	for i in maxi(n, ps.size()):
		if i < ps.size():
			var wp := part_of(ps[i])
			rows.append([Hub2ArsenalView.part_line_name(wp), Hub2ArsenalView.effects(wp), true])
		else:
			rows.append([Lang.t("Emplacement libre", "Empty slot"), [], false])
	_set_part_rows(rows)
	# Recyclage : valeur réelle (BuildRules), deux appuis, jamais la dernière.
	var last: bool = BuildRules.recycle_refusal(pd, insp[0], insp[1]) == BuildRules.LAST_WEAPON
	var loaned := bool(w.get("loaned", false))
	recycle_value_label.text = Lang.t("+%s ferraille", "+%s scrap") % Hub2Style.num(BuildRules.recycle_value(w))
	recycle_label.color = Hub2Style.text_a(0.65)
	recycle_value_label.color = Hub2Style.TEXT
	if last:
		recycle_label.text = BuildRules.recycle_refusal_text(BuildRules.LAST_WEAPON)
		recycle_value_label.text = ""
	elif loaned:
		recycle_label.text = Lang.t("Arme prêtée : pas de recyclage", "Loaned weapon: no recycling")
		recycle_value_label.text = ""
	elif _recycle_armed:
		recycle_label.text = Lang.t("Confirmer le recyclage", "Confirm recycling")
		recycle_label.color = Hub2Style.YELLOW
		recycle_value_label.color = Hub2Style.YELLOW
	else:
		recycle_label.text = Lang.t("Recycler cette arme", "Recycle this weapon")


func _set_part_rows(rows: Array) -> void:
	while _part_rows.get_child_count() > rows.size():
		var c := _part_rows.get_child(_part_rows.get_child_count() - 1)
		_part_rows.remove_child(c)
		c.queue_free()
	while _part_rows.get_child_count() < rows.size():
		_part_rows.add_child(InventoryDraw.PartRow.new())
	for i in rows.size():
		(_part_rows.get_child(i) as InventoryDraw.PartRow).set_data(rows[i][0], rows[i][1], rows[i][2])


## Invites : A ÉQUIPER (arme du sac) / ÉCHANGER (arme en main) / MONTER
## (pièce), X RECYCLER, Y PIÈCES, touche d'inventaire FERMER ; aide à gauche.
func _refresh_prompts(pd: PlayerData, insp: Array) -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var on_part := f is InventorySlot and part_buttons.has(f)
	var in_bag: bool = not insp.is_empty() and insp[0] == ROW_BAG
	var a := Lang.t("Monter", "Mount") if on_part else (Lang.t("Équiper", "Equip") if in_bag else Lang.t("Échanger", "Swap"))
	prompts.set_items([[Hub2Input.ACCEPT, a], [Hub2Input.SECONDARY, Lang.t("Recycler", "Recycle")],
			[Hub2Input.FILTER, Lang.t("Pièces", "Parts")],
			["close", Lang.t("Fermer", "Close"), close_keys(), close_pads()]])
	var w: Dictionary = BuildRules.weapon_at(pd, insp[0], insp[1]) if not insp.is_empty() else {}
	var help := ""
	if _notice != "":
		help = _notice
	elif selected_part >= 0:
		help = Lang.t("Choisis l'arme qui recevra la pièce.", "Pick the weapon that will get the part.")
	elif _recycle_armed and not w.is_empty():
		help = Lang.t("Appuie encore pour recycler %s.", "Press again to recycle %s.") % weapon_title(w)
	elif on_part:
		help = Lang.t("Choisis une pièce puis une arme pour la monter.", "Pick a part, then a weapon to mount it on.")
	elif in_bag and not w.is_empty():
		help = Lang.t("Choisis une arme en main pour l'échanger avec %s.", "Pick an equipped weapon to swap it with %s.") % weapon_title(w)
	else:
		help = Lang.t("Choisis une arme du sac pour l'échanger.", "Pick a backpack weapon to swap it.")
	prompts.help = help


## Touche (clavier) et bouton (manette) de l'action « inventory » réels.
static func close_keys() -> PackedStringArray:
	var code := Settings.binding("inventory")
	return PackedStringArray([Settings.code_label(code) if code != "" else "?"])


static func close_pads() -> Array:
	var ev := Settings.event_from_code(Settings.binding("inventory", true))
	if ev is InputEventJoypadButton:
		return [(ev as InputEventJoypadButton).button_index]
	return []


## Ligne d'information d'une case (infobulle, tests) : niveau, rareté,
## score ; niveau requis si l'arme ne s'équipe pas encore. Pure (tests).
static func slot_info(w: Dictionary, player_level: int) -> String:
	if w.is_empty():
		return ""
	var t := Lang.t("NIV. %d · %s · SCORE %d", "LVL %d · %s · SCORE %d") % [GameWeapon.level_of(w),
		GameWeapon.rarity_name(GameWeapon.rarity_of(w)), GameWeapon.score(w)]
	if not GameWeapon.can_equip(w, player_level):
		t += Lang.t(" · NIVEAU %d REQUIS", " · LEVEL %d REQUIRED") % GameWeapon.level_of(w)
	return t
