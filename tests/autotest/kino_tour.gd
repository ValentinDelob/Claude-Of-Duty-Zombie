extends AutotestScenario
## @parts 2 : partie 0 = visite, portes, navigation, courant ; partie 1 = téléporteur,
## Pack-a-Punch, piège et chiens (portes et courant ouverts directement).
## KINO : visite de chaque zone (captures + perf), portes fermées, zombies de
## la manche 1 dans le hall, départ aléatoire de la boîte, deux pièges,
## courant, liaison du téléporteur (plateforme -> poste central), voyage vers
## la cabine de projection, retour au poste central, Pack-a-Punch qui surgit
## sur la scène et fonctionne.

var H := AutotestHelpers
## [nom, cellule, cellule visée]
const VIEWS := [
	["hall", Vector2i(33, 41), Vector2i(33, 28)],
	["hall_poste", Vector2i(28, 35), Vector2i(33, 43)],
	["foyer", Vector2i(49, 41), Vector2i(68, 30)],
	["loges", Vector2i(12, 31), Vector2i(4, 19)],
	["loges_couloir", Vector2i(12, 21), Vector2i(12, 11)],
	["machines", Vector2i(18, 8), Vector2i(10, 2)],
	["allee_cour", Vector2i(54, 10), Vector2i(69, 3)],
	["allee_passage", Vector2i(61, 26), Vector2i(61, 12)],
	["theatre", Vector2i(36, 20), Vector2i(36, 3)],
	["theatre_rangs", Vector2i(22, 18), Vector2i(48, 8)],
	["scene", Vector2i(36, 6), Vector2i(36, 19)],
	["cabine", Vector2i(39, 25), Vector2i(29, 23)],
]

var game: Game
var p: Player


