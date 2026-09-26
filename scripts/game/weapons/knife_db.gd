class_name KnifeDB
extends RefCounted
## Couteaux de mêlée (BO1 Zombies). Données et règles pures, partagées par le
## client (prédiction : fente, animation) et le serveur (validation, dégâts).
##
## * Couteau de départ : 150 dégâts (tue en un coup à la manche 1, deux à la 2...).
## * COUTEAU DE CHASSE (Bowie Knife de Kino der Toten) : acheté au mur 3000,
##   il remplace le couteau ; ~1300 dégâts : un coup jusqu'à la manche 12.
## * Fente : si un zombie est visé à portée de fente (~3 m devant), le joueur se
##   projette vers lui en LUNGE_TIME avant de frapper, comme dans BO1.

const DEFAULT := "knife"
const KNIVES := {
	"knife": {"name": "COUTEAU", "damage": 150, "model": "knife"},
	"bowie": {"name": "COUTEAU DE CHASSE", "damage": 1300, "model": "bowie", "wall_cost": 3000},
}

## Portée d'un coup sans fente (m, horizontale, depuis le joueur).
const RANGE := 1.9
## Distance max d'une fente (m, jusqu'au zombie).
const LUNGE_RANGE := 3.2
## Durée de la projection (s).
const LUNGE_TIME := 0.15
## Distance à laquelle la fente s'arrête devant le zombie (m).
const LUNGE_STOP := 1.0
## Cône de visée d'une fente (cosinus : ~20° de part et d'autre du regard).
const LUNGE_CONE := 0.93
## Cône d'un coup au contact (cosinus, ~63°).
const MELEE_CONE := 0.45
## Durée de l'animation de récupération du couteau de chasse (s).
const PICKUP_TIME := 2.0


static func exists(id: String) -> bool:
	return KNIVES.has(id)


static func info(id: String) -> Dictionary:
	return KNIVES.get(id, KNIVES[DEFAULT])


static func damage(id: String) -> int:
	return int(info(id).damage)


static func display_name(id: String) -> String:
	return info(id).name


static func model(id: String) -> String:
	return info(id).model


static func wall_cost(id: String) -> int:
	return int(info(id).get("wall_cost", 0))


## Choisit la cible d'un coup de couteau parmi `positions` (pieds des zombies).
## `origin` : position du joueur, `dir` : regard. Un coup au contact (< `reach`)
## accepte un large cône ; au-delà et jusqu'à `lunge_reach`, seul un zombie
## visé (LUNGE_CONE) déclenche une fente. Retourne l'index retenu (le plus
## proche) ou -1.
static func pick_target(origin: Vector3, dir: Vector3, positions: Array, reach := RANGE, lunge_reach := LUNGE_RANGE) -> int:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return -1
	flat = flat.normalized()
	var best := -1
	var best_d := INF
	for i in positions.size():
		var p: Vector3 = positions[i]
		if absf(p.y - origin.y) > 1.6:
			continue
		var to := Vector3(p.x - origin.x, 0.0, p.z - origin.z)
		var d := to.length()
		if d >= best_d:
			continue
		var ok := false
		if d < 0.6:
			ok = true
		elif d < reach:
			ok = to.normalized().dot(flat) > MELEE_CONE
		elif d <= lunge_reach:
			ok = to.normalized().dot(flat) > LUNGE_CONE
		if ok:
			best = i
			best_d = d
	return best


## Vrai si frapper une cible à `distance` demande une fente.
static func needs_lunge(distance: float) -> bool:
	return distance > RANGE * 0.75
