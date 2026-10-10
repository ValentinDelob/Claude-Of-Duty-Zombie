extends AutotestScenario
## Station de construction (GAME_CONCEPT §4.11, §4.12), cas nominal en solo
## sur l'arène de test : [F] à la station ouvre l'interface (la partie
## continue) qui liste l'arsenal du profil avec prix et niveau requis ;
## construction refusée sans ferraille et au-dessus du niveau, lancée sinon
## (ferraille dépensée aussitôt, une seule à la fois) ; prête à la fin de la
## bonne manche ; récupération refusée inventaire plein, recyclage depuis
## l'inventaire, récupération ; recharge des munitions et recyclage à la
## station ; évacuation : la version améliorée en partie met à jour l'arsenal
## et l'arme ramassée y entre.

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


func run() -> void:
	timeout_sec = 120
	# Profil : niveau 5 ; arsenal : MP40 niveau 3 rare avec une pièce, M14 niveau 9.
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(5))
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
	at.check(panel.entries.size() == 3, "pistolet de base + 2 armes de l'arsenal (%d)" % panel.entries.size())
	at.check(panel.entries[1].uid == uid, "MP40 de l'arsenal listé")
	var info: Label = panel.rows[2].get_child(0).get_child(0).get_child(1)
	at.check(info.text.contains(Lang.t("NIVEAU 9 REQUIS", "LEVEL 9 REQUIRED")) and panel.rows[2].disabled, "M14 niveau 9 : niveau requis, non constructible (%s)" % info.text)
	var price := BuildRules.owned_price(mp40)
	var price_l: Label = panel.rows[1].get_child(0).get_child(1)
	at.check(price_l.text.contains(str(price)), "prix du MP40 affiché : %s" % price_l.text)
	await at.screenshot("panel")

	# 2. Sans ferraille : refusé. Au-dessus du niveau : refusé par le serveur.
	panel.press_build(1)
	await frames(5)
	at.check(st.builds.is_empty() and pd.points == 0, "pas assez de ferraille : rien de lancé")
	game.session.add_points(1, 5000)
	st.srv_build.rpc_id(1, GameWeapon.make("m14", 9, OwnedWeapon.Rarity.EPIC, [], "w2"))
	await frames(3)
	at.check(st.builds.is_empty() and pd.points == 5000, "niveau trop bas : refusé par le serveur")

	# 3. Construction : ferraille dépensée au lancement, une seule à la fois.
	var r0 := game.rounds.round_n
	var expect_round := BuildRules.ready_round(r0, game.rounds.phase == RoundManager.Phase.ACTIVE, price)
	panel.press_build(1)
	await until(func(): return st.builds.has(1), 2.0, "construction lancée")
	at.check(pd.points == 5000 - price, "ferraille dépensée au lancement (%d)" % pd.points)
	at.check(int(st.builds[1]["round"]) == expect_round and not bool(st.builds[1].ready), "prête à la fin de la manche %d" % expect_round)
	var built: Dictionary = st.builds[1].w
	at.check(String(built.uid) == uid and int(built.level) == 3 and int(built.rarity) == OwnedWeapon.Rarity.RARE \
			and (built.parts as Array).size() == 1, "exemplaire de la version de l'arsenal (uid, niveau, rareté, pièces)")
	at.check(panel.status_text().contains(str(expect_round)), "état affiché : %s" % panel.status_text())
	at.check(not panel.can_build(0), "les autres lignes sont grisées")
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
	await _use()
	await until(func(): return not st.builds.has(1), 2.0, "arme récupérée")
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
	at.check(not panel.refill_button.disabled and panel.refill_button.text.contains(str(cost)), "bouton de recharge : %s" % panel.refill_button.text)
	panel.press_refill()
	await until(func(): return BuildRules.ammo_full(pd.current_weapon()), 2.0, "munitions rechargées")
	at.check(pd.points == before - cost, "recharge payée %d" % cost)
	await until(func(): return int(p.weapons.current().get("mag", 0)) > 0, 2.0, "client : chargeur plein")
	panel.press_refill()
	await frames(3)
	at.check(pd.points == before - cost, "munitions déjà pleines : rien payé")

	# 8. Recyclage à la station (arme de base : rien ; deux appuis).
	var k := panel.recycle_slots.find([0, 0])
	before = pd.points
	var hand_n := pd.weapons.size()
	panel.press_recycle(k)
	panel.press_recycle(k)
	await until(func(): return pd.weapons.size() == hand_n - 1, 2.0, "arme en main recyclée")
	at.check(pd.points == before, "arme de base : ne rapporte rien")
	panel.close()

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
