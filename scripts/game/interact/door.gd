class_name Door
extends Node3D
## Porte blindée entre deux zones. Construite de façon déterministe à partir
## des cellules d'un marqueur chiffré de la carte.

const SLAB_THICKNESS := 0.22
const OPEN_TIME := 1.6

var door_id := ""
var cells: Array = []
var cost := 0
var is_open := false
## Zones reliées par la porte.
var zones: Array = []

var _slab: Node3D
var _body: StaticBody3D
var _size := Vector3.ONE
var _along_z := false


func setup(id: String, door_cells: Array, door_cost: int, data: MapData) -> void:
	door_id = id
	cells = door_cells
	cost = door_cost
	name = "Door" + id
	var minc := Vector2i(999, 999)
	var maxc := Vector2i(-999, -999)
	for c in cells:
		minc = Vector2i(mini(minc.x, c.x), mini(minc.y, c.y))
		maxc = Vector2i(maxi(maxc.x, c.x), maxi(maxc.y, c.y))
	# Porte dans un mur « vertical » (x constant) si les voisins en X sont du sol.
	var probe: Vector2i = cells[0]
	_along_z = data.is_floor(Vector2i(minc.x - 1, probe.y)) and data.is_floor(Vector2i(maxc.x + 1, probe.y))
	var span := (maxc - minc) + Vector2i.ONE
	var width := float(span.y if _along_z else span.x) * MapData.CELL
	_size = Vector3(width, MapBuilder.WALL_HEIGHT, SLAB_THICKNESS)
	position = (MapData.cell_to_world(minc) + MapData.cell_to_world(maxc)) * 0.5
	rotation.y = PI * 0.5 if _along_z else 0.0
	# Zones de part et d'autre.
	var side_a := minc - (Vector2i(1, 0) if _along_z else Vector2i(0, 1))
	var side_b := maxc + (Vector2i(1, 0) if _along_z else Vector2i(0, 1))
	zones = []
	for c in [side_a, side_b]:
		var z := data.zone_at(c)
		if z != "" and not z in zones:
			zones.append(z)


func _ready() -> void:
	_slab = Node3D.new()
	_slab.name = "Slab"
	add_child(_slab)
	var mat := WorldLook.surface("door")
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = _size
	slab.mesh = bm
	slab.material_override = mat
	slab.position.y = _size.y * 0.5
	_slab.add_child(slab)
	# Bandes d'avertissement jaunes et noires.
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_texture = _stripes_texture()
	stripe_mat.roughness = 0.8
	stripe_mat.uv1_scale = Vector3(_size.x * 1.5, 1, 1)
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(_size.x - 0.05, 0.28, _size.z + 0.02)
	stripe.mesh = sm
	stripe.material_override = stripe_mat
	stripe.position.y = 1.0
	_slab.add_child(stripe)
	# Poignée / volant de verrouillage.
	for side in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18
		cm.bottom_radius = 0.18
		cm.height = 0.05
		cm.radial_segments = 10
		wheel.mesh = cm
		wheel.material_override = WorldLook.surface("steel")
		wheel.rotation.x = PI * 0.5
		wheel.position = Vector3(0, 1.45, side * (_size.z * 0.5 + 0.03))
		_slab.add_child(wheel)

	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size.x, _size.y, 0.9)
	cs.shape = box
	cs.position.y = _size.y * 0.5
	_body.add_child(cs)
	add_child(_body)


## Ouvre la porte (toutes les machines). La navigation est gérée par le serveur.
func set_open(open: bool, animate := true) -> void:
	if open == is_open:
		return
	is_open = open
	_body.process_mode = Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT
	(_body.get_child(0) as CollisionShape3D).disabled = open
	var target_y := MapBuilder.WALL_HEIGHT - 0.1 if open else 0.0
	if animate:
		var tw := create_tween()
		tw.tween_property(_slab, "position:y", target_y, OPEN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		if open:
			tw.tween_callback(func(): _slab.visible = false)
	else:
		_slab.position.y = target_y
		_slab.visible = not open


func interact_position() -> Vector3:
	return global_position + Vector3.UP * 1.2


static var _stripes: Texture2D


static func _stripes_texture() -> Texture2D:
	if _stripes:
		return _stripes
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var s := fmod(float(x + y), 32.0) < 16.0
			var c := Color(0.75, 0.6, 0.08) if s else Color(0.05, 0.05, 0.04)
			img.set_pixel(x, y, c * (0.8 + 0.2 * randf()))
	_stripes = ImageTexture.create_from_image(img)
	return _stripes
