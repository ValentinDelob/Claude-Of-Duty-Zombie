extends AutotestScenario
## [MP] Client : fente au couteau sur les zombies (marionnettes) apparus devant
## lui, deux fois (le couteau de chasse est supprimé : lot C).

const PORT := 17885


func run() -> void:
	timeout_sec = 110
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	for k in 2:
		var ok: bool = await until(func(): return game.zombies.alive_count() >= 1, 30.0, "zombie reçu")
		if not ok:
			return
		var z: Zombie = game.zombies.alive[0]
		await until(func(): return z.state != Zombie.State.EMERGE, Zombie.EMERGE_TIME + 3.0, "zombie sorti de terre")
		await seconds(0.3)  # fin du redressement (animation)
		AutotestHelpers.aim_at(p, z.global_position + Vector3.UP * 1.2)
		await seconds(0.1)  # visée
		p.input.melee = true
		await until(func(): return not p.input.melee, 1.0, "couteau pris en compte")
		at.check(p.weapons.lunging, "fente locale %d" % (k + 1))
		await seconds(0.12)
		await at.screenshot("lunge_%d" % k)
		ok = await until(func(): return game.zombies.alive_count() == 0, 5.0, "zombie mort")
		at.check(ok, "zombie tué (coup %d)" % (k + 1))
		if k == 0:
			# Retour au point de départ, puis second zombie.
			p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
			MpHelpers.signal_peer("retour")
	at.check(pd.knife == KnifeDB.DEFAULT, "inventaire client : couteau de base")

	# 3. Batte en main (donnée par l'hôte) : coup sur le zombie devant soi.
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	MpHelpers.signal_peer("pret_batte")
	if not await MpHelpers.wait_peer(self, "batte", 20.0):
		return
	var got: bool = await until(func(): return p.weapons.current().get("id", "") == "bat" and game.zombies.alive_count() >= 1, 10.0, "batte en main, zombie reçu")
	if not got:
		return
	var zb: Zombie = game.zombies.alive[0]
	await until(func(): return zb.state != Zombie.State.EMERGE, Zombie.EMERGE_TIME + 3.0, "zombie sorti de terre")
	await seconds(WeaponController.SWITCH_TIME + 0.3)  # batte sortie, zombie redressé
	AutotestHelpers.aim_at(p, zb.global_position + Vector3.UP * 1.2)
	await seconds(0.1)  # visée
	p.input.fire = true
	await until(func(): return p.weapons.view.is_swinging(), 1.0, "coup de batte lancé")
	p.input.fire = false
	at.check(p.weapons.view.is_swinging(), "coup de batte local")
	await seconds(0.25)
	await at.screenshot("bat_swing")
	await MpHelpers.finish(self)
