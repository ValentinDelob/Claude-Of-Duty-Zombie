extends TestCase
## Inventaire de partie v2 (docs/hub_v2/InventaireJeu.dc.html) : statistiques
## de la fiche comparées à l'arme en main (vert mieux, rouge moins bien,
## recharge plus courte = mieux), cases des pièces (nom, effets), touches des
## invites (touche d'inventaire réelle, réaffectable), touches 1 · 2 · 3,
## case dessinée (tailles de la maquette, NEUF, niveau trop élevé).


func _line(lines: Array, key: String) -> Dictionary:
	for l in lines:
		if l.key == key:
			return l
	return {}


func test_compare_lines_vs_hand_weapon() -> void:
	var was := Settings.language
	Settings.language = "fr"
	var shotgun := GameWeapon.make("stakeout", 1)
	var pistol := GameWeapon.make("m1911", 1)
	var lines := InventoryPanel.compare_lines(shotgun, pistol)
	assert_eq(lines.size(), 6, "six statistiques")
	assert_eq(lines.map(func(l): return l.key), Hub2ArsenalView.STATS, "ordre de la maquette")
	var dmg := _line(lines, "damage")
	var sd := float(GameWeapon.stats(shotgun).damage)
	var pdmg := float(GameWeapon.stats(pistol).damage)
	assert_eq(dmg.value, Hub2ArsenalView.format_value("damage", sd), "valeur effective de l'arme montrée")
	assert_eq(dmg.mod, Hub2ArsenalView.format_mod("damage", sd - pdmg), "écart à l'arme en main")
	assert_eq(dmg.good, sd > pdmg, "plus de dégâts : vert")
	var rel := _line(lines, "reload")
	var d := float(GameWeapon.stats(shotgun).reload) - float(GameWeapon.stats(pistol).reload)
	if absf(d) >= 0.05:
		assert_eq(rel.good, d < 0.0, "recharge : plus court = mieux")
		assert_true(String(rel.mod).begins_with("+ " if d > 0.0 else "− "), "signe de l'écart (%s)" % rel.mod)
	assert_eq(_line(lines, "rpm").icon, Hub2ArsenalView.ICONS.rpm, "icône de l'ARSENAL")
	Settings.language = was


func test_compare_lines_without_hand_weapon() -> void:
	var lines := InventoryPanel.compare_lines(GameWeapon.make("mp40", 3), {})
	for l in lines:
		assert_eq(l.mod, "", "pas de comparaison : aucun écart (%s)" % l.key)
	assert_true(InventoryPanel.compare_lines({}, {}).is_empty())
	# Même arme : écarts nuls, rien d'affiché.
	var w := GameWeapon.make("mp40", 3)
	for l in InventoryPanel.compare_lines(w, w.duplicate(true)):
		assert_eq(l.mod, "", "même arme : %s" % l.key)


## Fiche complète (DÉTAILS) dans l'inventaire : valeurs effectives, écart à
## l'arme en main comme les six statistiques (recul et mise en joue : plus
## petit = mieux), lignes propres à la famille, aucun écart sans arme comparée.
func test_compare_detail_lines() -> void:
	var was := Settings.language
	Settings.language = "fr"
	var nb := String.chr(0xA0)
	var shotgun := GameWeapon.make("stakeout", 1)
	var pistol := GameWeapon.make("cz75", 1)
	var lines := InventoryPanel.compare_detail_lines(shotgun, pistol)
	assert_eq(_line(lines, "fire_mode").value, "POMPE")
	assert_eq(_line(lines, "fire_mode").mod, "", "mode de tir : pas d'écart")
	assert_eq(_line(lines, "pellets").value, "8")
	assert_eq(_line(lines, "pellets").mod, "", "le pistolet n'a pas de plombs : pas d'écart")
	var hm := _line(lines, "head_mult")
	assert_eq(hm.value, "×" + nb + "1,5")
	assert_eq(hm.mod, "− 1,5", "× 1,5 contre × 3")
	assert_false(hm.good)
	var ads := _line(lines, "ads_time")
	assert_eq(ads.mod, "+ 0,05", "0,20 s contre 0,15 s")
	assert_false(ads.good, "mise en joue plus longue : rouge")
	var rc := _line(lines, "recoil")
	assert_true(String(rc.mod).begins_with("+ ") and not rc.good, "recul plus fort : rouge (%s)" % rc.mod)
	assert_eq(_line(lines, "penetration").mod, "", "même pénétration : rien")
	# Pièce de recul sur l'arme montrée : valeur effective.
	var light := GameWeapon.make("cz75", 1, 0, [{"id": "crosse", "level": 2, "mods": {"recoil": 0.25}}])
	assert_eq(_line(InventoryPanel.compare_detail_lines(light, {}), "recoil").value, "1,4°", "1,8 ÷ 1,25 (effective)")
	for l in InventoryPanel.compare_detail_lines(GameWeapon.make("mp40", 3), {}):
		assert_eq(l.mod, "", "pas de comparaison : aucun écart (%s)" % l.key)
	var bat := InventoryPanel.compare_detail_lines(GameWeapon.make("bat", 1), pistol)
	assert_eq(bat.map(func(l): return l.key), ["energy", "swings", "lunge_range", "targets", "move_mult"], "batte")
	assert_true(InventoryPanel.compare_detail_lines({}, pistol).is_empty())
	Settings.language = was


