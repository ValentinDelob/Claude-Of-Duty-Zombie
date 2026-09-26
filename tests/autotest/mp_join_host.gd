extends AutotestScenario
## [MP] Hôte du test de connexion : attend le client puis ferme la partie
## (le client doit afficher une déconnexion propre).

var PORT := 17811 + MpHelpers.port_offset()


func run() -> void:
	timeout_sec = 90
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu")
	Net.host(PORT, 2, "Hote")
	GameState.set_state(GameState.State.LOBBY)
	var ok: bool = await until(func(): return Net.players.size() == 2, 45.0, "client connecté")
	if not ok:
		return
	at.check(true, "client connecté au salon")
	await seconds(3.0)
	Net.leave()
	GameState.reset_to_menu()
	at.check(true, "l'hôte ferme la partie")
	await seconds(4.0)
