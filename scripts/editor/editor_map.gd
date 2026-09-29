class_name EditorMap
extends RefCounted
## Carte de l'éditeur (docs/MAP_AUTHORING.md) : cinq fichiers JSON lisibles et
## écrivables à la main, dans un dossier (user://maps/<id>/) ou une archive
## .zip. Coordonnées en mètres (x vers l'est, y vers le sud), identifiants
## stables pour chaque élément.
##   carte.json       id, noms FR/EN, description, musique, version du format, étages
##   pieces.json      pièces (contour, étage, zone, hauteur de plafond...)
##   ouvertures.json  portes, débris, portes du courant, passages, fenêtres
##   objets.json      tout le reste (murs, piliers, escaliers, atouts, armes, boîte...)
##   zones.json       zones (noms FR/EN, matériaux) et zone de départ

const FORMAT := 1
const FILES := ["carte.json", "pieces.json", "ouvertures.json", "objets.json", "zones.json"]
const DEFAULT_CEILING := 3.2
const FLOOR_STEP := 3.5
## Exemple livré avec le jeu (lecture seule : « Enregistrer » en fait une copie).
const EXAMPLES := {"draft_arena": "res://assets/maps/draft_arena/"}

var carte: Dictionary = {}
var pieces: Array = []
var ouvertures: Array = []
var objets: Array = []
var zones: Array = []
var depart := ""
## Problèmes de lecture (fichier absent, JSON illisible...) : [fr, en].
var load_errors: Array = []


static func blank(map_id := "nouvelle_carte", name_fr := "NOUVELLE CARTE", name_en := "NEW MAP") -> EditorMap:
	var m := EditorMap.new()
	m.carte = {"format": FORMAT, "id": map_id, "nom": {"fr": name_fr, "en": name_en},
		"description": {"fr": "", "en": ""}, "musique": "ambience_bunker", "hauteur_portes": 2.5,
		"lampes_auto": true, "etages": [{"sol": 0.0, "hauteur": DEFAULT_CEILING}]}
	return m


# ------------------------------------------------------------------ accès

func id() -> String:
	return String(carte.get("id", "carte"))


func display_name() -> String:
	var n: Dictionary = carte.get("nom", {})
	return Lang.t(String(n.get("fr", id())), String(n.get("en", n.get("fr", id()))))


func floors() -> Array:
	return carte.get("etages", [])


func floor_count() -> int:
	return maxi(1, floors().size())


func floor_sol(k: int) -> float:
	var f: Array = floors()
	return float(f[k].get("sol", k * FLOOR_STEP)) if k < f.size() else k * FLOOR_STEP


func floor_height(k: int) -> float:
	var f: Array = floors()
	return float(f[k].get("hauteur", DEFAULT_CEILING)) if k < f.size() else DEFAULT_CEILING


func find(eid: String) -> Dictionary:
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			if String(e.get("id", "")) == eid:
				return e
	return {}


## Liste qui contient l'élément `eid` (pieces, ouvertures, objets ou zones).
func list_of(eid: String) -> Array:
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			if String(e.get("id", "")) == eid:
				return list
	return []


func remove(eid: String) -> void:
	var list := list_of(eid)
	for i in list.size():
		if String(list[i].get("id", "")) == eid:
			list.remove_at(i)
			return


func rooms_on(k: int) -> Array:
	return pieces.filter(func(p): return int(p.get("etage", 0)) == k)


func openings_on(k: int) -> Array:
	return ouvertures.filter(func(o): return int(o.get("etage", 0)) == k)


func objects_on(k: int) -> Array:
	return objets.filter(func(o): return int(o.get("etage", 0)) == k)


func zone(zid: String) -> Dictionary:
	for z in zones:
		if String(z.id) == zid:
			return z
	return {}


func zone_name(zid: String) -> String:
	var z := zone(zid)
	if z.is_empty():
		return zid
	var n: Dictionary = z.get("nom", {})
	return Lang.t(String(n.get("fr", zid)), String(n.get("en", n.get("fr", zid))))


func rooms_of_zone(zid: String) -> Array:
	return pieces.filter(func(p): return String(p.get("zone", "")) == zid)


func room_poly(p: Dictionary) -> PackedVector2Array:
	return MapGeom.poly(p.get("contour", []))


