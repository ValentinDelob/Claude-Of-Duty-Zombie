extends TestCase
## Onglets ARSENAL, PIÈCES et DÉPART du hub (docs/HUB_PLAN.md §3.2, §3.3,
## §3.6, lot C) : filtres et tri de l'arsenal, versions, montage refusé avec
## sa raison, montage accepté, retrait = pièce détruite en deux appuis,
## recyclage en deux appuis refusé sur une arme de base, 1 à 3 armes de
## départ, pastilles NOUVEAU, une seule écriture du profil par action (le
## profil enregistré reflète l'action), INSTALLER SUR… depuis PIÈCES.
## Le profil est enregistré dans un fichier de test (TestHub), jamais celui
## du joueur.

const TMP_PROFILE := "user://profile_hub_arsenal_unittest.json"

var _saved := {}
var _frame: Control
var _host: FakeHost


class FakeHost extends MenuHost:
	var shown: Array = []

	func show_screen(screen_name: String, _args := {}, _remember := true) -> void:
		shown.append(screen_name)

	func set_hint(_t: String) -> void:
		pass


## Hub dont le profil s'enregistre dans un fichier de test ; compte les
## écritures.
class TestHub extends HubScreen:
	var saves := 0

	func save_profile() -> Error:
		saves += 1
		var err := ProfileStore.save_profile(profile, TMP_PROFILE)
		_profile_updated()
		return err


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
	HubScreen.last_tab = "lab"
	for f in [TMP_PROFILE, ProfileStore.backup_path(TMP_PROFILE)]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


## Profil de la maquette (niveau 7) : FRELON épique niv. 7 (2 pièces) et sa
## version 2 rare niv. 5, SIROCCO rare 6, MAMBA légendaire 9 (verrouillée),
## CARNAGE commune 3, VIEILLE GARDE commune 4 ; 5 pièces en stock.
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 2140
	var w := OwnedWeapon.create("mp5k", 7, OwnedWeapon.Rarity.EPIC)
	w.parts.append(WeaponPart.create("part_damage", 6, {"damage": 0.15}))
	w.parts.append(WeaponPart.create("part_fire_rate", 5, {"fire_rate": 0.1, "accuracy": -0.06}))
	pr.add_weapon(w)
	pr.add_weapon(OwnedWeapon.create("mp5k", 5, OwnedWeapon.Rarity.RARE))
	pr.add_weapon(OwnedWeapon.create("m16", 6, OwnedWeapon.Rarity.RARE))
	pr.add_weapon(OwnedWeapon.create("python", 9, OwnedWeapon.Rarity.LEGENDARY))
	pr.add_weapon(OwnedWeapon.create("stakeout", 3, OwnedWeapon.Rarity.COMMON))
	pr.add_weapon(OwnedWeapon.create("m14", 4, OwnedWeapon.Rarity.COMMON))
	for p in [["damage", 9, 0.22], ["mag", 7, 0.2], ["accuracy", 6, 0.12], ["recoil", 4, 0.18], ["reload", 2, 0.07]]:
		pr.add_part(WeaponPart.create("part_" + p[0], p[1], {p[0]: p[2]}))
	pr.mark_all_seen()
	return pr


func _open(tab: String, pr: PlayerProfile) -> TestHub:
	_frame = Control.new()
	_frame.size = Vector2(1280, 720)
	host.add_child(_frame)
	_host = FakeHost.new()
	_host.size = Vector2(1280, 720)
	_frame.add_child(_host)
	var hub := TestHub.new()
	hub.menu = _host
	hub.size = Vector2(1280, 720)
	_host.add_child(hub)
	_host.current = hub
	_host.current_name = "hub"
	hub.enter({"tab": tab, "profile": pr})
	await wait_frames(3)
	return hub


func _names(panel: HubArsenalPanel) -> Array:
	var out := []
	for r in panel.rows:
		var w := panel.profile().get_weapon((r as HubPickRow).key)
		out.append("%s:%d" % [w.weapon_id, w.level])
	return out


func _saved_profile() -> PlayerProfile:
	return ProfileStore.load_profile(TMP_PROFILE)


func _focus(hub: HubScreen) -> Control:
	return hub.get_viewport().gui_get_focus_owner()


