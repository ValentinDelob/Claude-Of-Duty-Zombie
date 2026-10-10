class_name MatchRules
extends RefCounted
## Règles pures d'une partie (sans nœud, testées par tests/test_match_rules.gd) :
## fin de partie, réapparition des morts au début de chaque manche, point
## d'apparition d'une place de joueur. Game les applique et s'occupe du réseau.

## Carte sans point d'apparition (carte perso incomplète) : repli fixe au lieu
## d'une division par zéro.
const FALLBACK_SPAWN := Vector3(2, 0.1, 2)


## Fin de partie si plus aucun joueur n'est debout (BO1) : un joueur à terre
## qui va se relever seul (LAZARUS en solo, `will_self_revive(peer_id)`) la
## repousse ; à terre sans réanimation possible, ou mort, ne la repousse pas.
## Aucun joueur : fin de partie aussi (le dernier est parti).
static func is_game_over(data: Array, will_self_revive: Callable) -> bool:
	for pd: PlayerData in data:
		if pd.life == PlayerData.Life.ALIVE or will_self_revive.call(pd.peer_id):
			return false
	return true


## Mort définitive (saignement terminé).
static func bleed_out(pd: PlayerData) -> void:
	pd.life = PlayerData.Life.DEAD


## Total des zombies abattus (résumé de fin de partie).
static func total_kills(data: Array) -> int:
	var kills := 0
	for pd: PlayerData in data:
		kills += pd.kills
	return kills


## Un joueur mort revient à la manche suivante (les joueurs à terre, non).
static func should_respawn(pd: PlayerData) -> bool:
	return pd.life == PlayerData.Life.DEAD


## Réapparition en coop (GAME_CONCEPT §4.6) : debout, santé pleine, avec
## toutes ses affaires d'avant la mort : armes et munitions (mises de côté à
## terre, `saved_weapons`), couteau, grenades, ferraille et statistiques. Les
## atouts restent perdus (retirés en tombant à terre, BO1).
static func respawn(pd: PlayerData) -> void:
	pd.life = PlayerData.Life.ALIVE
	pd.health = pd.max_health
	restore_saved_weapons(pd)


## Rend au joueur les armes mises de côté à terre (`saved_weapons`) :
## réanimation et réapparition. L'arme utilisée à terre, si le joueur la
## possédait, revient avec ses munitions ; un M1911 prêté (aucun pistolet
## possédé) est repris. Rien de côté : l'inventaire actuel est gardé (pistolet
## de départ s'il est vide).
static func restore_saved_weapons(pd: PlayerData) -> void:
	if not pd.saved_weapons.is_empty():
		var used: Dictionary = pd.weapons[0] if not pd.weapons.is_empty() else {}
		pd.weapons = pd.saved_weapons.duplicate(true)
		if not used.is_empty():
			for i in pd.weapons.size():
				if pd.weapons[i].id == used.id and pd.weapons[i].pap == used.pap:
					pd.weapons[i] = used
					break
		pd.saved_weapons = []
	if pd.weapons.is_empty():
		pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)]
	pd.slot = clampi(pd.slot, 0, pd.weapons.size() - 1)


## Point d'apparition d'une place de joueur : les places au-delà du nombre de
## points se partagent les points (modulo positif) ; carte sans point
## d'apparition : FALLBACK_SPAWN.
static func spawn_for_slot(spawns: Array[Vector3], slot: int) -> Vector3:
	if spawns.is_empty():
		return FALLBACK_SPAWN
	return spawns[posmod(slot, spawns.size())]
