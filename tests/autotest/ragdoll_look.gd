extends AutotestScenario
## @rendu : captures des chutes en ragdoll (revue humaine, ZombieRagdoll).
## @niveau perf : hors check par défaut (captures d'un ajout en cours) ;
## lancer avec SCENARIOS="ragdoll_look" JOBS=1 GUI_JOBS=1 bash tools/check.sh.
## Zombies de la vraie partie (serveur solo) tués par le vrai chemin des
## dégâts (Combat.damage_zombie -> ZombieManager.kill -> _cl_die) : balle,
## tête, fusil à pompe, couteau, piège électrique, explosion de grenade,
## TONNERRE-7, zombie tué en courant ; captures pendant la chute puis au sol.
## Vérifie : aucun corps sous le sol, ni envolé, ni qui tremble (figé au repos).
## Puis mesure : 30 zombies tués d'affilée et une explosion qui en souffle 6,
## avec ragdolls (plafond de la qualité) puis sans (plafond 0), temps d'image
## et de physique.
## Captures : tests/_out/shots/ragdoll_look_*.png.

var H := AutotestHelpers
var game: Game
var p: Player
var zm: ZombieManager
var cam: Camera3D
var pid := 1
## Origine de la mise en scène (sol dégagé devant le départ du joueur).
var _o := Vector3.ZERO


func run() -> void:
	timeout_sec = 300
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	zm = game.zombies
	pid = p.peer_id
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	# Quai du BUNKER K-7 (scène de zombie_look) : sol dégagé.
	_o = Vector3(33.5, 0.0, 4.6)
	game.hud.visible = false
	cam = Camera3D.new()
	cam.fov = 55.0
	game.add_child(cam)
	cam.make_current()
	# Joueur hors champ, derrière la caméra.
	p.teleport_to(_o + Vector3(0, 0.05, 6.0), 0.0)
	print("[ragdoll_look] plafond de ragdolls (qualité %d) : %d" % [Settings.quality, ZombieRagdoll.cap()])
	await _case("balle", [Vector3(0, 0, -2)])
	await _case("tete", [Vector3(0, 0, -2)])
	await _case("pompe", [Vector3(0, 0, -2)])
	await _case("couteau", [Vector3(0, 0, -2)])
	await _case("piege", [Vector3(0, 0, -2)])
	await _case("explosion", [Vector3(-1.2, 0, -2.5), Vector3(0.9, 0, -1.6), Vector3(0.3, 0, -3.4)], 6.0)
	await _case("tonnerre", [Vector3(-1.0, 0, -0.5), Vector3(0.8, 0, -1.5), Vector3(0, 0, -3.0)])
	await _case("course", [Vector3(0, 0, -5)], 4.5, true)
	await _perf()
	p.camera.make_current()
	cam.queue_free()


## Le coup fatal du cas `name`.
func _kill(name: String, zs: Array) -> void:
	match name:
		"balle":
			_hit(zs[0], Combat.HitKind.BULLET, "m14", false, Vector3(0, -0.1, -1))
		"tete":
			_hit(zs[0], Combat.HitKind.BULLET, "m14", true, Vector3(0, -0.1, -1))
		"pompe":
			_hit(zs[0], Combat.HitKind.BULLET, "olympia", false, Vector3(0, -0.15, -1))
		"couteau":
			_hit(zs[0], Combat.HitKind.MELEE, "", false, Vector3(0, 0, -1))
		"piege":
			_hit(zs[0], Combat.HitKind.TRAP, "", false, Vector3.UP)
		"course":
			_hit(zs[0], Combat.HitKind.BULLET, "mp40", false, Vector3(0, -0.1, -1))
		"explosion":
			var c := _o + Vector3(0, 0.2, -2.4)
			game.fx_root.explosion_light(c, Color(1.0, 0.5, 0.2))
			game.combat.explosion(pid, c, 4.0, 100000, 0)
		"tonnerre":
			var origin := _o + Vector3(0, 1.5, 2.5)
			for z: Zombie in zs:
				var v := (z.global_position - origin).normalized() * 12.0 + Vector3.UP * 4.0
				game.combat.damage_zombie(z.id, z.health, pid, false, v.normalized(), Combat.HitKind.SPECIAL, v)


## Coup fatal par Combat (serveur) avec l'arme `weapon_id`.
func _hit(z: Zombie, kind: int, weapon_id: String, head: bool, dir: Vector3) -> void:
	if not is_instance_valid(z) or not z.is_alive():
		return
	game.combat._gib_weapon = weapon_id
	game.combat.damage_zombie(z.id, z.health + 10, pid, head, dir.normalized(), kind)
	game.combat._gib_weapon = ""


func _spawn(offsets: Array, run_at := false) -> Array:
	var zs := []
	for off: Vector3 in offsets:
		var z := zm.get_zombie(zm.spawn(_o + off, 3 if run_at else 0, 100))
		z.speed_mult = 0.0
		zs.append(z)
	await H.emerged(self, zs)
	return zs


