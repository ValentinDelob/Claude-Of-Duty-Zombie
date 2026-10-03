extends AutotestScenario
## [MP] Client (invité) : 8 s de sprint maintenu, mesures du scénario
## sprint_smooth sur le joueur invité (pas de bascule sprint/marche à chaque
## image une fois l'endurance épuisée, caméra, FOV et arme continus).

const PORT := 17897


func run() -> void:
	timeout_sec = 90
	if not await MpHelpers.join_game(self, PORT):
		return
	var p := Game.instance.local_player
	p.bot_controlled = true
	p.untargetable = true
	if not await MpHelpers.wait_peer(self, "pret", 20.0):
		return
	var probe = preload("res://tests/autotest/sprint_smooth.gd").new()
	probe.at = at
	probe.p = p
	MpHelpers.signal_peer("course")
	await probe.phase("invite", false)
	MpHelpers.signal_peer("course_fin")
	await MpHelpers.finish(self)
