class_name ThrowableSystem
extends Node
## Grenades et SINGE-TAMBOUR (chemin réseau : /root/Game/Throwables).
##
## Serveur autoritaire :
## * le client annonce le dégoupillage (srv_cook) puis le lancer (srv_throw) ;
##   le serveur décompte la réserve, simule la trajectoire, la mèche, le singe,
##   et applique les dégâts (Combat.explosion) ;
## * les clients simulent la même trajectoire (diffusée par _cl_spawn) ; le
##   lanceur l'affiche sans attendre (prédiction) puis la rattache à l'objet
##   du serveur ;
## * grenade gardée en main au-delà de la mèche : elle explose dans la main.
## Réserve : PlayerData.grenades / monkeys (répliquées avec les stats).

const K := ThrowableRules.Kind
## Marqueur de carte de l'achat mural de grenades.
const GRENADE_BUY_MARKER := "*"
const MAX_ORIGIN_ERROR := 4.0
const SHAKE_RANGE := 16.0
const MAX_SCORCH := 10

## Toutes les machines : une explosion a eu lieu (tests, statistiques).
signal exploded(kind: int, pos: Vector3, owner_pid: int)

var game: Game
## tid -> Throwable (objets du serveur, ou leurs copies chez les clients).
var items: Dictionary = {}
var _next_id := 1
## Serveur : pid -> [kind, instant du dégoupillage].
var _cooking: Dictionary = {}
## Serveur : singes dont la musique joue (leurres).
var _lures: Array[Throwable] = []
## Client : objets prédits en attente du serveur (numéro de lancer -> objet).
var _predicted: Dictionary = {}
var _seq := 0
var _shake_t := 0.0
var _shake_amp := 0.0
var _scorch: Array[Decal] = []
var _scorch_i := 0
var _flash: OmniLight3D
var _flash_t := 0.0


func _ready() -> void:
	game = get_parent()
	game.rounds.round_started.connect(_on_round_started)
	_build_buys()
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.6, 0.28)
	_flash.omni_range = 9.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)
	var tex := Fx.soft_dot_texture()
	for i in MAX_SCORCH:
		var d := Decal.new()
		d.texture_albedo = tex
		d.modulate = Color(0.02, 0.018, 0.015, 0.85)
		d.size = Vector3(2.6, 1.0, 2.6)
		d.visible = false
		d.cull_mask = 1
		d.add_to_group(RenderQuality.DECAL_GROUP)
		add_child(d)
		_scorch.append(d)


static func now() -> float:
	return GameClock.now()  # temps de jeu (voir game_clock.gd)


## Achats muraux de grenades (marqueur « * »), comme sur Kino der Toten.
func _build_buys() -> void:
	for m in game.layout.grenade_buys():
		var b := GrenadeBuy.new()
		b.setup_marker(m)
		game.world.add_child(b)
		game.interact.register(b)


# --------------------------------------------------------------------------
# Serveur : réserve
# --------------------------------------------------------------------------

## +2 grenades au début de chaque manche (maximum 4). La première manche
## commence avec la dotation de départ (PlayerData.grenades).
func _on_round_started(n: int) -> void:
	if not multiplayer.is_server() or n <= 1:
		return
	for pid in game.session.data:
		var pd: PlayerData = game.session.data[pid]
		var g := ThrowableRules.frags_after_round(pd.grenades)
		if g != pd.grenades:
			pd.grenades = g
			game.session.sync_stats(pid)


## Serveur : singes de la boîte mystère.
func srv_give_monkeys(pid: int) -> void:
	var pd := game.session.get_data(pid)
	if pd == null:
		return
	pd.has_monkeys = true
	pd.monkeys = ThrowableRules.MONKEY_MAX
	game.session.sync_stats(pid)


## Serveur : bonus MUNITIONS MAX (grenades à 4, singes à 3 s'ils en ont).
func srv_refill_all() -> void:
	for pid in game.session.data:
		var pd: PlayerData = game.session.data[pid]
		pd.grenades = ThrowableRules.FRAG_MAX
		if pd.has_monkeys:
			pd.monkeys = ThrowableRules.MONKEY_MAX
		game.session.sync_stats(pid)


# --------------------------------------------------------------------------
# Serveur : dégoupillage, lancer, mèche
# --------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_cook(kind: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var pd := game.session.get_data(pid)
	if pd == null or pd.life != PlayerData.Life.ALIVE or _cooking.has(pid):
		return
	match kind:
		K.FRAG:
			if pd.grenades <= 0:
				return
			pd.grenades -= 1
		K.MONKEY:
			if not pd.has_monkeys or pd.monkeys <= 0:
				return
			pd.monkeys -= 1
		_:
			return
	_cooking[pid] = [kind, now()]
	game.combat.cancel_reload(pid)
	game.session.sync_stats(pid)
	_cl_pin.rpc(pid, kind)


