extends "res://tests/autotest/stairs_types.gd"
## @couvre scripts/game/map/stair_gen.gd scripts/game/map/stair_lane.gd scripts/game/map/mesh_nav.gd scripts/game/zombies/zombie.gd
## Escaliers de chaque type (même carte que stairs_types) : une horde de 10
## coureurs monte puis descend chaque type. Chacun suit le couloir d'ancres
## à son propre écart (ils montent de front, sans s'empiler contre un bord) ;
## tous arrivent, aucun ne reste plus de 3 s immobile sur les marches.


func cases() -> Array:
	return [["horde de 10 coureurs", RoundRules.RUN, ZombieManager.KIND_ZOMBIE, false, 10, Zombie.SPEEDS[2]]]
