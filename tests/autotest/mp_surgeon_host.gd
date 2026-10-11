extends AutotestScenario
## [MP] Hôte : le Chirurgien en réseau (hôte autoritaire). 1) Il lance ses
## scalpels sur le CLIENT : vol simulé partout, touche et dégâts décidés
## ici. 2) Changement de phase près du client : onde de choc, projection
## appliquée par la machine du client (srv_knockback). 3) Vague forcée à
## deux joueurs : un boss aux PV de deux joueurs, 12 zombies d'escorte
## achevés par le serveur ; le CLIENT abat le boss en visant son cœur
## (touches validées ici) : élimination et XP au client, échantillons tirés
## pour chacun, deux armes de butin par joueur.

const PORT := 17877

var H := AutotestHelpers


func cell(x: int, z: int) -> Vector3:
	return MapData.cell_to_world(Vector2i(x, z), 0.0)


func run() -> void:
	timeout_sec = 190
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = false
	var sr := game.rounds.surgeon
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

	# ------------------------------------------------ scalpels sur le client
	var s := sr.debug_spawn(cell(8, 3), 200000)
	s.target = client
	s.throw_cooldown = 0.0
	s.slash_cooldown = 999.0
	var hp := cpd.health
	ok = await until(func(): return sr.scalpels.player_hits > 0, 12.0, "scalpel dans le client")
	at.check(ok, "un scalpel touche le client (%d lancés)" % sr.scalpels.thrown)
	at.check(cpd.health <= hp - SurgeonRules.THROW_DAMAGE, "dégâts du scalpel au client : %d -> %d" % [hp, cpd.health])
	await seconds(1.5)

	# ------------------------------------------------ onde de choc près du client
	cpd.health = cpd.max_health
	game.session.sync_stats(client_id)
	s.throw_cooldown = 999.0
	s.global_position = client.global_position + Vector3(-2.5, 0.0, 0.0)
	await seconds(0.5)
	hp = cpd.health
	var shock := [-1]
	s.shock_wave.connect(func(n): shock[0] = n)
	s.health = 99000
	ok = await until(func(): return shock[0] >= 0, 4.0, "onde de choc")
	at.check(ok and shock[0] == 1 and s.rage, "changement de phase : onde de choc sur le client")
	await seconds(0.3)
	at.check(cpd.health <= hp - SurgeonRules.SHOCK_DAMAGE, "dégâts de l'onde de choc au client : %d -> %d" % [hp, cpd.health])
	await seconds(2.5)  # rugissement vu par le client avant le retrait
	game.zombies.despawn(s.id)
	game.combat.debug_invulnerable = true
	await seconds(0.5)

	# ------------------------------------------------ vague à deux joueurs
	cpd.weapons = [WeaponDB.new_instance("commando")]
	cpd.slot = 0
	game.session.sync_inventory(client_id)
	game.loot.debug_sample_chance = 1.0
	game.loot.debug_part_chance = 0.0
	sr.debug_force_next(3)
	game.rounds.paused = false
	game.rounds.debug_jump_to(3)
	await until(func(): return sr.active, 2.0, "vague du Chirurgien lancée")
	at.check(sr.active and sr.total == 1 and game.rounds.to_spawn == 12, "2 joueurs : 1 boss, %d zombies d'escorte" % game.rounds.to_spawn)
	var t := 0.0
	var boss_id := -1
	var max_hp := 0
	while game.rounds.phase != RoundManager.Phase.INTERMISSION and t < 120.0:
		for z: Zombie in game.zombies.alive.duplicate():
			if z.state == Zombie.State.EMERGE:
				continue
			if z is Surgeon:
				if boss_id < 0:
					# Au client de l'abattre : PV réduits, immobile, à 7 m dans son axe.
					boss_id = z.id
					max_hp = z.max_health
					z.health = 400
					z.global_position = cell(11, 3)
					z.set_physics_process(false)
					z.target = client
				elif t > 60.0:
					game.combat.damage_zombie(z.id, 99999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
			else:
				game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
		await frames(1)
		t += at.get_process_delta_time()
	at.check(max_hp == SurgeonRules.health(3, 1, 2), "PV du boss à deux joueurs : %d" % max_hp)
	at.check(game.rounds.phase == RoundManager.Phase.INTERMISSION and sr.killed == 1, "vague de boss vaincue")
	var xp_client: Dictionary = game.xp.ledger(client_id)
	at.check(int(xp_client.kills.get(XpRules.SURGEON, 0)) == 1, "XP du Chirurgien au client qui l'a abattu (%s)" % str(xp_client.kills))
	var smp: Dictionary = game.loot.samples.get(client_id, {})
	at.check(int(smp.get("surgeon_scalpel", 0)) == 13 and int(smp.get("surgeon_heart", 0)) == 13,
		"échantillons du client : escorte et boss (%s)" % str(smp))
	ok = await until(func(): return game.loot.drops.size() == 4, 3.0, "armes de butin")
	at.check(ok, "deux armes de butin par joueur (%d)" % game.loot.drops.size())
	await MpHelpers.finish(self)