## Un cas : zombies aux décalages `offsets`, tués par `kill`, captures à
## 0,15 / 0,5 / 1,2 s puis au sol ; `side` : distance de la caméra de côté.
func _case(name: String, offsets: Array, side := 4.5, running := false) -> void:
	var zs := await _spawn(offsets, running)
	var mid := Vector3.ZERO
	for off: Vector3 in offsets:
		mid += off / offsets.size()
	var focus := _o + mid + Vector3(0, 0.6, -0.8)
	cam.look_at_from_position(focus + Vector3(side, 1.1, 1.2), focus)
	if name == "tonnerre":
		# Corps soufflés vers -Z : vue de derrière le tireur, de biais.
		cam.look_at_from_position(_o + Vector3(3.0, 2.4, 4.0), _o + Vector3(0, 0.4, -6.0))
	if running:
		# Il court vers le joueur (élan gardé à la mort).
		for z: Zombie in zs:
			z.speed_mult = 1.0
		await seconds(0.9)
		focus = zs[0].global_position + Vector3(0, 0.6, 0.6)
		cam.look_at_from_position(focus + Vector3(side, 1.1, 0.0), focus)
	await seconds(0.2)
	var floor_y := []
	for z: Zombie in zs:
		floor_y.append(z.global_position.y)
	await at.screenshot("%s_0" % name)
	_kill(name, zs)
	for t in [[0.15, "a"], [0.35, "b"], [0.7, "c"]]:
		await seconds(t[0])
		await at.screenshot("%s_%s" % [name, t[1]])
	await seconds(1.0)
	await at.screenshot("%s_sol" % name)
	for i in zs.size():
		var z: Zombie = zs[i]
		if not is_instance_valid(z):
			at.fail("%s : zombie libéré trop tôt" % name)
			continue
		at.check(not z.is_alive(), "%s : zombie %d mort" % [name, i])
		at.check(z.ragdolled or ZombieRagdoll.cap() == 0, "%s : zombie %d en ragdoll" % [name, i])
		var r := z.ragdoll
		if z.ragdolled and is_instance_valid(r) and not r.frozen:
			var lo := INF
			for pb: PhysicalBone3D in r.bodies.values():
				lo = minf(lo, pb.global_position.y)
			at.check(lo > floor_y[i] - 0.05, "%s : aucune partie sous le sol (%.2f)" % [name, lo - floor_y[i]])
		var bp := z.body_position()
		var d := Vector2(bp.x - _o.x - offsets[i].x, bp.z - _o.z - offsets[i].z).length()
		print("[ragdoll_look] %s zombie %d : bassin à %.2f m du sol, %.2f m du point de mort, figé %s" % [name, i, bp.y - floor_y[i], d, z.body_landed()])
		at.check(bp.y - floor_y[i] < 0.5 and bp.y - floor_y[i] > -0.05, "%s : corps couché au sol (%.2f)" % [name, bp.y - floor_y[i]])
		at.check(d < 22.0, "%s : corps pas envolé (%.1f m)" % [name, d])
	# Corps figés avant la dissolution (aucun tremblement au sol).
	await until(func():
		for z in zs:
			if is_instance_valid(z) and not (z as Zombie).body_landed():
				return false
		return true, ZombieRagdoll.MAX_SIM_TIME, "%s : corps figés" % name)
	await seconds(0.4)
	await at.screenshot("%s_fin" % name)
	await H.clear_zombies(self)
	await seconds(0.3)


## Coût : 30 zombies tués d'affilée puis une explosion qui en souffle 6.
func _perf() -> void:
	cam.look_at_from_position(_o + Vector3(0, 4.5, 6.0), _o + Vector3(0, 0, -2.0))
	var with := await _perf_run(-1)
	var without := await _perf_run(0)
	print("[ragdoll_look] PERF avec ragdolls (plafond %d) : %s" % [ZombieRagdoll.CAPS[Settings.quality], with])
	print("[ragdoll_look] PERF sans ragdoll : %s" % without)
	at.check(with.frame_max - without.frame_max < 25.0, "pas d'à-coup marqué (%.1f / %.1f ms)" % [with.frame_max, without.frame_max])


func _perf_run(cap: int) -> Dictionary:
	ZombieRagdoll.debug_cap = cap
	var zs := []
	for i in 36:
		@warning_ignore("integer_division")
		var off := Vector3((i % 6 - 2.5) * 1.1, 0, 1.5 - float(i / 6) * 1.2)
		var z := zm.get_zombie(zm.spawn(_o + off, 0, 100))
		z.speed_mult = 0.0
		zs.append(z)
	await H.emerged(self, zs)
	await seconds(0.5)
	var frame_sum := 0.0
	var frame_max := 0.0
	var phys_sum := 0.0
	var phys_max := 0.0
	var n := 0
	var killed := 0
	var t := 0.0
	var next_kill := 0.0
	var boom := false
	var peak_active := 0
	while t < 5.0:
		if killed < 30 and t >= next_kill:
			_hit(zs[killed], Combat.HitKind.BULLET, "m14", killed % 4 == 0, Vector3(0, -0.1, -1))
			killed += 1
			next_kill = t + 0.08
		if killed >= 30 and not boom:
			boom = true
			game.combat.explosion(pid, _o + Vector3(0, 0.2, -4.6), 3.5, 100000, 0)
		await tree().process_frame
		var dt := get_process_delta_time_ms()
		frame_sum += dt
		frame_max = maxf(frame_max, dt)
		if dt > 14.0:
			print("[ragdoll_look] image lente %.1f ms (t = %.2f s, %d tués, explosion %s, ragdolls %d)" % [dt, t, killed, boom, ZombieRagdoll.active_count()])
		var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		phys_sum += ph
		phys_max = maxf(phys_max, ph)
		peak_active = maxi(peak_active, ZombieRagdoll.active_count())
		n += 1
		t += dt / 1000.0
	await at.screenshot("perf_%s" % ("on" if cap < 0 else "off"))
	ZombieRagdoll.debug_cap = -1
	await H.clear_zombies(self)
	await seconds(0.5)
	return {"frame_avg": snappedf(frame_sum / n, 0.01), "frame_max": snappedf(frame_max, 0.01),
		"phys_avg": snappedf(phys_sum / n, 0.01), "phys_max": snappedf(phys_max, 0.01), "ragdolls_max": peak_active}


func get_process_delta_time_ms() -> float:
	return at.get_process_delta_time() * 1000.0
