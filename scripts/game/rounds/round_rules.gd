class_name RoundRules
extends RefCounted
## Formules des manches (fonctions pures, testées unitairement).
## Reprise fidèle de Black Ops 1 (_zombiemode.gsc) : nombre de zombies,
## santé, délai d'apparition et vitesse de course.

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


## Points de vie d'un zombie : 150, +100 par manche jusqu'à la 9, puis +10 %.
static func zombie_health(round_n: int) -> int:
	var h := 150
	for i in range(2, round_n + 1):
		if i >= 10:
			h += int(h * 0.1)
		else:
			h += 100
	return h


## Nombre max de zombies vivants simultanément.
static func max_alive(_round_n: int, _players: int) -> int:
	return MAX_ALIVE


## Délai entre deux apparitions (s) : 2 s, x0.95 à chaque manche.
static func spawn_interval(round_n: int, _players: int) -> float:
	return maxf(SPAWN_DELAY * pow(SPAWN_DELAY_FACTOR, round_n - 1), SPAWN_DELAY_MIN)


## Vitesse de base de la manche (level.zombie_move_speed).
static func move_speed(round_n: int) -> int:
	return round_n * MOVE_SPEED_MULT


## Tirage de la vitesse d'un zombie : aléatoire dans [vitesse, vitesse + 35] ;
## <= 35 marche, <= 70 court, au-delà sprinte.
static func speed_for_roll(roll: int) -> int:
	if roll <= 35:
		return WALK
	if roll <= 70:
		return RUN
	return SPRINT


## Classe de vitesse d'un nouveau zombie : marcheur avant RUNNERS_FROM_ROUND,
## ensuite le tirage de BO1.
static func pick_speed(round_n: int, rng: RandomNumberGenerator) -> int:
	if round_n < RUNNERS_FROM_ROUND:
		return WALK
	var s := move_speed(round_n)
	return speed_for_roll(rng.randi_range(s, s + 35))
