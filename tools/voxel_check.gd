extends SceneTree
## Vérification du STYLE CUBIQUE d'un modèle (GAME_CONCEPT.md § 4.19,
## VoxelCheck, docs/MAP_DESIGN_RULES.md « Style cubique »), sans fenêtre :
##   godot --headless --path . -s res://tools/voxel_check.gd -- <fichier.glb> [--anime | --statique] [--echelle=1.0] [--pas=<cm>] [--en]
##   godot --headless --path . -s res://tools/voxel_check.gd -- --carte=<dossier de carte>
## Modèle : statique ou animé deviné (squelette présent : chaque partie dans
## le repère de repos de son os). Grille : 5 cm en statique (décor, objets),
## 2,5 cm en animé (personnages, mobs) ; --pas=<cm> la force. Carte (dossier de user://maps/<id> ou chemin
## absolu) : objets posés hors quarts de tour, inclinés, et modèles importés
## non cubiques (avertissements : la carte se charge quand même).
## Code de sortie : 0 conforme, 1 non conforme, 2 erreur (fichier illisible).


func _init() -> void:
	var files: Array = []
	var animated := -1
	var scale := 1.0
	var cube := 0.0
	var map_dir := ""
	var en := false
	for a in OS.get_cmdline_user_args():
		if a == "--anime":
			animated = 1
		elif a == "--statique":
			animated = 0
		elif a.begins_with("--pas="):
			cube = a.substr(6).replace(",", ".").to_float() / 100.0
		elif a.begins_with("--echelle="):
			scale = a.substr(10).to_float()
		elif a.begins_with("--carte="):
			map_dir = a.substr(8)
		elif a == "--en":
			en = true
		elif not a.begins_with("--"):
			files.append(a)
	if files.is_empty() and map_dir == "":
		print("usage : godot --headless --path . -s res://tools/voxel_check.gd -- <fichier.glb> [--anime|--statique] [--echelle=N] [--pas=<cm>] [--en] | --carte=<dossier>")
		quit(2)
		return
	var code := 0
	for f in files:
		code = maxi(code, _model(String(f), animated, scale, cube, en))
	if map_dir != "":
		code = maxi(code, _map(map_dir, en))
	quit(code)


func _model(path: String, animated: int, scale: float, cube: float, en: bool) -> int:
	var p := path.replace("\\", "/")
	if not FileAccess.file_exists(p):
		print("[voxel_check] %s : %s" % [p, "missing file" if en else "fichier absent"])
		return 2
	var t0 := Time.get_ticks_msec()
	var rep := VoxelCheck.check_file(p, animated, scale, cube)
	if rep.has("error"):
		print("[voxel_check] %s : %s" % [p, rep.error[1] if en else rep.error[0]])
		return 2
	var mode := ("animated" if en else "animé") if bool(rep.get("animated", false)) else ("static" if en else "statique")
	print("[voxel_check] %s (%s, %d %s, %d ms)" % [p.get_file(), mode, int(rep.parts), "part(s)" if en else "partie(s)", Time.get_ticks_msec() - t0])
	print("  " + String(rep.en if en else rep.fr))
	print("  %s : faces %d, %s %d, %s %d, %s %d, %s %d" % ["OK" if rep.ok else ("FAIL" if en else "ÉCHEC"), int(rep.faces),
		"slanted" if en else "obliques", int(rep.oblique), "off-grid" if en else "hors grille", int(rep.off_grid),
		"smooth normals" if en else "normales lissées", int(rep.smooth), "non-triangles" if en else "non-triangles", int(rep.other_prims)])
	return 0 if rep.ok else 1


func _map(dir: String, en: bool) -> int:
	# Fichiers lus directement (objets.json, prefabs/<pid>/) : EditorMap
	# dépend des autoloads, absents d'un script lancé par -s.
	var d := dir.replace("\\", "/")
	if not DirAccess.dir_exists_absolute(d) and DirAccess.dir_exists_absolute("user://maps/" + d):
		d = "user://maps/" + d
	if not FileAccess.file_exists(d.path_join("objets.json")):
		print("[voxel_check] %s : %s" % [d, "missing map folder (objets.json)" if en else "dossier de carte absent (objets.json)"])
		return 2
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(d.path_join("objets.json")))
	var objs: Array = j.get("objets", []) if j is Dictionary else []
	var bad := 0
	for o in objs:
		if not o is Dictionary:
			continue
		var why := VoxelCheck.placement_issue(o)
		if not why.is_empty():
			bad += 1
			print("  %s %s (%s) : %s" % ["object" if en else "objet", String(o.get("id", "?")), String(o.get("type", "?")), why[1] if en else why[0]])
	var pdir := d.path_join("prefabs")
	for pid in (DirAccess.get_directories_at(pdir) if DirAccess.dir_exists_absolute(pdir) else PackedStringArray()):
		var mp := pdir.path_join(pid).path_join("model.glb")
		if not FileAccess.file_exists(mp):
			continue
		var def: Variant = JSON.parse_string(FileAccess.get_file_as_string(pdir.path_join(pid).path_join("prefab.json")))
		var sc := 1.0
		if def is Dictionary and def.get("modele") is Dictionary and (def.modele.get("echelle") is float or def.modele.get("echelle") is int):
			sc = float(def.modele.echelle)
		var rep := VoxelCheck.check_glb_bytes(FileAccess.get_file_as_bytes(mp), 0, sc)
		if not rep.get("ok", false):
			bad += 1
			print("  %s %s : %s" % ["model" if en else "modèle", pid, rep.en if en else rep.fr])
	print("[voxel_check] %s : %d %s" % [d.get_file(), bad, "issue(s) (warnings: the map still loads)" if en else "écart(s) (avertissements : la carte se charge quand même)"])
	return 0 if bad == 0 else 1
