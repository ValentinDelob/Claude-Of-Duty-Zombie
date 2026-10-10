extends TestCase
## Optimisations CPU (docs/REFACTORING_PLAN.md §5, R2 à R9) : chaque fonction
## réécrite donne EXACTEMENT le résultat de l'ancienne logique (recopiée ici
## comme référence) sur des entrées tirées au hasard.


# --------------------------------------------------------------------------
# Monde physique de test : sol, marches et murs (couche 1)
# --------------------------------------------------------------------------

func _box(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = center


## Sol de 24 x 24 m, une estrade, deux marches et un mur percé d'une porte.
func _world() -> Node3D:
	var w := Node3D.new()
	host.add_child(w)
	_box(w, Vector3(0, -0.25, 0), Vector3(24, 0.5, 24))
	_box(w, Vector3(5, 0.25, 5), Vector3(4, 0.5, 4))
	_box(w, Vector3(-5, 0.1, 4), Vector3(2, 0.2, 2))
	_box(w, Vector3(-5, 0.2, 6), Vector3(2, 0.4, 2))
	_box(w, Vector3(-3, 1.25, 0), Vector3(8, 2.5, 0.3))
	_box(w, Vector3(6, 1.25, 0), Vector3(6, 2.5, 0.3))
	return w


func _physics_frames(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


func _ray_y(w: Node3D, from: Vector3, to: Vector3, fallback: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else fallback


# --------------------------------------------------------------------------
# R2 : _follow_floor (requête de rayon gardée par zombie)
# --------------------------------------------------------------------------

func test_follow_floor_matches_fresh_ray() -> void:
	var w := _world()
	var z := Zombie.new()
	z.setup(1, 3, 0, true)
	w.add_child(z)
	z.set_physics_process(false)
	await _physics_frames(2)
	seed(11)
	var diffs := 0
	for i in 300:
		var start := Vector3(randf_range(-9, 9), randf_range(-0.2, 0.6), randf_range(-9, 9))
		z.global_position = start
		z.velocity = Vector3(randf_range(-2, 2), 0, 1.0)
		var want := _ray_y(w, start + Vector3.UP * 0.9, start + Vector3.DOWN * 1.1, start.y)
		z._follow_floor()
		if z.global_position.y != want:
			diffs += 1
	assert_eq(diffs, 0, "sol suivi identique à un rayon neuf")
	# Immobile : rien ne bouge.
	z.global_position = Vector3(5, 3, 5)
	z.velocity = Vector3.ZERO
	z._follow_floor()
	assert_eq(z.global_position.y, 3.0)
	w.queue_free()


# --------------------------------------------------------------------------
# R3 : MeshNav.find_path (cible en cache, requête réutilisée)
# --------------------------------------------------------------------------

static func _ref_find_path(mn: MeshNav, from: Vector3, to: Vector3) -> PackedVector3Array:
	var goal := mn.closest_point(to)
	var path := NavigationServer3D.map_get_path(mn.map, from, goal, true)
	if path.is_empty() or path[path.size() - 1].distance_to(goal) > MeshNav.REACH_TOLERANCE:
		return PackedVector3Array()
	return path


func _ref_line_clear(mn: MeshNav, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * MeshNav.EYE, to + Vector3.UP * MeshNav.EYE, 1 | Barricade.BARRIER_LAYER)
	return mn._world.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func test_find_path_matches_map_get_path() -> void:
	var w := _world()
	await _physics_frames(2)
	var mn := MeshNav.new()
	mn.setup(w)
	mn.bake()
	# Le serveur de navigation publie la carte cuite quelques pas plus tard.
	for i in 30:
		await _physics_frames(1)
		if mn.closest_point(Vector3(8, 0, 8)) != Vector3.ZERO:
			break
	seed(13)
	var diffs := 0
	var found := 0
	var targets: Array[Vector3] = []
	for i in 6:
		targets.append(Vector3(randf_range(-10, 10), 0.0, randf_range(-10, 10)))
	# La horde vise les mêmes cibles pendant un pas : le cache sert.
	for i in 240:
		var from := Vector3(randf_range(-10, 10), randf_range(0.0, 0.5), randf_range(-10, 10))
		var to: Vector3 = targets[i % targets.size()] if i % 3 != 0 else Vector3(randf_range(-11, 11), randf_range(0.0, 0.6), randf_range(-11, 11))
		var got := mn.find_path(from, to)
		if got != _ref_find_path(mn, from, to):
			diffs += 1
		if not got.is_empty():
			found += 1
		if mn.world_line_clear(from, to) != _ref_line_clear(mn, from, to):
			diffs += 1
	assert_eq(diffs, 0, "chemins et lignes de vue identiques à la référence")
	assert_true(found > 100, "des chemins sont trouvés (%d)" % found)
	# Un chemin rendu n'est pas modifié par les recherches suivantes.
	var a := mn.find_path(Vector3(-8, 0, -8), Vector3(8, 0, 8))
	var copy := a.duplicate()
	for i in 20:
		mn.find_path(Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)), Vector3(8, 0, -8))
	assert_true(a == copy and not a.is_empty(), "chemin rendu intact")
	# Le cache ne survit pas à l'image : il suit la carte.
	var t := Vector3(7, 0, 7)
	mn.goal_point(t)
	assert_true(mn._goals.has(t), "cible en cache")
	await _physics_frames(1)
	mn.goal_point(Vector3(1, 0, 1))
	assert_false(mn._goals.has(t), "cache vidé au pas suivant")
	# Passage ouvert ou fermé : cache vidé, toujours identique.
	mn.add_link("d", Vector3(-8, 0, -1), Vector3(-8, 0, 1))
	mn.goal_point(t)
	mn.set_blocked("d", false)
	assert_false(mn._goals.has(t), "cache vidé quand la carte change")
	diffs = 0
	for i in 40:
		var from := Vector3(randf_range(-10, 10), 0.0, randf_range(-10, 10))
		var to := Vector3(randf_range(-10, 10), 0.0, randf_range(-10, 10))
		if mn.find_path(from, to) != _ref_find_path(mn, from, to):
			diffs += 1
	assert_eq(diffs, 0, "identique après ouverture du passage")
	var polys := mn.region.navigation_mesh.get_polygon_count()
	# Coût (information) : même cible pour toute la horde.
	var t0 := Time.get_ticks_usec()
	for i in 200:
		_ref_find_path(mn, Vector3(-8, 0, -8 + i * 0.01), Vector3(8, 0, 8))
	var t1 := Time.get_ticks_usec()
	for i in 200:
		mn.find_path(Vector3(-8, 0, -8 + i * 0.01), Vector3(8, 0, 8))
	var t2 := Time.get_ticks_usec()
	print("         find_path (%d polygones) : référence %.1f µs, actuel %.1f µs" % [polys, (t1 - t0) / 200.0, (t2 - t1) / 200.0])
	w.queue_free()


# --------------------------------------------------------------------------
# R4 : Zombie._separation (clés de cases calculées, _mgr en cache)
# --------------------------------------------------------------------------

static func _ref_separation(z: Zombie) -> Vector3:
	var push := Vector3.ZERO
	var mgr := z.get_parent() as ZombieManager
	if mgr == null:
		return push
	var grid := mgr.separation_grid()
	var pos := z.global_position
	var cx := floori(pos.x / ZombieManager.GRID_CELL)
	var cz := floori(pos.z / ZombieManager.GRID_CELL)
	for gz in range(cz - 1, cz + 2):
		for gx in range(cx - 1, cx + 2):
			var bucket: Array = grid.get(ZombieManager.grid_key(gx, gz), ZombieManager.EMPTY)
			for op: Vector3 in bucket:
				var d := pos - op
				if absf(d.y) > 1.0:
					continue
				d.y = 0.0
				var l2 := d.length_squared()
				if l2 < z.sep_range * z.sep_range and l2 > 0.0001:
					push += d / l2 * 0.25
	return push.limit_length(1.0)


func test_separation_matches_reference() -> void:
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	seed(14)
	var zs: Array[Zombie] = []
	for i in 40:
		var z := Zombie.new()
		z.setup(i + 1, i, 0, true)
		mgr.add_child(z)
		z.set_physics_process(false)
		z.set_process(false)
		mgr.zombies[i + 1] = z
		mgr.alive.append(z)
		zs.append(z)
	var diffs := 0
	var nonzero := 0
	for round_i in 5:
		# Horde serrée autour de l'origine (cases négatives comprises), deux étages.
		for z in zs:
			z.global_position = Vector3(randf_range(-3, 3), 0.0 if randf() < 0.8 else 1.5, randf_range(-3, 3))
		await _physics_frames(1)  # grille refaite à ce pas
		for z in zs:
			var want := _ref_separation(z)
			if z.separation() != want:
				diffs += 1
			if want != Vector3.ZERO:
				nonzero += 1
	assert_eq(diffs, 0, "répulsion identique à la référence")
	assert_true(nonzero > 50, "des voisins se repoussent (%d)" % nonzero)
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		_ref_separation(zs[i % zs.size()])
	var t1 := Time.get_ticks_usec()
	for i in 2000:
		zs[i % zs.size()].separation()
	var t2 := Time.get_ticks_usec()
	print("         Zombie.separation : référence %.2f µs, actuel %.2f µs" % [(t1 - t0) / 2000.0, (t2 - t1) / 2000.0])
	# Hors d'un ZombieManager : aucune répulsion, comme avant.
	var lone := Zombie.new()
	lone.setup(99, 1, 0, true)
	host.add_child(lone)
	assert_eq(lone.separation(), Vector3.ZERO)
	lone.queue_free()
	mgr.queue_free()


# --------------------------------------------------------------------------
# R5 : instantanés des marionnettes (tampon circulaire)
# --------------------------------------------------------------------------

## Ancienne logique : liste d'instantanés [t, pos, yaw, code], retrait au début.
class RefPuppet:
	var snaps: Array = []
	var last_vel := Vector3.ZERO

	func push(t: float, pos: Vector3, net_yaw: float, code: int) -> void:
		if not snaps.is_empty():
			var prev: Array = snaps[snaps.size() - 1]
			var dt: float = t - prev[0]
			if dt > 0.001:
				last_vel = (pos - prev[1]) / dt
				last_vel.y = 0.0
		snaps.append([t, pos, net_yaw, code])
		if snaps.size() > 12:
			snaps.pop_front()

	## [position, lacet, code] à l'instant `render_t` (null : rien à poser).
	func at(render_t: float) -> Variant:
		if snaps.is_empty():
			return null
		while snaps.size() >= 2 and snaps[1][0] <= render_t:
			snaps.pop_front()
		var a: Array = snaps[0]
		var pos: Vector3 = a[1]
		var ny: float = a[2]
		if snaps.size() == 1 and render_t > a[0] and last_vel != Vector3.ZERO:
			pos = a[1] + last_vel * minf(render_t - a[0], 0.25)
		if snaps.size() >= 2 and render_t > a[0]:
			var b: Array = snaps[1]
			var t := clampf((render_t - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
			pos = a[1].lerp(b[1], t)
			ny = lerp_angle(a[2], b[2], t)
		return [pos, ny, a[3]]


## Ancien code complet de Zombie (liste, retrait au début), nœud posé.
class RefZombie extends Zombie:
	var snaps: Array = []

	func push_snapshot(t: float, pos: Vector3, net_yaw: float, code: int) -> void:
		if not snaps.is_empty():
			var prev: Array = snaps[snaps.size() - 1]
			var dt: float = t - prev[0]
			if dt > 0.001:
				_last_vel = (pos - prev[1]) / dt
				_last_vel.y = 0.0
		snaps.append([t, pos, net_yaw, code])
		if snaps.size() > 12:
			snaps.pop_front()

	func interpolate_at(render_t: float) -> void:
		if snaps.is_empty():
			return
		while snaps.size() >= 2 and snaps[1][0] <= render_t:
			snaps.pop_front()
		var a: Array = snaps[0]
		var pos: Vector3 = a[1]
		var ny: float = a[2]
		if snaps.size() == 1 and render_t > a[0] and _last_vel != Vector3.ZERO:
			pos = a[1] + _last_vel * minf(render_t - a[0], 0.25)
		if snaps.size() >= 2 and render_t > a[0]:
			var b: Array = snaps[1]
			var t := clampf((render_t - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
			pos = a[1].lerp(b[1], t)
			ny = lerp_angle(a[2], b[2], t)
		var prev := global_position
		global_position = pos
		yaw = ny
		rotation.y = yaw
		var dt := get_process_delta_time()
		if dt > 0.0:
			var v := (pos - prev) / dt
			anim_speed = lerpf(anim_speed, Vector2(v.x, v.z).length(), 0.2)
		var code: int = a[3]
		var new_state: State = (code & 7) as State
		speed_class = (code >> 3) & 3
		if new_state != state and state != State.DEAD:
			if new_state == State.ATTACK:
				play_attack()
			state = new_state
			_state_time = 0.0
			_update_solidity()


func test_snapshot_ring_matches_list() -> void:
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	var z := Zombie.new()
	z.setup(5, 2, 1, false)
	mgr.add_child(z)
	z.set_process(false)
	var ref := RefPuppet.new()
	seed(15)
	var t := 100.0
	var pos := Vector3(1, 0, 1)
	var diffs := 0
	var extrapolated := 0
	for step in 400:
		# Rafales de paquets (parfois plusieurs au même instant), puis rendu.
		var n := randi() % 4
		for k in n:
			t += 0.0 if randf() < 0.1 else randf_range(0.0005, 0.12)
			pos += Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
			var y := randf_range(-PI, PI)
			var code := (Zombie.State.CHASE if randf() < 0.9 else Zombie.State.IDLE) | ((randi() % 4) << 3)
			z.push_snapshot(t, pos, y, code)
			ref.push(t, pos, y, code)
		if z.snapshot_count() != ref.snaps.size():
			diffs += 1
		for k in ref.snaps.size():
			if z.snapshot(k) != ref.snaps[k]:
				diffs += 1
		var render_t := t - randf_range(-0.3, 0.4)
		var want: Variant = ref.at(render_t)
		z.interpolate_at(render_t)
		if want == null:
			continue
		if ref.snaps.size() == 1 and render_t > ref.snaps[0][0]:
			extrapolated += 1
		var code: int = want[2]
		if z.global_position != want[0] or z.yaw != want[1] or z.speed_class != (code >> 3) & 3 or z.state != (code & 7):
			diffs += 1
	assert_eq(diffs, 0, "mêmes instantanés et même pose que la liste d'origine")
	assert_true(extrapolated > 5, "prolongement des paquets en retard essayé (%d)" % extrapolated)
	# Même marionnette avec l'ancien code complet (nœud posé) : même pose, et
	# coût (information) à 15 paquets/s pour 60 images/s (1 paquet, 4 poses).
	var old := RefZombie.new()
	old.setup(6, 2, 1, false)
	mgr.add_child(old)
	old.set_process(false)
	var t0 := Time.get_ticks_usec()
	for i in 4000:
		if i % 4 == 0:
			old.push_snapshot(t + i * 0.016, pos + Vector3(i * 0.01, 0, 0), 0.5, 10)
		old.interpolate_at(t + i * 0.016 - 0.12)
	var t1 := Time.get_ticks_usec()
	for i in 4000:
		if i % 4 == 0:
			z.push_snapshot(t + i * 0.016, pos + Vector3(i * 0.01, 0, 0), 0.5, 10)
		z.interpolate_at(t + i * 0.016 - 0.12)
	var t2 := Time.get_ticks_usec()
	assert_true(old.global_position == z.global_position and old.yaw == z.yaw, "même pose que l'ancien code")
	print("         instantanés (paquet + pose) : liste %.2f µs, tampon %.2f µs par image" % [(t1 - t0) / 4000.0, (t2 - t1) / 4000.0])
	z.clear_snapshots()
	assert_eq(z.snapshot_count(), 0)
	mgr.queue_free()


# --------------------------------------------------------------------------
# R6 : MeshMapLayout.ground (requête gardée)
# --------------------------------------------------------------------------

func test_ground_matches_fresh_ray() -> void:
	var w := _world()
	var l := MeshMapLayout.new(null, {}, "")
	l._world = w
	await _physics_frames(2)
	seed(12)
	var diffs := 0
	for i in 300:
		var p := Vector3(randf_range(-13, 13), randf_range(-0.5, 2.0), randf_range(-13, 13))
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, p + Vector3.DOWN * 3.0, 1)
		var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
		var want: Vector3 = hit.position if not hit.is_empty() else p
		if l.ground(p) != want:
			diffs += 1
	assert_eq(diffs, 0, "sol identique à un rayon neuf")
	w.queue_free()


# --------------------------------------------------------------------------
# R8 : InteractionSystem.pick_focus (liste gardée, distance d'abord)
# --------------------------------------------------------------------------

class Obj extends Interactable:
	var usable := true

	func prompt(_pid: int) -> String:
		return "x" if usable else ""


static func _ref_focus(sys: InteractionSystem, eye: Vector3, fwd: Vector3, pid: int, pd: PlayerData) -> Interactable:
	var best: Interactable = null
	var best_score := -INF
	for obj: Interactable in sys.objects.values():
		if not obj.is_visible_in_tree():
			continue
		var to := obj.interact_point() - eye
		var d := to.length()
		if d > obj.interact_range + 0.6:
			continue
		var facing := fwd.dot(to / maxf(d, 0.001))
		if facing < 0.35 and d > 1.0:
			continue
		if not obj.can_interact(pid):
			continue
		var score := facing * 2.0 - d
		if score > best_score:
			best_score = score
			best = obj
	return best


func test_focus_matches_reference() -> void:
	var sys := InteractionSystem.new()
	var root := Node3D.new()
	host.add_child(root)
	var hidden := Node3D.new()
	hidden.visible = false
	root.add_child(hidden)
	seed(16)
	var all: Array[Obj] = []
	for i in 60:
		var o := Obj.new()
		o.interact_id = "o%d" % i
		o.interact_range = randf_range(1.0, 3.0)
		o.usable = randf() < 0.8
		(hidden if i % 7 == 0 else root).add_child(o)
		o.global_position = Vector3(randf_range(-6, 6), randf_range(-0.5, 0.5), randf_range(-6, 6))
		sys.register(o)
		all.append(o)
	# Retiré puis réinscrit, retiré : ordre du Dictionary suivi.
	sys.unregister(all[10])
	sys.register(all[10])
	sys.unregister(all[20])
	assert_eq(sys._list, sys.objects.values(), "liste dans l'ordre du Dictionary")
	var pd := PlayerData.new(1)
	var diffs := 0
	var hits := 0
	for i in 1500:
		var eye := Vector3(randf_range(-6, 6), 1.6, randf_range(-6, 6))
		var fwd := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.3), randf_range(-1, 1)).normalized()
		var want := _ref_focus(sys, eye, fwd, 1, pd)
		if sys.pick_focus(eye, fwd, 1, pd) != want:
			diffs += 1
		if want != null:
			hits += 1
	assert_eq(diffs, 0, "même objet visé que la référence")
	assert_true(hits > 100, "des objets sont visés (%d)" % hits)
	# Coût (information).
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		_ref_focus(sys, Vector3(i % 12 - 6, 1.6, 0), Vector3.FORWARD, 1, pd)
	var t1 := Time.get_ticks_usec()
	for i in 1000:
		sys.pick_focus(Vector3(i % 12 - 6, 1.6, 0), Vector3.FORWARD, 1, pd)
	var t2 := Time.get_ticks_usec()
	print("         focus (%d objets) : référence %.1f µs, actuel %.1f µs" % [sys._list.size(), (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	sys.free()
	root.queue_free()
