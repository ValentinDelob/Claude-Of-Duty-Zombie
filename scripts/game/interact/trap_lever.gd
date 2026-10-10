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
	mount_height = 1.3  # au mur : son niveau est 1,3 m plus bas (InteractionSystem.same_level)
	interact_range = 1.9


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	# Même panneau cubique que le piège (levier fixe, voyant).
	_lamp_mat = PropBuilder._emissive(Color(1.0, 0.1, 0.05), 3.0)
	ElectricTrap.build_panel(self, _lamp_mat)


func _process(_delta: float) -> void:
	var is_ready := system != null and system.game.power_on and trap.state == ElectricTrap.State.IDLE
	_lamp_mat.emission = Color(0.1, 1.0, 0.2) if is_ready else Color(1.0, 0.1, 0.05)


func interact_point() -> Vector3:
	return global_position - _normal * 0.35


func prompt(pid: int) -> String:
	return trap.prompt(pid)


func srv_use(pid: int) -> void:
	trap.srv_use(pid)
