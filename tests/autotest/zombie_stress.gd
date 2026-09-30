extends AutotestScenario
## Charge : 24 zombies en poursuite sur BUNKER K-7 (toutes portes ouvertes),
## le joueur tourne dans le laboratoire. Mesure le temps CPU par image
## (_process + _physics_process de tout l'arbre), le coût des apparitions et
## celui des morts.
##
## Les moniteurs Performance.TIME_* ne donnent que le MAXIMUM de la dernière
## seconde : on encadre donc les rappels de l'arbre par deux sondes de
## priorités extrêmes (première et dernière appelées à chaque image / pas).

var H := AutotestHelpers
var game: Game
var p: Player
var _proc_ms := PackedFloat32Array()
var _phys_ms := PackedFloat32Array()
var _measuring := false
var _probe_first: Probe
var _probe_last: Probe
## Trajectoire du joueur (ellipse dans le labo, sans obstacle).
var _orbit_t := 0.0
var _orbiting := false

const CENTER := Vector2(43.5, 24.5)
const RADIUS := Vector2(7.0, 2.0)
const ORBIT_SPEED := 3.2  # m/s (environ)


class Probe extends Node:
	var sc
	var first := false
	var t_proc := 0
	var t_phys := 0

	func _process(_d: float) -> void:
		if first:
			t_proc = Time.get_ticks_usec()
		else:
			sc._on_probe_process(Time.get_ticks_usec())

	func _physics_process(_d: float) -> void:
		if first:
			t_phys = Time.get_ticks_usec()
		else:
			sc._on_probe_physics(Time.get_ticks_usec())


func run() -> void:
	timeout_sec = 120
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	# Fenêtres déjà arrachées : on mesure la horde au contact, pas l'arrachage
	# des planches (~12 s par fenêtre au rythme de BO1).
	if game.barricades:
		for b in game.barricades.windows:
			b.srv_set_mask(0)
	_probe_first = _make_probe(true)
	_probe_last = _make_probe(false)
	p.teleport_to(_orbit_pos())
	_orbiting = true
	await seconds(1.0)

	# Référence sans zombie.
	var base := await _measure("0 zombie", 3.0)

	# Coût de construction du modèle seul (mesh skinné + squelette).
	var tb := Time.get_ticks_usec()
	for i in 24:
		ZombieModel.build(1000 + i).free()
	print("[perf] modèle de zombie : %.2f ms/construction" % ((Time.get_ticks_usec() - tb) / 1000.0 / 24.0))

	# Apparitions : 24 zombies répartis sur les points de la carte.
	var spots: Array = game.map_data.markers.get("Z", [])
	var t0 := Time.get_ticks_usec()
	var worst_spawn := 0
	for i in 24:
		var c: Vector2i = spots[(i * 7) % spots.size()]
		var ts := Time.get_ticks_usec()
		game.zombies.spawn(MapData.cell_to_world(c) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)), i % 4, 1000000)
		worst_spawn = maxi(worst_spawn, Time.get_ticks_usec() - ts)
	var spawn_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("[perf] apparitions : 24 zombies en %.1f ms (%.2f ms/zombie, pire %.2f ms)" % [spawn_ms, spawn_ms / 24.0, worst_spawn / 1000.0])
	at.check(game.zombies.alive_count() == 24, "24 zombies vivants")
	# Sortie de terre + premiers pas : fait partie du temps de trajet de la horde.
	await seconds(Zombie.EMERGE_TIME + 1.0)

	# Poursuite : les zombies traversent la carte jusqu'au labo.
	var chase := await _measure("24 zombies en poursuite", 10.0)
	var near := 0
	for z: Zombie in game.zombies.alive:
		if z.global_position.distance_to(p.global_position) < 8.0:
			near += 1
	at.check(near >= 10, "la horde a rejoint le joueur (%d/24 à moins de 8 m)" % near)
	# Mêlée autour du joueur immobile (attaques, séparation).
	_orbiting = false
	await seconds(2.0)  # la horde se resserre autour du joueur
	var crowd := await _measure("24 zombies au contact", 4.0)
	await at.screenshot("horde")
	await seconds(0.5)  # la capture bloque le GPU : hors mesure

	# Morts simultanées : 24 corps qui tombent puis se dissolvent.
	var tk := Time.get_ticks_usec()
	for z: Zombie in game.zombies.alive.duplicate():
		game.zombies.kill(z.id, false, Vector3.FORWARD)
	print("[perf] 24 morts simultanées : %.1f ms" % ((Time.get_ticks_usec() - tk) / 1000.0))
	var death := await _measure("24 corps", 3.0)
	await until(func(): return game.zombies.zombies.is_empty(), Zombie.DISSOLVE_DELAY + Zombie.DISSOLVE_TIME + 2.0, "corps dissous et retirés")
	at.check(game.zombies.zombies.is_empty(), "corps retirés après dissolution")
	_probe_first.queue_free()
	_probe_last.queue_free()

	print("[perf] résumé CPU (ms _process/image + ms _physics_process/pas) : base %s | poursuite %s | contact %s | morts %s" % [base.cpu, chase.cpu, crowd.cpu, death.cpu])
	at.check_perf(chase.fps, 150.0, "24 zombies en poursuite")
	at.check_perf(crowd.fps, 150.0, "24 zombies au contact")


func _measure(label: String, dur: float) -> Dictionary:
	_proc_ms.clear()
	_phys_ms.clear()
	_measuring = true
	at.begin_perf()
	await seconds(dur)
	var fps: float = at.end_perf(label)
	_measuring = false
	var pr := _stats(_proc_ms)
	var ph := _stats(_phys_ms)
	print("[perf] %s : CPU _process moy %.2f ms/image (max %.1f), _physics_process moy %.2f ms/pas (max %.1f)" % [label, pr.x, pr.y, ph.x, ph.y])
	return {"fps": fps, "cpu": "%.2f+%.2f" % [pr.x, ph.x], "proc": pr.x, "phys": ph.x}


static func _stats(a: PackedFloat32Array) -> Vector2:
	if a.is_empty():
		return Vector2.ZERO
	var s := 0.0
	var m := 0.0
	for v in a:
		s += v
		m = maxf(m, v)
	return Vector2(s / a.size(), m)


func _make_probe(first: bool) -> Probe:
	var pr := Probe.new()
	pr.sc = self
	pr.first = first
	pr.process_mode = Node.PROCESS_MODE_ALWAYS
	pr.process_priority = -1000000 if first else 1000000
	pr.process_physics_priority = -1000000 if first else 1000000
	tree().root.add_child(pr)
	return pr


func _on_probe_process(t_end: int) -> void:
	if _measuring:
		_proc_ms.append((t_end - _probe_first.t_proc) / 1000.0)
	_move_player()


func _on_probe_physics(t_end: int) -> void:
	if _measuring:
		_phys_ms.append((t_end - _probe_first.t_phys) / 1000.0)


func _orbit_pos() -> Vector3:
	return Vector3(CENTER.x + cos(_orbit_t) * RADIUS.x, 0.05, CENTER.y + sin(_orbit_t) * RADIUS.y)


func _move_player() -> void:
	if not _orbiting or p == null or not is_instance_valid(p):
		return
	var dt := at.get_process_delta_time()
	_orbit_t += dt * ORBIT_SPEED / ((RADIUS.x + RADIUS.y) * 0.5)
	var pos := _orbit_pos()
	var dir := pos - p.global_position
	p.global_position = pos
	if dir.length_squared() > 0.0001:
		p.yaw = atan2(-dir.x, -dir.z)
		p.rotation.y = p.yaw
