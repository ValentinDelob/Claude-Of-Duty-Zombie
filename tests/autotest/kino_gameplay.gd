extends AutotestScenario
## @carte kino : lancé seulement quand la carte Kino change (fichiers de la carte).
## KINO : jeu propre à Kino der Toten. Départ sur le disque du poste
## central face à la scène ; téléporteur de BO1 (gratuit, relier le pad puis le
## poste central, zombies foudroyés autour du pad, 30 s en salle de
## projection, retour sur le disque, 90 s de recharge avant de relier à
## nouveau) ; Pack-a-Punch en salle de projection ; pièges à deux leviers
## (40 s / 60 s) ; tableaux à la craie de la boîte.

var game: Game
var p: Player


func run() -> void:
	timeout_sec = 150
	p = await AutotestHelpers.start_solo_game(self, "kino")
	if p == null:
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	for zid in game.zombies.zombies.keys():
		game.zombies.despawn(zid)
	var l := game.layout as MeshMapLayout
	var tp := game.teleporter
	var mf := tp.mainframe
	# Départ : sur le disque, face à la scène (nord = -z).
	at.check(mf != null and mf.floor_pad, "poste central : disque au sol du hall")
	at.check(p.global_position.distance_to(mf.global_position) < 1.8 and p.global_position.y > mf.global_position.y + 0.2, "joueur apparu sur le disque (%s)" % p.global_position)
	at.check(absf(wrapf(p.yaw, -PI, PI)) < 0.2, "face à la scène (lacet %.2f)" % p.yaw)
	await seconds(1.6)  # fondu de l'écran de chargement
	p.pitch = -0.35
	await seconds(1.0)  # rendu posé avant la capture
	await at.screenshot("depart_disque")
	p.pitch = 0.0

	# Pack-a-Punch dans la salle de projection.
	var pap: PackAPunch = game.interact.get_obj("pap")
	at.check(pap != null and l.zone_at(pap.global_position) == "p", "Pack-a-Punch en salle de projection")

	# Pièges : 5, chacun avec son second levier, durées de BO1.
	var traps := 0
	for id in ["trap", "trap_2", "trap_3", "trap_4", "trap_5"]:
		var t: ElectricTrap = game.interact.get_obj(id)
		var lv: TrapLever = game.interact.get_obj(id + "_b")
		if t and lv and is_equal_approx(t.active_time, 40.0) and is_equal_approx(t.cooldown_time, 60.0):
			traps += 1
	at.check(traps == 5, "5 pièges à deux leviers, 40 s / 60 s (%d)" % traps)

	# Tableaux de la boîte : éteints sans courant.
	var boards := game.world.find_children("BoxBoard_*", "BoxBoard", true, false)
	at.check(boards.size() == 5, "5 tableaux à la craie (%d)" % boards.size())

	# Courant.
	(game.interact.get_obj("power") as PowerSwitch).srv_use(1)
	await until(func(): return game.power_on, 3.0, "courant")
	var board: BoxBoard = boards[0]
	var lit: StandardMaterial3D = board._bulbs[game.interact.get_obj("box").location]
	await until(func(): return lit.emission.g > 0.8 and lit.emission_energy_multiplier > 2.0, 2.0, "ampoule du tableau allumée")
	at.check(lit.emission.g > 0.8 and lit.emission_energy_multiplier > 2.0, "tableau : ampoule verte à l'emplacement de la boîte")
	var bm: MapMarker = l.box_boards()[0]
	p.teleport_to(bm.pos - bm.wall * 1.4 + Vector3.UP * 0.05, 0.0)
	H_look(board.global_position)
	await seconds(0.8)  # rendu posé avant la capture
	await at.screenshot("tableau_boite")

	# Second levier : il déclenche le piège.
	game.session.local_data().points = 20000
	var lv1: TrapLever = game.interact.get_obj("trap_b")
	lv1.srv_use(1)
	var t1: ElectricTrap = game.interact.get_obj("trap")
	at.check(t1.state == ElectricTrap.State.ACTIVE, "second levier : piège du couloir activé")

	# Téléporteur : gratuit, pad puis poste central.
	var pts := game.session.local_data().points
	p.teleport_to(tp.global_position + Vector3.UP * 0.1)
	await seconds(0.3)  # posé sur le pad après la téléportation
	tp.srv_use(1)
	at.check(tp.link == Teleporter.Link.PRIMED, "pad activé : à relier au poste central")
	mf.srv_use(1)
	at.check(tp.link == Teleporter.Link.LINKED, "poste central relié")
	# Un zombie près du pad est foudroyé au départ.
	var zid := game.zombies.spawn(tp.global_position + Vector3(3.0, 0, 0), 0, 150)
	var z := game.zombies.get_zombie(zid)
	z.speed_mult = 0.0
	await AutotestHelpers.emerged(self, [z])
	# Replacé sur le pad juste avant le départ (rien ne doit l'en avoir poussé).
	p.teleport_to(tp.global_position + Vector3.UP * 0.1)
	await seconds(0.1)
	tp.srv_use(1)
	at.check(game.session.local_data().points == pts, "voyage gratuit (joueur à %.2f m du pad, écart %.2f m)" % [Vector2(p.global_position.x - tp.global_position.x, p.global_position.z - tp.global_position.z).length(), p.global_position.y - tp.global_position.y])
	await until(func(): return l.zone_at(p.global_position) == "p", 4.0, "arrivée en salle de projection")
	at.check(not z.is_alive(), "zombie proche du pad foudroyé au départ")
	at.check(tp.state == Teleporter.State.ACTIVE and tp.seconds_left() > 25, "30 s en salle de projection (%d s)" % tp.seconds_left())
	await seconds(1.5)  # rendu posé avant la capture
	await at.screenshot("salle_projection")
	# Pack-a-Punch de la salle de projection : on y dépose son arme (5000).
	var before := game.session.local_data().points
	pap.srv_use(1)
	at.check(pap.state == PackAPunch.State.WORKING and before - game.session.local_data().points == PackAPunch.COST,
			"Pack-a-Punch utilisable en salle de projection (%d points)" % (before - game.session.local_data().points))
	# Retour (on abrège l'attente).
	tp._timer = 0.2
	await until(func(): return l.zone_at(p.global_position) == "a", 4.0, "retour dans le hall")
	at.check(p.global_position.distance_to(mf.global_position) < 2.5, "retour sur le disque du poste central")
	at.check(tp.state == Teleporter.State.COOLDOWN and tp.link == Teleporter.Link.UNLINKED, "recharge puis nouvelle liaison nécessaire")
	at.check(tp.seconds_left() > 80, "recharge de 90 s (%d s)" % tp.seconds_left())


func H_look(point: Vector3) -> void:
	AutotestHelpers.aim_at(p, point)
