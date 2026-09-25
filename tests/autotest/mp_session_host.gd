extends AutotestScenario
## [MP] Hôte : le client meurt et me regarde jouer (spectateur), réapparaît,
## puis je quitte : le client doit revenir au menu avec un message clair.

const PORT := 17815


func run() -> void:
	timeout_sec = 100
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	game.local_player.bot_controlled = true
	var cid := 0
	for pid in game.players:
		if pid != 1:
			cid = pid
	var cpd := game.session.get_data(cid)
	await seconds(3.0)
	game.downed.bleedout_time = 1.5
	game.combat.damage_player(cid, 500, Vector3.ZERO)
	await until(func(): return cpd.life == PlayerData.Life.DEAD, 5.0, "client mort")
	await seconds(4.0)
	game.rounds.debug_jump_to(2)
	await seconds(4.0)
	at.check(cpd.life == PlayerData.Life.ALIVE, "client réapparu")
	# L'hôte quitte la partie en cours.
	Router.back_to_menu()
	await seconds(4.0)
	at.check(tree().current_scene.name == "MainMenu", "hôte revenu au menu")
