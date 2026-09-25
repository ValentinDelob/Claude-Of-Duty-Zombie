extends AutotestScenario
## Visite du BUNKER K-7 : chaque zone, perf, portes fermées infranchissables,
## zombies uniquement dans la zone de départ.

var H := AutotestHelpers
## [nom, cellule, cellule visée]
const VIEWS := [
	["garde", Vector2i(9, 29), Vector2i(9, 17)],
	["dortoir", Vector2i(15, 13), Vector2i(3, 3)],
	["couloir", Vector2i(20, 23), Vector2i(32, 24)],
	["labo", Vector2i(35, 31), Vector2i(52, 18)],
	["generateur", Vector2i(55, 22), Vector2i(61, 28)],
	["quai", Vector2i(20, 9), Vector2i(46, 4)],
	["rituel", Vector2i(53, 8), Vector2i(57, 3)],
]


func run() -> void:
	timeout_sec = 120
	var p: Player = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	var game := Game.instance
	game.combat.debug_invulnerable = true
	at.check(game.map_def.id == "bunker_k7", "carte BUNKER K-7 chargée")
	at.check(game.doors.size() == 6, "6 portes (%d)" % game.doors.size())
	at.check(game.map_data.markers.get("P", []).size() == 4, "4 points d'apparition joueurs")

	# Porte fermée : on fonce dans la porte 2 (salle de garde -> couloir).
	p.teleport_to(MapData.cell_to_world(Vector2i(15, 23), 0.05), -PI * 0.5)
	p.input.move = Vector2(0, 1)
	await seconds(1.5)
	p.input.move = Vector2.ZERO
	at.check(p.global_position.x < 18.0, "la porte fermée bloque le joueur (x=%.2f)" % p.global_position.x)

	# Les zombies n'apparaissent que dans la zone de départ.
	await until(func(): return game.zombies.alive_count() >= 2, 14.0, "zombies de la manche 1")
	var ok_zone := true
	for z: Zombie in game.zombies.alive:
		if game.map_data.zone_at(MapData.world_to_cell(z.global_position)) != "a":
			ok_zone = false
	at.check(ok_zone, "zombies apparus dans la salle de garde uniquement")
	game.rounds.paused = true
	await H.clear_zombies(self)

	var worst := 10000.0
	for v in VIEWS:
		p.teleport_to(MapData.cell_to_world(v[1], 0.05))
		H.aim_at(p, MapData.cell_to_world(v[2], 1.2))
		await seconds(0.6)
		at.begin_perf()
		await seconds(1.0)
		worst = minf(worst, at.end_perf(v[0]))
		await at.screenshot(v[0])
	at.check_perf(worst, 150.0, "pire vue de la carte")
