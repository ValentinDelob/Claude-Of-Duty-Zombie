class_name TrapLever
extends Interactable
## Second levier d'un piège (Kino der Toten : un levier à chaque bout du
## passage piégé). Transmet l'usage au piège ; son voyant suit l'état du piège.

var trap: ElectricTrap
var _normal := Vector3.FORWARD
var _lamp_mat: StandardMaterial3D


func setup(t: ElectricTrap, m: MapMarker) -> void:
	trap = t
	interact_id = t.interact_id + "_b"
	name = "TrapLever_" + t.interact_id
	_normal = m.wall
	position = m.on_wall(0.12, 1.3)
	interact_range = 1.9


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.6, 0.15)
	box.mesh = bm
	box.material_override = WorldLook.surface("door")
	add_child(box)
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.06, 0.32, 0.06)
	handle.mesh = hm
	handle.material_override = WorldLook.surface("steel")
	handle.position = Vector3(0.12, 0.05, 0.12)
	handle.rotation.x = -0.5
	add_child(handle)
	_lamp_mat = PropBuilder._emissive(Color(1.0, 0.1, 0.05), 3.0)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	lamp.mesh = sm
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(-0.12, 0.2, 0.09)
	add_child(lamp)


func _process(_delta: float) -> void:
	var ready := system != null and system.game.power_on and trap.state == ElectricTrap.State.IDLE
	_lamp_mat.emission = Color(0.1, 1.0, 0.2) if ready else Color(1.0, 0.1, 0.05)


func interact_point() -> Vector3:
	return global_position - _normal * 0.35


func prompt(pid: int) -> String:
	return trap.prompt(pid)


func srv_use(pid: int) -> void:
	trap.srv_use(pid)
