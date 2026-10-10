class_name StationPanel
extends PanelContainer
## Interface de la station de construction (GAME_CONCEPT §4.11, §4.12 ;
## BuildStation, BuildRules), ouverte par [F] / X à la station, fermée par
## Échap / B. La partie continue pendant qu'elle est ouverte (même en solo) ;
## le joueur local ne bouge plus et ne tire plus (Game.menu_open).
##
## * ARSENAL : armes de base puis armes de l'arsenal du profil LOCAL
##   (BuildRules.catalog), avec nom, niveau, rareté (couleur), score, prix en
##   ferraille et durée ; « NIVEAU n REQUIS » quand le joueur n'a pas le
##   niveau (non constructible). Une seule construction à la fois : les
##   lignes sont grisées tant qu'une construction est en cours ou à récupérer.
## * Recharge des munitions de l'arme en main (prix selon l'arme).
## * Recyclage des armes portées (en main et inventaire) : deux appuis
##   (le premier demande confirmation).
## Le serveur décide de tout (BuildStation.srv_build / srv_refill,
## Combat.srv_recycle). Souris (clic) ou manette / flèches (focus, A ou Entrée).

const ROW_SIZE := Vector2(840, 58)
const RECYCLE_SIZE := Vector2(205, 52)

var game: Game
var station: BuildStation
## Armes affichées (BuildRules.catalog, profil lu à l'ouverture) et leurs lignes.
var entries: Array[OwnedWeapon] = []
var rows: Array[Button] = []
var refill_button: Button
## Boutons de recyclage : [rangée, place] de chaque bouton (même ordre).
var recycle_buttons: Array[Button] = []
var recycle_slots: Array = []
## Recyclage en attente de confirmation ([rangée, place], vide : aucun).
var _confirm: Array = []
var _title: Label
var _scrap: Label
var _status: Label
var _list: VBoxContainer
var _arsenal_title: Label
var _tools_title: Label
var _recycle_box: GridContainer
var _hint: Label
var _level := 1


