extends AutotestScenario
## [MP] Client : sprint, plongeon, reste allongé (le temps que l'hôte le voie)
## puis se relève.

const PORT := 17883


func run() -> void:
	timeout_sec = 90
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 7), 0.05), -PI * 0.5)
	p.pitch = 0.0
	if not await MpHelpers.wait_peer(self, "depart_vu", 20.0):
		return
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await seconds(0.45)  # élan : le joueur sprinte avant de plonger
	p.input.crouch = true
	var ok: bool = await until(func(): return p.diving, 1.0, "plongeon")
	at.check(ok, "plongeon local")
	ok = await until(func(): return p.prone, 1.5, "à plat ventre")
	at.check(ok, "atterrissage à plat ventre")
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	await seconds(0.3)
	await at.screenshot("prone")
	# Allongé (accroupi maintenu) jusqu'à ce que l'hôte ait vu la pose.
	await MpHelpers.wait_peer(self, "allonge_vu", 15.0)
	p.input.crouch = false
	ok = await until(func(): return not p.prone, 2.0, "relevé")
	at.check(ok, "relevé")
	await MpHelpers.finish(self)
