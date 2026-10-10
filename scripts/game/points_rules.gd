class_name PointsRules
extends RefCounted
## Barème de la ferraille (fonctions pures, testées unitairement).
##
## Les « points » du code sont la FERRAILLE du joueur (GAME_CONCEPT §4.8) : le
## nom interne `points` est gardé partout (PlayerData.points, Session,
## PointsRules…) pour ne pas tout renommer ; seul ce que le joueur voit dit
## « Ferraille » / « Scrap ».
## * gagnée seulement par le joueur qui TUE le zombie : rien pour les touches ;
## * montant FIXE par élimination (KILL), quel que soit le coup (balle, tête,
##   couteau, explosion) et quelle que soit la manche ;
## * chaque joueur commence la partie à 0 (PlayerData.STARTING_POINTS).

## Ferraille d'une élimination : l'ancien montant d'un kill normal (BO1).
const KILL := 50
## Tuer avec un piège ne rapporte rien (le piège a déjà été payé).
const TRAP_KILL := 0
## Bonus de fin de manche par joueur vivant (optionnel).
const ROUND_SURVIVAL := 0


## Pénalités de BO1 (_zombiemode_score, player_reduce_points) : à terre, le
## joueur perd 5 % de sa ferraille (arrondi à la dizaine supérieure) ; s'il
## succombe, chacun des autres perd 10 %. Ce qui est perdu n'est plus rendu
## au sauveteur (rien pour les réanimations, §4.8).
const PENALTY_DOWNED := 0.05
const PENALTY_NO_REVIVE := 0.10


## Arrondi à la dizaine supérieure (round_up_to_ten de BO1).
static func round_up_to_ten(n: int) -> int:
	var r := n - n % 10
	return r + 10 if r < n else r


## Ferraille perdue en tombant à terre avec `points` de ferraille.
static func downed_loss(points: int) -> int:
	return mini(round_up_to_ten(int(points * PENALTY_DOWNED)), maxi(points, 0))


## Ferraille perdue par un coéquipier quand un joueur succombe.
static func no_revive_loss(points: int) -> int:
	return mini(round_up_to_ten(int(points * PENALTY_NO_REVIVE)), maxi(points, 0))


## Ferraille gagnée pour un coup porté à un zombie : KILL s'il le tue (sauf
## piège), rien sinon. `_headshot` est gardé pour la signature de Combat.
static func for_damage(killed: bool, _headshot: bool, kind: int) -> int:
	if not killed:
		return 0
	if kind == Combat.HitKind.TRAP:
		return TRAP_KILL
	return KILL
