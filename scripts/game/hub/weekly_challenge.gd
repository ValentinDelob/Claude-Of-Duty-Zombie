class_name WeeklyChallenge
extends RefCounted
## Défi hebdomadaire (GAME_CONCEPT §4.18, valeurs provisoires §6 bis) : le
## même défi pour tout le monde chaque semaine, calculé HORS LIGNE à partir du
## numéro de semaine ISO (aucun serveur) : même carte, même graine, mêmes
## modificateurs pour une même version du jeu.
##
## * Réserve : assets/data/hub/weekly.json (format « hub_weekly ») : règles
##   (manche visée, XP), récompense en échantillons, cartes possibles,
##   modificateurs (identifiant connu du code, valeur bornée, poids, nom et
##   texte FR / EN ; « {pct} » et « {n} » remplacés par la valeur). Entrée
##   invalide écartée avec un avertissement (comme HubData).
## * Tirage (for_week) : graine = FNV-1a de « 2026-W41 », puis xorshift32
##   (pas le générateur de Godot, qui peut changer d'une version à l'autre) :
##   une carte parmi les cartes du jeu de la réserve qui ont une porte
##   d'évacuation ET une station de construction (map_ok), une graine de
##   partie, puis min à max modificateurs tirés selon leur poids, sans
##   doublon.
## * Conditions égales : tout le monde part avec les armes de base (niveau 1,
##   communes, sans pièce : starting_ids) ; la station ne construit que les
##   armes de base (build_allowed) ; le butin de la partie n'est PAS gardé.
## * Récompense : une fois par semaine, en atteignant l'objectif (évacuation
##   à la manche goal_round ou plus) : XP (comme un contrat, selon le
##   niveau) + échantillons. Meilleur résultat de chaque semaine gardé au
##   profil (WeeklyRecord).
## * Coop : l'hôte envoie la clé de semaine avec l'ordre de chargement
##   (Net.start_match) ; chaque machine recalcule le même défi.

const PATH := "res://assets/data/hub/weekly.json"
const FORMAT := "hub_weekly"
const VERSION := 1
const MAX_BYTES := 1 << 20

## Modificateurs connus du code : identifiant -> [valeur par défaut, min, max].
const MODS := {
	# Vitesse des zombies et des chiens × (1 + valeur).
	"fast_zombies": [0.15, 0.05, 0.5],
	# Points de vie des zombies et des chiens × (1 + valeur).
	"tough_zombies": [0.25, 0.05, 1.0],
	# Première manche jouée (les vagues spéciales gardent leur rythme).
	"late_start": [6, 2, 30],
	# Armes trouvées toutes communes.
	"common_loot": [0, 0, 0],
	# Aucune station de construction sur la carte.
	"no_station": [0, 0, 0],
}
const DEFAULT_RULES := {"goal_round": 10, "xp": 400, "min_modifiers": 1, "max_modifiers": 2}
const RULE_RANGES := {"goal_round": [1, 200], "xp": [0, 100000], "min_modifiers": [0, 5], "max_modifiers": [0, 5]}
const WEIGHT_MAX := 1000.0
const SAMPLE_MAX := 999

## Tests et scénarios : heure imposée (s unix, < 0 : horloge du système).
static var now_override := -1.0

## Réserve livrée, lue une fois (pool()).
static var _pool: Pool
## Cartes déjà contrôlées : identifiant -> bool (map_ok).
static var _maps_ok: Dictionary = {}

## Semaine ISO du défi.
var year := 0
var week := 0
var key := ""
var map_id := ""
## Graine des tirages de la partie (serveur : manches, butin, zombies).
var match_seed := 0
## Modificateurs tirés : [{id, value, title {fr, en}, text {fr, en}}].
var modifiers: Array[Dictionary] = []
## Objectif : évacuation à cette manche ou plus.
var goal_round := 10
## Récompense de la semaine : XP de base (selon le niveau) et échantillons.
var reward_xp := 0
var reward_samples: Dictionary = {}


# --------------------------------------------------------------------------
# Réserve (fichier de données)
# --------------------------------------------------------------------------

## Réserve normalisée de weekly.json.
class Pool extends RefCounted:
	var rules: Dictionary = {}
	var reward: Dictionary = {}
	var maps: PackedStringArray = []
	var modifiers: Array[Dictionary] = []
	var warnings: PackedStringArray = []

	func warn(msg: String) -> void:
		warnings.append(msg)
		push_warning("[Weekly] " + msg)


