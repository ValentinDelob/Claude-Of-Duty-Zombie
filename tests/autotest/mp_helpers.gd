class_name MpHelpers
extends RefCounted
## Démarrage des tests multijoueur (hôte / client) jusqu'à la partie.


static func host_game(sc: AutotestScenario, port: int, map_id := "test_arena") -> bool:
	await sc.until(func(): return sc.tree().current_scene != null and sc.tree().current_scene.name == "MainMenu", 5.0, "menu")
	Net.host(port, 4, "Hote")
	GameState.set_state(GameState.State.LOBBY)
	if not await sc.until(func(): return Net.players.size() >= 2, 40.0, "client connecté"):
		return false
	await sc.seconds(0.5)
	Net.start_match(map_id)
	return await sc.until(func(): return Game.instance != null and Game.instance.players.size() >= 2 and Game.instance.local_player != null, 25.0, "partie lancée")


static func join_game(sc: AutotestScenario, port: int) -> bool:
	await sc.until(func(): return sc.tree().current_scene != null and sc.tree().current_scene.name == "MainMenu", 5.0, "menu")
	await sc.seconds(1.5)
	GameState.set_state(GameState.State.CONNECTING)
	Net.join("127.0.0.1", port, "Client")
	return await sc.until(func(): return Game.instance != null and Game.instance.players.size() >= 2 and Game.instance.local_player != null, 45.0, "partie rejointe")
