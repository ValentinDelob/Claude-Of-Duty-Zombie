extends SceneTree
## Carte des dépendances des tests et empreinte de chaque tâche du check.
##   godot --headless --path . -s res://tools/test_deps.gd -- --out=tests/_out/deps
##
## Pour chaque tâche (même nommage que tools/check.sh : unit:<fichier>,
## head:<scénario>, gui:<scénario>, mp:<nom>, parse:scripts, net:smoke,
## launcher:tests), calcule l'ensemble des fichiers dont elle dépend puis une
## empreinte MD5 de leur contenu. check.sh ne relance une tâche que si son
## empreinte diffère de celle de son dernier succès (sélection par impact).
##
## Dépendances d'un fichier : les `class_name` qu'il nomme et les chemins
## `res://…` qu'il cite (scènes .tscn comprises), de proche en proche. On ne
## traverse PAS les fichiers « noyau » (HUBS) : presque tout en dépend, les
## suivre relierait chaque test à tout le projet. À la place, chaque scénario
## dépend de tous les noyaux (un noyau modifié relance tous les scénarios).
## Principe de prudence (Microsoft Test Impact Analysis) : un fichier du jeu
## qu'aucun scénario n'atteint est ajouté à TOUS les scénarios.
##
## Annotations en tête d'un test :
##   ## @couvre scripts/game/perks/*     dépendances ajoutées à la main (motifs)
##   ## @carte kino                      test propre à une carte : il ne dépend
##                                      QUE des fichiers de cette carte (et de
##                                      lui-même), jamais des noyaux.
## Sortie : <out>/tasks.txt (« tâche empreinte nb_fichiers carte|- »), <out>/<tâche>.txt
## (liste des dépendances, pour comprendre pourquoi une tâche a été relancée).

const HUBS := [
	"project.godot",
	"scripts/autoload/*",
	"scripts/boot.gd",
	"scripts/game/game.gd",
	"scripts/game/session.gd",
	"scripts/game/player/player.gd",
	"scenes/*",
	"tests/test_case.gd",
	"tests/test_runner.gd",
	"tests/autotest/scenario.gd",
	"tests/autotest/helpers.gd",
	"tests/autotest/mp_helpers.gd",
	"tools/check.sh",
	"tools/mp_test.sh",
	"tools/net_smoke.sh",
]
## Fichiers propres à chaque carte (@carte <id>), en plus de assets/maps/<id>/*
## et scripts/game/map/maps/<id>.gd.
const MAP_EXTRA := {
	"kino": ["scripts/game/map/theater_look.gd", "assets/models/kino/*"],
}
var DEPTH := int(OS.get_environment("DEPS_DEPTH")) if OS.get_environment("DEPS_DEPTH") != "" else 2
const SKIP_EXT := ["import", "uid", "tmp", "blend", "blend1", "py", "md"]

var _class_file := {}      # class_name -> chemin
var _direct := {}          # chemin -> PackedStringArray (dépendances directes)
var _md5 := {}             # chemin -> md5
var _all_files: PackedStringArray = []
var _re_class := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
var _re_word := RegEx.create_from_string("\\b[A-Z][A-Za-z0-9_]+\\b")
var _re_res := RegEx.create_from_string("res://([^\"'\\s)]+)")


