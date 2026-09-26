class_name PowerupSystem
extends Node3D
## Bonus façon Black Ops 1 (chemin réseau : /root/Game/Powerups).
##
## Serveur : décide des apparitions (seuil de points d'équipe x1,14, tirage
## ~3 % par kill, 4 par manche au plus, zone jouable), de l'ordre (sac mélangé),
## du ramassage (distance réelle des joueurs) et des effets.
## Clients : affichent les bonus au sol, les annonces et les minuteurs.

signal carpenter_used
signal powerup_grabbed(type: String, pid: int)
## Toutes les machines : un bonus temporisé commence (on) ou se termine.
signal effect_changed(type: String, on: bool)

var game: Game
## Toutes les machines : bonus temporisés actifs, type -> secondes restantes.
var timers: Dictionary = {}
## Toutes les machines : bonus au sol, id -> PowerupDrop.
var nodes: Dictionary = {}

## Serveur.
var tracker := PowerupRules.DropTracker.new()
var bag := PowerupRules.Bag.new()
var _rng := RandomNumberGenerator.new()
var _drops: Dictionary = {}  # id -> {type, pos, age}
var _next_id := 1
## Tests : désactive les apparitions automatiques.
var debug_no_auto_drops := false
## Tirage aléatoire par kill (~3 %). Coupé pendant les autotests pour que les
## scénarios restent déterministes (le seuil de points, lui, reste actif).
var random_drops := not Autotest.active
var _fire_sale_music: AudioStreamPlayer3D


func _ready() -> void:
	game = get_parent()
	_rng.randomize()
	if multiplayer.is_server():
		game.combat.zombie_damaged.connect(_on_zombie_damaged)
		game.rounds.round_started.connect(func(_n: int): tracker.new_round())


func is_active(type: String) -> bool:
	return timers.get(type, 0.0) > 0.0


## Mort instantanée active ? (lu par Combat, serveur).
func insta_kill() -> bool:
	return is_active(PowerupRules.INSTA_KILL)


# --------------------------------------------------------------------------
# Serveur : apparitions
# --------------------------------------------------------------------------

func _on_zombie_damaged(pid: int, zid: int, _dmg: int, killed: bool, _headshot: bool, kind: Combat.HitKind) -> void:
	# Seul un kill de joueur (ni piège, ni nuke : pid 0) peut faire tomber un
	# bonus. Le seuil est évalué APRÈS le tirage : c'est le kill suivant le
	# franchissement qui fait tomber le bonus, comme dans BO1.
	if killed and pid > 0 and kind != Combat.HitKind.TRAP and not debug_no_auto_drops:
		var z: Zombie = game.zombies.get_zombie(zid)
		# Les chiens de l'enfer ne font rien tomber (sauf le dernier : DogRound).
		if z and not z is Hellhound:
			var pos := z.global_position
			var roll := _rng.randi_range(0, 99) if random_drops else 99
			if tracker.try_drop(roll, in_playable_area(pos)):
				var type := bag.next_valid(is_valid)
				if type != "":
					spawn_drop(type, pos)
	tracker.on_team_total(game.points.team_earned)


## Zone ouverte par les joueurs (les zombies y apparaissent).
func in_playable_area(pos: Vector3) -> bool:
	if game.spawner == null:
		return true
	var zone := game.map_data.zone_at(MapData.world_to_cell(pos))
	return game.spawner.active_zones.has(zone)


## Bonus autorisé à cet instant (get_valid_powerup de BO1).
func is_valid(type: String) -> bool:
	match type:
		PowerupRules.FIRE_SALE:
			var box := _box()
			return box != null and box.moves >= 1 and box.state != MysteryBox.State.MOVING
		PowerupRules.CARPENTER:
			if game.has_method("barricades_need_repair"):
				return game.call("barricades_need_repair")
	return true


func _box() -> MysteryBox:
	return game.interact.get_obj("box") as MysteryBox


## Serveur : fait apparaître un bonus au sol.
func spawn_drop(type: String, pos: Vector3) -> int:
	if not multiplayer.is_server() or not type in PowerupRules.ALL:
		return -1
	var id := _next_id
	_next_id += 1
	pos.y = maxf(pos.y, 0.0)
	_drops[id] = {"type": type, "pos": pos, "age": 0.0}
	print("[Powerups] %s apparaît en %s" % [type, pos])
	_cl_spawn.rpc(id, type, pos, 0.0)
	return id


