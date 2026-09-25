extends AutotestScenario
## Le jeu démarre, affiche sa première scène et tourne sans erreur.

func run() -> void:
	await frames(10)
	at.begin_perf()
	await seconds(2.0)
	var fps: float = at.end_perf("boot")
	at.check(fps > 30.0, "FPS raisonnables au démarrage (%.0f)" % fps)
	at.check(tree().current_scene != null, "une scène courante existe")
	await at.screenshot("start")
