extends TestCase
## ARSENAL du hub v2 (docs/hub_v2/Arsenal.dc.html, docs/HUB_PLAN.md §9) :
## rail par niveau (groupement, ordre rareté puis score, ◄ ► / ▲ ▼, fenêtre de
## 5 colonnes, flèches ‹ ›, saut de la vue d'ensemble, colonnes à 130 %),
## filtres, statistiques de la fiche (valeur de base + modificateur « + N »
## vert / « − N » rouge sans unité, recharge plus longue = rouge, unités
## /min, %, m, s, corps à corps « — »), effets et qualité des pièces, et le
## panneau dans le hub : cartes, navigation clavier / manette, fiche,
## installer (aperçu), retirer et recycler en deux appuis, armes de base,
## sous-onglet PIÈCES, NEUF, anglais, 130 %.

const DEMO := preload("res://tests/autotest/hub2_arsenal_look.gd")

var _saved := {}
var _frame: Control


class FakeHost extends MenuHost:
	func show_screen(_screen_name: String, _args := {}, _remember := true) -> void:
		pass


## Hub sans disque qui compte les écritures du profil.
class CountingHub extends Hub2Screen:
	var saves := 0

	func save_profile() -> Error:
		saves += 1
		return super()


func before_each() -> void:
	Input.flush_buffered_events()
	for k in ["menu_ui_scale", "using_pad", "language"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	for k in _saved:
		Settings.set(k, _saved[k])
	Hub2Screen.last_screen = "lab"


func _open(pr: PlayerProfile) -> CountingHub:
	_frame = Control.new()
	_frame.size = Vector2(1280, 720)
	host.add_child(_frame)
	var mh := FakeHost.new()
	mh.size = Vector2(1280, 720)
	_frame.add_child(mh)
	var hub := CountingHub.new()
	hub.menu = mh
	hub.size = Vector2(1280, 720)
	mh.add_child(hub)
	mh.current = hub
	mh.current_name = "hub2"
	hub.enter({"screen": "arsenal", "profile": pr})
	await wait_frames(3)
	return hub


func _w(id: String, lvl: int, r: int, parts := []) -> OwnedWeapon:
	var w := OwnedWeapon.create(id, lvl, r)
	for p in parts:
		w.parts.append(p)
	return w


func _nav(card: Control, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	card._gui_input(ev)


# --- Rail ------------------------------------------------------------------------

func test_rail_groups_by_level_and_sorts_by_rarity_then_score() -> void:
	var a := _w("m14", 20, 1)
	var b := _w("python", 20, 3, [WeaponPart.create("part_damage", 5, {"damage": 0.1})])
	var c := _w("python", 20, 3)
	var d := _w("cz75", 8, 0)
	var e := _w("spectre", 24, 2)
	for i in 5:
		[a, b, c, d, e][i].uid = "w%d" % (i + 1)
	var rail := Hub2ArsenalRail.new()
	rail.setup([a, b, c, d, e], Hub2ArsenalView.weapon_before)
	assert_eq(rail.levels, [8, 20, 24] as Array[int], "niveaux croissants")
	assert_eq(rail.count(), 5)
	var col := rail.column(1)
	assert_eq([col[0].uid, col[1].uid, col[2].uid], ["w2", "w3", "w1"],
			"même niveau : légendaire score 25, légendaire score 20, puis rare")


func test_rail_navigation_and_window() -> void:
	var items := []
	for lvl in [1, 3, 5, 8, 12, 14, 18, 20, 24]:
		var w := _w("m14", lvl, 0)
		w.uid = "w%d" % lvl
		items.append(w)
	var extra := _w("python", 20, 3)
	extra.uid = "w99"
	items.append(extra)
	var rail := Hub2ArsenalRail.new()
	rail.setup(items, Hub2ArsenalView.weapon_before)
	assert_eq(rail.max_start(), 4, "9 niveaux, 5 visibles")
	assert_true(rail.select_uid("w99"))
	assert_eq([rail.sel_col, rail.sel_row], [7, 0], "légendaire en tête du niveau 20")
	rail.center_on_selection()
	assert_eq(rail.start, 4, "fenêtre centrée (bornée) : niveaux 12 à 24")
	assert_true(rail.move_row(1), "▼ : même niveau")
	assert_eq(String(rail.selected().uid), "w20")
	assert_false(rail.move_row(1), "▼ au bas de la colonne")
	assert_true(rail.move_col(1), "► : niveau 24")
	assert_eq([rail.selected_level(), rail.sel_row], [24, 0], "rang borné à la colonne")
	assert_false(rail.move_col(1), "► au dernier niveau")
	for i in 7:
		rail.move_col(-1)
	assert_eq(rail.selected_level(), 3)
	assert_eq(rail.start, 1, "◄ : la fenêtre suit au minimum")
	assert_true(rail.is_visible_col(rail.sel_col))
	assert_true(rail.shift(-1) and rail.start == 0, "‹ : fenêtre décalée")
	assert_false(rail.shift(-1), "‹ au bord")
	assert_false(rail.can_shift(-1))
	rail.jump(8)
	assert_eq(rail.start, 4, "vue d'ensemble : i − 2 borné")
	rail.jump(3)
	assert_eq(rail.start, 1)
	assert_eq(rail.visible_cols(), [1, 2, 3, 4, 5] as Array[int])
	assert_eq(rail.selected_level(), 3, "‹ › et saut ne changent pas le choix")


func test_rail_fit_visible() -> void:
	assert_eq(Hub2ArsenalRail.fit_visible(734.0, 135.0, 14.0), 5, "100 % : 5 colonnes")
	assert_eq(Hub2ArsenalRail.fit_visible(571.0, 176.0, 18.0), 3, "130 % : 3 colonnes lisibles")
	assert_eq(Hub2ArsenalRail.fit_visible(2000.0, 135.0, 14.0), 5, "jamais plus que la maquette")
	assert_eq(Hub2ArsenalRail.fit_visible(10.0, 135.0, 14.0), 1)
	var rail := Hub2ArsenalRail.new()
	rail.visible = 3
	var items := []
	for lvl in [1, 2, 3, 4]:
		var w := _w("m14", lvl, 0)
		w.uid = "w%d" % lvl
		items.append(w)
	rail.setup(items, Hub2ArsenalView.weapon_before)
	assert_eq(rail.max_start(), 1)
	rail.select_at(3, 0)
	rail.ensure_visible()
	assert_eq(rail.start, 1)


func test_filters() -> void:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(10)
	pr.add_weapon(_w("m14", 5, 0))
	pr.add_weapon(_w("galil", 24, 4))
	var all := Hub2ArsenalView.weapons(pr, "all")
	assert_eq(all.size(), 4, "2 armes de base + 2 de l'arsenal")
	assert_true(Hub2ArsenalView.is_base(all[0]))
	assert_eq(Hub2ArsenalView.weapons(pr, "melee").size(), 1, "MÊLÉE : la batte")
	assert_eq(Hub2ArsenalView.weapons(pr, "firearm").size(), 3)
	assert_eq(Hub2ArsenalView.weapons(pr, "usable").size(), 3, "UTILISABLES : sans le niveau 24")
	assert_eq(Hub2ArsenalView.next_filter(Hub2ArsenalView.FILTERS, "usable"), "all", "Y : en boucle")
	assert_eq(Hub2ArsenalView.filter_name("melee"), "MÊLÉE")
	Settings.language = "en"
	assert_eq(Hub2ArsenalView.filter_name("firearm"), "FIREARMS")
	assert_eq(Hub2ArsenalView.level_text(20), "LVL 20")
	assert_eq(Hub2ArsenalView.required_text(24), "LVL 24 REQUIRED")


# --- Statistiques ----------------------------------------------------------------

func test_stat_format_units_and_mods() -> void:
	var nb := String.chr(0xA0)
	assert_eq(Hub2ArsenalView.format_value("rpm", 400.0), "400/min")
	assert_eq(Hub2ArsenalView.format_value("accuracy", 70.4), "70" + nb + "%")
	assert_eq(Hub2ArsenalView.format_value("range", 25.0), "25" + nb + "m")
	assert_eq(Hub2ArsenalView.format_value("reload", 1.6), "1,6" + nb + "s")
	assert_eq(Hub2ArsenalView.format_value("damage", 1234.0), "1" + nb + "234")
	assert_eq(Hub2ArsenalView.format_mod("damage", 33.6), "+ 34", "sans unité, « + » espacé")
	assert_eq(Hub2ArsenalView.format_mod("rpm", -24.0), "− 24")
	assert_eq(Hub2ArsenalView.format_mod("reload", 0.3), "+ 0,3", "recharge : une décimale, sans « s »")
	assert_eq(Hub2ArsenalView.format_mod("damage", 0.4), "", "écart nul une fois arrondi : rien")
	assert_eq(Hub2ArsenalView.format_mod("reload", 0.02), "")
	assert_true(Hub2ArsenalView.mod_good("damage", 5.0))
	assert_false(Hub2ArsenalView.mod_good("rpm", -5.0))
	assert_false(Hub2ArsenalView.mod_good("reload", 0.3), "recharge plus longue : nuisible")
	assert_true(Hub2ArsenalView.mod_good("reload", -0.3), "recharge plus courte : bénéfique")
	assert_eq(Hub2ArsenalView.mod_color("reload", 0.3).to_html(false), "ff6b57")
	assert_eq(Hub2ArsenalView.mod_color("damage", 3.0).to_html(false), "4fe3c1")
	Settings.language = "en"
	assert_eq(Hub2ArsenalView.format_value("accuracy", 70.0), "70%")
	assert_eq(Hub2ArsenalView.format_value("reload", 2.5), "2.5" + nb + "s")
	assert_eq(Hub2ArsenalView.format_mod("reload", -0.3), "− 0.3")


func test_stat_lines_base_value_plus_part_modifier() -> void:
	var w := _w("m14", 5, 1, [WeaponPart.create("part_damage", 3, {"damage": 0.2}),
		WeaponPart.create("part_reload", 2, {"reload": -0.2})])
	var lines := Hub2ArsenalView.stat_lines(w)
	assert_eq(lines.size(), 6)
	var keys := []
	var labels := []
	for l in lines:
		keys.append(l.key)
		labels.append(l.label)
	assert_eq(keys, ["damage", "rpm", "accuracy", "range", "mag", "reload"], "ordre de la maquette")
	assert_eq(labels, ["DÉGÂTS", "CADENCE", "PRÉCISION", "PORTÉE", "CHARGEUR", "RECHARGE"])
	var raw := GameWeapon.stats(GameWeapon.make("m14", 5, 1))
	var dmg: Dictionary = lines[0]
	assert_eq(dmg.value, Hub2Style.num(int(raw.damage)), "valeur de BASE : niveau compris, sans pièce")
	assert_eq(dmg.mod, "+ " + Hub2Style.num(roundi(float(raw.damage) * 1.2) - int(raw.damage)), "apport des pièces")
	assert_true(dmg.good)
	var rl: Dictionary = lines[5]
	assert_true(String(rl.mod).begins_with("+ "), "malus de rechargement : temps plus long (%s)" % rl.mod)
	assert_false(rl.good, "recharge plus longue : rouge")
	assert_false(String(rl.mod).contains("s"), "pas d'unité sur le modificateur")
	assert_eq(lines[1].mod, "", "cadence sans pièce : rien")
	var bat := Hub2ArsenalView.stat_lines(BaseWeapons.make("bat"))
	assert_eq([bat[4].value, bat[5].value], ["—", "—"], "corps à corps : ni chargeur ni recharge")
	assert_true(String(bat[0].value) != "—")


func test_preview_lines_before_after() -> void:
	var w := _w("m14", 10, 2)
	var p := WeaponPart.create("part_fire_rate", 4, {"fire_rate": 0.1, "reload": -0.25})
	var pv := Hub2ArsenalView.preview_lines(w, p)
	var keys := []
	for l in pv:
		keys.append(l.key)
	assert_eq(keys, ["rpm", "reload"])
	assert_true(pv[0].good, "cadence plus haute : vert")
	assert_false(pv[1].good, "recharge plus longue : rouge")
	assert_true(String(pv[0].before) != String(pv[0].after))


func test_part_effects_and_quality() -> void:
	var nb := String.chr(0xA0)
	var p := WeaponPart.create("part_damage", 7, {"damage": 0.08, "reload": 0.25})
	var eff := Hub2ArsenalView.effects(p)
	assert_eq(eff[0], ["+8" + nb + "% dégâts", true], "principal d'abord")
	assert_eq(eff[1], ["−20" + nb + "% temps de recharge", true], "rechargement +25 % : durée ÷ 1,25")
	var bad := Hub2ArsenalView.effect("fire_rate", -0.1)
	assert_eq(bad, ["−10" + nb + "% cadence", false])
	assert_eq(Hub2ArsenalView.part_quality(WeaponPart.create("part_damage", 1, {"damage": 0.05})), 0)
	assert_eq(Hub2ArsenalView.part_quality(WeaponPart.create("part_damage", 1, {"damage": 0.15})), 1)
	assert_eq(Hub2ArsenalView.part_quality(WeaponPart.create("part_damage", 1, {"damage": 0.25, "mag": -0.05})), 2)
	assert_eq(Hub2ArsenalView.quality_name(2), "EXCELLENTE")
	assert_eq(Hub2ArsenalView.part_line_name(p), "Renfort · niv. 7")
	Settings.language = "en"
	assert_eq(Hub2ArsenalView.effect("damage", 0.08)[0], "+8% damage")


func test_svg_icons_render() -> void:
	for k in Hub2ArsenalView.STATS:
		var tex := Hub2ArsenalDraw.svg_icon(Hub2ArsenalView.ICONS[k], 18.0, Hub2Style.TEXT)
		assert_false(HubRenders.is_fallback(tex), "icône %s rendue" % k)
		var img := tex.get_image()
		var opaque := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		assert_true(opaque > 10, "icône %s : trait visible (%d)" % [k, opaque])


# --- Panneau dans le hub ---------------------------------------------------------

func test_panel_rail_cards_and_sheet() -> void:
	var pr: PlayerProfile = DEMO.demo_profile()
	var hub := await _open(pr)
	var p: Hub2ArsenalPanel = hub.panels.arsenal
	assert_true(p is Hub2ArsenalPanel and p.visible)
	assert_eq(p.rail.visible, 5, "5 colonnes à 100 %")
	assert_eq(p.columns_box.get_child_count(), 5)
	var sel := p.selected_weapon()
	assert_true(sel != null and sel.level <= pr.level(), "choix d'ouverture : arme utilisable")
	assert_eq(p.rail.selected_level(), 20, "plus haut niveau utilisable (20)")
	assert_eq(sel.weapon_id, "python", "en tête : la plus rare")
	await wait_frames(2)
	assert_true(p.selected_card() != null and p.selected_card().has_focus(), "focus sur la carte choisie")
	assert_true(p.selected_card().selected)
	assert_eq(p.name_text, "COUPERET")
	assert_eq(p.stat_cells.size(), 6)
	assert_eq(p.slots.size(), sel.slot_count(), "un emplacement par place")
	# Carte verrouillée : niveau 24 > 23.
	var locked: Hub2ArsenalCard = null
	for c in p.cards:
		if c.level == 24:
			locked = c
	assert_true(locked != null and locked.data.locked and is_equal_approx(locked.modulate.a, 0.5), "NIV. 24 REQUIS à 50 %")
	assert_eq(locked.data.required, "NIV. 24 REQUIS")
	# Navigation : ▼ même niveau, ► niveau suivant, ◄ retour.
	var card := p.selected_card()
	_nav(card, "ui_down")
	await wait_frames(1)
	assert_eq(p.rail.sel_row, 1, "▼ : carte suivante du niveau")
	assert_true(p.selected_card().has_focus())
	_nav(p.selected_card(), "ui_right")
	await wait_frames(1)
	assert_eq(p.rail.selected_level(), 24, "► : niveau 24")
	assert_eq(p.rail.sel_row, 1, "même rang")
	_nav(p.selected_card(), "ui_left")
	_nav(p.selected_card(), "ui_left")
	await wait_frames(1)
	assert_eq(p.rail.selected_level(), 18)
	_nav(p.selected_card(), "ui_up")
	await wait_frames(1)
	assert_true(p.tab_buttons[Hub2ArsenalPanel.WEAPONS].has_focus(), "▲ en haut de colonne : en-tête")
	hub.back()
	await wait_frames(1)
	assert_true(p.selected_card().has_focus(), "B : retour à la carte")
	# ‹ › et vue d'ensemble.
	var start := p.rail.start
	p.shift(-1)
	assert_eq(p.rail.start, start - 1, "‹ : fenêtre décalée")
	p.jump(0)
	assert_eq(p.rail.start, 0)
	# Filtre (Y) : UTILISABLES retire le niveau 24.
	assert_true(_pad_event(hub, JOY_BUTTON_Y))
	assert_true(_pad_event(hub, JOY_BUTTON_Y))
	assert_true(_pad_event(hub, JOY_BUTTON_Y))
	assert_eq(p.filter, "usable")
	assert_false(24 in p.rail.levels, "UTILISABLES : sans le niveau 24")
	assert_eq(p.chips.size(), 4)


func test_install_remove_recycle() -> void:
	var pr: PlayerProfile = DEMO.demo_profile()
	var hub := await _open(pr)
	var p: Hub2ArsenalPanel = hub.panels.arsenal
	# Arme avec un emplacement libre : le MÉTRONOME commun niveau 5 (1 place).
	var target: OwnedWeapon = null
	for w in pr.weapons:
		if w.weapon_id == "m14" and w.level == 5:
			target = w
	assert_true(target != null)
	p.selected_uid = target.uid
	p.refresh()
	await wait_frames(1)
	p.selected_card().grab_focus()
	await wait_frames(1)
	assert_eq(p.selected_weapon().uid, target.uid)
	p.selected_card().pressed_by_mouse = false
	p.selected_card().pressed.emit()
	await wait_frames(1)
	var f := hub.get_viewport().gui_get_focus_owner()
	assert_true(f in p.slots and not f.get_meta("installed"), "A sur la carte : emplacement libre")
	(f as Hub2Button).pressed.emit()
	await wait_frames(1)
	assert_true(p.picker != null, "A sur l'emplacement libre : fenêtre des pièces")
	assert_eq(hub.prompts.items.size(), 2, "invites : installer, annuler")
	var pk := p.picker
	var ok_index := -1
	for i in pk.parts.size():
		if HubGear.mount_refusal(target, pk.parts[i], pr.level()) == "":
			ok_index = i
			break
	assert_true(ok_index == 0, "pièces montables en tête")
	assert_true(pk.preview.get_child_count() >= 1, "aperçu avant / après")
	var part_uid := pk.parts[0].uid
	var stock := pr.parts.size()
	var saves := hub.saves
	pk.install_button.pressed.emit()
	await wait_frames(1)
	assert_true(p.picker == null, "fenêtre fermée")
	assert_eq(hub.saves, saves + 1, "une écriture")
	assert_eq(pr.parts.size(), stock - 1, "la pièce quitte le stock")
	assert_true(target.has_part(part_uid), "pièce installée")
	assert_true(bool(hub.get_viewport().gui_get_focus_owner().get_meta("installed", false)), "focus sur la pièce installée")
	# Retirer : deux appuis (X).
	assert_true(_pad_event(hub, JOY_BUTTON_X))
	assert_eq(p.armed, "remove", "premier appui : armé")
	assert_true(target.has_part(part_uid), "rien n'est retiré au premier appui")
	hub.back()
	assert_eq(p.armed, "", "B : annulé")
	_pad_event(hub, JOY_BUTTON_X)
	_pad_event(hub, JOY_BUTTON_X)
	assert_false(target.has_part(part_uid), "deuxième appui : pièce retirée")
	assert_true(pr.get_part(part_uid) == null, "pièce détruite (pas de retour au stock)")
	assert_eq(hub.saves, saves + 2)
	# Recycler : deux appuis depuis la carte ; jamais une arme de base.
	p.selected_card().grab_focus()
	await wait_frames(1)
	var uid := target.uid
	_pad_event(hub, JOY_BUTTON_X)
	assert_eq(p.armed, "recycle")
	assert_true(pr.get_weapon(uid) != null)
	_pad_event(hub, JOY_BUTTON_X)
	assert_true(pr.get_weapon(uid) == null, "arme recyclée")
	assert_true(p.selected_uid != uid and p.selected_card() != null, "une voisine prend la place")
	p.selected_uid = BaseWeapons.UID_PREFIX + WeaponDB.STARTING_WEAPON
	p.refresh()
	await wait_frames(1)
	p.selected_card().grab_focus()
	await wait_frames(1)
	_pad_event(hub, JOY_BUTTON_X)
	assert_eq(p.armed, "", "arme de base : jamais recyclée")
	assert_eq(p.slots.size(), 0, "arme de base : pas d'emplacement")


func test_parts_tab() -> void:
	var pr: PlayerProfile = DEMO.demo_profile()
	var hub := await _open(pr)
	var p: Hub2ArsenalPanel = hub.panels.arsenal
	p.set_tab(Hub2ArsenalPanel.PARTS)
	await wait_frames(1)
	assert_eq(p.tab, Hub2ArsenalPanel.PARTS)
	assert_eq(p.rail.count(), pr.parts.size(), "toutes les pièces en stock")
	assert_eq(p.chips.size(), 2, "TOUTES / MONTABLES")
	var part := p.selected_part()
	assert_true(part != null)
	assert_true(p.cards[0].data.part_art, "carte de pièce : pixel art")
	assert_false(p.compat_rows.is_empty(), "armes compatibles")
	p.enter_aside()
	await wait_frames(1)
	var row: Hub2Button = p.compat_rows[0]
	assert_true(row.has_focus())
	var wuid := String(row.get_meta("uid"))
	row.pressed.emit()
	await wait_frames(1)
	assert_true(p.picker != null and p.picker.parts[p.picker.selected].uid == part.uid, "fenêtre ouverte, pièce choisie")
	p.picker.install_button.pressed.emit()
	await wait_frames(1)
	assert_true(pr.get_weapon(wuid).has_part(part.uid), "installée sur l'arme choisie")
	assert_eq(p.tab, Hub2ArsenalPanel.WEAPONS, "retour à l'arme")
	assert_eq(p.selected_weapon().uid, wuid)


func test_new_tag_and_english_and_130() -> void:
	var pr: PlayerProfile = DEMO.demo_profile()
	var hub := await _open(pr)
	var p: Hub2ArsenalPanel = hub.panels.arsenal
	var news := 0
	for c in p.cards:
		if c.data.get("is_new", false):
			news += 1
	assert_true(news >= 1, "NEUF sur les armes jamais vues")
	assert_true(hub.top_bar.badges.get("arsenal", false), "pastille de l'onglet")
	Settings.language = "en"
	hub.rebuild()
	await wait_frames(3)
	p = hub.panels.arsenal
	assert_eq(p.name_text, "CLEAVER", "nom anglais")
	assert_eq((p.tab_buttons[Hub2ArsenalPanel.WEAPONS].get_meta("face") as Hub2ArsenalPanel.TabFace).label, "WEAPONS")
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.3
	await wait_frames(4)
	p = hub.panels.arsenal
	assert_eq(p.rail.visible, 3, "130 % : 3 colonnes")
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(1.0)
	var bad := []
	_scan(p, screen, bad)
	assert_true(bad.is_empty(), "130 %% : rien ne sort de l'écran %s" % str(bad.slice(0, 4)))


func _scan(n: Node, screen: Rect2, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		if not screen.encloses(c.get_global_rect()):
			bad.append("%s %s" % [c.name, c.get_global_rect()])
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_scan(ch, screen, bad)


func _pad_event(hub: Hub2Screen, button: JoyButton) -> bool:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	return hub.handle_event(ev)
