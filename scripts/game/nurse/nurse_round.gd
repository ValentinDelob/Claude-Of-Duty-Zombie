class_name NurseRound
extends Node
## Vagues spéciales « Infirmière hurlante » (chemin réseau :
## /root/Game/Rounds/Nurse).
##
## Serveur : manches de l'Infirmière = vagues spéciales du schéma de la carte
## de type « infirmiere » (WaveRules.special_type_at : rotation des types
## autorisés, vagues de boss exclues ; par défaut manches 20, 40, 65...).
## Fait apparaître les
## Infirmières une par une loin des joueurs, hors de leur vue de préférence
## (DogRound.pick_spawn_point, distances NurseRules), MAX_ALIVE à la fois ;
## l'escorte (zombies ordinaires, que son cri ameute) passe par le
## RoundManager (to_spawn). Transmet aux Infirmières les touches reçues
## (Combat.zombie_damaged : gorge touchée pendant la préparation = cri
## étranglé). Toutes les machines : mise en scène (bandeau « L'INFIRMIÈRE
## FAIT SA RONDE », alerte, musique de vague spéciale, compteur qui clignote,
## hurlements lointains), fin de l'ambiance à la dernière tuée.

signal nurse_round_started(round_n: int)
signal nurse_round_cleared(round_n: int)

## Hurlements lointains de l'annonce : instants (s), distance (m).
const ANNOUNCE_TIMES := [1.3, 3.4]
const ANNOUNCE_SOUNDS := ["nurse_far", "nurse_far"]
const ANNOUNCE_DIST := 20.0

var game: Game
var rounds: RoundManager

## Serveur : coupé pendant les autotests (manches déterministes), comme la meute.
var enabled := not Autotest.active
## Prochaine manche de l'Infirmière (schéma de la carte, srv_plan).
var next_round := WaveRules.next_special_of(WaveRules.DEFAULT, WaveRules.INFIRMIERE, 0, WaveRules.has_boss(WaveRules.DEFAULT))
## Vagues de l'Infirmière déjà terminées dans la partie (rang - 1).
var rounds_done := 0
var active := false
var rank := 0
var total := 0
var spawned := 0
var killed := 0
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
		# Game.combat (@onready) n'est pas encore posé : le nœud directement.
		var combat := game.get_node_or_null("Combat") as Combat
		if combat:
			combat.zombie_damaged.connect(_on_damaged)


func is_nurse_round(n: int) -> bool:
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
	next_round = WaveRules.next_special_of(_waves(), WaveRules.INFIRMIERE, after, _has_boss())


## Tests : la manche `n` sera une manche de l'Infirmière.
func debug_force_next(n: int) -> void:
	enabled = true
	next_round = n


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

func srv_begin(n: int) -> void:
	active = true
	rank = rounds_done + 1
	total = NurseRules.count(rounds.player_count())
	spawned = 0
	killed = 0
	_start_delay = NurseRules.START_DELAY
	_wait = 0.0
	_alive.clear()
	_far_time.clear()
	_end_sent = false
	print("[Nurse] manche %d : vague de l'Infirmière n° %d, %d Infirmière(s) de %d PV, %d zombies d'escorte" % [
		n, rank, total, NurseRules.health(n, rank), NurseRules.escorts(rounds.player_count())])
	_cl_round.rpc(true, total)
	nurse_round_started.emit(n)


## Toutes les Infirmières apparues et tuées ?
func srv_finished() -> bool:
	return active and spawned >= total and _alive.is_empty()


func srv_end(n: int) -> void:
	active = false
	if not _end_sent:
		_cl_round.rpc(false, 0)
	rounds_done += 1
	next_round = WaveRules.next_special_of(_waves(), WaveRules.INFIRMIERE, n, _has_boss())
	print("[Nurse] fin de la vague de l'Infirmière ; prochaine : manche %d" % next_round)
	nurse_round_cleared.emit(n)


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
	if _alive.size() >= NurseRules.MAX_ALIVE:
		return
	var valid := _valid_players()
	if valid.is_empty():
		return
	if _spawn_one(valid):
		spawned += 1
		_wait = NurseRules.SPAWN_WAIT
	else:
		_wait = 0.25


## L'escorte peut-elle apparaître (annonce terminée) ?
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
	var fav: Player = valid[spawned % valid.size()]
	var pos: Variant = rounds.dogs.pick_spawn_point(fav.global_position, NurseRules.SPAWN_MIN_DIST, NurseRules.SPAWN_MAX_DIST)
	if pos == null:
		return false
	var hp := NurseRules.health(rounds.round_n, rank)
	var zid := game.zombies.spawn(pos, 0, hp, ZombieManager.KIND_NURSE)
	var n := game.zombies.get_zombie(zid) as Nurse
	if n == null:
		return false
	n.target = fav
	_alive[zid] = true
	return true


## Spawn direct (tests) : une Infirmière en `pos`, PV de la vague en cours.
func debug_spawn(pos: Vector3, hp := -1) -> Nurse:
	var zid := game.zombies.spawn(pos, 0, hp if hp > 0 else NurseRules.health(maxi(rounds.round_n, 1), maxi(rank, 1)), ZombieManager.KIND_NURSE)
	return game.zombies.get_zombie(zid) as Nurse


## Infirmière égarée loin de tout joueur, ou coincée : retirée et refaite.
func _recycle(delta: float) -> void:
	var players := _valid_players()
	if players.is_empty():
		return
	for zid in _alive.keys():
		var n := game.zombies.get_zombie(zid) as Nurse
		if n == null or n.state == Zombie.State.EMERGE:
			continue
		var nearest := INF
		for p: Player in players:
			nearest = minf(nearest, p.global_position.distance_to(n.global_position))
		if nearest > 40.0 or (nearest > NurseRules.KEEP_MAX + 4.0 and n.stuck_time() > 8.0):
			_far_time[zid] = _far_time.get(zid, 0.0) + delta
		else:
			_far_time.erase(zid)
		if _far_time.get(zid, 0.0) >= 10.0:
			_far_time.erase(zid)
			_alive.erase(zid)
			spawned -= 1
			game.zombies.despawn(zid)


## Touche validée par le serveur : l'Infirmière touchée à la gorge ou à la
## tête pendant la préparation de son cri s'étrangle.
func _on_damaged(_pid: int, zid: int, _dmg: int, killed_now: bool, headshot: bool, _kind: int) -> void:
	if killed_now or not headshot:
		return
	var n := game.zombies.get_zombie(zid) as Nurse
	if n:
		n.srv_on_damaged(headshot)


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
		return Lang.t("LES INFIRMIÈRES FONT LEUR RONDE", "THE NURSES ARE DOING THEIR ROUNDS")
	return Lang.t("L'INFIRMIÈRE FAIT SA RONDE", "THE NURSE IS DOING HER ROUNDS")


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
			get_tree().create_timer(ANNOUNCE_TIMES[i]).timeout.connect(_announce.bind(gen, dir + i * 2.1))
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
	Audio.play_3d(ANNOUNCE_SOUNDS[cl_announces % ANNOUNCE_SOUNDS.size()], at, 4.0, 0.05, 4, 0.95 + 0.08 * cl_announces)
	cl_announces += 1


@rpc("authority", "call_local", "reliable")
func _cl_end() -> void:
	Audio.play_2d("special_wave_end", 0.0, 0.0)
	get_tree().create_timer(NurseRules.END_DELAY).timeout.connect(func():
		if cl_active:
			_cl_round(false, 0))
