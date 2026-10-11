class_name BrancardRules
extends RefCounted
## Règles de la vague spéciale « Brancardier » (GAME_CONCEPT.md §4.4 :
## mini-boss, gros zombie qui charge ; fonctions pures, tests/test_brancardier.gd).
## Valeurs PROVISOIRES (GAME_CONCEPT.md §6 bis), à régler en jeu.
##
## Composition : BRANCARDIER_PER_PLAYER Brancardier par joueur (au plus
## MAX_TOTAL, MAX_ALIVE en même temps), accompagnés de ESCORT_PER_PLAYER
## zombies d'escorte par joueur (au plus ESCORT_MAX), zombies ordinaires de la
## manche (PV et vitesse de la manche). Chaque zombie de la vague, escorte
## comprise, fait le tirage des échantillons (§4.7 : 20 % par zombie de la
## vague) : à un joueur, 6 tirages par vague, comme la première meute.
##
## PV d'un Brancardier : HP_FACTOR × PV d'un zombie de la manche
## (RoundRules.zombie_health) × (1 + HP_GROWTH × (rang − 1)), rang = numéro
## de la vague du Brancardier dans la partie (§4.4 : chaque nouvelle
## apparition d'un même mini-boss est plus forte). Manche 10, première :
## 10 × 1 050 = 10 500 PV ; manche 20, deuxième : 10 × 2 050 × 1,2 = 24 600.
##
## Charge : à portée (CHARGE_MIN à CHARGE_MAX m), en vue directe et au même
## niveau, hors délai de recharge (CHARGE_COOLDOWN), il s'arrête, gratte du
## pied et rugit (WINDUP_TIME : télégraphiée), puis fonce en ligne droite
## (CHARGE_SPEED, au plus CHARGE_TIME). Un joueur sur sa route (CHARGE_HIT_RADIUS)
## prend CHARGE_DAMAGE et est projeté (KNOCK_*), une fois par charge. Contre
## un mur : ÉTOURDI (STUN_TIME) ; sinon il reprend la poursuite. Au contact :
## coup des deux poings (SMASH_*).

const BRANCARDIER_PER_PLAYER := 1
const MAX_TOTAL := 6
const MAX_ALIVE := 4
const ESCORT_PER_PLAYER := 5
const ESCORT_MAX := 20
const HP_FACTOR := 10.0
const HP_GROWTH := 0.2
## Annonce (bandeau, rugissement lointain) avant le premier Brancardier.
const START_DELAY := 6.0
## Attente entre deux apparitions de Brancardier (coop).
const SPAWN_WAIT := 4.0
## Distance au joueur visé à l'apparition (m).
const SPAWN_MIN_DIST := 12.0
const SPAWN_MAX_DIST := 28.0
## Déplacement : marche lourde (m/s).
const WALK_SPEED := 1.7
## Charge.
const CHARGE_MIN := 4.0
const CHARGE_MAX := 15.0
const CHARGE_COOLDOWN := 5.0
const WINDUP_TIME := 1.3
const CHARGE_SPEED := 8.5
const CHARGE_TIME := 2.2
const CHARGE_HIT_RADIUS := 1.15
const CHARGE_DAMAGE := 45
## Projection d'un joueur percuté : vitesse horizontale (m/s) dans l'axe de
## la charge et sur le côté, vitesse verticale (m/s), durée de la poussée (s).
const KNOCK_FORWARD := 7.0
const KNOCK_SIDE := 4.5
const KNOCK_UP := 3.5
const KNOCK_TIME := 0.35
const STUN_TIME := 3.0
## Mur heurté : face au mur à moins de cet angle (cosinus de la normale).
const WALL_FACING := 0.55
## Coup des deux poings au contact.
const SMASH_RANGE := 1.6
const SMASH_REACH := 2.0
const SMASH_TIME := 1.25
const SMASH_HIT_TIME := 0.6
const SMASH_DAMAGE := 60
## Délai après le dernier Brancardier avant la fin de l'ambiance.
const END_DELAY := 2.0


## Nombre de Brancardiers de la vague.
static func count(players: int) -> int:
	return mini(maxi(players, 1) * BRANCARDIER_PER_PLAYER, MAX_TOTAL)


## Nombre de zombies d'escorte de la vague.
static func escorts(players: int) -> int:
	return mini(maxi(players, 1) * ESCORT_PER_PLAYER, ESCORT_MAX)


## PV d'un Brancardier à la manche `round_n`, `rank`-ième vague du
## Brancardier de la partie (1 pour la première).
static func health(round_n: int, rank: int) -> int:
	return roundi(HP_FACTOR * RoundRules.zombie_health(round_n) * (1.0 + HP_GROWTH * float(maxi(rank, 1) - 1)))


## La charge peut-elle partir ? `dist` : distance au sol, `dy` : écart de
## hauteur, `clear` : ligne droite dégagée (décor, escaliers, largeur du corps).
static func can_charge(dist: float, dy: float, clear: bool, cooldown: float) -> bool:
	return cooldown <= 0.0 and clear and dy < 0.9 and dist >= CHARGE_MIN and dist <= CHARGE_MAX


## Le joueur à `rel` (position relative au Brancardier, plan horizontal) est-il
## sur la route de la charge de direction `dir` (unitaire) ?
static func in_charge_path(rel: Vector3, dir: Vector3) -> bool:
	var flat := Vector3(rel.x, 0.0, rel.z)
	var along := flat.dot(dir)
	if along < -0.3:
		return false
	return (flat - dir * clampf(along, 0.0, 0.9)).length() <= CHARGE_HIT_RADIUS


## Vitesse de projection d'un joueur à `rel` (relatif au Brancardier) par une
## charge de direction `dir` : vers l'avant et repoussé du côté où il se trouve.
static func knock_velocity(rel: Vector3, dir: Vector3) -> Vector3:
	var side := Vector3(dir.z, 0.0, -dir.x)
	var s := 1.0 if Vector3(rel.x, 0.0, rel.z).dot(side) >= 0.0 else -1.0
	return dir * KNOCK_FORWARD + side * s * KNOCK_SIDE + Vector3.UP * KNOCK_UP


## Mur de face ? `normal` : normale de la collision, `dir` : direction de la charge.
static func hits_wall(normal: Vector3, dir: Vector3) -> bool:
	var n := Vector3(normal.x, 0.0, normal.z)
	if n.length() < 0.5:
		return false
	return n.normalized().dot(-dir) >= WALL_FACING
