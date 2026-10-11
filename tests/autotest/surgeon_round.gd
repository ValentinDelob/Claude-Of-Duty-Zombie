extends AutotestScenario
## Vague de boss « Le Chirurgien » dans le vrai jeu (GAME_CONCEPT.md §4.4) :
## modèle cubique, point faible (cœur : multiplicateur de tête), combo au
## scalpel télégraphié (préparation puis entailles) qui blesse le joueur
## devant lui (codex : rencontre), scalpels lancés en éventail (projectiles
## qui touchent le joueur), opération à 75 % (patients relevés), changement
## de phase à 50 % (rugissement, onde de choc qui projette, enragé), mort sur
## le dos ; vague forcée (manche 15) : bandeau, jauge de vie, musique, escorte,
## PV de la formule, échantillons (scalpel, cœur mutant) sur chaque zombie de
## la vague et à coup sûr sur le boss, XP du boss au tueur, 2 armes de butin,
## porte d'évacuation, prochaine vague du Chirurgien à la 30.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData


func cell(x: int, z: int) -> Vector3:
	return MapData.cell_to_world(Vector2i(x, z), 0.0)


func first_surgeon() -> Surgeon:
	for z: Zombie in game.zombies.alive:
		if z is Surgeon:
			return z
	return null


func heal() -> void:
	pd.health = pd.max_health
	game.session.sync_stats(1)


