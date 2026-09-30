extends AutotestScenario
## Manche de chiens de l'enfer (BO1) dans le vrai jeu : modèle et explosion de
## flammes (brûlure des joueurs proches), manche forcée : annonce, brouillard,
## musique, compteur qui clignote, apparition par la foudre près du joueur,
## 2 chiens vivants au plus, poursuite et morsure, kills au fusil (points
## comme les zombies), MUNITIONS MAX sur le dernier chien, puis retour à une
## manche de zombies normale.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var dogs: DogRound
var max_alive_seen := 0
var min_spawn_dist := INF
var max_spawn_dist := 0.0
var spawned_ids := {}
var spawn_invisible_ok := true


func _on_spawned(z: Zombie) -> void:
	if not z is Hellhound:
		return
	spawned_ids[z.id] = true
	var d := Vector2(z.global_position.x - p.global_position.x, z.global_position.z - p.global_position.z).length()
	min_spawn_dist = minf(min_spawn_dist, d)
	max_spawn_dist = maxf(max_spawn_dist, d)


func _track() -> void:
	max_alive_seen = maxi(max_alive_seen, dogs.alive_dogs())
	for z: Zombie in game.zombies.alive:
		if z is Hellhound and z.state == Zombie.State.EMERGE and (z as Hellhound).skel.visible:
			spawn_invisible_ok = false


## Un bonus MUNITIONS MAX est-il au sol ?
func has_max_ammo_drop() -> bool:
	for id in game.powerups._drops:
		if game.powerups._drops[id].type == PowerupRules.MAX_AMMO:
			return true
	return false


## Premier chien révélé (hors apparition) ou null.
func revealed_dog() -> Hellhound:
	for z: Zombie in game.zombies.alive:
		if z is Hellhound and (z as Hellhound)._revealed:
			return z
	return null