# --------------------------------------------------------------------------
# Règles d'affichage (HubGear)
# --------------------------------------------------------------------------

func test_filters() -> void:
	var pr := demo_profile()
	var base := BaseWeapons.all()
	var knife: OwnedWeapon = base[1]
	assert_true(HubGear.passes(knife, "melee", 7) and not HubGear.passes(knife, "firearm", 7), "couteau : corps à corps")
	var mamba := pr.weapons[3]
	assert_false(HubGear.passes(mamba, "usable", pr.level()), "niveau 9 > 7 : pas utilisable")
	assert_true(HubGear.passes(mamba, "firearm", pr.level()))
	var all := 0
	for g in HubGear.arsenal_groups(pr, "usable", "score"):
		all += g.versions.size()
	assert_eq(all, 5, "UTILISABLES : 6 armes moins MAMBA")
	assert_eq(HubGear.arsenal_groups(pr, "melee", "score").size(), 0, "aucune arme de corps à corps dans l'arsenal")


func test_sort_groups_versions() -> void:
	var pr := demo_profile()
	var ids := []
	for g in HubGear.arsenal_groups(pr, "all", "score"):
		for w in g.versions:
			ids.append("%s:%d" % [w.weapon_id, w.score()])
	# Les versions d'une même arme se suivent ; groupes rangés par score.
	assert_eq(ids, ["mp5k:18", "mp5k:5", "python:9", "m16:6", "m14:4", "stakeout:3"], "SCORE")
	var by_score := []
	for g in HubGear.arsenal_groups(pr, "all", "score"):
		by_score.append(g.versions[0].score())
	for i in by_score.size() - 1:
		assert_true(by_score[i] >= by_score[i + 1], "groupes par score décroissant %s" % str(by_score))
	var by_level := []
	for g in HubGear.arsenal_groups(pr, "all", "level"):
		by_level.append(g.versions[0].level)
	assert_eq(by_level, [9, 7, 6, 4, 3], "NIVEAU")
	var by_rarity := []
	for g in HubGear.arsenal_groups(pr, "all", "rarity"):
		by_rarity.append(int(g.versions[0].rarity))
	assert_eq(by_rarity, [3, 2, 1, 0, 0], "RARETÉ")
	var by_name := []
	for g in HubGear.arsenal_groups(pr, "all", "name"):
		by_name.append(HubGear.weapon_name(g.id))
	var sorted := by_name.duplicate()
	sorted.sort()
	assert_eq(by_name, sorted, "NOM")
	var v := HubGear.version_of(pr, pr.weapons[1])
	assert_eq(v, Vector2i(2, 2), "version 2 de 2 (ordre d'arrivée)")


func test_mount_refusal_reasons() -> void:
	var pr := demo_profile()
	var frelon := pr.weapons[0]
	var high := WeaponPart.create("part_damage", 9, {"damage": 0.2})
	assert_eq(HubGear.mount_refusal(frelon, high, 7), "NIVEAU 9 : AU-DESSUS DE L'ARME (7) ET DU VÔTRE (7)")
	assert_eq(HubGear.mount_refusal(pr.weapons[3], high, 7), "NIVEAU 9 : AU-DESSUS DU VÔTRE (7)")
	var mid := WeaponPart.create("part_mag", 6, {"mag": 0.2})
	assert_eq(HubGear.mount_refusal(pr.weapons[1], mid, 7), "NIVEAU 6 : AU-DESSUS DE L'ARME (5)")
	assert_eq(HubGear.mount_refusal(BaseWeapons.make(WeaponDB.STARTING_WEAPON), mid, 7), "ARME DE BASE")
	assert_eq(HubGear.mount_refusal(frelon, mid, 7), "", "montable : 6 ≤ 7 et ≤ 7, un emplacement libre")
	var full := OwnedWeapon.create("m14", 9, OwnedWeapon.Rarity.COMMON)
	full.parts.append(WeaponPart.create("part_damage", 1, {"damage": 0.1}))
	assert_eq(HubGear.mount_refusal(full, mid, 9), "AUCUN EMPLACEMENT LIBRE")
	Settings.language = "en"
	assert_eq(HubGear.mount_refusal(frelon, high, 7), "LEVEL 9: ABOVE THE WEAPON (7) AND YOURS (7)")


