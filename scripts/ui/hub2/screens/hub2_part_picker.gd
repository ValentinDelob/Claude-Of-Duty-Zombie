class_name Hub2PartPicker
extends Control
## Fenêtre « installer une pièce » de l'ARSENAL du hub v2 (pas de maquette :
## jetons des maquettes docs/hub_v2, logique de l'ancien HubPartPicker,
## docs/HUB_PLAN.md §3.2) : voile sombre sur l'écran, panneau de verre centré
## (880 × 520 à 100 %, borné à la zone <main>) :
##   - en-tête liseré de la couleur de rareté : « INSTALLER UNE PIÈCE ·
##     EMPLACEMENT N » (turquoise), nom de l'arme, niveau et rareté ;
##   - à gauche les pièces en stock : montables d'abord (niveau décroissant),
##     puis les autres, à 50 %, avec la raison (HubGear.mount_refusal, règle
##     OwnedWeapon.can_mount) ;
##   - à droite l'APERÇU avant -> après des statistiques de la fiche touchées
##     (vert : mieux, rouge : moins bien ; recharge plus longue = rouge) et du
##     score, la règle, INSTALLER (un appui : rien n'est détruit) et ANNULER.
## A / Entrée / clic sur une pièce montable ou INSTALLER : `install_requested` ;
## B / Échap / clic droit (via le panneau) ou ANNULER : `closed`.

signal install_requested(part_uid: String)
signal closed

const PANEL_SIZE := Vector2(880, 520)
const LIST_W := 470.0

var weapon: OwnedWeapon
var slot := 0
var parts: Array[WeaponPart] = []
var rows: Array = []  # Hub2Button, même ordre que `parts`
var selected := -1
var panel: Hub2Box
var install_button: Hub2Button
var cancel_button: Hub2Button
var preview: VBoxContainer
var _profile: PlayerProfile
var _area := Rect2()
var _hub: Node


## Ouvre la fenêtre pour l'emplacement `slot_index` de `w` dans la zone
## `area` (pixels du parent) ; `pre` : pièce choisie d'avance.
func open(hub: Node, pr: PlayerProfile, w: OwnedWeapon, slot_index: int, area: Rect2, pre := "") -> void:
	_hub = hub
	_profile = pr
	weapon = w
	slot = slot_index
	_area = area
	name = "PartPicker"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	var i := 0
	for j in parts.size():
		if parts[j].uid == pre:
			i = j
	select(i)
	if not rows.is_empty():
		(rows[selected] as Control).grab_focus()
	else:
		cancel_button.grab_focus()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Hub2Style.shade(0.6))


