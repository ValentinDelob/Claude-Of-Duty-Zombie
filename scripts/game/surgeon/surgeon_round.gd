class_name SurgeonRound
extends Node
## Vagues de boss « Le Chirurgien » (chemin réseau : /root/Game/Rounds/Surgeon).
##
## Serveur : manches du Chirurgien = vagues de boss du schéma de la carte de
## type « chirurgien » (WaveRules.boss_type_at : rotation des types de boss
## autorisés ; par défaut manches 15, 30, 45...). Après l'annonce, fait
## apparaître LE Chirurgien près d'un joueur, hors de sa vue de préférence
## (DogRound.pick_spawn_point, distances SurgeonRules) ; l'escorte (zombies
## ordinaires) passe par le RoundManager (to_spawn) ; les patients relevés
## par ses opérations (srv_summon) sont des zombies ordinaires de la manche.
## Diffuse ses PV (jauge du HUD, BossBar). Le Chirurgien égaré loin de tout
## joueur est REPLACÉ près d'eux (il garde ses PV). Scalpels lancés : enfant
## SurgeonScalpels.
## Toutes les machines : mise en scène (bandeau « LE CHIRURGIEN ENTRE AU
## BLOC », alerte, musique de vague, compteur qui clignote, bips de moniteur
## cardiaque et rire lointain), jauge de vie, bandeau de sa mort.

signal surgeon_round_started(round_n: int)
signal surgeon_round_cleared(round_n: int)

## Annonce : bips de moniteur puis rire lointain (instants en s, distance m).
const ANNOUNCE_TIMES := [0.8, 3.4]
const ANNOUNCE_SOUNDS := ["surgeon_monitor", "surgeon_laugh"]
const ANNOUNCE_DIST := 16.0
## PV diffusés (jauge) : fréquence (s).
const HP_PERIOD := 0.2

var game: Game
var rounds: RoundManager
var scalpels: SurgeonScalpels

## Serveur : coupé pendant les autotests (manches déterministes), comme les
## vagues spéciales ; debug_force_next le force.
var enabled := not Autotest.active
## Prochaine manche du Chirurgien (schéma de la carte, srv_plan).
var next_round := WaveRules.next_boss_of(WaveRules.DEFAULT, WaveRules.CHIRURGIEN, 0)
## Vagues du Chirurgien déjà terminées dans la partie (rang - 1).
var rounds_done := 0
var active := false
var rank := 0
var total := 0
var spawned := 0
var killed := 0
## Serveur : patients relevés par ses opérations (tests).
var summoned := 0
var relocations := 0
var _start_delay := 0.0
var _wait := 0.0
var _alive: Dictionary = {}  # zid -> true
var _far_time: Dictionary = {}
var _recycle_accum := 0.0
var _hp_accum := 0.0
var _end_sent := false
var _rng := RandomNumberGenerator.new()

## Toutes les machines : ambiance active, jauge.
var cl_active := false
var cl_announces := 0
var cl_hp := 1.0
var cl_rage := false
var bar: BossBar
var _gen := 0
var _prev_music := ""


func _ready() -> void:
	rounds = get_parent()
	game = rounds.game
	_rng.randomize()
	scalpels = SurgeonScalpels.new()
	scalpels.name = "Scalpels"
	add_child(scalpels)
	if multiplayer.is_server():
		var zm: ZombieManager = game.get_node("Zombies")
		zm.zombie_killed.connect(_on_killed)
		zm.zombie_removed.connect(_on_removed)


func is_surgeon_round(n: int) -> bool:
	return enabled and n == next_round


func remaining() -> int:
	return maxi(total - spawned, 0) + _alive.size() if active else 0


func alive_count() -> int:
	return _alive.size()


func _waves() -> Dictionary:
	return game.map_def.waves if game and game.map_def else WaveRules.DEFAULT


func srv_plan(after := 0) -> void:
	next_round = WaveRules.next_boss_of(_waves(), WaveRules.CHIRURGIEN, after)


## Tests : la manche `n` sera une manche du Chirurgien.
func debug_force_next(n: int) -> void:
	enabled = true
	next_round = n


## Le Chirurgien vivant (serveur), ou null.
func boss() -> Surgeon:
	for zid in _alive:
		var s := game.zombies.get_zombie(zid) as Surgeon
		if s:
			return s
	return null


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

