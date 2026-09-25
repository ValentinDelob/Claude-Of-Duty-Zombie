extends AutotestScenario
## Boîte mystère : achat, défilement, arme tirée par le serveur (jamais une
## arme déjà possédée), prise par l'acheteur, CLAUDE-RAY (dégâts de zone),
## crâne : remboursement et déménagement.

var H := AutotestHelpers
var game: Game
var p: Player
var box: MysteryBox


func face_box() -> void:
	var n: Vector3 = box.spots[box.location].normal
	p.teleport_to(box.global_position - n * 1.6 + Vector3(0, 0.05, 0))
	H.aim_at(p, box.global_position + Vector3.UP * 0.8)
	await seconds(0.3)


func press() -> void:
	p.input.interact_pressed = true
	await seconds(0.3)


func run() -> void:
	timeout_sec = 150
	p = await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	var pd := game.session.local_data()
	for id in game.doors:
		game.doors[id].srv_open()
	box = game.interact.get_obj("box")
	at.check(box != null and box.location == 1, "boîte au quai au départ (emplacement 1)")
	await face_box()
	at.check(game.hud._prompt.text.contains("950"), "invite : %s" % game.hud._prompt.text)
	await press()
	at.check(box.state == MysteryBox.State.IDLE and pd.points == 500, "refus sans 950 points")

	game.session.add_points(1, 20000)
	await seconds(0.1)
	await press()
	at.check(box.state == MysteryBox.State.ROLLING and pd.points == 20500 - 950, "achat : défilement en cours")
	await seconds(2.0)
	await at.screenshot("rolling")
	await until(func(): return box.state == MysteryBox.State.READY, 4.0, "arme prête")
	at.check(WeaponDB.exists(box.weapon) and box.weapon != "pistol", "arme tirée : %s" % box.weapon)
	await seconds(0.4)
	await at.screenshot("ready")
	var got := box.weapon
	await press()
	at.check(pd.has_weapon(got) >= 0 and box.state == MysteryBox.State.IDLE, "%s pris par l'acheteur" % got)

	# Jamais une arme déjà possédée.
	var dup := 0
	for i in 60:
		box._roll(pd)
		if pd.has_weapon(box.weapon) >= 0:
			dup += 1
	box.weapon = ""
	at.check(dup == 0, "le tirage exclut les armes possédées")

	# CLAUDE-RAY forcé : dégâts de zone.
	box.force_result = "ray"
	await press()
	await until(func(): return box.state == MysteryBox.State.READY, 6.0, "rayon prêt")
	await press()
	at.check(pd.current_weapon().id == "ray", "CLAUDE-RAY en main")
	await seconds(0.8)
	p.yaw += PI
	await seconds(0.2)
	var center := p.global_position + (-p.global_transform.basis.z) * 6.0
	var zs := []
	for k in 3:
		var z := await H.dummy_zombie(self, center + Vector3(k - 1, 0, 0) * 0.8, 500)
		zs.append(z)
	H.aim_at(p, zs[1].global_position + Vector3.UP * 0.9)
	await H.shoot(self, p, 0.4)
	var dead := 0
	for z: Zombie in zs:
		if not z.is_alive():
			dead += 1
	at.check(dead == 3, "tir de CLAUDE-RAY : %d/3 zombies tués par l'explosion" % dead)
	await at.screenshot("ray")
	await H.clear_zombies(self)

	# Crâne : remboursement et déménagement.
	await face_box()
	var before := pd.points
	var old_loc := box.location
	box.force_result = "skull"
	await press()
	await until(func(): return box.state == MysteryBox.State.MOVING, 6.0, "crâne")
	at.check(pd.points == before, "crâne : 950 points remboursés (%d)" % pd.points)
	await seconds(1.0)
	await at.screenshot("skull")
	await until(func(): return box.state == MysteryBox.State.IDLE, MysteryBox.MOVE_TIME + 2.0, "réapparition")
	at.check(box.location != old_loc, "la boîte a déménagé (%d -> %d)" % [old_loc, box.location])
