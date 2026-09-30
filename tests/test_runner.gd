extends Node
## Lance tous les fichiers tests/test_*.gd et quitte avec un code d'erreur
## si un test échoue.
##   godot --headless --path . res://tests/test_runner.tscn
##   godot --headless --path . res://tests/test_runner.tscn -- --filter=net
##   godot --headless --path . res://tests/test_runner.tscn -- --files=test_net.gd,test_perks.gd
## --files : uniquement ces fichiers (tools/check.sh : tests impactés).
## Chaque ligne [OK]/[FAIL] donne la durée du test ; les plus lents sont
## rappelés à la fin (repérer ce qui ralentit le niveau unitaire).

const SLOWEST := 8


func _ready() -> void:
	var filter := ""
	var only := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
		elif a.begins_with("--files="):
			only = a.substr(8).split(",", false)
	await get_tree().process_frame
	var total := 0
	var failed := 0
	var times := []
	var t_all := Time.get_ticks_msec()
	var files := DirAccess.get_files_at("res://tests")
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_case.gd" or f == "test_runner.gd":
			continue
		if filter != "" and not f.contains(filter):
			continue
		if not only.is_empty() and not f in only:
			continue
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_"):
				continue
			var tc: TestCase = script.new()
			tc.host = self
			total += 1
			var t0 := Time.get_ticks_msec()
			tc.before_each()
			await tc.call(mname)
			tc.after_each()
			var ms := Time.get_ticks_msec() - t0
			times.append([ms, "%s::%s" % [f, mname]])
			if tc.failures.is_empty():
				print("  [OK]   %s::%s (%d ms)" % [f, mname, ms])
			else:
				failed += 1
				print("  [FAIL] %s::%s (%d ms)" % [f, mname, ms])
				for msg in tc.failures:
					print("         - " + msg)
	times.sort_custom(func(a, b): return a[0] > b[0])
	print("")
	print("Tests les plus lents :")
	for i in mini(SLOWEST, times.size()):
		print("  %6d ms  %s" % times[i])
	print("")
	print("TESTS: %d, ÉCHECS: %d (%.1f s)" % [total, failed, (Time.get_ticks_msec() - t_all) / 1000.0])
	# Sons encore en cours (effets déclenchés par un test) : coupés avant de
	# quitter, sinon « resources still in use at exit » (compté comme erreur).
	Audio.stop_all()
	# Quelques images et un peu de temps réel : les tâches de fond (aperçu 3D,
	# chargements) rendent leurs ressources avant la sortie.
	var t_end := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_end < 150:
		await get_tree().process_frame
	get_tree().quit(1 if failed > 0 else 0)
