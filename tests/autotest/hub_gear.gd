extends "res://tests/autotest/hub_nav.gd"
## @rendu : onglets ARSENAL, PIÈCES et DÉPART du hub (docs/HUB_PLAN.md, lot
## C) parcourus au clavier et à la manette (événements d'entrée réels), avec
## un profil proche de la maquette (écrans 2, 3, 4 et 8) : liste et fiche,
## retrait d'une pièce armé (deuxième appui demandé), fenêtre « installer une
## pièce », onglet PIÈCES puis INSTALLER SUR… (montage réel, profil
## enregistré), DÉPART (retrait d'une arme de départ enregistré), français et
## anglais, TAILLE DES MENUS 80 et 130 % (rien ne sort de l'écran).
## Captures pendant le développement (comparaison avec la maquette), suffixe
## = hauteur de la fenêtre (720, 1080).


## Profil de la maquette (niveau 7) : FRELON épique niv. 7 (2 pièces) et sa
## version 2, SIROCCO, MAMBA (niv. 9, verrouillée), CARNAGE, VIEILLE GARDE ;
## 5 pièces en stock ; NOUVEAU : FRELON, VIEILLE GARDE, la pièce niv. 9.
static func gear_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 2140
	pr.add_samples("dog_fang", 7)
	pr.add_samples("dog_fur", 2)
	pr.add_samples("dog_collar", 5)
	var w := OwnedWeapon.create("mp5k", 7, OwnedWeapon.Rarity.EPIC)
	w.parts.append(WeaponPart.create("part_damage", 6, {"damage": 0.15}))
	w.parts.append(WeaponPart.create("part_fire_rate", 5, {"fire_rate": 0.1, "accuracy": -0.06}))
	pr.add_weapon(w)
	pr.add_weapon(OwnedWeapon.create("mp5k", 5, OwnedWeapon.Rarity.RARE))
	pr.add_weapon(OwnedWeapon.create("m16", 6, OwnedWeapon.Rarity.RARE))
	pr.add_weapon(OwnedWeapon.create("python", 9, OwnedWeapon.Rarity.LEGENDARY))
	pr.add_weapon(OwnedWeapon.create("stakeout", 3, OwnedWeapon.Rarity.COMMON))
	var old := OwnedWeapon.create("m14", 4, OwnedWeapon.Rarity.COMMON)
	pr.add_weapon(old)
	pr.add_part(WeaponPart.create("part_mag", 7, {"mag": 0.2}))
	pr.add_part(WeaponPart.create("part_accuracy", 6, {"accuracy": 0.12, "reload": -0.08}))
	pr.add_part(WeaponPart.create("part_recoil", 4, {"recoil": 0.18}))
	pr.add_part(WeaponPart.create("part_reload", 2, {"reload": 0.07}))
	pr.mark_all_seen()
	var fresh := WeaponPart.create("part_damage", 9, {"damage": 0.22})
	pr.add_part(fresh)
	pr.seen_weapons.erase(w.uid)
	pr.seen_weapons.erase(old.uid)
	return pr


