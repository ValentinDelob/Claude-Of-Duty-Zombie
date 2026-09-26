extends AutotestScenario
## [MP] Client : observe l'hôte (position interpolée, tirs, accroupi, arme,
## nom) et se déplace lui-même.

const PORT := 17812


func run() -> void:
	timeout_sec = 100
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var host: Player = game.players.get(1)
	at.check(host != null and host.visual is PlayerModel and host.visual.visible, "l'hôte est affiché (soldat low-poly)")
	at.check(host.name_tag.text == "Hote", "étiquette de nom : %s" % host.name_tag.text)
	var shots := [0]
	game.combat.remote_shot.connect(func(pid): if pid == 1: shots[0] += 1)
	# Traçante de l'hôte : part de la bouche de l'arme de son soldat (vérifiée
	# à la fin de l'image, une fois l'effet créé) ; capture pendant le vol.
	var tracer_err := [-1.0]
	var check_tracer := func():
		var fx: Fx = game.fx_root
		var i := (fx._tracer_i - 1 + Fx.MAX_TRACERS) % Fx.MAX_TRACERS
		var wm: Node3D = host.visual.weapon_model
		if wm == null or not fx._tracers[i].visible:
			return
		var muzzle := wm.to_global(WeaponModels.anchor(WeaponDB.stats(host.visual.weapon_key.split("_")[0]).model, "muzzle"))
		var e := fx._tr_from[i].distance_to(muzzle)
		if tracer_err[0] < 0.0:
			at.screenshot("host_tracer")
		tracer_err[0] = e if tracer_err[0] < 0.0 else minf(tracer_err[0], e)
	game.combat.remote_shot.connect(func(pid): if pid == 1: check_tracer.call_deferred())
	var saw_crouch := [false]
	p.teleport_to(MapData.cell_to_world(Vector2i(4, 9), 0.05))
	var t := 0.0
	# Fenêtre d'observation : jusqu'à ce que tout soit vu (au plus 25 s, la
	# séquence de l'hôte peut être décalée quand la machine est chargée).
	while t < 25.0 and not (t > 7.2 and host.global_position.x > 7.0 and shots[0] >= 5 and saw_crouch[0] and host.visual.weapon_key == "m14_false"):
		AutotestHelpers.aim_at(p, host.global_position + Vector3.UP * 1.2)
		if host.crouching:
			saw_crouch[0] = true
		await seconds(0.1)
		t += 0.1
		if t > 7.0 and t < 7.2:
			await at.screenshot("host_view")
	at.check(host.global_position.x > 7.0, "déplacement de l'hôte reçu (%s)" % host.global_position)
	at.check(shots[0] >= 4, "tirs de l'hôte reçus : %d/5" % shots[0])
	at.check(tracer_err[0] >= 0.0 and tracer_err[0] < 0.05, "traçante de l'hôte partie de la bouche de son arme (%.3f m)" % tracer_err[0])
	at.check(saw_crouch[0], "accroupi de l'hôte visible")
	at.check(host.visual.weapon_key == "m14_false", "arme de l'hôte mise à jour : %s" % host.visual.weapon_key)
	# Le client part vers (20, 12).
	p.teleport_to(MapData.cell_to_world(Vector2i(20, 12), 0.05))
	await seconds(6.0)
