extends AutotestScenario
## @parts 2 : partie 0 = emplacements, portes, navigation entre les étages,
## courant, vues (captures + perf) ; partie 1 = manche 1 dans le hall, piège,
## manche de chiens (portes et courant ouverts directement).
## KINO (Kino der Toten à l'échelle 1) : tous les emplacements de BO1 sont en
## place et dans la bonne zone, porte fermée infranchissable, la navigation
## relie toutes les salles une fois les portes ouvertes, le courant ouvre le
## rideau et le couloir du hall, les zombies changent d'étage par les
## escaliers ; zombies de la manche 1 dans le hall seulement ; chiens de
## l'enfer qui apparaissent près du joueur dans les zones ouvertes.

var H := AutotestHelpers
var game: Game
var p: Player
var l: MeshMapLayout
## [nom, œil au sol, lacet, tangage]
const VIEWS := [
	["hall", Vector3(75.0, 2.1, 105.0), 0.0, -0.05],
	["hall_balcon", Vector3(75.0, 6.9, 91.8), PI, -0.25],
	["theatre", Vector3(75.0, 0.2, 45.0), PI, 0.08],
	["foyer", Vector3(104.0, 0.1, 64.0), PI * 0.75, 0.0],
	["ruelle", Vector3(37.0, 0.1, 80.0), 0.0, 0.0],
]


func reach(from: Vector3, to: Vector3, limit: float, label: String) -> void:
	await H.clear_zombies(self)
	p.teleport_to(to + Vector3.UP * 0.05)
	await seconds(0.3)
	var z := game.zombies.get_zombie(game.zombies.spawn(from, 3, 150))
	var t0 := Time.get_ticks_msec()
	var ok: bool = await until(func(): return z.global_position.distance_to(p.global_position) < 2.0, limit, label)
	if ok:
		at.check(true, "%s (%.1f s)" % [label, (Time.get_ticks_msec() - t0) / 1000.0])


func run() -> void:
	timeout_sec = 240
	p = await H.start_solo_game(self, "kino")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	l = game.layout as MeshMapLayout
	at.check(game.map_def.id == "kino" and l != null, "KINO : carte en maillage")
	at.check(Audio._music_name == "ambience_kino", "ambiance sonore du théâtre (%s)" % Audio._music_name)
	if owns(1):
		await _round_one()
	game.rounds.paused = true
	await H.clear_zombies(self)
	at.check(l.zone_at(p.global_position) == "a", "départ dans le hall (%s)" % l.zone_at(p.global_position))

	# Emplacements de Kino der Toten.
	at.check(l.windows().size() == 22, "22 fenêtres (%d)" % l.windows().size())
	var box: MysteryBox = game.interact.get_obj("box")
	at.check(box != null and box.spots.size() == 9, "9 emplacements de boîte (%d)" % (box.spots.size() if box else 0))
	at.check(game.map_def.box_starts.size() == 8 and not 1 in game.map_def.box_starts, "départ de la boîte : 8 emplacements, jamais le balcon du hall")
	at.check(box.location in game.map_def.box_starts, "départ de la boîte tiré au sort parmi %s (%d)" % [game.map_def.box_starts, box.location])
	var wb_zone := {"V": "a", "R": "a", "B": "b", "K": "c", "<": "e", "M": "f", ">": "f", "U": "g", "/": "h", "%": "t"}
	for mk in l.wall_buys():
		at.check(mk.zone == wb_zone.get(mk.id, "?"), "achat mural %s (%s) dans la zone %s (%s)" % [mk.id, mk.data.weapon, wb_zone.get(mk.id, "?"), mk.zone])
	var bowie: WallBuy = game.interact.get_obj("wallbuy_%")
	at.check(bowie != null and bowie.is_knife and bowie.cost == 3000, "couteau de chasse au mur (3000)")
	var m14: WallBuy = game.interact.get_obj("wallbuy_R")
	var olympia: WallBuy = game.interact.get_obj("wallbuy_V")
	at.check(m14 != null and m14.weapon_id == "m14" and olympia != null and olympia.weapon_id == "olympia", "M14 et Olympia dans le hall")
	var nades := game.world.find_children("*", "GrenadeBuy", true, false)
	at.check(nades.size() == 1, "un achat de grenades (%d)" % nades.size())
	var perk_zone := {"Q": "a", "J": "t", "S": "f", "D": "c"}
	for mk in l.perks():
		at.check(mk.zone == perk_zone.get(mk.id, "?"), "atout %s dans la zone %s (%s)" % [mk.data.perk, perk_zone.get(mk.id, "?"), mk.zone])
	var costs := {}
	for d: Door in game.doors.values():
		costs[d.door_id] = d.cost
	at.check(costs.get("1") == 750 and costs.get("2") == 750 and costs.get("3") == 1000 and costs.get("4") == 1250 and costs.get("5") == 1250 and costs.get("6") == 1000 and costs.get("7") == 1250 and costs.get("8") == 1250, "prix des portes de BO1 (%s)" % str(costs))
	at.check(game.doors.has("rideau") and game.doors.rideau.power_door, "rideau de scène ouvert par le courant")
	at.check(game.teleporter != null and game.teleporter.needs_link and game.teleporter.mainframe != null, "téléporteur à relier au poste central")

	if owns(0):
		await _doors_and_navigation()
	if owns(1):
		await _trap_and_dogs()


