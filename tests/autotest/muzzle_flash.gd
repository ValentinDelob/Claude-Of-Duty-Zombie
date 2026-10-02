extends AutotestScenario
## Flamme de bouche de la vue FPS : matériau qui respecte la profondeur de
## l'arme (cachée là où elle passe derrière), angle tiré au hasard à chaque
## tir, en visée comme à la hanche.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await H.clear_zombies(self)
	var pd := game.session.local_data()
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 3), 0.05), -PI * 0.5)
	p.pitch = 0.0
	var spins := []
	for id in ["m14", "olympia", "m1911"]:
		if not WeaponDB.WEAPONS.has(id):
			continue
		pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON), WeaponDB.new_instance(id)]
		pd.slot = 1
		game.session.sync_inventory(1)
		await until(func(): return p.weapons.current().get("id", "") == id, 2.0, "arme %s en main" % id)
		await seconds(WeaponController.SWITCH_TIME + 0.25)
		var v := p.weapons.view
		var core := v._flash_mesh.material_override as ShaderMaterial
		at.check(core != null and float(core.get_shader_parameter("viewmodel")) > 0.5, "%s : flamme FPS avec profondeur de l'arme" % id)
		for aim in [true, false]:
			p.input.aim = aim
			await seconds(0.6)
			p.input.fire = true
			await until(func(): return v._flash_rig.visible, 1.0, "%s : flamme visible" % id)
			p.input.fire = false
			spins.append(float(core.get_shader_parameter("spin")))
			await seconds(0.5)
		p.input.aim = false
	var distinct := {}
	for s in spins:
		distinct[snappedf(s, 0.01)] = true
	at.check(distinct.size() >= 2, "angle de la flamme différent d'un tir à l'autre (%d angles sur %d tirs)" % [distinct.size(), spins.size()])
