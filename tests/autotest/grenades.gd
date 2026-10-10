extends AutotestScenario
## Grenades et SINGE-TAMBOUR (BO1) dans le vrai jeu : réserve (2 au départ,
## +2 par manche, 4 au plus), dégoupillage puis lancer en cloche avec rebonds,
## explosion qui tue les zombies (50 points par kill), rebond contre un mur,
## grenade cuite qui explose dans la main, achat mural à 250, MUNITIONS MAX,
## singe qui attire tous les zombies puis explose. Captures à chaque étape.

var H := AutotestHelpers
var game: Game
var p: Player
var pd: PlayerData
var sys: ThrowableSystem
var booms: Array = []


func stand(cell: Vector2i, yaw: float) -> void:
	p.teleport_to(MapData.cell_to_world(cell, 0.05), yaw)
	p.pitch = 0.0
	await seconds(0.3)  # le joueur se pose après la téléportation


func set_frags(n: int) -> void:
	pd.grenades = n
	game.session.sync_stats(1)
	await seconds(0.1)  # synchro vers le client


## Maintient [G] (ou [Q]) `hold` secondes puis relâche. Retourne l'objet lancé.
func throw(tactical: bool, hold: float, shot := "") -> Throwable:
	var before: Array = sys.items.keys()
	if tactical:
		p.input.tactical = true
	else:
		p.input.grenade = true
	await seconds(hold)
	if shot != "":
		await at.screenshot(shot)
	p.input.grenade = false
	p.input.tactical = false
	var ok: bool = await until(func(): return sys.items.size() > before.size(), 1.5, "objet lancé")
	if not ok:
		return null
	for id in sys.items:
		if not id in before:
			return sys.items[id]
	return null


func wait_boom(n: int, limit: float) -> bool:
	return await until(func(): return booms.size() >= n, limit, "explosion n°%d" % n)


