extends AutotestScenario
## [MP] Hôte : force une manche de chiens à deux joueurs (12 chiens, 4 vivants
## au plus, chaque chien chasse le joueur le moins chassé). Le CLIENT tire sur
## les chiens : ses touches sont validées ici contre la position serveur. Les
## chiens que le client n'abat pas assez vite sont achevés par le serveur.
## Le dernier chien fait tomber des munitions max.

const PORT := 17871

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var dogs := game.rounds.dogs
	# Le dernier chien peut tomber aux pieds d'un joueur qui ramasse aussitôt le bonus.
	var grabbed: Array = []
	game.powerups.powerup_grabbed.connect(func(type: String, _pid: int): grabbed.append(type))
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	var client: Player = game.players[client_id]
	var cpd := game.session.get_data(client_id)
	var ok: bool = await until(func(): return client.global_position.distance_to(MapData.cell_to_world(Vector2i(10, 7))) < 1.0, 15.0, "client en position")
	if not ok:
		return
	game.local_player.teleport_to(MapData.cell_to_world(Vector2i(10, 9), 0.05))
	cpd.weapons = [WeaponDB.new_instance("commando")]
	cpd.slot = 0
	game.session.sync_inventory(client_id)
	await H.clear_zombies(self)
	await seconds(0.5)
	dogs.debug_force_next(2)
	game.rounds.paused = false
	game.rounds.debug_jump_to(2)
	await seconds(0.3)
	at.check(dogs.active and dogs.total == 12, "manche de chiens à 2 joueurs : %d chiens" % dogs.total)
	var max_alive := 0
	var hunted := {}
	var revealed_at := {}
	var t := 0.0
	while not (game.rounds.phase == RoundManager.Phase.INTERMISSION) and t < 110.0:
		max_alive = maxi(max_alive, dogs.alive_dogs())
		for z: Zombie in game.zombies.alive:
			var d := z as Hellhound
			if d == null or not d._revealed:
				continue
			if d.favorite_enemy:
				hunted[d.favorite_enemy.peer_id] = hunted.get(d.favorite_enemy.peer_id, 0) + (0 if revealed_at.has(d.id) else 1)
			if not revealed_at.has(d.id):
				revealed_at[d.id] = t
			elif t - revealed_at[d.id] > 7.0:
				# Filet de sécurité : le serveur achève le chien.
				game.combat.damage_zombie(d.id, d.health + 1, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
		await frames(1)
		t += at.get_process_delta_time()
	at.check(game.rounds.phase == RoundManager.Phase.INTERMISSION and dogs.killed == 12, "12 chiens tués, fin de manche (%d)" % dogs.killed)
	at.check(max_alive <= 4, "4 chiens vivants au plus (max %d)" % max_alive)
	at.check(hunted.get(1, 0) > 0 and hunted.get(client_id, 0) > 0, "les chiens se répartissent les proies (%s)" % str(hunted))
	at.check(cpd.kills >= 2, "chiens abattus par les tirs du client (validés serveur) : %d" % cpd.kills)
	var drop := grabbed.has(PowerupRules.MAX_AMMO)
	for id in game.powerups._drops:
		drop = drop or game.powerups._drops[id].type == PowerupRules.MAX_AMMO
	at.check(drop, "munitions max sur le dernier chien")
	await seconds(8.0)