func test_part_texts() -> void:
	var p := WeaponPart.create("part_fire_rate", 5, {"fire_rate": 0.1, "accuracy": -0.06})
	assert_eq(HubGear.part_name(p), "Ressort")
	var nb := String.chr(0xA0)
	assert_eq(HubGear.mods_plain(p.mods), "cadence +10%s%% · précision −6%s%%" % [nb, nb])
	assert_eq(HubGear.mod_long("recoil", 0.18), "recul +18%s%% (moins de recul)" % nb)
	Settings.language = "en"
	assert_eq(HubGear.part_name(p), "Spring")
	assert_eq(HubGear.mods_plain(p.mods), "fire rate +10% · accuracy −6%")


func test_effective_stats_with_parts() -> void:
	var w := OwnedWeapon.create("mp5k", 1, OwnedWeapon.Rarity.EPIC)
	var plain := HubGear.stat_lines(w)
	assert_eq(String(plain[0].text), str(int(WeaponDB.stats("mp5k").damage)), "niveau 1 sans pièce : dégâts de base")
	assert_eq(String(plain[0].delta), "")
	w.parts.append(WeaponPart.create("part_damage", 1, {"damage": 0.5}))
	w.parts.append(WeaponPart.create("part_accuracy", 1, {"accuracy": -0.5}))
	var lines := HubGear.stat_lines(w)
	var dmg := roundi(WeaponDB.stats("mp5k").damage * 1.5)
	assert_eq(String(lines[0].text), str(dmg), "dégâts effectifs (GameWeapon.stats)")
	assert_eq(String(lines[0].delta), "+%d" % (dmg - int(WeaponDB.stats("mp5k").damage)))
	assert_true(lines[0].good and lines[0].ratio > lines[0].base_ratio, "bonus : barre plus longue")
	assert_true(not lines[4].good and lines[4].ratio < lines[4].base_ratio, "malus de précision : barre plus courte")
	assert_true(String(lines[4].delta).begins_with("−"), "écart de précision négatif")


# --------------------------------------------------------------------------
# Onglet ARSENAL
# --------------------------------------------------------------------------

func test_arsenal_list_and_sheet() -> void:
	var hub := await _open("arsenal", demo_profile())
	var ars: HubArsenalPanel = hub.panels.arsenal
	assert_true(ars is HubArsenalPanel, "ARSENAL : panneau du lot C")
	assert_eq(ars.rows.size(), 8, "2 armes de base + 6 versions")
	assert_true((ars.rows[0] as HubPickRow).key.begins_with(BaseWeapons.UID_PREFIX), "armes de base en tête")
	assert_eq(_focus(hub), ars.rows[0], "focus initial : première ligne")
	assert_eq(ars.list_box.right_label.text, "8 armes · 6 dans l'arsenal")
	# Choisir FRELON : fiche, score, emplacements.
	var frelon: HubPickRow = ars.rows[2]
	frelon.grab_focus()
	await wait_frames(1)
	assert_eq(ars.sheet.weapon.weapon_id, "mp5k")
	assert_eq(ars.sheet.score_label.text, "18", "score = 7 + 6 + 5")
	assert_eq(ars.sheet.slots.size(), 3, "épique : 3 emplacements")
	assert_false(ars.sheet.slots[0].empty)
	assert_true(ars.sheet.slots[2].empty, "emplacement libre")
	# Filtres (Tab) et tri (R).
	ars.set_filter("melee")
	assert_eq(ars.rows.size(), 1, "CORPS À CORPS : le couteau")
	ars.set_filter("usable")
	assert_eq(ars.rows.size(), 7, "UTILISABLES : sans MAMBA")
	ars.cycle_filter()
	assert_eq(ars.filter, "all")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_R
	ev.pressed = true
	hub._unhandled_input(ev)
	assert_eq(ars.sort, "level", "R : tri suivant")
	assert_eq(_names(ars).slice(2, 4), ["python:9", "mp5k:7"], "tri NIVEAU")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	ars._input(tab)
	assert_eq(ars.filter, "firearm", "Tab : filtre suivant")
	assert_eq(hub.saves, 0, "rien d'enregistré pour un filtre ou un tri")


