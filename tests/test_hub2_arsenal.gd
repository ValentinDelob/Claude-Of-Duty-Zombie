extends TestCase
## ARSENAL du hub v2 (docs/hub_v2/Arsenal.dc.html, docs/HUB_PLAN.md §9) :
## rail par niveau (groupement, ordre rareté puis score, ◄ ► / ▲ ▼, fenêtre de
## 5 colonnes, flèches ‹ ›, saut de la vue d'ensemble, colonnes à 130 %),
## filtres, statistiques de la fiche (valeur de base + modificateur « + N »
## vert / « − N » rouge sans unité, recharge plus longue = rouge, unités
## /min, %, m, s, corps à corps « — »), effets et qualité des pièces, et le
## panneau dans le hub : cartes, navigation clavier / manette, fiche,
## installer (aperçu), retirer et recycler en deux appuis, armes de base,
## sous-onglet PIÈCES, NEUF, anglais, 130 % ; VOIR DANS L'ARSENAL
## (show_item : sous-onglet, filtre, sélection).

var _saved := {}


## Profil de la maquette : niveau 23 ; armes de la maquette (modèles réels
## du jeu) rangées par niveau, pièces en stock de plusieurs niveaux.
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(23) + int(PlayerProfile.xp_to_next(23) * 0.643)
	var R := OwnedWeapon.Rarity
	var specs := [
		["mp40", 1, R.COMMON, [], false],
		["olympia", 3, R.RARE, [[3, {"damage": 0.06}]], false],
		["m14", 5, R.COMMON, [], false],
		["cz75", 8, R.RARE, [[6, {"fire_rate": 0.1}], [8, {"mag": 0.2}]], false],
		["m16", 12, R.EPIC, [[10, {"accuracy": 0.15}], [11, {"damage": 0.1}]], false],
		["m14", 14, R.RARE, [[12, {"reload": 0.12}]], false],
		["stakeout", 18, R.RARE, [], true],
		["python", 20, R.LEGENDARY, [[18, {"damage": 0.08}], [18, {"fire_rate": 0.06, "reload": -0.12}]], false],
		["python", 20, R.RARE, [[15, {"damage": 0.05}]], false],
		["spectre", 20, R.EPIC, [], true],
		["galil", 24, R.UNIQUE, [], true],
		["m14", 24, R.EPIC, [], false],
	]
	for s in specs:
		var w := OwnedWeapon.create(s[0], s[1], s[2])
		for pp in s[3]:
			var mods: Dictionary = pp[1]
			w.parts.append(WeaponPart.create("part_" + String(mods.keys()[0]), int(pp[0]), mods))
		pr.add_weapon(w)
		if not s[4]:
			pr.mark_weapon_seen(w.uid)
		for p in w.parts:
			pr.mark_part_seen(p.uid)
	for pp in [[3, {"damage": 0.12}], [7, {"fire_rate": 0.08, "accuracy": -0.05}], [7, {"mag": 0.25}],
			[12, {"reload": 0.2}], [18, {"accuracy": 0.18, "damage": 0.05}], [22, {"damage": 0.22}]]:
		var mods2: Dictionary = pp[1]
		var p2 := WeaponPart.create("part_" + String(mods2.keys()[0]), int(pp[0]), mods2)
		pr.add_part(p2)
		if int(pp[0]) != 22:
			pr.mark_part_seen(p2.uid)
	return pr
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
	Hub2WeaponDetails.reset_session()


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
	mh.current_name = "hub"
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


## Ligne `key` de la fiche complète ({} : absente).
func _detail(lines: Array, key: String) -> Dictionary:
	for l in lines:
		if l.key == key:
			return l
	return {}


func _keys(lines: Array) -> Array:
	return lines.map(func(l): return l.key)


