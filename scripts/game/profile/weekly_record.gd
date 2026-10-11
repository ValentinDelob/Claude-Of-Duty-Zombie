class_name WeeklyRecord
extends RefCounted
## Résultats du défi hebdomadaire dans le profil (GAME_CONCEPT §4.18 ;
## section « weekly » du profil, version 3 de ProfileStore) : pour chaque
## semaine jouée (clé ISO « 2026-W41 », WeeklyChallenge.key_of) le meilleur
## résultat et la récompense déjà donnée (une fois par semaine).
##
## Entrée : {"best": manche la plus haute atteinte, "evac": manche la plus
## haute à laquelle l'équipe s'est évacuée (0 : jamais), "runs": parties
## jouées, "rewarded": récompense de la semaine donnée}. Seules les
## KEEP_WEEKS semaines les plus récentes sont gardées (le fichier ne grossit
## pas). Données pures ; règles du défi : WeeklyChallenge.

const KEEP_WEEKS := 12
const ROUND_CAP := 1000000

## Clé de semaine -> entrée.
var weeks: Dictionary = {}


## Entrée d'une semaine (copie, valeurs par défaut si jamais jouée).
func entry(key: String) -> Dictionary:
	var e: Dictionary = weeks.get(key, {})
	return {"best": int(e.get("best", 0)), "evac": int(e.get("evac", 0)),
		"runs": int(e.get("runs", 0)), "rewarded": bool(e.get("rewarded", false))}


func played(key: String) -> bool:
	return weeks.has(key)


func is_rewarded(key: String) -> bool:
	return bool(weeks.get(key, {}).get("rewarded", false))


## Enregistre une partie de la semaine `key` (manche atteinte, évacuation).
## Vrai si c'est un nouveau meilleur résultat (manche plus haute, ou
## évacuation plus tardive).
func record(key: String, round_reached: int, evacuated: bool) -> bool:
	if WeeklyChallenge.parse_key(key).x <= 0:
		return false
	var e := entry(key)
	var r := clampi(round_reached, 0, ROUND_CAP)
	var better := r > int(e.best) or (evacuated and r > int(e.evac))
	e.best = maxi(int(e.best), r)
	if evacuated:
		e.evac = maxi(int(e.evac), r)
	e.runs = mini(int(e.runs) + 1, ROUND_CAP)
	weeks[key] = e
	_prune()
	return better


func mark_rewarded(key: String) -> void:
	var e := entry(key)
	e.rewarded = true
	weeks[key] = e
	_prune()


func to_dict() -> Dictionary:
	var out := {}
	for k in weeks:
		out[k] = entry(k)
	return out


## Lecture tolérante : entrée illisible écartée et comptée dans `dropped`.
## Section absente (profil v1 ou v2) : aucun résultat.
static func from_dict(d: Variant, dropped := [0]) -> WeeklyRecord:
	var w := WeeklyRecord.new()
	if d == null:
		return w
	if not d is Dictionary:
		dropped[0] += 1
		return w
	for k in d:
		var e: Variant = d[k]
		if not (k is String or k is StringName) or WeeklyChallenge.parse_key(String(k)).x <= 0 or not e is Dictionary:
			dropped[0] += 1
			continue
		var rw: Variant = e.get("rewarded", false)
		w.weeks[String(k)] = {
			"best": ProfileValues.to_int(e.get("best"), 0, 0, ROUND_CAP),
			"evac": ProfileValues.to_int(e.get("evac"), 0, 0, ROUND_CAP),
			"runs": ProfileValues.to_int(e.get("runs"), 0, 0, ROUND_CAP),
			"rewarded": rw is bool and rw,
		}
	w._prune()
	return w


## Garde les KEEP_WEEKS semaines les plus récentes (clés triables).
func _prune() -> void:
	if weeks.size() <= KEEP_WEEKS:
		return
	var keys := weeks.keys()
	keys.sort()
	for i in keys.size() - KEEP_WEEKS:
		weeks.erase(keys[i])
