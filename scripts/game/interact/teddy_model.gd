class_name TeddyModel
extends RefCounted
## Nounours de la boîte mystère (BO1) : ours en peluche assis, fourrure brune
## usée, museau et coussinets clairs, yeux-boutons, nœud rouge au cou, couture
## sur le ventre et une pièce rapiécée. Modèle procédural (sphères et
## capsules) ; face vers +Z (vers le joueur devant la boîte), assis sur y = 0,
## environ 0,5 m de haut.

const FUR := Color(0.42, 0.26, 0.13)
const FUR_LIGHT := Color(0.74, 0.57, 0.38)
const RIBBON := Color(0.55, 0.06, 0.05)
const HEIGHT := 0.5

static var _mats := {}


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Teddy"
	var fur := _fur(FUR)
	var light := _fur(FUR_LIGHT)
	var patch := _fur(Color(0.33, 0.3, 0.22))
	var button := _plain("button", Color(0.03, 0.025, 0.02), 0.15)
	var nose := _plain("nose", Color(0.07, 0.04, 0.03), 0.45)
	var ribbon := _plain("ribbon", RIBBON, 0.55)
	var thread := _plain("thread", Color(0.12, 0.07, 0.04), 0.9)

	# Corps en poire, ventre clair et couture verticale.
	_blob(root, _sphere(0.125, 0.29), Vector3(0, 0.175, 0), fur, Vector3.ZERO, Vector3(1.0, 1.0, 0.9))
	_blob(root, _sphere(0.085, 0.19), Vector3(0, 0.16, 0.055), light, Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
	_blob(root, _box(Vector3(0.004, 0.12, 0.004)), Vector3(0, 0.165, 0.108), thread, Vector3(-0.12, 0, 0))
	for i in 4:
		_blob(root, _box(Vector3(0.018, 0.003, 0.003)), Vector3(0, 0.12 + i * 0.03, 0.105 + i * 0.003), thread)
	# Jambes tendues vers l'avant, coussinets clairs sous les pieds.
	for side in [-1.0, 1.0]:
		_blob(root, _capsule(0.05, 0.17), Vector3(side * 0.07, 0.05, 0.07), fur, Vector3(PI * 0.5 - 0.15, side * 0.18, 0))
		_blob(root, _sphere(0.038, 0.076), Vector3(side * 0.085, 0.06, 0.155), light, Vector3(0, side * 0.18, 0), Vector3(1.0, 1.15, 0.3))
	# Bras le long du corps, un peu en avant.
	for side in [-1.0, 1.0]:
		_blob(root, _capsule(0.038, 0.16), Vector3(side * 0.125, 0.2, 0.03), fur, Vector3(-0.35, 0, side * 0.55))
		_blob(root, _sphere(0.028, 0.056), Vector3(side * 0.16, 0.14, 0.065), light, Vector3.ZERO, Vector3(1.0, 1.0, 0.5))
	# Pièce rapiécée sur l'épaule gauche (points de couture aux coins).
	_blob(root, _box(Vector3(0.06, 0.05, 0.006)), Vector3(-0.07, 0.25, 0.085), patch, Vector3(-0.35, -0.45, 0.2))
	# Tête : crâne rond, joues, museau clair, truffe et bouche cousue.
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.375, 0.01)
	head.rotation = Vector3(0, 0, 0.1)
	root.add_child(head)
	_blob(head, _sphere(0.115), Vector3.ZERO, fur, Vector3.ZERO, Vector3(1.0, 0.92, 0.95))
	_blob(head, _sphere(0.055, 0.09), Vector3(0, -0.035, 0.085), light, Vector3.ZERO, Vector3(1.0, 0.85, 0.85))
	_blob(head, _sphere(0.022, 0.03), Vector3(0, -0.02, 0.135), nose, Vector3.ZERO, Vector3(1.3, 1.0, 0.8))
	_blob(head, _box(Vector3(0.003, 0.025, 0.003)), Vector3(0, -0.045, 0.128), thread)
	for side in [-1.0, 1.0]:
		_blob(head, _box(Vector3(0.022, 0.003, 0.003)), Vector3(side * 0.009, -0.058, 0.122), thread, Vector3(0, 0, side * 0.5))
	# Yeux-boutons : l'un un peu plus haut, l'autre recousu de travers.
	_blob(head, _cyl(0.016, 0.008), Vector3(-0.042, 0.022, 0.098), button, Vector3(PI * 0.5 - 0.35, 0, 0))
	_blob(head, _cyl(0.015, 0.008), Vector3(0.044, 0.015, 0.099), button, Vector3(PI * 0.5 - 0.35, 0.2, 0))
	for side in [-1.0, 1.0]:
		_blob(head, _box(Vector3(0.012, 0.002, 0.002)), Vector3(0.044, 0.015, 0.104), thread, Vector3(0, 0, side * 0.785))
	# Oreilles rondes et aplaties, intérieur clair.
	for side in [-1.0, 1.0]:
		var ear := Vector3(side * 0.085, 0.085, -0.01)
		var tilt := Vector3(0, 0, -side * 0.45)
		_blob(head, _sphere(0.042), ear, fur, tilt, Vector3(1.0, 1.0, 0.45))
		_blob(head, _sphere(0.026), ear + Vector3(0, -0.004, 0.014), light, tilt, Vector3(1.0, 1.0, 0.3))
	# Nœud rouge au cou : collier, deux boucles et le nœud central.
	_blob(root, _torus(0.07, 0.085), Vector3(0, 0.3, 0.005), ribbon, Vector3(0.12, 0, 0))
	for side in [-1.0, 1.0]:
		_blob(root, _sphere(0.035, 0.05), Vector3(side * 0.04, 0.29, 0.1), ribbon, Vector3(0, 0, side * 0.3), Vector3(1.0, 1.0, 0.45))
	_blob(root, _sphere(0.016), Vector3(0, 0.29, 0.108), ribbon)
	return root


static func _blob(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.material_override = m
	parent.add_child(mi)
	return mi


## Peluche : très mate, liseré clair sur les bords (duvet).
static func _fur(c: Color) -> StandardMaterial3D:
	var key := "fur_%s" % c
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		m.rim_enabled = true
		m.rim = 0.6
		m.rim_tint = 0.4
		_mats[key] = m
	return _mats[key]


static func _plain(key: String, c: Color, rough: float) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		_mats[key] = m
	return _mats[key]


static func _sphere(r: float, h := -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = 20
	s.rings = 10
	return s


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 4
	return c


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 14
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 20
	t.ring_segments = 8
	return t
