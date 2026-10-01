extends "res://tests/autotest/stairs_types.gd"
## @carte kino
## @couvre scripts/game/map/stair_gen.gd scripts/game/map/stair_lane.gd scripts/game/map/mesh_nav.gd scripts/game/zombies/zombie.gd
## KINO : chaque escalier (hall, balcon, ruelle, arrière-salle, cage des
## coulisses, Foyer et sa mezzanine, escalier du Foyer, marches de la scène)
## a ses ancres sur le navmesh ; un marcheur, un sprinteur et un chien le
## montent puis le descendent par elles, portes ouvertes, sans rester plus
## de 3 s immobile sur les marches. Les marches de la scène, masquées en face
## par la première rangée de fauteuils, prennent leur ancre du pied dans
## l'allée libre à côté (le décor n'est pas déplacé).


func cases() -> Array:
	return [
		["marcheur", RoundRules.WALK, ZombieManager.KIND_ZOMBIE, false, 1, Zombie.SPEEDS[0]],
		["sprinteur", RoundRules.SPRINT, ZombieManager.KIND_ZOMBIE, false, 1, Zombie.SPEEDS[3]],
		["chien", 3, ZombieManager.KIND_DOG, false, 1, DogRules.RUN_SPEED],
	]


func start() -> bool:
	p = await H.start_solo_game(self, "kino")
	if p == null:
		return false
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	for id in game.doors:
		game.doors[id].srv_open()
	await H.clear_zombies(self)
	await seconds(0.5)  # collisions des portes ouvertes coupées
	nav = game.nav as MeshNav
	var stairs: Array = (game.layout as MeshMapLayout).data.stairs
	at.check(nav != null and nav.lanes.size() == stairs.size(), "un couloir d'ancres par escalier de KINO (%d / %d)" % [nav.lanes.size() if nav else 0, stairs.size()])
	return nav != null and await until(func(): return nav.ensure_anchors(), 5.0, "ancres posées")


func targets() -> Array:
	var out := []
	for l in nav.lanes:
		out.append(["escalier %d (%s)" % [l.index, l.name], l])
	return out