func test_detail_lines_firearm_base_plus_parts() -> void:
	var nb := String.chr(0xA0)
	# MÉTRONOME (fusil d'assaut semi-auto) : crosse (recul +25 %), réserve +20 %.
	var w := _w("m14", 5, 1, [WeaponPart.create("part_recoil", 3, {"recoil": 0.25}),
		WeaponPart.create("part_reserve", 2, {"reserve": 0.2})])
	var lines := Hub2ArsenalView.detail_lines(w)
	assert_eq(_keys(lines), ["head_mult", "fire_mode", "recoil", "ads_time", "reserve", "penetration", "move_mult"],
			"lignes d'une arme à feu sans plombs ni explosion, ordre d'affichage")
	assert_eq(_detail(lines, "head_mult").label, "TIR À LA TÊTE")
	assert_eq(_detail(lines, "head_mult").value, "×" + nb + "2,5")
	assert_eq(_detail(lines, "fire_mode").value, "SEMI-AUTO")
	var rc := _detail(lines, "recoil")
	assert_eq(rc.value, "2,2°", "recul de BASE en degrés")
	assert_eq(rc.mod, "− 0,4", "pièce : recul ÷ 1,25 (2,2 -> 1,76), sans unité")
	assert_true(rc.good, "recul plus faible : turquoise")
	assert_eq(_detail(lines, "ads_time").value, "0,22" + nb + "s")
	var rs := _detail(lines, "reserve")
	assert_eq(rs.value, "96")
	assert_eq(rs.mod, "+ 19", "réserve 96 × 1,2 = 115")
	assert_true(rs.good)
	assert_eq(_detail(lines, "penetration").value, "2" + nb + "zombies")
	assert_eq(_detail(lines, "move_mult").value, "95" + nb + "%", "mobilité en %")
	for k in ["head_mult", "ads_time", "penetration", "move_mult"]:
		assert_eq(_detail(lines, k).mod, "", "aucune pièce n'y touche : %s" % k)
	assert_true(_detail(lines, "ref").is_empty(), "pas de référence réelle tant que l'arme n'est pas refaite")
	# Malus de recul (−20 %) : recul plus fort, rouge.
	var bad := _detail(Hub2ArsenalView.detail_lines(_w("m14", 5, 1, [WeaponPart.create("part_recoil", 3, {"recoil": -0.2})])), "recoil")
	assert_true(String(bad.mod).begins_with("+ ") and not bad.good, "recul plus fort : « + » rouge (%s)" % bad.mod)
	# Niveau : la valeur de base suit les dégâts seulement (rien ici ne change).
	assert_eq(_detail(Hub2ArsenalView.detail_lines(_w("m14", 30, 1)), "reserve").value, "96")


func test_detail_fire_modes_shotgun_explosive_reference() -> void:
	var nb := String.chr(0xA0)
	var mode := func(id: String) -> String:
		return _detail(Hub2ArsenalView.detail_lines(_w(id, 1, 0)), "fire_mode").value
	assert_eq(mode.call("m16"), "RAFALE DE 3")
	assert_eq(mode.call("mp40"), "AUTO")
	assert_eq(mode.call("cz75"), "SEMI-AUTO")
	assert_eq(mode.call("stakeout"), "POMPE", "réarmement à la pompe (cycle)")
	assert_eq(mode.call("l96a1"), "VERROU", "culasse à verrou (cycle)")
	# Fusil à pompe : plombs ; explosifs : zone, sans plombs.
	var sg := Hub2ArsenalView.detail_lines(_w("olympia", 3, 0))
	assert_eq(_detail(sg, "pellets").value, "8")
	assert_eq(_detail(sg, "penetration").value, "1" + nb + "zombie", "singulier")
	assert_true(_detail(sg, "splash_radius").is_empty())
	var gl := Hub2ArsenalView.detail_lines(_w("china_lake", 38, 0))
	assert_eq(_detail(gl, "splash_radius").label, "ZONE D'EXPLOSION")
	assert_eq(_detail(gl, "splash_radius").value, "3" + nb + "m")
	assert_true(_detail(gl, "pellets").is_empty())
	assert_eq(_detail(Hub2ArsenalView.detail_lines(_w("law", 50, 0)), "splash_radius").value, "3,5" + nb + "m")
	# Référence réelle : seulement si elle existe, pleine largeur, en dernier.
	assert_eq(WeaponDB.real_ref("m1911"), "Colt M1911A1")
	assert_eq(WeaponDB.real_ref("mp40"), "")
	var pistol := Hub2ArsenalView.detail_lines(BaseWeapons.make("m1911"))
	var ref: Dictionary = pistol[pistol.size() - 1]
	assert_eq(ref.key, "ref")
	assert_eq(ref.value, "Réf. Colt M1911A1")
	assert_true(ref.wide)


