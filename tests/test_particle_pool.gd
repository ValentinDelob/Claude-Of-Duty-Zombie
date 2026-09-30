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
