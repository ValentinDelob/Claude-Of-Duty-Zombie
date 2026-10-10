class_name WaveRules
extends RefCounted
## Schéma d'apparition des vagues spéciales et des vagues de boss d'une carte
## (GAME_CONCEPT.md §4.4 ; fonctions pures, tests/test_wave_rules.gd).
##
## Le schéma est un dictionnaire {type: {premiere, intervalle}} :
##   speciale  vague spéciale (mini-boss : aujourd'hui la meute de chiens) ;
##   boss      vague de boss (aucun boss n'existe encore : sans boss défini,
##             la vague de boss ne fait rien et la manche reste normale).
## « premiere » : première manche du type (0 : jamais) ; « intervalle » :
## écart entre deux vagues du type (0 : une seule, à « premiere »).
## Défaut : une vague spéciale toutes les 5 manches (5, 10, 15...), un boss
## toutes les 15 (15, 30...). Une manche à la fois spéciale et de boss est une
## vague de boss si un boss est défini, sinon une vague spéciale.
##
## Éditeur (format 18) : clé « vagues » de carte.json, mêmes clés, jamais
## écrite à sa valeur par défaut (EditorMap.set_waves).

const SPECIAL := "speciale"
const BOSS := "boss"
const KINDS := [SPECIAL, BOSS]
const DEFAULT := {
	SPECIAL: {"premiere": 5, "intervalle": 5},
	BOSS: {"premiere": 15, "intervalle": 15},
}
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
	for kind in KINDS:
		var e: Variant = (v as Dictionary).get(kind)
		if not e is Dictionary:
			continue
		for key in ["premiere", "intervalle"]:
			var n: Variant = (e as Dictionary).get(key)
			if (n is int or n is float) and is_finite(float(n)):
				out[kind][key] = clampi(int(n), 0, ROUND_MAX)
	return out


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
