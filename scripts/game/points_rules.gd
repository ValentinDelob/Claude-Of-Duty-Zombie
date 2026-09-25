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
