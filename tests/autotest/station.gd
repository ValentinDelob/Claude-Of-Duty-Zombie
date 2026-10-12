extends AutotestScenario
## Station de construction (GAME_CONCEPT §4.11, §4.12), cas nominal en solo
## sur l'arène de test : [F] à la station ouvre l'interface (la partie
## continue) qui liste l'arsenal du profil avec prix et niveau requis ;
## construction refusée sans ferraille et au-dessus du niveau, lancée sinon
## (ferraille dépensée aussitôt, une seule à la fois) ; prête à la fin de la
## bonne manche (carte et fiche de l'arme : EN COURS / PRÊTE) ; récupération
## refusée inventaire plein, recyclage depuis l'inventaire (plus à la
## station : aide « ouvre l'inventaire »), récupération par [F] dans
## l'interface ; recharge des munitions (action « reload ») ; jamais la
## dernière arme recyclée ; évacuation : la version améliorée en partie met à
## jour l'arsenal et l'arme ramassée y entre.

var H := AutotestHelpers
var game: Game
var p: Player
var st: BuildStation
var pd: PlayerData


## [F] en visant la station.
func _use() -> void:
	H.aim_at(p, st.interact_point())
	await until(func(): return game.interact.focused == st, 2.0, "station visée")
	p.input.interact_pressed = true
	await frames(3)


## Fin de la manche `n` (sans jouer les zombies).
func _end_round(n: int) -> void:
	game.rounds.debug_jump_to(n)
	game.rounds._end_round()
	await frames(2)


## Une invite de la barre contient `t` ?
static func prompt_has(panel: StationPanel, t: String) -> bool:
	for d in panel.prompts.describe():
		if d.contains(t):
			return true
	return false


## Fiche complète (DÉTAILS) de la fiche du MR-40 choisi : fermée au départ,
## D l'ouvre (valeurs de l'arme construite, pièce de réserve comprise,
## « Réf. MP40 »), R3 la ferme ; ni construction, ni recharge, ni filtre
## déclenchés ; invite DÉTAILS / MASQUER.
func _check_details(panel: StationPanel) -> void:
	var d := panel.details
	at.check(d != null and d.visible and not d.open and not d.body.visible, "fiche : DÉTAILS repliée")
	at.check(prompt_has(panel, Lang.t("DÉTAILS", "DETAILS")), "invite DÉTAILS : %s" % " ".join(panel.prompts.describe()))
	var points := pd.points
	var f := panel.filter
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	var up := key.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)
	at.check(d.open and d.body.visible, "D : fiche complète ouverte")
	var keys: Array = d.lines.map(func(l): return l.key)
	at.check(keys == ["head_mult", "fire_mode", "recoil", "ads_time", "reserve", "penetration", "move_mult", "ref"],
			"lignes du MR-40 : %s" % [keys])
	var res: Array = d.lines.filter(func(l): return l.key == "reserve")
	at.check(not res.is_empty() and String(res[0].value) == "288" and String(res[0].mod) == "",
			"réserve de l'arme construite (192 + 50 %%) : %s" % [res])
	at.check(d.note.visible and d.note.text == Lang.t("Réf. MP40", "Ref. MP40"), "référence réelle : %s" % d.note.text)
	at.check(prompt_has(panel, Lang.t("MASQUER", "HIDE")), "invite MASQUER : %s" % " ".join(panel.prompts.describe()))
	at.check(pd.points == points and st.builds.is_empty() and panel.filter == f and panel.visible,
			"D : ni construction, ni recharge, ni filtre, panneau ouvert")
	var r3 := InputEventJoypadButton.new()
	r3.button_index = JOY_BUTTON_RIGHT_STICK
	r3.pressed = true
	Input.parse_input_event(r3)
	await frames(2)
	at.check(not d.open and not d.body.visible, "R3 : fiche complète repliée")
	at.check(not Hub2WeaponDetails.is_open_for(StationPanel.DETAILS_SCREEN), "état retenu : fermée")


