extends AutotestScenario
## [MP] Hôte : l'INVITÉ boit un atout pendant le rechargement de son fusil à
## pompe (BO1) : le serveur annule le rechargement (cartouches déjà poussées
## gardées, rien d'autre), ne remplit rien à l'échéance, refuse une demande
## de rechargement arrivée pendant la boisson ; après la boisson, le
## rechargement refait par l'invité aboutit.

const PORT := 17903


func run() -> void:
	timeout_sec = 90
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	await AutotestHelpers.clear_zombies(self)
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	if cid == 0:
		at.fail("aucun invité")
		return
	var cpd := game.session.get_data(cid)
	cpd.weapons = [WeaponDB.new_instance("stakeout"), WeaponDB.new_instance("m1911")]
	cpd.weapons[0].mag = 1
	cpd.weapons[0].reserve = 30
	cpd.slot = 0
	game.combat.cancel_reload(cid)
	game.session.sync_inventory(cid)
	var full := int(WeaponDB.stats("stakeout").mag)
	MpHelpers.signal_peer("arme")

	# L'invité recharge ; boisson après un peu plus de la moitié des poussées.
	if not await until(func(): return game.combat.is_reloading(cid), 20.0, "rechargement de l'invité reçu"):
		return
	var r: Array = game.combat._reload_end[cid]
	var dur := float(r[3])
	await until(func(): return GameClock.now() - float(r[2]) >= dur * (0.12 + 0.65 * 0.55), 5.0, "rechargement à mi-course")
	game.perks.srv_grant(cid, "titan")
	at.check(not game.combat.is_reloading(cid), "serveur : rechargement de l'invité annulé par la boisson")
	var kept := [int(cpd.weapons[0].mag), int(cpd.weapons[0].reserve)]
	at.check(kept[0] > 1 and kept[0] < full and kept[0] + kept[1] == 31, "serveur : cartouches poussées gardées, rien d'autre : %s" % [kept])
	print("[mp_drink] hôte : boisson à mi-course, munitions de l'invité %s" % [kept])

	# Demande de rechargement envoyée par l'invité pendant la boisson.
	if not await MpHelpers.wait_peer(self, "demande", 20.0):
		return
	await seconds(0.3)  # l'appel réseau suit le fichier de rendez-vous
	at.check(game.combat.hands_busy(cid), "serveur : boisson encore en cours")
	at.check(not game.combat.is_reloading(cid), "serveur : rechargement refusé pendant la boisson")
	await seconds(dur + 0.3)  # au-delà de l'échéance du rechargement annulé
	var after := [int(cpd.weapons[0].mag), int(cpd.weapons[0].reserve)]
	at.check(after == kept, "serveur : rien rempli à l'échéance : %s" % [after])
	MpHelpers.signal_peer("verifie")

	# Après la boisson, l'invité recharge de nouveau.
	var ok: bool = await until(func(): return int(cpd.weapons[0].mag) == full, 20.0, "rechargement refait par l'invité")
	at.check(ok and int(cpd.weapons[0].reserve) == 31 - full, "serveur : rechargement refait après la boisson (%d/%d)" % [int(cpd.weapons[0].mag), int(cpd.weapons[0].reserve)])
	await MpHelpers.finish(self)
