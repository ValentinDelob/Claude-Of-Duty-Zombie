extends AutotestScenario
## Session terminée PENDANT le chargement (préchauffage des shaders en cours),
## au début, au milieu et à la toute fin du préchauffage : retour propre au
## menu, sans erreur ni partie fantôme (le préchauffage s'arrête, le
## chargement n'est jamais annoncé à une session disparue).


func run() -> void:
	timeout_sec = 60
	for k in [0, 12, Warmup.FRAMES - 1, Warmup.FRAMES]:
		await _abort_after(k)


func _abort_after(k: int) -> void:
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	Router.start_solo("test_arena")
	var loading: bool = await until(func(): return Game.instance != null and Game.instance.world != null \
			and Game.instance.world.get_node_or_null("Warmup") != null, 10.0, "préchauffage en cours")
	at.check(loading, "[%d] le préchauffage a commencé" % k)
	var game := Game.instance
	var reported := []
	game.loaded.connect(func(): reported.append(GameState.state))
	await frames(k)
	var finished_before := not reported.is_empty()
	# La session se termine (hôte perdu, ou « Quitter » pendant le chargement).
	Net.session_ended.emit("test : session terminée pendant le chargement")
	var n := reported.size()
	var back: bool = await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 10.0, "retour au menu")
	at.check(back, "[%d] retour au menu" % k)
	# Plus que la durée du préchauffage : aucune reprise de coroutine sur un
	# objet libéré, aucun « chargé » envoyé, aucune partie lancée.
	await frames(Warmup.FRAMES * 2)
	at.check(reported.size() == n, "[%d] chargement jamais annoncé après la fin de session (avant : %s, après : %d)" % [k, finished_before, reported.size() - n])
	at.check(Game.instance == null and not is_instance_valid(game), "[%d] aucune partie restante" % k)
	at.check(GameState.state == GameState.State.MAIN_MENU, "[%d] état : menu principal (%s)" % [k, GameState.State.keys()[GameState.state]])
	at.check(Net.mode == Net.Mode.NONE and Net.loaded_peers.is_empty(), "[%d] plus de session réseau" % k)