func _build() -> void:
	panel = Hub2Box.new()
	panel.glass(Hub2Style.GLASS_STRONG)
	var sz := Hub2Style.pxv(PANEL_SIZE.x, PANEL_SIZE.y)
	sz = Vector2(minf(sz.x, _area.size.x), minf(sz.y, _area.size.y))
	panel.position = (_area.position + (_area.size - sz) * 0.5).round()
	panel.size = sz
	panel.custom_minimum_size = sz
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	# En-tête : padding 20 20 16, liseré haut 3 px de la rareté.
	var head := Hub2Box.new()
	head.flat(Color(0, 0, 0, 0), Hub2Style.rarity_color(weapon.rarity))
	head.border = Vector4(0, 3, 0, 0)
	head.pad(20, 20, 16, 20)
	col.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hv)
	var kicker := Hub2Text.new()
	kicker.setup(Lang.t("INSTALLER UNE PIÈCE · EMPLACEMENT %d", "INSTALL A PART · SLOT %d") % (slot + 1),
			Hub2Style.CHAKRA, 700, 13, Hub2Style.TEAL, 0.14)
	hv.add_child(kicker)
	var tl := HBoxContainer.new()
	tl.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(tl)
	var nm := Hub2Text.new()
	nm.setup(HubGear.weapon_name(weapon.weapon_id), Hub2Style.CHAKRA, 700, 28, Hub2Style.TEXT, 0.03)
	nm.line_height = 28
	tl.add_child(nm)
	var info := Hub2Text.new()
	info.setup("%s · %s" % [Hub2ArsenalView.level_text(weapon.level), GameWeapon.rarity_name(weapon.rarity)],
			Hub2Style.MONO, 700, 14, Hub2Style.text_a(0.7))
	info.size_flags_vertical = Control.SIZE_SHRINK_END
	tl.add_child(info)
	# Corps : liste | aperçu.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body)
	var left := Hub2Box.new()
	left.flat(Color(0, 0, 0, 0), Hub2Style.LINE)
	left.border = Vector4(0, 1, 1, 0)
	left.pad(14, 14, 14, 20)
	left.custom_minimum_size.x = minf(Hub2Style.px(LIST_W), sz.x * 0.56)
	body.add_child(left)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	Hub2ArsenalPanel.scroll_mark(sc, body, Hub2Style.px(5))
	left.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(list)
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
		list.add_child(_row(i))
	if parts.is_empty():
		var none := Hub2Style.label(Lang.t("Aucune pièce en stock : on en trouve en partie.", "No part in stock: they are found during matches."),
				Hub2Style.BARLOW, 400, 15, Hub2Style.text_a(0.6))
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = Hub2Style.px(300)
		list.add_child(none)
	var right := Hub2Box.new()
	right.flat(Color(0, 0, 0, 0))
	right.pad(14, 20, 18, 20)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(rv)
	var ph := Hub2Text.new()
	ph.setup(Lang.t("APERÇU", "PREVIEW"), Hub2Style.CHAKRA, 600, 12, Hub2Style.text_a(0.55), 0.18)
	rv.add_child(ph)
	preview = VBoxContainer.new()
	preview.add_theme_constant_override("separation", int(Hub2Style.px(6)))
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(preview)
	var rule := Hub2Style.label(Lang.t("Niveau de la pièce ≤ niveau de l’arme et ≤ le vôtre. Une pièce retirée plus tard est détruite.",
			"Part level ≤ weapon level and ≤ yours. A part removed later is destroyed."), Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.55))
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.custom_minimum_size.x = Hub2Style.px(200)
	rv.add_child(rule)
	var spring := Control.new()
	spring.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(spring)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(btns)
	install_button = _button(Lang.t("INSTALLER", "INSTALL"), true)
	install_button.pressed.connect(_install)
	install_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(install_button)
	cancel_button = _button(Lang.t("ANNULER", "CANCEL"), false)
	cancel_button.hint = Lang.t("Fermer sans rien installer.", "Close without installing anything.")
	cancel_button.pressed.connect(func(): closed.emit())
	btns.add_child(cancel_button)
	_link_focus()


func _button(t: String, primary: bool) -> Hub2Button:
	var b := Hub2Button.new()
	if primary:
		b.box.flat(Hub2Style.YELLOW)
		b.box.chamfer(10)
	else:
		b.box.glass(Hub2Style.GLASS, Hub2Style.white_a(0.14), 1.0)
	b.box.pad(11, 18)
	var tx := Hub2Text.new()
	tx.setup(t, Hub2Style.CHAKRA, 700, 15, Hub2Style.INK if primary else Hub2Style.TEXT, 0.1)
	tx.align = HORIZONTAL_ALIGNMENT_CENTER
	b.add_content(tx)
	return b


func _row(i: int) -> Hub2Button:
	var p := parts[i]
	var why := HubGear.mount_refusal(weapon, p, _profile.level())
	var b := Hub2Button.new()
	b.box.flat(Hub2Style.white_a(0.05))
	b.box.pad(9, 12)
	b.hint = why if why != "" else Lang.t("Installer cette pièce : rien n’est détruit.", "Install this part: nothing is destroyed.")
	if why != "":
		b.modulate.a = 0.5
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(2)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_content(v)
	var nm := Hub2Text.new()
	nm.setup(Hub2ArsenalView.part_line_name(p), Hub2Style.CHAKRA, 700, 15, Hub2Style.TEXT, 0.04)
	v.add_child(nm)
	var ml := Hub2ArsenalModLine.new()
	ml.effects = Hub2ArsenalView.effects(p)
	v.add_child(ml)
	if why != "":
		var r := Hub2Text.new()
		r.setup(why, Hub2Style.CHAKRA, 700, 11, Hub2Style.BAD, 0.08)
		v.add_child(r)
	var idx := i
	b.focus_entered.connect(func(): select(idx))
	# Clic : choisir (aperçu) ; double-clic, A ou Entrée : installer.
	b.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			b.set_meta("mouse", true)
			if mb.double_click:
				select(idx)
				_install.call_deferred()
		elif e.is_action_pressed("ui_accept"):
			b.set_meta("mouse", false))
	b.pressed.connect(func():
		select(idx)
		var mouse: bool = b.get_meta("mouse", false)
		b.set_meta("mouse", false)
		if not mouse:
			_install())
	rows.append(b)
	return b


