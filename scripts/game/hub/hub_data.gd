class_name HubData
extends RefCounted
## Contrats et catalogue d'échanges du scientifique, lus depuis les fichiers
## de données (docs/HUB_PLAN.md §5.1, §5.5, §6) :
##   assets/data/hub/contracts.json (format « hub_contracts »)
##   assets/data/hub/exchanges.json (format « hub_exchanges »)
## Pur, sans interface. Chaque entrée invalide est ÉCARTÉE avec un
## avertissement (journal + `warnings`) : le reste du fichier reste utilisable.
## Un test vérifie que les fichiers livrés se chargent sans aucun
## avertissement (tests/test_hub_data.gd).
##
## Entrées normalisées (dictionnaires, champs toujours présents) :
## * contrat : {id, title {fr, en}, text {fr, en}, thanks ({fr, en} ou {}),
##   samples {sorte: n}, xp, reward, min_level, max_level, starts, ends
##   (jour UTC, nombre de jours depuis le 1/1/1970, -1 : sans date), repeatable,
##   weight, after [ids], tutorial} ;
## * échange : {id, title, text ({} si absent), samples, reward, min_level,
##   starts, ends, limit} ;
## * récompense : {"kind": "weapon", "weapon": "any" ou id, "rarity": clé},
##   {"kind": "part", "quality": clé} (contrats), {"kind": "part", "mods":
##   {stat: valeur}} (échanges), {"kind": "none"} (contrats).

const CONTRACTS_PATH := "res://assets/data/hub/contracts.json"
const EXCHANGES_PATH := "res://assets/data/hub/exchanges.json"
const CONTRACTS_FORMAT := "hub_contracts"
const EXCHANGES_FORMAT := "hub_exchanges"
## Version du format des fichiers lue par le jeu (une version plus récente
## est refusée en entier).
const VERSION := 1
## Taille maximale d'un fichier de données (octets).
const MAX_BYTES := 4 << 20
## Bornes des champs (§5.1, §6).
const MAX_ID_LEN := 64
const SAMPLE_MIN := 1
const SAMPLE_MAX := 999
const XP_MAX := 1000000
const WEIGHT_MAX := 1000.0
const LIMIT_MAX := 1000000
const MOD_MIN := 0.01
const MOD_MAX := 0.5
## Qualités des pièces offertes par un contrat (§5.1, D11) : [FR, EN].
const QUALITIES := {
	"standard": ["ORDINAIRE", "STANDARD"],
	"fine": ["SOIGNÉE", "FINE"],
	"superior": ["D'EXCEPTION", "SUPERIOR"],
}
## Règles du tableau par défaut (§5.1), remplacées par la section « rules ».
const DEFAULT_RULES := {
	"offers": 5,
	"active_max": 3,
	"replace_per_match": 1,
	"min_rounds_for_rotation": 1,
	"xp_level_factor": 0.02,
}
## Bornes des règles [min, max].
const RULE_RANGES := {
	"offers": [1, 20],
	"active_max": [1, 10],
	"replace_per_match": [0, 20],
	"min_rounds_for_rotation": [0, 1000],
	"xp_level_factor": [0.0, 1.0],
}

## Règles du tableau des contrats (DEFAULT_RULES complétées par le fichier).
var rules: Dictionary = DEFAULT_RULES.duplicate()
## Contrats valides, dans l'ordre du fichier (ordre du tirage : reproductible).
var contracts: Array[Dictionary] = []
## Échanges valides, dans l'ordre du fichier (ordre d'affichage).
var exchanges: Array[Dictionary] = []
## Avertissements du chargement (un par entrée ou section écartée).
var warnings: PackedStringArray = []

var _contract_by_id := {}
var _exchange_by_id := {}

## Données livrées, chargées une fois (default()).
static var _default: HubData


## Données des fichiers livrés (chargées au premier appel, puis gardées).
static func default() -> HubData:
	if _default == null:
		_default = load_files(CONTRACTS_PATH, EXCHANGES_PATH)
	return _default


## Oublie les données gardées (tests ; fichiers modifiés).
static func clear_cache() -> void:
	_default = null


## Lit les deux fichiers. Un fichier absent ou illisible donne un
## avertissement et une liste vide (le jeu continue sans contrats).
static func load_files(contracts_path: String, exchanges_path: String) -> HubData:
	return from_texts(_read(contracts_path), _read(exchanges_path), contracts_path, exchanges_path)


