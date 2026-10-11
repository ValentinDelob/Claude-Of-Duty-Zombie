class_name StoryData
extends RefCounted
## Contrats d'HISTOIRE de Dr Brown (GAME_CONCEPT §4.2 quater, 💡 provisoire ;
## docs/HUB_PLAN.md §5.7), lus depuis assets/data/hub/story.json (format
## « hub_story ») : une suite de CHAPITRES, chacun fait d'ÉTAPES à remplir
## dans l'ordre, une seule à la fois (StoryRules). Pur, sans interface. Comme
## HubData, chaque entrée invalide est ÉCARTÉE avec un avertissement (journal
## + `warnings`) ; un test vérifie que le fichier livré se charge sans aucun
## avertissement (tests/test_story.gd).
##
##   {"format": "hub_story", "version": 1,
##    "rules": {"xp_level_factor": 0.02},
##    "chapters": [{"id", "title": {fr, en}, "steps": [
##      {"id", "short" {fr, en} (libellé de la frise, 14 caractères au plus),
##       "title" {fr, en}, "text" {fr, en} (demande de Dr Brown),
##       "lab" {fr, en} (réplique au LABO pendant l'étape, facultative),
##       "ready" {fr, en} (réplique au LABO quand elle est prête, facultative),
##       "thanks" {fr, en} (réplique à la remise, facultative),
##       "samples" {sorte: n}, "xp" (base au niveau 1), "reward" (comme un
##       contrat : arme « any » ou nommée + rareté, pièce + qualité, « none »),
##       "min_level" (niveau du joueur pour la remettre, défaut 1)}]}]}
##
## Identifiants uniques dans tout le fichier, jamais changés une fois publiés
## (le profil garde les étapes remplies, StoryState). Un chapitre sans
## étape valide est écarté ; 1 à MAX_STEPS étapes par chapitre (frise).
## Entrées normalisées : chapitre {id, title, steps: [étape]} ; étape {id,
## chapter (id), short, title, text, lab, ready, thanks ({} si absents),
## samples, xp, reward, min_level}.

const PATH := "res://assets/data/hub/story.json"
const FORMAT := "hub_story"
const VERSION := 1
const MAX_STEPS := 8
const MAX_CHAPTERS := 32
## Libellé de la frise (5 colonnes de 90 px à 11 px) : longueur maximale.
const SHORT_MAX := 14
const DEFAULT_RULES := {"xp_level_factor": 0.02}

## Règles (DEFAULT_RULES complétées par le fichier).
var rules: Dictionary = DEFAULT_RULES.duplicate()
## Chapitres valides, dans l'ordre du fichier.
var chapters: Array[Dictionary] = []
## Toutes les étapes valides, dans l'ordre de l'histoire.
var steps: Array[Dictionary] = []
## Avertissements du chargement.
var warnings: PackedStringArray = []

var _step_by_id := {}
## Validateur commun avec les contrats (textes, échantillons, récompenses).
var _v := HubData.new()

## Fichier livré, chargé une fois (shipped()).
static var _shipped: StoryData


## Histoire livrée (chargée au premier appel, puis gardée).
static func shipped() -> StoryData:
	if _shipped == null:
		_shipped = load_file(PATH)
	return _shipped


static func clear_cache() -> void:
	_shipped = null


static func load_file(path: String) -> StoryData:
	return from_text(HubData._read(path), path.get_file())


## Histoire lue depuis son texte (tests). `name` : nom cité dans les
## avertissements.
static func from_text(text: String, name := "story.json") -> StoryData:
	var d := StoryData.new()
	var doc: Variant = d._v._parse_doc(text, FORMAT, name)
	if doc is Dictionary:
		d._read_rules(doc.get("rules"), name)
		d._read_chapters(doc.get("chapters"), name)
	d.warnings.append_array(d._v.warnings)
	return d


func step(id: String) -> Dictionary:
	return _step_by_id.get(id, {})


func has_step(id: String) -> bool:
	return _step_by_id.has(id)


## Rang de l'étape `id` dans toute l'histoire (-1 : inconnue).
func step_index(id: String) -> int:
	for i in steps.size():
		if steps[i].id == id:
			return i
	return -1


