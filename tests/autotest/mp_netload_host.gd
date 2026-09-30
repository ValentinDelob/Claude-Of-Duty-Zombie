extends AutotestScenario
## @temps-reel : débit mesuré par seconde RÉELLE (budget réseau), reste en temps réel.
## [MP] Hôte : charge réseau. 24 zombies en poursuite (remplacés dès qu'ils
## meurent), l'hôte fait des allers-retours pour les faire bouger, le client
## tire en rafale (arme automatique donnée ici). Mesure chaque seconde les
## octets envoyés / reçus par l'hôte (statistiques ENet, après compression) et
## les classe en fenêtres « repos » (aucun tir validé) et « tirs ».
## Un seul client : les octets envoyés par l'hôte = le flux descendant du client.

const PORT := 17830
const ZOMBIES := 24
## Objectif du protocole (Ko/s descendants par client, tirs compris).
const BUDGET_KBPS := 10.0

var game: Game
var _shots := 0
var _snap_bytes := 0
var _idle: Array[Dictionary] = []
var _firing: Array[Dictionary] = []


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.host_game(self, PORT):
		return
	game = Game.instance
	game.rounds.paused = true
	game.combat.debug_invulnerable = true
	game.combat.shot_validated.connect(func(_pid: int): _shots += 1)
	var p := game.local_player
	p.bot_controlled = true
	var client_id := 0
	for pid in game.players:
		if pid != 1:
			client_id = pid
	await seconds(2.0)
	# Arme automatique pour le client (tirs soutenus), munitions illimitées.
	var cpd := game.session.get_data(client_id)
	cpd.weapons = [WeaponDB.new_instance("mp40")]
	cpd.slot = 0
	game.session.sync_inventory(client_id)
	p.teleport_to(MapData.cell_to_world(Vector2i(2, 3), 0.05), -PI * 0.5)
	await seconds(0.5)
	_top_up()
	await seconds(Zombie.EMERGE_TIME + 1.0)
	Net.sample_bandwidth()
	_snap_bytes = game.zombies.snapshot_bytes
	var t := 0.0
	var window := 0.0
	var dir := 1.0
	var zombie_frames := 0
	var zombie_sum := 0
	p.input.move = Vector2(0.0, 1.0)
	while t < 42.0:
		await tree().physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		window += dt
		# Allers-retours sur la rangée 3 (dégagée) : les zombies bougent sans cesse.
		var cx := p.global_position.x
		if dir > 0.0 and cx > MapData.cell_to_world(Vector2i(22, 3)).x:
			dir = -1.0
			p.yaw = PI * 0.5
		elif dir < 0.0 and cx < MapData.cell_to_world(Vector2i(3, 3)).x:
			dir = 1.0
			p.yaw = -PI * 0.5
		p.rotation.y = p.yaw
		zombie_sum += game.zombies.alive_count()
		zombie_frames += 1
		if window >= 1.0:
			window = 0.0
			_top_up()
			var s := Net.sample_bandwidth()
			if s.is_empty() or s.dt <= 0.0:
				continue
			s.shots = _shots
			s.snap = game.zombies.snapshot_bytes - _snap_bytes
			_snap_bytes = game.zombies.snapshot_bytes
			s.zombies = float(zombie_sum) / maxi(zombie_frames, 1)
			_shots = 0
			zombie_sum = 0
			zombie_frames = 0
			if s.shots == 0:
				_idle.append(s)
			elif s.shots >= 5:
				_firing.append(s)
			# Munitions : le client ne doit jamais s'arrêter faute de balles.
			var w: Dictionary = cpd.current_weapon()
			if not w.is_empty() and w.reserve < 200:
				w.reserve = 600
				game.session.sync_inventory(client_id)
	p.input.move = Vector2.ZERO
	var idle := _report("repos", _idle)
	var firing := _report("tirs", _firing)
	at.check(_idle.size() >= 4 and _firing.size() >= 6, "fenêtres de mesure : %d au repos, %d en tir" % [_idle.size(), _firing.size()])
	at.check(firing > 0.0 and firing < BUDGET_KBPS, "flux descendant par client en tir : %.2f Ko/s < %.0f Ko/s" % [firing, BUDGET_KBPS])
	at.check(idle > 0.0 and idle <= firing + 0.5, "repos (%.2f Ko/s) <= tirs (%.2f Ko/s)" % [idle, firing])
	await seconds(4.0)


## Maintient ZOMBIES zombies vivants (apparitions réparties dans l'arène).
func _top_up() -> void:
	var cells := [Vector2i(6, 1), Vector2i(12, 1), Vector2i(20, 1), Vector2i(23, 3), Vector2i(20, 8),
		Vector2i(12, 8), Vector2i(5, 9), Vector2i(22, 11), Vector2i(10, 11), Vector2i(3, 9)]
	var k := game.zombies.alive_count()
	while k < ZOMBIES:
		var c: Vector2i = cells[k % cells.size()]
		var jitter := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
		game.zombies.spawn(MapData.cell_to_world(c) + jitter, k % 4, 450)
		k += 1


## Moyenne des fenêtres : imprime une ligne [perf] et retourne les Ko/s
## envoyés par client (0 si aucune fenêtre).
func _report(label: String, list: Array[Dictionary]) -> float:
	if list.is_empty():
		print("[perf] réseau (hôte, %s) : aucune fenêtre" % label)
		return 0.0
	var sent := 0.0
	var recv := 0.0
	var sp := 0.0
	var rp := 0.0
	var dt := 0.0
	var shots := 0.0
	var zs := 0.0
	var snap := 0.0
	for s in list:
		snap += s.snap
		sent += s.sent
		recv += s.recv
		sp += s.sent_packets
		rp += s.recv_packets
		dt += s.dt
		shots += s.shots
		zs += s.zombies
	var clients := maxi(multiplayer_clients(), 1)
	var kbps := sent / dt / 1024.0 / clients
	print("[perf] réseau (hôte, %s, %.0f zombies, %.1f tirs/s) : %.2f Ko/s envoyés par client, %.2f Ko/s reçus, %.0f paquets/s envoyés, %.0f reçus, instantanés de zombies %.2f Ko/s avant compression (%d fenêtres de 1 s)" % [
		label, zs / list.size(), shots / dt, kbps, recv / dt / 1024.0 / clients, sp / dt, rp / dt, snap / dt / 1024.0, list.size()])
	return kbps


func multiplayer_clients() -> int:
	return tree().get_multiplayer().get_peers().size()
