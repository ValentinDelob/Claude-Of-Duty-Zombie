extends AutotestScenario
## [MP] Client : vote « partir » à la porte, sort de la zone, puis quitte la
## partie (menu pause) pendant la fenêtre d'évacuation : retour propre au
## menu ; l'hôte s'évacue sans lui.

const PORT := 17935

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	var p := game.local_player
	p.bot_controlled = true
	var me := p.peer_id
	var door := game.evac
	if door == null:
		at.fail("porte d'évacuation absente")
		return
	p.teleport_to(door.global_position + door.global_basis.z * 1.6 - door.global_basis.x * 1.0 + Vector3.UP * 0.05)
	await frames(3)
	MpHelpers.signal_peer("place")
	if not await MpHelpers.wait_peer(self, "ouverte", 60.0):
		return
	await until(func(): return door.is_open, 5.0, "porte ouverte chez le client")
	H.aim_at(p, door.interact_point())
	await until(func(): return game.interact.focused == door, 3.0, "client : porte visée")
	p.input.interact_pressed = true
	var ok: bool = await until(func(): return int(door.votes.get(me, 0)) == EvacRules.Vote.LEAVE, 5.0, "vote reçu en retour")
	at.check(ok, "client : vote « partir » enregistré")
	# Hors de la zone, au fond de la pièce.
	p.teleport_to(door.global_position + door.global_basis.z * 6.0 + Vector3.UP * 0.05)
	await frames(3)
	at.check(not door.in_zone(p.global_position), "client : sorti de la zone")
	MpHelpers.signal_peer("sorti")
	if not await MpHelpers.wait_peer(self, "attente", 30.0):
		return
	game.hud.pause_menu._leave()
	ok = await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 8.0, "menu")
	at.check(ok and Net.mode == Net.Mode.NONE, "client : parti, retour au menu")
	await MpHelpers.finish(self)
