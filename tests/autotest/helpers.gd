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


## Tir semi-automatique unique (bot) : détente pressée puis relâchée, comme un
## joueur (attentes fixes voulues : elles simulent le doigt).
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
	await emerged(sc, [z])
	return z


## Attend que ces zombies soient sortis de terre, puis la fin de leur
## redressement (0,3 s d'animation : tête et hitboxes à leur place).
static func emerged(sc: AutotestScenario, zs: Array) -> bool:
	var ok: bool = await sc.until(func():
		for z in zs:
			if is_instance_valid(z) and (z as Zombie).state == Zombie.State.EMERGE:
				return false
		return true, Zombie.EMERGE_TIME + 3.0, "zombie(s) sorti(s) de terre")
	await sc.seconds(0.3)
	return ok


## Tue (par le serveur) tous les chiens vivants ; rend leur nombre.
static func kill_dogs() -> int:
	var game := Game.instance
	var n := 0
	for z: Zombie in game.zombies.alive.duplicate():
		if z is Hellhound and z.is_alive():
			game.combat.damage_zombie(z.id, 999999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
			n += 1
	return n


## Vague de chiens forcée à la manche `n` : un chien au moins apparu et tué
## (butin de vague : LootSystem), puis le reste déclaré apparu et tué. Rend
## vrai quand la vague est vaincue et que l'arme de butin est posée.
## L'appelant ferme ensuite la fenêtre d'évacuation (evac.time_left) ou s'évacue.
static func clear_dog_wave(sc: AutotestScenario, n: int) -> bool:
	var game := Game.instance
	var dogs := game.rounds.dogs
	dogs.debug_force_next(n)
	game.rounds.debug_jump_to(n)
	if not await sc.until(func(): return dogs.active and game.rounds.round_n == n, 3.0, "vague de chiens %d" % n):
		return false
	if not await sc.until(func(): return dogs.alive_dogs() > 0, 20.0, "un chien apparu"):
		return false
	while kill_dogs() == 0:
		await sc.frames(1)
	dogs.spawned = dogs.total
	kill_dogs()
	return await sc.until(func(): return not game.loot.drops.is_empty(), 5.0, "arme posée après la vague")