func run() -> void:
	timeout_sec = 200
	p = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	pd = game.session.local_data()
	dogs = game.rounds.dogs
	await H.clear_zombies(self)
	at.check(dogs != null and dogs.get_path() == ^"/root/Game/Rounds/Dogs", "gestionnaire des chiens présent")
	at.check(not dogs.enabled, "manches de chiens coupées par défaut en autotest")
	at.check(dogs.next_dog_round >= 5 and dogs.next_dog_round <= 7, "première manche de chiens prévue en %d" % dogs.next_dog_round)
	var origin := MapData.cell_to_world(Vector2i(10, 7), 0.05)
	p.teleport_to(origin, -PI * 0.5)  # face à l'est (+X)
	await seconds(0.3)

	# ------------------------------------------------ modèle et explosion
	var spot := origin + Vector3(4.0, -0.05, 0.0)
	var zid := game.zombies.spawn(spot, 3, 400, ZombieManager.KIND_DOG)
	var dummy := game.zombies.get_zombie(zid) as Hellhound
	at.check(dummy != null, "type d'entité chien sur le canal des zombies")
	H.aim_at(p, spot + Vector3.UP * 1.3)
	await seconds(0.5)  # en pleine foudre (état vérifié pendant la fenêtre)
	at.check(not dummy.skel.visible and dummy.hit_body.collision_layer == 0, "invisible et intouchable pendant la foudre")
	await seconds(0.35)  # capture
	await at.screenshot("lightning")
	await until(func(): return not is_instance_valid(dummy._lightning) or dummy._lightning._struck, 1.0, "éclair")
	await frames(2)
	await at.screenshot("bolt")
	await until(func(): return dummy._revealed, 3.0, "chien révélé")
	# Figé pour la photo et l'explosion (plus de simulation serveur).
	dummy.set_physics_process(false)
	dummy.velocity = Vector3.ZERO
	dummy.yaw = 0.5
	dummy.rotation.y = dummy.yaw
	dummy.global_position = origin + Vector3(1.5, -0.05, 0.2)
	H.aim_at(p, dummy.global_position + Vector3(0, 0.5, 0))
	await seconds(0.6)  # capture
	await at.screenshot("model")
	var hp := pd.health
	var pts := pd.points
	game.combat.damage_zombie(zid, 1000, 1, false, Vector3.RIGHT, Combat.HitKind.BULLET)
	await until(func(): return not dummy.is_alive() and pd.health < hp and pd.points > pts, 2.0, "chien tué, brûlure et points")
	at.check(not dummy.is_alive(), "chien tué")
	at.check(hp - pd.health == DogRules.EXPLODE_DAMAGE, "explosion de flammes : brûlure de %d PV (%d -> %d)" % [DogRules.EXPLODE_DAMAGE, hp, pd.health])
	at.check(pd.points - pts == PointsRules.KILL, "kill de chien : +%d comme un zombie" % (pd.points - pts))
	await seconds(0.15)  # capture
	await at.screenshot("explode")
	at.check(game.powerups.drop_count() == 0, "un chien hors manche ne fait rien tomber")
	await seconds(2.0)  # fin des flammes avant la manche forcée

	# ------------------------------------------------ manche de chiens forcée
	game.combat.debug_invulnerable = false
	pd.weapons = [WeaponDB.new_instance("commando")]
	pd.slot = 0
	game.session.sync_inventory(1)
	for w in pd.weapons:
		w.reserve = 0
	game.session.sync_inventory(1)
	game.zombies.zombie_spawned.connect(_on_spawned)
	dogs.debug_force_next(5)
	game.rounds.paused = false
	game.rounds.debug_jump_to(5)
	await until(func(): return dogs.active and game.rounds.round_n == 5 and dogs.cl_active and game.hud.round_counter().special, 2.0, "annonce de la manche de chiens")
	at.check(dogs.active and game.rounds.round_n == 5, "manche 5 : manche de chiens")
	at.check(dogs.total == 6, "solo : 6 chiens (%d)" % dogs.total)
	at.check(game.rounds.to_spawn == 0 and game.zombies.alive_count() == 0, "aucun zombie")
	at.check(dogs.cl_active and game.hud.round_counter().special, "annonce reçue, compteur qui clignote")
	var env := (game.world.get_node("WorldEnvironment") as WorldEnvironment).environment
	# Montée du brouillard (fondu de 3 s) et musique.
	await until(func(): return dogs.fog_amount() > 0.95 and env.fog_density > WorldLook.BASE_FOG_DENSITY * 1.5 and Audio._music_name == "dog_round_music", 6.0, "brouillard de manche de chiens")
	at.check(dogs.fog_amount() > 0.95, "brouillard de manche de chiens (%.2f)" % dogs.fog_amount())
	at.check(env.fog_density > WorldLook.BASE_FOG_DENSITY * 1.5, "brouillard plus dense (%.3f)" % env.fog_density)
	at.check(Audio._music_name == "dog_round_music", "musique de manche de chiens")
	await at.screenshot("fog")

	# Apparition par la foudre (après l'annonce).
	var ok: bool = await until(func(): _track(); return not spawned_ids.is_empty(), DogRules.START_DELAY + 3.0, "premier chien")
	if not ok:
		return
	var first: Hellhound = game.zombies.get_zombie(spawned_ids.keys()[0])
	at.check(first.health == 400 and first.max_health == 400, "1re manche de chiens : 400 PV")
	H.aim_at(p, first.global_position + Vector3.UP * 1.4)
	await seconds(0.75)  # capture
	await at.screenshot("round_spawn")
	ok = await until(func(): _track(); return first._revealed, 2.5, "foudre puis chien")
	at.check(ok and first.state != Zombie.State.EMERGE, "le chien apparaît après l'éclair")

	# Poursuite et morsure (le joueur ne bouge pas).
	var d0 := first.global_position.distance_to(p.global_position)
	hp = pd.health
	ok = await until(func(): _track(); return pd.health < hp, 12.0, "morsure")
	at.check(ok, "le chien court (%.1f m) et mord : %d -> %d PV" % [d0, hp, pd.health])
	game.combat.debug_invulnerable = true
	await at.screenshot("bite")

	# Kills : fusil d'assaut, le bot vise les chiens visibles.
	var kills0 := pd.kills
	pts = pd.points
	var t := 0.0
	var _last_pos := Vector3.ZERO
	while (dogs.active and not dogs.srv_finished()) and t < 80.0:
		_track()
		var w: Dictionary = pd.current_weapon()
		if w.mag <= 3:
			w.mag = WeaponDB.stats(w.id).mag
			game.session.sync_inventory(1)
		var target := revealed_dog()
		if target:
			_last_pos = target.global_position
			H.aim_at(p, target.global_position + Vector3.UP * 0.5)
			p.input.fire = true
		else:
			p.input.fire = false
			# Retour au centre : les chiens apparaissent autour.
			if p.global_position.distance_to(origin) > 2.0:
				p.teleport_to(origin)
		await frames(1)
		t += get_delta()
	p.input.fire = false
	at.check(dogs.killed == 6 and spawned_ids.size() == 6, "6 chiens apparus et tués (%d / %d)" % [dogs.killed, spawned_ids.size()])
	at.check(max_alive_seen <= 2, "2 chiens vivants au plus (max %d)" % max_alive_seen)
	at.check(spawn_invisible_ok, "chiens invisibles pendant la foudre")
	at.check(min_spawn_dist >= 4.0, "apparitions près du joueur (%.1f à %.1f m)" % [min_spawn_dist, max_spawn_dist])
	at.check(pd.kills - kills0 == 6, "kills comptés (%d)" % (pd.kills - kills0))
	# 6 kills (+50) et au moins une touche non mortelle (+10) ; le nombre de
	# touches dépend de l'arme du bot.
	var gained := pd.points - pts
	at.check(gained > 6 * PointsRules.KILL and (gained - 6 * PointsRules.KILL) % PointsRules.HIT == 0, "points par touche et par kill (+%d)" % gained)

	# Munitions max sur le dernier chien, fin de manche.
	await until(func(): return has_max_ammo_drop() and game.rounds.phase == RoundManager.Phase.INTERMISSION, 2.0, "MUNITIONS MAX et entracte")
	var drop_ok := false
	var drop_pos := Vector3.ZERO
	for id in game.powerups._drops:
		var dr: Dictionary = game.powerups._drops[id]
		if dr.type == PowerupRules.MAX_AMMO:
			drop_ok = true
			drop_pos = dr.pos
	at.check(drop_ok, "le dernier chien fait tomber MUNITIONS MAX")
	at.check(drop_ok and Vector2(drop_pos.x - dogs.last_dog_pos.x, drop_pos.z - dogs.last_dog_pos.z).length() < 0.3, "à l'endroit du dernier chien")
	at.check(game.rounds.phase == RoundManager.Phase.INTERMISSION, "fin de la manche de chiens")
	at.check(dogs.next_dog_round == 9 or dogs.next_dog_round == 10, "prochaine manche de chiens : %d" % dogs.next_dog_round)
	if drop_ok:
		H.aim_at(p, drop_pos + Vector3.UP * 0.6)
		await seconds(0.4)  # capture
		await at.screenshot("max_ammo")
		p.teleport_to(drop_pos + Vector3.UP * 0.05)
		await until(func(): return pd.current_weapon().reserve == WeaponDB.stats("commando").reserve, 2.0, "MUNITIONS MAX ramassées")
		at.check(pd.current_weapon().reserve == WeaponDB.stats("commando").reserve, "munitions max ramassées : réserve pleine")
	# Fin de l'ambiance : délai puis fondu de 4 s du brouillard.
	await until(func(): return not dogs.cl_active and not game.hud.round_counter().special and dogs.fog_amount() < 0.05 and absf(env.fog_density - WorldLook.BASE_FOG_DENSITY) < 0.002, DogRules.FOG_CLEAR_DELAY + 8.0, "fin de l'ambiance de manche de chiens")
	at.check(not dogs.cl_active and not game.hud.round_counter().special, "fin de l'ambiance de manche de chiens")
	at.check(dogs.fog_amount() < 0.05 and absf(env.fog_density - WorldLook.BASE_FOG_DENSITY) < 0.002, "brouillard normal")

	# Manche suivante : zombies, progression normale.
	p.teleport_to(origin)
	ok = await until(func(): return game.rounds.round_n == 6 and game.rounds.phase == RoundManager.Phase.ACTIVE, RoundRules.INTERMISSION + 3.0, "manche 6")
	at.check(ok and not dogs.active, "manche 6 : retour des zombies")
	at.check(game.rounds.total == RoundRules.zombie_count(6, 1), "manche 6 : %d zombies" % game.rounds.total)
	ok = await until(func(): return game.zombies.alive_count() > 0, 8.0, "zombie de la manche 6")
	var z: Zombie = game.zombies.alive[0] if ok else null
	at.check(z != null and not z is Hellhound and z.max_health == RoundRules.zombie_health(6), "un zombie normal apparaît (%d PV)" % (z.max_health if z else 0))
	game.rounds.paused = true
	await seconds(0.5)


func get_delta() -> float:
	return at.get_process_delta_time()