func test_level_and_parts_count_in_compare() -> void:
	var lo := GameWeapon.make("mp40", 1)
	var hi := GameWeapon.make("mp40", 11)
	var dmg := _line(InventoryPanel.compare_lines(hi, lo), "damage")
	assert_true(dmg.good and String(dmg.mod).begins_with("+ "), "niveau 11 contre 1 : dégâts en hausse (%s)" % dmg.mod)
	var worse := _line(InventoryPanel.compare_lines(lo, hi), "damage")
	assert_true(not worse.good and String(worse.mod).begins_with("− "), "moins bien : rouge, « − » (%s)" % worse.mod)


func test_part_view() -> void:
	var was := Settings.language
	Settings.language = "fr"
	var v := InventoryPanel.part_view({"id": "p", "uid": "x1", "level": 3, "mods": {"fire_rate": 0.06, "recoil": -0.04}})
	assert_true(String(v.name).ends_with("niv. 3"), "nom et niveau : %s" % v.name)
	assert_eq(v.effects.size(), 2, "deux effets")
	assert_true(String(v.effects[0][0]).contains("cadence") and v.effects[0][1], "effet principal en premier, bénéfique : %s" % [v.effects[0]])
	Settings.language = "en"
	v = InventoryPanel.part_view({"id": "p", "level": 3, "mods": {"damage": 0.08}})
	assert_true(String(v.name).ends_with("lvl 3") and String(v.effects[0][0]).contains("damage"), "anglais : %s" % [v])
	Settings.language = was


func test_prompt_keys_follow_bindings() -> void:
	assert_eq(InventoryPanel.close_keys(), PackedStringArray([Settings.code_label(Settings.key_code(KEY_I))]), "I par défaut")
	assert_eq(InventoryPanel.close_pads(), [JOY_BUTTON_DPAD_UP], "croix haut par défaut")
	Settings.bind("inventory", Settings.key_code(KEY_K))
	assert_eq(InventoryPanel.close_keys()[0], Settings.code_label(Settings.key_code(KEY_K)), "touche réaffectée")
	Settings.reset_bindings()
	assert_eq(InventoryPanel.slot_key(0), Settings.code_label(Settings.binding("weapon_1")), "touche 1")
	assert_eq(InventoryPanel.weapon_title(GameWeapon.make("m1911")), BuildStation.weapon_name(GameWeapon.make("m1911")).to_upper())


func test_slot_sizes_and_tags() -> void:
	var was := Settings.menu_ui_scale
	for f in [1.0, 1.3]:
		Settings.menu_ui_scale = f
		var h := InventorySlot.new()
		h.setup(InventorySlot.Kind.HAND)
		var b := InventorySlot.new()
		b.setup(InventorySlot.Kind.BAG)
		var p := InventorySlot.new()
		p.setup(InventorySlot.Kind.PART)
		host.add_child(h)
		host.add_child(b)
		host.add_child(p)
		assert_eq(h.custom_minimum_size.y, Hub2Style.px(168), "en main : 168 px (%.0f %%)" % (f * 100))
		assert_eq(b.custom_minimum_size.y, Hub2Style.px(134), "sac : 134 px")
		b.show_item(GameWeapon.make("m14", 9, OwnedWeapon.Rarity.EPIC, [], "u1"), InventorySlot.Look.ON, true, true)
		assert_true(b.is_new and b.too_high, "NEUF et niveau trop élevé")
		b.show_item({}, InventorySlot.Look.NORMAL, true)
		assert_false(b.is_new, "case vide : jamais NEUVE")
		p.show_item({"name": "Ressort · niv. 3", "effects": [["+6 % cadence", true]]}, InventorySlot.Look.NORMAL)
		assert_true(p.custom_minimum_size.x >= Hub2Style.px(190), "pièce : 190 px au moins")
		await wait_frames(1)
		for n in [h, b, p]:
			n.queue_free()
	Settings.menu_ui_scale = was