## Nouvel identifiant stable : préfixe + premier numéro libre.
func new_id(prefix: String) -> String:
	var used := {}
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			used[String(e.get("id", ""))] = true
	var n := 1
	while used.has("%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]


## Nouvelle zone (nom par défaut « Zone N »).
func add_zone(name_fr := "", name_en := "") -> Dictionary:
	var zid := new_id("z")
	var n := zones.size() + 1
	var z := {"id": zid, "nom": {"fr": name_fr if name_fr != "" else "Zone %d" % n, "en": name_en if name_en != "" else "Zone %d" % n}}
	zones.append(z)
	if depart == "":
		depart = zid
	return z


## Zones sans pièce retirées, zone de départ toujours valide.
func tidy_zones() -> void:
	var used := {}
	for p in pieces:
		used[String(p.get("zone", ""))] = true
	zones = zones.filter(func(z): return used.has(String(z.id)))
	if zone(depart).is_empty():
		depart = String(zones[0].id) if not zones.is_empty() else ""


# ------------------------------------------------------------------ copie (annuler / rétablir)

func to_dict() -> Dictionary:
	return {"carte": carte, "pieces": pieces, "ouvertures": ouvertures, "objets": objets, "zones": zones, "depart": depart}


func snapshot() -> Dictionary:
	return to_dict().duplicate(true)


func restore(s: Dictionary) -> void:
	var d := s.duplicate(true)
	carte = d.get("carte", {})
	pieces = d.get("pieces", [])
	ouvertures = d.get("ouvertures", [])
	objets = d.get("objets", [])
	zones = d.get("zones", [])
	depart = String(d.get("depart", ""))


func duplicate_map() -> EditorMap:
	var m := EditorMap.new()
	m.restore(snapshot())
	return m


## Deux cartes identiques (contenu des cinq fichiers) ?
func same_as(other: EditorMap) -> bool:
	return file_texts() == other.file_texts()


# ------------------------------------------------------------------ fichiers

## Contenu des cinq fichiers (JSON lisible : un élément par ligne). Les
## nombres entiers s'écrivent sans décimale (17 et non 17.0) : un fichier relu
## puis réenregistré est identique.
func file_texts() -> Dictionary:
	var c := carte.duplicate(true)
	c["format"] = FORMAT
	return {
		"carte.json": dump(_ints(c)),
		"pieces.json": dump(_ints({"pieces": pieces})),
		"ouvertures.json": dump(_ints({"ouvertures": ouvertures})),
		"objets.json": dump(_ints({"objets": objets})),
		"zones.json": dump(_ints({"depart": depart, "zones": zones})),
	}


static func _ints(v: Variant) -> Variant:
	if v is float:
		var f: float = v
		return int(f) if f == floorf(f) and absf(f) < 1e12 else snappedf(f, 0.0001)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x): return _ints(x))
	return v


static func from_texts(texts: Dictionary) -> EditorMap:
	var m := EditorMap.new()
	var parsed := {}
	for f in FILES:
		if not texts.has(f):
			m.load_errors.append(["fichier %s absent" % f, "missing file %s" % f])
			parsed[f] = {}
			continue
		var j := JSON.new()
		if j.parse(String(texts[f])) != OK or not j.data is Dictionary:
			m.load_errors.append(["%s illisible (ligne %d : %s)" % [f, j.get_error_line(), j.get_error_message()],
				"%s unreadable (line %d: %s)" % [f, j.get_error_line(), j.get_error_message()]])
			parsed[f] = {}
			continue
		parsed[f] = j.data
	m.carte = parsed["carte.json"]
	if m.carte.is_empty():
		m.carte = blank().carte
	if int(m.carte.get("format", FORMAT)) > FORMAT:
		m.load_errors.append(["format %d plus récent que celui du jeu (%d)" % [int(m.carte.format), FORMAT],
			"format %d is newer than the game's (%d)" % [int(m.carte.format), FORMAT]])
	m.pieces = parsed["pieces.json"].get("pieces", [])
	m.ouvertures = parsed["ouvertures.json"].get("ouvertures", [])
	m.objets = parsed["objets.json"].get("objets", [])
	m.zones = parsed["zones.json"].get("zones", [])
	m.depart = String(parsed["zones.json"].get("depart", ""))
	m._normalize()
	return m


## Valeurs lues du JSON remises au bon type (étages entiers, identifiants en texte).
func _normalize() -> void:
	for list in [pieces, ouvertures, objets]:
		for e in list:
			e["id"] = String(e.get("id", ""))
			e["etage"] = int(e.get("etage", 0))
	for list in [pieces, ouvertures, objets, zones]:
		for e in list:
			if String(e.get("id", "")) == "":
				e["id"] = new_id("x")
	if floors().is_empty():
		carte["etages"] = [{"sol": 0.0, "hauteur": DEFAULT_CEILING}]
	if zone(depart).is_empty() and not zones.is_empty():
		depart = String(zones[0].id)


