extends AutotestScenario
## @niveau perf : mesure du CPU, hors check (préfixe perf_).
## Profil CPU sans rendu d'une fin de partie (manche 24) : 24 zombies en
## poursuite et 4 chiens de l'enfer gardés en vie. Deux phases par carte :
##   * « horde » : la horde au contact, le joueur (invulnérable) ne tire pas ;
##   * « combat » : le bot tire en continu (touches, démembrements, morts,
##     bonus, réapparitions) et une grenade explose toutes les 2 s.
## Sur KINO puis sur DRAFT ARENA (carte de l'éditeur, à étages).
##   godot --headless --fixed-fps 60 --path . -- --autotest=perf_cpu
##   bash tools/profile.sh     (copie instrumentée : détail par fonction)
## Sans rendu et en --fixed-fps, le jeu enchaîne les images aussi vite que
## possible : l'écart entre deux images = coût CPU complet d'une image.
## Lignes : [cpu] image complète et rappels _process / _physics_process de
## l'arbre ; [prof] (copie instrumentée seulement) ms par image et µs par
## appel de chaque fonction ; [micro] micro-mesures des fonctions chaudes.

var H := AutotestHelpers
var game: Game
var p: Player
const TARGET_ZOMBIES := 24
const TARGET_DOGS := 4
const PROF_PATH := "res://scripts/prof_tmp.gd"

var _frame_us := PackedFloat32Array()
var _proc_us := PackedFloat32Array()
var _phys_acc := 0.0
var _phys_us := PackedFloat32Array()
var _last_frame := 0
var _measuring := false
var _driving := false
var _combat := false
var _boom_t := 0.0
var _refill_t := 0.0
var _probe_first: Probe
var _probe_last: Probe
var _spots: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
## ProfTmp de la copie instrumentée (tools/profile.sh), sinon null.
var _prof: Script


class Probe extends Node:
	var sc
	var first := false
	var t_proc := 0
	var t_phys := 0

	func _process(d: float) -> void:
		if first:
			t_proc = Time.get_ticks_usec()
			sc._on_frame_start(t_proc)
		else:
			sc._on_probe_process(Time.get_ticks_usec(), d)

	func _physics_process(_d: float) -> void:
		if first:
			t_phys = Time.get_ticks_usec()
		else:
			sc._on_probe_physics(Time.get_ticks_usec())


func run() -> void:
	timeout_sec = 600
	_rng.seed = 1234
	if ResourceLoader.exists(PROF_PATH):
		_prof = load(PROF_PATH)
	for map_id in ["kino", "draft_arena"]:
		if not await _start(map_id):
			return
		await _profile(map_id)
		_driving = false
		_probe_first.queue_free()
		_probe_last.queue_free()
		Router.back_to_menu()
		await seconds(1.0)


func _start(map_id: String) -> bool:
	p = await H.start_solo_game(self, map_id)
	if p == null:
		return false
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	var sw := game.interact.get_obj("power") as PowerSwitch
	if sw:
		sw.srv_use(1)
	if game.barricades:
		for b in game.barricades.windows:
			b.srv_set_mask(0)
	var pd := game.session.local_data()
	WeaponDB.give(pd, "hk21")
	game.session.sync_inventory(1)
	# Points d'apparition à distance de poursuite du joueur.
	_spots.clear()
	var here := p.global_position
	for sp in game.spawner.points:
		var d := sp.pos.distance_to(here)
		if d > 8.0 and d < 32.0:
			_spots.append(sp.pos)
	if _spots.is_empty():
		for sp in game.spawner.points:
			_spots.append(sp.pos)
	_probe_first = _make_probe(true)
	_probe_last = _make_probe(false)
	# Quelques bonus posés au sol (modèles qui tournent).
	var kinds := [PowerupRules.MAX_AMMO, PowerupRules.DOUBLE_POINTS, PowerupRules.CARPENTER]
	for i in mini(3, _spots.size()):
		game.powerups.debug_drop(kinds[i], _spots[i] + Vector3.UP * 0.1)
	return true


func _profile(map_id: String) -> void:
	_driving = true
	_combat = false
	await seconds(6.0)  # la horde arrive
	await _phase(map_id, "horde", 4.0)
	_combat = true
	await seconds(1.0)
	await _phase(map_id, "combat", 5.0)
	_combat = false
	if map_id == "kino":
		await _micro()


