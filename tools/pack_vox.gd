extends SceneTree
## Paquet des répliques d'une langue (docs/RELEASE.md § 3) :
##   godot --headless --path . -s res://tools/pack_vox.gd -- --lang=fr --out=<fichier.pck>
## Contient, pour chaque réplique res://assets/audio/vox/<langue>/**.ogg, son
## fichier .import (redirection) et le fichier importé de .godot/imported/ :
## monté par l'autoload Packs, `load("res://assets/audio/vox/…ogg")` marche
## comme si la réplique était dans le paquet principal. Jamais les caches de
## Godot (.godot/*cache*, project.binary) : ils écraseraient ceux du core.
## Écrit aussi <fichier.pck>.inputs : empreinte MD5 des fichiers d'entrée
## (noms + contenus), stable d'une construction à l'autre (le PCK lui-même
## peut varier) : tools/release.sh ne republie le paquet que si elle change.
## Préalable : projet importé (tools/check.sh ou `godot --import`).

const VOX := "res://assets/audio/vox/"


func _init() -> void:
	var lang := ""
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			lang = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
	if not lang in ["fr", "en"] or out == "":
		printerr("[vox] usage : --lang=fr|en --out=<fichier.pck>")
		quit(2)
		return
	var imports := PackedStringArray()
	_collect(VOX + lang, imports)
	imports.sort()
	var pk := PCKPacker.new()
	if pk.pck_start(out) != OK:
		printerr("[vox] impossible d'écrire " + out)
		quit(1)
		return
	var sig := PackedStringArray()
	var bytes := 0
	for imp in imports:
		var cfg := ConfigFile.new()
		if cfg.load(imp) != OK:
			printerr("[vox] .import illisible : " + imp)
			quit(1)
			return
		var dest := String(cfg.get_value("remap", "path", ""))
		if not dest.begins_with("res://.godot/imported/") or not FileAccess.file_exists(dest):
			printerr("[vox] fichier importé absent (projet non importé ?) : %s -> %s" % [imp, dest])
			quit(1)
			return
		for f in [imp, dest]:
			if pk.add_file(f, ProjectSettings.globalize_path(f)) != OK:
				printerr("[vox] ajout impossible : " + f)
				quit(1)
				return
			sig.append("%s %s" % [f, FileAccess.get_md5(f)])
		bytes += FileAccess.get_file_as_bytes(dest).size()
	if pk.flush() != OK:
		printerr("[vox] écriture du paquet impossible")
		quit(1)
		return
	var fi := FileAccess.open(out + ".inputs", FileAccess.WRITE)
	fi.store_string("\n".join(sig).md5_text() + "\n")
	print("[vox] %s : %d répliques, %.1f Mo -> %s" % [lang, imports.size(), bytes / 1048576.0, out])
	quit(0)


func _collect(dir: String, into: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), into)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".ogg.import"):
			into.append(dir.path_join(f))
