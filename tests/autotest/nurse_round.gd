extends AutotestScenario
## Vague spéciale « Infirmière hurlante » dans le vrai jeu (GAME_CONCEPT.md
## §4.4) : modèle cubique, gorge point faible (vrais tirs validés par le
## serveur), elle FUIT quand on s'approche, CRI télégraphié (préparation :
## immobile, tête renversée) qui étourdit le joueur en vue (vue qui tangue,
## image en cubes, déplacement ralenti, 10 dégâts) et AMEUTE les zombies
## proches (accélérés, yeux qui flamboient), cri ÉTRANGLÉ par une balle dans
## la gorge pendant la préparation ; vague forcée (manche 20) : bandeau,
## compteur qui clignote, musique, 1 Infirmière (PV de la formule) et son
## escorte, échantillons (cordes vocales, seringue, badge) sur chaque zombie
## de la vague, XP du mini-boss au tueur, mort sur le dos, arme de butin et
## porte d'évacuation à la fin, rotation (Infirmière suivante à la 30).

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData


func cell(x: int, z: int) -> Vector3:
	return MapData.cell_to_world(Vector2i(x, z), 0.0)


func first_nurse() -> Nurse:
	for z: Zombie in game.zombies.alive:
		if z is Nurse:
			return z
	return null