func test_detail_lines_melee() -> void:
	var nb := String.chr(0xA0)
	var bat := Hub2ArsenalView.detail_lines(BaseWeapons.make("bat"))
	assert_eq(_keys(bat), ["energy", "swings", "lunge_range", "targets", "move_mult"],
			"corps à corps : ni tir à la tête, ni mode de tir, ni recul, ni réserve…")
	assert_eq(_detail(bat, "energy").label, "ÉNERGIE PAR COUP")
	assert_eq(_detail(bat, "energy").value, "15")
	assert_eq(_detail(bat, "swings").value, "1,25", "75 coups par minute")
	assert_eq(_detail(bat, "lunge_range").value, "3" + nb + "m")
	assert_eq(_detail(bat, "targets").value, "2" + nb + "zombies")
	assert_eq(_detail(bat, "move_mult").value, "100" + nb + "%")
	# Cadence +10 % : 75 -> 83 coups par minute, + 0,13 coup par seconde.
	var fast := _detail(Hub2ArsenalView.detail_lines(_w("bat", 1, 0, [WeaponPart.create("part_fire_rate", 2, {"fire_rate": 0.1})])), "swings")
	assert_eq(fast.mod, "+ 0,13")
	assert_true(fast.good)


func test_detail_english_and_mod_rules() -> void:
	var nb := String.chr(0xA0)
	assert_eq(Hub2ArsenalView.format_detail_mod("recoil", 0.01), "", "nul une fois arrondi : rien")
	assert_eq(Hub2ArsenalView.format_detail_mod("reserve", 0.4), "")
	assert_eq(Hub2ArsenalView.format_detail_mod("ads_time", -0.05), "− 0,05")
	assert_true(Hub2ArsenalView.detail_good("ads_time", -0.05), "mise en joue plus courte : mieux")
	assert_false(Hub2ArsenalView.detail_good("recoil", 0.3), "recul plus fort : moins bien")
	assert_true(Hub2ArsenalView.detail_good("reserve", 10.0))
	Settings.language = "en"
	var lines := Hub2ArsenalView.detail_lines(_w("m14", 5, 1, [WeaponPart.create("part_recoil", 3, {"recoil": 0.25})]))
	assert_eq(_detail(lines, "head_mult").label, "HEADSHOT")
	assert_eq(_detail(lines, "head_mult").value, "×" + nb + "2.5")
	assert_eq(_detail(lines, "recoil").value, "2.2°")
	assert_eq(_detail(lines, "recoil").mod, "− 0.4")
	assert_eq(_detail(lines, "ads_time").value, "0.22" + nb + "s")
	assert_eq(_detail(lines, "move_mult").value, "95%")
	assert_eq(_detail(lines, "move_mult").label, "MOBILITY")
	assert_eq(_detail(Hub2ArsenalView.detail_lines(_w("m16", 12, 0)), "fire_mode").value, "3-ROUND BURST")
	assert_eq(_detail(Hub2ArsenalView.detail_lines(_w("stakeout", 4, 0)), "fire_mode").value, "PUMP-ACTION")
	assert_eq(_detail(Hub2ArsenalView.detail_lines(_w("l96a1", 27, 0)), "fire_mode").value, "BOLT-ACTION")
	assert_eq(_detail(Hub2ArsenalView.detail_lines(_w("bat", 1, 0)), "swings").label, "SWINGS PER SECOND")
	var pistol := Hub2ArsenalView.detail_lines(BaseWeapons.make("m1911"))
	assert_eq(pistol[pistol.size() - 1].value, "Ref. Colt M1911A1")
	assert_eq(Hub2WeaponDetails.toggle_text(false), "DETAILS")
	assert_eq(Hub2WeaponDetails.toggle_text(true), "HIDE")


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


