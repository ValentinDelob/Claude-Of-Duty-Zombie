extends AutotestScenario
## [MP] Client : sprint, plongeon, reste allongé ~1,5 s puis se relève.

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
	await seconds(3.0)
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	await seconds(0.45)
	p.input.crouch = true
	var ok: bool = await until(func(): return p.diving, 1.0, "plongeon")
	at.check(ok, "plongeon local")
	ok = await until(func(): return p.prone, 1.5, "à plat ventre")
	at.check(ok, "atterrissage à plat ventre")
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	await seconds(1.5)
	await at.screenshot("prone")
	p.input.crouch = false
	ok = await until(func(): return not p.prone, 2.0, "relevé")
	at.check(ok, "relevé")
	await seconds(4.0)
