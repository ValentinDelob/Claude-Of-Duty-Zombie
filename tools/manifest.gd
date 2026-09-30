extends SceneTree
## Manifeste d'une version en paquets (docs/RELEASE.md § 4), pour
## tools/release.sh et tools/promote.sh :
##   --make=<entrées.tsv> --version=<tag> --channel=snapshot|stable --build=<n> --godot=<4.7.2> --out=<manifest.json>
##       entrées : « id  fichier  sha256  taille  release  empreinte_d_entrée » par ligne
##       (id « engine » = le moteur ; « core » = paquet principal ; « vox-<langue> »)
##   --get=<manifest.json> --id=<id> --field=<champ>   affiche « =<valeur> »
##   --promote=<manifest.json> --version=<tag stable> --out=<fichier>   canal stable

func _init() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			a[arg.get_slice("=", 0).substr(2)] = arg.substr(arg.find("=") + 1)
	if a.has("make"):
		quit(_make(a))
	elif a.has("get"):
		quit(_get_field(a))
	elif a.has("promote"):
		quit(_promote(a))
	else:
		printerr("[manifest] usage : --make=… | --get=… | --promote=…")
		quit(2)


func _make(a: Dictionary) -> int:
	var d := {"format": 1, "version": a.get("version", ""), "channel": a.get("channel", "snapshot"),
		"build": a.get("build", ""), "packs": []}
	for line in FileAccess.get_file_as_string(a.make).split("\n", false):
		var p := line.split("\t")
		if p.size() < 6:
			continue
		var e := {"file": p[1], "sha256": p[2], "size": p[3].to_int(), "release": p[4]}
		if p[5] != "":
			e["inputs"] = p[5]
		if p[0] == "engine":
			e["godot"] = a.get("godot", "")
			d["engine"] = e
		else:
			e["id"] = p[0]
			if p[0].begins_with("vox-"):
				e["lang"] = p[0].substr(4)
			if p[0] == "core":
				e["main"] = true
			(d.packs as Array).append(e)
	if not d.has("engine") or (d.packs as Array).is_empty():
		printerr("[manifest] entrées incomplètes (moteur ou paquets manquants)")
		return 1
	var f := FileAccess.open(a.out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ") + "\n")
	f.close()
	print("[manifest] %s (%s) : moteur %s, %d paquet(s)" % [d.version, d.channel, d.engine.file, d.packs.size()])
	return 0


func _get_field(a: Dictionary) -> int:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.get("get", "")))
	if not d is Dictionary:
		return 1
	var e: Variant = d.get("engine") if a.get("id", "") == "engine" else null
	if e == null:
		for p: Variant in d.get("packs", []):
			if p is Dictionary and p.get("id", "") == a.get("id", ""):
				e = p
	if not e is Dictionary or not e.has(a.get("field", "")):
		return 1
	var v: Variant = e[a.field]
	print("=" + (str(int(v)) if v is float else str(v)))
	return 0


## Même build et mêmes fichiers (qui restent dans la release de la snapshot) ;
## seuls le numéro et le canal changent.
func _promote(a: Dictionary) -> int:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.promote))
	if not d is Dictionary or not d.has("engine"):
		return 1
	d["version"] = a.get("version", "")
	d["channel"] = "stable"
	d["promoted_from"] = JSON.parse_string(FileAccess.get_file_as_string(a.promote)).get("version", "")
	d = _ints(d)
	var f := FileAccess.open(a.out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ") + "\n")
	f.close()
	print("[manifest] %s promue en stable (%s)" % [d.promoted_from, d.version])
	return 0


## JSON relu : les nombres entiers redeviennent des entiers (tailles, format).
static func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x): return _ints(x))
	return v
