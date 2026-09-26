class_name ZombieManager
extends Node3D
## Gestion réseau des zombies (chemin réseau : /root/Game/Zombies).
##
## Seul le serveur crée, simule et détruit les zombies. Il diffuse :
##  * les apparitions / disparitions (fiable) ;
##  * un instantané delta à SNAPSHOT_RATE Hz (non fiable) : seuls les champs
##    quantifiés qui ont changé, chaque zombie étant renvoyé en entier tous les
##    NetCodec.ZOMBIE_REFRESH instantanés (voir NetCodec, docs/ARCHITECTURE.md).
##    Les clients gardent le dernier état reçu de chaque zombie et l'interpolent.

const SNAPSHOT_RATE := 15.0
## Types d'entité partageant ce canal (apparition, instantanés, mort).
const KIND_ZOMBIE := 0
const KIND_DOG := 1

signal zombie_spawned(z: Zombie)
signal zombie_removed(zid: int)
signal zombie_killed(zid: int)

var zombies: Dictionary = {}  # id -> Zombie
## Zombies vivants (liste tenue à jour, sans allocation pour les parcours).
var alive: Array[Zombie] = []
var _next_id := 1
var _snap_accum := 0.0
## Réplication : dernier état quantifié envoyé (serveur) ou reçu (client),
## id -> PackedInt32Array (NetCodec.quantize_zombie).
var net_q: Dictionary = {}
## Serveur : masque des champs modifiés au dernier envoi, et nombre d'envois
## complets restants après l'apparition (id -> int).
var _net_mask: Dictionary = {}
var _net_fresh: Dictionary = {}
var _snap_seq := 0
## Serveur : total des octets d'instantanés envoyés (avant compression ENet), mesures.
var snapshot_bytes := 0
var _rng := RandomNumberGenerator.new()

## Grille spatiale des zombies vivants pour la séparation (serveur), refaite
## une fois par pas de physique. Case de 1 m >= rayon de répulsion (0,9 m) :
## les 9 cases autour d'un zombie contiennent tous ses voisins.
const GRID_CELL := 1.0
const EMPTY: Array = []
var _grid: Dictionary = {}  # clé de case -> Array[Zombie]
var _grid_frame := -1

## Caméra de l'image en cours (cadence d'animation des zombies).
const CULL_RADIUS := 1.3
const FAR_DIST := 20.0
const VERY_FAR_DIST := 35.0
var _cam_ok := false
var _cam_pos := Vector3.ZERO
var _frustum: Array[Plane] = []


static func grid_key(gx: int, gz: int) -> int:
	return (gx + 4096) + (gz + 4096) * 8192


func separation_grid() -> Dictionary:
	var f := Engine.get_physics_frames()
	if f != _grid_frame:
		_grid_frame = f
		_grid.clear()
		for z: Zombie in alive:
			var p := z.global_position
			var k := grid_key(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))
			var bucket: Array = _grid.get(k, EMPTY)
			if bucket.is_empty():
				bucket = []
				_grid[k] = bucket
			bucket.append(z)
	return _grid


## Le parent est traité avant ses enfants : la caméra est lue une fois par
## image, avant l'animation des zombies.
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	_cam_ok = cam != null and not alive.is_empty()
	if _cam_ok:
		_cam_pos = cam.global_position
		_frustum.assign(cam.get_frustum())
		# Ombres portées limitées aux zombies les plus proches (RenderQuality).
		if Engine.get_process_frames() % ZombieShadows.UPDATE_FRAMES == 0:
			ZombieShadows.update(alive, _cam_pos, RenderQuality.current())


## Intervalle minimal entre deux poses d'un zombie à `pos` : 0 (chaque image)
## s'il est visible et proche, plus long hors champ ou au loin.
func pose_step(pos: Vector3) -> float:
	if not _cam_ok:
		return 0.0
	var c := pos + Vector3(0.0, 0.9, 0.0)
	for pl in _frustum:
		if pl.distance_to(c) > CULL_RADIUS:
			return Zombie.POSE_STEP_OFFSCREEN
	var d2 := c.distance_squared_to(_cam_pos)
	if d2 > VERY_FAR_DIST * VERY_FAR_DIST:
		return Zombie.POSE_STEP_VERY_FAR
	if d2 > FAR_DIST * FAR_DIST:
		return Zombie.POSE_STEP_FAR
	return 0.0