func save_dir(dir: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and not DirAccess.dir_exists_absolute(dir):
		return err
	var texts := file_texts()
	for f in texts:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		if fa == null:
			return FileAccess.get_open_error()
		fa.store_string(texts[f])
		fa.close()
	return OK


static func load_dir(dir: String) -> EditorMap:
	var texts := {}
	for f in FILES:
		var p := dir.path_join(f)
		if FileAccess.file_exists(p):
			texts[f] = FileAccess.get_file_as_string(p)
	return from_texts(texts)


static func is_map_dir(dir: String) -> bool:
	return FileAccess.file_exists(dir.path_join("carte.json"))


## Archive .zip : les cinq fichiers à la racine.
func export_zip(path: String) -> Error:
	var z := ZIPPacker.new()
	var err := z.open(path)
	if err != OK:
		return err
	var texts := file_texts()
	for f in FILES:
		z.start_file(f)
		z.write_file(String(texts[f]).to_utf8_buffer())
		z.close_file()
	return z.close()


static func import_zip(path: String) -> EditorMap:
	var r := ZIPReader.new()
	if r.open(path) != OK:
		var m := EditorMap.new()
		m.load_errors.append(["archive illisible : %s" % path, "unreadable archive: %s" % path])
		return m
	var texts := {}
	for f in r.get_files():
		# Fichiers à la racine ou dans un dossier de l'archive.
		var base := String(f).get_file()
		if base in FILES and not texts.has(base):
			texts[base] = r.read_file(f).get_string_from_utf8()
	r.close()
	return from_texts(texts)


## JSON lisible dans un diff : une entrée (pièce, porte, objet...) par ligne.
static func dump(v: Variant, depth := 0) -> String:
	var pad := " ".repeat(depth + 1)
	if v is Dictionary and depth < 2:
		var parts := PackedStringArray()
		for k in v:
			parts.append("%s%s: %s" % [pad, JSON.stringify(String(k)), dump(v[k], depth + 1)])
		return "{\n%s\n%s}" % [",\n".join(parts), " ".repeat(depth)] if not parts.is_empty() else "{}"
	if v is Array and depth < 2 and not v.is_empty() and (v[0] is Dictionary or v[0] is Array):
		var parts := PackedStringArray()
		for e in v:
			parts.append(pad + JSON.stringify(e, "", false))
		return "[\n%s\n%s]" % [",\n".join(parts), " ".repeat(depth)]
	return JSON.stringify(v, "", false)


# ------------------------------------------------------------------ emplacements

## Dossier des cartes du joueur (user://maps ; en autotest, un dossier de
## tests/_out propre au scénario : jamais les cartes du joueur).
static var root_override := ""


static func maps_root() -> String:
	if root_override != "":
		return root_override
	var at: Node = Engine.get_main_loop().root.get_node_or_null("/root/Autotest") if Engine.get_main_loop() is SceneTree else null
	if at != null and at.active:
		return ProjectSettings.globalize_path("res://tests/_out/editor_maps_%s" % at.scenario_name)
	return "user://maps"


static func map_dir(map_id: String) -> String:
	return maps_root().path_join(map_id)


## Cartes enregistrées : [{id, dir, name}], triées par nom.
static func list_maps() -> Array:
	var out := []
	var root := maps_root()
	if DirAccess.dir_exists_absolute(root):
		for d in DirAccess.get_directories_at(root):
			if d.begins_with("_"):
				continue
			var dir := root.path_join(d)
			if not is_map_dir(dir):
				continue
			var c = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("carte.json")))
			var n: Dictionary = c.get("nom", {}) if c is Dictionary else {}
			out.append({"id": d, "dir": dir, "name": Lang.t(String(n.get("fr", d)), String(n.get("en", n.get("fr", d))))})
	out.sort_custom(func(a, b): return a.name < b.name)
	return out


## Identifiant de dossier tiré d'un nom (minuscules, chiffres et _).
static func slug(s: String) -> String:
	var t := s.strip_edges().to_lower()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ï", "i"],
			["ô", "o"], ["û", "u"], ["ù", "u"], ["ç", "c"]]:
		t = t.replace(pair[0], pair[1])
	var out := ""
	for ch in t:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	return out if out != "" else "carte"
