class_name BrancardRound
extends Node
## Vagues spéciales « Brancardier » (chemin réseau : /root/Game/Rounds/Brancard).
##
## Serveur : manches du Brancardier = vagues spéciales du schéma de la carte
## de type « brancardier » (WaveRules.special_type_at : rotation des types
## autorisés, vagues de boss exclues ; par défaut manches 10, 25, 40...).
## Fait apparaître les
## Brancardiers un par un près des joueurs, hors de leur vue de préférence
## (DogRound.pick_spawn_point, distances BrancardRules), MAX_ALIVE à la fois ;
## l'escorte (zombies ordinaires) passe par le RoundManager (to_spawn).
## Toutes les machines : mise en scène (bandeau « UN BRANCARDIER APPROCHE »,
## alerte, musique de vague spéciale, compteur qui clignote, rugissement
## lointain, grincement de roulettes), fin de l'ambiance au dernier tué.

signal brancard_round_started(round_n: int)
signal brancard_round_cleared(round_n: int)

## Rugissement et roulettes lointains de l'annonce : instants (s), distance (m).
const ANNOUNCE_TIMES := [1.4, 3.2]
const ANNOUNCE_SOUNDS := ["brancard_roar_1", "brancard_wheels"]
const ANNOUNCE_DIST := 18.0

var game: Game
var rounds: RoundManager

## Serveur : coupé pendant les autotests (manches déterministes), comme la meute.
var enabled := not Autotest.active
## Prochaine manche du Brancardier (schéma de la carte, srv_plan).
var next_round := WaveRules.next_special_of(WaveRules.DEFAULT, WaveRules.BRANCARDIER, 0)
## Vagues du Brancardier déjà terminées dans la partie (rang - 1).
var rounds_done := 0
var active := false
var rank := 0
var total := 0
var spawned := 0
var killed := 0
var spawned_hidden := 0
var _start_delay := 0.0
var _wait := 0.0
var _alive: Dictionary = {}  # zid -> true
var _far_time: Dictionary = {}
var _recycle_accum := 0.0
var _end_sent := false
var _rng := RandomNumberGenerator.new()

## Toutes les machines : ambiance active.
var cl_active := false
var cl_announces := 0
var _gen := 0
var _prev_music := ""


func _ready() -> void:
	rounds = get_parent()
	game = rounds.game
	_rng.randomize()
	if multiplayer.is_server():
		var zm: ZombieManager = game.get_node("Zombies")
		zm.zombie_killed.connect(_on_killed)
		zm.zombie_removed.connect(_on_removed)


func is_brancard_round(n: int) -> bool:
	return enabled and n == next_round


func remaining() -> int:
	return maxi(total - spawned, 0) + _alive.size() if active else 0


func alive_count() -> int:
	return _alive.size()


func _waves() -> Dictionary:
	return game.map_def.waves if game and game.map_def else WaveRules.DEFAULT


func _has_boss() -> bool:
	return WaveRules.has_boss(_waves())


func srv_plan(after := 0) -> void:
	next_round = WaveRules.next_special_of(_waves(), WaveRules.BRANCARDIER, after, _has_boss())


## Tests : la manche `n` sera une manche du Brancardier.
func debug_force_next(n: int) -> void:
	enabled = true
	next_round = n


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

func srv_begin(n: int) -> void:
	active = true
	rank = rounds_done + 1
	total = BrancardRules.count(rounds.player_count())
	spawned = 0
	killed = 0
	_start_delay = BrancardRules.START_DELAY
	_wait = 0.0
	_alive.clear()
	_far_time.clear()
	_end_sent = false
	print("[Brancard] manche %d : vague du Brancardier n° %d, %d Brancardier(s) de %d PV, %d zombies d'escorte" % [
		n, rank, total, BrancardRules.health(n, rank), BrancardRules.escorts(rounds.player_count())])
	_cl_round.rpc(true, total)
	brancard_round_started.emit(n)


## Tous les Brancardiers apparus et tués ?
func srv_finished() -> bool:
	return active and spawned >= total and _alive.is_empty()


func srv_end(n: int) -> void:
	active = false
	if not _end_sent:
		_cl_round.rpc(false, 0)
	rounds_done += 1
	next_round = WaveRules.next_special_of(_waves(), WaveRules.BRANCARDIER, n, _has_boss())
	print("[Brancard] fin de la vague du Brancardier ; prochaine : manche %d" % next_round)
	brancard_round_cleared.emit(n)


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
	if _alive.size() >= BrancardRules.MAX_ALIVE:
		return
	var valid := _valid_players()
	if valid.is_empty():
		return
	if _spawn_one(valid):
		spawned += 1
		_wait = BrancardRules.SPAWN_WAIT
	else:
		_wait = 0.25


## Est-ce le moment de laisser l'escorte apparaître (annonce terminée) ?
func escort_ready() -> bool:
	return active and _start_delay <= 0.0


