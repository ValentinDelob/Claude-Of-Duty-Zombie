extends AutotestScenario
## Vague spéciale « Brancardier » dans le vrai jeu (GAME_CONCEPT.md §4.4) :
## modèle cubique, charge télégraphiée (préparation : il gratte du pied et
## rugit) qui percute et projette le joueur (dégâts, poussée), choc contre le
## mur (étourdi), mort à genoux puis face contre terre ; vague forcée :
## bandeau « UN BRANCARDIER APPROCHE », compteur qui clignote, musique,
## 1 Brancardier (PV de la formule) et son escorte, échantillons (sangle,
## bracelet) sur chaque zombie de la vague, XP du mini-boss au tueur, arme de
## butin et porte d'évacuation à la fin, rotation des vagues (meute à 15,
## Brancardier à 20).

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData


## Point du monde au centre de la case (colonne x, rangée z) de l'arène.
func cell(x: int, z: int) -> Vector3:
	return MapData.cell_to_world(Vector2i(x, z), 0.0)


func first_brancardier() -> Brancardier:
	for z: Zombie in game.zombies.alive:
		if z is Brancardier:
			return z
	return null


func run() -> void:
	timeout_sec = 240
	p = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	pd = game.session.local_data()
	await H.clear_zombies(self)
	var br := game.rounds.brancard
	at.check(br != null and br.get_path() == ^"/root/Game/Rounds/Brancard", "gestionnaire du Brancardier présent")
	at.check(not br.enabled, "vagues du Brancardier coupées par défaut en autotest")
	at.check(br.next_round == 10 and game.rounds.dogs.next_dog_round == 5, "rotation : meute à la 5 (%d), Brancardier à la 10 (%d)" % [game.rounds.dogs.next_dog_round, br.next_round])

	# ------------------------------------------------ modèle
	p.teleport_to(cell(8, 3), -PI * 0.5)  # face à l'est (+X)
	await seconds(0.3)
	var b := br.debug_spawn(cell(12, 3), 5000)
	at.check(b != null and b.mesh.mesh == BrancardierModel.model().mesh, "type d'entité Brancardier, modèle cubique")
	if b == null:
		return
	b.set_physics_process(false)
	b.yaw = -PI * 0.5 + 0.5
	b.rotation.y = b.yaw
	H.aim_at(p, b.global_position + Vector3.UP * 1.3)
	await seconds(1.0)
	await at.screenshot("model")
	# Vrais tirs (touches validées par le serveur) : corps puis tête.
	pd.weapons = [WeaponDB.new_instance("commando")]
	pd.slot = 0
	game.session.sync_inventory(1)
	await seconds(0.3)
	var hp_b := b.health
	H.aim_at(p, b.global_position + Vector3.UP * 1.2)
	p.input.fire = true
	await seconds(0.6)
	p.input.fire = false
	var body_dmg := hp_b - b.health
	at.check(body_dmg > 0, "tirs au corps : %d dégâts" % body_dmg)
	# Tête (point faible) : multiplicateur de tête de l'arme, coup par coup.
	var head_hits := [0, 0]  # [dégâts d'une touche à la tête, d'une au corps]
	var on_dmg := func(_pid, zid, dmg, _killed, headshot, _kind):
		if zid == b.id:
			head_hits[0 if headshot else 1] = maxi(head_hits[0 if headshot else 1], dmg)
	game.combat.zombie_damaged.connect(on_dmg)
	p.input.fire = true
	# Visée recalée à chaque image (le recul fait monter l'arme).
	await until(func():
		H.aim_at(p, b.head_position())
		return head_hits[0] > 0, 3.0, "touche à la tête")
	p.input.fire = false
	game.combat.zombie_damaged.disconnect(on_dmg)
	at.check(head_hits[0] > 0 and head_hits[0] >= roundi(WeaponDB.stats("commando").damage * 2.0),
			"tête (point faible) : %d dégâts par touche (corps : %d au total)" % [head_hits[0], body_dmg])
	game.zombies.despawn(b.id)
	await seconds(0.3)

	# ------------------------------------------------ charge, projection, choc
	game.combat.debug_invulnerable = false
	pd.health = pd.max_health
	game.session.sync_stats(1)
	p.teleport_to(cell(18, 3), PI * 0.5)  # face à l'ouest (vers lui)
	b = br.debug_spawn(cell(10, 3), 50000)
	b.yaw = PI * 0.5
	b.rotation.y = b.yaw
	b.charge_cooldown = 0.0
	var started := [false]
	var hit_pid := [0]
	var stunned := [false]
	b.charge_started.connect(func(): started[0] = true)
	b.charge_hit_player.connect(func(pid): hit_pid[0] = pid)
	b.wall_stunned.connect(func(): stunned[0] = true)
	var hp := pd.health
	var knocks := p.knockbacks
	var ok: bool = await until(func():
		H.aim_at(p, b.global_position + Vector3.UP * 1.3)
		return b.charge_phase == Brancardier.Phase.WINDUP, 6.0, "préparation de la charge")
	at.check(ok, "préparation de la charge (télégraphiée)")
	await seconds(0.55)
	at.check(b.charge_phase == Brancardier.Phase.WINDUP and b.anim_speed < 0.5, "immobile pendant la préparation")
	await at.screenshot("windup")
	ok = await until(func():
		H.aim_at(p, b.global_position + Vector3.UP * 1.3)
		return started[0], 2.0, "charge")
	at.check(ok, "charge lancée après %.1f s de préparation" % BrancardRules.WINDUP_TIME)
	await seconds(0.25)
	await at.screenshot("charge")
	ok = await until(func(): return hit_pid[0] == 1, 3.0, "joueur percuté")
	at.check(ok and pd.health == hp - BrancardRules.CHARGE_DAMAGE, "percuté : %d -> %d PV" % [hp, pd.health])
	var x0 := p.global_position.x
	await seconds(0.3)
	at.check(Array(XpRules.met_types(game.xp.my_ledger)).has(XpRules.BRANCARDIER), "percuté : Brancardier rencontré (codex)")
	at.check(p.knockbacks == knocks + 1, "joueur projeté (%d)" % (p.knockbacks - knocks))
	at.check(absf(p.global_position.x - x0) > 0.8 or p.global_position.distance_to(cell(18, 3)) > 1.5, "poussé de %.1f m" % p.global_position.distance_to(cell(18, 3)))
	ok = await until(func(): return stunned[0], 3.0, "choc contre le mur")
	at.check(ok and b.charge_phase == Brancardier.Phase.STUN and b.wall_hits == 1, "mur heurté : étourdi")
	at.check(b.global_position.x > 21.0, "il a continué sa charge jusqu'au mur est (x = %.1f)" % b.global_position.x)
	# Vu de trois quarts : face au mur, sonné, étoiles au-dessus de la tête.
	p.teleport_to(b.global_position + Vector3(-3.2, 0.0, 1.6), -PI * 0.5)
	H.aim_at(p, b.global_position + Vector3.UP * 1.4)
	await seconds(0.6)
	H.aim_at(p, b.global_position + Vector3.UP * 1.4)
	await at.screenshot("stun")
	var pos0 := b.global_position
	await seconds(1.0)
	at.check(b.charge_phase == Brancardier.Phase.STUN and b.global_position.distance_to(pos0) < 0.3, "étourdi : immobile")
	ok = await until(func(): return b.charge_phase == Brancardier.Phase.NONE, BrancardRules.STUN_TIME + 1.0, "fin de l'étourdissement")
	at.check(ok, "reprend la poursuite après %.0f s" % BrancardRules.STUN_TIME)
	game.combat.debug_invulnerable = true
	game.zombies.despawn(b.id)
	await seconds(0.4)

	# ------------------------------------------------ vague forcée (manche 10)
	var loot := game.loot
	loot.debug_sample_chance = 1.0
	loot.debug_part_chance = 0.0
	br.debug_force_next(10)
	game.rounds.paused = false
	p.teleport_to(cell(12, 7), -PI * 0.5)
	game.rounds.debug_jump_to(10)
	ok = await until(func(): return br.active and br.cl_active and game.hud.round_counter().special, 2.0, "annonce de la vague")
	at.check(ok and game.rounds.special_type == WaveRules.BRANCARDIER and game.rounds.wave == WaveRules.SPECIAL, "manche 10 : vague du Brancardier")
	at.check(br.total == 1 and game.rounds.to_spawn == BrancardRules.escorts(1), "solo : 1 Brancardier, %d zombies d'escorte" % game.rounds.to_spawn)
	at.check(game.hud._center_msg.text == BrancardRound.banner_text(1), "bandeau « %s »" % game.hud._center_msg.text)
	await until(func(): return Audio._music_name == "special_wave_music", 3.0, "musique")
	at.check(Audio._music_name == "special_wave_music", "musique de vague spéciale")
	await seconds(0.6)
	await at.screenshot("announce")
	at.check(game.zombies.alive_count() == 0, "rien n'apparaît pendant l'annonce")
	ok = await until(func(): return first_brancardier() != null, BrancardRules.START_DELAY + 4.0, "Brancardier apparu")
	var boss := first_brancardier()
	at.check(ok and boss.max_health == BrancardRules.health(10, 1), "PV : %d (10 × %d)" % [boss.max_health if boss else 0, RoundRules.zombie_health(10)])
	# Escorte : zombies ordinaires de la manche.
	ok = await until(func(): return game.zombies.alive_count() >= 2, 10.0, "escorte")
	var escort: Zombie = null
	for z: Zombie in game.zombies.alive:
		if not z is Brancardier:
			escort = z
	at.check(escort != null and escort.max_health == RoundRules.zombie_health(10), "escorte : zombie ordinaire de la manche")
	# Tue l'escorte (échantillons sur chaque zombie de la vague).
	var killed := 0
	var t := 0.0
	while (game.rounds.to_spawn > 0 or game.zombies.alive_count() > 1) and t < 60.0:
		for z: Zombie in game.zombies.alive.duplicate():
			if not z is Brancardier and z.state != Zombie.State.EMERGE:
				game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
				killed += 1
		await seconds(0.25)
		t += 0.25
	at.check(killed == BrancardRules.escorts(1), "escorte tuée (%d)" % killed)
	await until(func(): return int(loot.my_samples.get("brancard_strap", 0)) == killed, 2.0, "échantillons reçus")
	at.check(int(loot.my_samples.get("brancard_strap", 0)) == killed and int(loot.my_samples.get("brancard_bracelet", 0)) == killed,
			"escorte : sangles %d, bracelets %d" % [int(loot.my_samples.get("brancard_strap", 0)), int(loot.my_samples.get("brancard_bracelet", 0))])
	at.check(game.rounds.phase == RoundManager.Phase.ACTIVE, "la vague continue tant que le Brancardier vit")
	# Mort du Brancardier, regardé par le joueur.
	boss.set_physics_process(false)
	boss.velocity = Vector3.ZERO
	boss.global_position = p.global_position + Vector3(4.5, 0.0, 0.5)
	boss.yaw = PI
	boss.rotation.y = boss.yaw
	# Le joueur regarde ailleurs au coup fatal : l'arme de butin est posée
	# devant lui, hors du cadre de la capture de la mort.
	H.aim_at(p, p.global_position + Vector3(-3.0, 1.0, 0.0))
	await seconds(0.3)
	var xp0 := int(game.xp.my_ledger.kills.get(XpRules.BRANCARDIER, 0)) if game.xp else 0
	game.combat.damage_zombie(boss.id, 999999, 1, true, Vector3.RIGHT, Combat.HitKind.BULLET)
	await until(func(): return not loot.drops.is_empty(), 1.0, "arme posée")
	H.aim_at(p, boss.global_position + Vector3(0.0, 1.6, 0.0))
	await seconds(0.3)
	await at.screenshot("death_kneel")
	H.aim_at(p, boss.global_position + Vector3(0.0, 1.3, 0.0))
	await seconds(1.3)
	await at.screenshot("death")
	at.check(absf(boss.skel.rotation.x - BrancardierAnim.DEATH_PITCH) < 0.1, "mort : face contre terre (%.2f)" % boss.skel.rotation.x)
	ok = await until(func(): return int(game.xp.my_ledger.kills.get(XpRules.BRANCARDIER, 0)) == xp0 + 1, 2.0, "XP du mini-boss")
	at.check(ok, "élimination du Brancardier comptée (XP %d)" % XpRules.kill_xp(XpRules.BRANCARDIER, 10))
	at.check(int(loot.my_samples.get("brancard_strap", 0)) == killed + 1, "le Brancardier donne aussi ses échantillons")
	ok = await until(func(): return game.rounds.phase == RoundManager.Phase.INTERMISSION, 3.0, "fin de vague")
	at.check(ok, "fin de la vague du Brancardier")
	ok = await until(func(): return not loot.drops.is_empty() and game.evac != null and game.evac.is_open, 3.0, "butin et évacuation")
	at.check(ok, "vague vaincue : arme de butin posée, porte d'évacuation ouverte")
	at.check(br.next_round == 25 and br.rank == 1, "prochaine vague du Brancardier : manche %d (boss à la 15, meute à la 20)" % br.next_round)
	at.check(game.rounds.dogs.next_dog_round == 5, "chiens : non forcés, toujours prévus en 5")
	await until(func(): return not br.cl_active and not game.hud.round_counter().special, BrancardRules.END_DELAY + 3.0, "fin de l'ambiance")
	at.check(not br.cl_active and Audio._music_name != "special_wave_music", "fin de l'ambiance, musique de la carte")
	game.rounds.paused = true
	await seconds(0.3)
