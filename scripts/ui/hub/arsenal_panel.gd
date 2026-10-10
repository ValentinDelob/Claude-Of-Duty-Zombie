class_name HubArsenalPanel
extends HubPanel
## Onglet ARSENAL (docs/HUB_PLAN.md §3.2, maquette écrans 2 et 3) :
##   - à gauche, la LISTE des armes : armes de base en tête (marque BASE),
##     puis l'arsenal groupé par arme, une ligne par version (« └ version 2 »),
##     niveau, rareté en couleur, score, pastille NOUVEAU, « NIV. n REQUIS »
##     (ligne grisée) ; filtres TOUTES / À FEU / CORPS À CORPS / UTILISABLES
##     (Tab / Y, clic) et tri SCORE / NIVEAU / RARETÉ / NOM (R / X, clic) ;
##   - à droite, la FICHE de la version choisie (HubWeaponSheet) ;
##   - INSTALLER : fenêtre des pièces (HubPartPicker) depuis un emplacement
##     libre ; RETIRER (pièce détruite) et RECYCLER (rien rendu) en deux
##     appuis.
## Chaque action modifie le profil en mémoire puis l'enregistre UNE fois
## (hub.save_profile). Les pastilles NOUVEAU vues pendant la visite restent
## affichées jusqu'à la fin de la visite ; elles sont enregistrées « vues » à
## la prochaine écriture, ou en quittant l'onglet.

## Proportions de la maquette (px à 100 %).
const LIST_W := 500.0
const SHEET_W := 732.0
## Couleurs d'une ligne verrouillée (.row.lock).
const LOCK_TEXT := Color("6D6A63")
const LOCK_RARITY := Color("8A6A3A")

var filter := "all"
var sort := "score"
var list_box: HubBox
var filter_bar: HubChip.FilterBar
var list: VBoxContainer
var list_scroll: ScrollContainer
var sheet: HubWeaponSheet
var picker: HubPartPicker
## Lignes choisissables de la liste (HubPickRow, clé = uid de l'exemplaire).
var rows: Array = []
var selected_uid := ""
## Armes NOUVELLES vues pendant cette visite (pastille gardée jusqu'au départ).
var _seen_now: Dictionary = {}
## Marques « vu » pas encore enregistrées.
var _pending_seen := false
## [uid de l'arme, uid de la pièce] : INSTALLER SUR… de l'onglet PIÈCES, fait
## à l'affichage de l'onglet (shown).
var pending_install: Array = []


func build() -> void:
	var root := HubBox.hbox(16)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	list_box = HubBox.new(Lang.t("ARMES", "WEAPONS"), "", false, false)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.size_flags_stretch_ratio = LIST_W
	root.add_child(list_box)
	var names := []
	for f in HubGear.FILTERS:
		var n: Array = HubGear.FILTER_NAMES[f]
		names.append(Lang.t(n[0], n[1]))
	filter_bar = HubChip.FilterBar.new(names)
	filter_bar.chip_clicked.connect(func(i): set_filter(HubGear.FILTERS[i]))
	filter_bar.sort_clicked.connect(cycle_sort)
	list_box.content.add_child(filter_bar)
	list_scroll = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	HubBox.style_scrollbar(list_scroll.get_v_scroll_bar())
	list_box.content.add_child(list_scroll)
	list = HubBox.vbox(0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)
	sheet = HubWeaponSheet.new()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_stretch_ratio = SHEET_W
	sheet.install_requested.connect(open_picker)
	sheet.remove_confirmed.connect(_remove_part)
	sheet.recycle_confirmed.connect(_recycle)
	sheet.armed_changed.connect(func(): hub.refresh_prompts())
	root.add_child(sheet)
	_fill(false)


## Le profil a changé (enregistrement) : liste et fiche relues, même choix,
## focus gardé.
func refresh() -> void:
	_fill(true)