## Chapitre de l'étape `id` : {chapter (dictionnaire), chapter_index (0..),
## step_index (0.. dans le chapitre), count (étapes du chapitre)} ; {} si
## inconnue.
func locate(id: String) -> Dictionary:
	for ci in chapters.size():
		var ch: Dictionary = chapters[ci]
		for si in ch.steps.size():
			if ch.steps[si].id == id:
				return {"chapter": ch, "chapter_index": ci, "step_index": si, "count": ch.steps.size()}
	return {}


func _warn(msg: String) -> void:
	warnings.append(msg)
	push_warning("[Story] " + msg)


func _read_rules(r: Variant, name: String) -> void:
	if r == null:
		return
	if not r is Dictionary:
		_warn("%s : section « rules » invalide, règles par défaut" % name)
		return
	for k in r:
		if k != "xp_level_factor":
			_warn("%s : règle inconnue « %s » ignorée" % [name, str(k)])
			continue
		var v: Variant = r[k]
		if not (v is int or v is float) or not is_finite(float(v)) or float(v) < 0.0 or float(v) > 1.0:
			_warn("%s : règle « %s » hors 0 à 1 (%s), valeur par défaut" % [name, k, str(v)])
			continue
		rules[k] = float(v)


func _read_chapters(list: Variant, name: String) -> void:
	if not list is Array:
		_warn("%s : liste « chapters » absente" % name)
		return
	var ids := {}
	for i in list.size():
		var e: Variant = list[i]
		var where := "%s, chapitre n° %d" % [name, i + 1]
		if chapters.size() >= MAX_CHAPTERS:
			_warn("%s : plus de %d chapitres, la suite est ignorée" % [name, MAX_CHAPTERS])
			return
		if not e is Dictionary:
			_warn(where + " : entrée invalide")
			continue
		var id := _v._id(e.get("id"), where, ids)
		if id == "":
			continue
		ids[id] = true
		where = "%s (« %s »)" % [where, id]
		var title := _v._text(e.get("title"), where, "title", true)
		if title.is_empty():
			continue
		var raw: Variant = e.get("steps")
		if not raw is Array:
			_warn(where + " : liste « steps » absente")
			continue
		var ch := {"id": id, "title": title, "steps": []}
		for j in raw.size():
			var sw := "%s, étape n° %d" % [where, j + 1]
			if ch.steps.size() >= MAX_STEPS:
				_warn("%s : plus de %d étapes, la suite est ignorée" % [where, MAX_STEPS])
				break
			if not raw[j] is Dictionary:
				_warn(sw + " : entrée invalide")
				continue
			var s := _step(raw[j], sw, ids, id)
			if not s.is_empty():
				ids[s.id] = true
				ch.steps.append(s)
		if ch.steps.is_empty():
			_warn(where + " : aucune étape valide, chapitre écarté")
			continue
		chapters.append(ch)
		for s in ch.steps:
			steps.append(s)
			_step_by_id[s.id] = s


func _step(e: Dictionary, where: String, ids: Dictionary, chapter_id: String) -> Dictionary:
	var id := _v._id(e.get("id"), where, ids)
	if id == "":
		return {}
	where = "%s (« %s »)" % [where, id]
	var s := {"id": id, "chapter": chapter_id}
	for k in ["short", "title", "text"]:
		s[k] = _v._text(e.get(k), where, k, true)
		if s[k].is_empty():
			return {}
	for lang in ["fr", "en"]:
		if String(s.short[lang]).length() > SHORT_MAX:
			_warn(where + " : « short » (%s) plus long que %d caractères" % [lang, SHORT_MAX])
			return {}
	for k in ["lab", "ready", "thanks"]:
		s[k] = _v._text(e.get(k), where, k, false)
		if e.get(k) != null and s[k].is_empty():
			return {}
	s.samples = _v._samples(e.get("samples"), where)
	if s.samples.is_empty():
		return {}
	var xp := HubData._int(e.get("xp"), -1, 0, HubData.XP_MAX)
	if xp < 0:
		_warn(where + " : « xp » absent ou hors 0 à %d" % HubData.XP_MAX)
		return {}
	s.xp = xp
	s.reward = _v._reward(e.get("reward"), where, false)
	if s.reward.is_empty():
		return {}
	var cap := PlayerProfile.MAX_LEVEL
	var lvl := HubData._int(e.get("min_level", 1) if e.get("min_level") != null else 1, -1, 1, cap)
	if lvl < 1:
		_warn(where + " : « min_level » hors 1 à %d" % cap)
		return {}
	s.min_level = lvl
	return s
