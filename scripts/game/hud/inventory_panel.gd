class_name InventoryPanel
extends PanelContainer
## Panneau d'inventaire de partie (GAME_CONCEPT §4.12), ouvert et fermé par
## l'action « inventory » ([I], croix haut à la manette ; Échap / B ferment
## aussi). Trois cases EN MAIN, quatre cases INVENTAIRE : choisir une case
## d'une rangée puis une case de l'autre échange les deux armes
## (Combat.srv_swap, le serveur décide). Chaque case montre le nom, le niveau,
## la rareté (couleur) et le score de l'arme ; une arme de niveau trop élevé
## est marquée et ne s'équipe pas.
##
## La partie continue pendant qu'il est ouvert (même en solo) ; le joueur
## local ne bouge plus et ne tire plus (Game.menu_open), comme avec le menu
## pause en multijoueur. Souris (clic) ou manette / flèches (focus, A ou
## Entrée).

const SLOT_SIZE := Vector2(184, 78)
const SEL_COLOR := Color(1.0, 0.86, 0.32)

var game: Game
var hand_buttons: Array[Button] = []
var bag_buttons: Array[Button] = []
## Case choisie en attente de la seconde (-1 : aucune).
var selected_hand := -1
var selected_bag := -1
var _power: Label
var _hint: Label
var _title_hand: Label
var _title_bag: Label
var _title: Label


func setup(g: Game) -> void:
	game = g
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.015, 0.018, 0.86)
	sb.border_color = Color(0.5, 0.48, 0.44, 0.35)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -400
	offset_right = 400
	offset_top = -170
	offset_bottom = 120
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = HudStyle.label("", 30, HudStyle.TEXT, "title")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_power = HudStyle.label("", 20, HudStyle.TEXT_DIM, "condensed", 2)
	_power.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_power)
	_title_hand = HudStyle.label("", 16, HudStyle.TEXT_DIM, "text", 2)
	box.add_child(_title_hand)
	box.add_child(_make_row(GameWeapon.HANDS, hand_buttons, 0))
	_title_bag = HudStyle.label("", 16, HudStyle.TEXT_DIM, "text", 2)
	box.add_child(_title_bag)
	box.add_child(_make_row(GameWeapon.BAG, bag_buttons, 1))
	_hint = HudStyle.label("", 15, HudStyle.TEXT_DIM, "text", 2)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(760, 0)
	box.add_child(_hint)
	# Voisins de focus entre les deux rangées (manette, flèches).
	for i in hand_buttons.size():
		hand_buttons[i].focus_neighbor_bottom = hand_buttons[i].get_path_to(bag_buttons[mini(i, bag_buttons.size() - 1)])
	for i in bag_buttons.size():
		bag_buttons[i].focus_neighbor_top = bag_buttons[i].get_path_to(hand_buttons[mini(i, hand_buttons.size() - 1)])
	# Créé par Hud._ready, avant Game._ready : `game.session` (@onready) n'est
	# pas encore rempli, le nœud existe déjà.
	var session := g.get_node("Session") as Session
	session.inventory_changed.connect(_on_data_changed)
	session.stats_changed.connect(_on_data_changed)
	visible = false


func _make_row(n: int, into: Array[Button], row: int) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	for i in n:
		var b := Button.new()
		b.custom_minimum_size = SLOT_SIZE
		b.focus_mode = Control.FOCUS_ALL
		b.clip_contents = true
		var v := VBoxContainer.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_top = 6
		v.offset_right = -8
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		var name_l := HudStyle.label("", 21, HudStyle.TEXT, "condensed", 2)
		name_l.name = "Name"
		v.add_child(name_l)
		var info_l := HudStyle.label("", 15, HudStyle.TEXT_DIM, "text", 2)
		info_l.name = "Info"
		v.add_child(info_l)
		b.pressed.connect(press.bind(row, i))
		hb.add_child(b)
		into.append(b)
	return hb


