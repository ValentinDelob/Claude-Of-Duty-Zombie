class_name HubPartsPanel
extends HubPanel
## Onglet PIÈCES (docs/HUB_PLAN.md §3.3, maquette écran 4) :
##   - à gauche, PIÈCES EN STOCK : toutes les pièces non installées (onglet
##     illimité), nom d'après le premier modificateur, niveau, modificateurs
##     (bonus en vert, malus en rouge), pastille NOUVEAU ; filtres TOUTES /
##     MONTABLES (Tab / Y, clic), tri NIVEAU / MODIFICATEUR (R / X, clic) ;
##   - à droite, la fiche de la pièce : niveau, modificateurs en clair, ARMES
##     COMPATIBLES (emplacement libre, niveau suffisant) avec l'effet sur la
##     statistique touchée, puis NON COMPATIBLES avec la raison ; INSTALLER
##     SUR… ouvre l'onglet ARSENAL sur cette arme, fenêtre des pièces ouverte,
##     la pièce déjà choisie (HubArsenalPanel.open_install).
## Pas de vente ni de destruction d'une pièce en stock (§3.3).

const LIST_W := 560.0
const SHEET_W := 672.0

var filter := "all"
var sort := "level"
var list_box: HubBox
var filter_bar: HubChip.FilterBar
var list: VBoxContainer
var sheet: HubBox
## Lignes des pièces (HubPickRow, clé = uid de la pièce).
var rows: Array = []
## Lignes des armes compatibles (HubPickRow, clé = uid de l'arme).
var weapon_rows: Array = []
var install_button: HubButton
var selected_uid := ""
var weapon_uid := ""
var title_label: Label
var _seen_now: Dictionary = {}
var _pending_seen := false