func setup(g: Game) -> void:
	game = g
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.015, 0.015, 0.018, 0.88)
	sb.border_color = Color(0.5, 0.48, 0.44, 0.35)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -450
	offset_right = 450
	offset_top = -300
	offset_bottom = 300
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = HudStyle.label("", 30, HudStyle.TEXT, "title")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_scrap = HudStyle.label("", 20, HudStyle.POINTS_GAIN, "condensed", 2)
	_scrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_scrap)
	_status = HudStyle.label("", 17, HudStyle.TEXT, "text", 2)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(860, 0)
	box.add_child(_status)
	_arsenal_title = HudStyle.label("", 16, HudStyle.TEXT_DIM, "text", 2)
	box.add_child(_arsenal_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_tools_title = HudStyle.label("", 16, HudStyle.TEXT_DIM, "text", 2)
	box.add_child(_tools_title)
	refill_button = _button(Vector2(860, 42))
	refill_button.pressed.connect(press_refill)
	box.add_child(refill_button)
	_recycle_box = GridContainer.new()
	_recycle_box.columns = 4
	_recycle_box.add_theme_constant_override("h_separation", 8)
	_recycle_box.add_theme_constant_override("v_separation", 6)
	box.add_child(_recycle_box)
	for row in 2:
		for i in (GameWeapon.HANDS if row == 0 else GameWeapon.BAG):
			var b := _button(RECYCLE_SIZE)
			b.pressed.connect(press_recycle.bind(recycle_buttons.size()))
			_recycle_box.add_child(b)
			recycle_buttons.append(b)
			recycle_slots.append([row, i])
	_hint = HudStyle.label("", 15, HudStyle.TEXT_DIM, "text", 2)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(860, 0)
	box.add_child(_hint)
	# Créé par Hud._ready, avant Game._ready (voir InventoryPanel.setup).
	var session := g.get_node("Session") as Session
	session.inventory_changed.connect(_on_data_changed)
	session.stats_changed.connect(_on_data_changed)
	visible = false


func _button(size: Vector2) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	b.add_theme_font_override("font", HudStyle.font("condensed"))
	b.add_theme_font_size_override("font_size", 17)
	return b


## Ouvre l'interface de la station `st` : arsenal du profil local relu, souris
## libérée, focus sur la première arme.
func open(st: BuildStation) -> void:
	if st != station:
		if station and station.builds_changed.is_connected(refresh):
			station.builds_changed.disconnect(refresh)
		station = st
		if station:
			station.builds_changed.connect(refresh)
	_confirm = []
	entries = BuildRules.catalog(ProfileStore.load_profile())
	_build_rows()
	visible = true
	refresh()
	game.capture_mouse(false)
	var first: Button = rows[0] if not rows.is_empty() else refill_button
	first.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_confirm = []
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f and is_ancestor_of(f):
		f.release_focus()
	if GameState.is_in_game():
		game.capture_mouse(true)


func _build_rows() -> void:
	for b in rows:
		b.queue_free()
	rows.clear()
	for i in entries.size():
		var b := Button.new()
		b.custom_minimum_size = ROW_SIZE
		b.focus_mode = Control.FOCUS_ALL
		b.clip_contents = true
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 12
		hb.offset_right = -12
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(v)
		var name_l := HudStyle.label("", 21, HudStyle.TEXT, "condensed", 2)
		name_l.name = "Name"
		v.add_child(name_l)
		var info_l := HudStyle.label("", 15, HudStyle.TEXT_DIM, "text", 2)
		info_l.name = "Info"
		v.add_child(info_l)
		var price_l := HudStyle.label("", 19, HudStyle.POINTS_GAIN, "condensed", 2)
		price_l.name = "Price"
		price_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(price_l)
		b.pressed.connect(press_build.bind(i))
		_list.add_child(b)
		rows.append(b)


# --------------------------------------------------------------------------
# Actions (clic, A, Entrée ; les tests les appellent directement)
# --------------------------------------------------------------------------

## Construire l'arme `i` de la liste.
func press_build(i: int) -> void:
	if station == null or i < 0 or i >= entries.size() or not can_build(i):
		return
	_confirm = []
	station.request_build(entries[i])


func press_refill() -> void:
	if station:
		_confirm = []
		station.request_refill()


## Recycler l'arme du bouton `k` : premier appui, confirmation demandée ;
## second appui sur le même bouton : demande au serveur.
func press_recycle(k: int) -> void:
	if k < 0 or k >= recycle_slots.size():
		return
	var slot: Array = recycle_slots[k]
	var pd := game.session.local_data()
	if pd == null or BuildRules.weapon_at(pd, slot[0], slot[1]).is_empty():
		return
	if _confirm != slot:
		_confirm = slot
		refresh()
		return
	_confirm = []
	game.combat.srv_recycle.rpc_id(1, slot[0], slot[1])


## Ligne `i` constructible par le joueur local (niveau, une construction à la
## fois) ? La ferraille est vérifiée par le serveur.
func can_build(i: int) -> bool:
	return i >= 0 and i < entries.size() and entries[i].level <= _level and (station == null or station.local_build().is_empty())


# --------------------------------------------------------------------------
# Affichage
# --------------------------------------------------------------------------

func _on_data_changed(pid: int) -> void:
	if visible and pid == multiplayer.get_unique_id():
		refresh()


func refresh() -> void:
	if not visible:
		return
	var pd := game.session.local_data()
	_level = pd.level if pd else 1
	var scrap := pd.points if pd else 0
	_title.text = Lang.t("STATION DE CONSTRUCTION", "CONSTRUCTION STATION")
	_scrap.text = Lang.t("FERRAILLE %d", "SCRAP %d") % scrap
	_status.text = status_text()
	_arsenal_title.text = Lang.t("ARSENAL (%d ARMES)", "ARSENAL (%d WEAPONS)") % entries.size()
	_tools_title.text = Lang.t("MUNITIONS ET RECYCLAGE", "AMMO AND RECYCLING")
	_hint.text = Lang.t("La partie continue. Une construction à la fois, prête en 1 à 3 manches ; récupérez-la ici ([F]) avec une place libre dans l'inventaire. %s : fermer.",
			"The game goes on. One build at a time, ready in 1 to 3 rounds; collect it here ([F]) with a free backpack slot. %s: close.") % Settings.action_label("pause")
	for i in rows.size():
		_fill_row(rows[i], entries[i], scrap, can_build(i))
	# Recharge de l'arme en main.
	var held: Dictionary = pd.current_weapon() if pd else {}
	if held.is_empty():
		refill_button.text = Lang.t("RECHARGER LES MUNITIONS : aucune arme en main", "REFILL AMMO: no weapon in hand")
		refill_button.disabled = true
	else:
		var full := BuildRules.ammo_full(held)
		refill_button.text = (Lang.t("RECHARGER LES MUNITIONS : %s — %d ferraille", "REFILL AMMO: %s — %d scrap") % [BuildStation.weapon_name(held), BuildRules.refill_price(held)]) \
				+ (Lang.t(" (déjà pleines)", " (already full)") if full else "")
		refill_button.disabled = full
	# Recyclage des armes portées.
	for k in recycle_buttons.size():
		var slot: Array = recycle_slots[k]
		var w: Dictionary = BuildRules.weapon_at(pd, slot[0], slot[1]) if pd else {}
		var b := recycle_buttons[k]
		b.visible = not w.is_empty()
		if w.is_empty():
			continue
		var v := BuildRules.recycle_value(w)
		if _confirm == slot:
			b.text = Lang.t("CONFIRMER : +%d", "CONFIRM: +%d") % v
		else:
			b.text = Lang.t("Recycler %s +%d", "Recycle %s +%d") % [BuildStation.weapon_name(w), v]
		b.add_theme_color_override("font_color", GameWeapon.rarity_color(GameWeapon.rarity_of(w)))
		b.disabled = bool(w.get("loaned", false))


## Ligne d'état de la construction du joueur local. Pure vis-à-vis de
## l'affichage (tests).
func status_text() -> String:
	var b: Dictionary = station.local_build() if station else {}
	if b.is_empty():
		return Lang.t("Aucune construction en cours : choisissez une arme de votre arsenal.", "No build in progress: pick a weapon from your arsenal.")
	var nm := BuildStation.weapon_name(b.w)
	if bool(b.ready):
		return Lang.t("PRÊTE : %s — appuyez sur [F] à la station pour la récupérer.", "READY: %s — press [F] at the station to collect it.") % nm
	return Lang.t("En construction : %s — prête à la fin de la manche %d.", "Building: %s — ready at the end of round %d.") % [nm, int(b["round"])]


func _fill_row(b: Button, o: OwnedWeapon, scrap: int, buildable: bool) -> void:
	var w := GameWeapon.from_owned(o)
	var hb := b.get_child(0)
	var name_l: Label = hb.get_child(0).get_child(0)
	var info_l: Label = hb.get_child(0).get_child(1)
	var price_l: Label = hb.get_child(1)
	var col := GameWeapon.rarity_color(o.rarity)
	name_l.text = BuildStation.weapon_name(w) + (Lang.t("  (arme de base)", "  (base weapon)") if BuildRules.is_base_copy(w) else "")
	name_l.add_theme_color_override("font_color", col if buildable else col.darkened(0.45))
	info_l.text = row_info(o, _level)
	info_l.add_theme_color_override("font_color", HudStyle.POINTS_LOSS if o.level > _level else HudStyle.TEXT_DIM)
	var cost := BuildRules.owned_price(o)
	price_l.text = Lang.t("%d FERRAILLE\n%s", "%d SCRAP\n%s") % [cost, BuildRules.rounds_text(BuildRules.rounds(cost))]
	price_l.add_theme_color_override("font_color", HudStyle.POINTS_GAIN if scrap >= cost else HudStyle.POINTS_LOSS)
	b.disabled = not buildable
	for st in ["normal", "hover", "focus", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.5 if st == "disabled" else (0.75 if st == "normal" else 0.9))
		sb.border_color = col if st in ["hover", "focus", "pressed"] else col.darkened(0.5)
		sb.set_border_width_all(3 if st == "focus" else 1)
		b.add_theme_stylebox_override(st, sb)


## Ligne d'information d'une arme de la liste : niveau, rareté, score ;
## « NIVEAU n REQUIS » si le joueur n'a pas le niveau. Pure (tests).
static func row_info(o: OwnedWeapon, player_level: int) -> String:
	var t := Lang.t("NIV. %d · %s · SCORE %d", "LVL %d · %s · SCORE %d") % [o.level, GameWeapon.rarity_name(o.rarity), o.score()]
	if o.level > player_level:
		t += Lang.t(" · NIVEAU %d REQUIS", " · LEVEL %d REQUIRED") % o.level
	return t
