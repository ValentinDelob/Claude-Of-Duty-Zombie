class_name DogRound
extends Node
## Manches de chiens de l'enfer (chemin réseau : /root/Game/Rounds/Dogs).
##
## Serveur : planifie les manches de chiens (5 à 7, puis +4 ou +5), fait
## apparaître les chiens un par un près des joueurs (2 vivants par joueur),
## leur attribue une proie, applique l'explosion de flammes à leur mort et
## fait tomber des MUNITIONS MAX sur le dernier chien tué.
## Toutes les machines : ambiance de la manche (brouillard, musique, annonce,
## compteur de manche qui clignote).

signal dog_round_started(round_n: int)
signal dog_round_cleared(round_n: int)

var game: Game
var rounds: RoundManager

## Serveur : planification.
## Coupé pendant les autotests (manches déterministes) ; un scénario peut le
## réactiver ou forcer la manche suivante (debug_force_next).
var enabled := not Autotest.active
var next_dog_round := 0
## Manches de chiens déjà terminées (level.dog_round_count - 1).
var dog_rounds_done := 0
## Serveur : manche de chiens en cours.
var active := false
var round_index := 0
var total := 0
var spawned := 0
var killed := 0
var last_dog_pos := Vector3.INF
var _start_delay := 0.0
var _wait := 0.0
var _alive: Dictionary = {}  # zid -> true
var _recycle_accum := 0.0
var _far_time: Dictionary = {}  # zid -> s
var _last_spawn_cell := Vector2i(-99, -99)
var _end_sent := false
var _cells: Array[Vector2i] = []
var _rng := RandomNumberGenerator.new()

## Toutes les machines : ambiance de manche de chiens active.
var cl_active := false
var _fog_k := 0.0
var _fog_tween: Tween
var _prev_music := ""

static var _flames: ParticlePool


## Pool de particules des flammes des chiens (null hors partie).
static func flame_pool() -> ParticlePool:
	return _flames if is_instance_valid(_flames) else null


func _ready() -> void:
	rounds = get_parent()
	game = rounds.get_parent()
	_rng.randomize()
	next_dog_round = DogRules.first_dog_round(_rng)
	var pool := ParticlePool.new().setup(200, Fx._particle_mat(true), 0.08)
	pool.name = "DogFlames"
	pool.gravity = -2.5
	pool.drag = 2.5
	pool.grow = -0.6
	add_child(pool)
	_flames = pool
	if multiplayer.is_server():
		# Les @onready de Game ne sont pas encore assignés (enfant prêt avant).
		var zm: ZombieManager = game.get_node("Zombies")
		zm.zombie_killed.connect(_on_killed)
		zm.zombie_removed.connect(_on_removed)


func is_dog_round(n: int) -> bool:
	return enabled and n == next_dog_round


func remaining() -> int:
	return maxi(total - spawned, 0) + _alive.size() if active else 0


func alive_dogs() -> int:
	return _alive.size()


## Tests : la prochaine manche sera une manche de chiens.
func debug_force_next(n: int) -> void:
	enabled = true
	next_dog_round = n


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

## Début d'une manche de chiens (appelé par RoundManager).
func srv_begin(n: int) -> void:
	active = true
	round_index = dog_rounds_done + 1
	total = DogRules.dog_count(rounds.player_count(), round_index)
	spawned = 0
	killed = 0
	last_dog_pos = Vector3.INF
	_start_delay = DogRules.START_DELAY
	_wait = 0.0
	_alive.clear()
	_far_time.clear()
	_end_sent = false
	print("[Dogs] manche %d : manche de chiens n° %d, %d chiens, %d PV" % [n, round_index, total, DogRules.dog_health(round_index)])
	_cl_dog_round.rpc(true)
	dog_round_started.emit(n)


## Manche de chiens terminée (tous les chiens apparus et tués) ?
func srv_finished() -> bool:
	return active and spawned >= total and _alive.is_empty()


