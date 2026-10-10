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
## Serveur : vague spéciale ou de boss vaincue (`wave` : WaveRules.SPECIAL ou
## BOSS), après l'ouverture de la porte d'évacuation (butin : LootSystem).
signal wave_cleared(wave: String, round_n: int)

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
var _recycle_accum := 0.0
## Serveur : type de vague de la manche en cours (WaveRules.SPECIAL, BOSS ou "").
var wave := ""


## Manches de chiens de l'enfer (chemin réseau : /root/Game/Rounds/Dogs).
var dogs: DogRound


func _ready() -> void:
	game = get_parent()
	_rng.randomize()
	dogs = DogRound.new()
	dogs.name = "Dogs"
	add_child(dogs)


## Serveur : lance la première manche après un court délai.
func start_game() -> void:
	if not multiplayer.is_server():
		return
	_started = true
	phase = Phase.WAITING
	dogs.srv_plan()
	_timer = RoundRules.FIRST_ROUND_DELAY


func player_count() -> int:
	return maxi(game.players.size(), 1)


func remaining() -> int:
	return to_spawn + game.zombies.alive_count() + (maxi(dogs.total - dogs.spawned, 0) if dogs.active else 0)


func _process(delta: float) -> void:
	if not multiplayer.is_server() or not _started or paused:
		return
	if GameState.state == GameState.State.GAME_OVER:
		return
	match phase:
		Phase.WAITING, Phase.INTERMISSION:
			# Fenêtre d'évacuation ouverte : la manche suivante attend (EvacDoor).
			if game.evac and game.evac.is_open:
				return
			_timer -= delta
			if _timer <= 0.0:
				_begin_round(round_n + 1)
		Phase.ACTIVE:
			if dogs.active:
				# Manche de chiens : aucun zombie, fin au dernier chien.
				dogs.srv_tick(delta)
				if dogs.srv_finished():
					dogs.srv_end(round_n)
					_end_round()
					_wave_cleared()
				return
			_spawn_tick(delta)
			_recycle_accum += delta
			if _recycle_accum >= 1.0:
				to_spawn += game.spawner.recycle(_recycle_accum)
				_recycle_accum = 0.0
			if to_spawn <= 0 and game.zombies.alive_count() == 0:
				_end_round()
				# Vague de boss vaincue : la porte d'évacuation s'ouvre aussi (§4.5).
				if wave != "":
					_wave_cleared()


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
	game.respawn_dead_players()
	if dogs.active:
		dogs.srv_end(n - 1)
	wave = ""
	var boss_wave := WaveRules.wave_kind(_waves(), n, _has_boss()) == WaveRules.BOSS
	if boss_wave:
		# Vague de boss : aucun boss n'existe encore (MapDef.boss vide partout,
		# une vague de boss sans boss ne fait rien) ; branche prête pour les
		# lots suivants, d'ici là manche normale.
		push_warning("[Rounds] vague de boss « %s » : boss pas encore implémenté" % game.map_def.boss)
		# Vague de boss quand même : vaincue, elle ouvre la porte d'évacuation.
		wave = WaveRules.BOSS
	if not boss_wave and dogs.is_dog_round(n):
		wave = WaveRules.SPECIAL
		to_spawn = 0
		dogs.srv_begin(n)
		total = dogs.total
	else:
		print("[Rounds] manche %d : %d zombies, %d PV" % [n, total, RoundRules.zombie_health(n)])
	_cl_round.rpc(n, Phase.ACTIVE)


func _end_round() -> void:
	phase = Phase.INTERMISSION
	_timer = RoundRules.INTERMISSION
	print("[Rounds] fin de la manche %d" % round_n)
	_cl_round.rpc(round_n, Phase.INTERMISSION)


## Schéma des vagues de la carte (WaveRules).
func _waves() -> Dictionary:
	return game.map_def.waves if game.map_def else WaveRules.DEFAULT


func _has_boss() -> bool:
	return game.map_def != null and game.map_def.boss != ""


## Serveur : vague spéciale ou de boss vaincue : la porte d'évacuation s'ouvre
## (carte sans porte : entracte normal).
func _wave_cleared() -> void:
	print("[Rounds] vague %s vaincue (manche %d)" % [wave, round_n])
	var kind := wave
	wave = ""
	if game.evac:
		game.evac.srv_open()
	# Après srv_open : les morts sont revenus et reçoivent leur butin.
	wave_cleared.emit(kind, round_n)


## Serveur : fenêtre d'évacuation fermée sans évacuation : la manche suivante
## commence dans `delay` secondes.
func srv_resume_after(delay: float) -> void:
	if phase == Phase.INTERMISSION or phase == Phase.WAITING:
		_timer = delay


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
		if not dogs.cl_active:  # manche de chiens : son d'annonce propre
			Audio.play_2d("round_start", -2.0, 0.0)
		round_started.emit(n)
	else:
		if GameState.state == GameState.State.PLAYING:
			GameState.set_state(GameState.State.ROUND_END)
		game.hud.round_changed(n, false)
		if not dogs.cl_active:
			Audio.play_2d("round_end", -2.0, 0.0)
		round_ended.emit(n)