## Manche 1 : les zombies viennent du hall (ses fenêtres et son sol) seulement.
func _round_one() -> void:
	var ok: bool = await until(func(): return game.zombies.alive_count() >= 2, 16.0, "zombies de la manche 1")
	if not ok:
		return
	var zones := []
	for z: Zombie in game.zombies.alive:
		# Zombie derrière une fenêtre : zone de la fenêtre (la poche du dehors
		# de la fenêtre du balcon surplombe la salle basse) ; sinon, sa position.
		zones.append(l.windows()[z.barricade.window_index].zone if z.barricade != null else l.zone_at(z.global_position))
	at.check(zones.all(func(zone): return zone == "a"), "zombies apparus dans le hall uniquement (%s)" % str(zones))


func _doors_and_navigation() -> void:
	# Porte fermée : on fonce dans la porte 1 (hall -> salle basse), vers l'ouest.
	var door1: Door = game.doors["1"]
	p.teleport_to(door1.global_position + Vector3(2.2, 0.1, 0), PI * 0.5)
	p.input.move = Vector2(0, 1)
	await seconds(1.5)
	p.input.move = Vector2.ZERO
	at.check(p.global_position.x > door1.global_position.x + 0.5, "la porte fermée bloque le joueur (x=%.2f, porte %.2f)" % [p.global_position.x, door1.global_position.x])

	# Fenêtres : chaque apparition du dehors est rattachée à sa fenêtre.
	var attached := 0
	for w: Barricade in game.barricades.windows:
		var z := game.zombies.get_zombie(game.zombies.spawn(l.windows()[w.window_index].spawn_points[0], 2, 150))
		await frames(2)
		if z.barricade == w:
			attached += 1
	at.check(attached == 22, "22 apparitions derrière leur fenêtre (%d)" % attached)
	await H.clear_zombies(self)

	# Navigation : portes fermées, rien au-delà du hall.
	var start := l.player_spawns()[0]
	var nav := game.nav
	var lower_hall: MapMarker = null
	for mk in l.wall_buys():
		if mk.id == "B":
			lower_hall = mk
	at.check(nav.find_path(start, lower_hall.pos).is_empty(), "porte 750 fermée : salle basse inaccessible")
	# Toutes les portes payantes et le courant.
	for d: Door in game.doors.values():
		if not d.power_door:
			d.srv_open()
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await until(func(): return game.power_on and game.doors.rideau.is_open and game.doors.courant_hall.is_open, 4.0, "courant : rideau et couloir ouverts")
	await seconds(0.5)
	var unreachable := []
	for list in [l.wall_buys(), l.perks(), l.box_spots()]:
		for mk: MapMarker in list:
			if nav.find_path(start, mk.pos).is_empty():
				unreachable.append("%s (%s)" % [mk.id, mk.zone])
	at.check(unreachable.is_empty(), "tout est accessible à pied depuis le hall (inaccessibles : %s)" % str(unreachable))
	var pap := l.pack_a_punch()
	at.check(nav.find_path(start, pap.pos).is_empty(), "salle de projection : seulement par le téléporteur")

	# Zombies : changements d'étage.
	await reach(start, l.box_spots()[1].pos, 30.0, "zombie monte l'escalier du hall jusqu'au balcon")
	await reach(l.box_spots()[3].pos, l.box_spots()[4].pos, 40.0, "zombie de la ruelle monte à l'arrière-salle")
	await reach(start, l.box_spots()[8].pos, 40.0, "zombie du hall entre dans la salle de théâtre par le couloir")
	await H.clear_zombies(self)

	# Vues (courant rétabli) : captures et images par seconde.
	var worst := 10000.0
	for v in VIEWS:
		p.teleport_to(v[1], v[2])
		p.pitch = v[3]
		await seconds(0.8)
		at.begin_perf()
		await seconds(0.8)
		worst = minf(worst, at.end_perf(v[0]))
		await at.screenshot(v[0])
	at.check_perf(worst, 150.0, "pire vue de KINO")


func _trap_and_dogs() -> void:
	# Portes et courant ouverts directement.
	for d: Door in game.doors.values():
		if not d.power_door:
			d.srv_open()
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await until(func(): return game.power_on, 5.0, "courant")
	# Piège des loges : 1000 points.
	var pd := game.session.local_data()
	pd.points = 2000
	game.session.sync_stats(1)
	var trap: ElectricTrap = game.interact.get_obj("trap_4")
	trap.srv_use(1)
	at.check(trap.state == ElectricTrap.State.ACTIVE and pd.points == 1000, "piège des loges activé (%d points restants)" % pd.points)
	await _dog_round()


## Manche de chiens sur KINO : apparitions sur le navmesh dans les zones
## ouvertes, près du joueur (10 à 25 m), chiens qui le rejoignent, puis retour
## à l'ambiance du théâtre.
func _dog_round() -> void:
	var dogs: DogRound = game.rounds.dogs
	await H.clear_zombies(self)
	p.teleport_to(Vector3(75.0, 0.1, 65.6), PI)  # allée centrale de la salle
	var dists: Array = []
	var bad_zones: Array = []
	game.zombies.zombie_spawned.connect(func(z: Zombie):
		if z is Hellhound:
			dists.append(Vector2(z.global_position.x - p.global_position.x, z.global_position.z - p.global_position.z).length())
			var zone := l.zone_at(z.global_position)
			if not game.spawner.active_zones.has(zone):
				bad_zones.append(zone))
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
	at.check(near_ok and bad_zones.is_empty(), "chiens apparus près du joueur, zones ouvertes (%s m ; hors zone : %s)" % [dists, bad_zones])
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
