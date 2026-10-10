class_name ElectricTrap
extends Interactable
## Piège électrique : un levier (H) électrifie une portion de couloir (E).
##
## Serveur : actif 25 s, puis recharge 45 s. Tout zombie qui entre dans la
## zone est foudroyé (aucun point : le piège a été payé), les joueurs y
## perdent de la santé.

enum State { IDLE, ACTIVE, COOLDOWN }

const COST := 1000
const ACTIVE_TIME := 25.0
const COOLDOWN_TIME := 45.0
const PLAYER_DAMAGE := 40
const PLAYER_TICK := 0.5

var state: State = State.IDLE
var trap_cells: Dictionary = {}  # Vector2i -> true
var activator := 0
var _timer := 0.0
var _hurt_t: Dictionary = {}
var _normal := Vector3.FORWARD
## Durées du piège (Kino der Toten : 40 s actif, 60 s de recharge).
var active_time := ACTIVE_TIME
var cooldown_time := COOLDOWN_TIME
var _area := AABB()
var _area_min := Vector3.ZERO
var _area_max := Vector3.ZERO
## Zone tournée (cartes de l'éditeur) : `_area` est donnée avant rotation,
## tournée de `_yaw` autour de son centre (0 : zone alignée sur les axes).
var _yaw := 0.0
var _center := Vector3.ZERO
var _lamp_mat: StandardMaterial3D
## Arcs en chaînes de cubes de 5 cm (VoxelFx), en coordonnées monde.
var _bolts: MultiMeshInstance3D
var _imesh: MultiMesh
const BOLTS := 7
const BOLT_CUBES := 96
const BOLT_CUBE := 0.05
var _bolt_t := 0.0
var _lights: Array[OmniLight3D] = []
var _hum: AudioStreamPlayer3D


## Levier `m` (plaqué au mur) ; m.data.area = volume électrifié (AABB, bas au
## niveau du sol) ; m.data.cells = cellules de la zone sur une carte grille.
func setup_marker(m: MapMarker) -> void:
	interact_id = m.id
	name = "ElectricTrap" if m.id == "trap" else "ElectricTrap_" + m.id
	for c in m.data.get("cells", []):
		trap_cells[c] = true
	_normal = m.wall
	position = m.on_wall(0.12, 1.3)
	mount_height = 1.3  # au mur : son niveau est 1,3 m plus bas (InteractionSystem.same_level)
	interact_range = 1.9
	active_time = float(m.data.get("active", ACTIVE_TIME))
	cooldown_time = float(m.data.get("cooldown", COOLDOWN_TIME))
	_area = m.data.area
	_yaw = float(m.data.get("yaw", 0.0))
	_center = _area.get_center()
	# Rectangle au sol (y = sol de la zone).
	_area_min = _area.position
	_area_max = Vector3(_area.end.x, _area.position.y, _area.end.z)


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	_lamp_mat = PropBuilder._emissive(Color(0.9, 0.1, 0.05), 3.0)
	build_panel(self, _lamp_mat)
	var label := Label3D.new()
	label.text = "DANGER\n%d" % COST
	label.font = UiStyle.font("stencil")
	label.font_size = 40
	label.pixel_size = 0.004
	label.modulate = Color(0.85, 0.7, 0.2)
	label.position = Vector3(0, -0.12, 0.06)
	add_child(label)
	# Émetteurs sur les murs de la zone + arcs dessinés à la volée.
	_imesh = VoxelFx.chain_multimesh(BOLTS * BOLT_CUBES)
	_bolts = MultiMeshInstance3D.new()
	_bolts.multimesh = _imesh
	_bolts.material_override = VoxelFx.material("add", {"max": BOLT_CUBE, "shrink": false, "energy": 3.0, "tint": Color(0.7, 0.85, 1.0)})
	_bolts.custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 200, 1000))
	_bolts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolts.top_level = true
	add_child(_bolts)
	_bolts.global_transform = Transform3D.IDENTITY
	var center := (_area_min + _area_max) * 0.5
	for k in 2:
		var l := OmniLight3D.new()
		l.light_color = Color(0.55, 0.75, 1.0)
		l.omni_range = 6.0
		l.light_energy = 0.0
		l.top_level = true
		add_child(l)
		l.global_position = _rotate(center + Vector3((k - 0.5) * 1.5, 1.6, 0))
		_lights.append(l)
	_hum = AudioStreamPlayer3D.new()
	_hum.bus = "SFX"
	_hum.unit_size = 5.0
	_hum.max_distance = 30.0
	_hum.top_level = true
	add_child(_hum)
	_hum.global_position = center + Vector3.UP * 1.5
	system.game.power_changed.connect(func(_on): _refresh_lamp())
	_refresh_lamp()


## Panneau CUBIQUE d'un levier de piège (tools/blender/voxel_props/objets.py
## « levier_piege », cubes de 5 cm) sous `root` (origine au milieu, à 12 cm
## du mur, +z vers la pièce) : boîtier à cadre jaune et noir, levier fixe,
## voyant au matériau `lamp_mat` (vert : prêt, rouge sinon). Rend le voyant.
static func build_panel(root: Node3D, lamp_mat: Material) -> MeshInstance3D:
	var parts := VoxelBuild.parts("levier_piege")
	if parts.has("panneau"):
		root.add_child(parts.panneau)
	var lamp: MeshInstance3D = parts["voyant"] if parts.has("voyant") else MeshInstance3D.new()
	lamp.material_override = lamp_mat
	root.add_child(lamp)
	return lamp


