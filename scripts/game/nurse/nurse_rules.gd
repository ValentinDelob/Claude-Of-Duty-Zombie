class_name NurseRules
extends RefCounted
## Règles de la vague spéciale « Infirmière hurlante » (GAME_CONCEPT.md §4.4 :
## mini-boss, cri qui attire et étourdit ; fonctions pures, tests/test_nurse.gd).
## Valeurs PROVISOIRES (GAME_CONCEPT.md §6 bis), à régler en jeu.
##
## Composition : NURSE_PER_PLAYER Infirmière par joueur (au plus MAX_TOTAL,
## MAX_ALIVE en même temps), avec ESCORT_PER_PLAYER zombies d'escorte par
## joueur (au plus ESCORT_MAX), zombies ordinaires de la manche : c'est eux
## que son cri ameute. Chaque zombie de la vague, escorte comprise, fait le
## tirage des échantillons (§4.7 : 20 % par zombie de la vague).
##
## PV d'une Infirmière : HP_FACTOR × PV d'un zombie de la manche
## (RoundRules.zombie_health) × (1 + HP_GROWTH × (rang − 1)), rang = numéro
## de la vague de l'Infirmière dans la partie (§4.4). Plus fragile que le
## Brancardier (elle fuit au lieu d'encaisser). Manche 15, première :
## 8 × 1 550 = 12 400 PV ; manche 30, deuxième : 8 × 3 050 × 1,2 = 29 280.
##
## Distance : elle garde ses distances. Plus près que FLEE_DIST, elle FUIT
## (FLEE_SPEED) vers un point dégagé loin des joueurs ; plus loin que
## KEEP_MAX ou hors de vue, elle approche (WALK_SPEED) ; entre les deux, elle
## reste face à sa proie. Acculée (fuite impossible), elle se défend : coup de
## seringue au contact (STAB_*).
##
## CRI : à portée (SCREAM_RANGE), en vue directe et au même niveau, hors délai
## (SCREAM_COOLDOWN), elle s'arrête et prend sa respiration (WINDUP_TIME :
## TÉLÉGRAPHIÉ, tête renversée, bras écartés, gorge et yeux qui flamboient,
## sifflement qui monte), puis hurle (SCREAM_TIME). Au début du hurlement :
##   - chaque joueur à moins de DAZE_RADIUS, en vue directe, est ÉTOURDI
##     (daze_time : plus long de près) : vue qui tangue, image « en cubes »,
##     déplacement ralenti (DAZE_SLOW au plus) ; SCREAM_DAMAGE dégâts ;
##     derrière un mur : rien (jouable : se mettre à couvert) ;
##   - chaque zombie à moins de RALLY_RADIUS est AMEUTÉ RALLY_TIME s : il
##     fonce (RALLY_SPEED) sur le joueur le plus proche de l'Infirmière.
## Point faible : la GORGE et la tête (multiplicateur de tête de l'arme). Une
## touche à la tête ou à la gorge pendant la préparation l'ÉTRANGLE : le cri
## avorte, elle tousse CHOKE_TIME s, immobile (récompense de la visée).

const NURSE_PER_PLAYER := 1
const MAX_TOTAL := 4
const MAX_ALIVE := 3
const ESCORT_PER_PLAYER := 6
const ESCORT_MAX := 24
const HP_FACTOR := 8.0
const HP_GROWTH := 0.2
## Annonce (bandeau, cri lointain) avant la première Infirmière.
const START_DELAY := 6.0
const SPAWN_WAIT := 4.0
const SPAWN_MIN_DIST := 12.0
const SPAWN_MAX_DIST := 26.0
## Déplacement (m/s) et distances gardées (m).
const WALK_SPEED := 1.9
const FLEE_SPEED := 3.4
const FLEE_DIST := 6.0
const KEEP_MAX := 12.0
## Fuite : point visé à FLEE_MIN..FLEE_MAX m d'elle ; acculée (aucun point,
## ou bloquée) : elle se défend CORNERED_TIME s avant de réessayer.
const FLEE_MIN := 4.0
const FLEE_MAX := 12.0
const CORNERED_TIME := 3.0
## Cri.
const SCREAM_RANGE := 14.0
const SCREAM_COOLDOWN := 8.0
const FIRST_SCREAM_DELAY := 2.5
const WINDUP_TIME := 1.4
const SCREAM_TIME := 1.2
const CHOKE_TIME := 2.0
const DAZE_RADIUS := 11.0
const DAZE_TIME_MAX := 3.0
const DAZE_TIME_MIN := 1.2
const DAZE_SLOW := 0.5
const SCREAM_DAMAGE := 10
const RALLY_RADIUS := 22.0
const RALLY_TIME := 5.0
const RALLY_SPEED := 1.45
## Coup de seringue au contact.
const STAB_RANGE := 1.3
const STAB_REACH := 1.8
const STAB_TIME := 0.9
const STAB_HIT_TIME := 0.42
const STAB_DAMAGE := 35
## Délai après la dernière Infirmière avant la fin de l'ambiance.
const END_DELAY := 2.0


