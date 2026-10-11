extends AutotestScenario
## [MP] Hôte : l'Infirmière hurlante en réseau (hôte autoritaire). 1) Elle
## hurle sur le CLIENT : joueurs étourdis et zombies ameutés décidés ici,
## étourdissement appliqué par la machine du client (Player.srv_daze),
## zombies ameutés allumés chez tous (Nurse._cl_rally). 2) Vague forcée à
## deux joueurs : 2 Infirmières et 12 zombies d'escorte ; l'escorte est
## achevée par le serveur, le CLIENT abat une Infirmière (touches validées
## ici) : élimination et XP au client, échantillons tirés pour chacun.

const PORT := 17875

var H := AutotestHelpers


func cell(x: int, z: int) -> Vector3:
	return MapData.cell_to_world(Vector2i(x, z), 0.0)


func run() -> void:
	timeout_sec = 170
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = false
	var nr := game.rounds.nurse
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var client: Player = game.players[client_id]
	var cpd := game.session.get_data(client_id)
	var ok: bool = await until(func(): return client.global_position.distance_to(cell(18, 3)) < 1.0, 20.0, "client en position")
	if not ok:
		return
	game.local_player.teleport_to(cell(10, 9))
	await H.clear_zombies(self)

	# ------------------------------------------------ cri sur le client
	var horde: Array[int] = []
	for i in 2:
		horde.append(game.zombies.spawn(cell(4, 4 + i * 4), 0, 5000))
	var n := nr.debug_spawn(cell(10, 3), 50000)
	n.target = client
	n.scream_cooldown = 0.0
	var hp := cpd.health
	ok = await until(func(): return n.screams > 0, 12.0, "cri sur le client")
	at.check(ok and n.last_dazed.has(client_id), "l'Infirmière étourdit le client (%s)" % str(n.last_dazed))
	await seconds(0.3)
	at.check(cpd.health == hp - NurseRules.SCREAM_DAMAGE, "dégâts du cri au client : %d -> %d" % [hp, cpd.health])
	var rallied := 0
	for zid in horde:
		var z := game.zombies.get_zombie(zid)
		if z and z.rally_left > 0.0:
			rallied += 1
	at.check(rallied == 2 and n.last_rallied.size() == 2, "zombies ameutés par le cri (%d)" % rallied)
	await seconds(2.0)  # cri et étourdissement vus par le client avant le retrait
	game.zombies.despawn(n.id)
	for zid in horde:
		game.zombies.despawn(zid)
	game.combat.debug_invulnerable = true
	await seconds(0.5)

	# ------------------------------------------------ vague à deux joueurs
	cpd.weapons = [WeaponDB.new_instance("commando")]
	cpd.slot = 0
	game.session.sync_inventory(client_id)
	game.loot.debug_sample_chance = 1.0
	game.loot.debug_part_chance = 0.0
	nr.debug_force_next(3)
	game.rounds.paused = false
	game.rounds.debug_jump_to(3)
	await until(func(): return nr.active, 2.0, "vague de l'Infirmière lancée")
	at.check(nr.active and nr.total == 2 and game.rounds.to_spawn == 12, "2 joueurs : %d Infirmières, %d zombies d'escorte" % [nr.total, game.rounds.to_spawn])
	var t := 0.0
	var weakened := {}
	var spawned_n := {}
	while game.rounds.phase != RoundManager.Phase.INTERMISSION and t < 120.0:
		for z: Zombie in game.zombies.alive.duplicate():
			if z.state == Zombie.State.EMERGE:
				continue
			if z is Nurse:
				spawned_n[z.id] = true
				# La première : PV réduits, au client de l'abattre (immobile,
				# sans cri) ; les autres (et celle-là si elle traîne) achevées ici.
				if weakened.is_empty():
					weakened[z.id] = t
					z.health = 300
					z.global_position = cell(12, 3)
					z.set_physics_process(false)
					(z as Nurse).scream_cooldown = 999.0
				elif not weakened.has(z.id) or t - float(weakened[z.id]) > 25.0:
					game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
			else:
				game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
		await frames(1)
		t += at.get_process_delta_time()
	at.check(game.rounds.phase == RoundManager.Phase.INTERMISSION and nr.killed == 2, "vague vaincue : 2 Infirmières tuées (%d)" % nr.killed)
	at.check(spawned_n.size() == 2, "2 Infirmières apparues")
	var xp_client: Dictionary = game.xp.ledger(client_id)
	at.check(int(xp_client.kills.get(XpRules.NURSE, 0)) == 1, "XP de l'Infirmière au client qui l'a abattue (%s)" % str(xp_client.kills))
	var s: Dictionary = game.loot.samples.get(client_id, {})
	at.check(int(s.get("nurse_vocal_cords", 0)) == 14 and int(s.get("nurse_badge", 0)) == 14,
		"échantillons du client : tirés sur les 14 zombies de la vague (%s)" % str(s))
	ok = await until(func(): return game.loot.drops.size() == 2, 3.0, "armes de butin")
	at.check(ok, "une arme de butin par joueur")
	at.check(nr.next_round == 0 or nr.next_round > 3, "prochaine vague de l'Infirmière replanifiée (%d)" % nr.next_round)
	await MpHelpers.finish(self)
