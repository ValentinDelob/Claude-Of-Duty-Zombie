extends SceneTree
## Instrumentation des scripts pour la couverture de code (GDScript n'en a pas
## nativement ; voir docs/TESTING.md § Couverture). Appelé par tools/coverage.sh
## sur une COPIE du projet, jamais sur les sources :
##   godot --headless -s res://tools/coverage/instrument.gd -- \
##       --dst=<copie> --roots=scripts [--base=0] --map=<fichier> --class=<chemin>
##
## Avant chaque instruction d'un corps de fonction, insère une ligne
## `CovHits.h(<n>)` (même indentation) ; <n> numérote l'instruction et la
## carte <map> donne « n fichier ligne fonction » (ligne = ligne d'origine).
## Ne sont PAS instrumentées (pas de ligne indépendante possible) : les suites
## d'une expression sur plusieurs lignes, les lignes `elif` / `else`, les
## motifs d'un `match`, le contenu des chaînes """…""", les fonctions écrites
## sur une seule ligne et les accesseurs `get` / `set` de propriétés.

var _re_func := RegEx.create_from_string("^(\\s*)(static\\s+)?func\\s+(\\w+)")
var _n := 0
var _map := PackedStringArray()


func _init() -> void:
	var dst := ""
	var roots := PackedStringArray(["scripts"])
	var map_path := ""
	var class_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dst="):
			dst = a.substr(6)
		elif a.begins_with("--roots="):
			roots = a.substr(8).split(",", false)
		elif a.begins_with("--base="):
			_n = a.substr(7).to_int()
		elif a.begins_with("--map="):
			map_path = a.substr(6)
		elif a.begins_with("--class="):
			class_path = a.substr(8)
	if dst == "" or map_path == "":
		printerr("[cov] usage : --dst=<copie> --map=<fichier> [--roots=a,b] [--class=<chemin du CovHits>]")
		quit(2)
		return
	var files := PackedStringArray()
	for r in roots:
		_collect(dst.path_join(r), files)
	var count := 0
	for f in files:
		var rel := f.trim_prefix(dst + "/")
		var src := FileAccess.get_file_as_string(f)
		var out := instrument(src, rel)
		var fa := FileAccess.open(f, FileAccess.WRITE)
		fa.store_string(out)
		count += 1
	var fm := FileAccess.open(map_path, FileAccess.WRITE)
	fm.store_string("\n".join(_map) + "\n")
	if class_path != "":
		var fc := FileAccess.open(class_path, FileAccess.WRITE)
		fc.store_string(_hits_class(_n))
	print("[cov] %d scripts instrumentés, %d instructions" % [count, _n])
	quit(0)


func _collect(dir: String, into: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(dir.path_join(sub), into)
	for f in d.get_files():
		if f.ends_with(".gd"):
			into.append(dir.path_join(f))


## Script instrumenté. `rel` : chemin relatif (pour la carte).
func instrument(src: String, rel: String) -> String:
	var lines := src.split("\n")
	var out := PackedStringArray()
	var depth := 0            # parenthèses / crochets / accolades ouverts
	var cont := false         # ligne précédente terminée par « \ »
	var in_triple := false    # dans une chaîne """…"""
	var func_indent := -1     # indentation de la fonction en cours (-1 : aucune)
	var func_name := ""
	var header_open := false  # en-tête de fonction pas encore terminé
	# Blocs ouverts dans la fonction : [indentation, est un match, indentation des motifs].
	var blocks: Array = []
	for i in lines.size():
		var line := lines[i]
		var clean := depth == 0 and not cont and not in_triple
		var stripped := line.strip_edges()
		var indent := _indent_of(line)
		var code := stripped != "" and not stripped.begins_with("#")
		var is_stmt := false
		if clean and code:
			# Sortie de fonction ou de blocs : indentation revenue en arrière.
			if func_indent >= 0 and indent <= func_indent:
				func_indent = -1
				blocks.clear()
			while not blocks.is_empty() and indent <= blocks[-1][0]:
				blocks.pop_back()
			var m := _re_func.search(line)
			if m:
				func_indent = indent
				func_name = m.get_string(3)
				header_open = true
			elif func_indent >= 0:
				is_stmt = true
				var pattern := false
				if not blocks.is_empty() and blocks[-1][1]:
					if blocks[-1][2] == -1:
						blocks[-1][2] = indent
					pattern = indent == blocks[-1][2]
				var skip := pattern or stripped.begins_with("elif ") or stripped.begins_with("elif(") \
						or stripped.begins_with("else:") or stripped.begins_with("else :")
				if not skip:
					var ws := line.substr(0, line.length() - line.lstrip(" \t").length())
					out.append("%sCovHits.h(%d)" % [ws, _n])
					_map.append("%d %s %d %s" % [_n, rel, i + 1, func_name])
					_n += 1
		out.append(line)
		var st := _scan(line, depth, in_triple)
		depth = st[0]
		in_triple = st[1]
		cont = st[2]
		var ended := depth == 0 and not cont and not in_triple
		if header_open and ended:
			# Fin de l'en-tête : un corps suit seulement s'il finit par « : ».
			header_open = false
			if not String(st[3]).ends_with(":"):
				func_indent = -1
		elif is_stmt and ended and String(st[3]).ends_with(":"):
			var is_match := stripped.begins_with("match ") or stripped.begins_with("match(")
			blocks.append([indent, is_match, -1])
	return "\n".join(out)


func _indent_of(line: String) -> int:
	var n := 0
	for c in line:
		if c == "\t":
			n += 4
		elif c == " ":
			n += 1
		else:
			break
	return n


## Parcourt une ligne : [profondeur, dans """, suite « \ », code sans commentaire].
func _scan(line: String, depth: int, in_triple: bool) -> Array:
	var i := 0
	var n := line.length()
	var code := ""
	var quote := ""
	while i < n:
		var c := line[i]
		if in_triple:
			if line.substr(i, 3) == "\"\"\"":
				in_triple = false
				i += 3
				continue
			i += 1
			continue
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
			code += "x"
			i += 1
			continue
		if line.substr(i, 3) == "\"\"\"":
			in_triple = true
			i += 3
			continue
		if c == "\"" or c == "'":
			quote = c
			code += "x"
			i += 1
			continue
		if c == "#":
			break
		if c in "([{":
			depth += 1
		elif c in ")]}":
			depth = maxi(depth - 1, 0)
		code += c
		i += 1
	code = code.strip_edges()
	var cont := code.ends_with("\\")
	return [depth, in_triple, cont, code]


func _hits_class(n: int) -> String:
	return """class_name CovHits
extends Object
## Généré par tools/coverage/instrument.gd (copie instrumentée seulement).
## Compteurs de passage de chaque instruction ; vidés dans COV_OUT à la sortie
## (CovDump, autoload de la copie).

const N := %d
static var hits := PackedInt32Array()


static func h(i: int) -> void:
	if hits.is_empty():
		hits.resize(N)
	hits[i] += 1


static func dump(tag: String) -> void:
	var dir := OS.get_environment("COV_OUT")
	if dir == "" or hits.is_empty():
		return
	var f := FileAccess.open("%%s/%%s_%%d.cov" %% [dir, tag, OS.get_process_id()], FileAccess.WRITE)
	if f == null:
		return
	for i in hits.size():
		if hits[i] > 0:
			f.store_line("%%d %%d" %% [i, hits[i]])
""" % n