func drop_count() -> int:
	return _drops.size()


func _process(delta: float) -> void:
	for type in timers.keys():
		timers[type] = maxf(timers[type] - delta, 0.0)
	if not multiplayer.is_server():
		return
	# Fin des bonus temporisés (le serveur décide).
	for type in timers.keys():
		if timers[type] <= 0.0:
			_cl_timer.rpc(type, 0.0)
	var life := PowerupRules.lifetime()
	for id in _drops.keys():
		var d: Dictionary = _drops[id]
		d.age += delta
		if d.age >= life:
			_drops.erase(id)
			_cl_remove.rpc(id)
			continue
		var pid := _player_on(d.pos)
		if pid > 0:
			grab(id, pid)


## Premier joueur debout sur le bonus (position connue du serveur).
func _player_on(pos: Vector3) -> int:
	for pid in game.players:
		var p: Player = game.players[pid]
		var pd := game.session.get_data(pid)
		if pd == null or pd.life != PlayerData.Life.ALIVE:
			continue
		var d := Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length()
		if d <= PowerupRules.PICKUP_RADIUS and absf(p.global_position.y - pos.y) < 2.0:
			return pid
	return 0


## Serveur : `pid` ramasse le bonus `id`.
func grab(id: int, pid: int) -> void:
	if not multiplayer.is_server() or not _drops.has(id):
		return
	var d: Dictionary = _drops[id]
	_drops.erase(id)
	print("[Powerups] %s ramassé par %d" % [d.type, pid])
	_cl_grab.rpc(id, d.type, pid, d.pos)
	apply(d.type, pid, d.pos)
	powerup_grabbed.emit(d.type, pid)


# --------------------------------------------------------------------------
# Serveur : effets
# --------------------------------------------------------------------------