func test_locked_weapon_sheet() -> void:
	var hub := await _open("arsenal", demo_profile())
	var ars: HubArsenalPanel = hub.panels.arsenal
	var r := ars._row_of(ars.profile().weapons[3].uid)
	assert_true(r.locked, "MAMBA niveau 9 : ligne verrouillée")
	r.grab_focus()
	await wait_frames(1)
	var found := false
	for t in _all(ars.sheet, HubTag):
		found = found or (t as HubTag).text == "NIVEAU 9 REQUIS"
	assert_true(found, "fiche : NIVEAU 9 REQUIS")


func test_mount_refused_then_accepted() -> void:
	var pr := demo_profile()
	var hub := await _open("arsenal", pr)
	var ars: HubArsenalPanel = hub.panels.arsenal
	(ars.rows[2] as HubPickRow).grab_focus()  # FRELON niv. 7
	await wait_frames(1)
	ars.sheet.slots[2].activated.emit()  # emplacement libre
	await wait_frames(1)
	var pk := ars.picker
	assert_true(pk != null and pk.is_inside_tree(), "fenêtre des pièces ouverte")
	await wait_frames(2)
	var rect := pk.panel.get_global_rect()
	assert_near(rect.position.x - hub.global_position.x, 200.0, 1.0, "fenêtre à sa place (maquette : 200, 132)")
	assert_near(rect.position.y - hub.global_position.y, 132.0, 1.0)
	assert_near(rect.size.x, 880.0, 1.0, "880 × 520")
	assert_near(rect.size.y, 520.0, 1.0)
	assert_eq(hub.prompts.describe()[0], "Entrée Installer")
	assert_eq(pk.parts.size(), 5)
	assert_eq(pk.parts[0].level, 7, "montables d'abord, plus haut niveau choisi")
	assert_eq(pk.parts[4].level, 9, "pièce niv. 9 non montable, en dernier")
	assert_true((pk.rows[4] as HubPickRow).locked)
	pk.select(4)
	assert_true(pk.install_button.disabled, "INSTALLER grisé")
	assert_eq(pk.install_button.hint, "NIVEAU 9 : AU-DESSUS DE L'ARME (7) ET DU VÔTRE (7)", "raison écrite")
	(pk.rows[4] as HubPickRow).activated.emit()
	assert_eq(hub.saves, 0, "refus : rien d'enregistré")
	assert_eq(pr.weapons[0].parts.size(), 2)
	# Échap : fermée.
	hub.back()
	assert_true(ars.picker == null, "Échap : fenêtre fermée")
	# Installer la pièce niv. 7 (chargeur).
	ars.open_picker(2)
	pk = ars.picker
	pk.select(0)
	var mag_uid := pk.parts[0].uid
	pk.install_button.pressed.emit()
	await wait_frames(1)
	assert_eq(hub.saves, 1, "une écriture")
	assert_true(ars.picker == null, "fenêtre fermée après l'installation")
	assert_eq(pr.weapons[0].parts.size(), 3)
	assert_true(pr.get_part(mag_uid) == null, "la pièce a quitté l'onglet")
	var disk := _saved_profile()
	assert_eq(disk.weapons[0].parts.size(), 3, "profil enregistré : pièce installée")
	assert_eq(disk.parts.size(), 4)
	assert_eq(ars.sheet.score_label.text, "25", "score 18 + 7")