## Réserve des fichiers livrés (lue au premier appel, puis gardée).
static func pool() -> Pool:
	if _pool == null:
		var t := ""
		if FileAccess.file_exists(PATH):
			var f := FileAccess.open(PATH, FileAccess.READ)
			if f and f.get_length() <= MAX_BYTES:
				t = f.get_as_text()
		_pool = parse_pool(t)
	return _pool


static func clear_cache() -> void:
	_pool = null
	_maps_ok.clear()


## Lit une réserve depuis son texte (tests). Entrées invalides écartées.
static func parse_pool(text: String, name := "weekly.json") -> Pool:
	var p := Pool.new()
	p.rules = DEFAULT_RULES.duplicate()
	if text.is_empty():
		p.warn("%s : fichier absent ou vide" % name)
		return p
	var json := JSON.new()
	if json.parse(text) != OK:
		p.warn("%s : JSON invalide ligne %d" % [name, json.get_error_line()])
		return p
	var doc: Variant = json.data
	if not doc is Dictionary or doc.get("format") != FORMAT:
		p.warn("%s : format attendu « %s »" % [name, FORMAT])
		return p
	var v: Variant = doc.get("version")
	if not (v is int or v is float) or not is_finite(float(v)) or int(v) < 1 or int(v) > VERSION:
		p.warn("%s : version illisible par le jeu" % name)
		return p
	var r: Variant = doc.get("rules", {})
	if r is Dictionary:
		for k in r:
			if not RULE_RANGES.has(k):
				p.warn("%s : règle inconnue « %s »" % [name, str(k)])
				continue
			var x: Variant = r[k]
			if not (x is int or x is float) or not is_finite(float(x)) or float(x) != floorf(float(x)) \
					or float(x) < RULE_RANGES[k][0] or float(x) > RULE_RANGES[k][1]:
				p.warn("%s : règle « %s » invalide (%s)" % [name, k, str(x)])
				continue
			p.rules[k] = int(x)
	else:
		p.warn("%s : section « rules » invalide" % name)
	if int(p.rules.min_modifiers) > int(p.rules.max_modifiers):
		p.warn("%s : min_modifiers > max_modifiers" % name)
		p.rules.min_modifiers = p.rules.max_modifiers
	var rw: Variant = doc.get("reward", {})
	if rw is Dictionary:
		for k in rw:
			var n: Variant = rw[k]
			if not (k is String and HubData.known_sample(k)) or not (n is int or n is float) \
					or float(n) != floorf(float(n)) or int(n) < 1 or int(n) > SAMPLE_MAX:
				p.warn("%s : récompense « %s » invalide" % [name, str(k)])
				continue
			p.reward[k] = int(n)
	var ms: Variant = doc.get("maps", [])
	if ms is Array:
		for m in ms:
			if not (m is String) or not Game.MAP_SCRIPTS.has(m) or m in p.maps:
				p.warn("%s : carte « %s » inconnue ou en double" % [name, str(m)])
				continue
			p.maps.append(m)
	else:
		p.warn("%s : section « maps » invalide" % name)
	var mods: Variant = doc.get("modifiers", [])
	if mods is Array:
		for e in mods:
			var m := _read_mod(e, p, name)
			if not m.is_empty():
				p.modifiers.append(m)
	else:
		p.warn("%s : section « modifiers » invalide" % name)
	return p


static func _read_mod(e: Variant, p: Pool, name: String) -> Dictionary:
	if not e is Dictionary:
		p.warn("%s : modificateur illisible" % name)
		return {}
	var id: Variant = e.get("id")
	if not id is String or not MODS.has(id):
		p.warn("%s : modificateur inconnu « %s »" % [name, str(id)])
		return {}
	for m in p.modifiers:
		if m.id == id:
			p.warn("%s : modificateur « %s » en double" % [name, id])
			return {}
	var spec: Array = MODS[id]
	var v: Variant = e.get("value", spec[0])
	if not (v is int or v is float) or not is_finite(float(v)) or float(v) < float(spec[1]) or float(v) > float(spec[2]):
		p.warn("%s : valeur de « %s » hors %s à %s" % [name, id, str(spec[1]), str(spec[2])])
		return {}
	var w: Variant = e.get("weight", 1)
	if not (w is int or w is float) or not is_finite(float(w)) or float(w) < 0.0 or float(w) > WEIGHT_MAX:
		p.warn("%s : poids de « %s » invalide" % [name, id])
		return {}
	var out := {"id": id, "value": float(v), "weight": float(w)}
	for k in ["title", "text"]:
		var t: Variant = e.get(k)
		if not t is Dictionary or not t.get("fr") is String or not t.get("en") is String \
				or String(t.fr).strip_edges() == "" or String(t.en).strip_edges() == "":
			p.warn("%s : « %s » de « %s » sans français ou anglais" % [name, k, id])
			return {}
		out[k] = {"fr": String(t.fr), "en": String(t.en)}
	return out