func run() -> void:
	timeout_sec = 150
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	var res := OS.get_environment("HUB_SHOT_RES")
	if res != "" and DisplayServer.get_name() != "headless":
		var p := res.split("x")
		if p.size() == 2:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
			await frames(3)
	await until(_settled, 5.0, "menu titre affiché")
	var pr := gear_profile()
	var frelon_uid := pr.weapons[0].uid
	ProfileStore.save_profile(pr)
	Router.last_match = demo_last_match()
	await press("ui_accept")  # JOUER
	await until(_settled, 3.0, "hub affiché")
	hub = menu.current
	await _tour("")
	# --- INSTALLER SUR… depuis PIÈCES : montage réel, enregistré.
	hub.select_tab("parts")
	await frames(3)
	var parts: HubPartsPanel = hub.panels.parts
	var damper := ""
	for p in hub.profile.parts:
		if p.mods.has("recoil"):
			damper = p.uid
	parts._row_of(damper).grab_focus()
	await frames(2)
	await press("ui_accept")  # vers les armes compatibles
	at.check(_focused() == parts.weapon_rows[0], "A sur la pièce : première arme compatible")
	await press("ui_accept")  # INSTALLER SUR FRELON
	await frames(3)
	var ars: HubArsenalPanel = hub.panels.arsenal
	at.check(hub.tab == "arsenal" and ars.picker != null, "INSTALLER SUR… : fenêtre des pièces dans l'ARSENAL")
	at.check(ars.picker != null and ars.picker.parts[ars.picker.selected].uid == damper, "pièce déjà choisie")
	at.check(_focused() == (ars.picker.install_button if ars.picker else null), "focus sur INSTALLER")
	await press("ui_accept")  # INSTALLER
	await frames(2)
	var saved := ProfileStore.load_profile()
	at.check(saved.get_weapon(frelon_uid).parts.size() == 3, "pièce installée et enregistrée (%d)" % saved.get_weapon(frelon_uid).parts.size())
	at.check(saved.get_part(damper) == null, "la pièce a quitté l'onglet PIÈCES")
	# --- Retrait en deux appuis (clavier) : la pièce est détruite.
	var gone: String = saved.get_weapon(frelon_uid).parts[2].uid
	(ars.sheet.slots[2] as Control).grab_focus()
	await frames(2)
	await press("ui_accept")
	at.check(ars.sheet.armed == HubWeaponSheet.REMOVE, "premier appui : retrait armé")
	await press("ui_accept")
	saved = ProfileStore.load_profile()
	at.check(saved.get_weapon(frelon_uid).parts.size() == 2 and saved.get_part(gone) == null, "deuxième appui : pièce détruite, enregistré")
	# --- DÉPART : retirer l'arme de l'emplacement 2, enregistré.
	hub.select_tab("loadout")
	await frames(3)
	var lo: HubLoadoutPanel = hub.panels.loadout
	var before := hub.profile.starting_weapons.size()
	(lo.slots[before - 1] as Control).grab_focus()
	await frames(2)
	await press("ui_accept")
	saved = ProfileStore.load_profile()
	at.check(saved.starting_weapons.size() == before - 1, "DÉPART : arme retirée et enregistrée (%s)" % str(saved.starting_weapons))
	await press("ui_accept")  # dernière arme : refusé
	saved = ProfileStore.load_profile()
	at.check(saved.starting_weapons.size() == maxi(before - 1, 1), "la dernière arme reste")
	await _contract_to_install()
	# Taille des menus : rien ne sort de l'écran.
	for f in [0.8, 1.3]:
		Settings.menu_ui_scale = f
		await frames(4)
		hub = menu.current
		for t in ["arsenal", "parts", "loadout"]:
			hub.select_tab(t)
			await frames(3)
			_check_inside(hub, "%s à %d %%" % [t, roundi(f * 100.0)])
		await seconds(0.2)
		await shot("arsenal_%d" % roundi(f * 100.0))
	Settings.menu_ui_scale = 1.0
	await frames(3)
	# Anglais, manette.
	ProfileStore.save_profile(gear_profile())
	Settings.language = "en"
	menu.show_screen("hub")
	await until(_settled, 3.0, "hub réaffiché en anglais")
	hub = menu.current
	await _tour("_en")
	Settings.language = "fr"
	Settings.using_pad = false
	ProfileStore.reset()


## Onglets réels ensemble (lots C et D) : CONTRATS -> REMETTRE -> VOIR DANS
## LES PIÈCES (pièce reçue choisie, NOUVEAU, même nom que la fenêtre) ->
## INSTALLER SUR… (ARSENAL) -> montage enregistré, pièce vue -> E E :
## CONTRATS (premier élément utile). Profil de la maquette avec ses contrats.
func _contract_to_install() -> void:
	var cp := gear_profile()
	cp.contracts = demo_profile().contracts
	ProfileStore.save_profile(cp)
	menu.show_screen("hub")
	await until(_settled, 3.0, "hub rouvert (contrats)")
	hub = menu.current
	hub.select_tab("contracts")
	await frames(3)
	var cps: HubContractsPanel = hub.panels.contracts
	var card: HubContractCard = null
	for c in cps.active_cards:
		if c.contract_id == "dog_fangs_small":
			card = c
	at.check(card != null and _focused() == card.main_button, "CONTRATS : focus sur REMETTRE (Dents de lait)")
	if card == null:
		return
	card.main_button.grab_focus()
	await press("ui_accept")  # REMETTRE
	await frames(3)
	at.check(cps.popup_open(), "fenêtre « contrat remis »")
	var uid: String = hub.profile.parts[-1].uid
	var got := hub.profile.get_part(uid)
	var item_name: String = cps.popup.item_name if cps.popup else ""
	at.check(got != null and item_name == HubGear.part_name(got).to_upper(), "nom de la pièce partagé (%s)" % item_name)
	at.check(hub.profile.is_new_part(uid), "pièce reçue NOUVELLE")
	await press("ui_accept")  # VOIR DANS LES PIÈCES
	await frames(3)
	var parts: HubPartsPanel = hub.panels.parts
	at.check(hub.tab == "parts" and not cps.popup_open(), "VOIR DANS LES PIÈCES : onglet PIÈCES (%s)" % hub.tab)
	at.check(parts.selected_uid == uid and _focused() == parts._row_of(uid), "pièce reçue choisie, focus dessus")
	at.check(parts._seen_now.has(uid), "pastille NOUVEAU gardée pendant la visite")
	at.check(parts.title_label != null and parts.title_label.text == item_name, "même nom dans la fiche (%s)" % (parts.title_label.text if parts.title_label else ""))
	await seconds(0.3)
	await shot("parts_received")
	await press("ui_accept")  # vers les armes compatibles
	at.check(not parts.weapon_rows.is_empty() and _focused() == parts.weapon_rows[0], "A : première arme compatible")
	if parts.weapon_rows.is_empty():
		return
	var wuid: String = parts.weapon_uid
	await press("ui_accept")  # INSTALLER SUR…
	await frames(3)
	var ars: HubArsenalPanel = hub.panels.arsenal
	at.check(hub.tab == "arsenal" and ars.picker != null and ars.picker.parts[ars.picker.selected].uid == uid,
			"INSTALLER SUR… : la pièce reçue choisie dans l'ARSENAL")
	await press("ui_accept")  # INSTALLER
	await frames(2)
	var saved := ProfileStore.load_profile()
	var w := saved.get_weapon(wuid)
	var mounted := false
	if w:
		for p in w.parts:
			mounted = mounted or p.uid == uid
	at.check(mounted and saved.get_part(uid) == null, "pièce reçue installée et enregistrée")
	at.check(not saved.is_new_part(uid), "pièce reçue enregistrée « vue »")
	await key(KEY_E)
	await key(KEY_E)
	at.check(hub.tab == "contracts" and _focused() == cps.first_focus(), "E E : CONTRATS, premier élément utile")