func _refresh_lamp() -> void:
	var is_ready := system.game.power_on and state == State.IDLE
	_lamp_mat.emission = Color(0.1, 1.0, 0.2) if is_ready else Color(1.0, 0.1, 0.05)


func interact_point() -> Vector3:
	return global_position - _normal * 0.35


func prompt(_pid: int) -> String:
	if state != State.IDLE:
		return ""
	if not system.game.power_on:
		return Interactable.need_power_text()
	return Lang.t("[F] Activer le piège électrique %s", "[F] Activate the electric trap %s") % Interactable.cost_text(COST)


func srv_use(pid: int) -> void:
	if state != State.IDLE:
		return
	if not system.game.power_on:
		system.deny(pid, InteractionSystem.NO_POWER)
		return
	if not system.game.session.try_spend(pid, COST):
		system.deny(pid, InteractionSystem.NO_POINTS)
		return
	system.purchase_fx(self)
	activator = pid
	VoxSystem.say(pid, "trap_on", 0.8)
	_timer = active_time
	_hurt_t.clear()
	state = State.ACTIVE
	broadcast_state()


func contains(pos: Vector3) -> bool:
	if not trap_cells.is_empty():
		return trap_cells.has(MapData.world_to_cell(pos))
	return _area.grow(0.05).has_point(_unrotate(pos) + Vector3.UP * 0.1)


## Point du monde ramené dans le repère de la zone avant rotation.
func _unrotate(pos: Vector3) -> Vector3:
	if _yaw == 0.0:
		return pos
	return _center + Basis(Vector3.UP, -_yaw) * (pos - _center)


## Point du repère de la zone (avant rotation) -> monde.
func _rotate(p: Vector3) -> Vector3:
	if _yaw == 0.0:
		return p
	return _center + Basis(Vector3.UP, _yaw) * (p - _center)


func _process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server() or state == State.IDLE:
		return
	_timer -= delta
	if state == State.ACTIVE:
		var game := system.game
		for z: Zombie in game.zombies.alive.duplicate():
			if z.state != Zombie.State.EMERGE and contains(z.global_position):
				game.combat.damage_zombie(z.id, 1000000, activator, false, Vector3.UP, Combat.HitKind.TRAP)
				_cl_zap.rpc(z.global_position + Vector3.UP)
		for p: Player in game.players.values():
			if contains(p.global_position):
				var t: float = _hurt_t.get(p.peer_id, 0.0) - delta
				if t <= 0.0:
					t = PLAYER_TICK
					game.combat.damage_player(p.peer_id, PLAYER_DAMAGE, p.global_position + Vector3.UP)
				_hurt_t[p.peer_id] = t
			else:
				_hurt_t.erase(p.peer_id)
	if _timer <= 0.0:
		if state == State.ACTIVE:
			state = State.COOLDOWN
			_timer = cooldown_time
		else:
			state = State.IDLE
		broadcast_state()


@rpc("authority", "call_local", "reliable")
func _cl_zap(pos: Vector3) -> void:
	system.game.fx_root.sparks.burst(pos, Vector3.UP, 16, 5.0, 1.0, 0.5, Color(0.6, 0.8, 1.0))
	Audio.play_3d("zap", pos, 0.0, 0.1, 4)


func get_state() -> Dictionary:
	return {"state": state}


func apply_state(s: Dictionary, _animated: bool) -> void:
	state = s.get("state", State.IDLE)
	if state == State.ACTIVE:
		_hum.stream = Audio.get_stream("trap_hum")
		_hum.play()
	else:
		_hum.stop()
	_refresh_lamp()


func _animate(delta: float) -> void:
	if _imesh == null:
		return
	var active := state == State.ACTIVE
	for l in _lights:
		l.light_energy = (randf_range(1.5, 4.0) if randf() < 0.7 else 0.3) if active else 0.0
	_bolt_t -= delta
	if _bolt_t > 0.0:
		return
	_bolt_t = 0.05
	_imesh.visible_instance_count = 0
	if not active:
		return
	# Arcs en zigzag d'un mur à l'autre, régénérés 20 fois par seconde : chaînes
	# de cubes de 5 cm le long de chaque ligne brisée.
	var across_z := (_area_max.z - _area_min.z) < (_area_max.x - _area_min.x)
	var used := 0
	var pts := PackedVector3Array()
	for k in BOLTS:
		var t := randf()
		var h := _area_min.y + randf_range(0.2, 2.6)
		var a: Vector3
		var b: Vector3
		if across_z:
			var x := lerpf(_area_min.x, _area_max.x, t)
			a = Vector3(x, h, _area_min.z)
			b = Vector3(x + randf_range(-0.5, 0.5), h + randf_range(-0.5, 0.5), _area_max.z)
		else:
			var z := lerpf(_area_min.z, _area_max.z, t)
			a = Vector3(_area_min.x, h, z)
			b = Vector3(_area_max.x, h + randf_range(-0.5, 0.5), z + randf_range(-0.5, 0.5))
		pts.clear()
		pts.append(_rotate(a))
		for s in range(1, 9):
			var p := a.lerp(b, s / 8.0)
			if s < 8:
				p += Vector3(randf_range(-0.15, 0.15), randf_range(-0.2, 0.2), randf_range(-0.15, 0.15))
			pts.append(_rotate(p))
		var mm_end := mini(used + BOLT_CUBES, _imesh.instance_count)
		used += VoxelFx.fill_chain(_imesh, pts, BOLT_CUBE, Vector3.ONE, used, mm_end)
	_imesh.visible_instance_count = used