func _fill(keep_focus: bool) -> void:
	var fkey := _focus_key() if keep_focus else ""
	var pr := profile()
	filter_bar.set_state(HubGear.FILTERS.find(filter), _sort_name())
	list_box.set_right(Lang.t("%d armes · %d dans l'arsenal", "%d weapons · %d in the arsenal") % [
		BaseWeapons.ids().size() + pr.weapons.size(), pr.weapons.size()])
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	rows.clear()
	var bases := HubGear.base_rows(pr, filter)
	if not bases.is_empty():
		list.add_child(HubRow.group(Lang.t("ARMES DE BASE", "BASE WEAPONS")))
		for w in bases:
			_add_row(w, false)
	var groups := HubGear.arsenal_groups(pr, filter, sort)
	if not groups.is_empty():
		list.add_child(HubRow.group(Lang.t("ARSENAL", "ARSENAL")))
		for g in groups:
			var vs: Array = g.versions
			for i in vs.size():
				_add_row(vs[i], i > 0)
	if groups.is_empty() and pr.weapons.is_empty() and filter != "melee":
		var tip := HubStyle.label(Lang.t("L'arsenal est vide : les armes gardées sur vous à l'évacuation y arrivent.",
				"The arsenal is empty: weapons you carry when you evacuate end up here."), 13, HubStyle.DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(HubBox.pad(tip, 12, 12, 12, 12))
	for i in rows.size():
		(rows[i] as HubPickRow).alt = i % 2 == 1
	# Choix gardé s'il est encore dans la liste, sinon la première ligne.
	var row := _row_of(selected_uid)
	if row == null and not rows.is_empty():
		row = rows[0]
	_choose(row, false)
	_link_focus()
	if fkey != "":
		_restore_focus(fkey)


func _add_row(w: OwnedWeapon, version_row: bool) -> void:
	var pr := profile()
	var is_base := w.uid.begins_with(BaseWeapons.UID_PREFIX)
	var locked := w.level > pr.level()
	var row := HubPickRow.new()
	row.key = w.uid
	row.locked = locked
	row.hint = _row_hint(w, locked)
	if version_row:
		row.add_theme_constant_override("margin_left", int(HubStyle.px(34)))
	var rc := HubStyle.rarity_color(w.rarity)
	var b := row.box
	if version_row:
		var v := HubGear.version_of(pr, w)
		b.add_child(HubStyle.label(Lang.t("└ version %d", "└ version %d") % v.x, 13, HubStyle.DIM))
		b.add_child(HubStyle.label(HubGear.weapon_name(w.weapon_id), 13, Color(rc, 0.6) if locked else rc))
	else:
		var ic := HubIcon.make(HubGear.weapon_art(w.weapon_id), 2)
		if locked:
			ic.dim = 0.5
		b.add_child(ic)
		var nl := HubStyle.label(HubGear.weapon_name(w.weapon_id), 15, Color(rc, 0.6) if locked else (HubStyle.PAPER if is_base else rc))
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_child(nl)
	if is_base:
		b.add_child(HubTag.make("BASE", HubTag.BASE))
	if not is_base and (pr.is_new_weapon(w.uid) or _seen_now.has(w.uid)):
		b.add_child(HubTag.make(Lang.t("NOUVEAU", "NEW"), HubTag.NEW))
	if locked:
		b.add_child(HubTag.make(Lang.t("NIV. %d REQUIS", "LVL %d REQUIRED") % w.level, HubTag.LOCK))
	b.add_child(HubBox.spring(false))
	b.add_child(HubStyle.label(HubGear.level_text(w.level), 13, LOCK_TEXT if locked else HubStyle.DIM))
	var rl := HubStyle.label(GameWeapon.rarity_name(w.rarity), 13, LOCK_RARITY if locked else rc)
	rl.custom_minimum_size.x = HubStyle.px(72)
	rl.clip_text = true
	b.add_child(rl)
	var sc := HubStyle.label(str(w.score()), 15, LOCK_TEXT if locked else HubStyle.PAPER)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sc.custom_minimum_size.x = HubStyle.px(28)
	sc.name = "Score"
	b.add_child(sc)
	row.chosen.connect(func():
		_choose(row, true)
		hub.set_hint(row.hint))
	row.activated.connect(func():
		var f := sheet.first_control()
		if f:
			f.grab_focus())
	list.add_child(row)
	rows.append(row)


func _row_hint(w: OwnedWeapon, locked: bool) -> String:
	if locked:
		return Lang.t("Niveau %d requis pour l'équiper ou la construire : gardée pour plus tard.",
				"Level %d required to equip or build it: kept for later.") % w.level
	if w.uid.begins_with(BaseWeapons.UID_PREFIX):
		return Lang.t("Arme de base : donnée à tous, ni modifiable ni recyclable.", "Base weapon: given to everyone, can't be modified or recycled.")
	return Lang.t("Entrée : aller à la fiche (pièces, recyclage).", "Enter: go to the sheet (parts, recycling).")


func _row_of(uid: String) -> HubPickRow:
	for r in rows:
		if (r as HubPickRow).key == uid:
			return r
	return null


## Choisit la ligne `row` : sélection gardée, fiche affichée, NOUVEAU vu.
func _choose(row: HubPickRow, from_focus: bool) -> void:
	var pr := profile()
	for r in rows:
		(r as HubPickRow).sticky = r == row
		var sl := (r as HubPickRow).box.get_node_or_null("Score") as Label
		if sl:
			var sel: bool = r == row and not (r as HubPickRow).locked
			sl.add_theme_color_override("font_color", HubStyle.YELLOW if sel else (LOCK_TEXT if (r as HubPickRow).locked else HubStyle.PAPER))
			sl.add_theme_font_override("font", HubStyle.font("bold" if sel else "ui"))
	var uid := row.key if row else ""
	var same := uid == selected_uid and sheet.weapon != null and sheet.weapon.uid == uid
	selected_uid = uid
	var w := pr.get_weapon(uid) if uid != "" else null
	if not same or not from_focus:
		sheet.show_weapon(hub, pr, w, same)
	sheet.set_left(row)
	if w and pr.is_new_weapon(uid):
		_seen_now[uid] = true
		pr.mark_weapon_seen(uid)
		for p in w.parts:
			pr.mark_part_seen(p.uid)
		_pending_seen = true


func _link_focus() -> void:
	for i in rows.size():
		var r: Control = rows[i]
		if i > 0:
			r.focus_neighbor_top = r.get_path_to(rows[i - 1])
		if i < rows.size() - 1:
			r.focus_neighbor_bottom = r.get_path_to(rows[i + 1])
		var f := sheet.first_control()
		if f:
			r.focus_neighbor_right = r.get_path_to(f)


# --------------------------------------------------------------------------
# Filtres et tri
# --------------------------------------------------------------------------

func _sort_name() -> String:
	var n: Array = HubGear.SORT_NAMES[sort]
	return Lang.t(n[0], n[1])


func set_filter(f: String) -> void:
	if not f in HubGear.FILTERS:
		return
	filter = f
	var in_list := _focus_in_list()
	_fill(false)
	if in_list or not _focus_inside():
		var r := _row_of(selected_uid)
		if r:
			r.grab_focus()
	hub.set_hint(Lang.t("Filtre : %s", "Filter: %s") % filter_bar.chips[HubGear.FILTERS.find(f)].text)


func cycle_filter() -> void:
	set_filter(HubGear.FILTERS[(HubGear.FILTERS.find(filter) + 1) % HubGear.FILTERS.size()])


func cycle_sort() -> void:
	sort = HubGear.SORTS[(HubGear.SORTS.find(sort) + 1) % HubGear.SORTS.size()]
	var in_list := _focus_in_list()
	_fill(false)
	if in_list or not _focus_inside():
		var r := _row_of(selected_uid)
		if r:
			r.grab_focus()
	hub.set_hint(Lang.t("Tri : %s", "Sort: %s") % _sort_name())


# --------------------------------------------------------------------------
# Actions (une écriture du profil chacune)
# --------------------------------------------------------------------------

## Ouvre la fenêtre des pièces pour l'emplacement `slot` de l'arme affichée
## (`pre` : pièce choisie d'avance).
func open_picker(slot: int, pre := "") -> void:
	var w := sheet.weapon
	if w == null or w.uid.begins_with(BaseWeapons.UID_PREFIX):
		return
	if w.free_slots() <= 0:
		hub.set_hint(Lang.t("Aucun emplacement libre : retirez d'abord une pièce.", "No free slot: remove a part first."))
		return
	close_picker()
	picker = HubPartPicker.new()
	picker.install_requested.connect(_install)
	picker.closed.connect(close_picker)
	hub.add_child(picker)
	picker.open(hub, profile(), w, mini(slot, w.parts.size()), pre)
	hub.refresh_prompts()


func close_picker() -> void:
	if picker == null:
		return
	var p := picker
	picker = null
	if is_instance_valid(p):
		p.get_parent().remove_child(p)
		p.queue_free()
	hub.refresh_prompts()
	var f := sheet.first_control()
	if visible:
		if sheet.slots.size() > 0:
			var w := sheet.weapon
			var i := mini(w.parts.size(), sheet.slots.size() - 1) if w else 0
			(sheet.slots[i] as Control).grab_focus()
		elif f:
			f.grab_focus()


## INSTALLER SUR… (onglet PIÈCES) : la fiche de l'arme `weapon_uid`, la
## fenêtre ouverte avec la pièce `part_uid` choisie.
func open_install(weapon_uid: String, part_uid: String) -> void:
	if _row_of(weapon_uid) == null:
		filter = "all"
		_fill(false)
	var r := _row_of(weapon_uid)
	if r == null:
		return
	_choose(r, false)
	r.grab_focus()
	var w := profile().get_weapon(weapon_uid)
	open_picker(w.parts.size() if w else 0, part_uid)


## L'onglet s'affiche : INSTALLER SUR… demandé par l'onglet PIÈCES.
func shown() -> void:
	if not pending_install.is_empty():
		var a := pending_install
		pending_install = []
		open_install(String(a[0]), String(a[1]))


func _install(part_uid: String) -> void:
	var pr := profile()
	var w := sheet.weapon
	if w == null:
		return
	var slot := w.parts.size()
	if not pr.mount_part(w.uid, part_uid):
		hub.set_hint(Lang.t("Cette pièce ne se monte pas sur cette arme.", "This part can't be mounted on this weapon."))
		return
	pr.mark_part_seen(part_uid)
	_pending_seen = false
	var p := picker
	picker = null
	if is_instance_valid(p):
		p.get_parent().remove_child(p)
		p.queue_free()
	hub.save_profile()
	hub.refresh_prompts()
	if slot < sheet.slots.size():
		(sheet.slots[slot] as Control).grab_focus()
	hub.set_hint(Lang.t("Pièce installée.", "Part installed."))


func _remove_part(part_uid: String) -> void:
	var w := sheet.weapon
	if w == null or not profile().unmount_part(w.uid, part_uid):
		return
	_pending_seen = false
	Audio.play_ui(MenuStyle.SND_BACK, -4.0)
	hub.save_profile()
	var f: Control = sheet.slots[mini(sheet.target_slot, sheet.slots.size() - 1)] if not sheet.slots.is_empty() else sheet.first_control()
	if f:
		f.grab_focus()
	hub.set_hint(Lang.t("Pièce retirée et détruite.", "Part removed and destroyed."))


func _recycle() -> void:
	var w := sheet.weapon
	var pr := profile()
	if w == null or not pr.is_recyclable(w.uid):
		return
	var i := rows.find(_row_of(w.uid))
	if pr.remove_weapon(w.uid) == null:
		return
	_pending_seen = false
	_seen_now.erase(w.uid)
	Audio.play_ui(MenuStyle.SND_BACK, -4.0)
	# La ligne suivante (ou la précédente) prend la place.
	var next := ""
	if i >= 0:
		for j in [i + 1, i - 1]:
			if j >= 0 and j < rows.size():
				next = (rows[j] as HubPickRow).key
				break
	selected_uid = next
	hub.save_profile()
	var r := _row_of(selected_uid)
	if r:
		r.grab_focus()
	hub.set_hint(Lang.t("Arme recyclée : rien n'est rendu au hub.", "Weapon recycled: nothing is given back at the hub."))


# --------------------------------------------------------------------------
# Contrat des panneaux (HubPanel)
# --------------------------------------------------------------------------

func first_focus() -> Control:
	if picker:
		if not picker.install_button.disabled:
			return picker.install_button
		return picker.rows[picker.selected] if picker.selected >= 0 else picker.cancel_button
	var r := _row_of(selected_uid)
	if r == null and not rows.is_empty():
		r = rows[0]
	return r


func prompts() -> Array:
	if picker:
		return [[HubPrompts.ACCEPT, Lang.t("Installer", "Install")], [HubPrompts.BACK, Lang.t("Annuler", "Cancel")]]
	if sheet and sheet.armed != HubWeaponSheet.NONE:
		return [[HubPrompts.ACCEPT, Lang.t("Confirmer", "Confirm")], [HubPrompts.BACK, Lang.t("Annuler", "Cancel")],
			[HubPrompts.FILTER, Lang.t("Filtre", "Filter")], [HubPrompts.SORT, Lang.t("Tri", "Sort")]]
	return [[HubPrompts.ACCEPT, Lang.t("Choisir", "Select")], [HubPrompts.FILTER, Lang.t("Filtre", "Filter")],
		[HubPrompts.SORT, Lang.t("Tri", "Sort")], [HubPrompts.TABS, Lang.t("Onglets", "Tabs")],
		[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]


func back() -> bool:
	if picker:
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		close_picker()
		return true
	if sheet.cancel_armed():
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		hub.set_hint("")
		return true
	if _focus_inside() and not _focus_in_list():
		var r := _row_of(selected_uid)
		if r:
			Audio.play_ui(MenuStyle.SND_BACK, -4.0)
			r.grab_focus()
			return true
	return false


func handle_input(event: InputEvent) -> bool:
	if picker:
		return false
	if _pressed_key(event, KEY_R) or _pressed_pad(event, JOY_BUTTON_X):
		cycle_sort()
		return true
	if _pressed_pad(event, JOY_BUTTON_Y):
		cycle_filter()
		return true
	if _pressed_key(event, KEY_DELETE):
		var f := get_viewport().gui_get_focus_owner()
		if f is HubSlot and not (f as HubSlot).empty:
			sheet.target_slot = (f as HubSlot).index
			sheet.arm(HubWeaponSheet.REMOVE)
		elif sheet.recycle_button and not sheet.recycle_button.disabled:
			sheet.arm(HubWeaponSheet.RECYCLE)
		return true
	return false


## Tab : filtre suivant (Tab ferait sinon passer le focus au contrôle suivant).
func _input(event: InputEvent) -> void:
	if not visible or picker or hub == null or not hub._active() or hub.hub_menu.is_open():
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_TAB and not k.ctrl_pressed and not k.alt_pressed:
		get_viewport().set_input_as_handled()
		cycle_filter()


func on_prompt(id: String) -> void:
	match id:
		HubPrompts.FILTER:
			cycle_filter()
		HubPrompts.SORT:
			cycle_sort()


func hidden() -> void:
	close_picker()
	if sheet:
		sheet.cancel_armed()
	_seen_now.clear()
	if _pending_seen:
		_pending_seen = false
		hub.save_profile()


static func _pressed_key(event: InputEvent, physical: Key) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.physical_keycode == physical and not k.ctrl_pressed and not k.alt_pressed


static func _pressed_pad(event: InputEvent, button: JoyButton) -> bool:
	var b := event as InputEventJoypadButton
	return b != null and b.pressed and b.button_index == button


# --------------------------------------------------------------------------
# Focus
# --------------------------------------------------------------------------

func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner() if get_viewport() else null


func _focus_inside() -> bool:
	var f := _focus_owner()
	return f != null and is_ancestor_of(f)


func _focus_in_list() -> bool:
	var f := _focus_owner()
	return f != null and list.is_ancestor_of(f)


## Clé de l'élément qui a le focus (pour le retrouver après reconstruction).
func _focus_key() -> String:
	var f := _focus_owner()
	if f == null or not is_ancestor_of(f):
		return ""
	if f is HubPickRow:
		return "row:" + (f as HubPickRow).key
	if f is HubSlot:
		return "slot:%d" % (f as HubSlot).index
	if f == sheet.install_button:
		return "install"
	if f == sheet.remove_button:
		return "remove"
	if f == sheet.recycle_button:
		return "recycle"
	return "row:" + selected_uid


func _restore_focus(fkey: String) -> void:
	var c: Control = null
	if fkey.begins_with("row:"):
		c = _row_of(fkey.substr(4))
	elif fkey.begins_with("slot:"):
		var i := fkey.substr(5).to_int()
		if not sheet.slots.is_empty():
			c = sheet.slots[mini(i, sheet.slots.size() - 1)]
	elif fkey == "install":
		c = sheet.install_button
	elif fkey == "remove":
		c = sheet.remove_button if sheet.remove_button else sheet.install_button
	elif fkey == "recycle":
		c = sheet.recycle_button
	if c == null or (c is BaseButton and (c as BaseButton).disabled):
		c = first_focus()
	if c:
		c.grab_focus()
