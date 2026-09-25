extends AutotestScenario
## [MP] Client : à terre (état, HUD, barre de réanimation), réanimé, mort,
## réapparition.

const PORT := 17814


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var pd := game.session.local_data()
	p.teleport_to(MapData.cell_to_world(Vector2i(6, 7), 0.05), -PI * 0.5)
	await until(func(): return pd.life == PlayerData.Life.DOWNED, 20.0, "à terre")
	await seconds(0.3)
	at.check(GameState.state == GameState.State.PLAYER_DOWN, "état PLAYER_DOWN")
	at.check(game.hud._downed._title.text == "À TERRE", "HUD : À TERRE")
	var saw_bar := [false]
	var ok: bool = await until(func():
		if game.hud._downed._revive.text.contains("█"):
			saw_bar[0] = true
		return pd.life == PlayerData.Life.ALIVE, 20.0, "réanimé")
	at.check(ok and saw_bar[0], "barre de réanimation affichée puis réanimé")
	await seconds(0.2)
	at.check(GameState.state == GameState.State.PLAYING, "retour à PLAYING")
	await until(func(): return pd.life == PlayerData.Life.DEAD, 20.0, "mort")
	at.check(pd.life == PlayerData.Life.DEAD, "mort par saignement reçue")
	await until(func(): return pd.life == PlayerData.Life.ALIVE, 15.0, "réapparition")
	at.check(pd.life == PlayerData.Life.ALIVE and not p.dead, "réapparition à la manche suivante")
	await seconds(3.0)