func srv_begin(n: int) -> void:
	active = true
	rank = rounds_done + 1
	total = SurgeonRules.count(rounds.player_count())
	spawned = 0
	killed = 0
	summoned = 0
	_start_delay = SurgeonRules.START_DELAY
	_wait = 0.0
	_alive.clear()
	_far_time.clear()
	_end_sent = false
	print("[Chirurgien] manche %d : vague du Chirurgien n° %d, %d PV, %d zombies d'escorte" % [
		n, rank, SurgeonRules.health(n, rank, rounds.player_count()), SurgeonRules.escorts(rounds.player_count())])
	_cl_round.rpc(true)
	surgeon_round_started.emit(n)


## Chirurgien apparu et tué ?
func srv_finished() -> bool:
	return active and spawned >= total and _alive.is_empty()


func srv_end(n: int) -> void:
	active = false
	if not _end_sent:
		_cl_round.rpc(false)
	rounds_done += 1
	next_round = WaveRules.next_boss_of(_waves(), WaveRules.CHIRURGIEN, n)
	print("[Chirurgien] fin de la vague du Chirurgien ; prochaine : manche %d" % next_round)
	surgeon_round_cleared.emit(n)


func srv_tick(delta: float) -> void:
	if not active:
		return
	_recycle_accum += delta
	if _recycle_accum >= 1.0:
		_recycle(_recycle_accum)
		_recycle_accum = 0.0
	_hp_accum += delta
	if _hp_accum >= HP_PERIOD:
		_hp_accum = 0.0
		var b := boss()
		if b:
			_cl_hp.rpc(float(b.health) / float(maxi(b.max_health, 1)), b.rage)
	if _start_delay > 0.0:
		_start_delay -= delta
		return
	if spawned >= total:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var valid := _valid_players()
	if valid.is_empty():
		return
	if _spawn_one(valid):
		spawned += 1
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
	var fav: Player = valid[_rng.randi() % valid.size()]
	var pos: Variant = rounds.dogs.pick_spawn_point(fav.global_position, SurgeonRules.SPAWN_MIN_DIST, SurgeonRules.SPAWN_MAX_DIST)
	if pos == null:
		return false
	var hp := SurgeonRules.health(rounds.round_n, rank, rounds.player_count())
	var zid := game.zombies.spawn(pos, 0, hp, ZombieManager.KIND_SURGEON)
	var s := game.zombies.get_zombie(zid) as Surgeon
	if s == null:
		return false
	s.target = fav
	_alive[zid] = true
	return true


## Spawn direct (tests) : un Chirurgien en `pos`, PV donnés (sinon ceux de la vague).
func debug_spawn(pos: Vector3, hp := -1) -> Surgeon:
	var zid := game.zombies.spawn(pos, 0, hp if hp > 0 else SurgeonRules.health(maxi(rounds.round_n, 1), maxi(rank, 1), rounds.player_count()), ZombieManager.KIND_SURGEON)
	var s := game.zombies.get_zombie(zid) as Surgeon
	if s and active:
		_alive[zid] = true
	return s


## Opération du Chirurgien `b` : patients (zombies ordinaires de la manche)
## qui sortent de terre autour de lui.
func srv_summon(b: Surgeon) -> int:
	if not multiplayer.is_server() or b == null:
		return 0
	var n := SurgeonRules.summons(rounds.player_count())
	var made := 0
	var layout := game.layout
	for i in n * 4:
		if made >= n:
			break
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(SurgeonRules.SUMMON_MIN_DIST, SurgeonRules.SUMMON_MAX_DIST)
		var pos := b.global_position + Vector3(cos(a), 0.0, sin(a)) * d
		if layout and not layout.is_walkable_at(pos):
			continue
		if game.nav and not game.nav.world_line_clear(b.global_position + Vector3.UP * 0.5, pos + Vector3.UP * 0.5):
			continue
		pos.y = b.global_position.y
		game.zombies.spawn(pos, RoundRules.pick_speed(maxi(rounds.round_n, 1), _rng), RoundRules.zombie_health(maxi(rounds.round_n, 1)))
		made += 1
	summoned += made
	print("[Chirurgien] opération : %d patient(s) relevé(s)" % made)
	return made


## Chirurgien égaré loin de tout joueur (ou coincé) : replacé près d'eux,
## hors de vue de préférence, avec ses PV.
func _recycle(delta: float) -> void:
	var players := _valid_players()
	if players.is_empty():
		return
	for zid in _alive.keys():
		var b := game.zombies.get_zombie(zid) as Surgeon
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
			var fav: Player = players[_rng.randi() % players.size()]
			var pos: Variant = rounds.dogs.pick_spawn_point(fav.global_position, SurgeonRules.SPAWN_MIN_DIST, SurgeonRules.SPAWN_MAX_DIST)
			if pos != null:
				relocations += 1
				b.global_position = pos
				b.target = fav
				b.velocity = Vector3.ZERO
				print("[Chirurgien] égaré : replacé près de %d" % fav.peer_id)


