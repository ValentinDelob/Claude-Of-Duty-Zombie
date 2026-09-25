class_name AutotestHelpers
extends RefCounted
## Fonctions partagées par les scénarios.


## Lance une partie solo et attend que le joueur local soit en jeu.
static func start_solo_game(sc: AutotestScenario, map_id := "test_arena") -> Player:
	await sc.until(func(): return sc.tree().current_scene != null and sc.tree().current_scene.name == "MainMenu", 5.0, "menu")
	Router.start_solo(map_id)
	var ok: bool = await sc.until(func(): return Game.instance != null and Game.instance.local_player != null, 10.0, "joueur local en jeu")
	if not ok:
		return null
	var p := Game.instance.local_player
	p.bot_controlled = true
	await sc.frames(5)
	return p


## Oriente le joueur (bot) vers un point du monde.
static func aim_at(p: Player, point: Vector3) -> void:
	var dir := point - p.camera.global_position
	p.yaw = atan2(-dir.x, -dir.z)
	p.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
	p.rotation.y = p.yaw
	p.head.rotation.x = p.pitch


## Tir semi-automatique unique (bot).
static func shoot(sc: AutotestScenario, p: Player, interval := 0.2) -> void:
	p.input.fire = true
	await sc.seconds(0.04)
	p.input.fire = false
	await sc.seconds(interval)


static func clear_zombies(sc: AutotestScenario) -> void:
	var zm := Game.instance.zombies
	for zid in zm.zombies.keys():
		zm.despawn(zid)
	await sc.frames(2)


## Fait apparaître un zombie immobile devant le joueur.
static func dummy_zombie(sc: AutotestScenario, pos: Vector3, health := 150) -> Zombie:
	var zm := Game.instance.zombies
	var zid := zm.spawn(pos, 0, health)
	var z := zm.get_zombie(zid)
	z.speed_mult = 0.0
	await sc.seconds(Zombie.EMERGE_TIME + 0.3)
	return z