func run() -> void:
	timeout_sec = 300
	p = await H.start_solo_game(self, "kino")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	at.check(game.map_def.id == "kino", "carte KINO chargée")
	at.check(game.doors.size() == 5, "5 portes (%d)" % game.doors.size())
	at.check(game.barricades.windows.size() == 14, "14 fenêtres barricadées (%d)" % game.barricades.windows.size())
	at.check(Audio._music_name == "ambience_kino", "ambiance sonore du théâtre (%s)" % Audio._music_name)
	var box: MysteryBox = game.interact.get_obj("box")
	at.check(box != null and box.spots.size() == 5, "boîte mystère : 5 emplacements")
	at.check(box.location in game.map_def.box_starts, "départ de la boîte tiré au sort parmi %s (%d)" % [game.map_def.box_starts, box.location])
	var pap: PackAPunch = game.interact.get_obj("pap")
	at.check(pap != null and not pap.revealed and not pap.visible, "Pack-a-Punch caché avant le premier voyage")
	var trap1: ElectricTrap = game.interact.get_obj("trap")
	var trap2: ElectricTrap = game.interact.get_obj("trap_2")
	at.check(trap1 != null and trap2 != null, "deux pièges électriques")
	at.check(trap1.contains(MapData.cell_to_world(Vector2i(12, 15))) and trap2.contains(MapData.cell_to_world(Vector2i(61, 16))), "pièges des loges et de l'allée")
	var bowie: WallBuy = game.interact.get_obj("wallbuy_%")
	var m14: WallBuy = game.interact.get_obj("wallbuy_R")
	at.check(bowie != null and bowie.is_knife and bowie.cost == 3000, "couteau de chasse au mur (3000)")
	at.check(m14 != null and m14.weapon_id == "m14" and game.interact.get_obj("wallbuy_V").weapon_id == "olympia", "M14 et Olympia dans le hall")
	at.check(game.interact.get_obj("grenades_45_33") is GrenadeBuy and game.interact.get_obj("grenades_70_30") is GrenadeBuy, "achats de grenades dans le hall et le foyer")
	var tp := game.teleporter
	var mf: TeleporterMainframe = game.interact.get_obj("mainframe")
	at.check(tp != null and mf != null and tp.needs_link, "téléporteur à relier au poste central")

	if owns(0):
		# Porte fermée : on fonce dans la porte 2 (hall -> loges), vers l'ouest.
		p.teleport_to(MapData.cell_to_world(Vector2i(23, 31), 0.05), PI * 0.5)
		p.input.move = Vector2(0, 1)
		await seconds(1.5)
		p.input.move = Vector2.ZERO
		at.check(p.global_position.x > 20.5, "la porte fermée bloque le joueur (x=%.2f)" % p.global_position.x)

		# Manche 1 : zombies du hall uniquement (fenêtres et sol du hall).
		await until(func(): return game.zombies.alive_count() >= 2, 16.0, "zombies de la manche 1")
		var ok_zone := true
		for z: Zombie in game.zombies.alive:
			if game.map_data.zone_at(MapData.world_to_cell(z.global_position)) != "a":
				ok_zone = false
		at.check(ok_zone, "zombies apparus dans le hall uniquement")
		game.rounds.paused = true
		await H.clear_zombies(self)
		p.teleport_to(MapData.cell_to_world(Vector2i(33, 40), 0.05))
		H.aim_at(p, MapData.cell_to_world(Vector2i(33, 28), 1.6))
		await seconds(0.8)
		await at.screenshot("hall_sans_courant")

		for id in game.doors:
			game.doors[id].srv_open()
		await seconds(1.8)
		at.check(game.spawner.active_zones.has("g") and game.spawner.active_zones.has("e"), "zones reliées sans porte activées")

		# Navigation : un zombie du fond de la salle rejoint le joueur sur la scène
		# (allées entre les rangées de fauteuils).
		p.teleport_to(MapData.cell_to_world(Vector2i(36, 4), 0.05))
		var zid := game.zombies.spawn(MapData.cell_to_world(Vector2i(49, 19)), 2, 100000)
		var reached: bool = await until(func():
			var z := game.zombies.get_zombie(zid)
			return z != null and z.global_position.distance_to(p.global_position) < 2.2, 30.0, "zombie jusqu'à la scène")
		if reached:
			at.check(true, "un zombie traverse la salle jusqu'à la scène")
		await H.clear_zombies(self)

		# Courant : levier de la salle des machines.
		var sw: PowerSwitch = game.interact.get_obj("power")
		await _use(sw, Vector2i(14, 4))
		at.check(game.power_on, "courant rétabli depuis la salle des machines")
		await seconds(2.5)

		# Visite.
		var worst := 10000.0
		for v in VIEWS:
			p.teleport_to(MapData.cell_to_world(v[1], 0.05))
			H.aim_at(p, MapData.cell_to_world(v[2], 1.3))
			await seconds(0.6)
			at.begin_perf()
			await seconds(1.0)
			worst = minf(worst, at.end_perf(v[0]))
			await at.screenshot(v[0])
		at.check_perf(worst, 150.0, "pire vue de KINO")

	if not owns(1):
		return
	if not owns(0):
		# Partie seule : portes et courant ouverts directement.
		game.rounds.paused = true
		await H.clear_zombies(self)
		for id in game.doors:
			game.doors[id].srv_open()
		(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
		await until(func(): return game.power_on, 5.0, "courant")
		await seconds(1.0)
	await _teleporter(tp, mf, pap, pd)
	await _pap(pap, pd)

	# Piège de l'allée.
	pd.points = 2000
	game.session.sync_stats(1)
	trap2.srv_use(1)
	at.check(trap2.state == ElectricTrap.State.ACTIVE and pd.points == 1000, "piège de l'allée activé (%d)" % pd.points)
	p.teleport_to(MapData.cell_to_world(Vector2i(61, 22), 0.05))
	H.aim_at(p, MapData.cell_to_world(Vector2i(61, 15), 1.2))
	await seconds(0.8)
	await at.screenshot("piege_allee")
	await _dog_round()


## Se place devant un objet, le vise et appuie sur [F] (vraie interaction).
func _use(obj: Interactable, cell: Vector2i) -> void:
	p.teleport_to(MapData.cell_to_world(cell, 0.05))
	H.aim_at(p, obj.interact_point())
	await seconds(0.4)
	at.check(game.interact.focused == obj, "%s visé : %s" % [obj.interact_id, game.hud._prompt.text])
	p.input.interact_pressed = true
	await seconds(0.4)


func _teleporter(tp: Teleporter, mf: TeleporterMainframe, pap: PackAPunch, pd: PlayerData) -> void:
	pd.points = 5000
	game.session.sync_stats(1)
	# 1. Activer la plateforme de la scène.
	await _use(tp, Vector2i(26, 5))
	at.check(tp.link == Teleporter.Link.PRIMED, "plateforme activée (%s)" % game.hud._prompt.text)
	p.input.interact_pressed = true
	await seconds(0.3)
	at.check(tp.state == Teleporter.State.IDLE and pd.points == 5000, "pas de voyage avant la liaison")
	# 2. Relier au poste central du hall.
	await _use(mf, Vector2i(33, 41))
	at.check(tp.link == Teleporter.Link.LINKED, "téléporteur relié au poste central")
	await seconds(0.3)
	await at.screenshot("poste_relie")
	# 3. Voyage (1500) vers la cabine de projection.
	p.teleport_to(tp.global_position + Vector3(0.3, 0.1, 0.3))
	H.aim_at(p, tp.global_position + Vector3.UP * 0.2)
	await seconds(0.4)
	p.input.interact_pressed = true
	await seconds(0.3)
	at.check(tp.state == Teleporter.State.CHARGING and pd.points == 3500, "voyage payé, charge (%d)" % pd.points)
	await until(func(): return tp.state == Teleporter.State.ACTIVE, 4.0, "départ")
	await seconds(0.6)
	var zone := game.map_data.zone_at(MapData.world_to_cell(p.global_position))
	at.check(zone == "p", "joueur dans la cabine de projection (zone %s)" % zone)
	at.check(game.hud._hint.text.begins_with("RETOUR DANS"), "compte à rebours : %s" % game.hud._hint.text)
	at.check(pap.revealed, "le premier voyage fait apparaître le Pack-a-Punch")
	H.aim_at(p, MapData.cell_to_world(Vector2i(30, 23), 1.2))
	await seconds(0.4)
	await at.screenshot("cabine_arrivee")
	await until(func(): return tp.state == Teleporter.State.IDLE, Teleporter.ACTIVE_TIME + 3.0, "retour")
	await seconds(0.5)
	var d := p.global_position.distance_to(mf.arrival_point())
	at.check(d < 2.5, "retour devant le poste central (%.1f m)" % d)
	at.check(tp.link == Teleporter.Link.UNLINKED, "liaison à refaire après chaque voyage")


func _pap(pap: PackAPunch, pd: PlayerData) -> void:
	at.check(pap.visible and absf(pap.position.y) < 0.05, "Pack-a-Punch dressé sur la scène")
	p.teleport_to(MapData.cell_to_world(Vector2i(35, 8), 0.05))
	H.aim_at(p, pap.global_position + Vector3.UP * 1.5)
	await seconds(0.5)
	await at.screenshot("scene_pack_a_punch")
	pd.points = 6000
	game.session.sync_stats(1)
	await _use(pap, Vector2i(35, 5))
	at.check(pap.state == PackAPunch.State.WORKING and pd.points == 1000, "Pack-a-Punch sur scène utilisable (%d)" % pd.points)


## Manche de chiens sur KINO : apparitions dans les zones ouvertes, près du
## joueur (10 à 25 m), chiens qui le rejoignent, puis retour à l'ambiance du
## théâtre.
func _dog_round() -> void:
	var dogs: DogRound = game.rounds.dogs
	await H.clear_zombies(self)
	p.teleport_to(MapData.cell_to_world(Vector2i(36, 15), 0.05))
	var dists: Array = []
	var zones_ok := [true]
	game.zombies.zombie_spawned.connect(func(z: Zombie):
		if z is Hellhound:
			dists.append(Vector2(z.global_position.x - p.global_position.x, z.global_position.z - p.global_position.z).length())
			var zone := game.map_data.zone_at(MapData.world_to_cell(z.global_position))
			if not game.spawner.active_zones.has(zone):
				zones_ok[0] = false)
	dogs.debug_force_next(5)
	game.rounds.paused = false
	game.rounds.debug_jump_to(5)
	await seconds(0.3)
	at.check(dogs.active, "manche 5 : manche de chiens sur KINO")
	var ok: bool = await until(func(): return dists.size() >= 2, 20.0, "chiens apparus")
	if not ok:
		return
	var near_ok := true
	for d in dists:
		near_ok = near_ok and d >= 4.0 and d <= DogRules.SPAWN_MAX_DIST + 2.0
	at.check(near_ok and zones_ok[0], "chiens apparus près du joueur, zones ouvertes (%s m)" % [dists])
	var reached: bool = await until(func():
		for z: Zombie in game.zombies.alive:
			if z is Hellhound and (z as Hellhound)._revealed and z.global_position.distance_to(p.global_position) < 3.0:
				return true
		return false, 25.0, "un chien rejoint le joueur")
	if reached:
		at.check(true, "un chien traverse la salle jusqu'au joueur")
	await at.screenshot("chiens")
	# Fin de manche : tous les chiens abattus.
	var cleared: bool = await until(func():
		for z: Zombie in game.zombies.alive.duplicate():
			if z is Hellhound and (z as Hellhound)._revealed:
				game.combat.damage_zombie(z.id, 100000, 1, false, Vector3.UP, Combat.HitKind.BULLET)
		return not dogs.active, 60.0, "fin de la manche de chiens")
	if cleared:
		at.check(true, "manche de chiens terminée (%d chiens)" % dogs.total)
		await until(func(): return dogs.fog_amount() < 0.01, 15.0, "brouillard dissipé")
		at.check(Audio._music_name == "ambience_kino", "musique du théâtre reprise (%s)" % Audio._music_name)
		var env := (game.world.get_node("WorldEnvironment") as WorldEnvironment).environment
		at.check(absf(env.fog_density - float(game.map_def.look.fog_density)) < 0.005, "ambiance du théâtre rétablie (brouillard %.3f)" % env.fog_density)
	game.rounds.paused = true
