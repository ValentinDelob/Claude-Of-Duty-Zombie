extends AutotestScenario
## @carte kino
## KINO : portes payantes en haut d'escaliers raides (« 3 », escalier de la
## ruelle ; « 5 », cage des coulisses). Sur les marches, à 2 m de la porte,
## le joueur est ~1,45 m plus bas que son sol : l'invite ne s'affichait pas
## (InteractionSystem.LEVEL_HEIGHT = 1,2 m seul). Vérifie l'invite et l'achat
## (serveur) depuis les marches.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	var p: Player = await H.start_solo_game(self, "kino")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	game.session.add_points(p.peer_id, 20000)
	for id in ["3", "5"]:
		await check_door(p, id)


func check_door(p: Player, id: String) -> void:
	var game := Game.instance
	var door: Door = game.doors.get(id)
	at.check(door != null and not door.is_open, "porte %s fermée" % id)
	if door == null or door.is_open:
		return
	var spot := stair_spot(door)
	at.check(spot != Vector3.INF, "porte %s : place sur les marches, 2 m avant elle et plus de 1,2 m plus bas" % id)
	if spot == Vector3.INF:
		return
	p.teleport_to(spot + Vector3.UP * 0.05)
	await seconds(0.4)
	H.aim_at(p, door.interact_point())
	await frames(4)
	var dy := door.level_y() - p.global_position.y
	at.check(dy > InteractionSystem.LEVEL_HEIGHT, "porte %s : joueur %.2f m plus bas sur les marches" % [id, dy])
	var eye := p.eye_position()
	var ip := door.interact_point()
	var flat := Vector2(ip.x - eye.x, ip.z - eye.z).length()
	var stop := eye + (ip - eye) * ((eye.distance_to(ip) - InteractionSystem.STAIR_SIGHT_STOP) / eye.distance_to(ip))
	var hit := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, stop, 1, door.own_rids()))
	if not hit.is_empty():
		print("[kino_stair_doors] porte %s : œil %s, point %s, rayon arrêté en %s par %s" % [id, eye, ip, hit.position, (hit.collider as Node).get_path()])
	at.check(game.interact.focused == door, "porte %s : invite depuis les marches (vise %s ; à plat %.2f m, écart permis %.2f m, distance %.2f m, vue %s)" % [id,
		game.interact.focused.interact_id if game.interact.focused else "rien", flat, InteractionSystem.level_gap(flat), eye.distance_to(ip),
		InteractionSystem.stair_sight_ok(door, p.global_position.y, eye, ip)])
	var pd := game.session.local_data()
	var before := pd.points
	game.interact.srv_interact.rpc_id(1, door.interact_id)
	await until(func(): return door.is_open, 2.0, "porte %s achetée depuis les marches" % id)
	at.check(pd.points < before, "porte %s payée" % id)


## Point sur l'axe de l'escalier qui monte à `door` (bout haut le plus proche
## d'elle), à ~2 m à plat de son point d'interaction et plus de LEVEL_HEIGHT
## plus bas que son sol ; posé sur la marche (rayon vers le bas). INF : aucun.
func stair_spot(door: Door) -> Vector3:
	var layout := Game.instance.layout as MeshMapLayout
	var ip := door.interact_point()
	var best := Vector3.INF
	var best_err := INF
	var space := door.get_world_3d().direct_space_state
	for st: Dictionary in layout.data.stairs:
		var a := MeshMapLayout.vec(st.a)
		var b := MeshMapLayout.vec(st.b)
		var top := b if b.y > a.y else a
		var low := a if b.y > a.y else b
		if Vector2(top.x - ip.x, top.z - ip.z).length() > 4.0 or absf(top.y - door.level_y()) > 0.5:
			continue
		for i in 101:
			var q := low.lerp(top, i / 100.0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 1.0, q + Vector3.DOWN * 1.5, 1))
			if hit.is_empty():
				continue
			var f: Vector3 = hit.position
			var flat := Vector2(f.x - ip.x, f.z - ip.z).length()
			if door.level_y() - f.y <= InteractionSystem.LEVEL_HEIGHT + 0.2:
				continue
			var err := absf(flat - 2.0)
			if err < best_err and err < 0.3:
				best_err = err
				best = f
	return best