## Choisit la pièce `i` : surlignée, aperçu, bouton INSTALLER.
func select(i: int) -> void:
	if parts.is_empty():
		selected = -1
		_fill_preview(null)
		install_button.disabled = true
		install_button.modulate.a = 0.5
		install_button.hint = Lang.t("Aucune pièce en stock.", "No part in stock.")
		return
	selected = clampi(i, 0, parts.size() - 1)
	for j in rows.size():
		var on := j == selected
		(rows[j] as Hub2Button).box.flat(Hub2Style.yellow_a(0.12) if on else Hub2Style.white_a(0.05),
				Hub2Style.YELLOW if on else Color(0, 0, 0, 0), 1.0 if on else 0.0)
	var p := parts[selected]
	_fill_preview(p)
	var why := HubGear.mount_refusal(weapon, p, _profile.level())
	install_button.disabled = why != ""
	install_button.modulate.a = 0.5 if why != "" else 1.0
	install_button.hint = why if why != "" else Lang.t("Installer %s : un appui, rien n’est détruit.",
			"Install %s: one press, nothing is destroyed.") % HubGear.part_name(p)
	install_button.focus_neighbor_left = install_button.get_path_to(rows[selected])
	if _hub and (rows[selected] as Control).has_focus():
		_hub.call("set_hint", (rows[selected] as Hub2Button).hint)


func _fill_preview(p: WeaponPart) -> void:
	for c in preview.get_children():
		preview.remove_child(c)
		c.queue_free()
	if p == null:
		return
	var lines := Hub2ArsenalView.preview_lines(weapon, p)
	for l in lines:
		_preview_row(String(l.label), String(l.before), String(l.after),
				Hub2ArsenalView.GOOD if l.good else Hub2ArsenalView.HARMFUL)
	if lines.is_empty():
		var eff := Hub2ArsenalModLine.new()
		eff.effects = Hub2ArsenalView.effects(p)
		preview.add_child(eff)
	_preview_row("SCORE", str(weapon.score()), str(weapon.score() + p.level), Hub2Style.YELLOW)


func _preview_row(label: String, before: String, after: String, col: Color) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Hub2Text.new()
	l.setup(label, Hub2Style.CHAKRA, 600, 10, Hub2Style.text_a(0.5), 0.14)
	l.custom_minimum_size.x = Hub2Style.px(96)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var b := Hub2Text.new()
	b.setup(before, Hub2Style.MONO, 700, 15, Hub2Style.TEXT)
	h.add_child(b)
	var ar := Hub2Text.new()
	ar.setup("→", Hub2Style.MONO, 500, 13, Hub2Style.text_a(0.45))
	ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ar)
	var a := Hub2Text.new()
	a.setup(after, Hub2Style.MONO, 700, 15, col)
	h.add_child(a)
	preview.add_child(h)


func _install() -> void:
	if selected < 0 or selected >= parts.size():
		return
	var p := parts[selected]
	var why := HubGear.mount_refusal(weapon, p, _profile.level())
	if why != "":
		Audio.play_ui(MenuStyle.SND_BACK, -4.0)
		if _hub:
			_hub.call("set_hint", why)
		return
	install_requested.emit(p.uid)


## Le focus reste dans la fenêtre : la liste à gauche, les boutons à droite.
func _link_focus() -> void:
	for i in rows.size():
		var r: Control = rows[i]
		r.focus_neighbor_top = r.get_path_to(rows[maxi(i - 1, 0)])
		r.focus_neighbor_bottom = r.get_path_to(rows[mini(i + 1, rows.size() - 1)])
		r.focus_neighbor_left = r.get_path_to(r)
		r.focus_neighbor_right = r.get_path_to(install_button if not install_button.disabled else cancel_button)
	for bc: Control in [install_button, cancel_button]:
		bc.focus_neighbor_top = bc.get_path_to(bc)
		bc.focus_neighbor_bottom = bc.get_path_to(bc)
	install_button.focus_neighbor_right = install_button.get_path_to(cancel_button)
	cancel_button.focus_neighbor_left = cancel_button.get_path_to(install_button)
	cancel_button.focus_neighbor_right = cancel_button.get_path_to(cancel_button)
	if rows.is_empty():
		install_button.focus_neighbor_left = install_button.get_path_to(install_button)
	else:
		cancel_button.focus_neighbor_left = cancel_button.get_path_to(install_button)
