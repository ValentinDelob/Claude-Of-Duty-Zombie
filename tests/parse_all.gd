extends SceneTree
## Charge (compile) tous les scripts du projet et échoue si l'un d'eux ne compile pas.
##   godot --headless --path . -s res://tests/parse_all.gd

var _bad := 0
var _count := 0


func _initialize() -> void:
	for dir in ["res://scripts", "res://tests", "res://tools"]:
		_scan(dir)
	print("PARSE: %d scripts, %d en erreur" % [_count, _bad])
	quit(1 if _bad > 0 else 0)


func _scan(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			_count += 1
			var path := dir + "/" + f
			var s: GDScript = load(path)
			if s == null or not s.can_instantiate():
				_bad += 1
				print("PARSE ERREUR : " + path)
	for d in DirAccess.get_directories_at(dir):
		_scan(dir + "/" + d)
