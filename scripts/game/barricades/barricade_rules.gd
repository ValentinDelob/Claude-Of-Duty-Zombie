class_name BarricadeRules
extends RefCounted
## Règles des fenêtres barricadées (fonctions pures, testées unitairement).
##
## 6 planches par fenêtre, comme dans Black Ops 1. Reposer une planche ne
## rapporte rien : la ferraille ne vient que des éliminations (GAME_CONCEPT
## §4.8). Portes à zombies (format 8) : KINDS (planches, zombies qui arrachent
## à la fois, places d'attente).

const PLANKS := 6
const FULL_MASK := (1 << PLANKS) - 1
## Secondes de maintien de [F] par planche reposée.
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
## Durée du passage d'une fenêtre ou d'une porte à zombies (enjambement).
const VAULT_TIME := 1.1

# --------------------------------------------------------------------------
# Types d'entrée (format 8 des cartes de l'éditeur ; docs/MAP_OBJECTS.md § 9)
# --------------------------------------------------------------------------
## fenêtre (BO1, l'entrée d'avant), porte à zombies simple, porte double.
const WINDOW := "fenetre"
const DOOR := "porte"
const DOUBLE_DOOR := "porte_double"
## type -> {planks, width (m), tearers (zombies qui arrachent à la fois),
## waiting (places d'attente derrière eux), lanes (passages de front)}.
## Fenêtre : 3 places devant les planches, chacun arrache (BO1 attack_spots).
## Porte simple : un seul zombie arrache à la fois, 3 attendent derrière lui.
## Porte double : un zombie par battant (2 à la fois, cadence doublée),
## 4 attendent ; 5 planches par battant ; deux passages de front.
const KINDS := {
	WINDOW: {"planks": 6, "width": 1.0, "tearers": 3, "waiting": 0, "lanes": 1},
	DOOR: {"planks": 6, "width": 1.0, "tearers": 1, "waiting": 3, "lanes": 1},
	DOUBLE_DOOR: {"planks": 10, "width": 2.0, "tearers": 2, "waiting": 4, "lanes": 2},
}
## Le plus de planches d'une entrée (masque sur 16 bits au plus).
const MAX_PLANKS := 10
## Le zombie passe le bras par le trou (BO1 : il attrape le joueur collé à
## l'entrée) dès que ce nombre de planches de son passage est arraché.
const REACH_MIN_TORN := 2


static func _kind(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS[WINDOW])


static func is_door(kind: String) -> bool:
	return kind == DOOR or kind == DOUBLE_DOOR


static func planks_for(kind: String) -> int:
	return int(_kind(kind).planks)


static func full_mask_for(kind: String) -> int:
	return (1 << planks_for(kind)) - 1


static func width(kind: String) -> float:
	return float(_kind(kind).width)


static func tearers(kind: String) -> int:
	return int(_kind(kind).tearers)


static func lanes(kind: String) -> int:
	return int(_kind(kind).lanes)


## Zombies rattachés au plus à une entrée : ceux qui arrachent et ceux qui
## attendent (fenêtre : WINDOW_QUEUE_MAX ; porte : 1 + 3 ; double : 2 + 4).
static func queue_max(kind: String) -> int:
	return tearers(kind) + int(_kind(kind).waiting)


## Battant (passage) d'une planche : porte double, planches paires à gauche,
## impaires à droite (la réparation, première manquante, alterne).
static func lane_of_plank(i: int, n_lanes: int) -> int:
	return i % maxi(n_lanes, 1)


## Planche arrachée par le zombie du passage `lane` : la dernière posée de son
## battant, sinon la dernière posée (il aide l'autre battant) ; -1 si aucune.
static func plank_to_tear_lane(mask: int, n: int, n_lanes: int, lane: int) -> int:
	for i in range(n - 1, -1, -1):
		if mask & (1 << i) and lane_of_plank(i, n_lanes) == lane:
			return i
	return plank_to_tear(mask, n)


## Planches présentes d'un battant.
static func count_lane(mask: int, n: int, n_lanes: int, lane: int) -> int:
	var c := 0
	for i in n:
		if mask & (1 << i) and lane_of_plank(i, n_lanes) == lane:
			c += 1
	return c


## Le zombie du passage `lane` peut-il passer le bras à travers (au moins
## REACH_MIN_TORN planches arrachées de son battant ; fenêtre : de l'entrée) ?
static func can_reach_through(mask: int, n: int, n_lanes: int, lane: int) -> bool:
	var lane_total := 0
	for i in n:
		if lane_of_plank(i, n_lanes) == lane:
			lane_total += 1
	return lane_total - count_lane(mask, n, n_lanes, lane) >= REACH_MIN_TORN


static func repair_interval() -> float:
	return REPAIR_TIME


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
## `kind` : type d'entrée (porte : 4 zombies, porte double : 6).
static func queue_full(waiting: int, kind := WINDOW) -> bool:
	return waiting >= (WINDOW_QUEUE_MAX if kind == WINDOW else queue_max(kind))


static func count(mask: int) -> int:
	var n := 0
	for i in MAX_PLANKS:
		if mask & (1 << i):
			n += 1
	return n


## Planche arrachée : la dernière posée (indice le plus haut présent), -1 si aucune.
static func plank_to_tear(mask: int, n := PLANKS) -> int:
	for i in range(n - 1, -1, -1):
		if mask & (1 << i):
			return i
	return -1


## Planche reposée : la première manquante, -1 si la fenêtre est complète.
static func plank_to_repair(mask: int, n := PLANKS) -> int:
	for i in n:
		if not (mask & (1 << i)):
			return i
	return -1