func test_remove_part_two_presses_destroys() -> void:
	var pr := demo_profile()
	var hub := await _open("arsenal", pr)
	var ars: HubArsenalPanel = hub.panels.arsenal
	(ars.rows[2] as HubPickRow).grab_focus()
	await wait_frames(1)
	var sh := ars.sheet
	var uid := pr.weapons[0].parts[1].uid
	sh.slots[1].grab_focus()
	sh.slots[1].activated.emit()  # premier appui (Entrée sur la pièce)
	assert_eq(sh.armed, HubWeaponSheet.REMOVE)
	assert_eq(sh.remove_button.label, "CONFIRMER : LA PIÈCE SERA DÉTRUITE")
	assert_eq(sh.remove_button.kind, HubButton.DANGER)
	assert_true(sh.slots[1].marked, "pièce visée encadrée")
	assert_eq(hub.prompts.describe()[0], "Entrée Confirmer")
	assert_eq(hub.saves, 0, "premier appui : rien")
	# Échap annule.
	hub.back()
	assert_eq(sh.armed, HubWeaponSheet.NONE, "Échap : annulé")
	assert_eq(pr.weapons[0].parts.size(), 2)
	# Deux appuis sur le bouton.
	sh.target_slot = 1
	sh.remove_button.pressed.emit()
	sh.remove_button.pressed.emit()
	await wait_frames(1)
	assert_eq(hub.saves, 1, "une écriture")
	assert_eq(pr.weapons[0].parts.size(), 1)
	assert_true(pr.get_part(uid) == null, "pièce détruite : pas rendue à l'onglet PIÈCES")
	assert_eq(pr.parts.size(), 5)
	assert_eq(_saved_profile().weapons[0].parts.size(), 1, "profil enregistré")


func test_recycle_two_presses_never_base() -> void:
	var pr := demo_profile()
	var hub := await _open("arsenal", pr)
	var ars: HubArsenalPanel = hub.panels.arsenal
	(ars.rows[0] as HubPickRow).grab_focus()  # arme de base
	await wait_frames(1)
	assert_true(ars.sheet.recycle_button.disabled, "arme de base : RECYCLER grisé")
	ars.sheet.arm(HubWeaponSheet.RECYCLE)
	assert_eq(ars.sheet.armed, HubWeaponSheet.NONE, "jamais armé sur une arme de base")
	var victim := pr.weapons[4]  # CARNAGE
	ars._row_of(victim.uid).grab_focus()
	await wait_frames(1)
	ars.sheet.recycle_button.pressed.emit()
	assert_eq(ars.sheet.recycle_button.label, "CONFIRMER : L'ARME SERA DÉTRUITE")
	assert_eq(pr.weapons.size(), 6, "premier appui : rien")
	ars.sheet.recycle_button.pressed.emit()
	await wait_frames(1)
	assert_eq(hub.saves, 1)
	assert_eq(pr.weapons.size(), 5)
	assert_true(pr.get_weapon(victim.uid) == null, "arme retirée de l'arsenal")
	assert_eq(pr.parts.size(), 5, "rien rapporté")
	assert_eq(_saved_profile().weapons.size(), 5, "profil enregistré")
	assert_eq(ars.rows.size(), 7)


func test_new_badges() -> void:
	var pr := demo_profile()
	var fresh := OwnedWeapon.create("m14", 2, OwnedWeapon.Rarity.COMMON)
	pr.add_weapon(fresh)
	var np := WeaponPart.create("part_reserve", 1, {"reserve": 0.1})
	pr.add_part(np)
	assert_true(pr.is_new_weapon(fresh.uid) and pr.is_new_part(np.uid))
	var hub := await _open("arsenal", pr)
	var ars: HubArsenalPanel = hub.panels.arsenal
	var r := ars._row_of(fresh.uid)
	assert_true(_has_tag(r, "NOUVEAU"), "pastille NOUVEAU")
	assert_false(_has_tag(ars._row_of(pr.weapons[2].uid), "NOUVEAU"), "arme déjà vue : sans pastille")
	r.grab_focus()
	await wait_frames(1)
	assert_false(pr.is_new_weapon(fresh.uid), "vue en l'affichant")
	assert_true(_has_tag(ars._row_of(fresh.uid), "NOUVEAU"), "pastille gardée pendant la visite")
	assert_eq(hub.saves, 0, "pas d'écriture rien que pour la lecture")
	hub.select_tab("parts")
	assert_eq(hub.saves, 1, "en quittant l'onglet : une écriture")
	assert_false(_saved_profile().is_new_weapon(fresh.uid), "enregistrée vue")
	var parts: HubPartsPanel = hub.panels.parts
	var pr_row := parts._row_of(np.uid)
	assert_true(_has_tag(pr_row, "NOUVEAU"), "pièce : pastille NOUVEAU")
	hub.select_tab("arsenal")
	assert_false(_has_tag(ars._row_of(fresh.uid), "NOUVEAU"), "visite suivante : plus de pastille")


# --------------------------------------------------------------------------
# Onglet PIÈCES
# --------------------------------------------------------------------------

