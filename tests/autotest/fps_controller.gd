extends AutotestScenario
## Contrôleur FPS : marche, sprint, saut, accroupi, visée, collisions murales.

func run() -> void:
	var p: Player = await AutotestHelpers.start_solo_game(self)
	if p == null:
		return
	at.check(GameState.state == GameState.State.PLAYING, "état PLAYING")
	await at.screenshot("spawn")

	# Marche avant 1 s dans une allée dégagée (rangée 7, vers +X).
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 7), 0.05), -PI * 0.5)
	await frames(3)
	var start := p.global_position
	p.input.move = Vector2(0, 1)
	await seconds(1.0)
	var walked := p.global_position.distance_to(start)
	at.check(walked > 3.0 and walked < 5.0, "marche ~4.4 m/s (%.2f m en 1 s)" % walked)

	# Sprint.
	start = p.global_position
	p.input.sprint = true
	await seconds(0.5)
	var sprint_speed := Vector2(p.velocity.x, p.velocity.z).length()
	at.check(p.sprinting and sprint_speed > 6.0, "sprint (%.2f m/s)" % sprint_speed)
	p.input.sprint = false
	p.input.move = Vector2.ZERO
	await seconds(0.4)
	at.check(Vector2(p.velocity.x, p.velocity.z).length() < 0.2, "arrêt après relâchement")

	# Saut.
	var ground_y := p.global_position.y
	p.input.jump = true
	await seconds(0.25)
	at.check(p.global_position.y > ground_y + 0.4, "saut (+%.2f m)" % (p.global_position.y - ground_y))
	await until(func(): return p.is_on_floor(), 3.0, "retombée au sol après le saut")
	at.check(p.is_on_floor(), "retombe au sol")

	# Accroupi.
	p.input.crouch = true
	await seconds(0.4)
	at.check(p.head.position.y < 1.2, "accroupi (yeux à %.2f m)" % p.head.position.y)
	p.input.crouch = false
	await seconds(0.4)
	at.check(p.head.position.y > 1.5, "debout")

	# Regard souris.
	var yaw0 := p.yaw
	p.input.look = Vector2(200, 0)
	await seconds(0.1)
	at.check(absf(p.yaw - yaw0) > 0.2, "rotation horizontale")
	p.input.look = Vector2(0, -100000)
	await seconds(0.1)
	at.check(p.pitch <= Player.PITCH_LIMIT + 0.001, "tangage limité")
	p.pitch = 0.0

	# Visée : réduit le FOV.
	p.input.aim = true
	await seconds(0.4)
	var ads_zoom: float = WeaponDB.stats(Game.instance.session.local_data().current_weapon().id).get("ads_zoom", 1.0)
	at.check(p.camera.fov < Settings.fov * 0.95 and absf(p.camera.fov - Settings.fov * ads_zoom) < 2.0, "visée : FOV réduit selon l'arme (%.0f)" % p.camera.fov)
	p.input.aim = false

	# Collision : on fonce dans un mur pendant 3 s, on doit rester dans la carte.
	p.yaw = -PI * 0.5
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await seconds(3.0)
	var pos := p.global_position
	var w := Game.instance.map_data.width
	at.check(pos.x > 1.0 and pos.x < w - 1.0 and pos.z > 1.0, "bloqué par les murs (%.1f, %.1f)" % [pos.x, pos.z])
	p.input.move = Vector2.ZERO
	p.input.sprint = false

	# Vue d'ensemble + perf.
	p.teleport_to(Vector3(3, 0.05, 2.5), deg_to_rad(-135))
	p.pitch = deg_to_rad(-8)
	await seconds(0.3)
	at.begin_perf()
	await seconds(2.0)
	var fps: float = at.end_perf("arène")
	at.check_perf(fps, 150.0, "arène")
	await at.screenshot("overview")
