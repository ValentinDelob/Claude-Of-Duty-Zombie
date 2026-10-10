class_name HubPartPicker
extends Control
## Fenêtre « installer une pièce » (docs/HUB_PLAN.md §3.2, maquette écran 3),
## ouverte depuis un emplacement libre de la fiche d'arme ou par INSTALLER
## SUR… de l'onglet PIÈCES : voile sur tout le hub (sauf la barre d'invites),
## panneau à en-tête rouge « INSTALLER SUR : FRELON (NIV. 7, ÉPIQUE) ·
## EMPLACEMENT 3 ».
##   - à gauche, les pièces en stock : montables d'abord (niveau décroissant,
##     la plus haute choisie d'abord), puis les autres, grisées, avec la
##     raison (HubGear.mount_refusal, règle OwnedWeapon.can_mount) ;
##   - à droite, l'APERÇU avant / après (statistiques touchées, score, prix à
##     la station), la règle, INSTALLER (un appui : rien n'est détruit) et
##     ANNULER.
## Entrée / A sur une pièce montable ou INSTALLER : `install_requested` ;
## Échap / B / clic droit (via le panneau) ou ANNULER : `closed`. Le panneau
## ARSENAL applique le montage (PlayerProfile.mount_part) et enregistre.

signal install_requested(part_uid: String)
signal closed

## Position et taille de la maquette (cadre 1280 × 720, à 100 %).
const PANEL_RECT := Rect2(200, 132, 880, 520)
const LIST_W := 520.0

var weapon: OwnedWeapon
var slot := 0
## Pièces de la liste, dans l'ordre affiché.
var parts: Array[WeaponPart] = []
var rows: Array = []  # HubPickRow, même ordre que `parts`
var selected := -1
var install_button: HubButton
var cancel_button: HubButton
var panel: HubBox
var preview: GridContainer
var _hub: Node
var _profile: PlayerProfile


## Ouvre la fenêtre pour l'emplacement `slot_index` de `w` ; `pre` : pièce
## choisie d'avance (onglet PIÈCES), sinon la montable de plus haut niveau.
func open(hub: Node, pr: PlayerProfile, w: OwnedWeapon, slot_index: int, pre := "") -> void:
	_hub = hub
	_profile = pr
	weapon = w
	slot = slot_index
	name = "PartPicker"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_bottom = -HubStyle.px(HubPrompts.HEIGHT)
	_build()
	var i := 0
	for j in parts.size():
		if parts[j].uid == pre:
			i = j
	select(i)
	if install_button and not install_button.disabled:
		install_button.grab_focus()
	elif not rows.is_empty():
		(rows[selected] as Control).grab_focus()
	else:
		cancel_button.grab_focus()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.62))


