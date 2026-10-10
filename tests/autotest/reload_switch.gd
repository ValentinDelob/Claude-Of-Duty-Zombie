extends AutotestScenario
## Changer d'arme pendant un rechargement (BO1) : le changement part tout de
## suite, le rechargement est annulé (chargeur ni rempli, réserve intacte,
## côté client ET serveur), aucun remplissage différé ne tombe sur l'une ou
## l'autre arme ; au retour il faut recharger. Fusil à pompe : les cartouches
## déjà poussées restent.

var game: Game
var p: Player
var pd: PlayerData


func equip(ids: Array, mag0: int, reserve0: int) -> bool:
	pd.weapons = []
	for id in ids:
		pd.weapons.append(WeaponDB.new_instance(id))
	pd.weapons[0].mag = mag0
	pd.weapons[0].reserve = reserve0
	pd.slot = 0
	game.combat.cancel_reload(1)
	game.session.sync_inventory(1)
	var ok: bool = await until(func(): return p.weapons.current().get("id", "") == ids[0] and int(p.weapons.current().mag) == mag0, 2.0, "%s en main" % ids[0])
	await seconds(WeaponController.SWITCH_TIME + 0.2)
	return ok


func ammo(i: int) -> Array:
	return [int(p.weapons.weapons[i].mag), int(p.weapons.weapons[i].reserve)]


func srv_ammo(i: int) -> Array:
	return [int(pd.weapons[i].mag), int(pd.weapons[i].reserve)]


func run() -> void:
	p = await AutotestHelpers.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	pd = game.session.local_data()
	var wc := p.weapons

	# 1. M1911 entamé (5/80) : rechargement puis changement à mi-course.
	await equip(["m1911", "mp40"], 5, 80)
	var dur := game.combat.reload_time(1, pd.weapons[0])
	p.input.reload = true
	await seconds(dur * 0.4)
	at.check(wc.is_reloading() and game.combat.is_reloading(1), "rechargement en cours (client et serveur)")
	p.input.switch_weapon = true
	await frames(2)
	at.check(not wc.is_reloading(), "rechargement annulé dès la demande de changement")
	await until(func(): return wc.current().get("id", "") == "mp40", 1.0, "changement vers le MP40 accepté")
	at.check(not game.combat.is_reloading(1), "serveur : rechargement annulé")
	at.check(pd.slot == 1, "serveur : MP40 en main")
	# Au-delà de l'échéance du rechargement annulé : rien ne se remplit.
	await seconds(dur + 0.3)
	at.check(ammo(0) == [5, 80], "M1911 inchangé côté client : %s" % [ammo(0)])
	at.check(srv_ammo(0) == [5, 80], "M1911 inchangé côté serveur : %s" % [srv_ammo(0)])
	var mp40 := WeaponDB.new_instance("mp40")
	at.check(ammo(1) == [int(mp40.mag), int(mp40.reserve)], "MP40 intact : %s" % [ammo(1)])
	at.check(not wc.is_reloading(), "MP40 : pas de rechargement hérité")

	# 2. Retour au M1911 : il faut recharger de nouveau, et cela fonctionne.
	p.input.switch_weapon = true
	await until(func(): return wc.current().get("id", "") == "m1911", 1.0, "retour au M1911")
	await seconds(WeaponController.SWITCH_TIME + 0.1)
	at.check(int(wc.current().mag) == 5, "M1911 toujours à 5 au retour")
	p.input.reload = true
	await seconds(dur + 0.3)
	at.check(ammo(0) == [8, 77] and srv_ammo(0) == [8, 77], "rechargement complet après le retour : %s / %s" % [ammo(0), srv_ammo(0)])

	# 3. Fusil à pompe (1/30) : changement à mi-course, cartouches poussées gardées.
	await equip(["stakeout", "m1911"], 1, 30)
	var sdur := game.combat.reload_time(1, pd.weapons[0])
	p.input.reload = true
	await seconds(sdur * (0.12 + 0.65 * 0.55))
	at.check(wc.is_reloading(), "fusil à pompe : rechargement en cours")
	p.input.switch_weapon = true
	await until(func(): return wc.current().get("id", "") == "m1911", 1.0, "changement vers le M1911")
	await seconds(sdur + 0.3)
	var kept := srv_ammo(0)
	at.check(kept[0] > 1 and kept[0] < 6 and kept[0] + kept[1] == 31, "cartouches poussées gardées, rien de perdu : %s" % [kept])
	at.check(ammo(0) == kept, "client = serveur : %s / %s" % [ammo(0), kept])
