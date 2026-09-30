extends AutotestScenario
## [MP] Hôte : se déplace, tire, s'accroupit, change d'arme ; vérifie qu'il
## voit bien le client bouger.

const PORT := 17812
## Tirs de plus au plus, tant que le client n'a pas vu 5 tirs : les
## effets de tir passent par un canal NON FIABLE (un paquet peut se perdre).
const EXTRA_SHOTS := 40


func run() -> void:
	timeout_sec = 100
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var p := game.local_player
	p.bot_controlled = true
	# Le client observe (signaux branchés, en place).
	if not await MpHelpers.wait_peer(self, "observe", 20.0):
		return
	# Se place dans l'allée dégagée (rangée 7), puis avance vers l'est.
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	await seconds(0.5)
	p.input.move = Vector2(0.0, 1.0)
	await seconds(1.5)  # touche d'avance tenue
	p.input.move = Vector2.ZERO
	# Tirs : 5, puis d'autres tant que le client n'en a pas vu 5.
	var fired := [0]
	p.weapons.fired.connect(func(): fired[0] += 1)
	var pd := game.session.local_data()
	for i in 5:
		await AutotestHelpers.shoot(self, p, 0.25)
	var extra := 0
	while not MpHelpers.peer_reached("tirs_vus") and extra < EXTRA_SHOTS:
		var w: Dictionary = pd.current_weapon()
		if w.mag <= 1:
			w.mag = WeaponDB.stats(w.id, w.pap).mag
			game.session.sync_inventory(1)
		await AutotestHelpers.shoot(self, p, 0.25)
		extra += 1
	print("[autotest] tirs : %d (dont %d supplémentaires)" % [fired[0], extra])
	# Accroupi jusqu'à ce que le client l'ait vu (au moins 0,5 s).
	p.input.crouch = true
	await seconds(0.5)
	await MpHelpers.wait_peer(self, "accroupi_vu", 10.0)
	p.input.crouch = false
	# Nouvelle arme (serveur) : la carabine.
	WeaponDB.give(pd, "m14")
	game.session.sync_inventory(1)
	# Le client a tout vu, puis se déplace de son côté.
	if not await MpHelpers.wait_peer(self, "hote_vu", 30.0):
		return
	var remote: Player = null
	for pl in game.players.values():
		if not pl.is_local:
			remote = pl
	var target := MapData.cell_to_world(Vector2i(20, 12))
	var ok: bool = await until(func(): return remote.global_position.distance_to(target) < 1.5, 15.0, "position du client")
	at.check(ok, "l'hôte voit le client à sa nouvelle position (%s)" % remote.global_position)
	await MpHelpers.finish(self)
