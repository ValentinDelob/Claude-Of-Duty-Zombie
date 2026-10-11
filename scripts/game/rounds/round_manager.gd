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
## Serveur : type de la vague spéciale en cours (WaveRules.MEUTE,
## BRANCARDIER ou "") : sorte d'échantillons (LootSystem).
var special_type := ""
## Serveur : type du boss de la vague de boss en cours (WaveRules.CHIRURGIEN
## ou "") : sorte d'échantillons (LootSystem).
var boss_type := ""


## Vagues spéciales : meute de chiens (chemin réseau : /root/Game/Rounds/Dogs)
## et Brancardier (/root/Game/Rounds/Brancard). Le type de chaque vague
## spéciale vient de la rotation de la carte (WaveRules.special_type_at) ;
## chaque gestionnaire tient sa prochaine manche (next_dog_round, next_round).
var dogs: DogRound
var brancard: BrancardRound
## Vagues de boss : le Chirurgien (/root/Game/Rounds/Surgeon ; rotation des
## types de boss, WaveRules.boss_type_at).
var surgeon: SurgeonRound


func _ready() -> void:
	game = get_parent()
	_rng.randomize()
	dogs = DogRound.new()
	dogs.name = "Dogs"
	add_child(dogs)
	brancard = BrancardRound.new()
	brancard.name = "Brancard"
	add_child(brancard)
	surgeon = SurgeonRound.new()
	surgeon.name = "Surgeon"
	add_child(surgeon)


## Serveur : lance la première manche après un court délai.
func start_game() -> void:
	if not multiplayer.is_server():
		return
	_started = true
	phase = Phase.WAITING
	# Défi hebdomadaire « en retard » (§4.18) : première manche plus haute ;
	# les vagues spéciales gardent leur rythme et leur rotation (prochaine de
	# chaque type après le départ).
	var first := game.challenge.start_round() if game and game.challenge else 1
	if first > 1:
		round_n = first - 1
	dogs.srv_plan(round_n)
	brancard.srv_plan(round_n)
	surgeon.srv_plan(round_n)
	_timer = RoundRules.FIRST_ROUND_DELAY


func player_count() -> int:
	return maxi(game.players.size(), 1)


func remaining() -> int:
	return to_spawn + game.zombies.alive_count() + (maxi(dogs.total - dogs.spawned, 0) if dogs.active else 0) \
		+ (maxi(brancard.total - brancard.spawned, 0) if brancard.active else 0) \
		+ (maxi(surgeon.total - surgeon.spawned, 0) if surgeon.active else 0)


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
			if brancard.active:
				# Vague du Brancardier : ses Brancardiers, et l'escorte (zombies
				# ordinaires, to_spawn) après l'annonce.
				brancard.srv_tick(delta)
				if brancard.escort_ready():
					_spawn_tick(delta)
			elif surgeon.active:
				# Vague du Chirurgien : le boss, et l'escorte après l'annonce
				# (les patients de ses opérations apparaissent seuls).
				surgeon.srv_tick(delta)
				if surgeon.escort_ready():
					_spawn_tick(delta)
			else:
				_spawn_tick(delta)
			_recycle_accum += delta
			if _recycle_accum >= 1.0:
				to_spawn += game.spawner.recycle(_recycle_accum)
				_recycle_accum = 0.0
			if brancard.active and not brancard.srv_finished():
				return
			if surgeon.active and not surgeon.srv_finished():
				return
			if to_spawn <= 0 and game.zombies.alive_count() == 0:
				if brancard.active:
					brancard.srv_end(round_n)
				if surgeon.active:
					surgeon.srv_end(round_n)
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
	if brancard.active:
		brancard.srv_end(n - 1)
	if surgeon.active:
		surgeon.srv_end(n - 1)
	wave = ""
	special_type = ""
	boss_type = ""
	# Vague de boss du schéma, ou manche du Chirurgien forcée (tests).
	var boss_wave := WaveRules.wave_kind(_waves(), n, _has_boss()) == WaveRules.BOSS or surgeon.is_surgeon_round(n)
	if boss_wave:
		# Vague de boss (vaincue, elle ouvre la porte d'évacuation, §4.5).
		wave = WaveRules.BOSS
		boss_type = WaveRules.CHIRURGIEN if surgeon.is_surgeon_round(n) else WaveRules.boss_type_at(_waves(), n)
	if surgeon.is_surgeon_round(n):
		# Vague du Chirurgien : le boss (SurgeonRound) et son escorte de
		# zombies ordinaires de la manche.
		to_spawn = SurgeonRules.escorts(player_count())
		surgeon.srv_begin(n)
		total = to_spawn + surgeon.total
	elif boss_wave:
		# Boss coupé (autotests, sauf SurgeonRound.debug_force_next) : manche
		# normale, comptée vague de boss.
		print("[Rounds] manche %d : vague de boss « %s » sans boss (coupé), manche normale" % [n, boss_type])
		boss_type = ""
	if not boss_wave and dogs.is_dog_round(n):
		wave = WaveRules.SPECIAL
		special_type = WaveRules.MEUTE
		to_spawn = 0
		dogs.srv_begin(n)
		total = dogs.total
	elif not boss_wave and brancard.is_brancard_round(n):
		# Vague du Brancardier : Brancardiers (BrancardRound) et escorte de
		# zombies ordinaires de la manche.
		wave = WaveRules.SPECIAL
		special_type = WaveRules.BRANCARDIER
		to_spawn = BrancardRules.escorts(player_count())
		brancard.srv_begin(n)
		total = to_spawn + brancard.total
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


## La carte a-t-elle un boss (vagues de boss prévues, WaveRules.has_boss) ?
func _has_boss() -> bool:
	return WaveRules.has_boss(_waves())


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
		if not dogs.cl_active and not brancard.cl_active and not surgeon.cl_active:  # vague spéciale ou de boss : son d'annonce propre
			Audio.play_2d("round_start", -2.0, 0.0)
		round_started.emit(n)
	else:
		if GameState.state == GameState.State.PLAYING:
			GameState.set_state(GameState.State.ROUND_END)
		game.hud.round_changed(n, false)
		if not dogs.cl_active and not brancard.cl_active and not surgeon.cl_active:
			Audio.play_2d("round_end", -2.0, 0.0)
		round_ended.emit(n)
