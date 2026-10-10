class_name MatchXp
extends RefCounted
## XP gagnée pendant une partie (GAME_CONCEPT §4.15), ajoutée au profil à la
## fin de la partie, que l'équipe s'évacue ou non : l'XP est toujours gardée
## (§4.6).
##
## Source minimale et PROVISOIRE : éliminations et manches survécues. Valeurs
## choisies pour viser le niveau 10 vers 3 h de jeu (§4.15 : ≈ 19 500 XP) :
## une partie de 20 min (≈ 150 éliminations, manche 12) rapporte
## 150 × 10 + 11 × 50 = 2 050 XP, soit le niveau 10 en ≈ 9 à 10 parties.
## À ajuster après mesure ; les autres sources prévues (mini-boss, boss,
## contrats, bonus d'évacuation) viendront avec leurs lots.

## XP par zombie tué par le joueur.
const XP_PER_KILL := 10
## XP par manche survécue.
const XP_PER_ROUND := 50


## XP d'une partie (règle pure).
static func match_xp(kills: int, rounds_survived: int) -> int:
	return maxi(kills, 0) * XP_PER_KILL + maxi(rounds_survived, 0) * XP_PER_ROUND


## Ajoute l'XP de la partie au profil enregistré (chargé, modifié, enregistré).
## À appeler une fois par partie, pour le joueur local, à la fin de la partie :
## aujourd'hui au GAME OVER (Game._cl_game_over, où CareerStats enregistre) ;
## l'évacuation l'appellera aussi, avec ses propres manches survécues.
## `rounds_survived` : au GAME OVER, la manche en cours ne compte pas
## (manche − 1) ; après une évacuation, la manche vaincue compte.
## Rend {xp, level_before, level_after}.
static func apply_match_xp(kills: int, rounds_survived: int, profile_path := "") -> Dictionary:
	var gained := match_xp(kills, rounds_survived)
	var pr := ProfileStore.load_profile(profile_path)
	var before := pr.level()
	pr.add_xp(gained)
	if gained > 0:
		ProfileStore.save_profile(pr, profile_path)
	return {"xp": gained, "level_before": before, "level_after": pr.level()}
