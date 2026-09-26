class_name BarricadeRules
extends RefCounted
## Règles des fenêtres barricadées (fonctions pures, testées unitairement).
##
## Comme dans Black Ops 1 : 6 planches par fenêtre, +10 points par planche
## reposée (multiplicateur « double points » compris), 500 points de
## réparation au plus par joueur et par manche.

const PLANKS := 6
const FULL_MASK := (1 << PLANKS) - 1
const POINTS_PER_PLANK := 10
const ROUND_CAP := 500
## Secondes de maintien de [F] par planche reposée (RAPID FIZZ : 2x plus vite).
const REPAIR_TIME := 0.75
## Secondes pour qu'un zombie arrache une planche (marcheur / coureur).
## BO1 : l'animation d'arrachage d'une planche dure environ 2 s ; un zombie seul
## met une dizaine de secondes à ouvrir une fenêtre de 6 planches.
const TEAR_TIME := 1.9
const TEAR_TIME_FAST := 1.5
## Pause aléatoire max entre deux planches (le zombie se ré-agrippe).
const TEAR_PAUSE_MAX := 0.4
## Durée du passage de la fenêtre (enjambement).
const VAULT_TIME := 1.1


## Points gagnés pour une planche reposée, compte tenu de ce que le joueur a
## déjà gagné en réparations pendant la manche.
static func repair_points(earned_this_round: int, multiplier := 1) -> int:
	var pts := POINTS_PER_PLANK * maxi(multiplier, 1)
	return clampi(ROUND_CAP - earned_this_round, 0, pts)


static func repair_interval(reload_mult := 1.0) -> float:
	return REPAIR_TIME * reload_mult


static func tear_interval(speed_class: int) -> float:
	return TEAR_TIME_FAST if speed_class >= 2 else TEAR_TIME


static func count(mask: int) -> int:
	var n := 0
	for i in PLANKS:
		if mask & (1 << i):
			n += 1
	return n


## Planche arrachée : la dernière posée (indice le plus haut présent), -1 si aucune.
static func plank_to_tear(mask: int) -> int:
	for i in range(PLANKS - 1, -1, -1):
		if mask & (1 << i):
			return i
	return -1


## Planche reposée : la première manquante, -1 si la fenêtre est complète.
static func plank_to_repair(mask: int) -> int:
	for i in PLANKS:
		if not (mask & (1 << i)):
			return i
	return -1