## Ouvre le panneau : souris libérée, focus sur la première case.
func open() -> void:
	selected_hand = -1
	selected_bag = -1
	visible = true
	refresh()
	game.capture_mouse(false)
	if not hand_buttons.is_empty():
		hand_buttons[0].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	selected_hand = -1
	selected_bag = -1
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f and is_ancestor_of(f):
		f.release_focus()
	if GameState.is_in_game():
		game.capture_mouse(true)


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Case `i` de la rangée `row` (0 : en main, 1 : inventaire) choisie (clic,
## A, Entrée ; les tests l'appellent directement). Deux cases de rangées
## différentes : échange demandé au serveur.
func press(row: int, i: int) -> void:
	if row == 0:
		selected_hand = -1 if selected_hand == i else i
	else:
		selected_bag = -1 if selected_bag == i else i
	if selected_hand >= 0 and selected_bag >= 0:
		request_swap(selected_hand, selected_bag)
		selected_hand = -1
		selected_bag = -1
	refresh()


func request_swap(hand: int, bag: int) -> void:
	if game.combat:
		game.combat.srv_swap.rpc_id(1, hand, bag)


func _on_data_changed(pid: int) -> void:
	if visible and pid == multiplayer.get_unique_id():
		refresh()


func refresh() -> void:
	var pd := game.session.local_data()
	_title.text = Lang.t("INVENTAIRE", "INVENTORY")
	_title_hand.text = Lang.t("EN MAIN", "EQUIPPED")
	_title_bag.text = Lang.t("INVENTAIRE (%d PLACES)", "BACKPACK (%d SLOTS)") % GameWeapon.BAG
	_hint.text = Lang.t("Choisissez une arme en main puis une place de l'inventaire pour les échanger. %s : fermer.",
			"Pick an equipped weapon, then a backpack slot, to swap them. %s: close.") % Settings.action_label("inventory")
	if pd == null:
		return
	_power.text = Lang.t("NIVEAU %d   PUISSANCE %d", "LEVEL %d   POWER %d") % [pd.level, pd.power()]
	for i in hand_buttons.size():
		_fill(hand_buttons[i], pd.weapons[i] if i < pd.weapons.size() else {}, pd.level, i == selected_hand, i == pd.slot and i < pd.weapons.size())
	for i in bag_buttons.size():
		_fill(bag_buttons[i], pd.bag[i] if i < pd.bag.size() else {}, pd.level, i == selected_bag, false)


func _fill(b: Button, w: Dictionary, player_level: int, selected: bool, held: bool) -> void:
	var name_l: Label = b.get_child(0).get_child(0)
	var info_l: Label = b.get_child(0).get_child(1)
	var col := HudStyle.TEXT_DIM
	if w.is_empty():
		name_l.text = Lang.t("— vide —", "— empty —")
		info_l.text = ""
		name_l.add_theme_color_override("font_color", HudStyle.TEXT_DIM)
	else:
		col = GameWeapon.rarity_color(GameWeapon.rarity_of(w))
		name_l.text = WeaponDB.localized(GameWeapon.stats(w).name) + ("  ◄" if held else "")
		name_l.add_theme_color_override("font_color", col)
		info_l.text = slot_info(w, player_level)
		info_l.add_theme_color_override("font_color", HudStyle.POINTS_LOSS if not GameWeapon.can_equip(w, player_level) else HudStyle.TEXT_DIM)
	for st in ["normal", "hover", "focus", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.75 if st == "normal" else 0.9)
		sb.border_color = SEL_COLOR if selected else (col if st != "normal" else col.darkened(0.4))
		sb.set_border_width_all(3 if selected or st == "focus" else 1)
		b.add_theme_stylebox_override(st, sb)


## Ligne d'information d'une case : niveau, rareté, score ; niveau requis si
## l'arme ne s'équipe pas encore. Pure (tests).
static func slot_info(w: Dictionary, player_level: int) -> String:
	if w.is_empty():
		return ""
	var t := Lang.t("NIV. %d · %s · SCORE %d", "LVL %d · %s · SCORE %d") % [GameWeapon.level_of(w),
		GameWeapon.rarity_name(GameWeapon.rarity_of(w)), GameWeapon.score(w)]
	if not GameWeapon.can_equip(w, player_level):
		t += Lang.t(" · NIVEAU %d REQUIS", " · LEVEL %d REQUIRED") % GameWeapon.level_of(w)
	return t
