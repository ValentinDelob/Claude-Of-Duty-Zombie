class_name CodexState
extends RefCounted
## Codex (bestiaire du hub, GAME_CONCEPT §4.17) du profil : types d'ennemis
## RENCONTRÉS par le joueur (coup porté ou reçu, élimination ; XpRules
## « met ») et nombre d'éliminations par type. Un type jamais rencontré reste
## une fiche « ??? » au hub (onglet CODEX). Données pures ; enregistré dans le
## profil (section « codex », PlayerProfile.to_dict), rempli UNE fois par
## partie avec le relevé du joueur local (MatchXp.apply) : en coop, chaque
## joueur remplit son propre codex.
##
## Format : {"enemies": {type: éliminations (≥ 0)}, "seen": [type...]}.
## « seen » : fiches déjà vues dans l'onglet CODEX (les autres portent la
## pastille NOUVEAU). Section absente (profil plus ancien) : codex vide.

## Plafond des compteurs (comme PlayerProfile.VALUE_CAP).
const CAP := 1 << 52

## Type -> éliminations ; présent = rencontré.
var enemies: Dictionary = {}
## Types dont la fiche a été vue au hub.
var seen: PackedStringArray = []


func is_known(type: String) -> bool:
	return enemies.has(type)


func kills(type: String) -> int:
	return int(enemies.get(type, 0))


## Note une rencontre ; vrai si le type est nouveau.
func encounter(type: String) -> bool:
	if not ProfileValues.id_ok(type) or enemies.has(type):
		return false
	enemies[type] = 0
	return true


## Ajoute `n` éliminations (une élimination est aussi une rencontre) ; vrai si
## le type est nouveau.
func add_kills(type: String, n: int) -> bool:
	if not ProfileValues.id_ok(type):
		return false
	var fresh := not enemies.has(type)
	enemies[type] = mini(kills(type) + clampi(n, 0, CAP), CAP)
	return fresh


## Ajoute le relevé d'une partie (XpRules : « kills » et « met ») ; rend les
## types découverts pendant cette partie.
func record_ledger(l: Dictionary) -> PackedStringArray:
	var fresh := PackedStringArray()
	var k: Variant = l.get("kills", {})
	for t in XpRules.met_types(l):
		var n := int(k.get(t, 0)) if k is Dictionary else 0
		if add_kills(t, n):
			fresh.append(t)
	return fresh


## Fiche découverte mais pas encore vue au hub (pastille NOUVEAU).
func is_new(type: String) -> bool:
	return is_known(type) and not type in seen


func mark_seen(type: String) -> void:
	if is_known(type) and not type in seen:
		seen.append(type)


## Nombre de fiches nouvelles parmi `types` (tous les types connus si vide).
func new_count(types: PackedStringArray = []) -> int:
	var n := 0
	for t in (types if not types.is_empty() else PackedStringArray(enemies.keys())):
		if is_new(t):
			n += 1
	return n


func to_dict() -> Dictionary:
	var s := PackedStringArray()
	for t in seen:
		if is_known(t):
			s.append(t)
	return {"enemies": enemies.duplicate(), "seen": Array(s)}


## Codex lu depuis la section « codex » d'un profil (null / absente : codex
## vide). Entrées illisibles écartées et comptées dans `dropped`.
static func from_dict(v: Variant, dropped := [0]) -> CodexState:
	var c := CodexState.new()
	if v == null:
		return c
	if not v is Dictionary:
		dropped[0] += 1
		return c
	var e: Variant = (v as Dictionary).get("enemies", {})
	if e is Dictionary:
		for t in e:
			var n := ProfileValues.to_int(e[t], -1, -1, CAP)
			if (t is String or t is StringName) and ProfileValues.id_ok(String(t)) and n >= 0:
				c.enemies[String(t)] = n
			else:
				dropped[0] += 1
	else:
		dropped[0] += 1
	var s: Variant = (v as Dictionary).get("seen", [])
	if s is Array:
		for t in s:
			var id := ProfileValues.clean_id(t)
			if id == "":
				dropped[0] += 1
			else:
				c.mark_seen(id)
	else:
		dropped[0] += 1
	return c
