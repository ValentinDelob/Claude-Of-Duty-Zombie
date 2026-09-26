extends AutotestScenario
## [MP] Client : reçoit le TONNERRE-7, tire sur les 4 zombies de l'hôte ; les
## voit mourir et s'envoler (RPC fiable de mort projetée avec la vitesse) ;
## reçoit ses points.

const PORT := 17891

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var start := MapData.cell_to_world(Vector2i(4, 7), 0.05)
	p.teleport_to(start, -PI * 0.5)
	p.pitch = 0.0
	var ok: bool = await until(func(): return p.weapons.current().get("id", "") == "thunder" and game.zombies.alive.size() >= 4, 40.0, "arme et zombies reçus")
	if not ok:
		return
	await seconds(Zombie.EMERGE_TIME + WeaponController.SWITCH_TIME + 0.5)
	var zs: Array = game.zombies.alive.duplicate()
	var start_pos := []
	for z: Zombie in zs:
		start_pos.append(z.global_position)
	var points0 := pd.points
	p.yaw = -PI * 0.5
	p.pitch = 0.0
	p.input.fire = true
	await seconds(0.1)
	p.input.fire = false
	ok = await until(func():
		for z: Zombie in zs:
			if is_instance_valid(z) and z.is_alive():
				return false
		return true, 5.0, "morts reçues")
	await seconds(0.15)
	await at.screenshot("flight")
	var flung := 0
	for z: Zombie in zs:
		if is_instance_valid(z) and z.get_node_or_null("Fling") is ZombieFling:
			flung += 1
	at.check(ok and flung == 4, "client : %d/4 zombies projetés" % flung)
	await seconds(1.0)
	var moved := 0
	for i in zs.size():
		var z: Zombie = zs[i]
		if is_instance_valid(z) and z.global_position.x - start_pos[i].x > 1.5:
			moved += 1
	at.check(moved == 4, "client : %d/4 corps envolés vers l'arrière" % moved)
	await at.screenshot("landed")
	ok = await until(func(): return pd.points - points0 == 4 * PointsRules.KILL, 3.0, "points répliqués")
	at.check(ok, "points du client répliqués (+%d)" % (pd.points - points0))
	await seconds(2.0)
