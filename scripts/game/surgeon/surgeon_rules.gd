class_name SurgeonRules
extends RefCounted
## Règles du premier boss, « Le Chirurgien » / « The Surgeon » (GAME_CONCEPT.md
## §4.4 : vague de boss ; fonctions pures, tests/test_surgeon.gd). Valeurs
## PROVISOIRES (GAME_CONCEPT.md §6 bis), à régler en jeu.
##
## Composition : UN Chirurgien par vague de boss, quel que soit le nombre de
## joueurs ; ses PV montent avec eux (PLAYER_HP par joueur en plus). Escorte
## de ESCORT_PER_PLAYER zombies ordinaires de la manche par joueur (au plus
## ESCORT_MAX) après l'annonce. Chaque zombie de la vague (escorte, patients
## relevés par l'opération, Chirurgien) fait le tirage des échantillons.
##
## PV : HP_FACTOR × PV d'un zombie de la manche (RoundRules.zombie_health)
## × (1 + PLAYER_HP × (joueurs − 1)) × (1 + HP_GROWTH × (rang − 1)), rang =
## numéro de la vague du Chirurgien dans la partie (§4.4 : chaque nouvelle
## apparition est plus forte). Manche 15, seul, première : 30 × 1 550 =
## 46 500 PV ; à 4 : 151 125 ; manche 30, seul, deuxième : 30 × 3 050 × 1,25
## = 114 375.
##
## Combat (serveur, Surgeon) : attaques TÉLÉGRAPHIÉES, deux phases.
##  * Combo au scalpel (au contact, < SLASH_START m) : il lève le scalpel
##    (lame qui brille, « chiing », SLASH_WINDUP s) puis enchaîne SLASH_HITS
##    entailles (3 en phase 2), chacune avec une petite fente en avant ;
##    dégâts SLASH_DAMAGE aux joueurs dans l'arc devant lui (in_slash_arc).
##  * Scalpels lancés (à distance, THROW_MIN à THROW_MAX m, en vue) : bras
##    armé au-dessus de l'épaule (THROW_WINDUP s), puis éventail de
##    THROW_COUNT scalpels cubiques (5 en phase 2), projectiles visibles
##    (THROW_SPEED m/s) que l'on peut esquiver ; THROW_DAMAGE chacun.
##  * Opération (PV sous SURGERY_AT : 75 % et 25 %, une fois chacune) : il
##    s'arrête, se penche sur un patient invisible et relève SUMMON_PER_PLAYER
##    zombies par joueur autour de lui (au plus SUMMON_MAX) pendant
##    SURGERY_TIME s (les zombies sortent de terre).
##  * Changement de phase (PV ≤ ENRAGE_AT, 50 %) : il arrache sa blouse et
##    rugit (ROAR_TIME s, immobile) ; à ROAR_SHOCK_AT s, onde de choc :
##    SHOCK_DAMAGE et projection des joueurs à moins de SHOCK_RADIUS m. Puis
##    ENRAGÉ : plus rapide, préparations plus courtes, plus de coups et de
##    scalpels, cœur et yeux qui flamboient.
##  * Point faible : le CŒUR MUTANT, à vif dans sa poitrine (multiplicateur
##    de tête de l'arme) ; la tête compte comme le corps.

