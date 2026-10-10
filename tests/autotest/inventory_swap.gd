extends AutotestScenario
## Équipement et inventaire de partie (GAME_CONCEPT §4.9, §4.12, §4.13), cas
## nominal en solo : départ avec le niveau et les armes de départ du profil,
## armes rangées dans l'inventaire, échange par le panneau (la partie
## continue, le joueur ne tire plus tant qu'il est ouvert), dégâts selon le
## niveau de l'arme, arme de niveau trop élevé refusée, puissance et HUD, mort
## puis réapparition avec toutes ses affaires (inventaire compris).

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	# Profil : niveau 5, armes de départ pistolet + couteau.
	var pr := PlayerProfile.new()
	pr.add_xp(PlayerProfile.xp_for_level(5))
	pr.set_starting_weapons([WeaponDB.STARTING_WEAPON, KnifeDB.DEFAULT])
	ProfileStore.save_profile(pr)
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	var wc := p.weapons

	# 1. Départ : sélection et niveau du profil, inventaire vide.
	at.check(pd.level == 5, "niveau du profil (%d)" % pd.level)
	at.check(pd.weapons.size() == 1 and pd.weapons[0].uid == BaseWeapons.UID_PREFIX + WeaponDB.STARTING_WEAPON,
			"une arme en main : le pistolet de base (%s)" % [pd.weapons.map(func(w): return w.get("uid", ""))])
	at.check(pd.weapons[0].level == 1 and pd.weapons[0].rarity == OwnedWeapon.Rarity.COMMON, "arme de base niveau 1, commune")
	at.check(pd.bag.is_empty(), "inventaire vide au départ")
	at.check(pd.power() == 1, "puissance = score du pistolet (%d)" % pd.power())

	# 2. Armes rangées (comme une construction terminée) : MP40 niveau 3 rare,
	# M14 niveau 9 (trop haut pour le joueur).
	var mp40 := GameWeapon.make("mp40", 3, OwnedWeapon.Rarity.RARE, [{"id": "chargeur", "level": 2, "mods": {"reserve": 0.5}}], "w1")
	var m14 := GameWeapon.make("m14", 9, OwnedWeapon.Rarity.EPIC, [], "w2")
	at.check(game.session.give_to_bag(1, mp40) and game.session.give_to_bag(1, m14), "armes rangées dans l'inventaire")
	await until(func(): return game.hud.inventory != null, 1.0, "panneau d'inventaire")

	# 3. Panneau : échange du pistolet (en main) avec le MP40.
	var inv := game.hud.inventory
	inv.open()
	at.check(game.menu_open(), "panneau ouvert : entrées du joueur ignorées")
	at.check(not tree().paused, "la partie continue")
	at.check(inv.hand_buttons[0].get_child(0).get_child(0).text.begins_with(WeaponDB.localized(WeaponDB.stats(WeaponDB.STARTING_WEAPON).name)), "case 1 : le pistolet")
	at.check(inv.bag_buttons[1].get_child(0).get_child(1).text.contains(Lang.t("NIVEAU 9 REQUIS", "LEVEL 9 REQUIRED")), "M14 : niveau requis affiché")
	inv.press(0, 0)
	inv.press(1, 0)
	await until(func(): return wc.current().get("uid", "") == "w1", 2.0, "MP40 en main (client)")
	at.check(pd.weapons[0].id == "mp40" and pd.bag[0].id == WeaponDB.STARTING_WEAPON, "serveur : MP40 en main, pistolet rangé")
	at.check(pd.power() == 5, "puissance = score du MP40 (3 + 2) : %d" % pd.power())
	at.check(int(pd.weapons[0].reserve) == roundi(WeaponDB.stats("mp40").reserve * 1.5), "pièce : réserve +50 %")

	# 4. Arme de niveau trop élevé : refusée.
	inv.press(0, 0)
	inv.press(1, 1)
	await seconds(0.3)
	at.check(pd.weapons[0].id == "mp40" and pd.bag[1].id == "m14", "M14 niveau 9 non équipée par un joueur niveau 5")
	inv.close()
	at.check(not game.menu_open(), "panneau fermé")

	# 5. Dégâts : MP40 niveau 3 = 1,2 × dégâts de base.
	await seconds(WeaponController.SWITCH_TIME + 0.2)
	var z: Zombie = await H.dummy_zombie(self, p.global_position - p.global_transform.basis.z * 5.0, 5000)
	H.aim_at(p, z.global_position + Vector3.UP * 1.0)
	var dealt := []
	game.combat.zombie_damaged.connect(func(_pid, _zid, dmg, _k, head, _kind): dealt.append([dmg, head]))
	await H.shoot(self, p)
	await until(func(): return not dealt.is_empty(), 2.0, "touche")
	var expect := roundi(float(WeaponDB.stats("mp40").damage) * 1.2)
	if not dealt.is_empty():
		var d: int = dealt[0][0]
		if dealt[0][1]:
			expect = int(float(expect) * float(WeaponDB.stats("mp40").head_mult))
		at.check(d == expect, "dégâts du MP40 niveau 3 : %d (attendu %d)" % [d, expect])
	await H.clear_zombies(self)

	# 6. Touche 2 : choix direct d'un emplacement vide sans effet, touche 1 garde l'arme.
	p.input.select_slot = 1
	await frames(3)
	at.check(pd.slot == 0, "emplacement 2 vide : pas de changement")

	# 7. Mort puis réapparition (coéquipier fictif debout : pas de fin de partie).
	game.session.create(99)
	game.downed.srv_down(1)
	await until(func(): return pd.life == PlayerData.Life.DOWNED, 1.0, "à terre")
	at.check(pd.bag.size() == 2, "à terre : inventaire gardé")
	game.downed._bleed_out(1)
	await until(func(): return pd.life == PlayerData.Life.DEAD, 1.0, "mort")
	game.respawn_dead_players()
	await until(func(): return pd.life == PlayerData.Life.ALIVE and wc.current().get("uid", "") == "w1", 2.0, "réapparition avec le MP40")
	at.check(pd.weapons.size() == 1 and pd.weapons[0].uid == "w1" and pd.weapons[0].level == 3, "arme en main rendue (niveau gardé)")
	at.check(pd.bag.size() == 2 and pd.bag[0].id == WeaponDB.STARTING_WEAPON and pd.bag[1].id == "m14", "inventaire rendu tel quel")
	at.check(game.local_player.weapons.weapons.size() == 1, "client : armes en main resynchronisées")
	game.session.remove(99)