func _valid_players() -> Array:
	var out := []
	for p: Player in game.players.values():
		var pd := game.session.get_data(p.peer_id)
		if pd and pd.life == PlayerData.Life.ALIVE and not p.untargetable:
			out.append(p)
	return out


func _spawn_one(valid: Array) -> bool:
	# Proie : chaque joueur reçoit son Brancardier, à tour de rôle.
	var fav: Player = valid[spawned % valid.size()]
	var pos: Variant = rounds.dogs.pick_spawn_point(fav.global_position, BrancardRules.SPAWN_MIN_DIST, BrancardRules.SPAWN_MAX_DIST)
	if pos == null:
		return false
	var hp := BrancardRules.health(rounds.round_n, rank)
	var zid := game.zombies.spawn(pos, 0, hp, ZombieManager.KIND_BRANCARDIER)
	var b := game.zombies.get_zombie(zid) as Brancardier
	if b == null:
		return false
	b.target = fav
	_alive[zid] = true
	return true


## Spawn direct (tests) : un Brancardier en `pos`, PV de la vague en cours.
func debug_spawn(pos: Vector3, hp := -1) -> Brancardier:
	var zid := game.zombies.spawn(pos, 0, hp if hp > 0 else BrancardRules.health(maxi(rounds.round_n, 1), maxi(rank, 1)), ZombieManager.KIND_BRANCARDIER)
	return game.zombies.get_zombie(zid) as Brancardier


## Brancardier coincé ou égaré loin de tout joueur : retiré et refait apparaître.
func _recycle(delta: float) -> void:
	var players := _valid_players()
	if players.is_empty():
		return
	for zid in _alive.keys():
		var b := game.zombies.get_zombie(zid) as Brancardier
		if b == null or b.state == Zombie.State.EMERGE:
			continue
		var nearest := INF
		for p: Player in players:
			nearest = minf(nearest, p.global_position.distance_to(b.global_position))
		if nearest > 40.0 or (nearest > 8.0 and b.stuck_time() > 6.0):
			_far_time[zid] = _far_time.get(zid, 0.0) + delta
		else:
			_far_time.erase(zid)
		if _far_time.get(zid, 0.0) >= 10.0:
			_far_time.erase(zid)
			_alive.erase(zid)
			spawned -= 1
			game.zombies.despawn(zid)


func _on_killed(zid: int) -> void:
	if not _alive.has(zid):
		return
	_alive.erase(zid)
	_far_time.erase(zid)
	killed += 1
	if active and spawned >= total and _alive.is_empty():
		_end_sent = true
		_cl_end.rpc()


func _on_removed(zid: int) -> void:
	_alive.erase(zid)
	_far_time.erase(zid)


# --------------------------------------------------------------------------
# Toutes les machines : ambiance
# --------------------------------------------------------------------------

## Bandeau de l'annonce (FR / EN), au pluriel en coop.
static func banner_text(count: int) -> String:
	if count > 1:
		return Lang.t("DES BRANCARDIERS APPROCHENT", "STRETCHER-BEARERS ARE COMING")
	return Lang.t("UN BRANCARDIER APPROCHE", "A STRETCHER-BEARER IS COMING")


@rpc("authority", "call_local", "reliable")
func _cl_round(on: bool, count: int) -> void:
	cl_active = on
	_gen += 1
	if on:
		Audio.play_2d("special_wave_start", 0.0, 0.0)
		_prev_music = Audio._music_name
		Audio.play_music("special_wave_music", -3.0, 2.5)
		cl_announces = 0
		var gen := _gen
		var dir := _rng.randf() * TAU
		for i in ANNOUNCE_TIMES.size():
			get_tree().create_timer(ANNOUNCE_TIMES[i]).timeout.connect(_announce.bind(gen, dir + i * 0.4))
	else:
		Audio.play_music(_prev_music if _prev_music != "" else "ambience_bunker", -6.0, 3.0)
	if game.hud:
		game.hud.set_special_round(on)
		if on:
			game.hud.show_banner(banner_text(count), 3.0)


func _announce(gen: int, dir: float) -> void:
	if gen != _gen or not cl_active:
		return
	var ear: Variant = Audio.listener_position()
	if ear == null:
		ear = game.local_player.global_position if game and game.local_player else Vector3.ZERO
	var at: Vector3 = ear + Vector3(sin(dir), 0.0, cos(dir)) * ANNOUNCE_DIST
	Audio.play_3d(ANNOUNCE_SOUNDS[cl_announces % ANNOUNCE_SOUNDS.size()], at, 4.0, 0.05, 4, 0.9)
	cl_announces += 1


@rpc("authority", "call_local", "reliable")
func _cl_end() -> void:
	Audio.play_2d("special_wave_end", 0.0, 0.0)
	get_tree().create_timer(BrancardRules.END_DELAY).timeout.connect(func():
		if cl_active:
			_cl_round(false, 0))
