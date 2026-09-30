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
	game.downed.bleedout_time = 1.5
	game.combat.damage_player(cid, 500, Vector3.ZERO)
	await until(func(): return cpd.life == PlayerData.Life.DEAD, 5.0, "client mort")
	# Le client est passé spectateur.
	if not await MpHelpers.wait_peer(self, "spectateur", 15.0):
		return
	game.rounds.debug_jump_to(2)
	await until(func(): return cpd.life == PlayerData.Life.ALIVE, 5.0, "client réapparu")
	at.check(cpd.life == PlayerData.Life.ALIVE, "client réapparu")
	# Le client a retrouvé sa vue ; l'hôte quitte la partie en cours.
	if not await MpHelpers.wait_peer(self, "revenu", 15.0):
		return
	Router.back_to_menu()
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 8.0, "menu de l'hôte")
	at.check(tree().current_scene.name == "MainMenu", "hôte revenu au menu")
	await MpHelpers.finish(self)
