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
var _area_min := Vector3.ZERO
var _area_max := Vector3.ZERO
var _lamp_mat: StandardMaterial3D
var _bolts: MeshInstance3D
var _imesh: ImmediateMesh
var _bolt_t := 0.0
var _lights: Array[OmniLight3D] = []
var _hum: AudioStreamPlayer3D


func setup(lever_cell: Vector2i, cells: Array, data: MapData) -> void:
	interact_id = "trap"
	name = "ElectricTrap"
	for c in cells:
		trap_cells[c] = true
	_normal = MapDef.wall_normal(data, lever_cell)
	position = MapData.cell_to_world(lever_cell) + _normal * 0.38 + Vector3.UP * 1.3
	interact_range = 1.9
	var minc := Vector2i(9999, 9999)
	var maxc := Vector2i(-9999, -9999)
	for c in cells:
		minc = Vector2i(mini(minc.x, c.x), mini(minc.y, c.y))
		maxc = Vector2i(maxi(maxc.x, c.x), maxi(maxc.y, c.y))
	_area_min = Vector3(minc.x, 0, minc.y) * MapData.CELL
	_area_max = Vector3(maxc.x + 1, 0, maxc.y + 1) * MapData.CELL


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.6, 0.15)
	box.mesh = bm
	box.material_override = WorldLook.surface("door")
	add_child(box)
	_lamp_mat = PropBuilder._emissive(Color(0.9, 0.1, 0.05), 3.0)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.05
	lm.height = 0.1
	lamp.mesh = lm
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0, 0.22, 0.08)
	add_child(lamp)
	var label := Label3D.new()
	label.text = "DANGER\n%d" % COST
	label.font = UiStyle.font("stencil")
	label.font_size = 40
	label.pixel_size = 0.004
	label.modulate = Color(0.85, 0.7, 0.2)
	label.position = Vector3(0, -0.12, 0.08)
	add_child(label)
	# Émetteurs sur les murs de la zone + arcs dessinés à la volée.
	_imesh = ImmediateMesh.new()
	_bolts = MeshInstance3D.new()
	_bolts.mesh = _imesh
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.albedo_color = Color(0.7, 0.85, 1.0)
	bolt_mat.emission_enabled = true
	bolt_mat.emission = Color(0.6, 0.8, 1.0)
	bolt_mat.emission_energy_multiplier = 6.0
	_bolts.material_override = bolt_mat
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
		l.global_position = center + Vector3((k - 0.5) * 1.5, 1.6, 0)
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


func _refresh_lamp() -> void:
	var ready := system.game.power_on and state == State.IDLE
	_lamp_mat.emission = Color(0.1, 1.0, 0.2) if ready else Color(1.0, 0.1, 0.05)


func interact_point() -> Vector3:
	return global_position - _normal * 0.35


func prompt(_pid: int) -> String:
	if state != State.IDLE:
		return ""
	if not system.game.power_on:
		return "Le courant doit être rétabli"
	return "[F] Activer le piège électrique %s" % Interactable.cost_text(COST)


func srv_use(pid: int) -> void:
	if state != State.IDLE:
		return
	if not system.game.power_on:
		system.deny(pid, "Pas de courant")
		return
	if not system.game.session.try_spend(pid, COST):
		system.deny(pid, "Pas assez de points")
		return
	system.purchase_fx(self)
	activator = pid
	_timer = ACTIVE_TIME
	_hurt_t.clear()
	state = State.ACTIVE
	broadcast_state()


func contains(pos: Vector3) -> bool:
	return trap_cells.has(MapData.world_to_cell(pos))


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
			_timer = COOLDOWN_TIME
		else:
			state = State.IDLE
		broadcast_state()


@rpc("authority", "call_local", "reliable")
func _cl_zap(pos: Vector3) -> void:
	system.game.fx_root.sparks.burst(pos, Vector3.UP, 16, 5.0, 1.0, 0.5, Color(0.6, 0.8, 1.0))
	Audio.play_3d("zap", pos, 0.0, 0.1, 4)


func get_state() -> Dictionary:
	return {"state": state}


func apply_state(s: Dictionary, _animate: bool) -> void:
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
	_imesh.clear_surfaces()
	if not active:
		return
	# Arcs en zigzag d'un mur à l'autre, régénérés 20 fois par seconde.
	var across_z := (_area_max.z - _area_min.z) < (_area_max.x - _area_min.x)
	_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in 7:
		var t := randf()
		var h := randf_range(0.2, 2.6)
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
		var prev := a
		for s in range(1, 9):
			var p := a.lerp(b, s / 8.0)
			if s < 8:
				p += Vector3(randf_range(-0.15, 0.15), randf_range(-0.2, 0.2), randf_range(-0.15, 0.15))
			_imesh.surface_add_vertex(prev)
			_imesh.surface_add_vertex(p)
			prev = p
	_imesh.surface_end()