func run() -> void:
	timeout_sec = 120
	# Profil : niveau 5 ; arsenal : MP40 niveau 3 rare avec une pièce, M14 niveau 9.
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(5))
	# Départ au pistolet seul (la batte, autre arme de base, reste listée à la station).
	pr.set_starting_weapons([WeaponDB.STARTING_WEAPON])
	var mp40 := OwnedWeapon.create("mp40", 3, OwnedWeapon.Rarity.RARE)
	mp40.parts.append(WeaponPart.create("chargeur", 2, {"reserve": 0.5}))
	var uid := pr.add_weapon(mp40)
	pr.add_weapon(OwnedWeapon.create("m14", 9, OwnedWeapon.Rarity.EPIC))
	ProfileStore.save_profile(pr)
	p = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	pd = game.session.local_data()
	st = game.station
	at.check(st != null and st.interact_id == "station", "station de construction construite")
	if st == null:
		return
	var panel := game.hud.station_panel

	# 1. [F] : l'interface s'ouvre, la partie continue.
	p.teleport_to(st.global_position + st.global_basis.z * 1.7 + Vector3.UP * 0.05)
	await frames(3)
	at.check(st.prompt(1).contains(Lang.t("Station", "station")), "invite : %s" % st.prompt(1))
	await _use()
	await until(func(): return panel.visible, 2.0, "interface ouverte")
	at.check(panel.visible and game.menu_open(), "interface ouverte : entrées du joueur ignorées")
	at.check(not tree().paused, "la partie continue")
	at.check(panel.entries.size() == 4, "armes de base (pistolet, batte) + 2 armes de l'arsenal (%d)" % panel.entries.size())
	at.check(panel.entries[2].uid == uid, "MP40 de l'arsenal listé")
	await frames(2)
	at.check(not game.hud._crosshair.visible, "HUD (réticule) masqué sous la station")
	at.check(panel.filter == StationPanel.BUILDABLE and panel.card_of(panel.entries[3].uid) == null,
			"CONSTRUCTIBLES : M14 niveau 9 absente")
	at.check(prompt_has(panel, Lang.t("RECHARGER", "REFILL")) and panel.prompts.help.contains(Settings.action_label("inventory")),
			"invites : %s · aide « %s »" % [" ".join(panel.prompts.describe()), panel.prompts.help])
	panel.toggle_filter()
	var m14_card := panel.card_of(panel.entries[3].uid)
	at.check(m14_card != null and m14_card.data.locked and String(m14_card.data.price) == Lang.t("NIV. 9 REQUIS", "LVL 9 REQUIRED") \
			and m14_card.modulate.a < 0.6, "TOUTES : M14 niveau 9 à 50 %, « NIV. 9 REQUIS »")
	at.check(panel.select_uid(panel.entries[3].uid) and panel.note_label.text == Lang.t("NIV. 9 REQUIS", "LVL 9 REQUIRED") \
			and not panel.can_build(panel.entries[3]), "fiche de la M14 : %s" % panel.note_label.text)
	panel.toggle_filter()
	var price := BuildRules.owned_price(mp40)
	at.check(panel.select_uid(uid), "MP40 choisi")
	var mp_card := panel.card_of(uid)
	at.check(mp_card != null and String(mp_card.data.price) == Hub2Style.num(price) and mp_card.data.price_bad,
			"prix du MP40 affiché, rouge sans ferraille : %s" % mp_card.data.price)
	at.check(panel.note_label.text == Lang.t("IL MANQUE %s", "%s SHORT") % Hub2Style.num(price), "raison : %s" % panel.note_label.text)
	await _check_details(panel)
	await at.screenshot("panel")

	# 2. Sans ferraille : refusé. Au-dessus du niveau : refusé par le serveur.
	panel.press_build()
	await frames(5)
	at.check(st.builds.is_empty() and pd.points == 0, "pas assez de ferraille : rien de lancé")
	game.session.add_points(1, 5000)
	st.srv_build.rpc_id(1, GameWeapon.make("m14", 9, OwnedWeapon.Rarity.EPIC, [], "w2"))
	await frames(3)
	at.check(st.builds.is_empty() and pd.points == 5000, "niveau trop bas : refusé par le serveur")

	# 3. Construction : ferraille dépensée au lancement, une seule à la fois.
	var r0 := game.rounds.round_n
	var expect_round := BuildRules.ready_round(r0, game.rounds.phase == RoundManager.Phase.ACTIVE, price)
	await frames(2)
	at.check(panel.can_build(mp40) and panel.note_label.text.contains(Hub2Style.num(5000 - price)), "note : %s" % panel.note_label.text)
	panel.press_build()
	await until(func(): return st.builds.has(1), 2.0, "construction lancée")
	at.check(pd.points == 5000 - price, "ferraille dépensée au lancement (%d)" % pd.points)
	at.check(int(st.builds[1]["round"]) == expect_round and not bool(st.builds[1].ready), "prête à la fin de la manche %d" % expect_round)
	var built: Dictionary = st.builds[1].w
	at.check(String(built.uid) == uid and int(built.level) == 3 and int(built.rarity) == OwnedWeapon.Rarity.RARE \
			and (built.parts as Array).size() == 1, "exemplaire de la version de l'arsenal (uid, niveau, rareté, pièces)")
	await frames(2)
	at.check(panel.build_label == Lang.t("EN CONSTRUCTION · MANCHE %d", "BUILDING · ROUND %d") % expect_round,
			"fiche : %s" % panel.build_label)
	at.check(String(panel.card_of(uid).data.rounds) == Lang.t("EN COURS", "BUILDING"), "carte : EN COURS")
	at.check(not panel.can_build(panel.entries[0]) and panel.select_uid(panel.entries[0].uid) \
			and panel.note_label.text == Lang.t("STATION OCCUPÉE", "STATION BUSY"), "les autres armes : %s" % panel.note_label.text)
	st.srv_build.rpc_id(1, GameWeapon.from_owned(BaseWeapons.make(WeaponDB.STARTING_WEAPON)))
	await frames(3)
	at.check(pd.points == 5000 - price and String(st.builds[1].w.uid) == uid, "une seule construction à la fois")
	panel.close()
	at.check(not game.menu_open(), "interface fermée")

	# 4. Manches : prête à la fin de la bonne manche, pas avant.
	if expect_round > 1:
		await _end_round(expect_round - 1)
		at.check(not bool(st.builds[1].ready), "pas prête avant la fin de la manche %d" % expect_round)
	await _end_round(expect_round)
	at.check(bool(st.builds[1].ready), "prête à la fin de la manche %d" % expect_round)
	at.check(st.prompt(1).contains(Lang.t("Récupérer", "Collect")), "invite : %s" % st.prompt(1))

	# 5. Inventaire plein : refus clair, l'interface s'ouvre.
	for i in GameWeapon.BAG:
		game.session.give_to_bag(1, GameWeapon.make("mp5k" if WeaponDB.exists("mp5k") else "mp40", 1, 0, [], ""))
	await frames(2)
	await _use()
	await frames(3)
	at.check(pd.bag.size() == GameWeapon.BAG and bool(st.builds[1].ready), "inventaire plein : arme gardée à la station")
	at.check(game.hud._flash.text == InteractionSystem.deny_text(InteractionSystem.BAG_FULL), "message : %s" % game.hud._flash.text)
	at.check(panel.visible, "l'interface s'ouvre pour s'organiser")
	at.check(panel.selected_uid == uid and panel.build_label.begins_with(Lang.t("PRÊTE", "READY")) \
			and String(panel.card_of(uid).data.rounds) == Lang.t("PRÊTE", "READY"), "ouverte sur l'arme prête : %s" % panel.build_label)
	panel.close()

	# 6. Recyclage depuis l'inventaire (deux appuis), puis récupération.
	var before := pd.points
	var inv := game.hud.inventory
	inv.open()
	inv.press(1, 0)
	var value := BuildRules.recycle_value(pd.bag[0])
	inv.recycle_selected()
	await frames(2)
	at.check(pd.bag.size() == GameWeapon.BAG, "premier appui : confirmation demandée")
	inv.recycle_selected()
	await until(func(): return pd.bag.size() == GameWeapon.BAG - 1, 2.0, "arme recyclée")
	at.check(pd.points == before + value and value > 0, "recyclage : +%d ferraille (%d)" % [value, pd.points])
	inv.close()
	# [F] dans l'interface ouverte : récupération.
	panel.open(st)
	var f := InputEventAction.new()
	f.action = "interact"
	f.pressed = true
	Input.parse_input_event(f)
	await until(func(): return not st.builds.has(1), 2.0, "arme récupérée ([F] dans l'interface)")
	var got: Dictionary = pd.bag[pd.bag.size() - 1]
	at.check(String(got.uid) == uid and int(got.level) == 3, "MP40 de l'arsenal dans l'inventaire")
	at.check(st.prompt(1).contains(Lang.t("Station", "station")), "station libre")
	panel.close()

	# 7. Recharge des munitions de l'arme en main.
	pd.weapons[pd.slot].mag = 0
	pd.weapons[pd.slot].reserve = 0
	game.session.sync_inventory(1)
	await frames(2)
	before = pd.points
	var cost := BuildRules.refill_price(pd.current_weapon())
	await _use()
	await until(func(): return panel.visible, 2.0, "interface")
	at.check(panel._ammo_price.text == Hub2Style.num(cost) and panel._ammo_line.count == "0 / 0" \
			and panel._refill_text.text.begins_with(Settings.action_label("reload")),
			"MUNITIONS : %s %s · %s" % [panel._ammo_line.count, panel._ammo_price.text, panel._refill_text.text])
	# Touche « reload » réelle (R par défaut).
	var r := InputEventAction.new()
	r.action = "reload"
	r.pressed = true
	Input.parse_input_event(r)
	await until(func(): return BuildRules.ammo_full(pd.current_weapon()), 2.0, "munitions rechargées")
	at.check(pd.points == before - cost, "recharge payée %d" % cost)
	await until(func(): return int(p.weapons.current().get("mag", 0)) > 0, 2.0, "client : chargeur plein")
	panel.press_refill()
	await frames(3)
	at.check(pd.points == before - cost, "munitions déjà pleines : rien payé")
	panel.close()

	# 8. Jamais la dernière arme : refus du serveur (message) et case grisée
	# de l'inventaire (le recyclage n'est plus à la station).
	var keep_hands := pd.weapons.duplicate()
	var keep_bag := pd.bag.duplicate()
	pd.weapons = [(pd.weapons if not pd.weapons.is_empty() else pd.bag)[0]]
	pd.slot = 0
	pd.bag = []
	game.session.sync_inventory(1)
	await frames(2)
	var last_text := BuildRules.recycle_refusal_text(BuildRules.LAST_WEAPON)
	game.hud._flash.text = ""
	game.combat.srv_recycle.rpc_id(1, 0, 0)
	await frames(2)
	at.check(pd.weapons.size() == 1 and game.hud._flash.text == last_text, "serveur : dernière arme refusée (%s)" % game.hud._flash.text)
	# Mains vides, une seule arme dans l'inventaire.
	pd.bag = [pd.weapons[0]]
	pd.weapons = []
	game.session.sync_inventory(1)
	await frames(2)
	var inv2 := game.hud.inventory
	inv2.open()
	inv2.press(1, 0)
	at.check(inv2.recycle_label.text == last_text and inv2.recycle_value_label.text == "", "inventaire : %s" % inv2.recycle_label.text)
	inv2.recycle_selected()
	inv2.recycle_selected()
	await frames(3)
	at.check(pd.bag.size() == 1, "inventaire : seule arme du sac gardée")
	inv2.close()
	pd.weapons = keep_hands
	pd.bag = keep_bag
	game.session.sync_inventory(1)
	await frames(2)

	# 9. Évacuation : la version améliorée en partie met à jour l'arsenal,
	# l'arme ramassée y entre.
	var i_built := -1
	for i in pd.bag.size():
		if String(pd.bag[i].get("uid", "")) == uid:
			i_built = i
	pd.bag[i_built].level = 4
	pd.bag[0] = GameWeapon.make("m14", 7, OwnedWeapon.Rarity.EPIC, [], "loot:7")
	game.session.sync_inventory(1)
	await frames(2)
	game.srv_end_match(true)
	var ok: bool = await until(func(): return GameState.state == GameState.State.GAME_OVER and game.last_result != null, 2.0, "évacuation")
	if not ok:
		return
	var after := ProfileStore.load_profile()
	var v := after.get_weapon(uid)
	at.check(v != null and v.level == 4 and v.rarity == OwnedWeapon.Rarity.RARE and v.parts.size() == 1, "version de l'arsenal mise à jour (niveau 4)")
	at.check(after.weapons.any(func(o): return o.weapon_id == "m14" and o.level == 7), "arme ramassée ajoutée à l'arsenal")
	at.check(after.versions_of("mp40").size() == 1, "même version, pas de doublon")
	ProfileStore.reset()