func _build() -> void:
	var n := HubGear.weapon_name(weapon.weapon_id)
	var title := Lang.t("INSTALLER SUR : %s (NIV. %d, %s) · EMPLACEMENT %d", "INSTALL ON: %s (LVL %d, %s) · SLOT %d") % [
		n, weapon.level, GameWeapon.rarity_name(weapon.rarity), slot + 1]
	var stock := (Lang.t("%d pièce en stock", "%d part in stock") if _profile.parts.size() == 1
			else Lang.t("%d pièces en stock", "%d parts in stock")) % _profile.parts.size()
	panel = HubBox.new(title, stock, true, false)
	panel.right_label.add_theme_color_override("font_color", HubStyle.HEADER_RED_TEXT)
	add_child(panel)
	resized.connect(_place)
	# Un texte à la ligne n'a sa vraie hauteur qu'une fois sa largeur connue :
	# la taille du panneau est reprise quand son minimum change.
	panel.minimum_size_changed.connect(func(): _place.call_deferred())
	# Après la mise en page du hub (taille de la fenêtre connue).
	_place.call_deferred()
	var body := HubWeaponSheet.SheetBody.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.content.add_child(body)
	# Liste des pièces.
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.custom_minimum_size.x = HubStyle.px(LIST_W)
	HubBox.style_scrollbar(sc.get_v_scroll_bar())
	body.add_child(sc)
	var list := HubBox.vbox(0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	# Filet de 2 px à droite de la liste (dessiné par SheetBody).
	var lm := HubBox.pad(list, 0, 0, 2, 0)
	lm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lm)
	var ok: Array[WeaponPart] = []
	var ko: Array[WeaponPart] = []
	for p in _profile.parts:
		(ok if HubGear.mount_refusal(weapon, p, _profile.level()) == "" else ko).append(p)
	ok.sort_custom(func(a, b): return HubGear.part_before(a, b, "level"))
	ko.sort_custom(func(a, b): return HubGear.part_before(a, b, "level"))
	parts.clear()
	parts.append_array(ok)
	parts.append_array(ko)
	for i in parts.size():
		var p := parts[i]
		var why := HubGear.mount_refusal(weapon, p, _profile.level())
		var row := HubPickRow.new(HubRow.ROW, 56.0 if why != "" else 40.0, why != "", 0.0)
		row.alt = i % 2 == 1
		row.locked = why != ""
		row.key = p.uid
		row.hint = why if why != "" else Lang.t("Installer cette pièce : rien n'est détruit.", "Install this part: nothing is destroyed.")
		var line := HubBox.hbox(10)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(_icon(p, why != ""))
		var nl := HubStyle.label(HubGear.part_name(p), 15, Color("6D6A63") if why != "" else HubStyle.PAPER, "bold")
		line.add_child(nl)
		var lv := HubStyle.label(HubGear.level_text(p.level), 13, Color("6D6A63") if why != "" else HubStyle.DIM)
		line.add_child(lv)
		line.add_child(HubBox.spring(false))
		if why != "":
			line.add_child(HubStyle.label(HubGear.mods_plain(HubGear.ordered_mods(p), p.mods.size() > 1), 13, Color("6D7A62"), "semi"))
		else:
			line.add_child(HubWeaponSheet.mods_row(HubGear.ordered_mods(p), 13, p.mods.size() > 1))
		row.box.add_child(line)
		if why != "":
			var reason := HubStyle.label(why, 12, Color("B0705F"))
			row.box.add_child(HubBox.pad(reason, 34, 0, 0, 0))
		var idx := i
		row.chosen.connect(func():
			select(idx)
			if _hub:
				_hub.set_hint(row.hint))
		row.activated.connect(func():
			select(idx)
			_install())
		list.add_child(row)
		rows.append(row)
	if parts.is_empty():
		var none := HubStyle.label(Lang.t("Aucune pièce en stock : on en trouve en partie.", "No part in stock: they are found during matches."), 14, HubStyle.DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(HubBox.pad(none, 12, 12, 12, 12))
	# Aperçu.
	var right := HubBox.vbox(10)
	# Largeur de la maquette (880 − 520 − marges) : le texte de la règle se
	# coupe à cette largeur, pas mot par mot (hauteur minimale raisonnable).
	right.custom_minimum_size.x = HubStyle.px(324)
	var rm := HubBox.pad(right, 16, 14, 16, 12)
	rm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rm)
	right.add_child(HubStyle.label(Lang.t("APERÇU", "PREVIEW"), 13, HubStyle.DIM, "impact", false, 0.06))
	preview = GridContainer.new()
	preview.columns = 4
	preview.add_theme_constant_override("h_separation", int(HubStyle.px(6)))
	preview.add_theme_constant_override("v_separation", int(HubStyle.px(6)))
	right.add_child(preview)
	var rule := HubStyle.label(Lang.t("Règle : niveau de la pièce ≤ niveau de l'arme et ≤ votre niveau. Une pièce installée peut être retirée plus tard, mais elle sera détruite.",
			"Rule: part level ≤ weapon level and ≤ your level. A mounted part can be removed later, but it will be destroyed."), 13, HubStyle.DIM)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(HubBox.pad(rule, 0, 6, 0, 0))
	right.add_child(HubBox.spring())
	var btns := HubBox.hbox(10)
	right.add_child(btns)
	install_button = HubButton.make(Lang.t("INSTALLER", "INSTALL"), _install, HubButton.PRIMARY)
	install_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	install_button.focus_entered.connect(func(): _say(install_button.hint))
	btns.add_child(install_button)
	cancel_button = HubButton.make(Lang.t("ANNULER", "CANCEL"), close, HubButton.NORMAL,
			Lang.t("Fermer sans rien installer.", "Close without installing anything."))
	cancel_button.focus_entered.connect(func(): _say(cancel_button.hint))
	btns.add_child(cancel_button)
	_link_focus()


func _icon(_p: WeaponPart, dim: bool) -> HubIcon:
	var ic := HubIcon.make("part", 3)
	if dim:
		ic.dim = 0.45
	return ic


