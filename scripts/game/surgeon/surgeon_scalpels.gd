class_name SurgeonScalpels
extends Node3D
## Scalpels lancés par le Chirurgien (chemin réseau :
## /root/Game/Rounds/Surgeon/Scalpels). Projectiles VISIBLES, qu'on peut
## esquiver : le serveur annonce chaque éventail (_cl_throw, fiable : point
## de départ et vitesses), toutes les machines simulent le même vol
## (SurgeonRules.scalpel_pos : ligne droite et légère chute) et le même
## arrêt contre le décor (étincelles, tintement, la lame reste plantée un
## instant). Le SERVEUR seul décide des touches (SurgeonRules.scalpel_hits,
## une par scalpel) : dégâts au joueur (Combat.damage_player, le Chirurgien en
## `source` : rencontre du codex), puis _cl_hit (fiable) retire le scalpel
## partout (sang). Modèle : lame et manche en cubes de 2,5 cm.

## Scalpel planté dans le décor : reste visible (s).
const STUCK_TIME := 1.2
const MAX_FLYING := 48

signal scalpel_hit_player(pid: int)
signal scalpel_hit_wall(pos: Vector3)

var game: Game
## Toutes les machines : id -> {p0, v0, t, node, src, prev, stuck}.
var flying: Dictionary = {}
## Serveur : compteurs (tests).
var thrown := 0
var player_hits := 0
var _next_id := 1
var _blade_mesh: Mesh
var _handle_mesh: Mesh
var _blade_mat: StandardMaterial3D
var _handle_mat: StandardMaterial3D
var _q: PhysicsRayQueryParameters3D


func _ready() -> void:
	var sr := get_parent()
	game = sr.game if sr and "game" in sr else null
	_q = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.FORWARD, 1)


## Serveur : lance un éventail depuis `origin` (vitesses `vels`), pour `src`.
func srv_throw(src: Surgeon, origin: Vector3, vels: PackedVector3Array) -> void:
	if not multiplayer.is_server() or vels.is_empty():
		return
	var first := _next_id
	_next_id += vels.size()
	thrown += vels.size()
	_cl_throw.rpc(first, origin, vels, src.id if src else 0)


@rpc("authority", "call_local", "reliable")
func _cl_throw(first: int, origin: Vector3, vels: PackedVector3Array, src_id: int) -> void:
	if not NetGuard.finite_vec(origin) or vels.size() > 8:
		return
	for i in vels.size():
		if flying.size() >= MAX_FLYING or not NetGuard.finite_vec(vels[i]):
			continue
		var n := _make_node()
		add_child(n)
		n.global_position = origin
		flying[first + i] = {"p0": origin, "v0": vels[i].limit_length(40.0), "t": 0.0, "node": n, "src": src_id,
			"prev": origin, "stuck": -1.0}
		_orient(n, vels[i])


@rpc("authority", "call_local", "reliable")
func _cl_hit(sid: int, pos: Vector3) -> void:
	var s: Dictionary = flying.get(sid, {})
	if s.is_empty():
		return
	flying.erase(sid)
	(s.node as Node3D).queue_free()
	var fx: Fx = game.fx_root if game else null
	if fx and NetGuard.finite_vec(pos):
		fx.blood_hit(pos, Vector3.UP, 1.0)
	Audio.play_3d("surgeon_cut", pos, 0.0, 0.08, 3)


func _physics_process(delta: float) -> void:
	if flying.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for sid in flying.keys():
		var s: Dictionary = flying[sid]
		var n: Node3D = s.node
		if float(s.stuck) >= 0.0:
			s.stuck = float(s.stuck) + delta
			if float(s.stuck) >= STUCK_TIME:
				flying.erase(sid)
				n.queue_free()
			else:
				n.scale = Vector3.ONE * clampf(1.0 - (float(s.stuck) - STUCK_TIME + 0.3) / 0.3, 0.05, 1.0)
			continue
		s.t = float(s.t) + delta
		var prev: Vector3 = s.prev
		var pos := SurgeonRules.scalpel_pos(s.p0, s.v0, s.t)
		# Joueurs (serveur seulement : il décide des touches).
		if multiplayer.is_server() and game and _srv_hits(sid, s, prev, pos):
			continue
		_q.from = prev
		_q.to = pos
		var hit := space.intersect_ray(_q)
		if not hit.is_empty():
			n.global_position = hit.position
			s.stuck = 0.0
			_on_wall(hit.position, hit.normal)
			continue
		n.global_position = pos
		_orient(n, SurgeonRules.scalpel_pos(s.p0, s.v0, s.t + 0.02) - pos)
		s.prev = pos
		if float(s.t) >= SurgeonRules.THROW_LIFE:
			flying.erase(sid)
			n.queue_free()


func _srv_hits(sid: int, s: Dictionary, a: Vector3, b: Vector3) -> bool:
	for p: Player in game.players.values():
		var pd := game.session.get_data(p.peer_id)
		if pd == null or pd.life != PlayerData.Life.ALIVE or p.untargetable:
			continue
		if not SurgeonRules.scalpel_hits(a, b, p.global_position):
			continue
		player_hits += 1
		var src := game.zombies.get_zombie(int(s.src)) if game.zombies else null
		game.combat.damage_player(p.peer_id, SurgeonRules.THROW_DAMAGE, a, src if src and src.is_alive() else null)
		scalpel_hit_player.emit(p.peer_id)
		_cl_hit.rpc(sid, b)
		return true
	return false


func _on_wall(pos: Vector3, normal: Vector3) -> void:
	scalpel_hit_wall.emit(pos)
	Audio.play_3d("surgeon_scalpel_hit", pos, -2.0, 0.12, 4)
	var fx: Fx = game.fx_root if game else null
	if fx:
		fx.sparks.burst(pos, normal, 6, 2.5, 0.6, 0.3, Color(1.0, 0.9, 0.6), 1.0)


## Le scalpel vole pointe en avant (axe +Z du modèle).
func _orient(n: Node3D, dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	var up := Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	n.basis = Basis.looking_at(dir, up, true)


## Scalpel en cubes de 2,5 cm : lame d'acier (2 × 1 × 8 cubes) au bord clair,
## manche sombre (1 × 1 × 4).
func _make_node() -> Node3D:
	if _blade_mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.025, 0.2)
		_blade_mesh = bm
		var hm := BoxMesh.new()
		hm.size = Vector3(0.025, 0.025, 0.1)
		_handle_mesh = hm
		_blade_mat = StandardMaterial3D.new()
		_blade_mat.albedo_color = Color(0.82, 0.86, 0.9)
		_blade_mat.metallic = 0.6
		_blade_mat.roughness = 0.25
		_blade_mat.emission_enabled = true
		_blade_mat.emission = Color(0.55, 0.65, 0.75)
		_blade_mat.emission_energy_multiplier = 0.8
		_handle_mat = StandardMaterial3D.new()
		_handle_mat.albedo_color = Color(0.2, 0.22, 0.25)
		_handle_mat.roughness = 0.6
	var root := Node3D.new()
	root.name = "Scalpel"
	var blade := MeshInstance3D.new()
	blade.mesh = _blade_mesh
	blade.material_override = _blade_mat
	blade.position = Vector3(0.0, 0.0, 0.05)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(blade)
	var handle := MeshInstance3D.new()
	handle.mesh = _handle_mesh
	handle.material_override = _handle_mat
	handle.position = Vector3(0.0, 0.0, -0.1)
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(handle)
	return root