func _init() -> void:
	var out := "tests/_out/deps"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	for top_dir in ["scripts", "scenes", "tests", "assets", "tools"]:
		_scan("res://" + top_dir)
	_all_files.append("project.godot")
	for f in _all_files:
		if f.ends_with(".gd"):
			var m := _re_class.search(_read(f))
			if m:
				_class_file[m.get_string(1)] = f

	var tasks := _tasks()
	# Fichiers atteints par au moins un scénario (hors cartes dédiées).
	var reached := {}
	for t in tasks:
		if not t.map_only and (t.kind in ["head", "gui", "mp"]):
			for f in t.deps:
				reached[f] = true
	var orphans: PackedStringArray = []
	for f in _all_files:
		if (f.begins_with("scripts/") or f.begins_with("assets/") or f.begins_with("scenes/")) \
				and not reached.has(f) and not _is_map_specific(f):
			orphans.append(f)

	var lines: PackedStringArray = []
	for t in tasks:
		var deps: Dictionary = t.deps
		if t.kind in ["head", "gui", "mp"] and not t.map_only:
			for f in orphans:
				deps[f] = true
		var keys: Array = deps.keys()
		keys.sort()
		var buf := PackedStringArray()
		for f in keys:
			buf.append("%s %s" % [f, _hash(f)])
		var joined := "\n".join(buf)
		lines.append("%s %s %d %s" % [t.name, joined.md5_text(), keys.size(), t.map_id if t.map_id != "" else "-"])
		var fa := FileAccess.open("res://%s/%s.txt" % [out, t.name.replace(":", "_")], FileAccess.WRITE)
		if fa:
			fa.store_string(joined + "\n")
	var fo := FileAccess.open("res://%s/tasks.txt" % out, FileAccess.WRITE)
	fo.store_string("\n".join(lines) + "\n")
	var fo2 := FileAccess.open("res://%s/orphans.txt" % out, FileAccess.WRITE)
	fo2.store_string("\n".join(orphans) + "\n")
	print("[deps] %d tâches, %d fichiers, %d sans scénario (ajoutés à tous)" % [tasks.size(), _all_files.size(), orphans.size()])
	quit(0)


# ------------------------------------------------------------------ tâches

func _tasks() -> Array:
	var tasks := []
	var all_gd := {}
	for f in _all_files:
		if f.ends_with(".gd"):
			all_gd[f] = true
	tasks.append({"name": "parse:scripts", "kind": "parse", "map_only": false, "map_id": "", "deps": all_gd})
	var launcher := {}
	for f in _all_files:
		if f.begins_with("launcher/"):
			launcher[f] = true
	_scan_into("res://launcher", launcher)
	tasks.append({"name": "launcher:tests", "kind": "launcher", "map_only": false, "map_id": "", "deps": launcher})
	var net := _closure(["tests/net_smoke.gd", "scripts/autoload/net.gd", "scripts/game/net_guard.gd"])
	_add_hubs(net)
	tasks.append({"name": "net:smoke", "kind": "net", "map_only": false, "map_id": "", "deps": net})

	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd" and f != "test_runner.gd":
			tasks.append(_task("unit:" + f.get_basename(), "unit", ["tests/" + f]))
	for f in DirAccess.get_files_at("res://tests/autotest"):
		if not f.ends_with(".gd"):
			continue
		var n := f.get_basename()
		if n in ["scenario", "helpers", "mp_helpers"] or n.begins_with("long_") or n.begins_with("perf_"):
			continue
		if n.begins_with("mp_"):
			if n.ends_with("_host"):
				var base := n.substr(3, n.length() - 8)
				tasks.append(_task("mp:" + base, "mp", ["tests/autotest/%s.gd" % n, "tests/autotest/mp_%s_client.gd" % base]))
			continue
		var kind := "gui" if _read("tests/autotest/" + f).contains("\n## @rendu") or _read("tests/autotest/" + f).begins_with("## @rendu") else "head"
		tasks.append(_task("%s:%s" % [kind, n], kind, ["tests/autotest/" + f]))
	return tasks


func _task(tname: String, kind: String, roots: Array) -> Dictionary:
	var map_id := ""
	var extra: PackedStringArray = []
	for r in roots:
		for line in _read(r).split("\n"):
			if line.begins_with("## @carte "):
				map_id = line.substr(10).strip_edges().get_slice(" ", 0)
			elif line.begins_with("## @couvre "):
				for pat in line.substr(11).strip_edges().split(" ", false):
					extra.append(pat)
	var deps := {}
	if map_id != "":
		for r in roots:
			deps[r] = true
		for f in _all_files:
			if _is_map_file(f, map_id):
				deps[f] = true
	else:
		deps = _closure(roots)
		if kind != "unit":
			_add_hubs(deps)
		else:
			deps["tests/test_case.gd"] = true
			deps["tests/test_runner.gd"] = true
			deps["project.godot"] = true
	for pat in extra:
		for f in _all_files:
			if f.match(pat):
				deps[f] = true
	return {"name": tname, "kind": kind, "map_only": map_id != "", "map_id": map_id, "deps": deps}


