class_name ZombieVoice
extends RefCounted
## Choix et rythme des sons d'un zombie (règles pures, cosmétiques, non
## synchronisées). Comme dans BO1 : des râles rauques espacés pour les
## marcheurs, des cris plus fréquents pour les coureurs, jamais deux fois
## de suite la même variante pour un même zombie ; la polyphonie globale est
## plafonnée par Audio (groupe « zombie »).

const GROANS := 8
const SPRINTS := 4
const ATTACKS := 4
const DEATHS := 4
const STEPS := 4
## Intervalle entre deux vocalises (s) : marcheur, coureur.
const WALK_INTERVAL := Vector2(4.0, 9.5)
const RUN_INTERVAL := Vector2(2.2, 5.0)
## Premier râle après l'apparition (s), étalé pour éviter les chœurs.
const FIRST_DELAY := Vector2(0.6, 4.0)
## Pas audibles seulement de près (m).
const STEP_RANGE := 14.0
const GROUP := "zombie"
const STEP_GROUP := "zombie_step"


## Variante 1..count différente de `last` (0 = aucune).
static func pick(count: int, last: int, roll: int) -> int:
	if count <= 1:
		return 1
	var v := 1 + posmod(roll, count - 1)
	if last >= 1 and v >= last:
		v += 1
	return v if last >= 1 else 1 + posmod(roll, count)


static func vocal_name(speed_class: int, variant: int) -> String:
	return ("zombie_sprint_%d" if speed_class >= 2 else "zombie_groan_%d") % variant


static func vocal_count(speed_class: int) -> int:
	return SPRINTS if speed_class >= 2 else GROANS


static func interval(speed_class: int, u: float) -> float:
	var r := RUN_INTERVAL if speed_class >= 2 else WALK_INTERVAL
	return lerpf(r.x, r.y, clampf(u, 0.0, 1.0))
