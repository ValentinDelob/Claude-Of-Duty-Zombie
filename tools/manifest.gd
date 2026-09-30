extends SceneTree
## Manifeste d'une version en paquets (docs/RELEASE.md § 4), pour
## tools/release.sh et tools/promote.sh :
##   --make=<entrées.tsv> --version=<tag> --channel=snapshot|stable --build=<n> --godot=<4.7.2> --out=<manifest.json>
##       entrées : « id  fichier  sha256  taille  release  empreinte_d_entrée  [numéro] » par ligne
##       (id « engine » = le moteur ; « core » = paquet principal ; « vox-<langue> » ;
##       « launcher » = le lanceur, avec son numéro LAUNCHER_VERSION en 7e colonne)
##   --get=<manifest.json> --id=<id> --field=<champ>   affiche « =<valeur> » (--id= : champ du manifeste)
##   --promote=<manifest.json> --version=<tag stable> --out=<fichier>   canal stable
##       [--launcher=<entrée.tsv>] : entrée « launcher » ajoutée si le manifeste
##       de la snapshot n'en a pas (snapshots 165 à 167)
## Les fonctions statiques (make, get_field, promote) sont testées par
## tests/test_release_tools.gd.

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


## Manifeste à partir des lignes TSV (voir en tête) ; {} si les entrées sont
## incomplètes (moteur, paquet principal ou lanceur manquant) ou invalides.
static func make(tsv: String, version: String, channel: String, build: String, godot: String) -> Dictionary:
	var d := {"format": 1, "version": version, "channel": channel, "build": build, "packs": []}
	for line in tsv.split("\n", false):
		var p := line.trim_suffix("\r").split("\t")
		if p.size() < 6:
			continue
		var e := {"file": p[1], "sha256": p[2], "size": p[3].to_int(), "release": p[4]}
		if p[5] != "":
			e["inputs"] = p[5]
		if p[0] == "engine":
			e["godot"] = godot
			d["engine"] = e
		elif p[0] == "launcher":
			if p.size() < 7 or not p[6].is_valid_int() or p[6].to_int() < 1:
				printerr("[manifest] numéro du lanceur absent ou invalide")
				return {}
			e["version"] = p[6].to_int()
			d["launcher"] = e
		else:
			e["id"] = p[0]
			if p[0].begins_with("vox-"):
				e["lang"] = p[0].substr(4)
			if p[0] == "core":
				e["main"] = true
			(d.packs as Array).append(e)
	if not d.has("engine") or not d.has("launcher") or (d.packs as Array).is_empty():
		printerr("[manifest] entrées incomplètes (moteur, lanceur ou paquets manquants)")
		return {}
	return d


## Entrée `id` d'un manifeste (« engine », « launcher » ou un paquet), {} sans.
static func entry(d: Dictionary, id: String) -> Dictionary:
	if id == "engine" or id == "launcher":
		var e: Variant = d.get(id)
		return e if e is Dictionary else {}
	for p: Variant in d.get("packs", []):
		if p is Dictionary and p.get("id", "") == id:
			return p
	return {}


## Valeur d'un champ en texte (entiers sans « .0 »), "" si absent ou si ce
## n'est pas un texte ou un nombre. `id` vide : champ du manifeste lui-même
## (version, channel, build).
static func get_field(d: Dictionary, id: String, field: String) -> String:
	var e := d if id == "" else entry(d, id)
	if e.has(field) and not (e[field] is String or e[field] is float or e[field] is int):
		return ""
	if not e.has(field):
		return ""
	var v: Variant = e[field]
	return str(int(v)) if v is float else str(v)


## Même build et mêmes fichiers (qui restent dans la release de la snapshot) ;
## seuls le numéro et le canal changent. `launcher` : entrée ajoutée si la
## snapshot n'en a pas (sinon celle de la snapshot est gardée telle quelle).
static func promote(snap: Dictionary, version: String, launcher := {}) -> Dictionary:
	if not snap.has("engine"):
		return {}
	var d: Dictionary = _ints(snap.duplicate(true))
	d["promoted_from"] = snap.get("version", "")
	d["version"] = version
	d["channel"] = "stable"
	if not d.has("launcher"):
		if launcher.is_empty():
			return {}
		d["launcher"] = launcher
	return d


func _make(a: Dictionary) -> int:
	var d := make(FileAccess.get_file_as_string(a.get("make", "")), a.get("version", ""), a.get("channel", "snapshot"),
		a.get("build", ""), a.get("godot", ""))
	if d.is_empty():
		return 1
	_write(a.out, d)
	print("[manifest] %s (%s) : moteur %s, lanceur %d (%s), %d paquet(s)" % [d.version, d.channel, d.engine.file,
		d.launcher.version, d.launcher.release, d.packs.size()])
	return 0


func _get_field(a: Dictionary) -> int:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.get("get", "")))
	if not d is Dictionary:
		return 1
	var v := get_field(d, a.get("id", ""), a.get("field", ""))
	if v == "":
		return 1
	print("=" + v)
	return 0


func _promote(a: Dictionary) -> int:
	var snap: Variant = JSON.parse_string(FileAccess.get_file_as_string(a.promote))
	if not snap is Dictionary:
		return 1
	var launcher := {}
	if a.has("launcher"):
		launcher = _launcher_line(FileAccess.get_file_as_string(a.launcher))
	var d := promote(snap, a.get("version", ""), launcher)
	if d.is_empty():
		printerr("[manifest] promotion impossible (moteur ou lanceur manquant)")
		return 1
	_write(a.out, d)
	print("[manifest] %s promue en stable (%s), lanceur %d (%s)" % [d.promoted_from, d.version, d.launcher.version, d.launcher.release])
	return 0


## Entrée « launcher » d'une ligne TSV isolée, {} si invalide.
static func _launcher_line(tsv: String) -> Dictionary:
	for line in tsv.split("\n", false):
		var p := line.trim_suffix("\r").split("\t")
		if p.size() >= 7 and p[0] == "launcher" and p[6].is_valid_int() and p[6].to_int() >= 1:
			var e := {"file": p[1], "sha256": p[2], "size": p[3].to_int(), "release": p[4], "version": p[6].to_int()}
			if p[5] != "":
				e["inputs"] = p[5]
			return e
	return {}


func _write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ") + "\n")
	f.close()


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