## Escorte et opération.
const ESCORT_PER_PLAYER := 6
const ESCORT_MAX := 24
const SUMMON_PER_PLAYER := 2
const SUMMON_MAX := 8
## PV.
const HP_FACTOR := 30.0
const PLAYER_HP := 0.75
const HP_GROWTH := 0.25
## Annonce (bandeau, moniteur cardiaque, rire) avant son arrivée.
const START_DELAY := 7.0
## Distance au joueur visé à l'apparition (m).
const SPAWN_MIN_DIST := 14.0
const SPAWN_MAX_DIST := 30.0
## Déplacement (m/s) : phase 1, phase 2 (enragé).
const WALK_SPEED := 1.9
const RAGE_WALK_SPEED := 2.7
## Seuils (fraction des PV) : phase 2 et opérations.
const ENRAGE_AT := 0.5
const SURGERY_AT := [0.75, 0.25]
## Combo au scalpel.
const SLASH_START := 2.3
const SLASH_REACH := 2.7
## Arc devant lui : cosinus minimal de l'angle (≈ 66° de chaque côté).
const SLASH_ARC := 0.4
const SLASH_WINDUP := 0.65
const RAGE_SLASH_WINDUP := 0.42
const SLASH_HITS := 2
const RAGE_SLASH_HITS := 3
## Durée d'une entaille et instant du coup dans l'entaille (s).
const SLASH_TIME := 0.42
const SLASH_HIT_AT := 0.16
const SLASH_DAMAGE := 35
## Fente en avant au début de chaque entaille (m/s, s).
const LUNGE_SPEED := 3.4
const LUNGE_TIME := 0.16
## Récupération après le combo (immobile, s) puis délai avant le suivant.
const SLASH_RECOVER := 0.6
const SLASH_COOLDOWN := 1.4
## Scalpels lancés.
const THROW_MIN := 5.0
const THROW_MAX := 20.0
const THROW_WINDUP := 0.85
const RAGE_THROW_WINDUP := 0.6
const THROW_RECOVER := 0.45
const THROW_COOLDOWN := 6.5
const RAGE_THROW_COOLDOWN := 4.0
const THROW_COUNT := 3
const RAGE_THROW_COUNT := 5
## Écart entre deux scalpels de l'éventail (rad).
const THROW_SPREAD := 0.13
const THROW_SPEED := 15.0
## Chute du scalpel (m/s²) et durée de vie (s).
const THROW_GRAVITY := 1.5
const THROW_LIFE := 2.2
const THROW_DAMAGE := 22
## Rayon de touche d'un scalpel autour de l'axe du joueur (m).
const THROW_HIT_RADIUS := 0.45
## Hauteur de lâcher (m, au-dessus des pieds).
const THROW_HEIGHT := 1.75
## Opération.
const SURGERY_TIME := 3.2
## Relève des patients : instant (s depuis le début de l'opération) et
## distance autour de lui (m).
const SUMMON_AT := 1.0
const SUMMON_MIN_DIST := 2.0
const SUMMON_MAX_DIST := 4.5
## Changement de phase.
const ROAR_TIME := 2.2
const ROAR_SHOCK_AT := 0.8
const SHOCK_RADIUS := 4.5
const SHOCK_DAMAGE := 20
const SHOCK_PUSH := 6.5
const SHOCK_UP := 3.0
const SHOCK_TIME := 0.3
## Délai après sa mort avant la fin de l'ambiance.
const END_DELAY := 2.5


## Nombre de Chirurgiens de la vague (un seul : c'est LE boss).
static func count(_players: int) -> int:
	return 1


## Nombre de zombies d'escorte.
static func escorts(players: int) -> int:
	return mini(maxi(players, 1) * ESCORT_PER_PLAYER, ESCORT_MAX)


## Patients relevés par une opération.
static func summons(players: int) -> int:
	return mini(maxi(players, 1) * SUMMON_PER_PLAYER, SUMMON_MAX)


## PV du Chirurgien à la manche `round_n`, `rank`-ième vague du Chirurgien
## de la partie (1 pour la première), contre `players` joueurs.
static func health(round_n: int, rank: int, players: int) -> int:
	var per_players := 1.0 + PLAYER_HP * float(maxi(players, 1) - 1)
	var growth := 1.0 + HP_GROWTH * float(maxi(rank, 1) - 1)
	return roundi(HP_FACTOR * RoundRules.zombie_health(round_n) * per_players * growth)


## Phase 2 (enragé) à `hp` PV sur `max_hp` ?
static func enraged(hp: int, max_hp: int) -> bool:
	return max_hp > 0 and float(hp) <= float(max_hp) * ENRAGE_AT


## Opération due : indice du premier seuil de SURGERY_AT franchi (PV ≤
## seuil) et pas encore fait (`done` : masque des opérations faites) ; -1 :
## aucune.
static func surgery_due(hp: int, max_hp: int, done: int) -> int:
	if max_hp <= 0:
		return -1
	for i in SURGERY_AT.size():
		if done & (1 << i) == 0 and float(hp) <= float(max_hp) * float(SURGERY_AT[i]):
			return i
	return -1


