class_name PlayerEnergy
extends RefCounted
## Énergie du joueur (GAME_CONCEPT §4.14, docs/ENERGY_PLAN.md). Jauge
## invisible de 0 à `max_value`, calculée chez le joueur qui la vit (aucun
## message réseau). Logique pure, sans nœud : Player l'avance à chaque image
## physique et la dépense au saut et au coup de couteau.
##
## * Vidée par la course (SPRINT_COST par seconde), le saut (JUMP_COST) et les
##   coups de corps à corps (statistique « energy » de l'arme, KnifeDB).
## * Rechargée hors course après REGEN_DELAY sans dépense.
## * Épuisé : commence quand l'énergie touche 0, finit quand elle remonte à
##   RECOVER_AT (sinon les pénalités disparaîtraient dès la première image de
##   recharge). Épuisé : plus de course, coups deux fois plus lents, sauts
##   plus petits, recharge 25 % plus lente.
## * Une dépense plus grande que l'énergie restante se fait quand même :
##   l'énergie tombe à 0 (la pénalité suffit, aucune action refusée).

## Énergie de base (sans atout).
const MAX := 100.0
## Course : énergie par seconde (4 s de course pleine).
const SPRINT_COST := 25.0
## Saut : énergie par saut (environ 10 sauts d'affilée).
const JUMP_COST := 10.0
## Recharge (énergie par seconde) : 2,5 s pour tout remplir.
const REGEN_RATE := 40.0
## Délai sans dépense avant que la recharge reprenne (s).
const REGEN_DELAY := 0.4
## Épuisé : recharge 25 % plus lente (30 / s).
const EXHAUSTED_REGEN_MULT := 0.75
## Épuisé : l'état prend fin quand l'énergie remonte à ce seuil.
const RECOVER_AT := 50.0
## Énergie minimale pour (re)lancer une course : pas de sprint d'une image
## (0,5 s de course).
const SPRINT_RESTART_MIN := 12.5
## Épuisé : vitesse de saut (environ 56 % de la hauteur).
const EXHAUSTED_JUMP_MULT := 0.75
## Épuisé : durée d'un coup de corps à corps (cadence divisée par 2).
const EXHAUSTED_MELEE_TIME_MULT := 2.0

var value := MAX
var max_value := MAX
var exhausted := false
## Temps écoulé depuis la dernière dépense (s) : la recharge attend REGEN_DELAY.
var _idle := REGEN_DELAY


## Une image physique : la course dépense, sinon recharge après le délai.
func tick(delta: float, sprinting: bool) -> void:
	if delta <= 0.0:
		return
	if sprinting:
		_drain(SPRINT_COST * delta)
		return
	_idle += delta
	if _idle < REGEN_DELAY:
		return
	var rate := REGEN_RATE * (EXHAUSTED_REGEN_MULT if exhausted else 1.0)
	value = minf(value + rate * delta, max_value)
	if exhausted and value >= minf(RECOVER_AT, max_value):
		exhausted = false


## Dépense ponctuelle (saut, coup) : faite même si l'énergie manque.
func spend(amount: float) -> void:
	if amount <= 0.0:
		return
	_drain(amount)


## Course autorisée au départ : assez d'énergie et pas épuisé.
func can_start_sprint() -> bool:
	return not exhausted and value >= SPRINT_RESTART_MIN


## Multiplicateur de la vitesse de saut (sauts plus petits épuisé).
func jump_velocity_mult() -> float:
	return EXHAUSTED_JUMP_MULT if exhausted else 1.0


## Multiplicateur de la durée d'un coup de corps à corps (plus lents épuisé).
func melee_time_mult() -> float:
	return EXHAUSTED_MELEE_TIME_MULT if exhausted else 1.0


## Part de l'énergie restante (0 à 1), pour le retour sonore.
func ratio() -> float:
	return clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


## Énergie max en plus (atout STRIDE SODA, à supprimer avec les atouts).
## L'énergie courante n'est pas remplie : elle remonte par la recharge.
func set_bonus_max(bonus: float) -> void:
	max_value = MAX + maxf(bonus, 0.0)
	value = minf(value, max_value)


func _drain(amount: float) -> void:
	value = maxf(value - amount, 0.0)
	_idle = 0.0
	if value <= 0.0:
		exhausted = true