func run() -> void:
	timeout_sec = 300
	p = await H.start_solo_game(self, "test_arena")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	pd = game.session.local_data()
	await H.clear_zombies(self)
	var sr := game.rounds.surgeon
	at.check(sr != null and sr.get_path() == ^"/root/Game/Rounds/Surgeon", "gestionnaire du Chirurgien présent")
	at.check(not sr.enabled, "Chirurgien coupé par défaut en autotest")
	at.check(sr.next_round == 15, "boss prévu à la manche 15 (%d)" % sr.next_round)
	at.check(game.rounds.dogs.next_dog_round == 5 and game.rounds.brancard.next_round == 10,
		"rotation avec boss : meute 5, Brancardier 10 (%d, %d)" % [game.rounds.dogs.next_dog_round, game.rounds.brancard.next_round])

	# ------------------------------------------------ modèle, point faible
	p.teleport_to(cell(8, 3), -PI * 0.5)
	await seconds(0.3)
	var s := sr.debug_spawn(cell(12, 3), 200000)
	at.check(s != null and s.mesh.mesh == SurgeonModel.model().mesh, "type d'entité Chirurgien, modèle cubique")
	if s == null:
		return
	s.set_physics_process(false)
	s.yaw = -PI * 0.5 + 0.4
	s.rotation.y = s.yaw
	H.aim_at(p, s.global_position + Vector3.UP * 1.5)
	await seconds(1.0)
	await at.screenshot("model")
	pd.weapons = [WeaponDB.new_instance("commando")]
	pd.slot = 0
	game.session.sync_inventory(1)
	await seconds(0.3)
	var hits := [0, 0]  # [plus forte touche au cœur, au corps]
	var on_dmg := func(_pid, zid, dmg, _killed, headshot, _kind):
		if zid == s.id:
			hits[0 if headshot else 1] = maxi(hits[0 if headshot else 1], dmg)
	game.combat.zombie_damaged.connect(on_dmg)
	p.input.fire = true
	await until(func():
		H.aim_at(p, s.global_position + Vector3.UP * 0.9)
		return hits[1] > 0, 3.0, "touche au corps")
	await until(func():
		H.aim_at(p, s.head_position())
		return hits[0] > 0, 3.0, "touche au cœur")
	p.input.fire = false
	game.combat.zombie_damaged.disconnect(on_dmg)
	at.check(hits[1] > 0, "tirs au corps : %d dégâts" % hits[1])
	at.check(hits[0] >= roundi(WeaponDB.stats("commando").damage * 2.0) and hits[0] > hits[1],
		"cœur (point faible) : %d dégâts par touche (corps : %d)" % [hits[0], hits[1]])
	game.zombies.despawn(s.id)
	await seconds(0.3)

	# ------------------------------------------------ combo au scalpel
	game.combat.debug_invulnerable = false
	heal()
	p.teleport_to(cell(10, 3), -PI * 0.5)
	s = sr.debug_spawn(cell(10, 3) + Vector3(1.8, 0, 0), 200000)
	s.target = p
	s.throw_cooldown = 999.0
	var acts := {}
	s.action_started.connect(func(a): acts[a] = true)
	var hp := pd.health
	var ok: bool = await until(func():
		H.aim_at(p, s.global_position + Vector3.UP * 1.5)
		return acts.has(Surgeon.Action.SLASH_WINDUP), 6.0, "préparation de l'entaille")
	at.check(ok, "préparation de l'entaille (télégraphiée)")
	await seconds(0.25)
	at.check(s.action == Surgeon.Action.SLASH_WINDUP and pd.health == hp, "rien avant la fin de la préparation")
	await at.screenshot("slash_windup")
	ok = await until(func(): return s.slash_hits > 0, 3.0, "entaille")
	at.check(ok and pd.health <= hp - SurgeonRules.SLASH_DAMAGE, "entaillé : %d -> %d PV" % [hp, pd.health])
	at.check(Array(XpRules.met_types(game.xp.my_ledger)).has(XpRules.SURGEON), "entaillé : Chirurgien rencontré (codex)")
	await seconds(0.2)
	await at.screenshot("slash")
	game.zombies.despawn(s.id)
	await seconds(0.4)

	# ------------------------------------------------ scalpels lancés
	heal()
	p.teleport_to(cell(18, 3), PI * 0.5)
	s = sr.debug_spawn(cell(8, 3), 200000)
	s.target = p
	s.throw_cooldown = 0.0
	s.slash_cooldown = 999.0
	var thrown0 := sr.scalpels.thrown
	var phits0 := sr.scalpels.player_hits
	hp = pd.health
	ok = await until(func(): return s.action == Surgeon.Action.THROW_WINDUP, 6.0, "préparation du lancer")
	at.check(ok, "préparation du lancer (bras armé)")
	ok = await until(func(): return sr.scalpels.thrown > thrown0, 3.0, "scalpels lancés")
	at.check(ok and sr.scalpels.thrown - thrown0 == SurgeonRules.THROW_COUNT, "éventail de %d scalpels" % (sr.scalpels.thrown - thrown0))
	at.check(not sr.scalpels.flying.is_empty(), "scalpels en vol (visibles)")
	await seconds(0.15)
	H.aim_at(p, s.global_position + Vector3.UP * 1.6)
	await at.screenshot("throw")
	ok = await until(func(): return sr.scalpels.player_hits > phits0, 3.0, "scalpel dans le joueur")
	at.check(ok and pd.health <= hp - SurgeonRules.THROW_DAMAGE, "touché par un scalpel : %d -> %d PV" % [hp, pd.health])
	await until(func(): return sr.scalpels.flying.is_empty(), 4.0, "scalpels retombés")
	at.check(sr.scalpels.flying.is_empty(), "plus aucun scalpel en vol")
	game.zombies.despawn(s.id)
	await seconds(0.4)

	# ------------------------------------------------ opération, phase 2
	game.combat.debug_invulnerable = true
	heal()
	p.teleport_to(cell(12, 7), -PI * 0.5)
	s = sr.debug_spawn(cell(15, 7), 100000)
	s.target = p
	s.throw_cooldown = 999.0
	s.slash_cooldown = 999.0
	var alive0 := game.zombies.alive_count()
	s.health = 74000
	ok = await until(func(): return s.action == Surgeon.Action.SURGERY, 3.0, "opération")
	at.check(ok, "opération à 75 %")
	H.aim_at(p, s.global_position + Vector3.UP * 1.0)
	await seconds(1.4)
	await at.screenshot("surgery")
	at.check(game.zombies.alive_count() - alive0 == SurgeonRules.summons(1), "patients relevés : %d" % (game.zombies.alive_count() - alive0))
	await until(func(): return s.action == Surgeon.Action.NONE, 4.0, "fin de l'opération")
	for z: Zombie in game.zombies.alive.duplicate():
		if not z is Surgeon:
			game.zombies.despawn(z.id)
	game.combat.debug_invulnerable = false
	heal()
	p.teleport_to(s.global_position + Vector3(-2.5, 0, 0), -PI * 0.5)
	var knocks := p.knockbacks
	hp = pd.health
	s.health = 49000
	ok = await until(func(): return s.action == Surgeon.Action.ROAR, 3.0, "changement de phase")
	at.check(ok and s.rage, "phase 2 à 50 % : enragé")
	ok = await until(func(): return p.knockbacks > knocks, 2.0, "onde de choc")
	at.check(ok and pd.health <= hp - SurgeonRules.SHOCK_DAMAGE, "onde de choc : projeté, %d -> %d PV" % [hp, pd.health])
	H.aim_at(p, s.global_position + Vector3.UP * 1.8)
	await seconds(0.3)
	await at.screenshot("roar")
	game.combat.debug_invulnerable = true
	game.zombies.despawn(s.id)
	await seconds(0.4)

	# ------------------------------------------------ vague forcée (manche 15)
	var loot := game.loot
	loot.debug_sample_chance = 1.0
	loot.debug_part_chance = 0.0
	sr.debug_force_next(15)
	game.rounds.paused = false
	p.teleport_to(cell(12, 7), -PI * 0.5)
	game.rounds.debug_jump_to(15)
	ok = await until(func(): return sr.active and sr.cl_active and game.hud.round_counter().special, 2.0, "annonce de la vague")
	at.check(ok and game.rounds.wave == WaveRules.BOSS and game.rounds.boss_type == WaveRules.CHIRURGIEN, "manche 15 : vague du Chirurgien")
	at.check(sr.total == 1 and game.rounds.to_spawn == SurgeonRules.escorts(1), "un boss, %d zombies d'escorte" % game.rounds.to_spawn)
	at.check(game.hud._center_msg.text == SurgeonRound.banner_text(), "bandeau « %s »" % game.hud._center_msg.text)
	at.check(sr.bar != null and sr.bar.is_inside_tree(), "jauge de vie du boss")
	await until(func(): return Audio._music_name == "special_wave_music", 3.0, "musique")
	at.check(Audio._music_name == "special_wave_music", "musique de vague")
	await seconds(0.6)
	await at.screenshot("announce")
	at.check(game.zombies.alive_count() == 0, "rien n'apparaît pendant l'annonce")
	ok = await until(func(): return first_surgeon() != null, SurgeonRules.START_DELAY + 4.0, "Chirurgien apparu")
	var boss := first_surgeon()
	at.check(ok and boss.max_health == SurgeonRules.health(15, 1, 1), "PV : %d (30 × %d)" % [boss.max_health if boss else 0, RoundRules.zombie_health(15)])
	if boss == null:
		return
	boss.set_physics_process(false)
	await seconds(0.6)
	at.check(sr.bar and sr.bar.fraction > 0.99, "jauge pleine")
	game.combat.damage_zombie(boss.id, int(boss.max_health * 0.2), 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
	await until(func(): return sr.bar and sr.bar.fraction < 0.85, 2.0, "jauge")
	at.check(sr.bar and absf(sr.bar.fraction - 0.8) < 0.02, "jauge à %.2f" % (sr.bar.fraction if sr.bar else -1.0))
	var killed := 0
	var t := 0.0
	while (game.rounds.to_spawn > 0 or game.zombies.alive_count() > 1) and t < 60.0:
		for z: Zombie in game.zombies.alive.duplicate():
			if not z is Surgeon and z.state != Zombie.State.EMERGE:
				game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
				killed += 1
		await seconds(0.25)
		t += 0.25
	at.check(killed == SurgeonRules.escorts(1), "escorte tuée (%d)" % killed)
	await until(func(): return int(loot.my_samples.get("surgeon_scalpel", 0)) == killed, 2.0, "échantillons reçus")
	at.check(int(loot.my_samples.get("surgeon_scalpel", 0)) == killed and int(loot.my_samples.get("surgeon_heart", 0)) == killed,
		"escorte : scalpels %d, cœurs %d" % [int(loot.my_samples.get("surgeon_scalpel", 0)), int(loot.my_samples.get("surgeon_heart", 0))])
	at.check(game.rounds.phase == RoundManager.Phase.ACTIVE, "la vague continue tant que le boss vit")
	# Mort, regardée par le joueur.
	boss.velocity = Vector3.ZERO
	boss.global_position = p.global_position + Vector3(5.0, 0.0, 0.5)
	boss.yaw = -PI * 0.5
	boss.rotation.y = boss.yaw
	H.aim_at(p, p.global_position + Vector3(-3.0, 1.0, 0.0))
	await seconds(0.3)
	var xp0 := int(game.xp.my_ledger.kills.get(XpRules.SURGEON, 0))
	game.combat.damage_zombie(boss.id, 99999999, 1, true, Vector3.RIGHT, Combat.HitKind.BULLET)
	await until(func(): return loot.drops.size() >= 2, 1.5, "armes posées")
	H.aim_at(p, boss.global_position + Vector3(0.0, 1.4, 0.0))
	await seconds(0.4)
	await at.screenshot("death_stagger")
	H.aim_at(p, boss.global_position + Vector3(-0.8, 0.4, 0.0))
	await seconds(1.4)
	await at.screenshot("death")
	at.check(absf(boss.skel.rotation.x - SurgeonAnim.DEATH_PITCH) < 0.1, "mort : sur le dos (%.2f)" % boss.skel.rotation.x)
	ok = await until(func(): return int(game.xp.my_ledger.kills.get(XpRules.SURGEON, 0)) == xp0 + 1, 2.0, "XP du boss")
	at.check(ok, "élimination du Chirurgien comptée (XP %d)" % XpRules.kill_xp(XpRules.SURGEON, 15))
	at.check(int(loot.my_samples.get("surgeon_heart", 0)) == killed + 1, "le boss donne ses échantillons")
	ok = await until(func(): return game.rounds.phase == RoundManager.Phase.INTERMISSION, 3.0, "fin de vague")
	at.check(ok, "fin de la vague du Chirurgien")
	ok = await until(func(): return loot.drops.size() == 2 and game.evac != null and game.evac.is_open, 3.0, "butin et évacuation")
	at.check(ok, "vague de boss vaincue : 2 armes de butin, porte d'évacuation ouverte")
	at.check(int(game.xp.my_ledger.waves.get(WaveRules.BOSS, 0)) == 1, "XP de la vague de boss")
	at.check(sr.next_round == 30 and sr.rank == 1, "prochaine vague du Chirurgien : manche %d" % sr.next_round)
	await until(func(): return not sr.cl_active and sr.bar == null, SurgeonRules.END_DELAY + 3.0, "fin de l'ambiance")
	at.check(not sr.cl_active and sr.bar == null and Audio._music_name != "special_wave_music", "fin de l'ambiance, jauge retirée")
	game.rounds.paused = true
	await seconds(0.3)
