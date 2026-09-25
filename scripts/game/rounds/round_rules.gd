class_name RoundRules
extends RefCounted
## Formules des manches (fonctions pures, testées unitairement).
## Inspirées de la progression classique : quelques marcheurs aux premières
## manches, puis des hordes de plus en plus nombreuses, résistantes et rapides.

const MAX_ALIVE := 24
const INTERMISSION := 9.0
const FIRST_ROUND_DELAY := 4.0

## Nombre total de zombies de la manche.
static func zombie_count(round_n: int, players: int) -> int:
	var early := [0, 6, 8, 13, 18, 24]
	var base: float
	if round_n < early.size():
		base = early[round_n]
	else:
		base = 24.0 + (round_n - 5) * 3.5 + pow(maxf(round_n - 10, 0), 1.6)
	var mult := 1.0 + 0.5 * (clampi(players, 1, 8) - 1)
	return int(round(base * mult))


## Points de vie d'un zombie.
static func zombie_health(round_n: int) -> int:
	if round_n < 10:
		return 150 + 100 * (round_n - 1)
	var h := 950.0
	for i in range(10, round_n + 1):
		h *= 1.1
	return int(h)


## Nombre max de zombies vivants simultanément.
static func max_alive(round_n: int, players: int) -> int:
	return mini(MAX_ALIVE, 6 + round_n * 2 + (players - 1) * 4)


## Délai entre deux apparitions (s).
static func spawn_interval(round_n: int, players: int) -> float:
	var t := 2.0 * pow(0.93, round_n - 1) / (1.0 + 0.25 * (players - 1))
	return maxf(t, 0.35)


## Poids des classes de vitesse [marche, trot, course, sprint].
static func speed_weights(round_n: int) -> Array:
	if round_n <= 2:
		return [1.0, 0.0, 0.0, 0.0]
	if round_n <= 4:
		return [0.6, 0.4, 0.0, 0.0]
	if round_n <= 7:
		return [0.25, 0.5, 0.25, 0.0]
	if round_n <= 10:
		return [0.1, 0.3, 0.45, 0.15]
	return [0.0, 0.15, 0.45, 0.4]


static func pick_speed(round_n: int, rng: RandomNumberGenerator) -> int:
	var w := speed_weights(round_n)
	var total := 0.0
	for v in w:
		total += v
	var r := rng.randf() * total
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return i
	return 0
