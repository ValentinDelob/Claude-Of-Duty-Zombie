extends AutotestScenario
## Le jeu démarre, affiche le menu principal et tourne sans erreur.

func run() -> void:
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	await frames(10)
	at.begin_perf()
	await seconds(1.5)
	var fps: float = at.end_perf("menu")
	at.check_perf(fps, 150.0, "menu")
	at.check(GameState.state == GameState.State.MAIN_MENU, "état MAIN_MENU")
	await at.screenshot("menu")