func _on_killed(zid: int) -> void:
	if not _alive.has(zid):
		return
	_alive.erase(zid)
	_far_time.erase(zid)
	killed += 1
	if active and spawned >= total and _alive.is_empty():
		_end_sent = true
		_cl_hp.rpc(0.0, true)
		_cl_end.rpc()


func _on_removed(zid: int) -> void:
	_alive.erase(zid)
	_far_time.erase(zid)


# --------------------------------------------------------------------------
# Toutes les machines : ambiance, jauge
# --------------------------------------------------------------------------

## Textes (FR / EN) : annonce, opération, changement de phase, mort, jauge.
static func banner_text() -> String:
	return Lang.t("LE CHIRURGIEN ENTRE AU BLOC", "THE SURGEON IS SCRUBBING IN")


static func surgery_text() -> String:
	return Lang.t("IL OPÈRE : LES PATIENTS SE RELÈVENT", "SURGERY IN PROGRESS: PATIENTS GETTING UP")


static func rage_text() -> String:
	return Lang.t("LE CHIRURGIEN PERD PATIENCE", "THE SURGEON IS LOSING HIS PATIENCE")


static func death_text() -> String:
	return Lang.t("LE CHIRURGIEN RACCROCHE SA BLOUSE", "THE SURGEON HANGS UP HIS GOWN")


static func bar_title() -> String:
	return Lang.t("LE CHIRURGIEN", "THE SURGEON")


@rpc("authority", "call_local", "reliable")
func _cl_round(on: bool) -> void:
	cl_active = on
	_gen += 1
	if on:
		cl_hp = 1.0
		cl_rage = false
		Audio.play_2d("special_wave_start", 0.0, 0.0)
		_prev_music = Audio._music_name
		Audio.play_music("special_wave_music", -3.0, 2.5)
		cl_announces = 0
		var gen := _gen
		var dir := _rng.randf() * TAU
		for i in ANNOUNCE_TIMES.size():
			get_tree().create_timer(ANNOUNCE_TIMES[i]).timeout.connect(_announce.bind(gen, dir + i * 0.5))
		_show_bar()
	else:
		Audio.play_music(_prev_music if _prev_music != "" else "ambience_bunker", -6.0, 3.0)
		_hide_bar()
	if game.hud:
		game.hud.set_special_round(on)
		if on:
			game.hud.show_banner(banner_text(), 3.5)


func _announce(gen: int, dir: float) -> void:
	if gen != _gen or not cl_active:
		return
	var ear: Variant = Audio.listener_position()
	if ear == null:
		ear = game.local_player.global_position if game and game.local_player else Vector3.ZERO
	var at: Vector3 = ear + Vector3(sin(dir), 0.0, cos(dir)) * ANNOUNCE_DIST
	Audio.play_3d(ANNOUNCE_SOUNDS[cl_announces % ANNOUNCE_SOUNDS.size()], at, 4.0, 0.0, 4, 0.9)
	cl_announces += 1


## Serveur -> tous : PV du Chirurgien (fraction) et phase 2 ; perdre un
## envoi ne gêne pas (le suivant arrive 0,2 s plus tard).
@rpc("authority", "call_local", "unreliable_ordered")
func _cl_hp(f: float, enraged: bool) -> void:
	if not is_finite(f):
		return
	cl_hp = clampf(f, 0.0, 1.0)
	cl_rage = enraged
	if bar:
		bar.set_fraction(cl_hp, cl_rage)


func _show_bar() -> void:
	if bar or game == null or game.hud == null:
		return
	bar = BossBar.new(bar_title())
	bar.name = "BossBar"
	game.hud.add_child(bar)


func _hide_bar() -> void:
	if bar:
		bar.queue_free()
		bar = null


@rpc("authority", "call_local", "reliable")
func _cl_end() -> void:
	Audio.play_2d("special_wave_end", 0.0, 0.0)
	cl_hp = 0.0
	if bar:
		bar.set_fraction(0.0, cl_rage)
	if game.hud:
		game.hud.show_banner(death_text(), 3.0)
	get_tree().create_timer(SurgeonRules.END_DELAY).timeout.connect(func():
		if cl_active:
			_cl_round(false))