@rpc("any_peer", "call_local", "reliable")
func srv_throw(origin: Vector3, dir: Vector3, seq: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var c: Array = _cooking.get(pid, [])
	var p: Player = game.players.get(pid)
	if c.is_empty() or p == null:
		# Rien de dégoupillé (refus, déjà explosé) : la prédiction est annulée.
		if pid == multiplayer.get_unique_id():
			_cl_cancel(seq)
		else:
			_cl_cancel.rpc_id(pid, seq)
		return
	_cooking.erase(pid)
	# NaN / infini : repli sur la position et l'orientation connues du serveur.
	if not NetGuard.finite_vec(origin) or p.global_position.distance_to(origin) > MAX_ORIGIN_ERROR:
		origin = p.global_position + Vector3.UP * 1.5
	if not NetGuard.valid_dir(dir) or dir.length_squared() < 0.01:
		dir = -p.global_transform.basis.z
	var kind: int = c[0]
	var monkey := kind == ThrowableRules.Kind.MONKEY
	VoxSystem.say(pid, "throw_monkey" if monkey else "throw_grenade", 0.9 if monkey else 0.5)
	var fuse := ThrowableRules.fuse_left(c[1], now()) if kind == K.FRAG else 0.0
	_spawn(pid, kind, origin, ThrowableRules.throw_velocity(kind, dir), fuse, seq)


func _spawn(pid: int, kind: int, origin: Vector3, vel: Vector3, fuse: float, seq: int) -> void:
	var id := _next_id
	_next_id += 1
	var t := Throwable.new()
	t.setup(id, kind, pid, origin, vel, maxf(fuse, 0.05), true)
	t.system = self
	add_child(t)
	items[id] = t
	_cl_spawn.rpc(id, pid, kind, origin, vel, fuse, seq)


func _process(delta: float) -> void:
	_tick_fx(delta)
	if not multiplayer.is_server() or _cooking.is_empty():
		return
	var t := now()
	for pid in _cooking.keys():
		var c: Array = _cooking[pid]
		var pd := game.session.get_data(pid)
		var p: Player = game.players.get(pid)
		if pd == null or p == null:
			_cooking.erase(pid)
			continue
		if c[0] == K.FRAG and ThrowableRules.fuse_left(c[1], t) <= 0.0:
			# Gardée trop longtemps : explose dans la main.
			_cooking.erase(pid)
			print("[Throwables] grenade explosée dans la main de %d" % pid)
			_explode(0, pid, K.FRAG, p.global_position + Vector3.UP * 1.2 - p.global_transform.basis.z * 0.3)
		elif pd.life != PlayerData.Life.ALIVE:
			# À terre pendant le dégoupillage : l'objet tombe aux pieds.
			_cooking.erase(pid)
			var fuse := ThrowableRules.fuse_left(c[1], t) if c[0] == K.FRAG else 0.0
			_spawn(pid, c[0], p.global_position + Vector3.UP * 0.6, Vector3.ZERO, fuse, 0)


## Serveur : fin de la mèche (grenade) ou de la musique (singe).
func srv_detonate(t: Throwable) -> void:
	if not items.has(t.tid) or items[t.tid] != t:
		return
	_lures.erase(t)
	_explode(t.tid, t.owner_pid, t.kind, t.position)


## Serveur : le singe s'est posé ; sa musique attire les zombies.
func srv_monkey_landed(t: Throwable) -> void:
	t.start_lure(t.position, ThrowableRules.MONKEY_TIME)
	_lures.append(t)
	print("[Throwables] singe posé en %s : les zombies convergent" % t.position)
	_cl_lure.rpc(t.tid, t.position)


func _explode(tid: int, pid: int, kind: int, pos: Vector3) -> void:
	print("[Throwables] explosion %s n°%d (joueur %d) en %s" % [ThrowableRules.kind_name(kind), tid, pid, pos])
	if kind == K.FRAG:
		game.combat.explosion(pid, pos, ThrowableRules.FRAG_RADIUS, ThrowableRules.FRAG_DAMAGE, ThrowableRules.FRAG_SELF_DAMAGE)
	else:
		game.combat.explosion(pid, pos, ThrowableRules.MONKEY_RADIUS, ThrowableRules.MONKEY_DAMAGE, ThrowableRules.MONKEY_SELF_DAMAGE)
	_cl_explode.rpc(tid, pid, kind, pos)


## Serveur (zombies) : point d'attraction prioritaire sur les joueurs, ou
## Vector3.INF. Les chiens de l'enfer n'y prêtent aucune attention (BO1).
func lure_for(z: Zombie) -> Vector3:
	if _lures.is_empty() or z is Hellhound:
		return Vector3.INF
	var best := Vector3.INF
	var best_d := INF
	for t in _lures:
		var d := t.position.distance_squared_to(z.global_position)
		if d < best_d:
			best_d = d
			best = t.position
	return best


func lure_count() -> int:
	return _lures.size()


func is_cooking(pid: int) -> bool:
	return _cooking.has(pid)


# --------------------------------------------------------------------------
# Client : lancer prédit
# --------------------------------------------------------------------------

## Joueur local : lance l'objet dégoupillé (affiché aussitôt chez le lanceur).
func throw_local(kind: int, origin: Vector3, dir: Vector3, cook_start: float) -> void:
	_seq += 1
	if not multiplayer.is_server():
		var t := Throwable.new()
		t.setup(-_seq, kind, multiplayer.get_unique_id(), origin, ThrowableRules.throw_velocity(kind, dir),
			maxf(ThrowableRules.fuse_left(cook_start, now()), 0.05), false)
		add_child(t)
		_predicted[_seq] = t
	srv_throw.rpc_id(1, origin, dir, _seq)


@rpc("authority", "call_remote", "reliable")
func _cl_cancel(seq: int) -> void:
	var t: Throwable = _predicted.get(seq)
	_predicted.erase(seq)
	if t:
		t.queue_free()


# --------------------------------------------------------------------------
# Diffusions (toutes les machines)
# --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_pin(pid: int, _kind: int) -> void:
	if pid == multiplayer.get_unique_id():
		return
	var p: Player = game.players.get(pid)
	if p:
		Audio.play_3d("grenade_pin", p.global_position + Vector3.UP * 1.3, -4.0, 0.05)


@rpc("authority", "call_local", "reliable")
func _cl_spawn(id: int, pid: int, kind: int, origin: Vector3, vel: Vector3, fuse: float, seq: int) -> void:
	if multiplayer.is_server():
		return  # l'objet du serveur est aussi celui qu'on voit
	if pid == multiplayer.get_unique_id() and _predicted.has(seq):
		var pred: Throwable = _predicted[seq]
		_predicted.erase(seq)
		pred.tid = id
		items[id] = pred
		return
	var t := Throwable.new()
	t.setup(id, kind, pid, origin, vel, maxf(fuse, 0.05), false)
	add_child(t)
	items[id] = t
	if pid != multiplayer.get_unique_id():
		Audio.play_3d("grenade_throw", origin, -4.0, 0.08)


@rpc("authority", "call_local", "reliable")
func _cl_lure(id: int, pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	var t: Throwable = items.get(id)
	if t:
		t.start_lure(pos, ThrowableRules.MONKEY_TIME)


@rpc("authority", "call_local", "reliable")
func _cl_explode(id: int, pid: int, kind: int, pos: Vector3) -> void:
	var t: Throwable = items.get(id)
	items.erase(id)
	if t:
		t.queue_free()
	explosion_fx(pos, kind)
	exploded.emit(kind, pos, pid)


## Explosion : boule de feu, étincelles, débris, fumée, éclair, trace noire au
## sol, son et secousse de la caméra du joueur local.
func explosion_fx(pos: Vector3, kind: int) -> void:
	var fx: Fx = game.fx_root
	var big := kind == K.MONKEY
	var up := pos + Vector3.UP * 0.3
	fx.sparks.burst(up, Vector3.UP, 36, 9.0, 1.1, 0.7, Color(1.0, 0.55, 0.15, 0.95), 1.8)
	fx.sparks.burst(up, Vector3.UP, 14, 4.0, 1.0, 0.35, Color(1.0, 0.85, 0.5, 1.0), 3.5)
	fx.blood.burst(up, Vector3.UP, 22, 7.0, 0.9, 1.1, Color(0.13, 0.11, 0.08, 1.0), 1.1)
	fx.dust.burst(up, Vector3.UP, 18, 2.2, 1.0, 2.6, Color(0.22, 0.2, 0.18, 0.55), 3.4)
	fx.dust.burst(pos + Vector3.UP * 1.0, Vector3.UP, 10, 1.2, 0.5, 3.5, Color(0.12, 0.11, 0.1, 0.5), 4.0)
	_fireball(up, 1.6 if big else 1.2)
	_flash.global_position = pos + Vector3.UP * 0.8
	_flash_t = 0.35
	var floor_pos := _floor_below(pos)
	if floor_pos != Vector3.INF:
		var d := _scorch[_scorch_i]
		_scorch_i = (_scorch_i + 1) % MAX_SCORCH
		d.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), floor_pos)
		d.visible = true
	Audio.play_3d("frag_explode", pos, 1.0, 0.08, 4)
	var lp := game.local_player
	if lp:
		var dist := lp.global_position.distance_to(pos)
		if dist < SHAKE_RANGE:
			_shake_amp = maxf(_shake_amp, lerpf(0.05, 0.004, dist / SHAKE_RANGE))
			_shake_t = 0.5


func _floor_below(pos: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 2.0, 1)
	var hit := game.world.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else Vector3.INF


func _fireball(pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.55, 0.18, 0.9)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 2.0, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.32).set_delay(0.06)
	tw.chain().tween_callback(mi.queue_free)


func _tick_fx(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.light_energy = maxf(_flash_t / 0.35, 0.0) * 9.0
	if _shake_t > 0.0:
		_shake_t -= delta
		var lp := game.local_player
		if lp:
			var a := _shake_amp * clampf(_shake_t / 0.5, 0.0, 1.0)
			lp._flinch += Vector2(randf_range(-a, a), randf_range(-a, a))
		if _shake_t <= 0.0:
			_shake_amp = 0.0
