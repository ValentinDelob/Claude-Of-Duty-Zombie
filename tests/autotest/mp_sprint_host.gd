extends AutotestScenario
## [MP] Hôte : regarde l'invité sprinter 8 s (endurance épuisée en route).
## L'état de sprint reçu par le réseau ne doit pas basculer plus d'une fois
## par seconde (soldat de l'invité qui alternerait course et marche).

const PORT := 17897

var _client: Player
var _times: Array = []
var _last := false
var _t := 0.0


func run() -> void:
	timeout_sec = 90
	if not await MpHelpers.host_game(self, PORT):
		return
	var game := Game.instance
	game.rounds.paused = true
	await AutotestHelpers.clear_zombies(self)
	var host := game.local_player
	host.bot_controlled = true
	host.untargetable = true
	# Spectateur hors de la bande de course (rangée 3).
	host.teleport_to(MapData.cell_to_world(Vector2i(6, 12), 0.05), PI)
	for pid in game.players:
		if pid != 1:
			_client = game.players[pid]
	if _client == null:
		at.fail("aucun invité")
		return
	MpHelpers.signal_peer("pret")
	if not await MpHelpers.wait_peer(self, "course", 30.0):
		return
	tree().physics_frame.connect(_record)
	await MpHelpers.wait_peer(self, "course_fin", 40.0)
	tree().physics_frame.disconnect(_record)
	var best := 0
	var a := 0
	for b in _times.size():
		while _times[b] - _times[a] > 1.0:
			a += 1
		best = maxi(best, b - a + 1)
	print("[mp_sprint] hôte : %d bascules du sprint de l'invité vu par le réseau (max %d/s)" % [_times.size(), best])
	at.check(_times.size() >= 1, "l'hôte voit l'invité sprinter puis s'arrêter (%d bascules)" % _times.size())
	at.check(best <= 1, "sprint de l'invité vu sans va-et-vient (max %d bascules/s)" % best)
	await MpHelpers.finish(self)


func _record() -> void:
	_t += 1.0 / float(Engine.physics_ticks_per_second)
	if _client.sprinting != _last:
		_last = _client.sprinting
		_times.append(_t)