func run() -> void:
	timeout_sec = 150
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	sys = game.throwables
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	pd = game.session.local_data()
	sys.exploded.connect(func(kind, pos, pid): booms.append([kind, pos, pid]))
	at.check(sys != null and InputMap.has_action("grenade") and InputMap.has_action("tactical"), "touches [G] grenade et [Q] tactique")

	# 1. Réserve : 2 au départ, +2 par manche, jamais plus de 4.
	at.check(pd.grenades == 2, "2 grenades au départ (%d)" % pd.grenades)
	game.rounds.debug_jump_to(2)
	await until(func(): return pd.grenades == 4, 2.0, "grenades de la manche 2")
	at.check(pd.grenades == 4, "manche 2 : +2 grenades (%d)" % pd.grenades)
	game.rounds.debug_jump_to(3)
	await seconds(0.3)  # fenêtre fixe : la réserve doit rester à 4
	at.check(pd.grenades == 4, "manche 3 : plafonné à 4 (%d)" % pd.grenades)
	await H.clear_zombies(self)
	await stand(Vector2i(4, 7), -PI * 0.5)
	await at.screenshot("hud_4_frags")

	# 2. Lancer en cloche : rebonds, roulement, explosion qui tue 3 zombies de
	# la manche 8 (850 PV), 50 points chacun.
	# Manche 8 : marge suffisante à ~2,5 m, où la séparation des zombies peut
	# écarter le plus éloigné (à la limite exacte en manche 9).
	var hp := RoundRules.zombie_health(8)
	var zs := []
	for k in 3:
		zs.append(await H.dummy_zombie(self, MapData.cell_to_world(Vector2i(12, 7)) + Vector3(0, 0, (k - 1) * 0.75), hp))
	H.aim_at(p, MapData.cell_to_world(Vector2i(10, 7)))
	var points0 := pd.points
	var t := await throw(false, 0.6, "frag_hold")
	at.check(t != null and pd.grenades == 3, "grenade lancée, réserve 3 (%d)" % pd.grenades)
	if t:
		await seconds(0.25)  # capture : grenade en vol
		await at.screenshot("frag_flight")
		var bounced: bool = await until(func(): return not is_instance_valid(t) or t.bounces >= 1, 2.0, "rebond")
		at.check(bounced, "la grenade rebondit au sol")
		await until(func(): return not is_instance_valid(t) or t.on_ground, 3.0, "grenade qui roule")
		if is_instance_valid(t):
			at.check(t.bounces >= 1 and t.on_ground, "roule après %d rebond(s) en %s" % [t.bounces, t.position])
	var boomed := await wait_boom(1, 4.5)
	await seconds(0.06)  # capture
	await at.screenshot("frag_explosion")
	var dead := 0
	for z: Zombie in zs:
		if not z.is_alive():
			dead += 1
	at.check(boomed and dead == 3, "explosion : %d/3 zombies de manche 8 tués" % dead)
	at.check(pd.points - points0 == 3 * PointsRules.KILL, "50 points par kill d'explosion (+%d)" % (pd.points - points0))
	await seconds(0.8)  # capture : fumée
	await at.screenshot("frag_smoke")
	await H.clear_zombies(self)

	# 3. Contre un mur : la grenade est renvoyée.
	await stand(Vector2i(5, 3), 0.0)  # face au mur nord (z = 1), à 2,5 m
	t = await throw(false, 0.5)
	if t:
		await until(func(): return not is_instance_valid(t) or t.on_ground, 3.0, "retombée")
		if is_instance_valid(t):
			at.check(t.bounces >= 2 and t.position.z > 1.0, "renvoyée par le mur (%d rebonds, z %.2f)" % [t.bounces, t.position.z])
	await wait_boom(2, 4.5)

	# 4. Cuite trop longtemps : explose dans la main, le lanceur est blessé.
	game.combat.debug_invulnerable = false
	await seconds(0.3)
	pd.health = pd.max_health
	game.session.sync_stats(1)
	await stand(Vector2i(3, 12), -PI * 0.5)
	var zc := await H.dummy_zombie(self, p.global_position + Vector3(2.4, 0, 0), 800)
	var items0 := sys.items.size()
	p.input.grenade = true
	await seconds(ThrowableRules.FUSE - 0.6)  # touche tenue : la grenade cuit
	await at.screenshot("cook_danger")
	var in_hand := await wait_boom(3, 1.5)
	await seconds(0.05)  # capture
	await at.screenshot("cook_explosion")
	p.input.grenade = false
	at.check(in_hand and sys.items.size() == items0 and booms[2][0] == ThrowableRules.Kind.FRAG
		and (booms[2][1] as Vector3).distance_to(p.global_position) < 1.6, "explosion dans la main")
	at.check(pd.health < pd.max_health and pd.life == PlayerData.Life.ALIVE, "lanceur blessé mais debout (%d PV)" % pd.health)
	at.check(not zc.is_alive(), "le zombie voisin est tué")
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	await seconds(0.5)

	# 5. Achat mural : 250 points, réserve remplie à 4.
	at.check(pd.grenades == 1, "réserve après 3 grenades : 1 (%d)" % pd.grenades)
	var buy: GrenadeBuy = game.interact.get_obj("grenades_20_1")
	at.check(buy != null and buy.get_node_or_null("Chalk") != null, "achat mural de grenades (craie)")
	if buy:
		p.teleport_to(Vector3(buy.global_position.x, 0.05, buy.global_position.z + 1.3))
		H.aim_at(p, buy.global_position)
		await until(func(): return game.hud._prompt.text.contains("250"), 2.0, "invite de l'achat de grenades")
		at.check(game.hud._prompt.text.contains("250"), "invite : %s" % game.hud._prompt.text)
		await at.screenshot("wall_buy")
		game.session.add_points(1, 250)  # on part de 0 ferraille
		var pts := pd.points
		p.input.interact_pressed = true
		await until(func(): return pd.grenades == 4 and pts - pd.points == 250, 2.0, "grenades achetées")
		at.check(pd.grenades == 4 and pts - pd.points == 250, "grenades achetées : 4 (-%d points)" % (pts - pd.points))
		await until(func(): return game.hud._prompt.text == "", 2.0, "invite retirée")
		at.check(game.hud._prompt.text == "", "réserve pleine : plus d'invite")

	# 6. MUNITIONS MAX : grenades à 4 (et singes à 3 s'il y en a).
	await set_frags(0)
	game.powerups.apply(PowerupRules.MAX_AMMO, 1, p.global_position)
	await until(func(): return pd.grenades == 4, 2.0, "grenades rendues par munitions max")
	at.check(pd.grenades == 4 and pd.monkeys == 0, "munitions max : 4 grenades, pas de singe (%d / %d)" % [pd.grenades, pd.monkeys])

	# 7. SINGE-TAMBOUR : attire tous les zombies, puis explose.
	sys.srv_give_monkeys(1)
	await until(func(): return pd.has_monkeys and pd.monkeys == 3, 2.0, "singes reçus")
	at.check(pd.has_monkeys and pd.monkeys == 3, "3 singes reçus")
	await stand(Vector2i(4, 7), -PI * 0.5)
	await at.screenshot("hud_monkeys")
	var runners := []
	for c in [Vector2i(22, 2), Vector2i(23, 12), Vector2i(12, 17), Vector2i(12, 2)]:
		var zid := game.zombies.spawn(MapData.cell_to_world(c), 1, 150)
		runners.append(game.zombies.get_zombie(zid))
	await H.emerged(self, runners)
	H.aim_at(p, MapData.cell_to_world(Vector2i(11, 7)))
	var monkey := await throw(true, 0.5, "monkey_hold")
	at.check(monkey != null and pd.monkeys == 2, "singe lancé (reste %d)" % pd.monkeys)
	var luring: bool = await until(func(): return sys.lure_count() == 1, 4.0, "singe posé, musique")
	at.check(luring, "le singe joue sa musique")
	var mpos: Vector3 = monkey.position if is_instance_valid(monkey) else Vector3.ZERO
	# Le joueur s'éloigne : les zombies ne le suivent pas.
	await stand(Vector2i(5, 7), -PI * 0.5)
	H.aim_at(p, mpos)
	await seconds(4.5)  # fenêtre mesurée : les zombies rejoignent le singe sans poursuivre le joueur
	await at.screenshot("monkey_lure")
	var near := 0
	var lured := 0
	var closest_to_player := INF
	for z: Zombie in runners:
		if z.is_alive():
			if z.lured:
				lured += 1
			if Vector2(z.global_position.x - mpos.x, z.global_position.z - mpos.z).length() < 3.0:
				near += 1
			closest_to_player = minf(closest_to_player, z.global_position.distance_to(p.global_position))
	at.check(lured == runners.size(), "tous les zombies suivent le singe (%d/%d)" % [lured, runners.size()])
	at.check(near >= 3, "zombies regroupés autour du singe (%d/%d à moins de 3 m)" % [near, runners.size()])
	at.check(closest_to_player > 3.0, "aucun zombie ne poursuit le joueur (plus proche %.1f m)" % closest_to_player)
	var pts2 := pd.points
	var mboom := await wait_boom(4, ThrowableRules.MONKEY_TIME + 1.0)
	await seconds(0.06)  # capture
	await at.screenshot("monkey_explosion")
	var mdead := 0
	for z: Zombie in runners:
		if not z.is_alive():
			mdead += 1
	at.check(mboom and booms[3][0] == ThrowableRules.Kind.MONKEY and mdead >= near, "explosion du singe : %d zombies tués" % mdead)
	at.check(pd.points - pts2 == mdead * PointsRules.KILL, "points des kills du singe (+%d)" % (pd.points - pts2))
	# Après la musique, les zombies restants reviennent vers les joueurs.
	await until(func():
		for z in runners:
			if is_instance_valid(z) and z.is_alive() and z.lured:
				return false
		return true, 2.0, "zombies libérés du singe")
	for z: Zombie in runners:
		if z.is_alive():
			at.check(not z.lured, "zombie survivant de nouveau sur les joueurs")
	game.powerups.apply(PowerupRules.MAX_AMMO, 1, p.global_position)
	await until(func(): return pd.monkeys == 3, 2.0, "singes rendus par munitions max")
	at.check(pd.monkeys == 3, "munitions max : singes rendus (%d)" % pd.monkeys)
	await H.clear_zombies(self)
