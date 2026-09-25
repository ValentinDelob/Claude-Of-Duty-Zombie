extends AutotestScenario
## [MP] Hôte : se déplace, tire, s'accroupit, change d'arme ; vérifie qu'il
## voit bien le client bouger.

const PORT := 17812


func run() -> void:
	timeout_sec = 100
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var p := game.local_player
	p.bot_controlled = true
	await seconds(3.0)
	# Se place dans l'allée dégagée (rangée 7), puis avance vers l'est.
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	await seconds(1.0)
	p.input.move = Vector2(0.0, 1.0)
	await seconds(1.5)
	p.input.move = Vector2.ZERO
	# Tirs.
	for i in 5:
		await AutotestHelpers.shoot(self, p, 0.25)
	# Accroupi 2 s.
	p.input.crouch = true
	await seconds(2.0)
	p.input.crouch = false
	# Nouvelle arme (serveur) : la carabine.
	var pd := game.session.local_data()
	WeaponDB.give(pd, "carbine")
	game.session.sync_inventory(1)
	await seconds(3.0)
	# Le client s'est déplacé de son côté.
	var remote: Player = null
	for pl in game.players.values():
		if not pl.is_local:
			remote = pl
	var target := MapData.cell_to_world(Vector2i(20, 12))
	var ok: bool = await until(func(): return remote.global_position.distance_to(target) < 1.5, 15.0, "position du client")
	at.check(ok, "l'hôte voit le client à sa nouvelle position (%s)" % remote.global_position)
	await seconds(3.0)
