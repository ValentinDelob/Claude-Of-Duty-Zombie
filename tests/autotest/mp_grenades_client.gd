extends AutotestScenario
## [MP] Client : lance une grenade (affichée aussitôt, prédiction), puis la
## rattache à l'objet du serveur ; reçoit l'explosion et ses points. Puis
## lance le SINGE-TAMBOUR reçu du serveur et voit sa musique démarrer.

const PORT := 17881

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var sys := game.throwables
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	var booms := []
	sys.exploded.connect(func(kind, pos, pid): booms.append([kind, pos, pid]))
	p.teleport_to(MapData.cell_to_world(Vector2i(4, 7), 0.05), -PI * 0.5)
	var ok: bool = await until(func(): return game.zombies.alive.size() >= 3, 40.0, "zombies reçus")
	if not ok:
		return
	await seconds(Zombie.EMERGE_TIME + 0.5)
	H.aim_at(p, MapData.cell_to_world(Vector2i(10, 7)))
	var points0 := pd.points
	# Objets créés chez le client, avec leur numéro à la création (< 0 : prédit).
	var created := []
	sys.child_entered_tree.connect(func(n: Node):
		if n is Throwable:
			created.append([n, n.tid]))
	p.input.grenade = true
	await seconds(0.6)
	p.input.grenade = false
	ok = await until(func(): return sys._predicted.is_empty() and not sys.items.is_empty(), 3.0, "objet rattaché au serveur")
	var pred: Throwable = created[0][0] if not created.is_empty() else null
	at.check(created.size() == 1 and created[0][1] < 0, "grenade affichée sans attendre le serveur (prédiction, %d objet(s))" % created.size())
	at.check(ok and pred != null and sys.items.values()[0] == pred and pred.tid > 0, "prédiction rattachée à l'objet du serveur (n°%d)" % (pred.tid if pred else 0))
	await seconds(0.15)
	await at.screenshot("flight")
	ok = await until(func(): return booms.size() >= 1, 6.0, "explosion reçue")
	await seconds(0.05)
	await at.screenshot("explosion")
	await seconds(0.4)
	at.check(ok and sys.items.is_empty(), "explosion reçue, objet retiré")
	at.check(pd.points - points0 == 3 * PointsRules.SPLASH_KILL and pd.grenades == 1, "points (+%d) et réserve (%d) répliqués" % [pd.points - points0, pd.grenades])

	# SINGE-TAMBOUR donné par le serveur.
	ok = await until(func(): return pd.has_monkeys and pd.monkeys == 3, 20.0, "singes reçus")
	if not ok:
		return
	await seconds(0.5)
	H.aim_at(p, MapData.cell_to_world(Vector2i(11, 7)))
	p.input.tactical = true
	await seconds(0.6)
	p.input.tactical = false
	ok = await until(func(): return not sys.items.is_empty() and sys.items.values()[0].luring, 5.0, "musique du singe")
	at.check(ok, "le singe joue sa musique chez le client")
	await seconds(3.0)
	await at.screenshot("monkey")
	ok = await until(func(): return booms.size() >= 2, ThrowableRules.MONKEY_TIME, "explosion du singe")
	at.check(ok and pd.monkeys == 2, "explosion du singe reçue (reste %d)" % pd.monkeys)
	await seconds(3.0)