static func count(players: int) -> int:
	return mini(maxi(players, 1) * NURSE_PER_PLAYER, MAX_TOTAL)


static func escorts(players: int) -> int:
	return mini(maxi(players, 1) * ESCORT_PER_PLAYER, ESCORT_MAX)


## PV d'une Infirmière à la manche `round_n`, `rank`-ième vague de
## l'Infirmière de la partie (1 pour la première).
static func health(round_n: int, rank: int) -> int:
	return roundi(HP_FACTOR * RoundRules.zombie_health(round_n) * (1.0 + HP_GROWTH * float(maxi(rank, 1) - 1)))


## Le cri peut-il partir ? `dist` : distance au sol de la proie, `dy` :
## écart de hauteur, `clear` : ligne de vue dégagée.
static func can_scream(dist: float, dy: float, clear: bool, cooldown: float) -> bool:
	return cooldown <= 0.0 and clear and dy < 1.5 and dist <= SCREAM_RANGE


## Mode de déplacement selon la distance à la proie la plus proche :
## "flee", "approach" ou "hold".
static func move_mode(dist: float, visible: bool) -> String:
	if dist < FLEE_DIST:
		return "flee"
	if dist > KEEP_MAX or not visible:
		return "approach"
	return "hold"


## Durée de l'étourdissement d'un joueur à `dist` m du cri (0 : épargné).
static func daze_time(dist: float) -> float:
	if dist > DAZE_RADIUS or dist < 0.0:
		return 0.0
	return lerpf(DAZE_TIME_MAX, DAZE_TIME_MIN, clampf(dist / DAZE_RADIUS, 0.0, 1.0))


## Force de l'étourdissement (0..1) d'un joueur à `dist` m du cri.
static func daze_strength(dist: float) -> float:
	if dist > DAZE_RADIUS or dist < 0.0:
		return 0.0
	return lerpf(1.0, 0.45, clampf(dist / DAZE_RADIUS, 0.0, 1.0))


## Multiplicateur de vitesse d'un joueur étourdi : `k` = force restante (0..1).
static func daze_speed_mult(k: float) -> float:
	return 1.0 - DAZE_SLOW * clampf(k, 0.0, 1.0)


## Un zombie à `dist` m du cri est-il ameuté ?
static func rallies(dist: float) -> bool:
	return dist >= 0.0 and dist <= RALLY_RADIUS


## Note d'un point de fuite `p` (plus grand = meilleur) pour une Infirmière
## en `from`, menacée par les joueurs `threats` : loin du joueur le plus
## proche, à FLEE_MIN..FLEE_MAX m d'elle, jamais en passant devant un joueur
## (point du côté opposé). -INF : point refusé.
static func flee_score(from: Vector3, p: Vector3, threats: Array) -> float:
	var d := Vector2(p.x - from.x, p.z - from.z).length()
	if d < FLEE_MIN or d > FLEE_MAX or absf(p.y - from.y) > 1.0:
		return -INF
	var nearest := INF
	var away := 0.0
	for t: Vector3 in threats:
		var td := Vector2(p.x - t.x, p.z - t.z).length()
		nearest = minf(nearest, td)
		var to_t := Vector2(t.x - from.x, t.z - from.z)
		var to_p := Vector2(p.x - from.x, p.z - from.z)
		if to_t.length() > 0.01 and to_p.length() > 0.01:
			away += -to_t.normalized().dot(to_p.normalized())
	if threats.is_empty():
		return d
	if nearest < FLEE_DIST + 1.0:
		return -INF
	return nearest + 3.0 * away / threats.size()
