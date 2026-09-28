extends AutotestScenario
## KINO V2 (maquette grise) : tous les emplacements de Kino der Toten sont en
## place et dans la bonne zone, la navigation relie toutes les salles une fois
## les portes ouvertes, le courant ouvre le rideau et le couloir du hall, les
## zombies changent d'étage par les escaliers.

var game: Game
var p: Player
const VIEWS := [
	["hall", Vector3(75.0, 2.1, 105.0), 0.0, -0.05],
	["hall_balcon", Vector3(75.0, 6.9, 91.8), PI, -0.25],
	["theatre", Vector3(75.0, 0.2, 45.0), PI, 0.08],
	["foyer", Vector3(104.0, 0.1, 64.0), PI * 0.75, 0.0],
	["ruelle", Vector3(37.0, 0.1, 80.0), 0.0, 0.0],
]


func clear_zombies() -> void:
	for zid in game.zombies.zombies.keys():
		game.zombies.despawn(zid)
	await frames(2)


func reach(from: Vector3, to: Vector3, limit: float, label: String) -> void:
	await clear_zombies()
	p.teleport_to(to + Vector3.UP * 0.05)
	await seconds(0.3)
	var z := game.zombies.get_zombie(game.zombies.spawn(from, 3, 150))
	var t0 := Time.get_ticks_msec()
	var ok: bool = await until(func(): return z.global_position.distance_to(p.global_position) < 2.0, limit, label)
	if ok:
		at.check(true, "%s (%.1f s)" % [label, (Time.get_ticks_msec() - t0) / 1000.0])


func run() -> void:
	timeout_sec = 240
	p = await AutotestHelpers.start_solo_game(self, "kino_v2")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await clear_zombies()
	var l := game.layout as MeshMapLayout
	at.check(l != null, "KINO V2 : carte en maillage")
	at.check(l.zone_at(p.global_position) == "a", "départ dans le hall (%s)" % l.zone_at(p.global_position))

	# Emplacements de Kino der Toten.
	at.check(l.windows().size() == 22, "22 fenêtres (%d)" % l.windows().size())
	at.check(l.box_spots().size() == 9, "9 emplacements de boîte (%d)" % l.box_spots().size())
	at.check(game.map_def.box_starts.size() == 8 and not 1 in game.map_def.box_starts, "départ de la boîte : 8 emplacements, jamais le balcon du hall")
	var wb_zone := {"V": "a", "R": "a", "B": "b", "K": "c", "<": "e", "M": "f", ">": "f", "U": "g", "/": "h", "%": "t"}
	for mk in l.wall_buys():
		at.check(mk.zone == wb_zone.get(mk.id, "?"), "achat mural %s (%s) dans la zone %s (%s)" % [mk.id, mk.data.weapon, wb_zone.get(mk.id, "?"), mk.zone])
	var perk_zone := {"Q": "a", "J": "t", "S": "f", "D": "c"}
	for mk in l.perks():
		at.check(mk.zone == perk_zone.get(mk.id, "?"), "atout %s dans la zone %s (%s)" % [mk.data.perk, perk_zone.get(mk.id, "?"), mk.zone])
	var costs := {}
	for d: Door in game.doors.values():
		costs[d.door_id] = d.cost
	at.check(costs.get("1") == 750 and costs.get("2") == 750 and costs.get("3") == 1000 and costs.get("4") == 1250 and costs.get("5") == 1250 and costs.get("6") == 1000 and costs.get("7") == 1250 and costs.get("8") == 1250, "prix des portes de BO1 (%s)" % str(costs))
	at.check(game.doors.has("rideau") and game.doors.rideau.power_door, "rideau de scène ouvert par le courant")

	# Fenêtres : chaque apparition du dehors est rattachée à sa fenêtre.
	var attached := 0
	for w: Barricade in game.barricades.windows:
		var z := game.zombies.get_zombie(game.zombies.spawn(l.windows()[w.window_index].spawn_points[0], 2, 150))
		await frames(2)
		if z.barricade == w:
			attached += 1
	at.check(attached == 22, "22 apparitions derrière leur fenêtre (%d)" % attached)
	await clear_zombies()

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
	await clear_zombies()

	# Vues (maquette grise).
	for v in VIEWS:
		p.teleport_to(v[1], v[2])
		p.pitch = v[3]
		await seconds(0.8)
		await at.screenshot(v[0])
