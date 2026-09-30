extends AutotestScenario
## Zombies : apparition (émergence), poursuite du joueur, rendu, perf à 24.

func run() -> void:
	var p: Player = await AutotestHelpers.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	var zm := game.zombies
	game.combat.debug_invulnerable = true
	p.teleport_to(MapData.cell_to_world(Vector2i(12, 3), 0.05), 0.0)
	await until(func(): return zm.zombies.size() > 0, 12.0, "premier zombie")
	var z: Zombie = zm.zombies.values()[0]
	at.check(z.state == Zombie.State.EMERGE, "le zombie émerge du sol")
	await seconds(Zombie.EMERGE_TIME + 0.3)
	at.check(z.state == Zombie.State.CHASE, "puis poursuit")
	var d0 := z.global_position.distance_to(p.global_position)
	await seconds(1.5)
	var d1 := z.global_position.distance_to(p.global_position)
	at.check(d1 < d0 - 0.5, "se rapproche du joueur (%.1f -> %.1f m)" % [d0, d1])

	# Vue sur les zombies qui arrivent.
	p.teleport_to(MapData.cell_to_world(Vector2i(12, 8), 0.05), 0.0)
	for zz in zm.zombies.values():
		zz.global_position = p.global_position + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-6, -4))
	await seconds(0.6)
	p.yaw = 0.0
	p.pitch = deg_to_rad(-4)
	await seconds(0.5)
	await at.screenshot("approach")

	# Stress : 24 zombies simultanés.
	var missing := 24 - zm.alive_count()
	for i in missing:
		@warning_ignore("integer_division")
		zm.spawn(MapData.cell_to_world(Vector2i(3 + i % 20, 1 + (i / 20) * 12), 0.0), i % 4, 150)
	await seconds(Zombie.EMERGE_TIME + 1.0)
	at.check(zm.alive_count() >= 24, "%d zombies actifs" % zm.alive_count())
	p.teleport_to(MapData.cell_to_world(Vector2i(12, 14), 0.05), PI)
	await seconds(0.3)
	at.begin_perf()
	await seconds(3.0)
	var fps: float = at.end_perf("24 zombies")
	at.check_perf(fps, 150.0, "24 zombies")
	p.yaw = 0.0
	await seconds(0.2)
	await at.screenshot("horde")

	# Identifiants recyclés (après 65000) : jamais celui d'un zombie présent.
	game.rounds.paused = true
	var old: Zombie = zm.zombies.values()[0]
	var hp := old.health
	zm._next_id = old.id
	var nid := zm.spawn(p.global_position + Vector3(3, 0, 3), 0, 777)
	at.check(nid != old.id and zm.get_zombie(nid) != null and zm.get_zombie(nid).health == 777 and old.health == hp,
		"identifiant occupé sauté (%d -> %d), PV du zombie existant intacts" % [old.id, nid])
