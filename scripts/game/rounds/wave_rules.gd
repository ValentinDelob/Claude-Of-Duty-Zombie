class_name WaveRules
extends RefCounted
## Schéma d'apparition des vagues spéciales et des vagues de boss d'une carte
## (GAME_CONCEPT.md §4.4 ; fonctions pures, tests/test_wave_rules.gd).
##
## Le schéma est un dictionnaire {type: {premiere, intervalle}} :
##   speciale  vague spéciale (mini-boss : meute de chiens, Brancardier) ;
##   boss      vague de boss (le Chirurgien).
## « premiere » : première manche du type (0 : jamais) ; « intervalle » :
## écart entre deux vagues du type (0 : une seule, à « premiere »).
## Défaut : une vague spéciale toutes les 5 manches (5, 10, 15...), un boss
## toutes les 15 (15, 30...). Une manche à la fois spéciale et de boss est une
## vague de boss si la carte a un boss (has_boss : vagues de boss prévues),
## sinon une vague spéciale.
##
## Éditeur (format 18) : clé « vagues » de carte.json, mêmes clés, jamais
## écrite à sa valeur par défaut (EditorMap.set_waves).
##
## Format 21 : TYPES de vagues spéciales autorisés sur la carte
## (« types_speciaux » : liste d'identifiants de SPECIAL_TYPES ; absente,
## vide ou illisible : tous). Règle de ROTATION : la k-ième vague spéciale
## prévue par le schéma (manches 1 à n, sans celles remplacées par une vague
## de boss quand la carte a un boss) est du type types[(k − 1) mod nombre de
## types], dans l'ordre de SPECIAL_TYPES. Défaut (tous, boss à la 15) : meute
## à la 5, Brancardier à la 10, boss à la 15, meute à la 20, Brancardier à la
## 25... Une carte qui n'autorise qu'un type n'a que lui
## (EditorMap.set_special_types).
##
## Format 22 : TYPES de boss autorisés (« types_boss » : liste d'identifiants
## de BOSS_TYPES ; absente, vide ou illisible : tous), même rotation : la
## k-ième vague de boss est du type types[(k − 1) mod nombre de types]
## (boss_type_at). Aujourd'hui un seul boss : le Chirurgien. Carte sans
## boss : « premiere » 0 dans « boss » (EditorMap.set_waves).

const SPECIAL := "speciale"
const BOSS := "boss"
const KINDS := [SPECIAL, BOSS]
## Clé de la liste des types de vagues spéciales autorisés (format 21).
const TYPES_KEY := "types_speciaux"
## Types de vagues spéciales (mini-boss), dans l'ordre de la rotation :
## meute de chiens errants (DogRound), Brancardier (BrancardRound).
const MEUTE := "meute"
const BRANCARDIER := "brancardier"
const SPECIAL_TYPES := [MEUTE, BRANCARDIER]
## Clé de la liste des types de boss autorisés (format 22).
const BOSS_TYPES_KEY := "types_boss"
## Types de boss, dans l'ordre de la rotation : le Chirurgien (SurgeonRound).
const CHIRURGIEN := "chirurgien"
const BOSS_TYPES := [CHIRURGIEN]
const DEFAULT := {
	SPECIAL: {"premiere": 5, "intervalle": 5},
	BOSS: {"premiere": 15, "intervalle": 15},
	TYPES_KEY: SPECIAL_TYPES,
	BOSS_TYPES_KEY: BOSS_TYPES,
}
## Garde des recherches de la prochaine vague d'un type (vagues parcourues).
const SEARCH_MAX := 4000
## Bornes acceptées (éditeur, cartes reçues) : manche 0 (jamais) à 999.
const ROUND_MAX := 999


## Schéma par défaut (copie modifiable).
static func default_schedule() -> Dictionary:
	return DEFAULT.duplicate(true)


## Schéma lu dans `v` (clé « vagues » d'une carte ou d'une description) :
## valeurs illisibles ou absentes remplacées par le défaut, bornées.
static func parse(v: Variant) -> Dictionary:
	var out := default_schedule()
	if not v is Dictionary:
		return out
	out[TYPES_KEY] = parse_types((v as Dictionary).get(TYPES_KEY))
	out[BOSS_TYPES_KEY] = parse_boss_types((v as Dictionary).get(BOSS_TYPES_KEY))
	for kind in KINDS:
		var e: Variant = (v as Dictionary).get(kind)
		if not e is Dictionary:
			continue
		for key in ["premiere", "intervalle"]:
			var n: Variant = (e as Dictionary).get(key)
			if (n is int or n is float) and is_finite(float(n)):
				out[kind][key] = clampi(int(n), 0, ROUND_MAX)
	return out


## Types de vagues spéciales lus dans `v` : identifiants connus, sans
## doublon, dans l'ordre de SPECIAL_TYPES ; absent, vide ou illisible : tous.
static func parse_types(v: Variant) -> Array:
	var out := []
	if v is Array:
		for t in SPECIAL_TYPES:
			if (v as Array).has(t):
				out.append(t)
	return out if not out.is_empty() else SPECIAL_TYPES.duplicate()


## Types de vagues spéciales autorisés par le schéma `sched` (ordre de la rotation).
static func special_types(sched: Dictionary) -> Array:
	return parse(sched)[TYPES_KEY]