func apply(type: String, _pid: int, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	match type:
		PowerupRules.MAX_AMMO:
			_max_ammo()
		PowerupRules.NUKE:
			_nuke(pos)
		PowerupRules.CARPENTER:
			_carpenter()
		PowerupRules.INSTA_KILL, PowerupRules.DOUBLE_POINTS, PowerupRules.FIRE_SALE:
			# Ramasser à nouveau remet le minuteur à 30 s.
			_cl_timer.rpc(type, PowerupRules.DURATION)


## Réserve pleine pour toutes les armes de tous les joueurs (y compris celles
## mises de côté par un joueur à terre).
func _max_ammo() -> void:
	# Grenades à 4 et SINGE-TAMBOUR à 3 (BO1).
	if game.throwables:
		game.throwables.srv_refill_all()
	for pid in game.session.data:
		var pd: PlayerData = game.session.data[pid]
		for list in [pd.weapons, pd.saved_weapons]:
			for w in list:
				if w is Dictionary and WeaponDB.exists(w.get("id", "")):
					w.reserve = maxi(int(w.reserve), int(WeaponDB.stats(w.id, w.get("pap", false)).reserve))
		game.session.sync_inventory(pid)


## Tue tous les zombies vivants (du plus proche au plus lointain, échelonné),
## sans points ni bonus ; +400 points à chaque joueur.
func _nuke(pos: Vector3) -> void:
	var list: Array = game.zombies.alive.duplicate()
	list.sort_custom(func(a: Zombie, b: Zombie): return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
	var n := list.size()
	for i in n:
		var z: Zombie = list[i]
		var delay := PowerupRules.NUKE_SPREAD * float(i) / maxf(n, 1) + _rng.randf_range(0.05, 0.2)
		get_tree().create_timer(delay).timeout.connect(_nuke_kill.bind(z.id, pos))
	for pid in game.session.data:
		game.points.award(pid, PowerupRules.NUKE_POINTS)
	tracker.on_team_total(game.points.team_earned)
	_cl_nuke_fx.rpc(pos)
	print("[Powerups] nuke : %d zombies" % n)


func _nuke_kill(zid: int, pos: Vector3) -> void:
	var z: Zombie = game.zombies.get_zombie(zid)
	if z == null or not z.is_alive():
		return
	var dir := z.global_position - pos
	dir.y = 0.0
	# pid 0 : aucun point, aucun bonus.
	game.combat.damage_zombie(zid, z.health + 1, 0, false, dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD, Combat.HitKind.SPECIAL)


## +200 points à chaque joueur ; répare les barricades si la carte en a.
func _carpenter() -> void:
	if game.has_method("repair_all_barricades"):
		game.call("repair_all_barricades")
	carpenter_used.emit()
	for pid in game.session.data:
		game.points.award(pid, PowerupRules.CARPENTER_POINTS)
	tracker.on_team_total(game.points.team_earned)


# --------------------------------------------------------------------------
# Tests / débogage (serveur)
# --------------------------------------------------------------------------

## Fait tomber un bonus aux pieds (ou devant) d'un joueur.
func debug_drop(type: String, pos: Vector3) -> int:
	return spawn_drop(type, pos)


## Retire tous les bonus au sol et coupe les effets.
func debug_clear() -> void:
	if not multiplayer.is_server():
		return
	for id in _drops.keys():
		_cl_remove.rpc(id)
	_drops.clear()
	for type in timers.keys():
		_cl_timer.rpc(type, 0.0)


## Envoie l'état courant à un joueur (arrivée en cours de partie).
func sync_to(pid: int) -> void:
	if not multiplayer.is_server():
		return
	for id in _drops:
		var d: Dictionary = _drops[id]
		_cl_spawn.rpc_id(pid, id, d.type, d.pos, d.age)
	for type in timers:
		_cl_timer.rpc_id(pid, type, timers[type])


# --------------------------------------------------------------------------
# Toutes les machines
# --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_spawn(id: int, type: String, pos: Vector3, age: float) -> void:
	if nodes.has(id):
		return
	var d := PowerupDrop.new()
	d.setup(id, type, age)
	add_child(d)
	d.global_position = pos
	nodes[id] = d
	if age <= 0.0:
		Audio.play_3d("powerup_spawn", pos + Vector3.UP, 0.0, 0.02)


@rpc("authority", "call_local", "reliable")
func _cl_remove(id: int) -> void:
	var d: PowerupDrop = nodes.get(id)
	nodes.erase(id)
	if d:
		d.queue_free()


@rpc("authority", "call_local", "reliable")
func _cl_grab(id: int, type: String, _pid: int, pos: Vector3) -> void:
	_cl_remove(id)
	Audio.play_3d("powerup_grab", pos + Vector3.UP, 0.0, 0.02)
	# Annonce (voix de l'annonceur dans BO1) entendue par tout le monde.
	Audio.play_2d("announce_" + type, 0.0, 0.0)
	if game.hud and game.hud.powerup_hud:
		game.hud.powerup_hud.announce(type)
	game.fx_root.explosion_light(pos + Vector3.UP * 0.9, Color(0.3, 1.0, 0.35))


@rpc("authority", "call_local", "reliable")
func _cl_timer(type: String, seconds: float) -> void:
	var was := timers.has(type)
	if seconds > 0.0:
		timers[type] = seconds
	else:
		timers.erase(type)
	var on := seconds > 0.0
	if on == was:
		return
	match type:
		PowerupRules.DOUBLE_POINTS:
			game.points.multiplier = 2 if on else 1
		PowerupRules.FIRE_SALE:
			_set_fire_sale(on)
	if not on:
		Audio.play_2d("powerup_end", -4.0, 0.0)
	effect_changed.emit(type, on)


func _set_fire_sale(on: bool) -> void:
	var box := _box()
	if box == null:
		return
	box.fire_sale = on
	if on and _fire_sale_music == null:
		_fire_sale_music = AudioStreamPlayer3D.new()
		_fire_sale_music.bus = "Music"
		_fire_sale_music.stream = Audio.get_stream("fire_sale_loop")
		_fire_sale_music.unit_size = 8.0
		_fire_sale_music.max_distance = 60.0
		box.add_child(_fire_sale_music)
		_fire_sale_music.position = Vector3.UP * 1.2
		if _fire_sale_music.stream:
			_fire_sale_music.play()
	elif not on and _fire_sale_music:
		_fire_sale_music.queue_free()
		_fire_sale_music = null


@rpc("authority", "call_local", "reliable")
func _cl_nuke_fx(pos: Vector3) -> void:
	Audio.play_2d("powerup_nuke", 2.0, 0.0)
	game.fx_root.explosion_light(pos + Vector3.UP, Color(1.0, 0.95, 0.8))
	if game.hud and game.hud.powerup_hud:
		game.hud.powerup_hud.nuke_flash()
