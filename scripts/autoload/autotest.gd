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
var _frame_ms_max := 0.0
var _sampling := false
var _failed := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			scenario_name = a.substr(11)
	if scenario_name == "":
		set_process(false)
		return
	active = true
	# Mesure la capacité réelle du GPU, pas la fréquence de l'écran.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[autotest] scénario « %s »" % scenario_name)
	_run.call_deferred()


func _run() -> void:
	var path := "res://tests/autotest/%s.gd" % scenario_name
	if not ResourceLoader.exists(path):
		fail("scénario introuvable : " + path)
		finish()
		return
	var sc: AutotestScenario = load(path).new()
	sc.at = self
	# Filet de sécurité : un scénario bloqué ne doit jamais geler la CI.
	get_tree().create_timer(sc.timeout_sec, true, false, true).timeout.connect(func():
		fail("timeout du scénario (%ds)" % sc.timeout_sec)
		finish())
	await sc.run()
	finish()


func _process(delta: float) -> void:
	if _sampling:
		_fps_samples.append(1.0 / maxf(delta, 0.0001))
		_frame_ms_max = maxf(_frame_ms_max, delta * 1000.0)


func begin_perf() -> void:
	_fps_samples.clear()
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
	print("[perf] %s : moy %.0f fps, 1%% bas %.0f fps, pire image %.1f ms, draw calls %d, nœuds %d, objets %d, mém %.0f Mo" % [
		label, avg, p1, _frame_ms_max,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	return avg


func screenshot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
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
	if get_tree().current_scene:
		get_tree().current_scene.queue_free()
	Audio.stop_all()
	for i in 3:
		await get_tree().process_frame
	get_tree().quit(1 if _failed else 0)
