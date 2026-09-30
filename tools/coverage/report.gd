extends SceneTree
## Rapport de couverture (tools/coverage.sh) : fusionne les compteurs vidés par
## les jeux de la copie instrumentée (<dir>/raw/*.cov, « instruction nombre »)
## avec les cartes d'instrumentation (<dir>/map_game.txt, map_launcher.txt :
## « instruction fichier ligne fonction »).
##   godot --headless -s res://tools/coverage/report.gd -- --dir=<dossier> [--ratchet]
## Écrit dans <dir> :
##   summary.md    tableau par dossier (instructions et fonctions exécutées)
##   files.txt     détail par fichier, du moins couvert au plus couvert
##   missed.txt    fonctions jamais exécutées, par fichier
## Seuils : tools/coverage/floors.txt (« dossier pourcentage »). Un dossier
## sous son seuil est signalé (AVERTISSEMENT) ; COV_STRICT=1 le rend bloquant.
## --ratchet : relève chaque seuil au niveau atteint (arrondi à l'entier
## inférieur) ; un seuil ne descend jamais.

const FLOORS := "res://tools/coverage/floors.txt"

var _stmts := {}      # « jeu|n » ou « lanceur|n » -> [fichier, ligne, fonction]
var _hits := {}       # même clé -> nombre de passages


func _init() -> void:
	var dir := ""
	var ratchet := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
		elif a == "--ratchet":
			ratchet = true
	_read_map(dir.path_join("map_game.txt"), "jeu", "")
	_read_map(dir.path_join("map_launcher.txt"), "lanceur", "launcher/")
	var raw := dir.path_join("raw")
	var nfiles := 0
	for f in DirAccess.get_files_at(raw):
		if not f.ends_with(".cov"):
			continue
		nfiles += 1
		var side := "lanceur" if f.begins_with("launcher_") else "jeu"
		for line in FileAccess.get_file_as_string(raw.path_join(f)).split("\n", false):
			var p := line.split(" ")
			if p.size() == 2:
				var k := "%s|%s" % [side, p[0]]
				_hits[k] = int(_hits.get(k, 0)) + p[1].to_int()
	if _stmts.is_empty():
		printerr("[cov] aucune carte d'instrumentation dans " + dir)
		quit(1)
		return

	# Agrégats par fichier et par fonction.
	var files := {}   # fichier -> {n, hit, funcs: {nom: hit?}}
	for k in _stmts:
		var s: Array = _stmts[k]
		var fe: Dictionary = files.get(s[0], {"n": 0, "hit": 0, "funcs": {}, "missed_lines": []})
		files[s[0]] = fe
		fe.n += 1
		var hit := int(_hits.get(k, 0)) > 0
		if hit:
			fe.hit += 1
		else:
			fe.missed_lines.append(s[1])
		fe.funcs[s[2]] = bool(fe.funcs.get(s[2], false)) or hit
	var groups := {}  # dossier -> {n, hit, fn, fhit, files}
	for f in files:
		var g := _group_of(f)
		var ge: Dictionary = groups.get(g, {"n": 0, "hit": 0, "fn": 0, "fhit": 0, "files": 0})
		groups[g] = ge
		var fe: Dictionary = files[f]
		ge.n += fe.n
		ge.hit += fe.hit
		ge.files += 1
		for fn in fe.funcs:
			ge.fn += 1
			if fe.funcs[fn]:
				ge.fhit += 1

	var floors := _read_floors()
	var names: Array = groups.keys()
	names.sort()
	var md := PackedStringArray()
	md.append("# Couverture de code — %s" % Time.get_datetime_string_from_system(false, true))
	md.append("")
	md.append("Instructions = lignes exécutables instrumentées (tools/coverage/instrument.gd) ; ")
	md.append("fonctions = au moins une instruction exécutée. %d fichiers de compteurs fusionnés." % nfiles)
	md.append("")
	md.append("| Dossier | Fichiers | Instructions | Couvertes | % | Fonctions | % | Seuil |")
	md.append("|---|---|---|---|---|---|---|---|")
	var tot := {"n": 0, "hit": 0, "fn": 0, "fhit": 0, "files": 0}
	var below := PackedStringArray()
	for g in names:
		var ge: Dictionary = groups[g]
		for key in tot:
			tot[key] += ge[key]
		var pct: float = 100.0 * ge.hit / maxf(ge.n, 1)
		var fl: float = floors.get(g, 0.0)
		if pct + 0.001 < fl:
			below.append("%s : %.1f %% < seuil %.0f %%" % [g, pct, fl])
		if ratchet and floor(pct) > fl:
			floors[g] = floor(pct)
		md.append("| `%s` | %d | %d | %d | %.1f | %d / %d | %.1f | %s |" % [g, ge.files, ge.n, ge.hit, pct,
				ge.fhit, ge.fn, 100.0 * ge.fhit / maxf(ge.fn, 1), ("%.0f %%" % fl) if floors.has(g) else "—"])
	md.append("| **total** | %d | %d | %d | **%.1f** | %d / %d | **%.1f** | |" % [tot.files, tot.n, tot.hit,
			100.0 * tot.hit / maxf(tot.n, 1), tot.fhit, tot.fn, 100.0 * tot.fhit / maxf(tot.fn, 1)])
	_write(dir.path_join("summary.md"), "\n".join(md) + "\n")

	var flist: Array = files.keys()
	flist.sort_custom(func(a, b): return _pct(files[a]) < _pct(files[b]) or (_pct(files[a]) == _pct(files[b]) and a < b))
	var ft := PackedStringArray()
	var mt := PackedStringArray()
	for f in flist:
		var fe: Dictionary = files[f]
		ft.append("%5.1f %%  %4d / %-4d  %s" % [_pct(fe), fe.hit, fe.n, f])
		var missed := PackedStringArray()
		for fn in fe.funcs:
			if not fe.funcs[fn]:
				missed.append(fn)
		if not missed.is_empty():
			mt.append("%s : %s" % [f, ", ".join(missed)])
	_write(dir.path_join("files.txt"), "\n".join(ft) + "\n")
	_write(dir.path_join("missed.txt"), "\n".join(mt) + "\n")
	if ratchet:
		_write_floors(floors)

	print("\n".join(md))
	for b in below:
		print("[cov] AVERTISSEMENT sous le seuil : " + b)
	if not below.is_empty() and OS.get_environment("COV_STRICT") == "1":
		quit(1)
		return
	quit(0)


