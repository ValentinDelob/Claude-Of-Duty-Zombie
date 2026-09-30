extends AutotestScenario
## [MP] Client : fente au couteau sur les zombies (marionnettes) apparus devant
## lui ; reçoit le couteau de chasse (animation de récupération) puis frappe.

const PORT := 17881


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
			# Retour au point de départ, puis couteau de chasse donné par l'hôte.
			p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
			ok = await until(func(): return p.weapons.knife_id == "bowie", 15.0, "couteau de chasse reçu")
			at.check(ok and p.weapons.is_picking_up_knife(), "récupération du couteau de chasse (client)")
			await seconds(0.8)
			await at.screenshot("bowie_pickup")
			await until(func(): return not p.weapons.is_picking_up_knife(), 3.0, "fin de récupération")
			MpHelpers.signal_peer("bowie_en_main")
	at.check(pd.knife == "bowie", "inventaire client : couteau de chasse")
	await MpHelpers.finish(self)
