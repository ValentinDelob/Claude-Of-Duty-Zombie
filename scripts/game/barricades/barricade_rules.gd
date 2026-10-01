class_name BarricadeRules
extends RefCounted
## Règles des fenêtres barricadées (fonctions pures, testées unitairement).
##
## Comme dans Black Ops 1 : 6 planches par fenêtre, +10 points par planche
## reposée (multiplicateur « double points » compris), 500 points de
## réparation au plus par joueur et par manche.

const PLANKS := 6
const FULL_MASK := (1 << PLANKS) - 1
const POINTS_PER_PLANK := 10
const ROUND_CAP := 500
## Secondes de maintien de [F] par planche reposée (RAPID FIZZ : 2x plus vite).
const REPAIR_TIME := 0.75
## Arrachage, par zombie (règle demandée par le joueur : une planche toutes les
## 2,5 s en moyenne, pause « de folie » entre deux planches). Un cycle =
## agrippe-tire (TEAR_PULL, la planche part à TEAR_RIP de ce geste) puis pause
## tirée au hasard dans [TEAR_PAUSE_MIN, TEAR_PAUSE_MAX] pendant laquelle le
## zombie s'agite contre la fenêtre. Moyenne 1,3 + 1,2 = 2,5 s, écart ±0,3 s.
## BO1 (_zombiemode_spawner.gsc, tear_into_building) : une animation
## d'arrachage par planche, entrecoupée d'attentes / provocations à la
## fenêtre ; la cadence ne dépend pas de la vitesse de course. Les valeurs
## exactes viennent de la demande du joueur (2,5 s), l'écart de ±0,3 s évite
## que plusieurs zombies arrachent en cadence. Une fenêtre de 6 planches :
## ~14 s pour un zombie seul, moins à plusieurs (un par place).
const TEAR_PULL := 1.3
## Instant (fraction de TEAR_PULL) où la planche cède : bras jetés en arrière.
const TEAR_RIP := 0.7
const TEAR_PAUSE_MIN := 0.9
const TEAR_PAUSE_MAX := 1.5
## Cadence moyenne (s par planche et par zombie) ; anciennes constantes :
## TEAR_TIME (marcheur) et TEAR_TIME_FAST (coureur) valent désormais la même.
const TEAR_TIME := TEAR_PULL + (TEAR_PAUSE_MIN + TEAR_PAUSE_MAX) * 0.5
const TEAR_TIME_FAST := TEAR_TIME
## Places devant une fenêtre (BO1 : attack_spots, 3 par fenêtre) : au plus
## autant de zombies attendent derrière une fenêtre ; les suivants
## n'apparaissent pas tant qu'une place n'est pas libérée (enjambement, mort).
const WINDOW_QUEUE_MAX := 3
## Durée du passage de la fenêtre (enjambement).
const VAULT_TIME := 1.1


## Points gagnés pour une planche reposée, compte tenu de ce que le joueur a
## déjà gagné en réparations pendant la manche.
static func repair_points(earned_this_round: int, multiplier := 1) -> int:
	var pts := POINTS_PER_PLANK * maxi(multiplier, 1)
	return clampi(ROUND_CAP - earned_this_round, 0, pts)


static func repair_interval(reload_mult := 1.0) -> float:
	return REPAIR_TIME * reload_mult


## Cadence moyenne d'arrachage (s par planche), quelle que soit la vitesse.
static func tear_interval(_speed_class: int) -> float:
	return TEAR_TIME


## Durée de la pause « de folie » après une planche ; `u` dans [0, 1].
static func tear_pause(u: float) -> float:
	return lerpf(TEAR_PAUSE_MIN, TEAR_PAUSE_MAX, clampf(u, 0.0, 1.0))


## Avance de `delta` s le cycle d'arrachage d'un zombie posté à sa place.
## Entrée : `frenzy` (pause en cours), `t` (temps dans la phase), `pause`
## (durée de la pause en cours), `u` (tirage dans [0, 1] pour la prochaine
## pause). Retour : Vector4(frenzy 0/1, t, pause, 1 si la planche cède
## pendant ce pas). Pur, sans allocation (appelé à chaque image).
static func tear_tick(frenzy: bool, t: float, pause: float, delta: float, u: float) -> Vector4:
	var nt := t + delta
	if frenzy:
		if nt >= pause:
			return Vector4(0.0, minf(nt - pause, delta), pause, 0.0)
		return Vector4(1.0, nt, pause, 0.0)
	var rip_at := TEAR_PULL * TEAR_RIP
	var ripped := 1.0 if t < rip_at and nt >= rip_at else 0.0
	if nt >= TEAR_PULL:
		return Vector4(1.0, minf(nt - TEAR_PULL, delta), tear_pause(u), ripped)
	return Vector4(0.0, nt, pause, ripped)


## La fenêtre a-t-elle déjà toutes ses places prises (zombies qui attendent) ?
static func queue_full(waiting: int) -> bool:
	return waiting >= WINDOW_QUEUE_MAX


static func count(mask: int) -> int:
	var n := 0
	for i in PLANKS:
		if mask & (1 << i):
			n += 1
	return n


## Planche arrachée : la dernière posée (indice le plus haut présent), -1 si aucune.
static func plank_to_tear(mask: int) -> int:
	for i in range(PLANKS - 1, -1, -1):
		if mask & (1 << i):
			return i
	return -1


## Planche reposée : la première manquante, -1 si la fenêtre est complète.
static func plank_to_repair(mask: int) -> int:
	for i in PLANKS:
		if not (mask & (1 << i)):
			return i
	return -1
