class_name TeleporterMainframe
extends Interactable
## Poste central du téléporteur (KINO, `mainframe` de MapLayout.teleporter()) :
## disque au sol du hall (Kino der Toten) ou, à défaut, armoire murale de
## lampes et de cadrans. Relie la plateforme activée sur la scène ; les
## voyageurs reviennent dessus. L'état fait foi dans Teleporter (serveur).

var teleporter: Teleporter
var _normal := Vector3.FORWARD
var _lamp_mat: StandardMaterial3D
var _tube_mat: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0
## Kino der Toten : disque bas au centre du hall (on monte dessus), au lieu
## d'une armoire murale.
var floor_pad := false
const PAD_TOP_RADIUS := 1.75
const PAD_BOTTOM_RADIUS := 2.2
const PAD_HEIGHT := 0.28


func setup_marker(m: MapMarker) -> void:
	interact_id = "mainframe"
	name = "Mainframe"
	_normal = m.wall
	floor_pad = bool(m.data.get("floor", false))
	position = m.pos if floor_pad else m.pos + _normal * 0.12
	interact_range = 2.8 if floor_pad else 2.2


## Où arrivent les joueurs au retour de la salle de projection.
func arrival_point() -> Vector3:
	if floor_pad:
		return position + Vector3.UP * (PAD_HEIGHT + 0.05)
	return position - _normal * 1.6


func _ready() -> void:
	if floor_pad:
		_build_floor_pad()
		system.game.power_changed.connect(func(_on): refresh())
		refresh()
		return
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	var steel := WorldLook.surface("steel")
	var door := WorldLook.surface("door")
	_part(Vector3(2.2, 2.3, 0.7), Vector3(0, 1.15, 0), door)
	_part(Vector3(2.3, 0.1, 0.8), Vector3(0, 2.35, 0), steel)
	_part(Vector3(2.0, 0.9, 0.08), Vector3(0, 1.6, 0.36), steel)
	# Cadrans.
	var dial_mat := StandardMaterial3D.new()
	dial_mat.albedo_color = Color(0.8, 0.75, 0.6)
	dial_mat.emission_enabled = true
	dial_mat.emission = Color(0.9, 0.8, 0.5)
	dial_mat.emission_energy_multiplier = 0.06
	for k in 4:
		var d := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.12
		cm.height = 0.04
		cm.radial_segments = 12
		d.mesh = cm
		d.material_override = dial_mat
		d.rotation.x = PI * 0.5
		d.position = Vector3(-0.72 + k * 0.48, 1.75, 0.41)
		add_child(d)
	# Tubes à vide (lueur selon la liaison) et voyant principal.
	_tube_mat = PropBuilder._emissive(Color(1.0, 0.45, 0.15), 0.4)
	for k in 6:
		var tube := MeshInstance3D.new()
		var tm := CapsuleMesh.new()
		tm.radius = 0.05
		tm.height = 0.26
		tm.radial_segments = 8
		tm.rings = 2
		tube.mesh = tm
		tube.material_override = _tube_mat
		tube.position = Vector3(-0.75 + k * 0.3, 1.25, 0.42)
		add_child(tube)
	_lamp_mat = PropBuilder._emissive(Color(1.0, 0.1, 0.05), 3.0)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	lamp.mesh = sm
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(0, 2.15, 0.36)
	add_child(lamp)
	# Câbles vers le plafond.
	for x in [-0.8, -0.3, 0.4, 0.85]:
		var cable := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.03
		cm.height = 3.0
		cm.radial_segments = 6
		cable.mesh = cm
		cable.material_override = WorldLook.surface("barrel")
		cable.position = Vector3(x, 3.8, -0.2)
		add_child(cable)
	var label := Label3D.new()
	label.text = Lang.t("POSTE CENTRAL", "MAINFRAME")
	label.font = UiStyle.font("stencil")
	label.font_size = 44
	label.pixel_size = 0.004
	label.modulate = Color(0.85, 0.7, 0.35)
	label.position = Vector3(0, 0.75, 0.37)
	add_child(label)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.6, 0.9)
	add_child(_light)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")  # impacts de balles (Fx.surface_at)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 2.4, 0.75)
	cs.shape = shape
	cs.position.y = 1.2
	body.add_child(cs)
	add_child(body)
	system.game.power_changed.connect(func(_on): refresh())
	refresh()


