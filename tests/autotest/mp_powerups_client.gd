extends AutotestScenario
## [MP] Client : voit les bonus tombés par le serveur, marche dessus ; l'effet
## est appliqué et répliqué (réserve pleine, points doubles, icône du HUD).

const PORT := 17851


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var pw := game.powerups
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	var ok: bool = await until(func(): return pw.nodes.size() >= 1, 40.0, "bonus reçu du serveur")
	if not ok:
		return
	var node: PowerupDrop = pw.nodes.values()[0]
	at.check(node.type == PowerupRules.MAX_AMMO, "bonus au sol chez le client : %s" % node.type)
	at.check(pd.current_weapon().reserve == 0, "réserve vidée par le serveur")
	AutotestHelpers.aim_at(p, node.global_position + Vector3.UP * 0.8)
	await seconds(0.4)
	await at.screenshot("drop")
	p.teleport_to(node.global_position + Vector3.UP * 0.05)
	ok = await until(func(): return pw.nodes.is_empty(), 10.0, "bonus retiré après ramassage")
	at.check(ok, "ramassage validé par le serveur")
	ok = await until(func(): return pd.current_weapon().reserve == WeaponDB.stats(pd.current_weapon().id).reserve, 5.0, "réserve pleine")
	at.check(ok, "munitions max reçues (%d)" % pd.current_weapon().reserve)
	at.check(p.weapons.current().reserve == pd.current_weapon().reserve, "arme prédite du client synchronisée")
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	ok = await until(func(): return pw.nodes.size() >= 1, 20.0, "second bonus reçu")
	if not ok:
		return
	node = pw.nodes.values()[0]
	p.teleport_to(node.global_position + Vector3.UP * 0.05)
	ok = await until(func(): return pw.is_active(PowerupRules.DOUBLE_POINTS), 10.0, "points doubles actifs")
	at.check(ok, "points doubles actifs chez le client")
	await seconds(0.6)
	at.check(game.hud.powerup_hud.shown_icons().has(PowerupRules.DOUBLE_POINTS), "HUD du client : icône points doubles")
	await at.screenshot("hud")

	# FAUCHEUSE : ramassée, minigun en main, zombie fauché.
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	ok = await until(func(): return pw.nodes.size() >= 1, 20.0, "faucheuse reçue")
	if not ok:
		return
	node = pw.nodes.values()[0]
	p.teleport_to(node.global_position + Vector3.UP * 0.05)
	var dm := PowerupRules.DEATH_MACHINE_WEAPON
	ok = await until(func(): return p.weapons.current().get("id", "") == dm, 10.0, "minigun en main")
	at.check(ok and pw.has_death_machine(p.peer_id), "faucheuse : minigun du client")
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	ok = await until(func(): return game.zombies.alive.size() >= 1, 20.0, "zombie à faucher")
	if not ok:
		return
	var z: Zombie = game.zombies.alive[0]
	await seconds(Zombie.EMERGE_TIME + WeaponController.SWITCH_TIME)
	await at.screenshot("death_machine")
	AutotestHelpers.aim_at(p, z.global_position + Vector3.UP)
	p.input.fire = true
	ok = await until(func(): return not z.is_alive(), 8.0, "zombie fauché")
	p.input.fire = false
	at.check(ok, "faucheuse : zombie tué par le client")
	ok = await until(func(): return p.weapons.current().get("id", "") != dm, 10.0, "arme rendue")
	at.check(ok, "fin de la faucheuse : arme rendue au client (%s)" % p.weapons.current().get("id", ""))
	await seconds(2.0)