## Clôture côté serveur (appelé par RoundManager avant la fin de manche).
func srv_end(n: int) -> void:
	active = false
	if not _end_sent:
		# Manche interrompue (tests) : l'ambiance s'arrête aussitôt.
		_cl_dog_round.rpc(false)
	dog_rounds_done += 1
	next_dog_round = DogRules.next_dog_round(n, _rng)
	print("[Dogs] fin de la manche de chiens ; prochaine : manche %d" % next_dog_round)
	dog_round_cleared.emit(n)


func srv_tick(delta: float) -> void:
	if not active:
		return
	_recycle_accum += delta
	if _recycle_accum >= 1.0:
		_recycle(_recycle_accum)
		_recycle_accum = 0.0
	if _start_delay > 0.0:
		_start_delay -= delta
		return
	if spawned >= total:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var valid := _valid_players()
	if _alive.size() >= DogRules.max_alive(valid.size()):
		return
	if valid.is_empty():
		return
	if _spawn_dog(valid):
		spawned += 1
		_wait = DogRules.spawn_wait(round_index, spawned, total)


func _valid_players() -> Array:
	var out := []
	for p: Player in game.players.values():
		var pd := game.session.get_data(p.peer_id)
		if pd and pd.life == PlayerData.Life.ALIVE and not p.untargetable:
			out.append(p)
	return out


## Proie la moins chassée, point d'apparition près d'elle, puis apparition.
func _spawn_dog(valid: Array) -> bool:
	var hunted := []
	for p: Player in valid:
		var n := 0
		for zid in _alive:
			var d := game.zombies.get_zombie(zid) as Hellhound
			if d and d.favorite_enemy == p:
				n += 1
		hunted.append(n)
	var fav: Player = valid[DogRules.favorite_index(hunted)]
	var pos: Variant = pick_spawn_point(fav.global_position)
	if pos == null:
		return false
	var zid := game.zombies.spawn(pos, 3, DogRules.dog_health(round_index), ZombieManager.KIND_DOG)
	var dog := game.zombies.get_zombie(zid) as Hellhound
	if dog == null:
		return false
	dog.favorite_enemy = fav
	dog.target = fav
	_alive[zid] = true
	return true


## Cellules d'apparition possibles : praticables et dégagées tout autour.
func _candidate_cells() -> Array[Vector2i]:
	if _cells.is_empty() and game.nav:
		var md := game.map_data
		for y in md.height:
			for x in md.width:
				var c := Vector2i(x, y)
				if md.zone_at(c) == "" or not game.nav.is_walkable(c):
					continue
				var clear := true
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if not game.nav.is_walkable(c + Vector2i(dx, dy)):
							clear = false
				if clear:
					_cells.append(c)
	return _cells


## Point d'apparition d'un chien (BO1 : 400 à 1000 unités du joueur visé, dans
## une zone ouverte, jamais deux fois de suite au même endroit).
func pick_spawn_point(near: Vector3) -> Variant:
	var cells := _candidate_cells().duplicate()
	if cells.is_empty():
		return null
	var zones: Dictionary = game.spawner.active_zones if game.spawner else {}
	var fallback := Vector2i(-1, -1)
	var fallback_err := INF
	var tries := 0
	# Mélange partiel (quelques centaines de cellules suffisent).
	for i in mini(cells.size(), 400):
		var j := _rng.randi_range(i, cells.size() - 1)
		var c: Vector2i = cells[j]
		cells[j] = cells[i]
		cells[i] = c
		if not zones.is_empty() and not zones.has(game.map_data.zone_at(c)):
			continue
		if c == _last_spawn_cell or not game.nav.is_walkable(c):
			continue
		var pos := MapData.cell_to_world(c)
		var d := Vector2(pos.x - near.x, pos.z - near.z).length()
		if d >= DogRules.SPAWN_MIN_DIST and d <= DogRules.SPAWN_MAX_DIST:
			tries += 1
			if not game.nav.find_path(pos, near).is_empty():
				_last_spawn_cell = c
				return pos
			if tries > 8:
				break
		elif d >= 4.0:
			var err := absf(d - clampf(d, DogRules.SPAWN_MIN_DIST, DogRules.SPAWN_MAX_DIST))
			if err < fallback_err:
				fallback_err = err
				fallback = c
	if fallback.x < 0:
		return null
	_last_spawn_cell = fallback
	return MapData.cell_to_world(fallback)