func _add_hubs(deps: Dictionary) -> void:
	for f in _all_files:
		if _is_hub(f):
			deps[f] = true


func _is_hub(f: String) -> bool:
	for pat in HUBS:
		if f.match(pat):
			return true
	return false


func _is_map_file(f: String, map_id: String) -> bool:
	return f.begins_with("assets/maps/%s/" % map_id) or f == "scripts/game/map/maps/%s.gd" % map_id \
		or MAP_EXTRA.get(map_id, []).any(func(p): return f.match(p))


func _is_map_specific(f: String) -> bool:
	for id in MAP_EXTRA:
		if _is_map_file(f, id):
			return true
	return false


# ------------------------------------------------------------------ graphe

## Fermeture des dépendances à partir de `roots`, sans traverser les noyaux.
func _closure(roots: Array, depth := DEPTH) -> Dictionary:
	var seen := {}
	var frontier: Array = roots.duplicate()
	for f in frontier:
		seen[f] = true
	for level in depth:
		var next := []
		for f in frontier:
			if _is_hub(f) and not f in roots:
				continue
			for d in _deps_of(f):
				if not seen.has(d):
					seen[d] = true
					next.append(d)
		frontier = next
	return seen


func _deps_of(f: String) -> PackedStringArray:
	if _direct.has(f):
		return _direct[f]
	var out := {}
	if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres") or f.ends_with(".gdshader"):
		var text := _read(f)
		for m in _re_res.search_all(text):
			var p := m.get_string(1)
			if FileAccess.file_exists("res://" + p):
				out[p] = true
			elif DirAccess.dir_exists_absolute("res://" + p.trim_suffix("/")):
				for g in _all_files:
					if g.begins_with(p.trim_suffix("/") + "/"):
						out[g] = true
		if f.ends_with(".gd"):
			var words := {}
			for m in _re_word.search_all(text):
				words[m.get_string()] = true
			for w in words:
				if _class_file.has(w) and _class_file[w] != f:
					out[_class_file[w]] = true
			# Carte nommée par son identifiant ("kino", "verruckt"…) : ses fichiers.
			for id in _map_ids():
				if text.contains("\"%s\"" % id):
					for g in _all_files:
						if _is_map_file(g, id):
							out[g] = true
	var arr := PackedStringArray(out.keys())
	_direct[f] = arr
	return arr


var _map_ids_cache: PackedStringArray = []

func _map_ids() -> PackedStringArray:
	if _map_ids_cache.is_empty():
		for f in DirAccess.get_files_at("res://scripts/game/map/maps"):
			if f.ends_with(".gd"):
				_map_ids_cache.append(f.get_basename())
	return _map_ids_cache


# ------------------------------------------------------------------ fichiers

func _scan(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "_out" or sub == "piper" or sub == "tts" or sub == "__pycache__":
			continue
		_scan(dir.path_join(sub))
	for f in d.get_files():
		if f.get_extension() in SKIP_EXT:
			continue
		_all_files.append(dir.path_join(f).trim_prefix("res://"))


func _scan_into(dir: String, into: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_scan_into(dir.path_join(sub), into)
	for f in d.get_files():
		if not f.get_extension() in SKIP_EXT:
			into[dir.path_join(f).trim_prefix("res://")] = true


func _read(f: String) -> String:
	return FileAccess.get_file_as_string("res://" + f)


func _hash(f: String) -> String:
	if not _md5.has(f):
		_md5[f] = FileAccess.get_md5("res://" + f)
	return _md5[f]
