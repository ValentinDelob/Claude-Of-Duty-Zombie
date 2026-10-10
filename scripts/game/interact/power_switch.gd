class_name PowerSwitch
extends Interactable
## Levier du générateur. Une fois abaissé (gratuit, définitif), le courant est
## rétabli : pièges et téléporteur fonctionnent.

var is_on := false
var _normal := Vector3.FORWARD
var _lever: Node3D
var _beacon: OmniLight3D
var _beacon_mesh: MeshInstance3D
var _t := 0.0


func setup(cell: Vector2i, data: MapData) -> void:
	setup_marker(GridMapLayout.cell_marker("power", cell, data))


func setup_marker(m: MapMarker) -> void:
	interact_id = "power"
	name = "PowerSwitch"
	_normal = m.wall
	position = m.on_wall(0.12, 1.3)
	mount_height = 1.3  # au mur : son niveau est 1,3 m plus bas (InteractionSystem.same_level)
	interact_range = 1.9


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.95, 0.22)
	box.mesh = bm
	box.material_override = WorldLook.surface("door")
	add_child(box)
	# Câbles qui montent au plafond.
	for x in [-0.22, 0.0, 0.22]:
		var cable := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 1.5
		cm.radial_segments = 6
		cable.mesh = cm
		cable.material_override = WorldLook.surface("barrel")
		cable.position = Vector3(x, 1.2, -0.05)
		add_child(cable)
	_lever = Node3D.new()
	_lever.position = Vector3(0.0, 0.0, 0.12)
	add_child(_lever)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.06, 0.45, 0.06)
	arm.mesh = am
	arm.material_override = WorldLook.surface("steel")
	arm.position = Vector3(0, 0.22, 0.03)
	_lever.add_child(arm)
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.22, 0.07, 0.07)
	grip.mesh = gm
	grip.material_override = PropBuilder._emissive(Color(0.6, 0.05, 0.03), 0.5)
	grip.position = Vector3(0, 0.45, 0.03)
	_lever.add_child(grip)
	_lever.rotation.x = -0.5
	# Gyrophare rouge de secours tant que le courant est coupé.
	_beacon_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	_beacon_mesh.mesh = sm
	_beacon_mesh.material_override = PropBuilder._emissive(Color(1.0, 0.08, 0.03), 4.0)
	_beacon_mesh.position = Vector3(0, 0.62, 0.05)
	add_child(_beacon_mesh)
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.1, 0.05)
	_beacon.omni_range = 7.0
	_beacon.light_energy = 1.5
	_beacon.position = Vector3(0, 0.62, 0.3)
	add_child(_beacon)


func _process(delta: float) -> void:
	if is_on or _beacon == null:
		return
	_t += delta
	var k := 0.5 + 0.5 * sin(_t * 5.0)
	_beacon.light_energy = 0.3 + 1.6 * k


func interact_point() -> Vector3:
	return global_position - _normal * 0.35


func prompt(_pid: int) -> String:
	return "" if is_on else Lang.t("[F] Rétablir le courant", "[F] Turn on the power")


func srv_use(pid: int) -> void:
	if is_on:
		return
	is_on = true
	VoxSystem.say_later(1.5, pid, "power_on")
	print("[Power] courant rétabli")
	broadcast_state()


func get_state() -> Dictionary:
	return {"on": is_on}


func apply_state(state: Dictionary, animate: bool) -> void:
	var on: bool = state.get("on", false)
	if on == is_on and not animate:
		return
	is_on = on
	if not on:
		return
	_beacon.visible = false
	_beacon_mesh.visible = false
	var game := system.game
	if animate:
		var tw := create_tween()
		tw.tween_property(_lever, "rotation:x", 0.9, 0.25).set_trans(Tween.TRANS_BACK)
		Audio.play_3d("lever", interact_point(), 0.0, 0.02)
		Audio.play_2d("power_on", -2.0, 0.0)
		game.props.power.power_on_from(global_position)
		game.hud.show_banner(Lang.t("LE COURANT EST RÉTABLI", "THE POWER IS ON"))
	else:
		_lever.rotation.x = 0.9
		game.props.power.apply_immediate(true)
	game.set_power(true)
