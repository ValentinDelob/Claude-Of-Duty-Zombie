extends AutotestScenario
## [MP] Hôte : fait tomber des bonus ; c'est le CLIENT qui les ramasse. Le
## serveur valide le ramassage (position du client) et applique l'effet à
## tous : munitions max pour les deux joueurs, points doubles actifs partout.

const PORT := 17851

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pw := game.powerups
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var client: Player = game.players[client_id]
	var ok: bool = await until(func(): return client.global_position.distance_to(MapData.cell_to_world(Vector2i(3, 7))) < 1.0, 15.0, "client en position")
	if not ok:
		return
	# Réserves vidées chez les deux joueurs.
	for pid in game.session.data:
		for w in game.session.data[pid].weapons:
			w.reserve = 0
		game.session.sync_inventory(pid)
	var grabs := []
	pw.powerup_grabbed.connect(func(t: String, pid: int): grabs.append([t, pid]))
	await seconds(1.0)
	pw.debug_drop(PowerupRules.MAX_AMMO, MapData.cell_to_world(Vector2i(7, 7)))
	ok = await until(func(): return grabs.size() >= 1, 25.0, "munitions max ramassées")
	if not ok:
		return
	at.check(grabs[0][0] == PowerupRules.MAX_AMMO and grabs[0][1] == client_id, "munitions max ramassées par le client (%s)" % str(grabs[0]))
	var full := true
	for pid in game.session.data:
		for w in game.session.data[pid].weapons:
			full = full and w.reserve == WeaponDB.stats(w.id, w.pap).reserve
	at.check(full, "munitions max : réserve pleine pour l'hôte ET le client")
	at.check(game.local_player.weapons.current().reserve > 0, "arme de l'hôte rechargée")
	await seconds(1.5)
	pw.debug_drop(PowerupRules.DOUBLE_POINTS, MapData.cell_to_world(Vector2i(7, 9)))
	ok = await until(func(): return grabs.size() >= 2, 25.0, "points doubles ramassés")
	if not ok:
		return
	at.check(grabs[1][1] == client_id and pw.is_active(PowerupRules.DOUBLE_POINTS), "points doubles ramassés par le client, actifs chez l'hôte")
	at.check(game.points.multiplier == 2, "serveur : multiplicateur x2")
	# Gains doublés pour l'hôte aussi.
	var hpd := game.session.local_data()
	var before := hpd.points
	game.points.award(1, 50)
	await seconds(0.2)
	at.check(hpd.points - before == 100, "hôte : kill à +100 pendant les points doubles")
	await seconds(0.8)
	at.check(game.hud.powerup_hud.shown_icons().has(PowerupRules.DOUBLE_POINTS), "HUD de l'hôte : icône points doubles")
	await at.screenshot("hud")

	# FAUCHEUSE ramassée par le client : minigun pour lui seul, tirs validés.
	var rejects := []
	game.combat.shot_rejected.connect(func(_pid, r): rejects.append(r))
	await seconds(1.0)
	pw.debug_drop(PowerupRules.DEATH_MACHINE, MapData.cell_to_world(Vector2i(7, 7)))
	ok = await until(func(): return grabs.size() >= 3, 25.0, "faucheuse ramassée")
	if not ok:
		return
	var cpd := game.session.get_data(client_id)
	at.check(grabs[2][1] == client_id and cpd.current_weapon().get("id", "") == PowerupRules.DEATH_MACHINE_WEAPON, "faucheuse : minigun du client (serveur)")
	at.check(hpd.powerup_weapon.is_empty() and not pw.has_death_machine(1), "faucheuse : pas pour l'hôte")
	await seconds(0.5)
	at.check(client.visual.weapon_key.begins_with(PowerupRules.DEATH_MACHINE_WEAPON), "l'hôte voit le minigun dans les mains du client (%s)" % client.visual.weapon_key)
	var z := await H.dummy_zombie(self, MapData.cell_to_world(Vector2i(11, 7)), 3000)
	ok = await until(func(): return not z.is_alive(), 20.0, "zombie fauché par le client")
	at.check(ok and rejects.is_empty(), "faucheuse du client : tirs validés, zombie tué (%d refus %s)" % [rejects.size(), rejects])
	pw.death_machine[client_id] = 0.2
	await seconds(0.8)
	at.check(cpd.powerup_weapon.is_empty() and cpd.current_weapon().id != PowerupRules.DEATH_MACHINE_WEAPON, "fin de la faucheuse du client")
	await seconds(3.0)
