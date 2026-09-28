extends AutotestScenario
## Carte en maillage à plusieurs niveaux (test_levels) : le joueur monte
## l'escalier, les zombies le suivent sur la mezzanine et dans la salle en
## pente en restant au sol, une porte fermée coupe le chemin jusqu'à son
## achat, les zones et les objets muraux sont à leur place.

var game: Game
var p: Player


func clear_zombies() -> void:
	for zid in game.zombies.zombies.keys():
		game.zombies.despawn(zid)
	await frames(2)


## Un zombie apparu en `from` rejoint le joueur placé en `to`, en restant
## toujours près du sol (jamais dans le vide ni sous le plancher).
func reach_test(to: Vector3, from: Vector3, limit: float, label: String) -> Zombie:
	await clear_zombies()
	p.teleport_to(to + Vector3.UP * 0.05)
	await seconds(0.3)
	var zid := game.zombies.spawn(from, 2, 150)
	var z := game.zombies.get_zombie(zid)
	var t0 := Time.get_ticks_msec()
	var worst := [0.0]
	var ok: bool = await until(func():
		var g := game.layout.ground(z.global_position)
		worst[0] = maxf(worst[0], absf(g.y - z.global_position.y))
		return z.global_position.distance_to(p.global_position) < 1.8, limit, label)
	if ok:
		at.check(true, "%s (%.1f s)" % [label, (Time.get_ticks_msec() - t0) / 1000.0])
	at.check(worst[0] < 0.35, "%s : zombie au sol tout du long (écart max %.2f m)" % [label, worst[0]])
	return z


func run() -> void:
	timeout_sec = 120
	p = await AutotestHelpers.start_solo_game(self, "test_levels")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await clear_zombies()
	var layout := game.layout
	at.check(layout is MeshMapLayout and layout.is_multilevel(), "carte en maillage à plusieurs niveaux")
	at.check(p.global_position.distance_to(Vector3(13, 0.05, 20)) < 1.5, "joueur apparu au rez-de-chaussée")

	# Zones par position (étages compris).
	at.check(layout.zone_at(Vector3(15, 0, 18)) == "a", "zone du rez-de-chaussée")
	at.check(layout.zone_at(Vector3(15, 3, 12)) == "b", "zone de la mezzanine (au-dessus du rez-de-chaussée)")
	at.check(layout.zone_at(Vector3(15, 0, 12)) == "a", "sous la mezzanine : rez-de-chaussée")
	at.check(layout.zone_at(Vector3(26, 0, 16)) == "c", "zone de la salle est")
	at.check(layout.zone_at(Vector3(16, -1.0, 29)) == "d", "zone de la salle en pente")
	at.check(game.spawner.active_zones.has("b") and game.spawner.active_zones.has("d") and not game.spawner.active_zones.has("c"), "zones ouvertes au départ : a, b, d (%s)" % str(game.spawner.active_zones.keys()))

	# Le joueur monte l'escalier (vraie collision : rampe).
	p.teleport_to(Vector3(11.2, 0.05, 20.8), 0.0)
	await seconds(0.2)
	p.input.move = Vector2(0, 1)
	await until(func(): return p.global_position.z < 13.5, 6.0, "joueur en haut de l'escalier")
	p.input.move = Vector2.ZERO
	await seconds(0.3)
	at.check(p.global_position.y > 2.8 and p.global_position.y < 3.3, "joueur sur la mezzanine (y = %.2f)" % p.global_position.y)
	await at.screenshot("mezzanine")

	# Zombies : jusqu'à la mezzanine par l'escalier, dans la salle en pente.
	await reach_test(Vector3(18, 3.0, 12), Vector3(15, 0, 19), 20.0, "zombie monte l'escalier jusqu'à la mezzanine")
	await reach_test(Vector3(15, 0, 19), Vector3(18, 3.0, 11), 20.0, "zombie descend de la mezzanine")
	var zd := await reach_test(layout.ground(Vector3(16, 0, 30)), Vector3(15, 0, 17), 20.0, "zombie descend la salle en pente")
	at.check(zd.global_position.y < -0.5, "zombie en bas de la pente (y = %.2f)" % zd.global_position.y)

	# Porte fermée : aucun chemin vers la salle est tant qu'elle n'est pas achetée.
	await clear_zombies()
	var nav := game.nav
	at.check(nav.find_path(Vector3(15, 0, 16), Vector3(26, 0, 16)).is_empty(), "porte fermée : pas de chemin vers la salle est")
	var door: Door = game.doors.get("1")
	at.check(door != null and door.zones.size() == 2, "porte 1 entre deux zones")
	door.srv_open()
	await seconds(0.3)
	at.check(not nav.find_path(Vector3(15, 0, 16), Vector3(26, 0, 16)).is_empty(), "porte ouverte : chemin vers la salle est")
	at.check(game.spawner.active_zones.has("c"), "salle est active après l'ouverture")
	await reach_test(Vector3(26, 0, 16), Vector3(12, 0, 18), 20.0, "zombie passe la porte ouverte")

	# Distributeur d'atout plein : le joueur bute dessus au lieu de le traverser.
	await clear_zombies()
	p.teleport_to(Vector3(26, 0.05, 13.5), 0.0)
	await seconds(0.2)
	p.input.move = Vector2(0, 1)
	await seconds(1.5)
	p.input.move = Vector2.ZERO
	at.check(p.global_position.z > 11.2, "le joueur ne traverse pas le distributeur (z = %.2f, face avant à 10,98)" % p.global_position.z)

	# Objets muraux à leur place et fenêtre barricadée.
	var wb: WallBuy = game.interact.get_obj("wallbuy_R")
	at.check(wb != null and absf(wb.global_position.x - 10.17) < 0.05 and absf(wb.global_position.y - 1.45) < 0.05, "achat mural plaqué au mur ouest")
	at.check(game.barricades.windows.size() == 1, "une fenêtre barricadée")
	var w: Barricade = game.barricades.windows[0]
	at.check(w.zone == "c" and w.opening_height > 2.3, "fenêtre de la salle est (hauteur %.1f m)" % w.opening_height)
	var zw_id := game.zombies.spawn(Vector3(31.8, 0, 16), 2, 150)
	var zw := game.zombies.get_zombie(zw_id)
	await frames(2)
	at.check(zw.barricade == w, "zombie apparu dehors rattaché à sa fenêtre")
	await at.screenshot("salle_pente")