## Carte du jeu (livrée) utilisable par le défi : une porte d'évacuation et
## une station de construction (contrôlé une fois par carte).
static func map_ok(id: String) -> bool:
	if _maps_ok.has(id):
		return _maps_ok[id]
	var ok := false
	if id in Game.MENU_MAPS and Game.MAP_SCRIPTS.has(id):
		var def := Game.make_map_def(id)
		var layout := def.create_layout() if def else null
		ok = layout != null and layout.evac_door() != null and layout.build_station() != null
	_maps_ok[id] = ok
	return ok


# --------------------------------------------------------------------------
# Semaines ISO (UTC)
# --------------------------------------------------------------------------

## Heure actuelle (s unix, UTC ; now_override pendant les tests).
static func now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


## Jour de la semaine d'un jour UTC (jours depuis le 1/1/1970) : 0 = lundi.
static func weekday(day: int) -> int:
	return posmod(day + 3, 7)


static func _jan1(y: int) -> int:
	return floori(Time.get_unix_time_from_datetime_dict({"year": y, "month": 1, "day": 1,
		"hour": 0, "minute": 0, "second": 0}) / 86400.0)


## Semaine ISO d'un jour UTC : Vector2i(année ISO, semaine).
static func iso_week(day: int) -> Vector2i:
	var thu := day - weekday(day) + 3
	var y := int(Time.get_datetime_dict_from_unix_time(thu * 86400).year)
	@warning_ignore("integer_division")
	return Vector2i(y, (thu - _jan1(y)) / 7 + 1)


## Nombre de semaines ISO d'une année (52 ou 53).
static func weeks_in(y: int) -> int:
	return iso_week(_jan1(y + 1) - 4).y  # 28 décembre


## Lundi (jour UTC) de la semaine ISO.
static func week_monday(y: int, w: int) -> int:
	var jan4 := _jan1(y) + 3
	return jan4 - weekday(jan4) + 7 * (w - 1)


static func week_ok(y: int, w: int) -> bool:
	return y >= 2000 and y <= 9999 and w >= 1 and w <= weeks_in(y)


static func key_of(y: int, w: int) -> String:
	return "%04d-W%02d" % [y, w]


## Clé « AAAA-Wss » lue strictement : Vector2i(année, semaine), (0, 0) si
## illisible ou inexistante.
static func parse_key(k: Variant) -> Vector2i:
	if not (k is String or k is StringName):
		return Vector2i.ZERO
	var s := String(k)
	if s.length() != 8 or s[4] != "-" or s[5] != "W":
		return Vector2i.ZERO
	var ys := s.substr(0, 4)
	var ws := s.substr(6, 2)
	for ch in ys + ws:
		if not ch in "0123456789":
			return Vector2i.ZERO
	var y := ys.to_int()
	var w := ws.to_int()
	return Vector2i(y, w) if week_ok(y, w) else Vector2i.ZERO


# --------------------------------------------------------------------------
# Tirage
# --------------------------------------------------------------------------

## Générateur xorshift32 (reproductible sur toute version du moteur).
class Rng extends RefCounted:
	const M := 0xFFFFFFFF
	var s := 0

	func _init(seed_: int) -> void:
		s = seed_ & M
		if s == 0:
			s = 0x9E3779B9

	func u32() -> int:
		s ^= (s << 13) & M
		s ^= s >> 17
		s ^= (s << 5) & M
		s &= M
		return s

	func below(n: int) -> int:
		return u32() % maxi(n, 1)

	## Réel dans [0, 1[.
	func unit() -> float:
		return float(u32()) / 4294967296.0


## Empreinte FNV-1a 32 bits d'un texte.
static func fnv(t: String) -> int:
	var h := 2166136261
	for b in t.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


