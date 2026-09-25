extends Node
## Lance tous les fichiers tests/test_*.gd et quitte avec un code d'erreur
## si un test échoue.
##   godot --headless --path . res://tests/test_runner.tscn
##   godot --headless --path . res://tests/test_runner.tscn -- --filter=net

func _ready() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	await get_tree().process_frame
	var total := 0
	var failed := 0
	var files := DirAccess.get_files_at("res://tests")
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_case.gd" or f == "test_runner.gd":
			continue
		if filter != "" and not f.contains(filter):
			continue
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_"):
				continue
			var tc: TestCase = script.new()
			tc.host = self
			total += 1
			tc.before_each()
			await tc.call(mname)
			tc.after_each()
			if tc.failures.is_empty():
				print("  [OK]   %s::%s" % [f, mname])
			else:
				failed += 1
				print("  [FAIL] %s::%s" % [f, mname])
				for msg in tc.failures:
					print("         - " + msg)
	print("")
	print("TESTS: %d, ÉCHECS: %d" % [total, failed])
	get_tree().quit(1 if failed > 0 else 0)