func _part(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func refresh() -> void:
	if _lamp_mat == null or teleporter == null:
		return
	var on := system.game.power_on
	var linked := teleporter.link == Teleporter.Link.LINKED
	_lamp_mat.emission = Color(0.1, 1.0, 0.25) if linked else Color(1.0, 0.1, 0.05)
	_tube_mat.emission_energy_multiplier = (3.0 if linked else 1.2) if on else 0.1
	_light.light_energy = (0.9 if linked else 0.4) if on else 0.0


func _process(delta: float) -> void:
	if _lamp_mat == null or teleporter == null:
		return
	_t += delta
	# Plateforme activée : le voyant clignote en attendant la liaison.
	if teleporter.link == Teleporter.Link.PRIMED and system.game.power_on:
		_lamp_mat.emission_energy_multiplier = 5.0 if fmod(_t, 0.6) < 0.3 else 0.5
	else:
		_lamp_mat.emission_energy_multiplier = 3.0


func interact_point() -> Vector3:
	if floor_pad:
		return global_position + Vector3.UP * 1.0
	return global_position - _normal * 0.6 + Vector3.UP * 1.2


func prompt(_pid: int) -> String:
	if teleporter == null or teleporter.state != Teleporter.State.IDLE:
		return ""
	if not system.game.power_on:
		return Interactable.need_power_text()
	match teleporter.link:
		Teleporter.Link.UNLINKED:
			return Lang.t("Activez d'abord la plateforme du téléporteur (scène)", "Activate the teleporter pad first (stage)")
		Teleporter.Link.PRIMED:
			return Lang.t("[F] Relier le téléporteur", "[F] Link the teleporter")
	return ""


func srv_use(pid: int) -> void:
	if teleporter:
		teleporter.srv_link(pid)


## Disque du hall : socle à bord incliné (~32° : on y monte sans marche),
## plateau sombre, anneau de lampes selon la liaison, câble épais au sol
## vers la salle de théâtre (direction `_normal`).
func _build_floor_pad() -> void:
	var steel := WorldLook.surface("steel")
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = PAD_TOP_RADIUS
	cm.bottom_radius = PAD_BOTTOM_RADIUS
	cm.height = PAD_HEIGHT
	cm.radial_segments = 40
	cm.rings = 1
	base.mesh = cm
	base.material_override = WorldLook.surface("door")
	base.position.y = PAD_HEIGHT * 0.5
	add_child(base)
	var plate := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = PAD_TOP_RADIUS * 0.62
	pm.bottom_radius = PAD_TOP_RADIUS * 0.62
	pm.height = 0.03
	pm.radial_segments = 32
	plate.mesh = pm
	plate.material_override = steel
	plate.position.y = PAD_HEIGHT + 0.01
	add_child(plate)
	# Anneau de lampes (lueur selon la liaison).
	_tube_mat = PropBuilder._emissive(Color(1.0, 0.45, 0.15), 0.4)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = PAD_TOP_RADIUS * 0.66
	tm.outer_radius = PAD_TOP_RADIUS * 0.74
	tm.rings = 40
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = _tube_mat
	ring.position.y = PAD_HEIGHT + 0.005
	ring.scale.y = 0.3
	add_child(ring)
	# Voyant central (rouge : non relié, clignote : plateforme activée, vert : relié).
	_lamp_mat = PropBuilder._emissive(Color(1.0, 0.1, 0.05), 3.0)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.14
	sm.is_hemisphere = true
	lamp.mesh = sm
	lamp.material_override = _lamp_mat
	lamp.position.y = PAD_HEIGHT + 0.02
	add_child(lamp)
	# Câble du téléporteur, posé au sol.
	var cable := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.09
	cc.bottom_radius = 0.09
	cc.height = 6.0
	cc.radial_segments = 8
	cable.mesh = cc
	cable.material_override = WorldLook.surface("barrel")
	cable.top_level = true
	add_child(cable)
	var dir := Vector3(_normal.x, 0.0, _normal.z).normalized()
	cable.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5),
			global_position + dir * (PAD_BOTTOM_RADIUS + 2.9) + Vector3.UP * 0.09)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)
	# Collision : le socle (bord incliné praticable), impacts métalliques.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	var cs := CollisionShape3D.new()
	cs.shape = cm.create_convex_shape()
	cs.position.y = PAD_HEIGHT * 0.5
	body.add_child(cs)
	add_child(body)