## Défi de la semaine ISO (`y`, `w`) ; null si la semaine est invalide ou si
## aucune carte de la réserve ne convient.
static func for_week(y: int, w: int, p: Pool = null) -> WeeklyChallenge:
	if not week_ok(y, w):
		return null
	if p == null:
		p = pool()
	var maps := PackedStringArray()
	for m in p.maps:
		if map_ok(m):
			maps.append(m)
	if maps.is_empty():
		return null
	var c := WeeklyChallenge.new()
	c.year = y
	c.week = w
	c.key = key_of(y, w)
	var rng := Rng.new(fnv(c.key))
	c.map_id = maps[rng.below(maps.size())]
	c.match_seed = rng.u32()
	c.goal_round = int(p.rules.goal_round)
	c.reward_xp = int(p.rules.xp)
	c.reward_samples = p.reward.duplicate()
	var lo := int(p.rules.min_modifiers)
	var hi := int(p.rules.max_modifiers)
	var n := lo + rng.below(hi - lo + 1)
	var left: Array[Dictionary] = []
	for m in p.modifiers:
		# La station en panne n'a de sens que sur une carte qui en a une
		# (toujours vrai ici : map_ok l'exige).
		if float(m.weight) > 0.0:
			left.append(m)
	while c.modifiers.size() < n and not left.is_empty():
		var total := 0.0
		for m in left:
			total += float(m.weight)
		var x := rng.unit() * total
		var pick := left.size() - 1
		for i in left.size():
			x -= float(left[i].weight)
			if x < 0.0:
				pick = i
				break
		var m: Dictionary = left.pop_at(pick)
		c.modifiers.append({"id": m.id, "value": m.value, "title": m.title, "text": m.text})
	return c


## Défi d'une clé « AAAA-Wss » (coop : clé reçue de l'hôte) ; null si
## illisible.
static func from_key(k: Variant, p: Pool = null) -> WeeklyChallenge:
	var yw := parse_key(k)
	return for_week(yw.x, yw.y, p) if yw.x > 0 else null


## Défi de la semaine en cours (heure `at`, défaut : maintenant).
static func current(at := -1.0, p: Pool = null) -> WeeklyChallenge:
	var t := now() if at < 0.0 else at
	var yw := iso_week(floori(t / 86400.0))
	return for_week(yw.x, yw.y, p)


## Secondes avant la fin de la semaine du défi (lundi suivant, 0 h UTC).
func seconds_left(at := -1.0) -> int:
	var t := now() if at < 0.0 else at
	return maxi(int((week_monday(year, week) + 7) * 86400 - t), 0)


# --------------------------------------------------------------------------
# Modificateurs : application (pures)
# --------------------------------------------------------------------------

func has_mod(id: String) -> bool:
	for m in modifiers:
		if m.id == id:
			return true
	return false


func mod_value(id: String) -> float:
	for m in modifiers:
		if m.id == id:
			return float(m.value)
	return 0.0


## Multiplicateur de vitesse des zombies et des chiens.
func zombie_speed_mult() -> float:
	return 1.0 + mod_value("fast_zombies")


## Points de vie d'un zombie ou d'un chien (PV normaux `hp`).
func zombie_health(hp: int) -> int:
	return maxi(roundi(hp * (1.0 + mod_value("tough_zombies"))), 1)


## Première manche jouée (1 sans modificateur).
func start_round() -> int:
	return maxi(int(mod_value("late_start")), 1) if has_mod("late_start") else 1


func has_station() -> bool:
	return not has_mod("no_station")


## Arme de butin tirée `w`, ramenée à commune si le défi l'exige.
func loot_weapon(w: Dictionary) -> Dictionary:
	if not has_mod("common_loot") or GameWeapon.rarity_of(w) == 0:
		return w
	return GameWeapon.make(String(w.get("id", "")), GameWeapon.level_of(w), 0, [], String(w.get("uid", "")))


## Armes de départ de tout le monde (conditions égales, §4.10) : toutes les
## armes de base, quelle que soit la sélection du profil.
static func starting_ids() -> PackedStringArray:
	return BaseWeapons.default_selection()


## La station ne construit que les armes de base (niveau 1, commune, sans
## pièce) : l'arsenal du joueur n'entre pas dans le défi.
static func build_allowed(w: Dictionary) -> bool:
	return not w.is_empty() and BaseWeapons.is_base(String(w.get("id", ""))) and GameWeapon.level_of(w) == 1 \
		and GameWeapon.rarity_of(w) == 0 and (w.get("parts", []) as Array).is_empty()


