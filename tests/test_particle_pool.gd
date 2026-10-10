extends TestCase
## ParticlePool : le sol sous une gerbe (Fx.floor_under, un rayon sur les
## cartes en maillage) est demandé UNE fois par gerbe, pas une fois par
## particule ; chaque particule garde exactement le même sol qu'avant.

var _saved_instance: Game


class CountingLayout extends MapLayout:
	var calls := 0

	func floor_y(pos: Vector3) -> float:
		calls += 1
		return 0.25 + pos.x * 0.5


## Référence : l'ancienne mise à jour (deux passes, relectures des tableaux).
## La version en une passe de ParticlePool doit donner exactement la même image.
class ReferencePool extends ParticlePool:
	func _process(delta: float) -> void:
		if _count == 0:
			return
		var i := 0
		var damp := exp(-drag * delta)
		while i < _count:
			_life[i] -= delta
			if _life[i] <= 0.0:
				_count -= 1
				_pos[i] = _pos[_count]
				_vel[i] = _vel[_count]
				_life[i] = _life[_count]
				_max_life[i] = _max_life[_count]
				_size[i] = _size[_count]
				_col[i] = _col[_count]
				_floor[i] = _floor[_count]
				_axis[i] = _axis[_count]
				_rate[i] = _rate[_count]
				continue
			_vel[i] = _vel[i] * damp + Vector3.DOWN * gravity * delta
			_pos[i] += _vel[i] * delta
			if _pos[i].y < _floor[i]:
				_pos[i].y = _floor[i]
				_vel[i] = Vector3(_vel[i].x * 0.3, 0.0, _vel[i].z * 0.3)
			i += 1
		var mm := multimesh
		mm.visible_instance_count = _count
		for k in _count:
			var t := _life[k] / _max_life[k]
			# Cubes : rétrécissent pendant la seconde moitié de leur vie et
			# tournent sur leur axe (VoxelFx).
			var s := _size[k] * (1.0 + grow * (1.0 - t)) * clampf(t * 2.0, 0.0, 1.0)
			mm.set_instance_transform(k, Transform3D(Basis(_axis[k], _rate[k] * (_max_life[k] - _life[k])) * s, _pos[k]))
			mm.set_instance_color(k, _col[k])


func before_each() -> void:
	_saved_instance = Game.instance


func after_each() -> void:
	Game.instance = _saved_instance
	ParticlePool.density = 1.0


func _setup() -> Array:
	var g := Game.new()
	var l := CountingLayout.new()
	g.layout = l
	Game.instance = g
	var pool := ParticlePool.new().setup(64, StandardMaterial3D.new())
	return [g, l, pool]


func test_burst_queries_floor_once() -> void:
	var s := _setup()
	var l: CountingLayout = s[1]
	var pool: ParticlePool = s[2]
	pool.burst(Vector3(2, 1, 3), Vector3.UP, 12, 3.0, 0.8, 0.7, Color.RED)
	assert_eq(pool._count, 12, "12 particules émises")
	assert_eq(l.calls, 1, "un seul calcul du sol pour la gerbe (%d)" % l.calls)
	for i in pool._count:
		assert_near(pool._floor[i], 0.25 + 2.0 * 0.5 + 0.01, 0.00001, "sol de la particule %d" % i)
	# Densité réduite (LOW) : toujours un seul calcul.
	ParticlePool.density = 0.5
	pool.burst(Vector3(4, 1, 3), Vector3.UP, 10, 3.0, 0.8, 0.7, Color.RED)
	assert_eq(pool._count, 17, "5 particules de plus en LOW")
	assert_eq(l.calls, 2, "un calcul par gerbe")
	# Gerbe vide (densité normale) : aucun calcul.
	ParticlePool.density = 1.0
	pool.burst(Vector3(4, 1, 3), Vector3.UP, 0, 3.0, 0.8, 0.7, Color.RED)
	assert_eq(l.calls, 2, "gerbe vide : aucun rayon")
	pool.free()
	(s[0] as Game).free()


func test_emit_keeps_own_floor() -> void:
	var s := _setup()
	var l: CountingLayout = s[1]
	var pool: ParticlePool = s[2]
	pool.emit(Vector3(1, 1, 0), Vector3.UP, 0.5, Color.WHITE)
	pool.emit(Vector3(3, 1, 0), Vector3.UP, 0.5, Color.WHITE)
	assert_eq(l.calls, 2, "émission isolée : un calcul chacune")
	assert_near(pool._floor[0], 0.25 + 0.5 + 0.01, 0.00001)
	assert_near(pool._floor[1], 0.25 + 1.5 + 0.01, 0.00001)
	pool.free()
	(s[0] as Game).free()


func _fill(pool: ParticlePool, s: int) -> void:
	seed(s)
	for b in 20:
		pool.burst(Vector3(randf() * 4.0, 1.0 + randf(), randf() * 4.0), Vector3.UP, 12, 3.0, 0.8, 0.7, Color(0.45, 0.0, 0.0, 0.95))


func _pools() -> Array:
	var mat := StandardMaterial3D.new()
	var out := []
	for pl: ParticlePool in [ReferencePool.new().setup(240, mat, 0.07), ParticlePool.new().setup(240, mat, 0.07)]:
		pl.gravity = 9.0
		pl.drag = 1.0
		pl.grow = 0.5
		out.append(pl)
	return out


func test_update_matches_reference() -> void:
	Game.instance = null
	var pools := _pools()
	var ref: ParticlePool = pools[0]
	var cur: ParticlePool = pools[1]
	_fill(ref, 7)
	_fill(cur, 7)
	var diffs := 0
	# 60 images : chutes, rebonds au sol, morts et remplacements.
	for f in 60:
		ref._process(1.0 / 60.0)
		cur._process(1.0 / 60.0)
		assert_eq(cur._count, ref._count, "même nombre de particules (image %d)" % f)
		assert_eq(cur.multimesh.visible_instance_count, ref.multimesh.visible_instance_count)
		for k in ref._count:
			if cur.multimesh.get_instance_transform(k) != ref.multimesh.get_instance_transform(k) \
					or cur.multimesh.get_instance_color(k) != ref.multimesh.get_instance_color(k) \
					or cur._vel[k] != ref._vel[k]:
				diffs += 1
	assert_eq(diffs, 0, "instances identiques à la référence")
	assert_true(ref._count < 240, "des particules sont mortes pendant l'essai (%d)" % ref._count)
	# Coût (information) : 240 particules.
	var cost := []
	for pl: ParticlePool in pools:
		var t := 0
		for r in 200:
			_fill(pl, r)
			var t0 := Time.get_ticks_usec()
			pl._process(1.0 / 60.0)
			t += Time.get_ticks_usec() - t0
		cost.append(float(t) / 200.0)
	print("         ParticlePool._process (240 particules) : référence %.1f µs, actuel %.1f µs" % [cost[0], cost[1]])
	ref.free()
	cur.free()