## Format 22 : types de boss lus dans `v` (comme parse_types, BOSS_TYPES).
static func parse_boss_types(v: Variant) -> Array:
	var out := []
	if v is Array:
		for t in BOSS_TYPES:
			if (v as Array).has(t):
				out.append(t)
	return out if not out.is_empty() else BOSS_TYPES.duplicate()


## Types de boss autorisés par le schéma `sched` (ordre de la rotation).
static func boss_types(sched: Dictionary) -> Array:
	return parse(sched)[BOSS_TYPES_KEY]


## La carte a-t-elle un boss (vagues de boss prévues : « premiere » > 0) ?
## Alors une manche prévue pour les deux est une vague de boss, et les
## vagues spéciales remplacées ne comptent pas dans leur rotation.
static func has_boss(sched: Dictionary) -> bool:
	return int(parse(sched)[BOSS].premiere) > 0


## Le schéma est-il celui par défaut ?
static func is_default(sched: Dictionary) -> bool:
	return parse(sched) == DEFAULT


## La manche `n` est-elle prévue pour le type d'entrée `e` ({premiere, intervalle}) ?
static func scheduled(e: Dictionary, n: int) -> bool:
	var first := int(e.get("premiere", 0))
	var gap := int(e.get("intervalle", 0))
	if first <= 0 or n < first:
		return false
	if gap <= 0:
		return n == first
	return (n - first) % gap == 0


## Type de vague de la manche `n` : SPECIAL, BOSS ou "" (manche normale).
## `has_boss` : la carte a un boss défini (sinon une vague de boss ne fait rien).
static func wave_kind(sched: Dictionary, n: int, has_boss := false) -> String:
	var s := parse(sched)
	if has_boss and scheduled(s[BOSS], n):
		return BOSS
	if scheduled(s[SPECIAL], n):
		return SPECIAL
	return ""


## Prochaine manche strictement après `n` où le type `kind` est prévu (0 : jamais).
static func next_after(sched: Dictionary, kind: String, n: int) -> int:
	var e: Dictionary = parse(sched)[kind]
	var first := int(e.premiere)
	var gap := int(e.intervalle)
	if first <= 0:
		return 0
	if n < first:
		return first
	if gap <= 0:
		return 0
	@warning_ignore("integer_division")
	return first + ((n - first) / gap + 1) * gap


## Rang de la vague spéciale de la manche `n` parmi les vagues spéciales
## prévues par le schéma (1 pour la première, manches de boss exclues) ;
## 0 si la manche `n` n'en est pas une.
static func special_rank(sched: Dictionary, n: int, has_boss := false) -> int:
	var s := parse(sched)
	if wave_kind(s, n, has_boss) != SPECIAL:
		return 0
	var e: Dictionary = s[SPECIAL]
	var first := int(e.premiere)
	var gap := int(e.intervalle)
	@warning_ignore("integer_division")
	var k := 1 if gap <= 0 else (n - first) / gap + 1
	if has_boss:
		# Vagues spéciales prévues avant n mais remplacées par une vague de boss.
		var r := first
		for i in k:
			if scheduled(s[BOSS], r):
				k -= 1
			r += maxi(gap, 1)
	return k


## Type de la vague spéciale de la manche `n` (rotation de SPECIAL_TYPES
## autorisés) ; "" si la manche n'est pas une vague spéciale.
static func special_type_at(sched: Dictionary, n: int, has_boss := false) -> String:
	var k := special_rank(sched, n, has_boss)
	if k <= 0:
		return ""
	var types := special_types(sched)
	return String(types[(k - 1) % types.size()])


## Prochaine manche strictement après `n` dont la vague spéciale est du type
## `type` (0 : jamais, ou type non autorisé sur la carte).
static func next_special_of(sched: Dictionary, type: String, n: int, has_boss := false) -> int:
	var s := parse(sched)
	if not (s[TYPES_KEY] as Array).has(type):
		return 0
	var r := maxi(n, 0)
	for i in SEARCH_MAX:
		r = next_after(s, SPECIAL, r)
		if r <= 0:
			return 0
		if special_type_at(s, r, has_boss) == type:
			return r
	return 0


## Rang de la vague de boss de la manche `n` parmi les vagues de boss du
## schéma (1 pour la première) ; 0 si la manche `n` n'en est pas une.
static func boss_rank(sched: Dictionary, n: int) -> int:
	var e: Dictionary = parse(sched)[BOSS]
	if not scheduled(e, n):
		return 0
	var gap := int(e.intervalle)
	@warning_ignore("integer_division")
	return 1 if gap <= 0 else (n - int(e.premiere)) / gap + 1


## Type du boss de la manche `n` (rotation des BOSS_TYPES autorisés) ; ""
## si la manche n'est pas une vague de boss.
static func boss_type_at(sched: Dictionary, n: int) -> String:
	var k := boss_rank(sched, n)
	if k <= 0:
		return ""
	var types := boss_types(sched)
	return String(types[(k - 1) % types.size()])


## Prochaine manche strictement après `n` dont la vague de boss est du type
## `type` (0 : jamais, ou type non autorisé sur la carte).
static func next_boss_of(sched: Dictionary, type: String, n: int) -> int:
	var s := parse(sched)
	if not (s[BOSS_TYPES_KEY] as Array).has(type):
		return 0
	var r := maxi(n, 0)
	for i in SEARCH_MAX:
		r = next_after(s, BOSS, r)
		if r <= 0:
			return 0
		if boss_type_at(s, r) == type:
			return r
	return 0
