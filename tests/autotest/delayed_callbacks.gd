extends AutotestScenario
## Rappels différés (projectile en vol, réarmement, sons de rechargement,
## fente au couteau) encore en attente quand la partie se termine : aucun
## ne doit toucher un joueur, une arme ou une partie déjà libérés.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 60
	# 1. Projectile en vol (lance-grenades) + bruit de réarmement, puis fin de
	#    session avant l'arrivée.
	var p := await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var pd := game.session.local_data()
	pd.slot = WeaponDB.give(pd, "china_lake")
	game.session.sync_inventory(1)
	await until(func(): return p.weapons.current().get("id", "") == "china_lake" and not p.weapons.is_reloading(), 5.0, "lance-grenades en main")
	await seconds(0.8)
	var z := await H.dummy_zombie(self, p.global_position - p.global_transform.basis.z * 25.0, 5000)
	H.aim_at(p, z.hit_body.global_position)
	await H.shoot(self, p, 0.0)
	at.check(pd.current_weapon().mag < WeaponDB.stats("china_lake", false).mag, "tir parti (projectile en vol)")
	Net.session_ended.emit("test : fin pendant un projectile en vol")
	await until(func(): return Game.instance == null and tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu (1)")
	await seconds(1.5)
	at.check(Game.instance == null, "projectile : aucune partie restante")

	# 2. Rechargement (sons programmés) et fente au couteau en cours, puis fin
	#    de session.
	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	pd = game.session.local_data()
	pd.current_weapon().mag = 1
	game.session.sync_inventory(1)
	await seconds(0.5)
	p.input.reload = true
	await frames(2)
	p.input.reload = false
	at.check(p.weapons.is_reloading(), "rechargement en cours")
	Net.session_ended.emit("test : fin pendant un rechargement")
	await until(func(): return Game.instance == null and tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu (2)")
	await seconds(3.0)

	p = await H.start_solo_game(self)
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	# Projectile d'un joueur parti entre le tir et l'impact : les dégâts
	# s'appliquent, sans points ni confirmation envoyée à un pair inconnu.
	var gone := 4242
	var zg := await H.dummy_zombie(self, p.global_position - p.global_transform.basis.x * 6.0, 100)
	var pts0 := game.session.local_data().points
	game.combat.damage_zombie(zg.id, 500, gone, false, Vector3.FORWARD, Combat.HitKind.SPLASH)
	at.check(not zg.is_alive() and game.session.local_data().points == pts0, "coup d'un joueur parti : zombie tué, aucune ferraille")
	await H.clear_zombies(self)
	z = await H.dummy_zombie(self, p.global_position - p.global_transform.basis.z * 2.6, 5000)
	H.aim_at(p, z.hit_body.global_position)
	await frames(2)
	p.input.melee = true
	await frames(2)
	p.input.melee = false
	at.check(p.weapons.lunging, "fente au couteau en cours")
	Net.session_ended.emit("test : fin pendant une fente")
	await until(func(): return Game.instance == null and tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu (3)")
	await seconds(1.5)
	at.check(Game.instance == null, "fente : aucune partie restante")