## Lit les deux fichiers depuis leur texte (tests). `*_name` : nom cité dans
## les avertissements.
static func from_texts(contracts_text: String, exchanges_text: String,
		contracts_name := "contracts.json", exchanges_name := "exchanges.json") -> HubData:
	var d := HubData.new()
	var cdoc: Variant = d._parse_doc(contracts_text, CONTRACTS_FORMAT, contracts_name)
	if cdoc is Dictionary:
		d._read_rules(cdoc.get("rules"), contracts_name)
		d._read_contracts(cdoc.get("contracts"), contracts_name)
	var edoc: Variant = d._parse_doc(exchanges_text, EXCHANGES_FORMAT, exchanges_name)
	if edoc is Dictionary:
		d._read_exchanges(edoc.get("exchanges"), exchanges_name)
	return d


func contract(id: String) -> Dictionary:
	return _contract_by_id.get(id, {})


func has_contract(id: String) -> bool:
	return _contract_by_id.has(id)


func exchange(id: String) -> Dictionary:
	return _exchange_by_id.get(id, {})


func has_exchange(id: String) -> bool:
	return _exchange_by_id.has(id)


## Texte d'un champ {fr, en} dans la langue du jeu.
static func text_of(t: Variant) -> String:
	if not t is Dictionary or t.is_empty():
		return ""
	return Lang.t(String(t.get("fr", "")), String(t.get("en", "")))


## Nom affiché d'une qualité de pièce (clé brute si inconnue).
static func quality_name(q: String) -> String:
	var n: Array = QUALITIES.get(q, [q, q])
	return Lang.t(n[0], n[1])


# --------------------------------------------------------------------------
# Dates (UTC)
# --------------------------------------------------------------------------

## Jour UTC d'aujourd'hui (jours depuis le 1/1/1970).
static func today() -> int:
	return floori(Time.get_unix_time_from_system() / 86400.0)