func build() -> void:
	var root := HubBox.hbox(16)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	list_box = HubBox.new(Lang.t("PIÈCES EN STOCK", "PARTS IN STOCK"), "", false, false)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.size_flags_stretch_ratio = LIST_W
	root.add_child(list_box)
	var names := []
	for f in HubGear.PART_FILTERS:
		var n: Array = HubGear.PART_FILTER_NAMES[f]
		names.append(Lang.t(n[0], n[1]))
	filter_bar = HubChip.FilterBar.new(names)
	filter_bar.chip_clicked.connect(func(i): set_filter(HubGear.PART_FILTERS[i]))
	filter_bar.sort_clicked.connect(cycle_sort)
	list_box.content.add_child(filter_bar)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	HubBox.style_scrollbar(sc.get_v_scroll_bar())
	list_box.content.add_child(sc)
	list = HubBox.vbox(0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	sheet = HubBox.new("", "", false, true)
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_stretch_ratio = SHEET_W
	root.add_child(sheet)
	_fill(false)


func refresh() -> void:
	_fill(true)


func _fill(keep_focus: bool) -> void:
	var f := _focus_owner()
	var fkey := ""
	if keep_focus and f and is_ancestor_of(f):
		fkey = ("part:" if list.is_ancestor_of(f) else "other:") + ((f as HubPickRow).key if f is HubPickRow else "")
	var pr := profile()
	filter_bar.set_state(HubGear.PART_FILTERS.find(filter), _sort_name())
	list_box.set_right(Lang.t("%d · illimité", "%d · unlimited") % pr.parts.size())
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	rows.clear()
	var ps: Array[WeaponPart] = []
	for p in pr.parts:
		if filter != "mountable" or HubGear.mountable_anywhere(pr, p):
			ps.append(p)
	ps.sort_custom(func(a, b): return HubGear.part_before(a, b, sort))
	for i in ps.size():
		_add_row(ps[i], i)
	if ps.is_empty():
		var tip := HubStyle.label(Lang.t("Aucune pièce en stock. Pièces trouvées en partie : 5 % par zombie de vague spéciale."
				if pr.parts.is_empty() else "Aucune pièce montable sur une arme de l'arsenal.",
				"No part in stock. Parts are found during matches: 5% per special-wave zombie."
				if pr.parts.is_empty() else "No part can be mounted on an arsenal weapon."), 13, HubStyle.DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(HubBox.pad(tip, 12, 12, 12, 12))
	var row := _row_of(selected_uid)
	if row == null and not rows.is_empty():
		row = rows[0]
	_choose(row)
	if fkey.begins_with("part:"):
		var r := _row_of(fkey.substr(5))
		if r == null:
			r = first_focus() as HubPickRow
		if r:
			r.grab_focus()
	elif fkey != "":
		var c := first_focus()
		if c:
			c.grab_focus()


func _add_row(p: WeaponPart, i: int) -> void:
	var pr := profile()
	var row := HubPickRow.new()
	row.key = p.uid
	row.alt = i % 2 == 1
	row.hint = Lang.t("Pièces trouvées en partie : 5 % par zombie de vague spéciale.",
			"Parts are found during matches: 5% per special-wave zombie.")
	var b := row.box
	b.add_child(HubIcon.make("part", 3))
	b.add_child(HubStyle.label(HubGear.part_name(p), 15, HubStyle.PAPER, "bold"))
	if pr.is_new_part(p.uid) or _seen_now.has(p.uid):
		b.add_child(HubTag.make(Lang.t("NOUVEAU", "NEW"), HubTag.NEW))
	b.add_child(HubStyle.label(HubGear.level_text(p.level), 13, HubStyle.DIM))
	b.add_child(HubBox.spring(false))
	b.add_child(HubWeaponSheet.mods_row(p.mods, 13, p.mods.size() > 1))
	row.chosen.connect(func():
		_choose(row, false)
		hub.set_hint(row.hint))
	row.activated.connect(func():
		var c: Control = weapon_rows[0] if not weapon_rows.is_empty() else null
		if c:
			c.grab_focus()
		elif install_button and not install_button.disabled:
			install_button.grab_focus())
	list.add_child(row)
	rows.append(row)


func _row_of(uid: String) -> HubPickRow:
	for r in rows:
		if (r as HubPickRow).key == uid:
			return r
	return null


## Choisit la pièce de la ligne `row` ; la fiche est reconstruite si la pièce
## change ou si `force` (liste relue).
func _choose(row: HubPickRow, force := true) -> void:
	for r in rows:
		(r as HubPickRow).sticky = r == row
	var uid := row.key if row else ""
	if force or uid != selected_uid:
		selected_uid = uid
		_show_part(profile().get_part(uid))
	var pr := profile()
	if uid != "" and pr.is_new_part(uid):
		_seen_now[uid] = true
		pr.mark_part_seen(uid)
		_pending_seen = true
	for r in rows:
		if weapon_rows.size() > 0:
			(r as Control).focus_neighbor_right = (r as Control).get_path_to(weapon_rows[0])
		elif install_button:
			(r as Control).focus_neighbor_right = (r as Control).get_path_to(install_button)


# --------------------------------------------------------------------------
# Fiche de la pièce
# --------------------------------------------------------------------------

func _show_part(p: WeaponPart) -> void:
	var v := sheet.content
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	weapon_rows.clear()
	install_button = null
	title_label = null
	if p == null:
		var l := HubStyle.label(Lang.t("Aucune pièce choisie.", "No part selected."), 15, HubStyle.DIM)
		v.add_child(HubBox.pad(l, 16, 16, 16, 16))
		return
	var pr := profile()
	# En-tête : illustration, nom, niveau, modificateurs en clair.
	var head := HubWeaponSheet.SheetHead.new()
	head.tint = Color(0, 0, 0, 0)
	var hr := HubBox.hbox(16)
	head.add_child(HubBox.pad(hr, 16, 14, 16, 14))
	var art := HubWeaponSheet.IconWell.new()
	art.custom_minimum_size = HubStyle.pxv(84, 84)
	art.add_child(HubIcon.make("part", 8))
	hr.add_child(art)
	var col := HubBox.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(col)
	title_label = HubStyle.label(HubGear.part_name(p).to_upper(), 28, HubStyle.PAPER, "impact", true)
	col.add_child(title_label)
	col.add_child(HubStyle.label(Lang.t("Pièce niveau %d · se monte sur une arme de niveau %d ou plus",
			"Level %d part · fits a weapon of level %d or more") % [p.level, p.level], 13, HubStyle.DIM))
	col.add_child(HubBox.gap(0, 4))
	for k in p.mods:
		var val := float(p.mods[k])
		col.add_child(HubStyle.label(HubGear.mod_long(String(k), val), 16, HubStyle.OK if val >= 0.0 else HubStyle.BAD, "semi"))
	v.add_child(head)
	# Armes compatibles, puis les autres avec la raison.
	var ok: Array[OwnedWeapon] = []
	var ko: Array = []  # [OwnedWeapon, raison]
	for g in HubGear.arsenal_groups(pr, "all", "score"):
		for w in g.versions:
			var why := HubGear.mount_refusal(w, p, pr.level())
			if why == "":
				ok.append(w)
			else:
				ko.append([w, why])
	for w in BaseWeapons.all():
		ko.append([w, HubGear.mount_refusal(w, p, pr.level())])
	v.add_child(HubRow.group(Lang.t("ARMES COMPATIBLES (EMPLACEMENT LIBRE)", "COMPATIBLE WEAPONS (FREE SLOT)")))
	for i in ok.size():
		_weapon_row(v, p, ok[i], i)
	if ok.is_empty():
		var none := HubStyle.label(Lang.t("Aucune arme de l'arsenal ne peut la recevoir pour l'instant.",
				"No arsenal weapon can take it for now."), 13, HubStyle.DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(HubBox.pad(none, 12, 10, 12, 10))
	v.add_child(HubRow.group(Lang.t("NON COMPATIBLES", "NOT COMPATIBLE")))
	for i in ko.size():
		_locked_row(v, ko[i][0], String(ko[i][1]), i)
	v.add_child(HubBox.spring())
	var btns := HubBox.hbox(10)
	v.add_child(HubBox.pad(btns, 12, 12, 12, 12))
	install_button = hub_button("", _install, HubButton.PRIMARY)
	btns.add_child(install_button)
	var first: String = (weapon_rows[0] as HubPickRow).key if not weapon_rows.is_empty() else ""
	var keep := false
	for r in weapon_rows:
		keep = keep or (r as HubPickRow).key == weapon_uid
	_choose_weapon(weapon_uid if keep else first)
	# Voisins : armes compatibles en colonne, le bouton dessous.
	for i in weapon_rows.size():
		var r: Control = weapon_rows[i]
		if i > 0:
			r.focus_neighbor_top = r.get_path_to(weapon_rows[i - 1])
		r.focus_neighbor_bottom = r.get_path_to(weapon_rows[i + 1] if i < weapon_rows.size() - 1 else install_button)
		var sel := _row_of(selected_uid)
		if sel:
			r.focus_neighbor_left = r.get_path_to(sel)
	if not weapon_rows.is_empty():
		install_button.focus_neighbor_top = install_button.get_path_to(weapon_rows[weapon_rows.size() - 1])
	var sel_row := _row_of(selected_uid)
	if sel_row:
		install_button.focus_neighbor_left = install_button.get_path_to(sel_row)


func _weapon_row(v: VBoxContainer, p: WeaponPart, w: OwnedWeapon, i: int) -> void:
	var pr := profile()
	var row := HubPickRow.new()
	row.key = w.uid
	row.alt = i % 2 == 1
	var b := row.box
	b.add_child(HubIcon.make(HubGear.weapon_art(w.weapon_id), 2))
	b.add_child(HubStyle.label(HubGear.weapon_name(w.weapon_id), 15, HubStyle.rarity_color(w.rarity)))
	var ver := HubGear.version_of(pr, w)
	var info := (Lang.t("version %d · ", "version %d · ") % ver.x if ver.x > 1 else "") + HubGear.level_text(w.level) + " · " \
			+ (Lang.t("%d libre", "%d free") if w.free_slots() == 1 else Lang.t("%d libres", "%d free")) % w.free_slots()
	b.add_child(HubStyle.label(info, 13, HubStyle.DIM))
	b.add_child(HubBox.spring(false))
	var pv := HubGear.part_preview(w, p)
	if not pv.is_empty():
		var l: Dictionary = pv[0]
		var t := ("%s : " % l.label if i == 0 else "") if not Lang.is_en() else ("%s: " % l.label if i == 0 else "")
		b.add_child(HubStyle.label("%s%s → " % [t, l.before], 13, HubStyle.PAPER))
		b.add_child(HubStyle.label(String(l.after), 13, HubStyle.OK if l.good else HubStyle.BAD, "bold"))
	row.hint = Lang.t("Entrée : installer sur cette arme (onglet ARSENAL).", "Enter: install on this weapon (ARSENAL tab).")
	row.chosen.connect(func():
		_choose_weapon(w.uid)
		hub.set_hint(row.hint))
	row.activated.connect(func():
		_choose_weapon(w.uid)
		_install())
	v.add_child(row)
	weapon_rows.append(row)


func _locked_row(v: VBoxContainer, w: OwnedWeapon, why: String, i: int) -> void:
	var row := HubRow.new()
	row.alt = i % 2 == 1
	var ic := HubIcon.make(HubGear.weapon_art(w.weapon_id), 2)
	ic.dim = 0.5
	row.box.add_child(ic)
	row.box.add_child(HubStyle.label(HubGear.weapon_name(w.weapon_id), 15, HubArsenalPanel.LOCK_TEXT))
	row.box.add_child(HubBox.spring(false))
	row.box.add_child(HubStyle.label(why.to_lower(), 13, HubArsenalPanel.LOCK_TEXT))
	v.add_child(row)


func _choose_weapon(uid: String) -> void:
	weapon_uid = uid
	for r in weapon_rows:
		(r as HubPickRow).sticky = (r as HubPickRow).key == uid
	if install_button == null:
		return
	var w := profile().get_weapon(uid) if uid != "" else null
	if w == null:
		install_button.label = Lang.t("AUCUNE ARME COMPATIBLE", "NO COMPATIBLE WEAPON")
		install_button.disabled = true
		install_button.hint = ""
	else:
		install_button.label = Lang.t("INSTALLER SUR %s", "INSTALL ON %s") % HubGear.weapon_name(w.weapon_id)
		install_button.disabled = false
		install_button.hint = Lang.t("Ouvre la fiche de l'arme, la pièce déjà choisie.", "Opens the weapon's sheet with the part already picked.")


## INSTALLER SUR… : onglet ARSENAL, fenêtre des pièces ouverte.
func _install() -> void:
	if weapon_uid == "" or selected_uid == "":
		return
	var ars: HubPanel = hub.panels.get("arsenal") if "panels" in hub else null
	if ars == null or not ars.has_method("open_install"):
		return
	var w := weapon_uid
	var p := selected_uid
	# Ouverte à l'affichage de l'onglet (HubArsenalPanel.shown), avant le
	# focus initial de l'onglet.
	ars.set("pending_install", [w, p])
	hub.select_tab("arsenal")


# --------------------------------------------------------------------------
# Filtres et tri
# --------------------------------------------------------------------------

func _sort_name() -> String:
	var n: Array = HubGear.PART_SORT_NAMES[sort]
	return Lang.t(n[0], n[1])


func set_filter(f: String) -> void:
	if not f in HubGear.PART_FILTERS:
		return
	filter = f
	_refocus_after(func(): _fill(false))
	hub.set_hint(Lang.t("Filtre : %s", "Filter: %s") % filter_bar.chips[HubGear.PART_FILTERS.find(f)].text)


func cycle_filter() -> void:
	set_filter(HubGear.PART_FILTERS[(HubGear.PART_FILTERS.find(filter) + 1) % HubGear.PART_FILTERS.size()])


func cycle_sort() -> void:
	sort = HubGear.PART_SORTS[(HubGear.PART_SORTS.find(sort) + 1) % HubGear.PART_SORTS.size()]
	_refocus_after(func(): _fill(false))
	hub.set_hint(Lang.t("Tri : %s", "Sort: %s") % _sort_name())


func _refocus_after(cb: Callable) -> void:
	var f := _focus_owner()
	var inside := f != null and is_ancestor_of(f)
	cb.call()
	var c := first_focus()
	if c and (inside or f == null or not f.is_inside_tree()):
		c.grab_focus()


# --------------------------------------------------------------------------
# Contrat des panneaux
# --------------------------------------------------------------------------

func first_focus() -> Control:
	var r := _row_of(selected_uid)
	if r == null and not rows.is_empty():
		r = rows[0]
	return r


func prompts() -> Array:
	return [[HubPrompts.ACCEPT, Lang.t("Installer", "Install")], [HubPrompts.FILTER, Lang.t("Filtre", "Filter")],
		[HubPrompts.SORT, Lang.t("Tri", "Sort")], [HubPrompts.BACK, Lang.t("Retour", "Back")]]


func back() -> bool:
	var f := _focus_owner()
	if f and is_ancestor_of(f) and not list.is_ancestor_of(f):
		var r := first_focus()
		if r:
			Audio.play_ui(MenuStyle.SND_BACK, -4.0)
			r.grab_focus()
			return true
	return false


func handle_input(event: InputEvent) -> bool:
	if HubArsenalPanel._pressed_key(event, KEY_R) or HubArsenalPanel._pressed_pad(event, JOY_BUTTON_X):
		cycle_sort()
		return true
	if HubArsenalPanel._pressed_pad(event, JOY_BUTTON_Y):
		cycle_filter()
		return true
	return false


func _input(event: InputEvent) -> void:
	if not visible or hub == null or not hub._active() or hub.hub_menu.is_open():
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
	_seen_now.clear()
	if _pending_seen:
		_pending_seen = false
		hub.save_profile()


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner() if get_viewport() else null
