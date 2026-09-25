class_name RoundManager
extends Node
## Progression des manches (chemin réseau : /root/Game/Rounds).
##
## Le serveur décide de tout : début et fin de manche, nombre de zombies,
## cadence d'apparition, santé et vitesse. Les clients reçoivent uniquement les
## transitions (_cl_round) et le nombre de zombies restants (HUD).

enum Phase { WAITING, ACTIVE, INTERMISSION }

signal round_started(round_n: int)
signal round_ended(round_n: int)

var game: Game
var round_n := 0
var phase: Phase = Phase.WAITING
## Tests : fige la progression (pas d'apparition, pas de fin de manche).
var paused := false
## Serveur : zombies restant à faire apparaître dans la manche.
var to_spawn := 0
var total := 0
var _timer := 0.0
var _spawn_accum := 0.0
var _rng := RandomNumberGenerator.new()
var _started := false


func _ready() -> void:
	game = get_parent()
	_rng.randomize()


## Serveur : lance la première manche après un court délai.
func start_game() -> void:
	if not multiplayer.is_server():
		return
	_started = true
	phase = Phase.WAITING
	_timer = RoundRules.FIRST_ROUND_DELAY


func player_count() -> int:
	return maxi(game.players.size(), 1)


func remaining() -> int:
	return to_spawn + game.zombies.alive_count()


func _process(delta: float) -> void:
	if not multiplayer.is_server() or not _started or paused:
		return
	if GameState.state == GameState.State.GAME_OVER:
		return
	match phase:
		Phase.WAITING, Phase.INTERMISSION:
			_timer -= delta
			if _timer <= 0.0:
				_begin_round(round_n + 1)
		Phase.ACTIVE:
			_spawn_tick(delta)
			if to_spawn <= 0 and game.zombies.alive_count() == 0:
				_end_round()


func _spawn_tick(delta: float) -> void:
	if to_spawn <= 0:
		return
	_spawn_accum += delta
	if _spawn_accum < RoundRules.spawn_interval(round_n, player_count()):
		return
	if game.zombies.alive_count() >= RoundRules.max_alive(round_n, player_count()):
		return
	var pos: Variant = game.spawner.pick_spawn_point()
	if pos == null:
		return
	_spawn_accum = 0.0
	to_spawn -= 1
	game.zombies.spawn(pos, RoundRules.pick_speed(round_n, _rng), RoundRules.zombie_health(round_n))


func _begin_round(n: int) -> void:
	round_n = n
	total = RoundRules.zombie_count(n, player_count())
	to_spawn = total
	_spawn_accum = 0.0
	phase = Phase.ACTIVE
	print("[Rounds] manche %d : %d zombies, %d PV" % [n, total, RoundRules.zombie_health(n)])
	game.respawn_dead_players()
	_cl_round.rpc(n, Phase.ACTIVE)


func _end_round() -> void:
	phase = Phase.INTERMISSION
	_timer = RoundRules.INTERMISSION
	print("[Rounds] fin de la manche %d" % round_n)
	_cl_round.rpc(round_n, Phase.INTERMISSION)


## Tests : force le passage à une manche donnée.
func debug_jump_to(n: int) -> void:
	for zid in game.zombies.zombies.keys():
		game.zombies.despawn(zid)
	_begin_round(n)


@rpc("authority", "call_local", "reliable")
func _cl_round(n: int, new_phase: int) -> void:
	round_n = n
	phase = new_phase as Phase
	if phase == Phase.ACTIVE:
		if GameState.state == GameState.State.ROUND_END:
			GameState.set_state(GameState.State.PLAYING)
		game.hud.round_changed(n, true)
		Audio.play_2d("round_start", -2.0, 0.0)
		round_started.emit(n)
	else:
		if GameState.state == GameState.State.PLAYING:
			GameState.set_state(GameState.State.ROUND_END)
		game.hud.round_changed(n, false)
		Audio.play_2d("round_end", -2.0, 0.0)
		round_ended.emit(n)