## Chien coincé ou égaré loin de tout joueur : retiré et refait apparaître.
func _recycle(delta: float) -> void:
	var players := _valid_players()
	if players.is_empty():
		return
	for zid in _alive.keys():
		var d := game.zombies.get_zombie(zid) as Hellhound
		if d == null or d.state == Zombie.State.EMERGE:
			continue
		var nearest := INF
		for p: Player in players:
			nearest = minf(nearest, p.global_position.distance_to(d.global_position))
		if nearest > 35.0 or (nearest > 8.0 and d.stuck_time() > 5.0):
			_far_time[zid] = _far_time.get(zid, 0.0) + delta
		else:
			_far_time.erase(zid)
		if _far_time.get(zid, 0.0) >= 8.0:
			_far_time.erase(zid)
			_alive.erase(zid)
			spawned -= 1
			game.zombies.despawn(zid)


func _on_killed(zid: int) -> void:
	var dog := game.zombies.get_zombie(zid) as Hellhound
	if dog == null:
		return
	var pos := dog.global_position
	# Explosion de flammes : brûle les joueurs tout proches.
	if dog._revealed:
		for p: Player in game.players.values():
			if p.global_position.distance_to(pos + Vector3.UP * 0.4) <= DogRules.EXPLODE_RADIUS:
				game.combat.damage_player(p.peer_id, DogRules.EXPLODE_DAMAGE, pos + Vector3.UP * 0.5)
	if not _alive.has(zid):
		return
	_alive.erase(zid)
	_far_time.erase(zid)
	killed += 1
	if active and spawned >= total and _alive.is_empty():
		# Le dernier chien fait toujours tomber des munitions max.
		last_dog_pos = pos
		if game.powerups:
			game.powerups.spawn_drop(PowerupRules.MAX_AMMO, pos)
		_end_sent = true
		_cl_dog_end.rpc()


func _on_removed(zid: int) -> void:
	_alive.erase(zid)
	_far_time.erase(zid)


# --------------------------------------------------------------------------
# Toutes les machines : ambiance
# --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_dog_round(on: bool) -> void:
	cl_active = on
	if on:
		Audio.play_2d("dog_round_start", 0.0, 0.0)
		_prev_music = Audio._music_name
		Audio.play_music("dog_round_music", -3.0, 2.5)
	else:
		Audio.play_music(_prev_music if _prev_music != "" else "ambience_bunker", -6.0, 3.0)
	if game.hud:
		game.hud.set_special_round(on)
	_tween_fog(1.0 if on else 0.0, 3.0 if on else 4.0)


## Dernier chien abattu : fin de l'ambiance après un court délai (BO1 : wait 2).
@rpc("authority", "call_local", "reliable")
func _cl_dog_end() -> void:
	Audio.play_2d("dog_round_end", 0.0, 0.0)
	get_tree().create_timer(DogRules.FOG_CLEAR_DELAY).timeout.connect(func():
		if cl_active:
			_cl_dog_round(false))


func _tween_fog(to: float, time: float) -> void:
	if _fog_tween:
		_fog_tween.kill()
	_fog_tween = create_tween()
	_fog_tween.tween_method(_set_fog, _fog_k, to, time)


func _set_fog(k: float) -> void:
	_fog_k = k
	var we := game.world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		WorldLook.apply_dog_round_look(we.environment, k)


func fog_amount() -> float:
	return _fog_k
