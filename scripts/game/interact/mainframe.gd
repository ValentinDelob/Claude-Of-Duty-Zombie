class_name TeleporterMainframe
extends Interactable
## Poste central du téléporteur (`mainframe` de MapLayout.teleporter()) :
## disque au sol (façon Kino der Toten) ou, à défaut, armoire murale de
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
	# Armoire cubique (cadrans, tubes à vide et voyant lumineux selon la liaison).
	_tube_mat = PropBuilder._emissive(Color(1.0, 0.45, 0.15), 0.4)
	_lamp_mat = PropBuilder._emissive(Color(1.0, 0.1, 0.05), 3.0)
	build_model(self, "poste_central_mur", _tube_mat, _lamp_mat)
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


## Modèle CUBIQUE (tools/blender/voxel_props/objets.py, cubes de 5 cm) sous
## `root` : « poste_central_mur » (armoire, tubes, voyant) ou
## « poste_central_sol » (socle, anneau, voyant ; câble rendu à part). Les
## pièces lumineuses prennent `tube_mat` (tubes, anneau) et `lamp_mat`
## (voyant). Rend les pièces {nom: MeshInstance3D}.
static func build_model(root: Node3D, obj: String, tube_mat: Material, lamp_mat: Material) -> Dictionary:
	var parts := VoxelBuild.parts(obj)
	for part: String in parts:
		if part == "cable":
			continue
		var mi: MeshInstance3D = parts[part]
		if part in ["tubes", "anneau"]:
			mi.material_override = tube_mat
		elif part == "voyant":
			mi.material_override = lamp_mat
		root.add_child(mi)
	return parts


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


## Disque du hall : socle CUBIQUE à bord en marches de cubes (la collision
## garde son bord incliné, ~32° : on y monte sans marche), plateau d'acier
## peint, anneau de lampes à fleur (lueur selon la liaison), voyant central,
## câble épais au sol vers la salle de théâtre (direction `_normal`).
func _build_floor_pad() -> void:
	# Anneau (lueur selon la liaison) et voyant central (rouge : non relié,
	# clignote : plateforme activée, vert : relié).
	_tube_mat = PropBuilder._emissive(Color(1.0, 0.45, 0.15), 0.4)
	_lamp_mat = PropBuilder._emissive(Color(1.0, 0.1, 0.05), 3.0)
	var parts := build_model(self, "poste_central_sol", _tube_mat, _lamp_mat)
	# Câble du téléporteur, posé au sol (pavé de 6 m le long de z local).
	var cable: MeshInstance3D = parts.get("cable")
	if cable:
		cable.top_level = true
		add_child(cable)
		var dir := Vector3(_normal.x, 0.0, _normal.z).normalized()
		cable.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP),
				global_position + dir * (PAD_BOTTOM_RADIUS + 2.9))
	# Collision du socle : tronc de cône d'avant la conversion cubique.
	var cm := CylinderMesh.new()
	cm.top_radius = PAD_TOP_RADIUS
	cm.bottom_radius = PAD_BOTTOM_RADIUS
	cm.height = PAD_HEIGHT
	cm.radial_segments = 40
	cm.rings = 1
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