## Parcours des trois onglets avec les captures de la maquette (écrans 2, 3,
## 4, 8) ; `sfx` : suffixe des captures.
func _tour(sfx: String) -> void:
	hub.select_tab("lab")
	await frames(2)
	await key(KEY_E)
	at.check(hub.tab == "arsenal", "E : ARSENAL (%s)" % hub.tab)
	var ars: HubArsenalPanel = hub.panels.arsenal
	at.check(ars is HubArsenalPanel, "ARSENAL : panneau du lot C")
	at.check(_focused() == ars.rows[0], "focus sur la première ligne")
	# Descendre jusqu'à FRELON (2 armes de base puis l'arsenal).
	await press("ui_down")
	await press("ui_down")
	at.check(ars.sheet.weapon != null and ars.sheet.weapon.weapon_id == "mp5k" and ars.sheet.weapon.level == 7, "flèche bas : FRELON choisi")
	# A : vers la fiche, sur la pièce 2, premier appui de RETIRER.
	await press("ui_accept")
	at.check(_focused() == ars.sheet.slots[0], "A : premier emplacement de la fiche")
	await press("ui_down")
	await press("ui_accept")
	at.check(ars.sheet.armed == HubWeaponSheet.REMOVE, "Entrée sur une pièce : RETIRER armé")
	at.check(_focused() == ars.sheet.remove_button, "focus sur CONFIRMER")
	await seconds(0.3)
	await shot("arsenal" + sfx)
	await press("ui_cancel")
	at.check(ars.sheet.armed == HubWeaponSheet.NONE, "Échap : retrait annulé")
	at.check(hub.profile.weapons[0].parts.size() == 2, "rien de retiré")
	# Emplacement libre : fenêtre « installer une pièce ».
	await press("ui_down")
	at.check(_focused() == ars.sheet.slots[2], "flèche bas : emplacement libre")
	await press("ui_accept")
	at.check(ars.picker != null, "Entrée : fenêtre des pièces")
	await seconds(0.3)
	await shot("picker" + sfx)
	await press("ui_cancel")
	at.check(ars.picker == null, "Échap : fenêtre fermée")
	# Filtre (Tab) puis tri (R) : retour à l'état d'origine.
	await key(KEY_TAB)
	at.check(ars.filter == "firearm", "Tab : À FEU (%s)" % ars.filter)
	for i in 3:
		await key(KEY_TAB)
	at.check(ars.filter == "all", "Tab x4 : TOUTES")
	# PIÈCES : l'Amortisseur choisi (maquette écran 4).
	await key(KEY_E)
	at.check(hub.tab == "parts", "E : PIÈCES (%s)" % hub.tab)
	var parts: HubPartsPanel = hub.panels.parts
	for i in 3:
		await press("ui_down")
	await seconds(0.3)
	await shot("parts" + sfx)
	# DÉPART (manette : RB x3).
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	at.check(hub.tab == "loadout", "RB x3 : DÉPART (%s)" % hub.tab)
	var lo: HubLoadoutPanel = hub.panels.loadout
	await press("ui_right")
	await seconds(0.3)
	await shot("loadout" + sfx)
	at.check(parts.rows.size() == hub.profile.parts.size(), "PIÈCES : une ligne par pièce")
	at.check(lo.slots.size() == 3, "DÉPART : trois emplacements")
	Settings.using_pad = false
