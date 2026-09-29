extends AutotestScenario
## DRAFT ARENA, carte DESSINÉE (docs/MAP_AUTHORING.md) : preuve qu'une carte
## tirée d'un dessin se joue. Manche 1 : les zombies n'apparaissent qu'aux
## fenêtres de la zone de départ, franchissent leur barricade et rejoignent le
## joueur ; chaque apparition est rattachée à sa fenêtre ; portes fermées
## infranchissables pour la navigation ; achat d'une porte et des débris au
## vrai prix ; toutes portes ouvertes et courant rétabli, tout est accessible
## à pied depuis le départ (objets, fenêtres, milieu de chaque salle) ; un
## zombie monte l'escalier jusqu'à la passerelle. Captures (avec rendu) :
## sh tools/scenario.sh draft_arena -> tests/_out/shots/draft_arena_*.png

var H := AutotestHelpers
var game: Game
var p: Player
var l: MeshMapLayout
## [nom, position au sol, lacet, tangage]
const VIEWS := [
	["salle_des_machines", Vector3(7.8, 0.05, 36.4), -PI * 0.3, 0.0],
	["entrepot", Vector3(20.3, 0.05, 20.4), PI * 0.25, 0.12],
	["passerelle", Vector3(8.0, 3.55, 9.8), -PI * 0.75, -0.25],
	["couloir", Vector3(23.0, 0.05, 36.3), 0.0, 0.0],
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
	timeout_sec = 170
	p = await H.start_solo_game(self, "draft_arena")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	l = game.layout as MeshMapLayout
	at.check(game.map_def.id == "draft_arena" and l != null and l.is_multilevel(), "DRAFT ARENA : carte dessinée chargée en maillage à étages")
	at.check(l.zone_at(p.global_position) == "a", "départ dans la zone A (%s)" % l.zone_at(p.global_position))
	var start := l.player_spawns()[0]

	# Ce que le dessin contient, à sa place.
	at.check(game.barricades.windows.size() == 7, "7 fenêtres barricadées (%d)" % game.barricades.windows.size())
	var box: MysteryBox = game.interact.get_obj("box")
	at.check(box != null and box.spots.size() == 3 and box.location == 1, "3 emplacements de boîte, départ dans le couloir (%d)" % (box.location if box else -1))
	at.check(l.zone_at(l.box_spots()[2].pos) == "e", "3e boîte sur la passerelle, à l'étage (y = %.2f)" % l.box_spots()[2].pos.y)
	var perk_zone := {}
	for mk in l.perks():
		perk_zone[mk.data.perk] = mk.zone
	at.check(perk_zone == {"titan": "c", "lazarus": "a"}, "atouts : TITAN BREW dans l'entrepôt, LAZARUS au départ (%s)" % str(perk_zone))
	var wb_zone := {}
	for mk in l.wall_buys():
		wb_zone[mk.data.weapon] = mk.zone
	at.check(wb_zone == {"mp5k": "b", "m14": "a"}, "armes au mur : M14 au départ, MP5K dans le couloir (%s)" % str(wb_zone))
	var costs := {}
	for d: Door in game.doors.values():
		costs[d.door_id] = [d.cost, d.debris]
	at.check(costs == {"1": [1000, false], "2": [1250, true], "3": [750, false]}, "portes 750 et 1000, débris 1250 (%s)" % str(costs))
	at.check(game.interact.get_obj("power") != null and not game.power_on, "interrupteur du courant, courant coupé au départ")

	# Manche 1 : zombies des fenêtres de la zone A, qui rejoignent le joueur.
	p.teleport_to(start + Vector3.UP * 0.05, l.player_spawn_yaw())
	var ok: bool = await until(func(): return game.zombies.alive_count() >= 1, 20.0, "zombies de la manche 1")
	if ok:
		var zones := []
		for z: Zombie in game.zombies.alive:
			zones.append(l.windows()[z.barricade.window_index].zone if z.barricade != null else l.zone_at(z.global_position))
		at.check(zones.all(func(zone): return zone == "a"), "zombies apparus aux fenêtres de la zone A seulement (%s)" % str(zones))
		var t0 := Time.get_ticks_msec()
		var came: bool = await until(func():
			for z: Zombie in game.zombies.alive:
				if z.global_position.distance_to(p.global_position) < 2.2:
					return true
			return false, 70.0, "un zombie franchit sa fenêtre et rejoint le joueur")
		if came:
			at.check(true, "un zombie de la manche 1 arrache les planches, enjambe la fenêtre et rejoint le joueur (%.0f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	game.rounds.paused = true
	await H.clear_zombies(self)

	# Chaque apparition derrière une fenêtre est rattachée à sa fenêtre.
	var attached := 0
	for w: Barricade in game.barricades.windows:
		var z := game.zombies.get_zombie(game.zombies.spawn(l.windows()[w.window_index].spawn_points[0], 2, 150))
		await frames(2)
		if z.barricade == w:
			attached += 1
	at.check(attached == 7, "7 apparitions derrière leur fenêtre (%d)" % attached)
	await H.clear_zombies(self)

	# Portes fermées : la navigation ne passe pas.
	var nav := game.nav
	var titan: MapMarker = l.perks().filter(func(mk): return mk.data.perk == "titan")[0]
	var mp5k: MapMarker = l.wall_buys().filter(func(mk): return mk.data.weapon == "mp5k")[0]
	at.check(nav.find_path(start, mp5k.pos).is_empty() and nav.find_path(start, titan.pos).is_empty(), "portes fermées : couloir et entrepôt inaccessibles")
	await _capture_view(["debris", Vector3(10.0, 0.05, 29.5), 0.0, 0.0])

	# Achats au vrai prix : porte 750, puis débris 1250.
	var pd := game.session.local_data()
	pd.points = 2500
	game.session.sync_stats(1)
	var door_ab: Door = game.doors["3"]
	door_ab.srv_use(1)
	at.check(door_ab.is_open and pd.points == 1750, "porte A-B achetée 750 (%d points restants)" % pd.points)
	await seconds(0.3)
	at.check(not nav.find_path(start, mp5k.pos).is_empty() and game.spawner.active_zones.has("b"), "porte ouverte : couloir accessible et actif")
	var debris: Door = game.doors["2"]
	debris.srv_use(1)
	at.check(debris.is_open and pd.points == 500, "débris dégagés pour 1250 (%d points restants)" % pd.points)
	await seconds(Door.OPEN_TIME + 0.3)
	at.check(not (debris.get_node("Slab") as Node3D).visible, "le tas de débris a disparu")
	at.check(not nav.find_path(start, titan.pos).is_empty() and game.spawner.active_zones.has("c") and game.spawner.active_zones.has("e"),
		"par l'atelier : entrepôt et passerelle accessibles et actifs (zones ouvertes l'une sur l'autre)")

	# Toutes portes ouvertes et courant : tout est accessible à pied.
	for d: Door in game.doors.values():
		if not d.is_open:
			d.srv_open()
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await until(func(): return game.power_on, 4.0, "courant rétabli")
	await seconds(0.5)
	var unreachable := []
	for list in [l.wall_buys(), l.perks(), l.box_spots(), [l.power_switch()]]:
		for mk: MapMarker in list:
			if nav.find_path(start, mk.pos).is_empty():
				unreachable.append("%s (%s)" % [mk.id, mk.zone])
	for w in l.windows():
		if nav.find_path(start, w.pos + w.inward_dir * 1.0).is_empty():
			unreachable.append("fenêtre %d (%s)" % [w.index, w.zone])
	for r in l.data.rooms:
		if String(r.id).begins_with("dehors") or String(r.id).begins_with("porte"):
			continue
		var o: Array = r.outline
		var c := Vector3((float(o[0][0]) + float(o[2][0])) * 0.5, float(r.floor), (float(o[0][1]) + float(o[2][1])) * 0.5)
		if l.zone_at(c) != "" and not nav.find_path(start, c).is_empty():
			continue
		# Milieu d'une salle occupé (pilier, marches) : un coin de la salle.
		var corner := Vector3(float(o[0][0]) + 0.6, float(r.floor), float(o[0][1]) + 0.6)
		if nav.find_path(start, corner).is_empty():
			unreachable.append("salle %s" % r.id)
	at.check(unreachable.is_empty(), "tout est accessible à pied depuis le départ : objets, fenêtres, salles (inaccessibles : %s)" % str(unreachable))

	# Étages : un zombie monte l'escalier jusqu'à la passerelle, un autre en descend.
	await reach(Vector3(12.0, 0.0, 20.0), l.box_spots()[2].pos, 30.0, "zombie monte l'escalier jusqu'à la passerelle")
	at.check(l.zone_at(p.global_position) == "e", "joueur sur la passerelle (zone %s)" % l.zone_at(p.global_position))
	await reach(l.box_spots()[2].pos, Vector3(18.0, 0.0, 16.0), 30.0, "zombie descend de la passerelle dans l'entrepôt")
	await reach(start, l.box_spots()[2].pos, 45.0, "zombie du départ rejoint la passerelle par l'atelier et l'escalier")
	await H.clear_zombies(self)
	for v in VIEWS:
		await _capture_view(v)


func _capture_view(v: Array) -> void:
	p.teleport_to(v[1], v[2])
	p.pitch = v[3]
	p.head.rotation.x = v[3]
	await seconds(0.6)
	await at.screenshot(v[0])