## Objectif atteint : évacuation à la manche goal_round ou plus.
func goal_reached(round_reached: int, evacuated: bool) -> bool:
	return evacuated and round_reached >= goal_round


# --------------------------------------------------------------------------
# Résultat et récompense (profil)
# --------------------------------------------------------------------------

## XP de la récompense pour un joueur de niveau `lvl` (comme un contrat).
func reward_xp_for(lvl: int) -> int:
	return HubRewards.contract_xp(reward_xp, lvl)


## Enregistre une partie du défi dans le profil `pr` ; donne la récompense
## UNE fois par semaine si l'objectif est atteint. Rend {key, goal, new_best,
## rewarded (donnée cette fois), xp, samples}.
func apply_to(pr: PlayerProfile, round_reached: int, evacuated: bool) -> Dictionary:
	var out := {"key": key, "goal": goal_reached(round_reached, evacuated), "new_best": false,
		"rewarded": false, "xp": 0, "samples": {}}
	out.new_best = pr.weekly.record(key, round_reached, evacuated)
	if out.goal and not pr.weekly.is_rewarded(key):
		out.xp = reward_xp_for(pr.level())
		pr.add_xp(out.xp)
		for k in reward_samples:
			pr.add_samples(k, int(reward_samples[k]))
		out.samples = reward_samples.duplicate()
		pr.weekly.mark_rewarded(key)
		out.rewarded = true
	return out


## apply_to sur le profil enregistré (chargé, modifié, enregistré). Ajoute
## {total_xp, level} (profil après).
func apply_result(round_reached: int, evacuated: bool, profile_path := "") -> Dictionary:
	var pr := ProfileStore.load_profile(profile_path)
	var out := apply_to(pr, round_reached, evacuated)
	ProfileStore.save_profile(pr, profile_path)
	out.total_xp = pr.xp
	out.level = pr.level()
	return out


# --------------------------------------------------------------------------
# Textes (FR / EN)
# --------------------------------------------------------------------------

## « S41 » / « W41 ».
func week_label() -> String:
	return Lang.t("S%d", "W%d") % week


static func mod_title(m: Dictionary) -> String:
	return _fill(HubData.text_of(m.get("title", {})), m)


static func mod_text(m: Dictionary) -> String:
	return _fill(HubData.text_of(m.get("text", {})), m)


static func _fill(t: String, m: Dictionary) -> String:
	var v := float(m.get("value", 0.0))
	return t.replace("{pct}", str(roundi(v * 100.0))).replace("{n}", str(int(v)))


## « Évacuez à la manche 10 ou plus ».
func goal_text() -> String:
	return Lang.t("Évacuez à la manche %d ou plus", "Evacuate at round %d or later") % goal_round


## Meilleur résultat de la semaine dans le profil `pr`.
func best_text(pr: PlayerProfile) -> String:
	if pr == null or not pr.weekly.played(key):
		return Lang.t("pas encore tenté", "not tried yet")
	var e := pr.weekly.entry(key)
	var t := Lang.t("manche %d", "round %d") % int(e.best)
	if int(e.evac) > 0:
		t += Lang.t(", évacuation à la manche %d", ", evacuated at round %d") % int(e.evac)
	return t


## Récompense : « +400 XP · 4 crocs, 3 touffes, 2 colliers » (XP au niveau `lvl`).
func reward_text(lvl: int) -> String:
	var items := PackedStringArray()
	var keys := reward_samples.keys()
	keys.sort()
	for k in keys:
		items.append("%d %s" % [int(reward_samples[k]), LootRules.sample_name(String(k)).to_lower()])
	var xp_t := Lang.t("+%s XP", "+%s XP") % XpSystem.group(reward_xp_for(lvl))
	return xp_t if items.is_empty() else "%s · %s" % [xp_t, ", ".join(items)]


## Temps restant : « 3 j 4 h », « 5 h 12 min », « 8 min ».
static func remaining_text(sec: int) -> String:
	@warning_ignore("integer_division")
	var d := sec / 86400
	@warning_ignore("integer_division")
	var h := (sec / 3600) % 24
	@warning_ignore("integer_division")
	var m := (sec / 60) % 60
	if d > 0:
		return Lang.t("%d j %d h", "%d d %d h") % [d, h]
	if h > 0:
		return Lang.t("%d h %02d min", "%d h %02d min") % [h, m]
	return Lang.t("%d min", "%d min") % maxi(m, 1)
