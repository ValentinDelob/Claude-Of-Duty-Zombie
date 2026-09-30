extends AutotestScenario
## Système de dégâts : tirs corps / tête validés par le serveur, couteau,
## touches truquées refusées, attaques des zombies, régénération, mort, GAME OVER.

var game: Game
var p: Player
var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	await H.clear_zombies(self)
	var origin := MapData.cell_to_world(Vector2i(4, 7), 0.05)
	p.teleport_to(origin, -PI * 0.5)
	await seconds(0.3)

	# 1. Tirs au corps (M1911) : 25 dégâts x 6 = 150.
	var z := await H.dummy_zombie(self, origin + Vector3(6, 0, 0))
	for i in 5:
		H.aim_at(p, z.global_position + Vector3.UP * 0.9)
		await H.shoot(self, p)
	at.check(z.is_alive() and z.health == 25, "5 balles au corps : 150 -> %d PV (serveur)" % z.health)
	H.aim_at(p, z.global_position + Vector3.UP * 0.9)
	await H.shoot(self, p)
	at.check(not z.is_alive(), "6e balle : zombie mort")
	await seconds(0.7)  # capture : corps en train de tomber
	await at.screenshot("body_kill")
	var dead_id := z.id
	await until(func(): return game.zombies.get_zombie(dead_id) == null, Zombie.DISSOLVE_DELAY + Zombie.DISSOLVE_TIME + 2.0, "corps dissous et retiré")
	at.check(not is_instance_valid(z) or game.zombies.get_zombie(z.id) == null, "corps retiré après dissolution")

	# 2. Tirs à la tête : 25 x 3 = 75 dégâts x 2.
	p.input.reload = true
	await until(func(): return p.weapons.current().mag >= p.weapons.current_stats().mag, 4.0, "rechargement terminé")
	z = await H.dummy_zombie(self, origin + Vector3(5, 0, 0.5))
	H.aim_at(p, z.head_position())
	await H.shoot(self, p)
	at.check(z.is_alive() and z.health == 75, "tir à la tête : 150 -> %d PV" % z.health)
	H.aim_at(p, z.head_position())
	await H.shoot(self, p)
	at.check(not z.is_alive(), "2e tir à la tête : mort")
	at.check(z._headless, "tête arrachée")
	await seconds(0.25)
	await at.screenshot("headshot")

	# 3. Couteau : 150 dégâts.
	z = await H.dummy_zombie(self, origin + Vector3(1.3, 0, 0))
	H.aim_at(p, z.global_position + Vector3.UP)
	p.input.melee = true
	await until(func(): return not z.is_alive(), 2.0, "coup de couteau porté")
	at.check(not z.is_alive(), "coup de couteau mortel")

	# 4. Touche truquée : zombie derrière le joueur, revendiqué touché.
	z = await H.dummy_zombie(self, origin + Vector3(-2.5, 0, 0))
	var fake := [[z.id, 1, 5.0, z.head_position()]]
	await seconds(0.5)
	var hp0 := z.health
	game.combat.srv_fire.rpc_id(1, 0, p.camera.global_position, Vector3(1, 0, 0), PackedVector3Array(), fake)
	await seconds(0.2)  # délai laissé au serveur pour (ne pas) appliquer la touche
	at.check(z.health == hp0, "touche impossible refusée (PV %d)" % z.health)
	await H.clear_zombies(self)

	# 5. Un zombie attaque le joueur : 100 -> 50, puis régénération.
	var pd := game.session.local_data()
	z = await H.dummy_zombie(self, origin + Vector3(1.0, 0, 0))
	await until(func(): return pd.health < 100, 4.0, "le zombie frappe")
	at.check(pd.health == 50, "coup de zombie : 50 PV restants (%d)" % pd.health)
	await seconds(0.1)
	await at.screenshot("hurt")
	await H.clear_zombies(self)
	await until(func(): return pd.health == 100, 6.0, "régénération")
	at.check(pd.health == 100, "santé régénérée")

	# 6. Deux coups sans répit : à terre, et en solo sans LAZARUS : GAME OVER.
	z = await H.dummy_zombie(self, origin + Vector3(1.0, 0, 0))
	await until(func(): return pd.life == PlayerData.Life.DOWNED, 6.0, "joueur à terre")
	at.check(pd.life == PlayerData.Life.DOWNED, "le joueur tombe à terre après deux coups")
	await until(func(): return GameState.state == GameState.State.GAME_OVER, 2.0, "état GAME_OVER")
	await seconds(1.3)
	await at.screenshot("game_over")
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 12.0, "retour au menu")
	at.check(GameState.state == GameState.State.MAIN_MENU, "retour au menu principal")