func _read_map(path: String, side: String, prefix: String) -> void:
	if not FileAccess.file_exists(path):
		return
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var p := line.split(" ", false, 3)
		if p.size() == 4:
			_stmts["%s|%s" % [side, p[0]]] = [prefix + p[1], p[2].to_int(), p[3]]


## Dossier du rapport : scripts/game/<sous-dossier>, scripts/<dossier>,
## launcher/scripts ; les fichiers posés directement dans scripts/game sont
## regroupés sous « scripts/game ».
func _group_of(f: String) -> String:
	if f.begins_with("launcher/"):
		return "launcher/scripts"
	var parts := f.split("/")
	if parts.size() >= 4 and parts[1] == "game":
		return "scripts/game/" + parts[2]
	if parts.size() >= 3:
		return "scripts/" + parts[1]
	return "scripts"


func _pct(fe: Dictionary) -> float:
	return 100.0 * fe.hit / maxf(fe.n, 1)


func _read_floors() -> Dictionary:
	var d := {}
	if FileAccess.file_exists(FLOORS):
		for line in FileAccess.get_file_as_string(FLOORS).split("\n", false):
			if line.begins_with("#"):
				continue
			var p := line.split(" ", false)
			if p.size() == 2:
				d[p[0]] = p[1].to_float()
	return d


func _write_floors(d: Dictionary) -> void:
	var keys: Array = d.keys()
	keys.sort()
	var lines := PackedStringArray(["# Seuils de couverture par dossier (%), relevés par",
		"# tools/coverage.sh --ratchet ; ne descendent jamais (docs/TESTING.md § 4)."])
	for k in keys:
		lines.append("%s %d" % [k, int(d[k])])
	_write(ProjectSettings.globalize_path(FLOORS), "\n".join(lines) + "\n")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
