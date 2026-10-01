extends AutotestScenario
## @carte kino
## @couvre tools/blender/kino/make_layout.py
## KINO : haut des escaliers qui arrivent contre un mur (ruelle -> salle basse,
## escalier du Foyer -> salle des portraits...). Trouvé par le soak : l'ouverture
## du mur descendait 0,5 m sous le palier et les marches s'arrêtaient avant le
## mur ; la fente, plus étroite que la capsule, faisait retomber le rayon de sol
## du zombie à chaque pas : marcheurs et coureurs restaient coincés contre le
## bord du palier. Vérifie le profil du sol en haut de chaque escalier (aucune
## marche de plus de 0,3 m) puis des zombies qui montent et descendent.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 240
	var p: Player = await H.start_solo_game(self, "kino")
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	for id in game.doors:
		game.doors[id].srv_open()
	await H.clear_zombies(self)
	check_stair_tops(p)
	# Ruelle (zone c) -> salle basse (zone b) par l'escalier et la porte 3.
	await reach(p, Vector3(50.0, 2.1, 88.0), [Vector3(34.0, 0.0, 81.7), Vector3(35.0, 0.0, 70.0)], "monté de la ruelle", 25.0)
	await reach(p, Vector3(34.0, 0.1, 75.0), [Vector3(43.0, 2.1, 82.0)], "descendu dans la ruelle", 25.0)
	# Foyer (zone f) -> salle des portraits (zone e) par l'escalier du Foyer.
	await reach(p, Vector3(108.0, 8.2, 90.0), [Vector3(110.8, 4.1, 73.5), Vector3(112.0, 4.1, 74.0)], "monté dans la salle des portraits", 25.0)
	await reach(p, Vector3(110.8, 4.1, 66.0), [Vector3(110.0, 8.2, 85.0)], "descendu vers le Foyer", 35.0)


## Profil du sol (rayon vers le bas, couche du décor) de 0,5 m sous le haut des
## marches à 1 m au-delà, au centre et à ±40 % de la largeur.
func check_stair_tops(p: Player) -> void:
	var space := p.get_world_3d().direct_space_state
	var layout := Game.instance.layout as MeshMapLayout
	for st: Dictionary in layout.data.stairs:
		var a := MeshMapLayout.vec(st.a)
		var b := MeshMapLayout.vec(st.b)
		var ax := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := Vector3(-ax.z, 0, ax.x)
		var worst := 0.0
		var where := Vector3.ZERO
		for off: float in [-0.4, 0.0, 0.4]:
			var s: Vector3 = b - ax * 0.5 + side * off * float(st.w)
			var prev := NAN
			for i in 38:
				var q: Vector3 = s + ax * (i * 0.04)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q.x, b.y + 1.2, q.z), Vector3(q.x, b.y - 2.0, q.z), 1))
				var y: float = hit.position.y if not hit.is_empty() else b.y - 2.0
				if not is_nan(prev) and absf(y - prev) > worst:
					worst = absf(y - prev)
					where = Vector3(q.x, y, q.z)
				prev = y
		at.check(worst <= 0.3, "haut de l'escalier %s %s : plus grande marche %.2f m (en %s)" % [st.room, st.b, worst, where])


func reach(p: Player, stand: Vector3, starts: Array, what: String, limit: float) -> void:
	var game := Game.instance
	p.teleport_to(stand)
	await seconds(0.5)
	for sp: int in [RoundRules.WALK, RoundRules.SPRINT]:
		for start: Vector3 in starts:
			var z := game.zombies.get_zombie(game.zombies.spawn(start, sp, 100000))
			await H.emerged(self, [z])
			var t0 := GameClock.now()
			var ok: bool = await until(func(): return z.global_position.distance_to(p.global_position) < 2.5, limit, "zombie %s (%s, vitesse %d)" % [what, start, sp])
			if ok:
				at.check(true, "zombie %s (%s, vitesse %d) en %.1f s" % [what, start, sp, GameClock.now() - t0])
			await H.clear_zombies(self)