## Jour UTC d'une date « AAAA-MM-JJ » ; -1 si illisible ou inexistante
## (2026-02-30 refusée).
static func parse_day(v: Variant) -> int:
	if not v is String:
		return -1
	var s: String = v
	if s.length() != 10 or s[4] != "-" or s[7] != "-":
		return -1
	var y := s.substr(0, 4)
	var m := s.substr(5, 2)
	var dd := s.substr(8, 2)
	if not (y.is_valid_int() and m.is_valid_int() and dd.is_valid_int()) or "+" in s or y.begins_with("-"):
		return -1
	var dict := {"year": y.to_int(), "month": m.to_int(), "day": dd.to_int(), "hour": 0, "minute": 0, "second": 0}
	if dict.month < 1 or dict.month > 12 or dict.year < 1970 or dict.year > 9999:
		return -1
	# Date inexistante (31 avril, 29 février d'une année non bissextile) :
	# refusée ici, avant Godot (qui l'écrirait en erreur dans le journal).
	var leap: bool = dict.year % 4 == 0 and (dict.year % 100 != 0 or dict.year % 400 == 0)
	var month_days := [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if dict.day < 1 or dict.day > month_days[dict.month - 1]:
		return -1
	var unix := Time.get_unix_time_from_datetime_dict(dict)
	if Time.get_date_string_from_unix_time(unix) != s:
		return -1
	return floori(unix / 86400.0)


## Date « AAAA-MM-JJ » d'un jour UTC.
static func day_string(day: int) -> String:
	return Time.get_date_string_from_unix_time(day * 86400)


# --------------------------------------------------------------------------
# Lecture (interne)
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
	push_warning("[HubData] " + msg)


## Document JSON du bon format et d'une version lisible, sinon null (avec
## avertissement).
func _parse_doc(text: String, format: String, name: String) -> Variant:
	if text.is_empty():
		_warn("%s : fichier absent ou vide" % name)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		_warn("%s : JSON invalide ligne %d (%s)" % [name, json.get_error_line(), json.get_error_message()])
		return null
	var doc: Variant = json.data
	if not doc is Dictionary or doc.get("format") != format:
		_warn("%s : format attendu « %s »" % [name, format])
		return null
	var v: Variant = doc.get("version")
	if not (v is int or v is float) or not is_finite(float(v)) or int(v) < 1 or int(v) > VERSION:
		_warn("%s : version %s illisible par le jeu (%d)" % [name, str(v), VERSION])
		return null
	return doc


func _read_rules(r: Variant, name: String) -> void:
	if r == null:
		return
	if not r is Dictionary:
		_warn("%s : section « rules » invalide, règles par défaut" % name)
		return
	for k in r:
		if not RULE_RANGES.has(k):
			_warn("%s : règle inconnue « %s » ignorée" % [name, str(k)])
			continue
		var v: Variant = r[k]
		var lo: float = RULE_RANGES[k][0]
		var hi: float = RULE_RANGES[k][1]
		var is_float: bool = DEFAULT_RULES[k] is float
		if not (v is int or v is float) or not is_finite(float(v)) or float(v) < lo or float(v) > hi \
				or (not is_float and float(v) != floorf(float(v))):
			_warn("%s : règle « %s » hors bornes (%s), valeur par défaut" % [name, k, str(v)])
			continue
		rules[k] = float(v) if is_float else int(v)


func _read_contracts(list: Variant, name: String) -> void:
	if not list is Array:
		_warn("%s : liste « contracts » absente" % name)
		return
	var pending: Array[Dictionary] = []
	var ids := {}
	for i in list.size():
		var e: Variant = list[i]
		var where := "%s, contrat n° %d" % [name, i + 1]
		if not e is Dictionary:
			_warn(where + " : entrée invalide")
			continue
		var c := _contract(e, where, ids)
		if not c.is_empty():
			ids[c.id] = true
			pending.append(c)
	# `after` : seulement vers des contrats valides du fichier. Répété tant
	# qu'un contrat est écarté (un écart peut en entraîner un autre).
	var changed := true
	while changed:
		changed = false
		var kept: Array[Dictionary] = []
		var kept_ids := {}
		for c in pending:
			kept_ids[c.id] = true
		for c in pending:
			var bad := ""
			for a in c.after:
				if not kept_ids.has(a) or a == c.id:
					bad = a
					break
			if bad != "":
				_warn("%s, contrat « %s » : « after » vers un contrat inconnu ou écarté (« %s »)" % [name, c.id, bad])
				changed = true
			else:
				kept.append(c)
		pending = kept
	for c in pending:
		contracts.append(c)
		_contract_by_id[c.id] = c


func _contract(e: Dictionary, where: String, ids: Dictionary) -> Dictionary:
	var id := _id(e.get("id"), where, ids)
	if id == "":
		return {}
	where = "%s (« %s »)" % [where, id]
	var c := {"id": id}
	for k in ["title", "text"]:
		c[k] = _text(e.get(k), where, k, true)
		if c[k].is_empty():
			return {}
	c.thanks = _text(e.get("thanks"), where, "thanks", false)
	if e.get("thanks") != null and c.thanks.is_empty():
		return {}
	c.samples = _samples(e.get("samples"), where)
	if c.samples.is_empty():
		return {}
	var xp := _int(e.get("xp"), -1, 0, XP_MAX)
	if xp < 0:
		_warn(where + " : « xp » absent ou hors 0 à %d" % XP_MAX)
		return {}
	c.xp = xp
	c.reward = _reward(e.get("reward"), where, false)
	if c.reward.is_empty():
		return {}
	if not _levels(e, c, where):
		return {}
	if not _dates(e, c, where):
		return {}
	c.repeatable = _bool(e.get("repeatable"), true, where, "repeatable")
	c.tutorial = _bool(e.get("tutorial"), false, where, "tutorial")
	if c.repeatable == null or c.tutorial == null:
		return {}
	var w: Variant = e.get("weight", 1.0)
	if w == null:
		w = 1.0
	if not (w is int or w is float) or not is_finite(float(w)) or float(w) < 0.0 or float(w) > WEIGHT_MAX:
		_warn(where + " : « weight » hors 0 à %d" % int(WEIGHT_MAX))
		return {}
	c.weight = float(w)
	var after: Variant = e.get("after", [])
	if after == null:
		after = []
	if not after is Array:
		_warn(where + " : « after » doit être une liste")
		return {}
	var al := PackedStringArray()
	for a in after:
		if not a is String or not _id_ok(a):
			_warn(where + " : « after » invalide (%s)" % str(a))
			return {}
		if not a in al:
			al.append(a)
	c.after = al
	return c


func _read_exchanges(list: Variant, name: String) -> void:
	if not list is Array:
		_warn("%s : liste « exchanges » absente" % name)
		return
	var ids := {}
	for i in list.size():
		var e: Variant = list[i]
		var where := "%s, échange n° %d" % [name, i + 1]
		if not e is Dictionary:
			_warn(where + " : entrée invalide")
			continue
		var x := _exchange(e, where, ids)
		if not x.is_empty():
			ids[x.id] = true
			exchanges.append(x)
			_exchange_by_id[x.id] = x


func _exchange(e: Dictionary, where: String, ids: Dictionary) -> Dictionary:
	var id := _id(e.get("id"), where, ids)
	if id == "":
		return {}
	where = "%s (« %s »)" % [where, id]
	var x := {"id": id}
	x.title = _text(e.get("title"), where, "title", true)
	if x.title.is_empty():
		return {}
	x.text = _text(e.get("text"), where, "text", false)
	if e.get("text") != null and x.text.is_empty():
		return {}
	x.samples = _samples(e.get("samples"), where)
	if x.samples.is_empty():
		return {}
	x.reward = _reward(e.get("reward"), where, true)
	if x.reward.is_empty():
		return {}
	if not _levels(e, x, where):
		return {}
	x.erase("max_level")
	if not _dates(e, x, where):
		return {}
	var lim := _int(e.get("limit", 0) if e.get("limit") != null else 0, -1, 0, LIMIT_MAX)
	if lim < 0:
		_warn(where + " : « limit » hors 0 à %d" % LIMIT_MAX)
		return {}
	x.limit = lim
	return x


## Identifiant [a-z0-9_], 64 caractères au plus, unique ; "" (avertissement) sinon.
func _id(v: Variant, where: String, ids: Dictionary) -> String:
	if not v is String or not _id_ok(v):
		_warn(where + " : « id » absent ou invalide (%s)" % str(v))
		return ""
	if ids.has(v):
		_warn(where + " : « id » en double (« %s »)" % v)
		return ""
	return v


static func _id_ok(s: String) -> bool:
	if s.is_empty() or s.length() > MAX_ID_LEN:
		return false
	for ch in s:
		if not (ch >= "a" and ch <= "z" or ch >= "0" and ch <= "9" or ch == "_"):
			return false
	return true


## Texte {fr, en} (les deux langues, non vides) ; {} (avertissement si
## `required` ou si la valeur est présente mais invalide) sinon.
func _text(v: Variant, where: String, key: String, required: bool) -> Dictionary:
	if v == null:
		if required:
			_warn(where + " : « %s » absent" % key)
		return {}
	if not v is Dictionary:
		_warn(where + " : « %s » doit être {\"fr\", \"en\"}" % key)
		return {}
	var out := {}
	for lang in ["fr", "en"]:
		var t: Variant = v.get(lang)
		if not t is String or t.strip_edges().is_empty():
			_warn(where + " : « %s » sans texte « %s »" % [key, lang])
			return {}
		out[lang] = t
	return out


## Échantillons {sorte connue : 1 à 999} ; {} (avertissement) sinon.
func _samples(v: Variant, where: String) -> Dictionary:
	if not v is Dictionary or v.is_empty():
		_warn(where + " : « samples » absent ou vide")
		return {}
	var out := {}
	for k in v:
		if not k is String or not known_sample(k):
			_warn(where + " : sorte d'échantillon inconnue (« %s »)" % str(k))
			return {}
		var n := _int(v[k], -1, -1, SAMPLE_MAX + 1)
		if n < SAMPLE_MIN or n > SAMPLE_MAX:
			_warn(where + " : quantité de « %s » hors %d à %d (%s)" % [k, SAMPLE_MIN, SAMPLE_MAX, str(v[k])])
			return {}
		out[k] = n
	return out


## Sorte d'échantillon connue du butin (LootRules.SAMPLES) ?
static func known_sample(id: String) -> bool:
	for kind in LootRules.SAMPLES:
		for s in LootRules.SAMPLES[kind]:
			if s[0] == id:
				return true
	return false


## Récompense normalisée ; {} (avertissement) si invalide. `exact` :
## catalogue d'échanges (pièce aux modificateurs exacts, arme nommée).
func _reward(v: Variant, where: String, exact: bool) -> Dictionary:
	if not v is Dictionary:
		_warn(where + " : « reward » absent")
		return {}
	match v.get("kind"):
		"none":
			if exact:
				_warn(where + " : un échange doit rapporter un objet")
				return {}
			return {"kind": "none"}
		"weapon":
			var w: Variant = v.get("weapon", "" if exact else "any")
			if not w is String:
				_warn(where + " : arme invalide")
				return {}
			if w == "any":
				if exact:
					_warn(where + " : un échange doit nommer son arme")
					return {}
			elif not WeaponDB.exists(w) or BaseWeapons.is_base(w):
				_warn(where + " : arme inconnue ou arme de base (« %s »)" % w)
				return {}
			var r: Variant = v.get("rarity")
			if OwnedWeapon.rarity_from_key(r) < 0:
				_warn(where + " : rareté inconnue (%s)" % str(r))
				return {}
			return {"kind": "weapon", "weapon": w, "rarity": r}
		"part":
			if exact:
				var mods: Variant = v.get("mods")
				if not mods is Dictionary or mods.is_empty():
					_warn(where + " : pièce sans « mods »")
					return {}
				var out := {}
				for k in mods:
					var m: Variant = mods[k]
					if not k is String or not GameWeapon.MODS.has(k):
						_warn(where + " : modificateur inconnu (« %s »)" % str(k))
						return {}
					if not (m is int or m is float) or not is_finite(float(m)) \
							or absf(float(m)) < MOD_MIN - 1e-9 or absf(float(m)) > MOD_MAX + 1e-9:
						_warn(where + " : modificateur « %s » hors ±%.2f à ±%.2f (%s)" % [k, MOD_MIN, MOD_MAX, str(m)])
						return {}
					out[k] = float(m)
				return {"kind": "part", "mods": out}
			var q: Variant = v.get("quality")
			if not q is String or not QUALITIES.has(q):
				_warn(where + " : qualité de pièce inconnue (%s)" % str(q))
				return {}
			return {"kind": "part", "quality": q}
	_warn(where + " : sorte de récompense inconnue (%s)" % str(v.get("kind")))
	return {}


## min_level, max_level (défauts 1 et 50) ; faux (avertissement) si invalides.
func _levels(e: Dictionary, out: Dictionary, where: String) -> bool:
	var cap := PlayerProfile.MAX_LEVEL
	var lo := _int(e.get("min_level", 1) if e.get("min_level") != null else 1, -1, -1, cap + 1)
	var hi := _int(e.get("max_level", cap) if e.get("max_level") != null else cap, -1, -1, cap + 1)
	if lo < 1 or lo > cap or hi < 1 or hi > cap:
		_warn(where + " : niveau hors 1 à %d" % cap)
		return false
	if lo > hi:
		_warn(where + " : « min_level » (%d) > « max_level » (%d)" % [lo, hi])
		return false
	out.min_level = lo
	out.max_level = hi
	return true


## starts, ends (jours UTC, -1 : sans date) ; faux (avertissement) si illisibles.
func _dates(e: Dictionary, out: Dictionary, where: String) -> bool:
	for k in ["starts", "ends"]:
		var v: Variant = e.get(k)
		if v == null:
			out[k] = -1
			continue
		var day := parse_day(v)
		if day < 0:
			_warn(where + " : date « %s » illisible (%s, attendu AAAA-MM-JJ)" % [k, str(v)])
			return false
		out[k] = day
	if out.starts >= 0 and out.ends >= 0 and out.starts > out.ends:
		_warn(where + " : « starts » après « ends »")
		return false
	return true


## Booléen (défaut si absent) ; null (avertissement) si d'un autre type.
func _bool(v: Variant, default: bool, where: String, key: String) -> Variant:
	if v == null:
		return default
	if not v is bool:
		_warn(where + " : « %s » doit être vrai ou faux" % key)
		return null
	return v


## Entier JSON (nombre entier, éventuellement lu en flottant) dans [lo, hi] ;
## `bad` sinon.
static func _int(v: Variant, bad: int, lo: int, hi: int) -> int:
	if v is int:
		return v if v >= lo and v <= hi else bad
	if v is float and is_finite(v) and v == floorf(v) and v >= lo and v <= hi:
		return int(v)
	return bad
