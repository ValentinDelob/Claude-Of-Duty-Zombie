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
	var saw_crouch := [false]
	p.teleport_to(MapData.cell_to_world(Vector2i(4, 9), 0.05))
	var t := 0.0
	while t < 12.0:
		AutotestHelpers.aim_at(p, host.global_position + Vector3.UP * 1.2)
		if host.crouching:
			saw_crouch[0] = true
		await seconds(0.1)
		t += 0.1
		if t > 7.0 and t < 7.2:
			await at.screenshot("host_view")
	at.check(host.global_position.x > 7.0, "déplacement de l'hôte reçu (%s)" % host.global_position)
	at.check(shots[0] >= 4, "tirs de l'hôte reçus : %d/5" % shots[0])
	at.check(saw_crouch[0], "accroupi de l'hôte visible")
	at.check(host.visual.weapon_key == "m14_false", "arme de l'hôte mise à jour : %s" % host.visual.weapon_key)
	# Le client part vers (20, 12).
	p.teleport_to(MapData.cell_to_world(Vector2i(20, 12), 0.05))
	await seconds(6.0)
