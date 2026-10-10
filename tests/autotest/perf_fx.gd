extends AutotestScenario
## @niveau perf
## Coût des EFFETS (particules cubiques, docs/ARCHITECTURE.md « Effets ») :
## BUNKER K-7, 24 zombies immobiles de 6 à 14 m devant le joueur, puis :
##   - combat : à chaque image impacts (béton, métal, bois), sang, fumée de
##     tir, flammes de bouche, douilles, une explosion de grenade toutes les
##     0,6 s ;
##   - effets de carte : 13 effets de l'éditeur posés devant le joueur (feux,
##     fumées, vapeur, soudure, court-circuit, arcs, bobine, pluie
##     d'étincelles, fuite, brouillard, poussière) ;
##   - les deux ensemble.
## Pour chaque phase : temps GPU et CPU moyens du viewport, images par
## seconde, draw calls. Mesure seulement (pas de seuil) :
##   QUALITY=medium sh tools/perf.sh perf_fx

var H := AutotestHelpers
var game: Game
var p: Player
const SAMPLE_S := 4.0
const EFFECTS := ["petit_feu", "brasier", "incendie", "fumee_noire", "fumee_legere", "vapeur", "soudure", "court_circuit",
	"arc", "tesla", "pluie_etincelles", "fuite", "brouillard", "poussiere"]
var _combat := false
var _boom_t := 0.0
var _effects: Array[MapEffect] = []


func run() -> void:
	timeout_sec = 200
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	for id in game.doors:
		game.doors[id].srv_open()
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	if game.barricades:
		for b in game.barricades.windows:
			b.srv_set_mask(0)
	# 24 zombies immobiles devant le joueur, de 6 à 14 m (comme render_perf) :
	# les effets, posés de 2,5 à 5 m, restent visibles devant eux.
	p.teleport_to(MapData.cell_to_world(Vector2i(35, 31), 0.05))
	var target := MapData.cell_to_world(Vector2i(52, 18), 1.2)
	H.aim_at(p, target)
	var ahead := target - p.global_position
	ahead.y = 0.0
	ahead = ahead.normalized()
	var side := ahead.cross(Vector3.UP)
	for i in 24:
		var pos := p.global_position + ahead * (6.0 + 8.0 * float(i) / 23.0) + side * randf_range(-2.0, 2.0)
		var zid: int = game.zombies.spawn(Vector3(pos.x, 0.0, pos.z), i % 4, 1000000)
		game.zombies.get_zombie(zid).speed_mult = 0.0
	await seconds(Zombie.EMERGE_TIME + 0.5)
	H.aim_at(p, p.global_position + ahead * 10.0 + Vector3(0, 1.0, 0))
	await seconds(1.0)
	var rid := at.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _measure("horde", rid)
	_combat = true
	await seconds(1.0)
	await _measure("combat", rid)
	await at.screenshot("combat")
	_combat = false
	await seconds(2.5)
	_place_effects()
	await seconds(2.0)
	await _measure("effets de carte", rid)
	await at.screenshot("effets")
	_combat = true
	await seconds(1.0)
	await _measure("combat + effets", rid)
	_combat = false


## Les effets en arc de cercle devant le joueur, de 3 à 7 m.
func _place_effects() -> void:
	var cam := p.camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	for i in EFFECTS.size():
		var id: String = EFFECTS[i]
		var e := MapEffects.build(id, {"room_h": 3.2})
		if e == null:
			continue
		game.world.add_child(e)
		var t := float(i) / (EFFECTS.size() - 1) - 0.5
		var d := 2.5 + 2.5 * float(i % 3) / 2.0
		var pos := p.global_position + fwd * d + right * t * 6.0
		var d0: Dictionary = MapCatalog.EFFECTS[id]
		var y := 0.0
		match String(d0.mount):
			"mur":
				y = float(d0.get("y", 1.5))
			"plafond":
				y = 3.18
		e.global_position = Vector3(pos.x, y, pos.z)
		e.look_at(e.global_position - fwd, Vector3.UP)
		_effects.append(e)


func _process_combat(delta: float) -> void:
	var fx := game.fx_root
	var cam := p.camera.global_transform
	var o := cam.origin
	var fwd := -cam.basis.z
	for k in 3:
		var hit := o + fwd * randf_range(3.0, 8.0) + Vector3(randf_range(-1.5, 1.5), randf_range(-0.8, 0.8), randf_range(-1.5, 1.5))
		var n := -fwd
		fx.impact(hit, n, false, ["concrete", "metal", "wood"][k])
		fx.tracer(o + fwd * 0.5 + Vector3.DOWN * 0.2, hit)
	fx.blood_hit(o + fwd * 4.0 + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)), fwd, 1.0)
	fx.muzzle_flash(o + fwd * 2.0, fwd)
	fx.eject_shell(o + fwd * 0.6, Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)), "rifle")
	_boom_t -= delta
	if _boom_t <= 0.0:
		_boom_t = 0.6
		var pos := o + fwd * 6.0
		pos.y = 0.05
		game.throwables.explosion_fx(pos, 0)


## Moyennes sur SAMPLE_S secondes : GPU (ms), CPU du rendu (ms), fps, draw calls.
func _measure(label: String, rid: RID) -> void:
	var gpu := 0.0
	var cpu := 0.0
	var dc := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_frames_drawn()
	while (Time.get_ticks_usec() - t0) < SAMPLE_S * 1e6:
		if _combat:
			_process_combat(get_process_delta_time())
		await frames(1)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		n += 1
	var fps := float(Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - t0) / 1e6)
	print("[perf] fx %s : GPU %.2f ms, CPU rendu %.2f ms, %.0f fps, %.0f draw calls, %d effets de carte, %d particules de carte" % [label, gpu / n, cpu / n, fps, dc / n,
		_effects.size(), _map_particles()])
	at.check(n > 10, "%s : %d images mesurées" % [label, n])


func _map_particles() -> int:
	var s := 0
	for e in _effects:
		s += e.particle_count()
	return s


func get_process_delta_time() -> float:
	return at.get_process_delta_time()
