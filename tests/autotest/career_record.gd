extends AutotestScenario
## Dossier de combat : un GAME OVER solo enregistre la partie ; l'écran
## DOSSIER DE COMBAT du menu affiche les statistiques. L'XP de la partie est
## ajoutée au profil du joueur (MatchXp).

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	CareerStats.reset()
	ProfileStore.reset()
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	game.rounds.debug_jump_to(4)
	await H.clear_zombies(self)
	# Une élimination réelle (marcheur, manche 4) : l'XP de la partie.
	var z := await H.dummy_zombie(self, p.global_position + Vector3(0, 0, -4))
	game.combat.damage_zombie(z.id, 99999, 1, false, Vector3.FORWARD, Combat.HitKind.BULLET)
	var pd := game.session.local_data()
	pd.kills = 17
	pd.headshots = 5
	await seconds(1.0)  # la manche 4 s'installe (état exact attendu incertain : attente gardée)
	game.combat.damage_player(1, 500, p.global_position)
	await until(func(): return GameState.state == GameState.State.GAME_OVER, 5.0, "GAME OVER")
	var s := CareerStats.load_stats()
	at.check(s.games == 1 and s.best_round_solo == 4 and s.kills == 17 and s.headshots == 5,
			"partie enregistrée (%s)" % s)
	# XP de la partie ajoutée au profil (aucune manche terminée : l'élimination seule).
	var xp := ProfileStore.load_profile().xp
	at.check(xp == XpRules.kill_xp(XpRules.WALKER, 4) and game.last_result.xp == xp, "XP de la partie au profil (%d)" % xp)
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 20.0, "retour au menu")
	var menu: MainMenu = tree().current_scene
	await seconds(1.0)  # le menu finit d'apparaître
	menu.show_screen("career")
	await seconds(1.2)  # capture : fondu de l'écran (les valeurs sont remplies dès l'entrée)
	var screen = menu.current
	at.check(screen.rows.has("kills") and screen.rows.kills.text == "17", "écran : zombies abattus = 17")
	at.check(screen.rows.best_round_solo.text == "4", "écran : meilleure manche solo = 4")
	at.check(screen.level_label.text == Lang.t("NIVEAU %d", "LEVEL %d") % 1 and screen.progress_label.text == MatchResult.progress_text(xp),
			"écran : niveau du profil et progression (%s, %s)" % [screen.level_label.text, screen.progress_label.text])
	at.check(is_equal_approx(screen.progress_bar.value, float(xp)), "barre de progression : %d XP" % xp)
	await at.screenshot("screen")
	menu.show_screen("main")
	await seconds(1.0)  # capture : fondu de l'écran
	await at.screenshot("main_menu")
	CareerStats.reset()
