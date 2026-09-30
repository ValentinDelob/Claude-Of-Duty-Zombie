extends AutotestScenario
## Menu pause (solo : partie suspendue) et tableau des scores.

var H := AutotestHelpers


func run() -> void:
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	var z := await H.dummy_zombie(self, p.global_position + Vector3(0, 0, -8))
	z.speed_mult = 1.0
	await seconds(0.3)  # le zombie se met en marche avant la pause
	game.hud.pause_menu.open()
	await frames(2)
	at.check(tree().paused and game.hud.pause_menu.visible, "pause : partie suspendue en solo")
	var zpos := z.global_position
	await seconds(1.0)  # rien ne doit bouger : fenêtre d'observation fixe
	at.check(z.global_position.distance_to(zpos) < 0.01, "les zombies sont figés pendant la pause")
	await at.screenshot("pause")
	game.hud.pause_menu.close()
	await until(func(): return not tree().paused and is_instance_valid(z) and z.global_position.distance_to(zpos) > 0.2, 3.0, "zombie reparti après la pause")
	at.check(not tree().paused and z.global_position.distance_to(zpos) > 0.2, "reprise : les zombies repartent")
	# Tableau des scores.
	Input.action_press("scoreboard")
	await frames(3)
	at.check(game.hud.scoreboard.visible, "[Tab] : tableau des scores affiché")
	await at.screenshot("scoreboard")
	Input.action_release("scoreboard")
	await frames(3)
	at.check(not game.hud.scoreboard.visible, "relâché : tableau masqué")
	# Quitter la partie depuis la pause.
	game.hud.pause_menu.open()
	game.hud.pause_menu._leave()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "retour au menu")
	at.check(not tree().paused and GameState.state == GameState.State.MAIN_MENU, "QUITTER LA PARTIE : retour au menu")
