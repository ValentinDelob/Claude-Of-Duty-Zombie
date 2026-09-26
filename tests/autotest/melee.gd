extends AutotestScenario
## Couteau (BO1) : fente vers un zombie visé à 2,5 m, 150 dégâts, mort au
## couteau = 130 points, pas de fente hors du cône de visée, animation du bras
## gauche, achat mural du COUTEAU DE CHASSE (3000, récupération ~2 s) puis
## zombie de manche 10 tué d'un seul coup.

var H := AutotestHelpers


## Place le joueur au quai, regard vers +X, et un zombie immobile devant lui.
func setup_duel(p: Player, dist: float, health: int, side := 0.0) -> Zombie:
	await H.clear_zombies(self)
	var start := MapData.cell_to_world(Vector2i(28, 8), 0.05)
	p.teleport_to(start, -PI * 0.5)
	var z := await H.dummy_zombie(self, start + Vector3(dist, -0.05, side), health)
	p.teleport_to(start, -PI * 0.5)
	H.aim_at(p, z.global_position + Vector3.UP * 1.2)
	if side != 0.0:
		# Regard droit devant (+X) : le zombie est hors du cône.
		H.aim_at(p, start + Vector3(5.0, 1.4, 0.0))
	await seconds(0.9)  # couteau prêt
	return z


func knife(p: Player) -> void:
	p.input.melee = true
	await until(func(): return not p.input.melee, 1.0, "coup de couteau pris en compte")


func run() -> void:
	timeout_sec = 120
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	for id in game.doors:
		game.doors[id].srv_open()
	var power: PowerSwitch = game.interact.get_obj("power")
	if power:
		power.srv_use(1)  # lumière pour les captures
	await seconds(2.5)
	at.check(pd.knife == "knife" and p.weapons.knife_id == "knife", "couteau de départ")

	# 1. Fente : zombie visé à 2,5 m, mort d'un coup (150 PV), 130 points.
	var z := await setup_duel(p, 2.5, 150)
	var pts := pd.points
	var x0 := p.global_position.x
	await knife(p)
	at.check(p.weapons.lunging and p.is_lunging(), "fente déclenchée")
	await seconds(0.07)
	await at.screenshot("melee_windup")
	await seconds(0.12)
	await at.screenshot("melee_slash")
	var moved := p.global_position.x - x0
	at.check(moved > 1.0 and moved < 2.2, "le joueur s'est projeté vers le zombie (%.2f m)" % moved)
	await seconds(0.2)
	at.check(not z.is_alive(), "zombie à 2,5 m tué par la fente")
	at.check(pd.points - pts == 130, "mort au couteau : +130 (%d)" % (pd.points - pts))
	await seconds(0.5)

	# 2. Dégâts du couteau : 150 sur un zombie plus résistant.
	z = await setup_duel(p, 2.5, 1000)
	await knife(p)
	await seconds(0.45)
	at.check(z.is_alive() and z.health == 850, "couteau : 150 dégâts (1000 -> %d)" % z.health)
	pts = pd.points
	await seconds(0.5)

	# 3. Pas de fente si le zombie n'est pas visé (35° à côté).
	z = await setup_duel(p, 2.1, 1000, -1.45)
	x0 = p.global_position.x
	await knife(p)
	await seconds(0.1)
	await at.screenshot("melee_miss")
	await seconds(0.3)
	at.check(not p.weapons.lunging and absf(p.global_position.x - x0) < 0.3, "pas de fente hors du cône (%.2f m)" % (p.global_position.x - x0))
	at.check(z.health == 1000, "zombie non visé intact (%d)" % z.health)
	await seconds(0.5)

	# 4. Coup truqué : origine avancée de 4,2 m (sans fente possible) vers un
	# zombie à 6 m, hors de portée de fente depuis la position serveur.
	z = await setup_duel(p, 6.0, 1000)
	game.combat.srv_melee.rpc_id(1, p.camera.global_position + Vector3(4.2, 0, 0), Vector3(1, 0, 0))
	await seconds(0.2)
	at.check(z.health == 1000, "coup de couteau à distance refusé (%d)" % z.health)
	await H.clear_zombies(self)

	# 5. Achat du COUTEAU DE CHASSE (quai) : 3000 points, récupération ~2 s.
	var wb: WallBuy = game.interact.get_obj("wallbuy_%")
	at.check(wb != null and wb.is_knife and wb.cost == 3000, "achat mural du couteau de chasse (%d)" % (wb.cost if wb else 0))
	if wb == null:
		return
	var front := wb.interact_point() + Vector3(0, -1.0, 0) + (wb.interact_point() - wb.global_position).normalized() * 1.2
	p.teleport_to(front)
	H.aim_at(p, wb.global_position)
	await seconds(0.5)
	await at.screenshot("bowie_chalk")
	pd.points = 2999
	game.session.sync_stats(1)
	p.teleport_to(wb.interact_point() + Vector3(0, -1.0, 0) + (wb.interact_point() - wb.global_position).normalized() * 0.6)
	H.aim_at(p, wb.global_position)
	await seconds(0.3)
	at.check(game.hud._prompt.text.contains("COUTEAU DE CHASSE") and game.hud._prompt.text.contains("3000"), "invite : %s" % game.hud._prompt.text)
	p.input.interact_pressed = true
	await seconds(0.4)
	at.check(pd.knife == "knife" and pd.points == 2999, "refusé à 2999 points")
	pd.points = 3000
	game.session.sync_stats(1)
	p.input.interact_pressed = true
	await seconds(0.3)
	at.check(pd.knife == "bowie" and pd.points == 0, "couteau de chasse acheté (points %d)" % pd.points)
	at.check(p.weapons.knife_id == "bowie" and p.weapons.is_picking_up_knife(), "animation de récupération")
	p.pitch = 0.0
	await seconds(0.5)
	await at.screenshot("bowie_pickup_raise")
	await seconds(0.5)
	await at.screenshot("bowie_pickup_look")
	# Pendant la récupération : ni tir ni couteau.
	var mag: int = p.weapons.current().mag
	p.input.fire_pressed = true
	p.input.fire = true
	await seconds(0.1)
	p.input.fire = false
	at.check(p.weapons.current().mag == mag, "pas de tir pendant la récupération")
	await seconds(1.2)
	at.check(not p.weapons.is_picking_up_knife(), "récupération terminée (~2 s)")
	at.check(game.hud._prompt.text == "", "plus d'invite une fois acheté (%s)" % game.hud._prompt.text)

	# 6. Manche 10 : un coup de couteau de chasse (avec fente) suffit.
	var hp10 := RoundRules.zombie_health(10)
	pts = pd.points
	z = await setup_duel(p, 2.5, hp10)
	await knife(p)
	await seconds(0.15)
	await at.screenshot("bowie_slash")
	await seconds(0.3)
	at.check(not z.is_alive(), "zombie de manche 10 (%d PV) tué d'un coup de couteau de chasse" % hp10)
	at.check(pd.points - pts == 130, "mort au couteau de chasse : +130 (%d)" % (pd.points - pts))
	z = await setup_duel(p, 1.2, 5000)
	await knife(p)
	await seconds(0.4)
	at.check(z.health == 5000 - KnifeDB.damage("bowie"), "couteau de chasse : %d dégâts (5000 -> %d)" % [KnifeDB.damage("bowie"), z.health])
	await H.clear_zombies(self)
