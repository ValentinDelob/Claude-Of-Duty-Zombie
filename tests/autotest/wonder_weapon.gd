extends AutotestScenario
## TONNERRE-7 (arme merveille façon Thundergun) : l'onde de choc calculée par
## le serveur projette et tue tous les zombies du cône (manche 30), épargne
## ceux de derrière et ceux cachés par un mur, rapporte 50 points par kill,
## ne blesse pas le joueur ; 2 coups puis rechargement long ; version
## améliorée (4 coups, réserve 24) ; unicité pour la boîte mystère.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData


func equip(pap: bool) -> bool:
	pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance("thunder", pap)]
	pd.slot = 1
	game.combat.cancel_reload(1)
	game.session.sync_inventory(1)
	var ok: bool = await until(func(): return p.weapons.current().get("id", "") == "thunder" and p.weapons.current().get("pap", false) == pap, 2.0, "TONNERRE-7 en main")
	await seconds(WeaponController.SWITCH_TIME + 0.25)
	return ok


func spawn_still(pos: Vector3, health: int) -> Zombie:
	var zm := game.zombies
	var z := zm.get_zombie(zm.spawn(pos, 0, health))
	z.speed_mult = 0.0
	return z


func pull_trigger() -> void:
	var before: int = p.weapons.current().get("mag", 0)
	p.input.fire = true
	var t := 0.0
	while p.weapons.current().get("mag", 0) == before and t < 0.5:
		await tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	p.input.fire = false


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	await H.clear_zombies(self)
	pd = game.session.local_data()

	# Joueur à l'ouest de l'arène, face à l'est (+X) : 20 m de salle dégagée.
	var origin := MapData.cell_to_world(Vector2i(4, 7), 0.05)
	p.teleport_to(origin, -PI * 0.5)
	p.pitch = 0.0
	await seconds(0.3)
	at.check(await equip(false), "TONNERRE-7 équipé")
	at.check(MysteryBox.wonders_taken(game).has("thunder"), "boîte : TONNERRE-7 déjà dans la partie (plus proposé)")
	await at.screenshot("fps_thunder")

	# 1. Sept zombies de manche 30 dans le cône, un derrière le joueur.
	var hp := RoundRules.zombie_health(30)
	var front := []
	for off in [Vector3(2.5, 0, 0), Vector3(4.0, 0, -1.0), Vector3(5.5, 0, 1.2), Vector3(8.0, 0, 0.3),
			Vector3(10.5, 0, 0.9), Vector3(13.0, 0, 1.5), Vector3(16.5, 0, -0.4)]:
		front.append(spawn_still(origin + off, hp))
	var behind := spawn_still(origin + Vector3(-3.0, 0, 0), hp)
	await seconds(Zombie.EMERGE_TIME + 0.4)
	p.yaw = -PI * 0.5
	p.pitch = 0.0
	await seconds(0.1)
	await at.screenshot("before")
	var points_before := pd.points
	var health_before := pd.health
	var start_pos := []
	for z: Zombie in front:
		start_pos.append(z.global_position)
	await pull_trigger()
	await seconds(0.12)
	await at.screenshot("blast")
	var dead := 0
	for z: Zombie in front:
		if not z.is_alive():
			dead += 1
	at.check(dead == 7, "onde de choc : %d/7 zombies de manche 30 (%d PV) tués d'un coup" % [dead, hp])
	at.check(behind.is_alive() and behind.health == hp, "zombie derrière le joueur intact (%d PV)" % behind.health)
	var flung := 0
	for z: Zombie in front:
		if z.get_node_or_null("Fling") is ZombieFling:
			flung += 1
	at.check(flung == 7, "%d/7 zombies projetés (vol procédural)" % flung)
	await seconds(0.25)
	await at.screenshot("flight")
	await seconds(0.9)
	var moved := 0
	var landed := 0
	for i in front.size():
		var z: Zombie = front[i]
		if not is_instance_valid(z):
			continue
		var d := Vector2(z.global_position.x - start_pos[i].x, z.global_position.z - start_pos[i].z)
		if d.length() > 1.5 and d.x > 0.0:
			moved += 1
		print("[wonder] zombie %d : déplacé de %s" % [i, d])
		var f := z.get_node_or_null("Fling") as ZombieFling
		if f and not f.flying and absf(z.global_position.y - start_pos[i].y) < 0.05:
			landed += 1
	at.check(moved == 7, "%d/7 corps projetés vers l'arrière (> 1,5 m)" % moved)
	at.check(landed == 7, "%d/7 corps retombés au sol" % landed)
	await at.screenshot("landed")
	at.check(pd.points - points_before == 7 * PointsRules.KILL, "points : +%d (50 par kill, comme BO1)" % (pd.points - points_before))
	at.check(pd.health == health_before, "aucun dégât au joueur (%d PV)" % pd.health)
	at.check(pd.current_weapon().mag == 1, "1 coup restant dans le chargeur")
	await H.clear_zombies(self)

	# 2. Un zombie caché derrière un pilier n'est pas touché ; le 2e coup vide
	# le chargeur, puis rechargement automatique (long).
	var pillar := MapData.cell_to_world(Vector2i(15, 4), 0.0) + Vector3(0.5, 0, 0.5)  # pilier 2x2
	var eye := MapData.cell_to_world(Vector2i(10, 4), 0.05)
	p.teleport_to(eye, -PI * 0.5)
	p.pitch = 0.0
	var hidden := spawn_still(pillar + Vector3(2.2, 0, 0), hp)
	var open := spawn_still(eye + Vector3(3.0, 0, 1.4), hp)
	await seconds(Zombie.EMERGE_TIME + 0.4)
	p.yaw = -PI * 0.5
	await pull_trigger()
	await seconds(0.15)
	at.check(not open.is_alive(), "zombie à découvert tué")
	at.check(hidden.is_alive(), "zombie caché derrière le pilier épargné (pas à travers les murs)")
	var rt := game.combat.reload_time(1, pd.current_weapon())
	at.check(rt >= 3.0, "rechargement long : %.1f s" % rt)
	await until(func(): return pd.current_weapon().mag == 2, rt + 2.0, "rechargement automatique")
	at.check(pd.current_weapon().mag == 2 and pd.current_weapon().reserve == 10, "rechargé : %d / %d" % [pd.current_weapon().mag, pd.current_weapon().reserve])
	await H.clear_zombies(self)

	# 3. Version améliorée (OURAGAN-77) : 4 coups, réserve 24, même onde.
	p.teleport_to(origin, -PI * 0.5)
	p.pitch = 0.0
	at.check(await equip(true), "OURAGAN-77 équipé")
	at.check(pd.current_weapon().mag == 4 and pd.current_weapon().reserve == 24, "amélioré : %d / %d" % [pd.current_weapon().mag, pd.current_weapon().reserve])
	await at.screenshot("fps_thunder_pap")
	var zs := []
	for k in 3:
		zs.append(spawn_still(origin + Vector3(4.0 + k * 3.0, 0, (k - 1) * 1.0), hp))
	# Un chien de l'enfer aussi.
	var dog := game.zombies.get_zombie(game.zombies.spawn(origin + Vector3(6.0, 0, -2.0), 0, 2000, ZombieManager.KIND_DOG))
	dog.speed_mult = 0.0
	await seconds(2.6)
	p.yaw = -PI * 0.5
	p.pitch = 0.0
	await pull_trigger()
	await seconds(0.12)
	await at.screenshot("blast_pap")
	var dead_pap := 0
	for z: Zombie in zs:
		if not z.is_alive():
			dead_pap += 1
	at.check(dead_pap == 3 and pd.current_weapon().mag == 3, "OURAGAN-77 : %d/3 tués, 3 coups restants" % dead_pap)
	at.check(not dog.is_alive(), "chien de l'enfer projeté et tué")
	await seconds(0.8)
	await H.clear_zombies(self)
