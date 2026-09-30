extends AutotestScenario
## [MP] Client : quitte la partie via le menu pause.

const PORT := 17816


func run() -> void:
	timeout_sec = 90
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	game.hud.pause_menu.open()
	await seconds(0.3)  # la partie continue de tourner menu ouvert
	at.check(not tree().paused, "en multijoueur la pause ne fige pas la partie")
	await at.screenshot("pause_mp")
	game.hud.pause_menu._leave()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 8.0, "menu")
	at.check(Net.mode == Net.Mode.NONE, "session fermée côté client")
	await MpHelpers.finish(self)