## Largeur d'une colonne du rail à la taille des menus courante (comme
## Hub2ArsenalPanel._fit_columns : 135 px à 100 %).
func _col_width() -> float:
	var section := 1280.0 - Hub2Style.px(28) * 2.0 - Hub2Style.px(20) - Hub2Style.px(384) - Hub2Style.px(1) * 2.0
	var rail_w := section - Hub2Style.px(1) * 2.0 - Hub2Style.px(36) * 2.0 - Hub2Style.px(6) * 2.0
	var n := Hub2ArsenalRail.fit_visible(rail_w, Hub2Style.px(135), Hub2Style.px(14))
	return floorf((rail_w - (n - 1) * Hub2Style.px(14)) / n)


func test_rail_cards_never_truncate_names_or_rarity() -> void:
	var checked := 0
	for lang in ["fr", "en"]:
		Settings.language = lang
		for factor in [1.0, 1.3]:
			Settings.menu_ui_scale = factor
			var cw := _col_width()
			for id in WeaponDB.WEAPONS.keys():
				for r in 5:
					for locked in [false, true]:
						var card := Hub2ArsenalCard.new()
						card.size = Vector2(cw, 100)
						var slots := OwnedWeapon.slots_for(r)
						card.setup({"name": HubGear.weapon_name(id), "color": Hub2Style.rarity_color(r),
							"kind_name": GameWeapon.rarity_name(r), "img": null, "is_new": true, "base": false,
							"locked": locked, "required": Hub2ArsenalView.required_text(50), "score": "250",
							"slots": slots, "filled": slots})
						var texts := card.shown_texts()
						var joined := " | ".join(texts)
						assert_false(joined.contains("…"), "%s %s %d %.1f : pas de « … » (%s)" % [lang, id, r, factor, joined])
						assert_true(card.texts_fit(), "%s %s %d %.1f verrouillée %s : tout tient dans %.0f px (%s)" % [
							lang, id, r, factor, locked, cw, joined])
						var lay := card.layout(Hub2ArsenalCard.inner_width(cw))
						assert_true(float(lay.name.size) >= Hub2ArsenalCard.NAME_MIN, "nom lisible (%s)" % id)
						card.free()
						checked += 1
			# Cartes de pièce : nom, qualité et effets.
			for k in LootRules.PART_MODS:
				for q in 3:
					var p := WeaponPart.create("part_" + k, 10, {k: 0.25, "reload": -0.25})
					var card2 := Hub2ArsenalCard.new()
					card2.size = Vector2(cw, 100)
					card2.setup({"name": HubGear.part_name(p).to_upper(), "color": Hub2ArsenalView.quality_color(q),
						"kind_name": Hub2ArsenalView.quality_name(q), "part_art": true, "is_new": true, "score": "",
						"slots": 0, "filled": 0, "effects": Hub2ArsenalView.effects(p)})
					assert_true(card2.texts_fit(), "%s pièce %s %.1f : tout tient" % [lang, k, factor])
					card2.free()
	assert_true(checked > 300, "toutes les armes, raretés, langues, tailles (%d)" % checked)


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
	var pr: PlayerProfile = demo_profile()
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