func run() -> void:
	timeout_sec = 260
	p = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	pd = game.session.local_data()
	await H.clear_zombies(self)
	var nr := game.rounds.nurse
	at.check(nr != null and nr.get_path() == ^"/root/Game/Rounds/Nurse", "gestionnaire de l'Infirmière présent")
	at.check(not nr.enabled, "vagues de l'Infirmière coupées par défaut en autotest")
	at.check(nr.next_round == 20 and game.rounds.brancard.next_round == 10 and game.rounds.dogs.next_dog_round == 5,
		"rotation : meute 5, Brancardier 10, boss 15, Infirmière 20 (%d)" % nr.next_round)

	# ------------------------------------------------ modèle, gorge point faible
	p.teleport_to(cell(8, 3), -PI * 0.5)  # face à l'est (+X)
	await seconds(0.3)
	var n := nr.debug_spawn(cell(12, 3), 20000)
	at.check(n != null and n.mesh.mesh == NurseModel.model().mesh, "type d'entité Infirmière, modèle cubique")
	if n == null:
		return
	n.set_physics_process(false)
	n.yaw = -PI * 0.5 + 0.4
	n.rotation.y = n.yaw
	H.aim_at(p, n.global_position + Vector3.UP * 1.2)
	await seconds(1.0)
	await at.screenshot("model")
	pd.weapons = [WeaponDB.new_instance("commando")]
	pd.slot = 0
	game.session.sync_inventory(1)
	await seconds(0.3)
	var hits := [0, 0]  # [dégâts d'une touche à la tête / gorge, d'une au corps]
	var on_dmg := func(_pid, zid, dmg, _killed, headshot, _kind):
		if zid == n.id:
			hits[0 if headshot else 1] = maxi(hits[0 if headshot else 1], dmg)
	game.combat.zombie_damaged.connect(on_dmg)
	H.aim_at(p, n.global_position + Vector3.UP * 0.95)
	p.input.fire = true
	await until(func():
		H.aim_at(p, n.global_position + Vector3.UP * 0.95)
		return hits[1] > 0, 3.0, "touche au corps")
	p.input.fire = false
	await seconds(0.3)
	p.input.fire = true
	await until(func():
		H.aim_at(p, n.throat_position())
		return hits[0] > 0, 3.0, "touche à la gorge")
	p.input.fire = false
	game.combat.zombie_damaged.disconnect(on_dmg)
	at.check(hits[1] > 0 and hits[0] >= roundi(WeaponDB.stats("commando").damage * 2.0),
			"gorge (point faible) : %d dégâts par touche, corps : %d" % [hits[0], hits[1]])
	game.zombies.despawn(n.id)
	await seconds(0.3)

	# ------------------------------------------------ elle garde ses distances
	p.teleport_to(cell(6, 7), -PI * 0.5)
	n = nr.debug_spawn(cell(8, 7), 50000)
	n.scream_cooldown = 999.0
	n.target = p
	var ok: bool = await until(func(): return n.flee_starts > 0, 4.0, "fuite")
	at.check(ok, "trop près : elle s'enfuit")
	ok = await until(func():
		H.aim_at(p, n.global_position + Vector3.UP * 1.2)
		return Vector2(n.global_position.x - p.global_position.x, n.global_position.z - p.global_position.z).length() > NurseRules.FLEE_DIST + 0.5, 6.0, "distance reprise")
	at.check(ok, "elle a repris ses distances (%.1f m)" % n.global_position.distance_to(p.global_position))
	await at.screenshot("flee")
	game.zombies.despawn(n.id)
	await seconds(0.3)

	# ------------------------------------------------ le cri : étourdit et ameute
	game.combat.debug_invulnerable = false
	pd.health = pd.max_health
	game.session.sync_stats(1)
	p.teleport_to(cell(6, 7), -PI * 0.5)
	n = nr.debug_spawn(cell(13, 7), 50000)
	n.target = p
	n.scream_cooldown = 0.0
	# Zombies ordinaires plus loin, qui doivent être ameutés.
	var horde: Array[Zombie] = []
	for i in 3:
		var zid := game.zombies.spawn(cell(18, 4 + i * 3), 0, 5000)
		horde.append(game.zombies.get_zombie(zid))
	var started := [false]
	n.scream_started.connect(func(): started[0] = true)
	var hp := pd.health
	var dazes := p.dazes
	ok = await until(func():
		H.aim_at(p, n.global_position + Vector3.UP * 1.3)
		return n.scream_phase == Nurse.Phase.WINDUP, 6.0, "préparation du cri")
	at.check(ok and started[0], "préparation du cri (télégraphiée)")
	await seconds(0.6)
	at.check(n.scream_phase == Nurse.Phase.WINDUP and n.anim_speed < 0.6, "immobile pendant la préparation")
	await at.screenshot("windup")
	ok = await until(func(): return n.scream_phase == Nurse.Phase.SCREAM, 2.0, "cri")
	at.check(ok and n.screams == 1, "cri après %.1f s de préparation" % NurseRules.WINDUP_TIME)
	await seconds(0.25)
	await at.screenshot("scream")
	await until(func(): return p.dazes == dazes + 1, 1.0, "joueur étourdi")
	at.check(p.dazes == dazes + 1 and p.daze_amount() > 0.3, "joueur étourdi (force %.2f)" % p.daze_amount())
	at.check(pd.health == hp - NurseRules.SCREAM_DAMAGE, "cri : %d -> %d PV" % [hp, pd.health])
	at.check(p.current_max_speed() < Player.WALK_SPEED * 0.85, "étourdi : déplacement ralenti (%.2f m/s)" % p.current_max_speed())
	at.check(Array(XpRules.met_types(game.xp.my_ledger)).has(XpRules.NURSE), "cri reçu : Infirmière rencontrée (codex)")
	var rallied := 0
	for z in horde:
		if is_instance_valid(z) and z.rally_left > 0.0 and z.rally_target == p and z.rally_mult > 1.0:
			rallied += 1
	at.check(rallied == horde.size() and n.last_rallied.size() >= horde.size(), "zombies proches ameutés (%d / %d)" % [rallied, horde.size()])
	H.aim_at(p, horde[0].global_position + Vector3.UP * 1.4)
	await seconds(0.3)
	await at.screenshot("dazed")
	await until(func(): return p.daze_amount() == 0.0, NurseRules.DAZE_TIME_MAX + 1.0, "fin de l'étourdissement")
	at.check(p.daze_amount() == 0.0 and absf(p.current_max_speed() - Player.WALK_SPEED * float(p.weapons.current_stats().get("move_mult", 1.0))) < 0.05, "étourdissement terminé")
	for z in horde:
		if is_instance_valid(z):
			game.zombies.despawn(z.id)
	ok = await until(func(): return n.scream_phase == Nurse.Phase.NONE, NurseRules.SCREAM_TIME + 1.0, "fin du cri")
	at.check(ok, "fin du cri, elle reprend")

	# ------------------------------------------------ cri étranglé (gorge)
	pd.health = pd.max_health
	game.session.sync_stats(1)
	n.global_position = cell(13, 7)
	n.scream_cooldown = 0.0
	dazes = p.dazes
	ok = await until(func():
		H.aim_at(p, n.global_position + Vector3.UP * 1.3)
		return n.scream_phase == Nurse.Phase.WINDUP, 6.0, "deuxième préparation")
	at.check(ok, "deuxième préparation du cri")
	p.input.fire = true
	ok = await until(func():
		H.aim_at(p, n.throat_position())
		return n.chokes > 0, NurseRules.WINDUP_TIME, "gorge touchée")
	p.input.fire = false
	at.check(ok and n.scream_phase == Nurse.Phase.CHOKE, "balle dans la gorge : cri étranglé")
	await seconds(0.5)
	await at.screenshot("choke")
	await seconds(1.0)
	at.check(p.dazes == dazes and n.screams == 1, "cri avorté : personne n'est étourdi")
	game.combat.debug_invulnerable = true
	game.zombies.despawn(n.id)
	await seconds(0.4)

	# ------------------------------------------------ vague forcée (manche 20)
	var loot := game.loot
	loot.debug_sample_chance = 1.0
	loot.debug_part_chance = 0.0
	nr.debug_force_next(20)
	game.rounds.paused = false
	p.teleport_to(cell(12, 7), -PI * 0.5)
	game.rounds.debug_jump_to(20)
	ok = await until(func(): return nr.active and nr.cl_active and game.hud.round_counter().special, 2.0, "annonce de la vague")
	at.check(ok and game.rounds.special_type == WaveRules.INFIRMIERE and game.rounds.wave == WaveRules.SPECIAL, "manche 20 : vague de l'Infirmière")
	at.check(nr.total == 1 and game.rounds.to_spawn == NurseRules.escorts(1), "solo : 1 Infirmière, %d zombies d'escorte" % game.rounds.to_spawn)
	at.check(game.hud._center_msg.text == NurseRound.banner_text(1), "bandeau « %s »" % game.hud._center_msg.text)
	await until(func(): return Audio._music_name == "special_wave_music", 3.0, "musique")
	at.check(Audio._music_name == "special_wave_music", "musique de vague spéciale")
	await seconds(0.6)
	await at.screenshot("announce")
	at.check(game.zombies.alive_count() == 0, "rien n'apparaît pendant l'annonce")
	ok = await until(func(): return first_nurse() != null, NurseRules.START_DELAY + 4.0, "Infirmière apparue")
	var boss := first_nurse()
	at.check(ok and boss.max_health == NurseRules.health(20, 1), "PV : %d (8 × %d)" % [boss.max_health if boss else 0, RoundRules.zombie_health(20)])
	boss.scream_cooldown = 999.0
	ok = await until(func(): return game.zombies.alive_count() >= 2, 10.0, "escorte")
	var killed := 0
	var t := 0.0
	while (game.rounds.to_spawn > 0 or game.zombies.alive_count() > 1) and t < 60.0:
		for z: Zombie in game.zombies.alive.duplicate():
			if not z is Nurse and z.state != Zombie.State.EMERGE:
				game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
				killed += 1
		await seconds(0.25)
		t += 0.25
	at.check(killed == NurseRules.escorts(1), "escorte tuée (%d)" % killed)
	await until(func(): return int(loot.my_samples.get("nurse_badge", 0)) == killed, 2.0, "échantillons reçus")
	at.check(int(loot.my_samples.get("nurse_vocal_cords", 0)) == killed and int(loot.my_samples.get("nurse_syringe", 0)) == killed
			and int(loot.my_samples.get("nurse_badge", 0)) == killed, "escorte : %s" % str(loot.my_samples))
	at.check(game.rounds.phase == RoundManager.Phase.ACTIVE, "la vague continue tant que l'Infirmière vit")
	# Mort de l'Infirmière, regardée par le joueur.
	boss.set_physics_process(false)
	boss.velocity = Vector3.ZERO
	boss.global_position = p.global_position + Vector3(4.5, 0.0, 0.5)
	boss.yaw = -PI * 0.5
	boss.rotation.y = boss.yaw
	H.aim_at(p, p.global_position + Vector3(-3.0, 1.0, 0.0))
	await seconds(0.3)
	var xp0 := int(game.xp.my_ledger.kills.get(XpRules.NURSE, 0))
	game.combat.damage_zombie(boss.id, 999999, 1, true, Vector3.RIGHT, Combat.HitKind.BULLET)
	await until(func(): return not loot.drops.is_empty(), 1.0, "arme posée")
	H.aim_at(p, boss.global_position + Vector3(0.0, 1.3, 0.0))
	await seconds(0.4)
	await at.screenshot("death_clutch")
	H.aim_at(p, boss.global_position + Vector3(0.0, 0.4, 0.0))
	await seconds(1.2)
	await at.screenshot("death")
	at.check(absf(boss.skel.rotation.x - NurseAnim.DEATH_PITCH) < 0.1, "mort : sur le dos (%.2f)" % boss.skel.rotation.x)
	ok = await until(func(): return int(game.xp.my_ledger.kills.get(XpRules.NURSE, 0)) == xp0 + 1, 2.0, "XP du mini-boss")
	at.check(ok, "élimination de l'Infirmière comptée (XP %d)" % XpRules.kill_xp(XpRules.NURSE, 20))
	at.check(int(loot.my_samples.get("nurse_vocal_cords", 0)) == killed + 1, "l'Infirmière donne aussi ses échantillons")
	ok = await until(func(): return game.rounds.phase == RoundManager.Phase.INTERMISSION, 3.0, "fin de vague")
	at.check(ok, "fin de la vague de l'Infirmière")
	ok = await until(func(): return not loot.drops.is_empty() and game.evac != null and game.evac.is_open, 3.0, "butin et évacuation")
	at.check(ok, "vague vaincue : arme de butin posée, porte d'évacuation ouverte")
	at.check(nr.next_round == 40 and nr.rank == 1, "prochaine vague de l'Infirmière : manche %d" % nr.next_round)
	await until(func(): return not nr.cl_active and not game.hud.round_counter().special, NurseRules.END_DELAY + 3.0, "fin de l'ambiance")
	at.check(not nr.cl_active and Audio._music_name != "special_wave_music", "fin de l'ambiance, musique de la carte")
	game.rounds.paused = true
	await seconds(0.3)