func _phase(map_id: String, label: String, dur: float) -> void:
	if _prof:
		_prof.reset()
	var r := await _measure(dur)
	var near := 0
	for z: Zombie in game.zombies.alive:
		if z.global_position.distance_to(p.global_position) < 6.0:
			near += 1
	print("[cpu] %s %s : image %.2f ms (max %.1f), _process %.2f ms, _physics_process %.2f ms, reste (moteur : physique, scène, audio) %.2f ms | %d zombies dont %d à moins de 6 m, nœuds %d" % [
		map_id, label, r.frame, r.frame_max, r.proc, r.phys, r.frame - r.proc - r.phys,
		game.zombies.alive_count(), near, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	if _prof == null:
		return
	var n: int = maxi(r.frames, 1)
	var rows := []
	for k in _prof.acc:
		rows.append([float(_prof.acc[k]) / n / 1000.0, String(k), int(_prof.calls[k])])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for row in rows.slice(0, 45):
		print("[prof] %s %-7s %-42s %7.3f ms/image %7.1f appels/image %8.2f µs/appel" % [
			map_id, label, row[1], row[0], float(row[2]) / n, row[0] * 1000.0 * n / maxf(row[2], 1)])


# --------------------------------------------------------------------------
# Charge
# --------------------------------------------------------------------------

func _drive(delta: float) -> void:
	if not _driving or game == null or not is_instance_valid(p):
		return
	var zombies := 0
	var dogs := 0
	for z: Zombie in game.zombies.alive:
		if z is Hellhound:
			dogs += 1
		else:
			zombies += 1
	if zombies < TARGET_ZOMBIES:
		game.zombies.spawn(_spots[_rng.randi() % _spots.size()], _rng.randi_range(1, 3), RoundRules.zombie_health(24))
	elif dogs < TARGET_DOGS:
		game.zombies.spawn(_spots[_rng.randi() % _spots.size()] + Vector3(0.5, 0, 0.5), 3, 1600, ZombieManager.KIND_DOG)
	if not _combat:
		p.input.fire = false
		return
	# Bot : vise le zombie le plus proche sorti du sol, tire en continu.
	var best: Zombie = null
	var best_d := 30.0
	for z: Zombie in game.zombies.alive:
		if z.state == Zombie.State.EMERGE:
			continue
		var d := z.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = z
	if best:
		H.aim_at(p, best.global_position + Vector3.UP * (0.9 if best.is_crawler() else 1.3))
		p.input.fire = true
	else:
		p.input.fire = false
	_refill_t += delta
	if _refill_t > 1.0:
		_refill_t = 0.0
		var pd := game.session.local_data()
		WeaponDB.refill(pd, pd.slot)
		game.session.sync_inventory(1)
	_boom_t += delta
	if _boom_t > 2.0 and best:
		_boom_t = 0.0
		var c := best.global_position
		game.combat.explosion(1, c, 4.0, 400, 0)
		game.throwables.explosion_fx(c, ThrowableRules.Kind.FRAG)


# --------------------------------------------------------------------------
# Mesures
# --------------------------------------------------------------------------

func _on_frame_start(t: int) -> void:
	if _measuring and _last_frame > 0:
		_frame_us.append(t - _last_frame)
		_phys_us.append(_phys_acc)
	_phys_acc = 0.0
	_last_frame = t


func _on_probe_process(t_end: int, d: float) -> void:
	if _measuring:
		_proc_us.append(t_end - _probe_first.t_proc)
	_drive(d)


func _on_probe_physics(t_end: int) -> void:
	_phys_acc += t_end - _probe_first.t_phys


func _measure(dur: float) -> Dictionary:
	_frame_us.clear()
	_proc_us.clear()
	_phys_us.clear()
	_last_frame = 0
	_measuring = true
	await seconds(dur)
	_measuring = false
	return {"frame": _mean(_frame_us) / 1000.0, "frame_max": _max(_frame_us) / 1000.0,
		"proc": _mean(_proc_us) / 1000.0, "phys": _mean(_phys_us) / 1000.0, "frames": _proc_us.size()}


static func _mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m


func _make_probe(first: bool) -> Probe:
	var pr := Probe.new()
	pr.sc = self
	pr.first = first
	pr.process_mode = Node.PROCESS_MODE_ALWAYS
	pr.process_priority = -1000000 if first else 1000000
	pr.process_physics_priority = -1000000 if first else 1000000
	tree().root.add_child(pr)
	return pr


## µs par appel de `f`, appelée `n` fois.
func _bench(label: String, n: int, f: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		f.call(i)
	var us := float(Time.get_ticks_usec() - t0) / n
	print("[micro] %-44s %8.2f µs/appel" % [label, us])


func _micro() -> void:
	_driving = false
	p.input.fire = false
	await frames(2)
	var alive: Array[Zombie] = []
	for z: Zombie in game.zombies.alive:
		if not (z is Hellhound) and z.crawl_t < 0.0 and z.anim:
			alive.append(z)
	if alive.is_empty():
		print("[micro] aucun zombie")
		return
	var z := alive[0]
	var saved_state := z.state
	var saved_attack := z.attack_t
	_bench("(appel vide, référence)", 5000, func(_i): pass)
	_bench("ZombieAnim.pose (marche)", 2000, func(_i): z.anim.pose(1.0 / 60.0))
	_bench("ZombieAnim.pose (attaque)", 2000, func(_i):
		z.attack_t = 0.3
		z.anim.pose(1.0 / 60.0))
	z.state = Zombie.State.EMERGE
	_bench("ZombieAnim.pose (émergence)", 2000, func(_i):
		z.attack_t = -1.0
		z.anim.pose(1.0 / 60.0))
	z.state = saved_state
	z.attack_t = saved_attack
	# Table de clés : littérale (allouée à chaque appel) contre constante.
	_bench("ZombieAnim._keys (table littérale)", 5000, func(i): ZombieAnim._keys(float(i % 100) / 100.0, [[0.0, -1.3], [0.28, -2.45], [0.5, -0.85], [0.7, -1.0], [1.0, -1.2]]))
	_bench("ZombieAnim._keys (table constante)", 5000, func(i): ZombieAnim._keys(float(i % 100) / 100.0, ZombieAnim.K_ATTACK_ARM_R))
	_bench("ZombieAnim.death", 2000, func(_i): z.anim.death(1.0 / 60.0, 0.3, 1.0))
	_bench("ZombieGibs.crawl_pose", 2000, func(_i): ZombieGibs.crawl_pose(z, 1.0 / 60.0))
	_bench("ZombieGibs.limb_at", 1000, func(_i): ZombieGibs.limb_at(z, z.global_position + Vector3.UP))
	_bench("Zombie.separation", 2000, func(i): alive[i % alive.size()].separation())
	_bench("ZombieManager.pose_step", 5000, func(i): game.zombies.pose_step(alive[i % alive.size()].global_position))
	var tgt := p.global_position
	# Déplacement du joueur (move_and_slide) : ce qui l'entoure.
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 2.4
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, tgt + Vector3.UP * 1.0)
	q.collision_mask = p.collision_mask
	var around := p.get_world_3d().direct_space_state.intersect_shape(q, 256)
	var kinds := {}
	for h in around:
		var col: Object = h.collider
		var key := col.get_class()
		if col is CollisionObject3D:
			var sh: Shape3D = (col as CollisionObject3D).shape_owner_get_shape((col as CollisionObject3D).shape_find_owner(int(h.shape)), 0)
			key += "/" + (sh.get_class() if sh else "?")
			if sh is ConcavePolygonShape3D:
				key += "(%d tri)" % ((sh as ConcavePolygonShape3D).get_faces().size() / 3)
			elif sh is ConvexPolygonShape3D:
				key += "(%d points, %s)" % [(sh as ConvexPolygonShape3D).points.size(), (col as Node).get_path()]
		kinds[key] = int(kinds.get(key, 0)) + 1
	print("[micro] autour du joueur (masque %d) : %s" % [p.collision_mask, kinds])
	# Formes convexes lourdes de la carte (coût de move_and_slide au contact).
	var heavy := []
	for cs in game.world.find_children("*", "CollisionShape3D", true, false):
		var sh := (cs as CollisionShape3D).shape
		if sh is ConvexPolygonShape3D and (sh as ConvexPolygonShape3D).points.size() > 24:
			heavy.append("%s (%d points)" % [game.world.get_path_to(cs), (sh as ConvexPolygonShape3D).points.size()])
	print("[micro] formes convexes de plus de 24 points : %d %s" % [heavy.size(), heavy.slice(0, 8)])
	var vel0 := p.velocity
	_bench("Player.move_and_slide (horde autour)", 200, func(_i):
		p.velocity = vel0
		p.move_and_slide())
	var saved_mask := p.collision_mask
	p.collision_mask = 1
	_bench("Player.move_and_slide (décor seul)", 200, func(_i):
		p.velocity = vel0
		p.move_and_slide())
	p.collision_mask = saved_mask
	# Même mesure sans les formes convexes voisines (socle du téléporteur...).
	var off: Array[CollisionShape3D] = []
	for h in around:
		if h.collider is StaticBody3D:
			for c in (h.collider as Node).get_children():
				if c is CollisionShape3D and (c as CollisionShape3D).shape is ConvexPolygonShape3D and not c.disabled:
					c.disabled = true
					off.append(c)
	if not off.is_empty():
		await frames(3)
		_bench("Player.move_and_slide (sans convexes voisines)", 200, func(_i):
			p.velocity = vel0
			p.move_and_slide())
		for c in off:
			c.disabled = false
		await frames(3)
	_bench("nav.world_line_clear", 2000, func(i): game.nav.world_line_clear(alive[i % alive.size()].global_position, tgt))
	_bench("nav.find_path (zombie -> joueur)", 200, func(i): game.nav.find_path(alive[i % alive.size()].global_position, tgt))
	_bench("Spawner.pick_spawn_point", 200, func(_i): game.spawner.pick_spawn_point())
	_bench("Spawner.recycle", 200, func(_i): game.spawner.recycle(0.0))
	var snap := PackedByteArray()
	_bench("ZombieManager.build_snapshot", 500, func(_i): snap = game.zombies.build_snapshot())
	var states := game.zombies.net_q.duplicate(true)
	_bench("NetCodec.decode_zombie_snapshot", 500, func(_i): NetCodec.decode_zombie_snapshot(snap, states))
	_bench("ZombieShadows.update", 500, func(_i): ZombieShadows.update(game.zombies.alive, p.camera.global_position, RenderQuality.current()))
	var fx: Fx = game.fx_root
	_bench("Fx.blood_hit", 500, func(_i): fx.blood_hit(tgt + Vector3(0, 1, -3), Vector3.UP, 1.6))
	_bench("Fx.impact (balle, béton)", 500, func(_i): fx.impact(tgt + Vector3(0, 1, -3), Vector3.UP, false))
	_bench("ThrowableSystem.explosion_fx", 50, func(_i): game.throwables.explosion_fx(tgt + Vector3(0, 0, -6), ThrowableRules.Kind.FRAG))
	_bench("ParticlePool.emit (seul)", 2000, func(_i): fx.dust.emit(tgt + Vector3(0, 1, -3), Vector3.UP, 0.5, Color.WHITE))
	# Gerbe de 12 : un sol pour toute la gerbe, contre un par particule.
	_bench("ParticlePool.burst (12)", 500, func(_i): fx.blood.burst(tgt + Vector3(0, 1, -3), Vector3.UP, 12, 3.0, 0.8, 0.7, Color.RED))
	_bench("ParticlePool.emit x12 (un sol chacune)", 500, func(_i):
		for k in 12:
			fx.blood.emit(tgt + Vector3(0, 1, -3), Vector3.UP, 0.7, Color.RED))
	_bench("GibPool.spawn_limb", 50, func(_i): fx.gibs.spawn_limb(z.variant, ["forearm_l"], z.skel.global_transform, Vector3.UP, Vector3.ONE))
	_bench("Audio.play_3d", 500, func(i): Audio.play_3d("zombie_step_%d" % (1 + i % 3), tgt + Vector3(0, 0, -4), -9.0, 0.1, 6))
	# Premier son d'un nom encore jamais joué (chargement du fichier).
	var cold: Array[String] = []
	for f in DirAccess.get_files_at(Audio.DIR):
		if f.ends_with(".wav") and not Audio._cache.has(f.get_basename()) and cold.size() < 20:
			cold.append(f.get_basename())
	if not cold.is_empty():
		_bench("Audio.get_stream (1er appel, %d sons)" % cold.size(), cold.size(), func(i): Audio.get_stream(cold[i]))
	print("[micro] sons en cache après la partie : %d sur %d" % [Audio._cache.size(), DirAccess.get_files_at(Audio.DIR).size() / 2])
	_bench("ZombieModel.build (apparition)", 10, func(i): ZombieModel.build(4000 + i).free())
	# Démembrement (jambes, zombie qui devient rampant) : appels un par un.
	var worst := 0
	var total := 0
	var nz := mini(alive.size(), 6)
	for i in nz:
		var t0 := Time.get_ticks_usec()
		ZombieGibs.apply(alive[i], ZombieGibs.LEGS | ZombieGibs.ARM_L, Vector3.FORWARD, false)
		var dt := Time.get_ticks_usec() - t0
		worst = maxi(worst, dt)
		total += dt
	print("[micro] %-44s %8.2f µs/appel (pire %d µs)" % ["ZombieGibs.apply (jambes + bras)", float(total) / maxi(nz, 1), worst])
	# Grenade au milieu de la horde (dégâts, démembrements, morts, effets).
	var c := Vector3.ZERO
	for zz in alive:
		c += zz.global_position
	c /= alive.size()
	var before := game.zombies.alive_count()
	var tb := Time.get_ticks_usec()
	game.combat.explosion(1, c, 4.0, 100000, 0)
	game.throwables.explosion_fx(c, ThrowableRules.Kind.FRAG)
	print("[micro] %-44s %8.2f µs (%d zombies tués)" % ["grenade dans la horde (Combat.explosion + effets)", float(Time.get_ticks_usec() - tb), before - game.zombies.alive_count()])
	await frames(10)
