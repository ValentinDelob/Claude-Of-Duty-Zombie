extends AutotestScenario
## [MP] Client (invité) : recharge son fusil à pompe, l'hôte lui fait boire un
## atout à mi-course : la prédiction s'arrête (même compte de cartouches que
## le serveur, chargeur pas rempli), pas de rechargement pendant la boisson,
## puis il faut recharger de nouveau.

const PORT := 17903


func run() -> void:
	timeout_sec = 90
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	p.untargetable = true
	var wc := p.weapons
	var pd := game.session.local_data()
	if not await MpHelpers.wait_peer(self, "arme", 30.0):
		return
	if not await until(func(): return wc.current().get("id", "") == "stakeout" and int(wc.current().mag) == 1, 5.0, "fusil à pompe reçu"):
		return
	await seconds(WeaponController.SWITCH_TIME + 0.2)
	var full := int(WeaponDB.stats("stakeout").mag)
	p.input.reload = true
	await until(func(): return wc.is_reloading(), 2.0, "rechargement local")
	if not await until(func(): return wc.view.is_drinking(), 20.0, "boisson reçue"):
		return
	at.check(not wc.is_reloading(), "invité : rechargement arrêté par la boisson")
	# Touche pendant la boisson : ignorée ; demande envoyée quand même (comme
	# partie juste avant d'apprendre la boisson) : refusée par le serveur.
	p.input.reload = true
	game.combat.srv_reload.rpc_id(1, wc.slot)
	MpHelpers.signal_peer("demande")
	await frames(3)
	at.check(not wc.is_reloading(), "invité : pas de rechargement pendant la boisson")
	if not await MpHelpers.wait_peer(self, "verifie", 30.0):
		return
	var mine := [int(wc.weapons[0].mag), int(wc.weapons[0].reserve)]
	var srv := [int(pd.weapons[0].mag), int(pd.weapons[0].reserve)]
	print("[mp_drink] invité : prédiction %s, inventaire du serveur %s" % [mine, srv])
	at.check(mine == srv, "invité : prédiction = inventaire du serveur (%s / %s)" % [mine, srv])
	at.check(mine[0] > 1 and mine[0] < full and mine[0] + mine[1] == 31, "invité : cartouches gardées, chargeur pas rempli : %s" % [mine])
	await until(func(): return GameClock.now() >= wc._drink_end and not wc.view.is_drinking(), 5.0, "fin de la boisson")
	p.input.reload = true
	var ok: bool = await until(func(): return int(wc.current().mag) == full and int(pd.weapons[0].mag) == full, 10.0, "rechargement refait")
	at.check(ok, "invité : rechargement refait après la boisson (%d, serveur %d)" % [int(wc.current().mag), int(pd.weapons[0].mag)])
	await MpHelpers.finish(self)
