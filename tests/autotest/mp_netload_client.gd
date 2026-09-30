extends AutotestScenario
## [MP] Client : charge réseau (voir mp_netload_host.gd). 10 s sans tirer puis
## 16 s de tirs en rafale sur le zombie le plus proche. Mesure le flux reçu
## (statistiques ENet) et la fluidité des marionnettes : pour chaque zombie en
## poursuite, vitesse d'une image à l'autre ; un « gel » est une image où un
## zombie qui avançait (> 1 m/s) s'arrête net (< 0,2 m/s), un « saut » un
## déplacement impossible (> 9 m/s, sprinteur = 5 m/s). Le client fait des
## allers-retours sur la rangée 14 pour que les zombies le poursuivent.

const PORT := 17830

var game: Game
var _last_pos: Dictionary = {}   # zid -> Vector3
var _last_speed: Dictionary = {} # zid -> float
var _frames := 0
var _freezes := 0
var _jumps := 0
var _speed_sum := 0.0
var _last_us := 0
var _dir := 1.0
var _turns := 0


func run() -> void:
	timeout_sec = 120
	if not await MpHelpers.join_game(self, PORT):
		return
	game = Game.instance
	var p := game.local_player
	p.bot_controlled = true
	p.teleport_to(MapData.cell_to_world(Vector2i(3, 14), 0.05), -PI * 0.5)
	if not await until(func(): return game.zombies.alive_count() >= 20, 30.0, "zombies reçus"):
		return
	await until(func(): return game.session.local_data().current_weapon().get("id", "") == "mp40" and game.zombies.alive.all(func(z): return z.state != Zombie.State.EMERGE), Zombie.EMERGE_TIME + 5.0, "arme reçue, horde sortie de terre")
	await seconds(1.0)  # la horde se met en route avant la mesure
	at.check(game.session.local_data().current_weapon().get("id", "") == "mp40", "arme automatique reçue de l'hôte")
	await at.screenshot("netload")
	# Repos.
	Net.sample_bandwidth()
	var idle := await _measure(p, 10.0, false)
	var idle_smooth := _smoothness("repos")
	# Tirs.
	var firing := await _measure(p, 16.0, true)
	var fire_smooth := _smoothness("tirs")
	p.input.fire = false
	print("[perf] réseau (client, repos) : %.2f Ko/s reçus, %.2f Ko/s envoyés, %.0f paquets/s reçus" % [idle.recv, idle.sent, idle.recv_packets])
	print("[perf] réseau (client, tirs, %d tirs) : %.2f Ko/s reçus, %.2f Ko/s envoyés, %.0f paquets/s reçus" % [idle.get("shots", 0) + firing.shots, firing.recv, firing.sent, firing.recv_packets])
	at.check(firing.shots > 50, "le client a tiré en rafale (%d tirs)" % firing.shots)
	at.check(firing.recv < 10.0, "flux reçu en tir : %.2f Ko/s < 10 Ko/s" % firing.recv)
	# Ancien protocole (instantanés complets), mêmes conditions : 0,1-0,9 % de
	# sauts, 0,1-0,3 % de gels (images lentes d'une machine chargée).
	at.check(idle_smooth[1] < 0.015 and fire_smooth[1] < 0.015, "marionnettes sans téléportation : sauts %.2f %% / %.2f %% des images" % [idle_smooth[1] * 100.0, fire_smooth[1] * 100.0])
	at.check(idle_smooth[0] < 0.015 and fire_smooth[0] < 0.015, "interpolation fluide : gels %.2f %% / %.2f %% des images" % [idle_smooth[0] * 100.0, fire_smooth[0] * 100.0])
	# En tir, la horde bloquée contre le joueur ralentit selon la charge de la
	# machine : on vérifie seulement qu'elle n'est pas figée.
	at.check(idle_smooth[2] > 0.4 and fire_smooth[2] > 0.2, "les marionnettes avancent (%.2f / %.2f m/s en moyenne)" % [idle_smooth[2], fire_smooth[2]])
	await at.screenshot("netload_fire")
	await MpHelpers.finish(self)


class Probe extends Node:
	var sc

	func _process(_d: float) -> void:
		sc._on_probe()


func _on_probe() -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_track((now - _last_us) / 1000000.0)
	_last_us = now


