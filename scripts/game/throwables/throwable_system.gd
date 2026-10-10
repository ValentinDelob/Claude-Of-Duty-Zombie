class_name ThrowableSystem
extends Node
## Objets de l'emplacement de grenade : grenades et PELUCHES LEURRES (chemin
## réseau : /root/Game/Throwables).
##
## Serveur autoritaire :
## * le client annonce le dégoupillage (srv_cook) puis le lancer (srv_throw) ;
##   le serveur décompte la réserve, simule la trajectoire, la mèche, le
##   leurre, et applique les dégâts (Combat.explosion) ;
## * les clients simulent la même trajectoire (diffusée par _cl_spawn) ; le
##   lanceur l'affiche sans attendre (prédiction) puis la rattache à l'objet
##   du serveur ;
## * grenade gardée en main au-delà de la mèche : elle explose dans la main.
## Réserve : PlayerData.throwable (sorte) et PlayerData.grenades (quantité),
## répliquées avec les stats.

const K := ThrowableRules.Kind
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
## Serveur : peluches leurres dont la musique joue.
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
## Serveur : demandes de dégoupillage et de lancer par joueur. Un humain en
## fait au plus 2 à 3 par seconde ; un lancer valide suit toujours un
## dégoupillage accepté (borné par la réserve) : seuls les refus sont bornés.
var _cook_limit := NetGuard.Limiter.new(8.0, 8.0)
var _cancel_limit := NetGuard.Limiter.new(8.0, 8.0)


func _ready() -> void:
	game = get_parent()
	game.rounds.round_started.connect(_on_round_started)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.6, 0.28)
	_flash.omni_range = 9.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)
	# Trace noire en pixel art : 52 pixels de 5 cm (2,6 m).
	var tex := Fx.scorch_texture(52)
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


# --------------------------------------------------------------------------
# Serveur : réserve
# --------------------------------------------------------------------------

## Dotation PROVISOIRE : +2 grenades au début de chaque manche (maximum 4),
## si l'emplacement contient des grenades ou est vide. La première manche
## commence avec la dotation de départ (PlayerData.grenades).
func _on_round_started(n: int) -> void:
	if not multiplayer.is_server() or n <= 1:
		return
	for pid in game.session.data:
		var pd: PlayerData = game.session.data[pid]
		if not ThrowableRules.gets_free_frags(pd.throwable, pd.grenades):
			continue
		var g := ThrowableRules.frags_after_round(pd.grenades)
		if g != pd.grenades or pd.throwable != K.FRAG:
			pd.throwable = K.FRAG
			pd.grenades = g
			game.session.sync_stats(pid)


## Serveur : objet pris à la caisse au hasard (sorte `kind`) : l'emplacement
## de grenade en est rempli jusqu'au maximum, ce qu'il contenait est remplacé.
func srv_fill_slot(pid: int, kind: int) -> void:
	var pd := game.session.get_data(pid)
	if pd == null or not ThrowableRules.NAMES.has(kind):
		return
	pd.throwable = kind
	pd.grenades = ThrowableRules.SLOT_MAX
	game.session.sync_stats(pid)


# --------------------------------------------------------------------------
# Serveur : dégoupillage, lancer, mèche
# --------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func srv_cook(kind: int) -> void:
	# Données de session suffisent (pas de nœud Player exigé) ; le lancer,
	# lui, en a besoin (srv_throw).
	var pid := NetGuard.alive_sender(self, game, _cook_limit, false)
	if pid == NetGuard.NO_SENDER or _cooking.has(pid):
		return
	var pd := game.session.get_data(pid)
	# Seul l'objet que contient l'emplacement se lance.
	if kind != pd.throwable or pd.grenades <= 0:
		return
	pd.grenades -= 1
	if pd.grenades <= 0:
		# Emplacement vide : il redevient « grenades » (dotation de la manche).
		pd.throwable = K.FRAG
	_cooking[pid] = [kind, GameClock.now()]
	# Cartouches déjà poussées gardées, comme ThrowController côté client.
	game.combat.cancel_reload(pid, true)
	game.session.sync_stats(pid)
	_cl_pin.rpc(pid, kind)


