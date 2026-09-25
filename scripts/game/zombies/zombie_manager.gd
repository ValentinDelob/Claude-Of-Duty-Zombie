class_name ZombieManager
extends Node3D
## Gestion réseau des zombies (chemin réseau : /root/Game/Zombies).
##
## Seul le serveur crée, simule et détruit les zombies. Il diffuse :
##  * les apparitions / disparitions (fiable) ;
##  * un instantané compact de tous les zombies à SNAPSHOT_RATE Hz (non fiable),
##    10 octets par zombie, que les clients interpolent.

const SNAPSHOT_RATE := 15.0
const BYTES_PER_ZOMBIE := 10
## Décalage vertical pour coder y (peut être négatif pendant l'émergence).
const Y_OFFSET := 20.0

signal zombie_spawned(z: Zombie)
signal zombie_removed(zid: int)

var zombies: Dictionary = {}  # id -> Zombie
## Zombies vivants (liste tenue à jour, sans allocation pour les parcours).
var alive: Array[Zombie] = []
var _next_id := 1
var _snap_accum := 0.0
var _rng := RandomNumberGenerator.new()


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
func spawn(pos: Vector3, speed_class: int, health: int) -> int:
	if not multiplayer.is_server():
		return -1
	var zid := _next_id
	_next_id = (_next_id % 65000) + 1
	var yaw := _rng.randf() * TAU
	var variant := _rng.randi() % 100000
	_cl_spawn.rpc(zid, pos, yaw, variant, speed_class)
	var z: Zombie = zombies.get(zid)
	if z:
		z.health = health
		z.max_health = health
	return zid


func despawn(zid: int) -> void:
	if multiplayer.is_server() and zombies.has(zid):
		_cl_despawn.rpc(zid)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or zombies.is_empty():
		return
	_snap_accum += delta
	if _snap_accum < 1.0 / SNAPSHOT_RATE:
		return
	_snap_accum = 0.0
	if Net.is_online() and multiplayer.get_peers().size() > 0:
		_cl_snapshot.rpc(build_snapshot())


func build_snapshot() -> PackedByteArray:
	var buf := PackedByteArray()
	var list := alive
	buf.resize(2 + list.size() * BYTES_PER_ZOMBIE)
	buf.encode_u16(0, list.size())
	var o := 2
	for z: Zombie in list:
		var p := z.global_position
		buf.encode_u16(o, z.id)
		buf.encode_u16(o + 2, clampi(int(round(p.x * 100.0)), 0, 65535))
		buf.encode_u16(o + 4, clampi(int(round((p.y + Y_OFFSET) * 100.0)), 0, 65535))
		buf.encode_u16(o + 6, clampi(int(round(p.z * 100.0)), 0, 65535))
		buf.encode_u8(o + 8, int(fposmod(z.yaw, TAU) / TAU * 255.0) & 255)
		buf.encode_u8(o + 9, z.anim_code())
		o += BYTES_PER_ZOMBIE
	return buf


# --------------------------------------------------------------------------
# Toutes les machines
# --------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _cl_spawn(zid: int, pos: Vector3, yaw: float, variant: int, speed_class: int) -> void:
	if zombies.has(zid):
		return
	var z := Zombie.new()
	z.setup(zid, variant, speed_class, multiplayer.is_server())
	z.yaw = yaw
	add_child(z)
	z.global_position = pos
	z.rotation.y = yaw
	zombies[zid] = z
	alive.append(z)
	zombie_spawned.emit(z)


@rpc("authority", "call_local", "reliable")
func _cl_despawn(zid: int) -> void:
	var z: Zombie = zombies.get(zid)
	if z == null:
		return
	zombies.erase(zid)
	alive.erase(z)
	z.queue_free()
	zombie_removed.emit(zid)


@rpc("authority", "call_remote", "unreliable_ordered")
func _cl_snapshot(buf: PackedByteArray) -> void:
	apply_snapshot(buf)


func apply_snapshot(buf: PackedByteArray) -> void:
	if buf.size() < 2:
		return
	var n := buf.decode_u16(0)
	if buf.size() < 2 + n * BYTES_PER_ZOMBIE:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var o := 2
	for i in n:
		var zid := buf.decode_u16(o)
		var z: Zombie = zombies.get(zid)
		if z:
			var pos := Vector3(buf.decode_u16(o + 2) / 100.0, buf.decode_u16(o + 4) / 100.0 - Y_OFFSET, buf.decode_u16(o + 6) / 100.0)
			var yaw := buf.decode_u8(o + 8) / 255.0 * TAU
			z.push_snapshot(t, pos, yaw, buf.decode_u8(o + 9))
		o += BYTES_PER_ZOMBIE
