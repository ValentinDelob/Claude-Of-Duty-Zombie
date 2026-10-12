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
## propre barème ; "" : aucun), planned (ennemi prévu, pas encore en jeu),
## weak, tip (facultatifs, {fr, en} ou {} : point faible et conseil de la
## page DÉTAILS du codex, CodexDetails ; jamais de chiffre dedans)}.
## L'XP n'est JAMAIS écrite dans le fichier : elle se lit dans XpRules (xp()).
##
## Groupes facultatifs (« groups », hub v2, docs/hub_v2/Codex.dc.html) :
## plusieurs fiches montrées comme UNE carte au bestiaire (« Les zombies » :
## marcheur, rampant, coureur, sprinteur) : {id, name {fr, en}, text {fr, en},
## members [id de fiche...]}. Les fiches gardent leurs données (éliminations,
## rencontres et pastille NOUVEAU par type) ; cards() rend les cartes.

const PATH := "res://assets/data/hub/codex.json"
const FORMAT := "hub_codex"
const VERSION := 1
const MAX_BYTES := 1 << 20
const ROUND_MAX := 999
const SAMPLES_MAX := 6
const MEMBERS_MAX := 16

static var _default: CodexData

## Fiches, dans l'ordre d'affichage.
var entries: Array[Dictionary] = []
## Groupes de fiches (une carte du bestiaire chacun) : {id, name, text,
## members}.
var groups: Array[Dictionary] = []
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


## « ZOMBIE · DÈS LA MANCHE 4 » : famille (catégorie de XpRules) et manche
## d'apparition (langue du jeu).
static func family_line(e: Dictionary) -> String:
	var id := String(e.get("id", ""))
	var cat := XpRules.category_of(id) if XpRules.is_enemy(id) else XpRules.category_of(String(e.get("xp_ref", "")))
	var fam := "ZOMBIE"
	match cat:
		XpRules.SPECIAL:
			fam = Lang.t("VAGUE SPÉCIALE", "SPECIAL WAVE")
		XpRules.MINIBOSS:
			fam = "MINI-BOSS"
		XpRules.BOSS:
			fam = "BOSS"
	return fam + " · " + Lang.t("DÈS LA MANCHE %d", "FROM ROUND %d") % int(e.get("round", 1))


## Cartes du bestiaire (hub v2) : un groupe = une carte (à la place de la
## première de ses fiches), toute autre fiche = sa propre carte ; triées par
## manche d'apparition (ordre du fichier à égalité). Carte : {id, members
## [ids], name, text, round (la plus petite), samples (réunis), category
## (XpRules, celle de la première fiche), xp_min, xp_max (XpRules), weak, tip
## (du groupe ou de la fiche, {} si absents)}.
func cards() -> Array[Dictionary]:
	var in_group := {}
	for g in groups:
		for m in g.members:
			in_group[m] = g
	var out: Array[Dictionary] = []
	var done := {}
	for e in entries:
		var g: Dictionary = in_group.get(e.id, {})
		if g.is_empty():
			out.append(_card(e.id, [e], e.name, e.text, e))
		elif not done.has(g.id):
			done[g.id] = true
			var list: Array = []
			for m in g.members:
				list.append(_by_id[m])
			out.append(_card(g.id, list, g.name, g.text, g))
	for i in out.size():
		out[i]["order"] = i
	out.sort_custom(func(a, b): return a.round < b.round or (a.round == b.round and a.order < b.order))
	return out


func _card(id: String, list: Array, name: Dictionary, text: Dictionary, src: Dictionary) -> Dictionary:
	var members := PackedStringArray()
	var samples := PackedStringArray()
	var r := ROUND_MAX
	var xmin := -1
	var xmax := 0
	for e in list:
		members.append(String(e.id))
		r = mini(r, int(e.round))
		for s in e.samples:
			if not s in samples:
				samples.append(s)
		var x := xp(e)
		xmin = x if xmin < 0 else mini(xmin, x)
		xmax = maxi(xmax, x)
	return {"id": id, "members": members, "name": name, "text": text, "round": r, "samples": samples,
		"category": category(list[0]), "xp_min": maxi(xmin, 0), "xp_max": xmax,
		"weak": src.get("weak", {}), "tip": src.get("tip", {})}


