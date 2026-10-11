extends AutotestScenario
## [MP] Hôte : le Brancardier en réseau (hôte autoritaire). 1) Un Brancardier
## charge le CLIENT : touche, dégâts et projection décidés ici, appliqués par
## la machine du client (srv_knockback), choc contre le mur. 2) Vague forcée
## à deux joueurs : 2 Brancardiers et 10 zombies d'escorte ; l'escorte est
## achevée par le serveur, le CLIENT abat un Brancardier (touches validées
## ici) : élimination et XP au client, échantillons tirés pour chacun.

const PORT := 17873

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
	var br := game.rounds.brancard
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

	# ------------------------------------------------ charge sur le client
	var b := br.debug_spawn(cell(10, 3), 50000)
	b.charge_cooldown = 0.0
	b.target = client
	var hit := [0]
	b.charge_hit_player.connect(func(pid): hit[0] = pid)
	var hp := cpd.health
	ok = await until(func(): return hit[0] != 0, 12.0, "charge sur le client")
	at.check(ok and hit[0] == client_id, "le Brancardier percute le client (%d)" % hit[0])
	at.check(cpd.health == hp - BrancardRules.CHARGE_DAMAGE, "dégâts de la charge au client : %d -> %d" % [hp, cpd.health])
	ok = await until(func(): return b.wall_hits > 0, 4.0, "choc contre le mur")
	at.check(ok and b.charge_phase == Brancardier.Phase.STUN, "mur heurté : étourdi")
	await seconds(2.5)  # étourdi vu par le client avant le retrait
	game.zombies.despawn(b.id)
	game.combat.debug_invulnerable = true
	await seconds(0.5)

	# ------------------------------------------------ vague à deux joueurs
	cpd.weapons = [WeaponDB.new_instance("commando")]
	cpd.slot = 0
	game.session.sync_inventory(client_id)
	game.loot.debug_sample_chance = 1.0
	game.loot.debug_part_chance = 0.0
	br.debug_force_next(3)
	game.rounds.paused = false
	game.rounds.debug_jump_to(3)
	await until(func(): return br.active, 2.0, "vague du Brancardier lancée")
	at.check(br.active and br.total == 2 and game.rounds.to_spawn == 10, "2 joueurs : %d Brancardiers, %d zombies d'escorte" % [br.total, game.rounds.to_spawn])
	var t := 0.0
	var weakened := {}
	var spawned_b := {}
	while game.rounds.phase != RoundManager.Phase.INTERMISSION and t < 120.0:
		for z: Zombie in game.zombies.alive.duplicate():
			if z.state == Zombie.State.EMERGE:
				continue
			if z is Brancardier:
				spawned_b[z.id] = true
				# Le premier : PV réduits, au client de l'abattre ; les autres
				# (et celui-là s'il traîne) achevés par le serveur.
				if weakened.is_empty():
					# Placé dans l'axe du client, à 7 m, sans charge.
					weakened[z.id] = t
					z.health = 300
					z.global_position = cell(12, 3)
					z.set_physics_process(false)  # cible immobile pour le client
					z.target = client
					(z as Brancardier).charge_cooldown = 999.0
				elif not weakened.has(z.id) or t - float(weakened[z.id]) > 25.0:
					game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
			else:
				game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
		await frames(1)
		t += at.get_process_delta_time()
	at.check(game.rounds.phase == RoundManager.Phase.INTERMISSION and br.killed == 2, "vague vaincue : 2 Brancardiers tués (%d)" % br.killed)
	at.check(spawned_b.size() == 2, "2 Brancardiers apparus")
	var xp_client: Dictionary = game.xp.ledger(client_id)
	at.check(int(xp_client.kills.get(XpRules.BRANCARDIER, 0)) == 1, "XP du Brancardier au client qui l'a abattu (%s)" % str(xp_client.kills))
	var s: Dictionary = game.loot.samples.get(client_id, {})
	at.check(int(s.get("brancard_strap", 0)) == 12 and int(s.get("brancard_bracelet", 0)) == 12, "échantillons du client : tirés sur les 12 zombies de la vague (%s)" % str(s))
	ok = await until(func(): return game.loot.drops.size() == 2, 3.0, "armes de butin")
	at.check(ok, "une arme de butin par joueur")
	await MpHelpers.finish(self)