func test_parts_tab_and_install_on() -> void:
	var pr := demo_profile()
	var hub := await _open("parts", pr)
	var parts: HubPartsPanel = hub.panels.parts
	assert_true(parts is HubPartsPanel, "PIÈCES : panneau du lot C")
	assert_eq(parts.rows.size(), 5)
	assert_eq(parts.list_box.right_label.text, "5 · illimité")
	assert_eq(pr.get_part((parts.rows[0] as HubPickRow).key).level, 9, "tri NIVEAU décroissant")
	parts.set_filter("mountable")
	assert_eq(parts.rows.size(), 4, "MONTABLES : sans la pièce niv. 9")
	parts.set_filter("all")
	# Amortisseur (recul, niv. 4) : armes compatibles.
	var damper := ""
	for p in pr.parts:
		if p.mods.has("recoil"):
			damper = p.uid
	parts._row_of(damper).grab_focus()
	await wait_frames(1)
	assert_eq(parts.title_label.text, "AMORTISSEUR")
	var compat := []
	for r in parts.weapon_rows:
		compat.append(pr.get_weapon((r as HubPickRow).key).weapon_id)
	assert_eq(compat, ["mp5k", "mp5k", "python", "m16", "m14"], "versions de niveau ≥ 4 avec un emplacement libre, ordre de l'arsenal")
	assert_false(pr.weapons[4].uid in parts.weapon_rows.map(func(r): return r.key), "CARNAGE niv. 3 : non compatible")
	assert_eq(parts.install_button.label, "INSTALLER SUR %s" % HubGear.weapon_name("mp5k"))
	parts.install_button.pressed.emit()
	await wait_frames(2)
	assert_eq(hub.tab, "arsenal", "INSTALLER SUR… : onglet ARSENAL")
	var ars: HubArsenalPanel = hub.panels.arsenal
	assert_true(ars.picker != null, "fenêtre des pièces ouverte")
	assert_eq(ars.picker.parts[ars.picker.selected].uid, damper, "pièce déjà choisie")
	assert_eq(ars.sheet.weapon.uid, pr.weapons[0].uid, "fiche de l'arme choisie")


# --------------------------------------------------------------------------
# Onglet DÉPART
# --------------------------------------------------------------------------

func test_loadout_one_to_three() -> void:
	var pr := demo_profile()
	assert_eq(Array(pr.starting_weapons), Array(BaseWeapons.default_selection()))
	var hub := await _open("loadout", pr)
	var lo: HubLoadoutPanel = hub.panels.loadout
	assert_true(lo is HubLoadoutPanel, "DÉPART : panneau du lot C")
	var n := pr.starting_weapons.size()
	assert_eq(lo.slots.size(), 3, "trois emplacements")
	assert_eq((lo.slots[2] as HubSlot).empty, n < 3, "emplacement non choisi : vide")
	# Retirer jusqu'à une seule arme ; la dernière ne se retire pas.
	var first := pr.starting_weapons[0]
	while pr.starting_weapons.size() > 1:
		assert_true(lo.remove_slot(pr.starting_weapons.size() - 1))
	assert_eq(hub.saves, n - 1, "une écriture par retrait")
	assert_false(lo.remove_slot(0), "la dernière arme reste")
	assert_false(lo.toggle(first), "ni par la liste")
	assert_eq(Array(pr.starting_weapons), [first])
	assert_eq(hub.saves, n - 1, "refus : rien d'enregistré")
	assert_eq(Array(_saved_profile().starting_weapons), [first], "profil enregistré")
	# Ajouter de nouveau.
	for id in BaseWeapons.ids():
		if not id in pr.starting_weapons:
			assert_true(lo.toggle(id))
	assert_eq(pr.starting_weapons.size(), mini(BaseWeapons.ids().size(), 3))
	assert_eq(Array(_saved_profile().starting_weapons), Array(pr.starting_weapons))
	assert_true(BaseWeapons.selection_ok(pr.starting_weapons))
	# Utilisées au lancement : armes en main de Session.starting_hands.
	var hands := Session.starting_hands(pr.starting_weapons)
	assert_true(hands.size() >= 1 and String(hands[0].id) == WeaponDB.STARTING_WEAPON, "pistolet en main au départ")


