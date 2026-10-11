class_name CodexData
extends RefCounted
## Fiches du codex (bestiaire du hub, GAME_CONCEPT §4.17 ; HUB_PLAN §3.10),
## lues depuis assets/data/hub/codex.json (format « hub_codex »). Pur, sans
## interface. Une fiche invalide est ÉCARTÉE avec un avertissement (journal +
## `warnings`) ; un test vérifie que le fichier livré se charge sans aucun
## avertissement (tests/test_codex.gd).
##
## Fiche normalisée : {id (type d'ennemi de XpRules), name {fr, en}, text
## {fr, en}, round (manche d'apparition, ≥ 1), samples [sorte...], xp_ref
## (type de XpRules dont l'XP sert de référence tant que `id` n'a pas son
## propre barème ; "" : aucun), planned (ennemi prévu, pas encore en jeu)}.
## L'XP n'est JAMAIS écrite dans le fichier : elle se lit dans XpRules (xp()).

const PATH := "res://assets/data/hub/codex.json"
const FORMAT := "hub_codex"
const VERSION := 1
const MAX_BYTES := 1 << 20
const ROUND_MAX := 999
const SAMPLES_MAX := 6

static var _default: CodexData

## Fiches, dans l'ordre d'affichage.
var entries: Array[Dictionary] = []
var warnings: PackedStringArray = []
var _by_id := {}


## Fiches livrées (gardées en mémoire).
static func default() -> CodexData:
	if _default == null:
		_default = from_text(_read(PATH), PATH)
	return _default


static func clear_cache() -> void:
	_default = null


## Fiches lues depuis un texte JSON (tests). `name` : nom cité dans les
## avertissements.
static func from_text(text: String, name := "codex.json") -> CodexData:
	var d := CodexData.new()
	d._parse(text, name)
	return d


func entry(id: String) -> Dictionary:
	return _by_id.get(id, {})


func has(id: String) -> bool:
	return _by_id.has(id)


## Identifiants des fiches, dans l'ordre.
func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append(String(e.id))
	return out


## XP de base (manche 1) d'une élimination, lue dans XpRules : celle du type,
## sinon celle du type de référence `xp_ref` (ennemi pas encore au barème),
## sinon 0.
static func xp(e: Dictionary) -> int:
	var id := String(e.get("id", ""))
	if XpRules.is_enemy(id):
		return XpRules.base_xp(id)
	return XpRules.base_xp(String(e.get("xp_ref", "")))


## Nom d'une sorte d'échantillon (LootRules) ; "???" si le jeu ne la connaît
## pas encore (ennemi prévu).
static func sample_name(id: String) -> String:
	return LootRules.sample_name(id) if HubData.known_sample(id) else "???"


# --------------------------------------------------------------------------

static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


func _warn(msg: String) -> void:
	warnings.append(msg)
	push_warning("[CodexData] " + msg)


func _parse(text: String, name: String) -> void:
	if text.is_empty():
		_warn("%s : fichier absent ou vide" % name)
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		_warn("%s : JSON invalide ligne %d (%s)" % [name, json.get_error_line(), json.get_error_message()])
		return
	var doc: Variant = json.data
	if not doc is Dictionary or doc.get("format") != FORMAT:
		_warn("%s : format attendu « %s »" % [name, FORMAT])
		return
	var v: Variant = doc.get("version")
	if not (v is int or v is float) or not is_finite(float(v)) or int(v) < 1 or int(v) > VERSION:
		_warn("%s : version %s illisible par le jeu (%d)" % [name, str(v), VERSION])
		return
	var list: Variant = doc.get("enemies")
	if not list is Array:
		_warn("%s : liste « enemies » absente" % name)
		return
	for i in (list as Array).size():
		var where := "%s, fiche %d" % [name, i + 1]
		var e: Variant = list[i]
		if not e is Dictionary:
			_warn(where + " : pas un objet")
			continue
		var out := _entry(e, where)
		if not out.is_empty():
			entries.append(out)
			_by_id[out.id] = out


func _entry(e: Dictionary, where: String) -> Dictionary:
	var id := ProfileValues.clean_id(e.get("id"))
	if id == "":
		_warn(where + " : identifiant manquant ou invalide")
		return {}
	where += " (« %s »)" % id
	if _by_id.has(id):
		_warn(where + " : identifiant en double")
		return {}
	var out := {"id": id}
	for key in ["name", "text"]:
		var t: Variant = e.get(key)
		if not t is Dictionary or not t.get("fr") is String or not t.get("en") is String \
				or String(t.fr).strip_edges() == "" or String(t.en).strip_edges() == "":
			_warn(where + " : « %s » doit avoir un texte fr et en" % key)
			return {}
		out[key] = {"fr": String(t.fr), "en": String(t.en)}
	var r: Variant = e.get("round")
	if not (r is int or r is float) or not is_finite(float(r)) or int(r) < 1 or int(r) > ROUND_MAX:
		_warn(where + " : manche d'apparition hors 1 à %d" % ROUND_MAX)
		return {}
	out.round = int(r)
	var sm: Variant = e.get("samples", [])
	if not sm is Array or (sm as Array).size() > SAMPLES_MAX:
		_warn(where + " : « samples » doit être une liste de %d sortes au plus" % SAMPLES_MAX)
		return {}
	var samples := PackedStringArray()
	for s in sm:
		var sid := ProfileValues.clean_id(s)
		if sid == "" or sid in samples:
			_warn(where + " : sorte d'échantillon invalide ou en double (%s)" % str(s))
			return {}
		samples.append(sid)
	out.samples = samples
	var ref: Variant = e.get("xp_ref", "")
	if not ref is String or (String(ref) != "" and not XpRules.is_enemy(String(ref))):
		_warn(where + " : « xp_ref » doit être un type de XpRules")
		return {}
	out.xp_ref = String(ref)
	if not XpRules.is_enemy(id) and out.xp_ref == "":
		_warn(where + " : type absent de XpRules sans « xp_ref »")
		return {}
	var p: Variant = e.get("planned", false)
	if not p is bool:
		_warn(where + " : « planned » doit être vrai ou faux")
		return {}
	out.planned = p
	return out
