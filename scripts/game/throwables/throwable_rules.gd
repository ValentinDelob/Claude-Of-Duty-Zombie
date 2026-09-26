class_name ThrowableRules
extends RefCounted
## Règles des objets lancés de BO1 Zombies (fonctions pures, testées
## unitairement) : grenades à fragmentation (arme létale) et SINGE-TAMBOUR
## (arme tactique, le « Cymbal Monkey » de BO1).

enum Kind { FRAG, MONKEY }

# ---------------------------------------------------------------- réserve
## Grenades au début de la partie, gain au début de chaque manche, maximum.
const FRAG_START := 2
const FRAG_PER_ROUND := 2
const FRAG_MAX := 4
## Achat mural (Kino der Toten) : recharge à FRAG_MAX.
const FRAG_WALL_COST := 250
## Singes donnés par la boîte mystère (et rendus par MUNITIONS MAX). Pas de
## recharge à chaque manche, comme dans BO1.
const MONKEY_MAX := 3
## Identifiant du singe dans la boîte mystère (ce n'est pas une arme).
const MONKEY_ID := "monkey"
const MONKEY_NAME := "SINGE-TAMBOUR"
const MONKEY_BOX_WEIGHT := 1.0

# ---------------------------------------------------------------- grenade
## Mèche : comptée depuis le dégoupillage (maintenir la touche = « cuire »).
const FUSE := 4.0
## Rayon et dégâts de l'explosion (au centre ; 50 % au bord). Tue en un coup
## jusqu'aux manches 10-11 à 1 m du point d'impact (1045 / 1149 PV).
const FRAG_RADIUS := 5.0
const FRAG_DAMAGE := 1300
## Dégâts subis par le lanceur (réduits, comme BO1 ; jamais aux coéquipiers).
const FRAG_SELF_DAMAGE := 80

# ---------------------------------------------------------------- singe
## Durée de la musique : tous les zombies convergent vers le singe.
const MONKEY_TIME := 8.0
## Explosion finale : tue tout ce qui l'entoure, quelle que soit la manche.
const MONKEY_RADIUS := 4.5
const MONKEY_DAMAGE := 100000
const MONKEY_SELF_DAMAGE := 60
## Les zombies arrivés à cette distance du singe l'encerclent sans avancer.
const LURE_STOP := 1.1

# ---------------------------------------------------------------- lancer
## Vitesse de lancer (m/s) et composante verticale ajoutée (lancer en cloche).
const FRAG_SPEED := 15.0
const MONKEY_SPEED := 10.5
const THROW_LIFT := 2.6
const GRAVITY := 14.0
const RADIUS := 0.05
## Rebond : part de la vitesse normale conservée, perte tangentielle.
const RESTITUTION := 0.42
const TANGENT_LOSS := 0.3
## Roulement au sol : freinage proportionnel (1/s) et constant (m/s²).
const ROLL_FRICTION := 1.6
const ROLL_DECEL := 5.0


## Réserve de grenades après le début d'une manche (+2, plafonnée à 4).
static func frags_after_round(current: int) -> int:
	return mini(maxi(current, 0) + FRAG_PER_ROUND, FRAG_MAX)


## L'achat mural est-il utile (réserve incomplète) ?
static func can_buy_frags(current: int) -> bool:
	return current < FRAG_MAX


## Temps restant avant l'explosion d'une grenade dégoupillée à `cook_start`.
static func fuse_left(cook_start: float, now: float) -> float:
	return FUSE - (now - cook_start)


## Vitesse initiale d'un objet lancé dans la direction `dir` (visée).
static func throw_velocity(kind: int, dir: Vector3) -> Vector3:
	var speed := FRAG_SPEED if kind == Kind.FRAG else MONKEY_SPEED
	return dir.normalized() * speed + Vector3.UP * THROW_LIFT


## Dégâts d'explosion à la distance `d` du centre (décroissance linéaire de
## 100 % à 50 % au bord, 0 au-delà).
static func splash(damage: int, radius: float, d: float) -> int:
	if d > radius or radius <= 0.0:
		return 0
	return int(float(damage) * (1.0 - d / radius * 0.5))


## Rebond d'une vitesse `vel` sur une surface de normale `n`.
static func bounce(vel: Vector3, n: Vector3) -> Vector3:
	var vn := vel.dot(n)
	if vn >= 0.0:
		return vel
	var normal := n * vn
	var tangent := vel - normal
	return tangent * (1.0 - TANGENT_LOSS) - normal * RESTITUTION


static func kind_name(kind: int) -> String:
	return "GRENADE" if kind == Kind.FRAG else MONKEY_NAME
