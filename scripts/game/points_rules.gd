class_name PointsRules
extends RefCounted
## Barème des points (fonctions pures, testées unitairement).

const HIT := 10
const KILL := 50
const HEADSHOT_KILL := 100
const MELEE_KILL := 130
const SPLASH_KILL := 50
## Tuer avec un piège ne rapporte rien (le piège a déjà été payé).
const TRAP_KILL := 0
## Bonus de fin de manche par joueur vivant (optionnel).
const ROUND_SURVIVAL := 0


## Pénalités de BO1 (_zombiemode_score, player_reduce_points) : à terre, le
## joueur perd 5 % de ses points (arrondi à la dizaine supérieure), rendus au
## coéquipier qui le réanime ; s'il succombe, chacun des autres perd 10 %.
const PENALTY_DOWNED := 0.05
const PENALTY_NO_REVIVE := 0.10


## Arrondi à la dizaine supérieure (round_up_to_ten de BO1).
static func round_up_to_ten(n: int) -> int:
	var r := n - n % 10
	return r + 10 if r < n else r


## Points perdus en tombant à terre avec `points` points.
static func downed_loss(points: int) -> int:
	return mini(round_up_to_ten(int(points * PENALTY_DOWNED)), maxi(points, 0))


## Points perdus par un coéquipier quand un joueur succombe.
static func no_revive_loss(points: int) -> int:
	return mini(round_up_to_ten(int(points * PENALTY_NO_REVIVE)), maxi(points, 0))


## Points gagnés pour un coup porté à un zombie.
static func for_damage(killed: bool, headshot: bool, kind: int) -> int:
	match kind:
		Combat.HitKind.TRAP:
			return TRAP_KILL
		Combat.HitKind.MELEE:
			return MELEE_KILL if killed else HIT
		Combat.HitKind.SPLASH:
			return SPLASH_KILL if killed else HIT
	if not killed:
		return HIT
	return HEADSHOT_KILL if headshot else KILL
