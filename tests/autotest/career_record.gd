extends AutotestScenario
## Dossier de combat : un GAME OVER solo enregistre la partie ; l'écran
## DOSSIER DE COMBAT du menu affiche les statistiques.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	CareerStats.reset()
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.rounds.debug_jump_to(4)
	var pd := game.session.local_data()
	pd.kills = 17
	pd.headshots = 5
	await seconds(1.0)  # la manche 4 s'installe (état exact attendu incertain : attente gardée)
	game.combat.damage_player(1, 500, p.global_position)
	await until(func(): return GameState.state == GameState.State.GAME_OVER, 5.0, "GAME OVER")
	var s := CareerStats.load_stats()
	at.check(s.games == 1 and s.best_round_solo == 4 and s.kills == 17 and s.headshots == 5,
			"partie enregistrée (%s)" % s)
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 20.0, "retour au menu")
	var menu: MainMenu = tree().current_scene
	await seconds(1.0)  # le menu finit d'apparaître
	menu.show_screen("career")
	await seconds(1.2)  # capture : fondu de l'écran (les valeurs sont remplies dès l'entrée)
	var screen = menu.current
	at.check(screen.rows.has("kills") and screen.rows.kills.text == "17", "écran : zombies abattus = 17")
	at.check(screen.rows.best_round_solo.text == "4", "écran : meilleure manche solo = 4")
	await at.screenshot("screen")
	menu.show_screen("main")
	await seconds(1.0)  # capture : fondu de l'écran
	await at.screenshot("main_menu")
	CareerStats.reset()