## Mesure pendant `dur` secondes (en tirant ou non) ; retourne les Ko/s moyens.
func _measure(p: Player, dur: float, fire: bool) -> Dictionary:
	_frames = 0
	_freezes = 0
	_jumps = 0
	_speed_sum = 0.0
	_last_pos.clear()
	_last_speed.clear()
	_last_us = 0
	var shots := [0]
	var cb := func(): shots[0] += 1
	p.weapons.fired.connect(cb)
	Net.sample_bandwidth()
	# Sonde appelée APRÈS l'interpolation de tous les zombies de l'image, avec
	# l'horloge murale (celle de l'interpolation) : mesure indépendante de la
	# charge de la machine (pas de physique de rattrapage, etc.).
	var probe := Probe.new()
	probe.sc = self
	probe.process_priority = 1000
	game.add_child(probe)
	var t := 0.0
	while t < dur:
		await tree().process_frame
		var dt := at.get_process_delta_time()
		t += dt
		if fire:
			var z := _nearest(p)
			if z:
				AutotestHelpers.aim_at(p, z.head_position())
			p.input.fire = z != null
		_patrol(p)
	probe.queue_free()
	p.input.fire = false
	p.input.move = Vector2.ZERO
	p.weapons.fired.disconnect(cb)
	print("[autotest] client : %d demi-tours, x = %.1f" % [_turns, p.global_position.x])
	var s := Net.sample_bandwidth()
	var d: float = maxf(s.get("dt", 0.0), 0.001)
	return {"recv": s.get("recv", 0) / d / 1024.0, "sent": s.get("sent", 0) / d / 1024.0,
		"recv_packets": s.get("recv_packets", 0) / d, "shots": shots[0]}


## Allers-retours sur la rangée 14 (dégagée), quelle que soit la visée : les
## zombies poursuivent une cible mobile au lieu de s'agglutiner.
func _patrol(p: Player) -> void:
	var x := p.global_position.x
	if _dir > 0.0 and x > MapData.cell_to_world(Vector2i(22, 14)).x:
		_dir = -1.0
		_turns += 1
	elif _dir < 0.0 and x < MapData.cell_to_world(Vector2i(3, 14)).x:
		_dir = 1.0
		_turns += 1
	var want := Vector3(_dir, 0.0, 0.0)
	var b := Basis(Vector3.UP, p.yaw)
	p.input.move = Vector2(want.dot(b.x), want.dot(-b.z))


func _nearest(p: Player) -> Zombie:
	var best: Zombie = null
	var bd := INF
	for z: Zombie in game.zombies.alive:
		if z.state == Zombie.State.EMERGE:
			continue
		var d := z.global_position.distance_squared_to(p.global_position)
		if d < bd:
			bd = d
			best = z
	return best


func _track(dt: float) -> void:
	if dt <= 0.0:
		return
	var seen := {}
	for z: Zombie in game.zombies.alive:
		seen[z.id] = true
		var pos := z.global_position
		if _last_pos.has(z.id) and z.state == Zombie.State.CHASE:
			var d := Vector2(pos.x - _last_pos[z.id].x, pos.z - _last_pos[z.id].z).length()
			var v := d / dt
			var prev: float = _last_speed.get(z.id, -1.0)
			_frames += 1
			_speed_sum += v
			if prev > 1.0 and v < 0.2 and dt > 0.005:
				_freezes += 1
			# Tolérance de 8 cm : l'image lue ici et celle de l'interpolation
			# ne tombent pas exactement au même instant.
			if d > 9.0 * dt + 0.08:
				_jumps += 1
			_last_speed[z.id] = v
		else:
			_last_speed.erase(z.id)
		_last_pos[z.id] = pos
	for zid in _last_pos.keys():
		if not seen.has(zid):
			_last_pos.erase(zid)
			_last_speed.erase(zid)


## [taux de gels, taux de sauts] sur les images-zombies mesurées.
func _smoothness(label: String) -> Array:
	var n := maxi(_frames, 1)
	var r := [float(_freezes) / n, float(_jumps) / n, _speed_sum / n]
	print("[perf] fluidité des zombies (client, %s) : %d images-zombies, %d gels (%.2f %%), %d sauts (%.2f %%), vitesse moyenne %.2f m/s" % [label, _frames, _freezes, r[0] * 100.0, _jumps, r[1] * 100.0, r[2]])
	return r