## Texte facultatif {fr, en} de la clé `key` de `e` : {} s'il est absent ;
## illisible : {} et avertissement (la fiche reste).
func _optional_text(e: Dictionary, key: String, where: String) -> Dictionary:
	if not e.has(key):
		return {}
	var t: Variant = e.get(key)
	if not t is Dictionary or not t.get("fr") is String or not t.get("en") is String \
			or String(t.fr).strip_edges() == "" or String(t.en).strip_edges() == "":
		_warn(where + " : « %s » doit avoir un texte fr et en (ignoré)" % key)
		return {}
	return {"fr": String(t.fr), "en": String(t.en)}


## Catégorie de XpRules d'une fiche (celle de `xp_ref` pour un ennemi prévu).
static func category(e: Dictionary) -> String:
	var id := String(e.get("id", ""))
	return XpRules.category_of(id) if XpRules.is_enemy(id) else XpRules.category_of(String(e.get("xp_ref", "")))


## Fiche qui porte la sorte d'échantillon `sample` (vide : aucune).
func entry_of_sample(sample: String) -> Dictionary:
	for e in entries:
		if sample in e.samples:
			return e
	return {}


## Indice d'une fiche inconnue : « Peut apparaître dès la manche 20 ».
static func round_hint(round_n: int) -> String:
	if round_n <= 1:
		return Lang.t("Rôde dès la première manche", "Lurks from the very first round")
	return Lang.t("Peut apparaître dès la manche %d", "May appear from round %d") % round_n


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
	var gl: Variant = doc.get("groups", [])
	if not gl is Array:
		_warn("%s : « groups » doit être une liste" % name)
		return
	var used := {}
	for i in (gl as Array).size():
		var g: Variant = gl[i]
		var where := "%s, groupe %d" % [name, i + 1]
		if not g is Dictionary:
			_warn(where + " : pas un objet")
			continue
		var out := _group(g, where, used)
		if not out.is_empty():
			groups.append(out)
			for m in out.members:
				used[m] = true
			used["#" + out.id] = true


## Groupe de fiches validé ({} et avertissement sinon) : identifiant propre
## (ni fiche ni autre groupe), noms et textes FR / EN, au moins deux fiches
## existantes, chacune dans un seul groupe.
func _group(g: Dictionary, where: String, used: Dictionary) -> Dictionary:
	var id := ProfileValues.clean_id(g.get("id"))
	if id == "" or _by_id.has(id) or used.has("#" + id):
		_warn(where + " : identifiant manquant, invalide ou déjà pris")
		return {}
	where += " (« %s »)" % id
	var out := {"id": id}
	for key in ["name", "text"]:
		var t: Variant = g.get(key)
		if not t is Dictionary or not t.get("fr") is String or not t.get("en") is String \
				or String(t.fr).strip_edges() == "" or String(t.en).strip_edges() == "":
			_warn(where + " : « %s » doit avoir un texte fr et en" % key)
			return {}
		out[key] = {"fr": String(t.fr), "en": String(t.en)}
	var ms: Variant = g.get("members")
	if not ms is Array or (ms as Array).size() < 2 or (ms as Array).size() > MEMBERS_MAX:
		_warn(where + " : « members » doit lister de 2 à %d fiches" % MEMBERS_MAX)
		return {}
	var members := PackedStringArray()
	for m in ms:
		var mid := ProfileValues.clean_id(m)
		if mid == "" or not _by_id.has(mid) or mid in members or used.has(mid):
			_warn(where + " : fiche inconnue, en double ou déjà groupée (%s)" % str(m))
			return {}
		members.append(mid)
	out.members = members
	out.weak = _optional_text(g, "weak", where)
	out.tip = _optional_text(g, "tip", where)
	return out


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
	out.weak = _optional_text(e, "weak", where)
	out.tip = _optional_text(e, "tip", where)
	return out