## Fiche complète dans le panneau : fermée au départ, D / R3 / invite / clic
## l'ouvrent et la ferment, état retenu d'une arme à l'autre (session), la
## fiche ouverte reste dans le panneau (elle défile), invite DÉTAILS / MASQUER.
func test_panel_details_toggle() -> void:
	var hub := await _open(demo_profile())
	var p: Hub2ArsenalPanel = hub.panels.arsenal
	var d := p.details
	assert_true(d != null and d.visible, "fiche d'arme : composant DÉTAILS")
	assert_false(d.open, "fermée au départ")
	assert_false(d.body.visible)
	assert_eq(d.title.text, "DÉTAILS")
	assert_true(" ".join(hub.prompts.describe()).contains("D DÉTAILS"), "invite : %s" % " ".join(hub.prompts.describe()))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	assert_true(hub.handle_event(key), "D : consommé")
	await wait_frames(2)
	assert_true(d.open and d.body.visible, "D : ouverte")
	assert_eq(d.title.text, "MASQUER")
	assert_eq(d.cells.size(), 7, "COUPERET : sept lignes (sans plombs ni zone)")
	assert_true(" ".join(hub.prompts.describe()).contains("D MASQUER"), "invite : %s" % " ".join(hub.prompts.describe()))
	# Ouverte : la fiche reste dans le panneau (elle défile), le panneau dans l'écran.
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	assert_true(screen.grow(1.0).encloses(p.aside.get_global_rect()), "fiche dans l'écran : %s" % p.aside.get_global_rect())
	assert_true(p.aside.get_global_rect().grow(1.0).encloses(p.aside_scroll.get_global_rect()), "zone qui défile dans la fiche")
	# Autre arme : toujours ouverte (session).
	_nav(p.selected_card(), "ui_down")
	await wait_frames(2)
	assert_true(p.details != d and p.details.open, "état retenu d'une arme à l'autre")
	d = p.details
	# Manette : R3 ferme ; invite cliquée et clic sur le titre rouvrent / referment.
	Settings.using_pad = true
	hub.refresh_prompts()
	assert_true(" ".join(hub.prompts.describe()).contains("RS MASQUER"), "invite manette : %s" % " ".join(hub.prompts.describe()))
	assert_true(_pad_event(hub, JOY_BUTTON_RIGHT_STICK))
	assert_false(d.open, "R3 : fermée")
	p.on_prompt(Hub2Input.DETAILS)
	assert_true(d.open, "invite cliquée : ouverte")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	d.title._gui_input(mb)
	assert_false(d.open, "clic sur le titre : fermée")
	assert_false(Hub2WeaponDetails.is_open_for(Hub2ArsenalPanel.DETAILS_SCREEN))
	# Onglet PIÈCES : pas de fiche d'arme, D ne fait rien.
	p.set_tab(Hub2ArsenalPanel.PARTS)
	await wait_frames(2)
	assert_true(p.details == null)
	assert_false(p.toggle_details())


func test_install_remove_recycle() -> void:
	var pr: PlayerProfile = demo_profile()
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
	var pr: PlayerProfile = demo_profile()
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


## VOIR DANS L'ARSENAL (show_item) : la pièce ou l'arme montrée, sous-onglet
## changé, filtre remis à TOUTES s'il la cachait ; objet inconnu : rien.
func test_show_item() -> void:
	var pr: PlayerProfile = demo_profile()
	var hub := await _open(pr)
	var p: Hub2ArsenalPanel = hub.panels.arsenal
	var part: WeaponPart = pr.parts[-1]
	assert_true(p.show_item(part.uid), "pièce trouvée")
	assert_eq(p.tab, Hub2ArsenalPanel.PARTS, "sous-onglet PIÈCES")
	assert_eq(p.selected_part().uid, part.uid, "pièce choisie")
	var w: OwnedWeapon = pr.weapons[0]
	p.set_tab(Hub2ArsenalPanel.WEAPONS)
	p.set_filter("melee")
	assert_true(p.show_item(w.uid), "arme trouvée")
	assert_eq(p.tab, Hub2ArsenalPanel.WEAPONS)
	assert_eq(p.filter, "all", "filtre qui la cachait remis à TOUTES")
	assert_eq(p.selected_weapon().uid, w.uid, "arme choisie")
	assert_eq(p.rail.selected_level(), w.level, "fenêtre sur son niveau")
	assert_false(p.show_item("w_inconnue"), "objet inconnu")
	assert_eq(p.selected_weapon().uid, w.uid, "sélection gardée")


func test_new_tag_and_english_and_130() -> void:
	var pr: PlayerProfile = demo_profile()
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
