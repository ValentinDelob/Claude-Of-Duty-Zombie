extends Node
## Autotest — scénarios de test automatisés joués dans le vrai jeu.
##
##   godot --path . -- --autotest=<nom> [--shots]
##
## Charge res://tests/autotest/<nom>.gd (qui étend AutotestScenario), l'exécute,
## mesure les performances, prend des captures (tests/_out/shots/) et quitte avec
## le code 0 (succès) ou 1 (échec). Inactif sans l'argument --autotest.

var active := false
var scenario_name := ""
var _fps_samples: PackedFloat32Array = []
## Temps GPU du viewport principal (ms) des mêmes images : moins sensible que
## les fps à la charge CPU des autres jeux (machine partagée).
var _gpu_ms_sum := 0.0
## Temps GPU moyen (ms) de la dernière mesure end_perf().
var last_gpu_ms := 0.0
var _frame_ms_max := 0.0
var _sampling := false
var _failed := false
var _t_pre := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			scenario_name = a.substr(11)
	if scenario_name == "":
		set_process(false)
		return
	active = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	RenderingServer.frame_pre_draw.connect(func(): _t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func():
		var d := Time.get_ticks_usec() - _t_pre
		if d > 15000 and _sampling:
			print("[prof] rendu de l'image : %.1f ms" % (d / 1000.0)))
	# Mesure la capacité réelle du GPU, pas la fréquence de l'écran.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if DisplayServer.get_name() != "headless":
		_move_offscreen()
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[autotest] scénario « %s »" % scenario_name)
	# Chien de garde global (au cas où le scénario lui-même planterait).
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		fail("chien de garde global")
		finish())
	_run.call_deferred()


func _run() -> void:
	var path := "res://tests/autotest/%s.gd" % scenario_name
	# Le nom devient un chemin de script chargé : jamais « .. », « / » ni « : ».
	if not NetGuard.safe_token(scenario_name, 64):
		fail("nom de scénario invalide : " + scenario_name.left(64))
		finish()
		return
	if not ResourceLoader.exists(path):
		fail("scénario introuvable : " + path)
		finish()
		return
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		fail("le scénario ne compile pas : " + path)
		finish()
		return
	var sc: AutotestScenario = script.new()
	sc.at = self
	# Filet de sécurité : un scénario bloqué ne doit jamais geler la CI.
	# Vérifié chaque seconde : les scénarios fixent `timeout_sec` au début de
	# run(), APRÈS la création du minuteur (un minuteur fixe plafonnait donc
	# tous les scénarios à la valeur par défaut de 60 s).
	var t0 := Time.get_ticks_msec()
	var watchdog := Timer.new()
	watchdog.wait_time = 1.0
	watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(watchdog)
	watchdog.timeout.connect(func():
		if (Time.get_ticks_msec() - t0) / 1000.0 >= sc.timeout_sec:
			watchdog.stop()
			fail("timeout du scénario (%ds)" % sc.timeout_sec)
			finish())
	watchdog.start()
	await sc.run()
	finish()


func _process(delta: float) -> void:
	if _sampling:
		if delta > 0.025:
			var vp := get_viewport().get_viewport_rid()
			print("[prof] image lente %.1f ms à t=%.2f : process %.1f ms, physique %.1f ms, rendu CPU %.1f ms, GPU %.1f ms, nav %.1f" % [delta * 1000.0, Time.get_ticks_msec() / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp), Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0])
		_fps_samples.append(1.0 / maxf(delta, 0.0001))
		_gpu_ms_sum += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		_frame_ms_max = maxf(_frame_ms_max, delta * 1000.0)


func begin_perf() -> void:
	_fps_samples.clear()
	_gpu_ms_sum = 0.0
	_frame_ms_max = 0.0
	_sampling = true


## Termine la mesure et imprime une ligne [perf]. Retourne le FPS moyen.
func end_perf(label: String) -> float:
	_sampling = false
	if _fps_samples.is_empty():
		return 0.0
	var sum := 0.0
	var sorted := _fps_samples.duplicate()
	sorted.sort()
	for f in _fps_samples:
		sum += f
	var avg := sum / _fps_samples.size()
	var p1: float = sorted[int(sorted.size() * 0.01)]
	last_gpu_ms = _gpu_ms_sum / _fps_samples.size()
	print("[perf] %s : moy %.0f fps, 1%% bas %.0f fps, pire image %.1f ms, GPU %.2f ms, draw calls %d, nœuds %d, objets %d, mém %.0f Mo" % [
		label, avg, p1, _frame_ms_max, last_gpu_ms,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	return avg


func screenshot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Deux images pour être sûr que la vue est à jour (frame_post_draw peut ne
	# jamais arriver si la fenêtre est masquée).
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://tests/_out/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s_%s.png" % [dir, scenario_name, shot_name]
	img.save_png(path)
	print("[autotest] capture : " + path)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("[autotest] OK   " + msg)
	else:
		fail(msg)


func fail(msg: String) -> void:
	_failed = true
	print("[autotest] ECHEC " + msg)


var _finishing := false


func finish() -> void:
	if _finishing:
		return
	_finishing = true
	print("[autotest] fin : %s" % ("ECHEC" if _failed else "SUCCES"))
	# Libère la scène et coupe les sons avant de quitter : sortie propre, sans
	# ressources encore référencées.
	Net.leave()
	Audio.stop_all()
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	for i in 3:
		await get_tree().process_frame
	get_tree().quit(1 if _failed else 0)


## Vérification de performance. En exécution parallèle (check.sh lance
## plusieurs jeux à la fois, AUTOTEST_PARALLEL=1), un seuil manqué n'est qu'un
## avertissement : les mesures fiables sont faites par tools/perf.sh.
func check_perf(fps: float, minimum: float, label: String) -> void:
	# Sans rendu (tests logiques en --headless), les fps ne mesurent rien :
	# la performance est vérifiée par tools/perf.sh, avec rendu.
	if DisplayServer.get_name() == "headless":
		print("[autotest] perf %s ignorée (sans rendu)" % label)
		return
	if fps >= minimum:
		print("[autotest] OK   perf %s (%.0f fps >= %.0f)" % [label, fps, minimum])
	elif OS.get_environment("AUTOTEST_PARALLEL") == "1":
		print("[autotest] AVERTISSEMENT perf %s (%.0f fps < %.0f, exécution parallèle)" % [label, fps, minimum])
	else:
		fail("perf %s (%.0f fps < %.0f)" % [label, fps, minimum])


## Fenêtre de test hors de tous les écrans : elle rend normalement (captures,
## mesures) sans jamais apparaître par-dessus les fenêtres de l'utilisateur.
## tools/nofocus.sh la fait démarrer réduite et sans focus ; on la place à
## droite du bureau (tous écrans confondus) puis on la restaure là-bas.
## AUTOTEST_ONSCREEN=1 : laisse la fenêtre visible (débogage).
func _move_offscreen() -> void:
	if OS.get_environment("AUTOTEST_ONSCREEN") == "1":
		return
	var right := 0
	var top := 0
	for i in DisplayServer.get_screen_count():
		var r := DisplayServer.screen_get_usable_rect(i)
		right = maxi(right, r.end.x)
		top = mini(top, r.position.y)
	var pos := Vector2i(right + 400, top)
	DisplayServer.window_set_position(pos)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_position(pos)
	print("[autotest] fenêtre hors écran en %s" % DisplayServer.window_get_position())
