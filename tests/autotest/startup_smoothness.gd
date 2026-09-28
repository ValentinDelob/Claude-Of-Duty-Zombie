extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## Début de partie fluide : aucune saccade due à la compilation des shaders
## une fois la main donnée au joueur (préchauffage pendant le chargement).

func run() -> void:
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	Router.start_solo("bunker_k7")
	await until(func(): return Game.instance != null and Game.instance.local_player != null, 15.0, "joueur en jeu")
	var p := Game.instance.local_player
	p.bot_controlled = true
	# L'image de transition (fin du chargement -> apparition) est masquée par
	# l'écran de chargement qui s'estompe : on mesure juste après.
	await seconds(0.3)
	at.begin_perf()
	# On regarde partout pendant 2 s, on tire, un zombie apparaît.
	Game.instance.zombies.spawn(p.global_position + Vector3(0, 0, -6), 0, 150)
	for i in 40:
		p.input.look = Vector2(35, 0)
		p.input.fire = i % 6 == 0
		await seconds(0.05)
	at.end_perf("début de partie")
	var worst: float = at._frame_ms_max
	if OS.get_environment("AUTOTEST_PARALLEL") == "1":
		print("[autotest] (parallèle) pire image au démarrage : %.1f ms" % worst)
	else:
		at.check(worst < 40.0, "pire image au démarrage %.1f ms (< 40)" % worst)