func test_loadout_station_list() -> void:
	var hub := await _open("loadout", demo_profile())
	var lo: HubLoadoutPanel = hub.panels.loadout
	var tags := []
	for t in _all(lo.station_box, HubTag):
		tags.append((t as HubTag).text)
	assert_eq(tags, ["NIV. 9 REQUIS"], "MAMBA grisé")


# --------------------------------------------------------------------------
# Taille, langue, navigation
# --------------------------------------------------------------------------

func test_tabs_stay_on_screen_80_130() -> void:
	for f in [0.8, 1.3]:
		Settings.menu_ui_scale = f
		for tab in ["arsenal", "parts", "loadout"]:
			var hub := await _open(tab, demo_profile())
			await wait_frames(2)
			var bad := []
			_scan(hub, Rect2(0, 0, 1280, 720).grow(1.0), hub, bad)
			assert_true(bad.is_empty(), "%s à %d %% : rien ne sort de l'écran %s" % [tab, roundi(f * 100.0), str(bad.slice(0, 3))])
			if tab == "arsenal":
				var ars: HubArsenalPanel = hub.panels.arsenal
				(ars.rows[2] as HubPickRow).grab_focus()
				ars.open_picker(2)
				await wait_frames(2)
				bad.clear()
				_scan(ars.picker, Rect2(0, 0, 1280, 720).grow(1.0), hub, bad)
				assert_true(bad.is_empty(), "fenêtre des pièces à %d %% %s" % [roundi(f * 100.0), str(bad.slice(0, 3))])
			_frame.free()


func test_english_texts() -> void:
	Settings.language = "en"
	var hub := await _open("arsenal", demo_profile())
	var ars: HubArsenalPanel = hub.panels.arsenal
	assert_eq(ars.list_box.right_label.text, "8 weapons · 6 in the arsenal")
	assert_eq(ars.filter_bar.chips[0].text, "ALL")
	assert_eq(Array(hub.prompts.describe()).slice(0, 3), ["Enter Select", "Tab Filter", "%s Sort" % HubPrompts.physical_key_name(KEY_R)])
	hub.select_tab("loadout")
	assert_eq(hub.panels.loadout.slots.size(), 3)
	Settings.using_pad = true
	hub.select_tab("arsenal")
	assert_eq(Array(hub.prompts.describe()).slice(0, 3), ["A Select", "Y Filter", "X Sort"])


func test_pad_and_back_navigation() -> void:
	var hub := await _open("arsenal", demo_profile())
	var ars: HubArsenalPanel = hub.panels.arsenal
	(ars.rows[2] as HubPickRow).grab_focus()
	await wait_frames(1)
	(ars.rows[2] as HubPickRow).activated.emit()  # A : vers la fiche
	await wait_frames(1)
	assert_eq(_focus(hub), ars.sheet.slots[0], "A sur une ligne : premier emplacement de la fiche")
	assert_true(ars.back(), "B dans la fiche : retour à la liste")
	assert_eq(_focus(hub), ars.rows[2])
	assert_false(ars.back(), "B dans la liste : menu du hub")
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_Y
	y.pressed = true
	hub._unhandled_input(y)
	assert_eq(ars.filter, "firearm", "Y : filtre suivant")
	var x := InputEventJoypadButton.new()
	x.button_index = JOY_BUTTON_X
	x.pressed = true
	hub._unhandled_input(x)
	assert_eq(ars.sort, "level", "X : tri suivant")


# --------------------------------------------------------------------------
# Outils
# --------------------------------------------------------------------------

func _has_tag(n: Node, t: String) -> bool:
	for c in _all(n, HubTag):
		if (c as HubTag).text == t:
			return true
	return false


func _all(n: Node, type: Variant) -> Array:
	var out := []
	for c in n.get_children():
		if is_instance_of(c, type):
			out.append(c)
		out.append_array(_all(c, type))
	return out


func _scan(n: Node, screen: Rect2, root: Control, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.visible:
			return
		var r := Rect2(c.global_position - root.global_position, c.size)
		if not screen.encloses(r):
			bad.append("%s %s" % [c.name, r])
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_scan(ch, screen, root, bad)
