class_name RoundRules
extends RefCounted
## Formules des manches (fonctions pures, testées unitairement).
## Nombre de zombies, délai d'apparition et vitesse de course repris de
## Black Ops 1 (_zombiemode.gsc) ; santé linéaire propre au jeu (§4.3 de
## GAME_CONCEPT.md).

## zombie_max_ai : jamais plus de 24 zombies vivants en même temps.
const MAX_ALIVE := 24
## zombie_ai_per_player
const AI_PER_PLAYER := 6
## zombie_between_round_time
const INTERMISSION := 10.0
const FIRST_ROUND_DELAY := 4.0
## zombie_spawn_delay (manche 1) et facteur appliqué à chaque manche.
const SPAWN_DELAY := 2.0
const SPAWN_DELAY_FACTOR := 0.95
const SPAWN_DELAY_MIN := 0.08
## zombie_move_speed_multiplier (difficulté normale).
const MOVE_SPEED_MULT := 8

## Classes de vitesse du zombie (index dans Zombie.SPEEDS).
const WALK := 0
const RUN := 2
const SPRINT := 3
## Règle du joueur (demande explicite) : que des marcheurs aux manches 1 à 3,
## des coureurs peuvent apparaître à partir de la manche 4. Le tirage de BO1
## seul ([manche x 8, manche x 8 + 35]) en sortait déjà dès la manche 1
## (tirages 36 à 43 : ~22 % de coureurs).
const RUNNERS_FROM_ROUND := 4
## 💡 Course progressive (demande du joueur : tous couraient d'un coup à la
## manche 4, le tirage de BO1 n'y laissant que 11 % de marcheurs et aucun à
## la 5) : de la manche 4 à la 7, une part croissante des zombies court
## (20 %, 40 %, 60 %, 80 %) ; TOUS courent (ou sprintent) à partir de la
## manche 8, jamais avant.
const ALL_RUN_FROM_ROUND := 8


## Nombre total de zombies de la manche.
static func zombie_count(round_n: int, players: int) -> int:
	var mult := maxf(round_n / 5.0, 1.0)
	if round_n >= 10:
		mult *= round_n * 0.15
	var n := MAX_ALIVE
	if players <= 1:
		n += int(0.5 * AI_PER_PLAYER * mult)
	else:
		n += int((players - 1) * AI_PER_PLAYER * mult)
	var early := {1: 0.25, 2: 0.3, 3: 0.5, 4: 0.7, 5: 0.9}
	if early.has(round_n):
		n = int(n * early[round_n])
	return n


## Points de vie d'un zombie : 150 à la manche 1, puis +100 par manche, sans
## plafond (GAME_CONCEPT §4.3). Remplace la formule de BO1 (+10 % par manche
## après la 9), qui atteignait des millions de PV.
static func zombie_health(round_n: int) -> int:
	return 150 + 100 * (maxi(round_n, 1) - 1)


## Nombre max de zombies vivants simultanément.
static func max_alive(_round_n: int, _players: int) -> int:
	return MAX_ALIVE


## Délai entre deux apparitions (s) : 2 s, x0.95 à chaque manche.
static func spawn_interval(round_n: int, _players: int) -> float:
	return maxf(SPAWN_DELAY * pow(SPAWN_DELAY_FACTOR, round_n - 1), SPAWN_DELAY_MIN)


## Vitesse de base de la manche (level.zombie_move_speed).
static func move_speed(round_n: int) -> int:
	return round_n * MOVE_SPEED_MULT


## Part des zombies de la manche qui courent ou sprintent (0 à 1) : 0 avant
## RUNNERS_FROM_ROUND, puis linéaire jusqu'à 1 à ALL_RUN_FROM_ROUND.
static func run_share(round_n: int) -> float:
	if round_n < RUNNERS_FROM_ROUND:
		return 0.0
	if round_n >= ALL_RUN_FROM_ROUND:
		return 1.0
	return float(round_n - RUNNERS_FROM_ROUND + 1) / float(ALL_RUN_FROM_ROUND - RUNNERS_FROM_ROUND + 1)


## Part des sprinteurs (0 à 1), calendrier de BO1 inchangé : part des tirages
## de [vitesse, vitesse + 35] au-delà de 70 (manche 5 : 14 %, 6 : 36 %, 7 :
## 58 %, 8 : 81 %, tous à partir de la 9), jamais avant RUNNERS_FROM_ROUND
## et jamais plus que run_share (un sprinteur est un coureur plus rapide).
static func sprint_share(round_n: int) -> float:
	if round_n < RUNNERS_FROM_ROUND:
		return 0.0
	var s := move_speed(round_n)
	return minf(clampf(float(s + 35 - 70) / 36.0, 0.0, 1.0), run_share(round_n))


## Classe de vitesse pour un tirage uniforme `u` dans [0, 1) : sprinteur sous
## sprint_share, coureur sous run_share, marcheur au-delà.
static func speed_for_share(round_n: int, u: float) -> int:
	if u < sprint_share(round_n):
		return SPRINT
	if u < run_share(round_n):
		return RUN
	return WALK


## Classe de vitesse d'un nouveau zombie (tirée par le serveur, qui l'envoie
## aux clients avec l'apparition) : marcheur avant RUNNERS_FROM_ROUND (aucun
## tirage), ensuite un tirage du générateur de la partie (speed_for_share).
static func pick_speed(round_n: int, rng: RandomNumberGenerator) -> int:
	if round_n < RUNNERS_FROM_ROUND:
		return WALK
	return speed_for_share(round_n, rng.randf())