@rpc("any_peer", "call_local", "reliable")
func srv_throw(origin: Vector3, dir: Vector3, seq: int) -> void:
	# Limiteur réservé aux refus (un lancer valide suit un dégoupillage borné).
	var pid := NetGuard.server_sender(self)
	if pid == NetGuard.NO_SENDER:
		return
	var c: Array = _cooking.get(pid, [])
	var p: Player = game.players.get(pid)
	if c.is_empty() or p == null:
		# Rien de dégoupillé (refus, déjà explosé) : la prédiction est annulée.
		# Chaque refus renvoie un message : borné (inondation de faux lancers).
		if not _cancel_limit.allow(pid):
			return
		if pid == multiplayer.get_unique_id():
			_cl_cancel(seq)
		else:
			_cl_cancel.rpc_id(pid, seq)
		return
	_cooking.erase(pid)
	# NaN / infini, ou trop loin : repli sur la position connue du serveur
	# (dernier état reçu et accepté, pas la position interpolée affichée).
	var ref := p.srv_origin()
	if not Combat.origin_ok(ref, origin, MAX_ORIGIN_ERROR):
		origin = ref + Vector3.UP * 1.5
	elif not _origin_reachable(p, origin):
		# Origine annoncée derrière un mur, une porte ou le sol : l'objet
		# partirait de l'autre côté. Repli sur les yeux du joueur (serveur).
		origin = p.srv_eye()
	if not NetGuard.valid_dir(dir) or dir.length_squared() < 0.01:
		dir = -p.global_transform.basis.z
	var kind: int = c[0]
	# Pas encore de réplique pour la peluche leurre (voix du joueur à refaire).
	if kind == K.FRAG:
		VoxSystem.say(pid, "throw_grenade", 0.5)
	var fuse := ThrowableRules.fuse_left(c[1], GameClock.now()) if kind == K.FRAG else 0.0
	_spawn(pid, kind, origin, ThrowableRules.throw_velocity(kind, dir), fuse, seq)


## Rien de solide (décor, portes, barricades) entre les yeux du joueur,
## connus du serveur (Player.srv_eye), et le point de départ annoncé par le client.
func _origin_reachable(p: Player, origin: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p.srv_eye(), origin, Throwable.FLIGHT_MASK, [p.get_rid()])
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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
	var t := GameClock.now()
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


## Serveur : fin de la mèche (grenade) ou de la musique (peluche leurre).
func srv_detonate(t: Throwable) -> void:
	if not items.has(t.tid) or items[t.tid] != t:
		return
	_lures.erase(t)
	_explode(t.tid, t.owner_pid, t.kind, t.position)


## Serveur : la peluche leurre s'est posée ; sa musique attire les zombies.
func srv_decoy_landed(t: Throwable) -> void:
	t.start_lure(t.position, ThrowableRules.DECOY_TIME)
	_lures.append(t)
	print("[Throwables] peluche leurre posée en %s : les zombies convergent" % t.position)
	_cl_lure.rpc(t.tid, t.position)


func _explode(tid: int, pid: int, kind: int, pos: Vector3) -> void:
	print("[Throwables] explosion %s n°%d (joueur %d) en %s" % [ThrowableRules.kind_name(kind), tid, pid, pos])
	if kind == K.FRAG:
		game.combat.explosion(pid, pos, ThrowableRules.FRAG_RADIUS, ThrowableRules.FRAG_DAMAGE, ThrowableRules.FRAG_SELF_DAMAGE)
	else:
		game.combat.explosion(pid, pos, ThrowableRules.DECOY_RADIUS, ThrowableRules.DECOY_DAMAGE, ThrowableRules.DECOY_SELF_DAMAGE)
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
			maxf(ThrowableRules.fuse_left(cook_start, GameClock.now()), 0.05), false)
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
		t.start_lure(pos, ThrowableRules.DECOY_TIME)


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
	var big := kind == K.DECOY
	var up := pos + Vector3.UP * 0.3
	fx.sparks.burst(up, Vector3.UP, 36, 9.0, 1.1, 0.7, Color(1.0, 0.55, 0.15, 0.95), 1.8)
	fx.sparks.burst(up, Vector3.UP, 14, 4.0, 1.0, 0.35, Color(1.0, 0.85, 0.5, 1.0), 3.5)
	fx.blood.burst(up, Vector3.UP, 22, 7.0, 0.9, 1.1, Color(0.13, 0.11, 0.08, 1.0), 1.1)
	fx.dust.burst(up, Vector3.UP, 18, 2.2, 1.0, 2.6, Color(0.22, 0.2, 0.18, 0.55), 3.4)
	fx.dust.burst(pos + Vector3.UP * 1.0, Vector3.UP, 10, 1.2, 0.5, 3.5, Color(0.12, 0.11, 0.1, 0.5), 4.0)
	# Boule de feu en cubes (Fx.fireball).
	fx.fireball(up, 1.6 if big else 1.2)
	_flash.global_position = pos + Vector3.UP * 0.8
	_flash_t = 0.35
	var floor_pos := _floor_below(pos)
	if floor_pos != Vector3.INF:
		var d := _scorch[_scorch_i]
		_scorch_i = (_scorch_i + 1) % MAX_SCORCH
		# Pixels alignés sur la grille du sol : quart de tour, centre à 5 cm.
		var at := Vector3(snappedf(floor_pos.x, 0.05), floor_pos.y, snappedf(floor_pos.z, 0.05))
		d.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * (randi() % 4)), at)
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


func _tick_fx(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.light_energy = maxf(_flash_t / 0.35, 0.0) * 9.0
	if _shake_t > 0.0:
		_shake_t -= delta
		var lp := game.local_player
		if lp:
			var a := _shake_amp * clampf(_shake_t / 0.5, 0.0, 1.0)
			lp.add_flinch(Vector2(randf_range(-a, a), randf_range(-a, a)))
		if _shake_t <= 0.0:
			_shake_amp = 0.0
