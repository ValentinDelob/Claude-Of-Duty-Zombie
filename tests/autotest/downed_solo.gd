extends AutotestScenario
## À terre en solo : avec LAZARUS, auto-réanimation (armes rendues, atout
## perdu) ; à terre on rampe et on tire au pistolet.

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 90
	var p: Player = await H.start_solo_game(self)
	if p == null:
		return
	var game := Game.instance
	game.rounds.paused = true
	var pd := game.session.local_data()
	# Équipement : carabine + LAZARUS.
	WeaponDB.give(pd, "m14")
	game.session.sync_inventory(1)
	game.perks.srv_grant(1, "lazarus")
	await seconds(2.6)  # fin de la boisson de l'atout (réplique incluse)
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 7), 0.05), -PI * 0.5)
	game.combat.damage_player(1, 200, p.global_position + Vector3(1, 1, 0))
	await until(func(): return pd.life == PlayerData.Life.DOWNED and GameState.state == GameState.State.PLAYER_DOWN and game.hud._downed._title.text == Lang.t("À TERRE", "DOWNED"), 2.0, "joueur à terre")
	at.check(pd.life == PlayerData.Life.DOWNED, "à terre à 0 PV")
	at.check(GameState.state == GameState.State.PLAYER_DOWN, "état PLAYER_DOWN")
	at.check(pd.weapons.size() == 1 and pd.current_weapon().id == "m1911", "dernier recours : pistolet seul")
	at.check(not pd.has_perk("lazarus"), "atouts perdus")
	at.check(game.hud._downed._title.text == Lang.t("À TERRE", "DOWNED"), "HUD : À TERRE")
	await seconds(0.3)  # capture
	await at.screenshot("downed")
	# On rampe.
	var x0 := p.global_position.x
	p.input.move = Vector2(0, 1)
	await seconds(1.0)  # durée mesurée
	p.input.move = Vector2.ZERO
	var crawl := p.global_position.x - x0
	at.check(crawl > 0.3 and crawl < 1.5, "déplacement limité à terre (%.2f m/s)" % crawl)
	# On tire.
	var shots := [0]
	game.combat.shot_validated.connect(func(_pid): shots[0] += 1)
	await H.shoot(self, p)
	at.check(shots[0] == 1, "tir possible à terre")
	# HUD : la barre d'auto-réanimation se remplit (pas de compte à rebours
	# de saignement de 45 s alors qu'on se relève en 10 s).
	var ov := game.hud._downed
	at.check(ov._revive.text.contains("█") and ov._time.text == "",
		"HUD : barre d'auto-réanimation (« %s », « %s »)" % [ov._revive.text, ov._time.text])
	# Auto-réanimation LAZARUS (10 s, comme BO1).
	await until(func(): return pd.life == PlayerData.Life.ALIVE, DownedSystem.SOLO_SELF_REVIVE + 3.0, "réanimation")
	at.check(pd.life == PlayerData.Life.ALIVE and pd.health == 100, "réanimé par LAZARUS (%d PV)" % pd.health)
	at.check(pd.has_weapon("m14") >= 0 and pd.weapons.size() == 2, "armes rendues")
	at.check(GameState.state == GameState.State.PLAYING, "retour à PLAYING")
	# Sans LAZARUS : fin de partie.
	game.combat.damage_player(1, 200, p.global_position)
	await until(func(): return GameState.state == GameState.State.GAME_OVER, 3.0, "GAME OVER")
	at.check(GameState.state == GameState.State.GAME_OVER, "à terre sans LAZARUS en solo : GAME OVER")
