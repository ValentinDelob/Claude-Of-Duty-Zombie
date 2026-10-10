class_name PointsRules
extends RefCounted
## Barème de la ferraille (fonctions pures, testées unitairement).
##
## Les « points » du code sont la FERRAILLE du joueur (GAME_CONCEPT §4.8) : le
## nom interne `points` est gardé partout (PlayerData.points, Session,
## PointsRules…) pour ne pas tout renommer ; seul ce que le joueur voit dit
## « Ferraille » / « Scrap ».
## * gagnée seulement par le joueur qui porte le coup (rien pour les
##   assistances) ;
## * TOUCHE (coup qui ne tue pas) : HIT pour une balle d'arme à feu ou un coup
##   de couteau ; rien pour une explosion (grenade, arme à zone : un seul tir
##   paierait toute une horde), une brûlure, un piège ou un effet spécial
##   (téléporteur). Au plus HIT_CAP touches payées par zombie, tous joueurs
##   confondus (Zombie.paid_hits) : un zombie aux PV élevés (boss) ne rapporte
##   pas une fortune. Un tir de fusil à pompe compte pour UNE touche par
##   zombie (plombs cumulés par Combat) ;
## * ÉLIMINATION : montant FIXE (KILL), quel que soit le coup (balle, tête,
##   couteau, explosion) et quelle que soit la manche ; le coup qui tue ne
##   rapporte pas la touche en plus ;
## * un zombie mort ne prend plus de coups (Combat.damage_zombie) : rien ; un
##   zombie qui sort du sol est déjà touchable, il rapporte comme les autres ;
## * chaque joueur commence la partie à 0 (PlayerData.STARTING_POINTS).

## Ferraille d'une élimination : l'ancien montant d'un kill normal (BO1).
const KILL := 50
## Ferraille d'une touche (balle ou couteau) : l'ancien montant d'une touche (BO1).
const HIT := 10
## Touches payées au plus par zombie ; au-delà, seule l'élimination rapporte.
const HIT_CAP := 10
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


## Coup de sorte `kind` payé comme une touche (s'il ne tue pas) ?
static func pays_hit(kind: int) -> bool:
	return kind == Combat.HitKind.BULLET or kind == Combat.HitKind.MELEE


## Ferraille gagnée pour un coup porté à un zombie : KILL s'il le tue (sauf
## piège) ; sinon HIT pour une balle ou un coup de couteau tant que le zombie
## a payé moins de HIT_CAP touches (`paid_hits`), rien pour le reste.
## `_headshot` est gardé pour la signature de Combat (pas de bonus de tête).
static func for_damage(killed: bool, _headshot: bool, kind: int, paid_hits := 0) -> int:
	if killed:
		return TRAP_KILL if kind == Combat.HitKind.TRAP else KILL
	if pays_hit(kind) and paid_hits < HIT_CAP:
		return HIT
	return 0