## Préparations, nombre de coups et de scalpels, délais selon la phase.
static func slash_windup(rage: bool) -> float:
	return RAGE_SLASH_WINDUP if rage else SLASH_WINDUP


static func slash_hits(rage: bool) -> int:
	return RAGE_SLASH_HITS if rage else SLASH_HITS


static func throw_windup(rage: bool) -> float:
	return RAGE_THROW_WINDUP if rage else THROW_WINDUP


static func throw_count(rage: bool) -> int:
	return RAGE_THROW_COUNT if rage else THROW_COUNT


static func throw_cooldown(rage: bool) -> float:
	return RAGE_THROW_COOLDOWN if rage else THROW_COOLDOWN


static func walk_speed(rage: bool) -> float:
	return RAGE_WALK_SPEED if rage else WALK_SPEED


## Le joueur à `rel` (relatif au Chirurgien) est-il dans l'arc de l'entaille
## devant lui (`fwd` unitaire, plan horizontal) ?
static func in_slash_arc(rel: Vector3, fwd: Vector3) -> bool:
	var flat := Vector3(rel.x, 0.0, rel.z)
	var d := flat.length()
	if d > SLASH_REACH:
		return false
	if d < 0.4:
		return true
	return flat.dot(fwd) / d >= SLASH_ARC


## Le lancer peut-il partir ? `dist` : distance au sol, `dy` : écart de
## hauteur, `clear` : ligne de vue dégagée.
static func can_throw(dist: float, dy: float, clear: bool, cooldown: float) -> bool:
	return cooldown <= 0.0 and clear and dy < 2.5 and dist >= THROW_MIN and dist <= THROW_MAX


## Directions de l'éventail de `n` scalpels autour de `dir` (unitaire), de
## gauche à droite, à plat.
static func fan_dirs(dir: Vector3, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if flat == Vector3.ZERO:
		flat = Vector3.FORWARD
	for i in n:
		out.append(flat.rotated(Vector3.UP, (float(i) - float(n - 1) * 0.5) * THROW_SPREAD))
	return out


## Vitesse de départ d'un scalpel lancé de `from` vers `to` (vise un peu
## au-dessus de la cible, gravité compensée à mi-chemin), selon `dir` de
## l'éventail.
static func throw_velocity(from: Vector3, to: Vector3, dir: Vector3) -> Vector3:
	var flat_d := Vector2(to.x - from.x, to.z - from.z).length()
	var t := flat_d / THROW_SPEED
	var vy := ((to.y - from.y) + 0.5 * THROW_GRAVITY * t * t) / maxf(t, 0.05)
	return Vector3(dir.x, 0.0, dir.z).normalized() * THROW_SPEED + Vector3.UP * clampf(vy, -4.0, 4.0)


## Position d'un scalpel `t` s après son lancer (`p0`, `v0`).
static func scalpel_pos(p0: Vector3, v0: Vector3, t: float) -> Vector3:
	return p0 + v0 * t + Vector3.DOWN * 0.5 * THROW_GRAVITY * t * t


## Le segment de vol [a, b] passe-t-il assez près du joueur dont les pieds
## sont en `feet` (axe vertical de 0,2 à 1,8 m) ?
static func scalpel_hits(a: Vector3, b: Vector3, feet: Vector3) -> bool:
	# Distance entre le segment de vol et l'axe du joueur, par échantillons
	# (segments courts : un pas de physique, < 0,3 m).
	for i in 5:
		var p := a.lerp(b, i / 4.0)
		var y := clampf(p.y, feet.y + 0.2, feet.y + 1.8)
		if Vector3(p.x - feet.x, p.y - y, p.z - feet.z).length() <= THROW_HIT_RADIUS:
			return true
	return false


## Projection d'un joueur à `rel` (relatif au Chirurgien) par l'onde de choc.
static func shock_velocity(rel: Vector3) -> Vector3:
	var flat := Vector3(rel.x, 0.0, rel.z)
	var dir := flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
	return dir * SHOCK_PUSH + Vector3.UP * SHOCK_UP


## Le joueur à `rel` est-il pris dans l'onde de choc ?
static func in_shock(rel: Vector3) -> bool:
	return Vector3(rel.x, 0.0, rel.z).length() <= SHOCK_RADIUS and absf(rel.y) < 1.5
