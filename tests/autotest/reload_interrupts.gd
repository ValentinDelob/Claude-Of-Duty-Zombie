extends AutotestScenario
## Actions du serveur qui interrompent l'arme pendant un rechargement (BO1) :
## achat mural (munitions, nouvelle arme), boîte mystère, Pack-a-Punch (dépôt
## et reprise), FAUCHEUSE (bonus), mise à terre. Chaque fois : rechargement
## annulé côté serveur ET client (prévenu), rien rempli à l'échéance, client
## et serveur d'accord sur les munitions.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var wc: WeaponController


## Arme `ids[0]` en main, chargeur `mag0` / réserve `reserve0`.
func equip(ids: Array, mag0: int, reserve0: int) -> bool:
	pd.weapons = []
	for id in ids:
		pd.weapons.append(WeaponDB.new_instance(id))
	pd.weapons[0].mag = mag0
	pd.weapons[0].reserve = reserve0
	pd.slot = 0
	game.combat.cancel_reload(1)
	game.session.sync_inventory(1)
	var ok: bool = await until(func(): return wc.current().get("id", "") == ids[0] and int(wc.current().mag) == mag0, 2.0, "%s en main" % ids[0])
	await seconds(WeaponController.SWITCH_TIME + 0.2)
	return ok


## Lance un rechargement (client puis serveur) ; durée, ou -1 en cas d'échec.
func start_reload() -> float:
	p.input.reload = true
	var ok: bool = await until(func(): return wc.is_reloading() and game.combat.is_reloading(1), 1.0, "rechargement en cours")
	if not ok:
		return -1.0
	await seconds(0.2)
	return game.combat.reload_time(1, pd.current_weapon())


func stopped(label: String) -> void:
	await frames(3)
	at.check(not game.combat.is_reloading(1), "%s : rechargement serveur annulé" % label)
	at.check(not wc.is_reloading(), "%s : rechargement client annulé" % label)


## Munitions [chargeur, réserve] de l'arme `id` (client, serveur).
func ammo_of(id: String) -> Array:
	var c := []
	for w in wc.weapons:
		if w.id == id:
			c = [int(w.mag), int(w.reserve)]
	var s := []
	for w in pd.weapons:
		if w.id == id:
			s = [int(w.mag), int(w.reserve)]
	return [c, s]


## Au-delà de l'échéance du rechargement annulé : l'arme `id` vaut `expect`
## des deux côtés.
func unchanged(label: String, id: String, expect: Array, dur: float) -> void:
	await seconds(dur + 0.3)
	var a := ammo_of(id)
	at.check(a[0] == expect and a[1] == expect, "%s : %s inchangé (client %s, serveur %s)" % [label, id, a[0], a[1]])


func find_obj(cls: String) -> Interactable:
	for o in game.interact.objects.values():
		if o.get_script() and o.get_script().get_global_name() == cls:
			if cls == "WallBuy" and (o as WallBuy).is_knife:
				continue
			return o
	return null


func run() -> void:
	timeout_sec = 150
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	pd = game.session.local_data()
	wc = p.weapons
	for id in game.doors:
		game.doors[id].srv_open()
	var power: Interactable = game.interact.get_obj("power")
	if power:
		(power as PowerSwitch).srv_use(1)
	game.session.add_points(1, 100000)
	await seconds(0.5)

	# 1. Achat mural de munitions pendant le rechargement de cette arme.
	var wb := find_obj("WallBuy") as WallBuy
	at.check(wb != null, "achat mural présent")
	if wb:
		var wid := wb.weapon_id
		await equip([wid, "m1911"], 1, 10)
		var dur := await start_reload()
		wb.srv_use(1)
		await stopped("achat de munitions")
		var full := WeaponDB.new_instance(wid)
		await unchanged("achat de munitions", wid, [int(full.mag), int(full.reserve)], dur)

		# 2. Achat mural d'une nouvelle arme pendant le rechargement du M1911.
		await equip(["m1911"], 5, 80)
		dur = await start_reload()
		wb.srv_use(1)
		await stopped("achat d'une arme")
		at.check(wc.current().get("id", "") == wid, "nouvelle arme en main")
		await unchanged("achat d'une arme", "m1911", [5, 80], dur)

	# 3. Boîte mystère : arme prise pendant le rechargement.
	var box := find_obj("MysteryBox") as MysteryBox
	at.check(box != null, "boîte mystère présente")
	if box:
		await equip(["m1911"], 5, 80)
		box.force_result = "ak74u"
		box.srv_use(1)
		var ok: bool = await until(func(): return box.state == MysteryBox.State.READY, MysteryBox.ROLL_TIME + 3.0, "tirage de la boîte")
		if ok:
			var dur := await start_reload()
			box.srv_use(1)
			await stopped("boîte mystère")
			at.check(wc.current().get("id", "") == "ak74u", "arme de la boîte en main")
			await unchanged("boîte mystère", "m1911", [5, 80], dur)

	# 4. Pack-a-Punch : dépôt de l'arme en cours de rechargement, puis reprise
	# pendant le rechargement de l'autre arme.
	var pap := find_obj("PackAPunch") as PackAPunch
	if pap == null:
		print("[reload_interrupts] pas de Pack-a-Punch sur cette carte : cas ignoré")
	else:
		await equip(["m1911", "mp40"], 5, 80)
		var dur := await start_reload()
		pap.srv_use(1)
		await stopped("dépôt au Pack-a-Punch")
		at.check(wc.current().get("id", "") == "mp40", "MP40 en main pendant l'amélioration")
		var ok: bool = await until(func(): return pap.state == PackAPunch.State.READY, PackAPunch.WORK_TIME + 3.0, "amélioration finie")
		if ok:
			pd.current_weapon().mag = 10
			var res: int = pd.current_weapon().reserve
			game.session.sync_inventory(1)
			await until(func(): return int(wc.current().mag) == 10, 1.0, "MP40 entamé")
			dur = await start_reload()
			pap.srv_use(1)
			await stopped("reprise au Pack-a-Punch")
			await unchanged("reprise au Pack-a-Punch", "mp40", [10, res], dur)

	# 5. FAUCHEUSE (bonus) ramassée pendant le rechargement, puis fin du bonus.
	await equip(["m1911"], 5, 80)
	var d5 := await start_reload()
	game.powerups._give_death_machine(1)
	await stopped("FAUCHEUSE")
	game.powerups.end_death_machine(1)
	await unchanged("FAUCHEUSE", "m1911", [5, 80], d5)

	# 6. Mise à terre pendant le rechargement (LAZARUS : relevé seul en solo).
	game.perks.srv_grant(1, "lazarus")
	await until(func(): return GameClock.now() >= wc._drink_end and not wc.view.is_drinking(), 4.0, "fin de la boisson")
	await equip(["m1911", "mp40"], 5, 80)
	var d6 := await start_reload()
	game.combat.debug_invulnerable = false
	game.combat.damage_player(1, 500, p.global_position + Vector3(1, 1, 0))
	game.combat.debug_invulnerable = true
	await until(func(): return pd.life == PlayerData.Life.DOWNED, 2.0, "joueur à terre")
	await stopped("mise à terre")
	await unchanged("mise à terre", "m1911", [5, 80], d6)
