extends TestCase
## Format 17 (docs/LEVELS_PLAN.md § 3) : plus de clé « etage » dans le code
## (scripts/), hors de la conversion des cartes d'avant et du contrôle des
## cartes reçues (schéma figé du format 16). Les commentaires ne comptent pas.

## Fichiers qui lisent encore l'ancien format, et pourquoi.
const ALLOWED := {
	"res://scripts/editor/editor_map.gd": "conversion des cartes d'avant (migrate_levels)",
	"res://scripts/game/map/custom_map_guard.gd": "contrôle des cartes reçues au format 16 (schéma figé)",
	"res://scripts/editor/map_catalog.gd": "conversion des effets d'avant le format 11 (avant celle des niveaux)",
	"res://scripts/editor/collab/map_summary.gd": "résumé des cartes d'avant (références du script Python d'origine)",
}


static func _files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_files(dir.path_join(d), out)


## Code d'une ligne, sans son commentaire (un « # » hors d'une chaîne).
static func _code(line: String) -> String:
	var in_str := ""
	for i in line.length():
		var ch := line[i]
		if in_str != "":
			if ch == "\\":
				continue
			if ch == in_str and (i == 0 or line[i - 1] != "\\"):
				in_str = ""
		elif ch == "\"" or ch == "'":
			in_str = ch
		elif ch == "#":
			return line.left(i)
	return line


func test_no_floor_key_in_scripts() -> void:
	var files := []
	_files("res://scripts", files)
	assert_true(files.size() > 100, "scripts trouvés")
	var bad := []
	for f in files:
		if ALLOWED.has(f):
			continue
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in lines.size():
			var c := _code(lines[i])
			if c.contains("\"etage\"") or c.contains(".etage") or c.contains("\"double_hauteur\"") or c.contains(".floor_height("):
				bad.append("%s:%d  %s" % [f, i + 1, lines[i].strip_edges().left(100)])
	assert_true(bad.is_empty(), "clés d'étage encore lues ou écrites :\n" + "\n".join(bad))
