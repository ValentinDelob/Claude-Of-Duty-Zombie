extends AutotestScenario
## [MP] Client : voit le zombie devenir un RAMPANT (jambes au sol, hitboxes
## couchées), se traîner vers lui, le tue d'un tir à la tête sur sa
## marionnette ; voit un corps déchiqueté par une explosion.

const PORT := 17893

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	p.teleport_to(MapData.cell_to_world(Vector2i(4, 7), 0.05), -PI * 0.5)
	var gibs: GibPool = game.fx_root.gibs
	var ok: bool = await until(func(): return game.zombies.alive.size() >= 1, 40.0, "zombie reçu")
	if not ok:
		return
	var z: Zombie = game.zombies.alive[0]
	MpHelpers.signal_peer("zombie_1")
	ok = await until(func(): return z.is_crawler(), 15.0, "rampant reçu")
	at.check(ok and (z.gibs & ZombieGibs.LEGS) != 0 and not z.server_side, "marionnette : rampant (masque %d)" % z.gibs)
	at.check(gibs.active_count() >= 2, "jambes tombées chez le client (%d morceaux)" % gibs.active_count())
	var hips_y := func() -> float:
		return (z.skel.global_transform * z.skel.get_bone_global_pose(z.bones.hips)).origin.y
	# Le corps bascule au sol (animation de chute).
	await until(func(): return hips_y.call() < 0.45 and z.hit_body.global_position.y < 0.45, 3.0, "corps au sol")
	at.check(hips_y.call() < 0.45 and z.hit_body.global_position.y < 0.45, "corps et hitbox au sol (bassin %.2f)" % hips_y.call())
	# Il se traîne vers le client (position interpolée : temps réel).
	var x0 := z.global_position.x
	# Attente bornée plutôt qu'une fenêtre fixe de 2 s : sous charge (check
	# parallèle), les instantanés réseau arrivent en retard.
	var crawled: bool = await until(func(): return z.global_position.x < x0 - 0.5, 6.0, "rampant qui se traîne")
	at.check(crawled, "le rampant se traîne vers le client (%.2f m)" % (x0 - z.global_position.x))
	H.aim_at(p, z.head_position())
	await seconds(0.1)
	await at.screenshot("crawler")
	# Tir à la tête sur la marionnette couchée, en visée (en hanche, la
	# dispersion de BO1 rend une tête couchée à cette distance aléatoire).
	p.input.aim = true
	await seconds(0.5)  # mise en joue
	for i in 4:
		if not z.is_alive():
			break
		H.aim_at(p, z.head_position())
		await H.shoot(self, p, 0.4)
	ok = await until(func(): return not z.is_alive(), 3.0, "mort du rampant reçue")
	at.check(ok and z._headless, "rampant tué d'un tir à la tête (tête éclatée)")
	await seconds(0.3)
	await at.screenshot("crawler_dead")

	ok = await until(func(): return game.zombies.alive.size() >= 1, 20.0, "second zombie")
	if not ok:
		return
	var z2: Zombie = game.zombies.alive[0]
	MpHelpers.signal_peer("zombie_2")
	ok = await until(func(): return not z2.is_alive(), 10.0, "explosion mortelle")
	await seconds(0.1)
	await at.screenshot("death_gibs")
	at.check(ok and z2.gibs != 0, "corps déchiqueté chez le client (masque %d)" % z2.gibs)
	await MpHelpers.finish(self)