## Panneau à sa place de la maquette, mis à l'échelle autour du centre et
## gardé dans la fenêtre.
func _place() -> void:
	if panel == null:
		return
	var f := HubStyle.factor()
	var sz := PANEL_RECT.size * f
	var area := size
	sz = Vector2(minf(sz.x, area.x - HubStyle.px(16)), minf(sz.y, area.y - HubStyle.px(16)))
	var c := PANEL_RECT.get_center() * Vector2(area.x / 1280.0, (area.y + HubStyle.px(HubPrompts.HEIGHT)) / 720.0)
	var pos := (c - sz * 0.5).round()
	pos.x = clampf(pos.x, HubStyle.px(8), area.x - sz.x - HubStyle.px(8))
	pos.y = clampf(pos.y, HubStyle.px(8), area.y - sz.y - HubStyle.px(8))
	panel.position = pos
	panel.size = sz


## Choisit la pièce `i` : sélection, aperçu, bouton INSTALLER.
func select(i: int) -> void:
	if parts.is_empty():
		selected = -1
		_fill_preview(null)
		install_button.disabled = true
		install_button.hint = Lang.t("Aucune pièce en stock.", "No part in stock.")
		return
	selected = clampi(i, 0, parts.size() - 1)
	for j in rows.size():
		(rows[j] as HubPickRow).sticky = j == selected
	var p := parts[selected]
	_fill_preview(p)
	var why := HubGear.mount_refusal(weapon, p, _profile.level())
	install_button.disabled = why != ""
	install_button.hint = why if why != "" else Lang.t("Installer %s : un appui, rien n'est détruit.", "Install %s: one press, nothing is destroyed.") % HubGear.part_name(p)
	install_button.focus_neighbor_left = install_button.get_path_to(rows[selected])


func _fill_preview(p: WeaponPart) -> void:
	for c in preview.get_children():
		preview.remove_child(c)
		c.queue_free()
	if p == null:
		return
	for l in HubGear.part_preview(weapon, p):
		_preview_row(String(l.label), String(l.before), String(l.after), HubStyle.OK if l.good else HubStyle.BAD)
	_preview_row(Lang.t("Score", "Score"), str(weapon.score()), str(weapon.score() + p.level), HubStyle.YELLOW)
	var price := HubStyle.num(BuildRules.owned_price(weapon))
	# Les pièces ne changent pas le prix de construction (provisoire).
	_preview_row(Lang.t("Prix à la station", "Station price"), price, price, HubStyle.PAPER, false)


func _preview_row(label: String, before: String, after: String, col: Color, bold := true) -> void:
	var l := HubStyle.label(label, 14, HubStyle.PAPER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_child(l)
	var b := HubStyle.label(before, 14, HubStyle.PAPER)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.custom_minimum_size.x = HubStyle.px(60)
	preview.add_child(b)
	var arrow := HubStyle.label("→", 14, HubStyle.DIM)
	arrow.custom_minimum_size.x = HubStyle.px(20)
	preview.add_child(arrow)
	var a := HubStyle.label(after, 14, col, "bold" if bold else "ui")
	a.custom_minimum_size.x = HubStyle.px(60)
	preview.add_child(a)


func _install() -> void:
	if selected < 0 or selected >= parts.size():
		return
	var p := parts[selected]
	if HubGear.mount_refusal(weapon, p, _profile.level()) != "":
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		if _hub:
			_hub.set_hint(HubGear.mount_refusal(weapon, p, _profile.level()))
		return
	install_requested.emit(p.uid)


func close() -> void:
	closed.emit()


func _say(t: String) -> void:
	if _hub:
		_hub.set_hint(t)


## Le focus reste dans la fenêtre : la liste en haut à gauche, les boutons
## à droite.
func _link_focus() -> void:
	for i in rows.size():
		var r: Control = rows[i]
		r.focus_neighbor_top = r.get_path_to(rows[maxi(i - 1, 0)])
		r.focus_neighbor_bottom = r.get_path_to(rows[mini(i + 1, rows.size() - 1)])
		r.focus_neighbor_left = r.get_path_to(r)
		r.focus_neighbor_right = r.get_path_to(install_button)
	for b in [install_button, cancel_button]:
		var bc: Control = b
		bc.focus_neighbor_top = bc.get_path_to(bc)
		bc.focus_neighbor_bottom = bc.get_path_to(bc)
	install_button.focus_neighbor_right = install_button.get_path_to(cancel_button)
	cancel_button.focus_neighbor_left = cancel_button.get_path_to(install_button)
	cancel_button.focus_neighbor_right = cancel_button.get_path_to(cancel_button)
	if rows.is_empty():
		install_button.focus_neighbor_left = install_button.get_path_to(install_button)