func _ready() -> void:
	_rng.randomize()


func alive_count() -> int:
	return alive.size()


func get_zombie(zid: int) -> Zombie:
	return zombies.get(zid)


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

## Fait apparaître un zombie (serveur uniquement). Retourne son id.
func spawn(pos: Vector3, speed_class: int, health: int, kind := KIND_ZOMBIE) -> int:
	if not multiplayer.is_server():
		return -1
	var zid := _next_id
	_next_id = (_next_id % 65000) + 1
	var yaw := _rng.randf() * TAU
	var variant := _rng.randi() % 100000
	_cl_spawn.rpc(zid, pos, yaw, variant, speed_class, kind)
	var z: Zombie = zombies.get(zid)
	if z:
		z.health = health
		z.max_health = health
	return zid


## Serveur : tue un zombie (dégâts déjà validés par Combat).
func kill(zid: int, headshot: bool, dir: Vector3, _gib := false) -> void:
	var z: Zombie = zombies.get(zid)
	if not multiplayer.is_server() or z == null or not z.is_alive():
		return
	_cl_die.rpc(zid, headshot, dir)
	zombie_killed.emit(zid)
	# Le corps reste le temps de la chute et de la dissolution.
	get_tree().create_timer(Zombie.DISSOLVE_DELAY + Zombie.DISSOLVE_TIME + 0.3).timeout.connect(despawn.bind(zid))


## Serveur : tue un zombie en le projetant (onde de choc du TONNERRE-7).
## `vel` : vitesse initiale du vol, identique sur toutes les machines.
func kill_flung(zid: int, vel: Vector3) -> void:
	var z: Zombie = zombies.get(zid)
	if not multiplayer.is_server() or z == null or not z.is_alive():
		return
	_cl_die_flung.rpc(zid, vel)
	zombie_killed.emit(zid)
	get_tree().create_timer(Zombie.DISSOLVE_DELAY + Zombie.DISSOLVE_TIME + 0.3).timeout.connect(despawn.bind(zid))
## Serveur : démembrement éventuel d'un coup (ZombieGibs), appelé par
## Combat.damage_zombie APRÈS le retrait des PV et AVANT la mort : le RPC
## fiable part avant _cl_die (ordre garanti). `hit_at` : point d'impact
## (Vector3.INF si inconnu), `weapon_id` : arme du tir ("" sinon).
func srv_gib(z: Zombie, dmg: int, killed: bool, headshot: bool, kind: int, hit_at: Vector3, weapon_id: String, dir: Vector3) -> void:
	if not multiplayer.is_server() or z == null or z is Hellhound:
		return
	var limb := ZombieGibs.limb_at(z, hit_at) if hit_at != Vector3.INF else ZombieGibs.TORSO
	var wclass: String = WeaponDB.stats(weapon_id).get("class", "") if weapon_id != "" else ""
	var bits := ZombieGibs.decide(kind, wclass, dmg, z.health + dmg, killed, headshot, limb, z.gibs, _rng)
	if bits != 0:
		_cl_gib.rpc(z.id, bits, dir, killed)


@rpc("authority", "call_local", "reliable")
func _cl_gib(zid: int, bits: int, dir: Vector3, lethal: bool) -> void:
	var z: Zombie = zombies.get(zid)
	if z:
		ZombieGibs.apply(z, bits, dir, lethal)


func despawn(zid: int) -> void:
	if multiplayer.is_server() and zombies.has(zid):
		_cl_despawn.rpc(zid)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or zombies.is_empty():
		return
	_snap_accum += delta
	if _snap_accum < 1.0 / SNAPSHOT_RATE:
		return
	# Soustraction (et non remise à zéro) : cadence exacte malgré le pas de physique.
	_snap_accum = minf(_snap_accum - 1.0 / SNAPSHOT_RATE, 1.0 / SNAPSHOT_RATE)
	if Net.is_online() and multiplayer.get_peers().size() > 0:
		var buf := build_snapshot()
		snapshot_bytes += buf.size()
		_cl_snapshot.rpc(buf)


