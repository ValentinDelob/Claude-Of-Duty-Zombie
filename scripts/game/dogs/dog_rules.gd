class_name DogRules
extends RefCounted
## Règles des manches de chiens de l'enfer (fonctions pures, testées
## unitairement). Reprise de Black Ops 1 (_zombiemode_dogs.gsc).

## Rythme des manches de chiens : vagues spéciales du schéma de la carte
## (WaveRules, GAME_CONCEPT.md §4.4) ; le tirage de BO1 (5 à 7, puis +4 ou
## +5) a disparu.
## Chiens par joueur : 6 pour les deux premières manches de chiens, 8 ensuite.
const PER_PLAYER_EARLY := 6
const PER_PLAYER_LATE := 8
## BO1 n'a pas de plafond (4 joueurs au plus : 32 chiens) ; le jeu accepte
## jusqu'à 8 joueurs, on garde donc le maximum de BO1.
const MAX_TOTAL := 32
## Chiens vivants en même temps : 2 par joueur valide.
const ALIVE_PER_PLAYER := 2
## PV selon le numéro de la manche de chiens (dog_health_increase).
const HEALTH := [400, 900, 1300, 1600]
## Annonce : wait(1) + voix + wait(6) avant le premier chien.
const START_DELAY := 7.0
## Boule de foudre : le chien apparaît 1,5 s après l'arrivée de l'éclair.
const SPAWN_TIME := 1.5
## Distance au joueur visé (400 à 1000 unités de BO1 ≈ 10 à 25 m).
const SPAWN_MIN_DIST := 10.0
const SPAWN_MAX_DIST := 25.0
## Déplacement et morsure.
const RUN_SPEED := 6.3
const BITE_DAMAGE := 50
## Explosion de flammes à la mort : petite brûlure autour du chien.
const EXPLODE_RADIUS := 1.8
const EXPLODE_DAMAGE := 15
## Délai après le dernier chien avant le retour du brouillard normal (wait 2).
const FOG_CLEAR_DELAY := 2.0


## Nombre total de chiens. `dog_round_index` : 1 pour la première manche de chiens.
static func dog_count(players: int, dog_round_index: int) -> int:
	var per := PER_PLAYER_EARLY if dog_round_index < 3 else PER_PLAYER_LATE
	return mini(maxi(players, 1) * per, MAX_TOTAL)


static func max_alive(valid_players: int) -> int:
	return maxi(valid_players, 1) * ALIVE_PER_PLAYER


static func dog_health(dog_round_index: int) -> int:
	return HEALTH[clampi(dog_round_index - 1, 0, HEALTH.size() - 1)]


## Attente après l'apparition du chien n° `count` (waiting_for_next_dog_spawn) :
## 3 s, 2,5 s, 2 s puis 1,5 s selon la manche de chiens, moins count / max.
static func spawn_wait(dog_round_index: int, count: int, total: int) -> float:
	var base := 1.5
	match dog_round_index:
		1:
			base = 3.0
		2:
			base = 2.5
		3:
			base = 2.0
	return maxf(base - float(count) / maxf(total, 1.0), 0.1)


## Choix du joueur visé : celui que le moins de chiens chassent déjà
## (get_favorite_enemy). `hunted` : nombre de chiens par candidat.
static func favorite_index(hunted: Array) -> int:
	var best := -1
	var best_n := 1 << 30
	for i in hunted.size():
		if int(hunted[i]) < best_n:
			best_n = int(hunted[i])
			best = i
	return best