## Serveur : instantané delta. Pour chaque zombie, les champs modifiés depuis
## l'envoi précédent ET ceux modifiés à l'envoi d'avant (redondance : la perte
## d'un seul paquet non fiable ne laisse aucun champ périmé) ; en entier pendant
## ses NetCodec.FRESH_FULL premiers envois (son apparition, fiable, a pu arriver
## après) et à son tour de rafraîchissement. Met à jour net_q : à n'appeler que
## pour un envoi réel.
func build_snapshot() -> PackedByteArray:
	var entries := []
	for z: Zombie in alive:
		var q := NetCodec.quantize_zombie(z.global_position, z.yaw, z.anim_code())
		var changed := NetCodec.diff_mask(net_q.get(z.id, PackedInt32Array()), q)
		var m: int = changed | _net_mask.get(z.id, 0)
		_net_mask[z.id] = changed
		var fresh: int = _net_fresh.get(z.id, 0)
		if fresh > 0:
			_net_fresh[z.id] = fresh - 1
			m = NetCodec.FULL_MASK
		if (z.id + _snap_seq) % NetCodec.ZOMBIE_REFRESH == 0:
			m = NetCodec.FULL_MASK
		if m != 0:
			entries.append([z.id, m, q])
			net_q[z.id] = q
	_snap_seq += 1
	return NetCodec.encode_zombie_snapshot(entries)


# --------------------------------------------------------------------------
# Toutes les machines
# --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_spawn(zid: int, pos: Vector3, yaw: float, variant: int, speed_class: int, kind: int) -> void:
	if zombies.has(zid):
		return
	var z: Zombie = Hellhound.new() if kind == KIND_DOG else Zombie.new()
	z.setup(zid, variant, speed_class, multiplayer.is_server())
	z.yaw = yaw
	add_child(z)
	z.global_position = pos
	z.rotation.y = yaw
	zombies[zid] = z
	alive.append(z)
	# État initial connu de toutes les machines (message fiable) : base des deltas.
	net_q[zid] = NetCodec.quantize_zombie(pos, yaw, z.anim_code())
	if multiplayer.is_server():
		_net_fresh[zid] = NetCodec.FRESH_FULL
	zombie_spawned.emit(z)
	if kind == KIND_DOG:
		return  # Apparition par la foudre (Hellhound).
	# Les zombies des fenêtres (BarricadeSystem) ne sortent pas du sol.
	if z.state == Zombie.State.EMERGE:
		if Game.instance:
			Game.instance.fx_root.dirt_burst(pos)
		Audio.play_3d("emerge", pos, -3.0, 0.1, 3)


@rpc("authority", "call_local", "reliable")
func _cl_die(zid: int, headshot: bool, dir: Vector3) -> void:
	var z: Zombie = zombies.get(zid)
	if z == null:
		return
	alive.erase(z)
	z.die(dir, headshot)


@rpc("authority", "call_local", "reliable")
func _cl_die_flung(zid: int, vel: Vector3) -> void:
	var z: Zombie = zombies.get(zid)
	if z == null:
		return
	alive.erase(z)
	z.die_flung(vel)


@rpc("authority", "call_local", "reliable")
func _cl_despawn(zid: int) -> void:
	var z: Zombie = zombies.get(zid)
	if z == null:
		return
	zombies.erase(zid)
	net_q.erase(zid)
	_net_mask.erase(zid)
	_net_fresh.erase(zid)
	alive.erase(z)
	z.queue_free()
	zombie_removed.emit(zid)


@rpc("authority", "call_remote", "unreliable_ordered")
func _cl_snapshot(buf: PackedByteArray) -> void:
	apply_snapshot(buf)


## Client : met à jour les derniers états reçus puis ajoute un échantillon
## d'interpolation à CHAQUE zombie vivant, même inchangé (la ligne de temps de
## l'interpolation avance au rythme des instantanés).
func apply_snapshot(buf: PackedByteArray) -> void:
	if NetCodec.decode_zombie_snapshot(buf, net_q) < 0:
		return
	var t := Time.get_ticks_usec() / 1000000.0
	for z: Zombie in alive:
		var q: PackedInt32Array = net_q.get(z.id, PackedInt32Array())
		if q.size() == 5:
			z.push_snapshot(t, NetCodec.zombie_pos(q), NetCodec.zombie_yaw(q), q[NetCodec.QCODE])
