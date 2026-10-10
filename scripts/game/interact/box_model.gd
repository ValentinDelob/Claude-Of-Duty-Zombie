class_name BoxModel
extends RefCounted
## Apparence de la caisse au hasard (ancienne boîte mystère) : coffre de bois usé cerclé de fer modélisé
## sous Blender (tools/blender/props/mystery_box.py ->
## assets/models/props/mystery_box.glb), points d'interrogation au pochoir
## originaux, matières procédurales (assets/shaders/mystery_box.gdshader) ;
## colonne de lumière douce (assets/shaders/box_beam.gdshader). Partagé par
## la caisse du jeu et l'aperçu de l'éditeur (même
## MysteryBox). La collision reste celle de MysteryBox.

const MODEL_PATH := "res://assets/models/props/mystery_box.glb"
const SHADER := preload("res://assets/shaders/mystery_box.gdshader")
const BEAM_SHADER := preload("res://assets/shaders/box_beam.gdshader")
## Objet du modèle -> type de matière du shader (0 bois, 1 fer, 2 laiton,
## 3 peinture, 4 intérieur, 5 fond lumineux).
const PARTS := {"wood": 0, "lid_wood": 0, "iron": 1, "lid_iron": 1, "brass": 2, "paint": 3, "inner": 4, "glow": 5}
## Petites pièces sans ombre portée (rivets, ferrures, peinture, fond).
const NO_SHADOW := ["iron", "lid_iron", "brass", "paint", "glow"]

static var _materials := {}
static var _beam_mat: ShaderMaterial
static var _haze_mat: ShaderMaterial


## Construit le modèle sous `root` ; les pièces du couvercle (« lid_* ») vont
## sous `lid` (pivot de la charnière). Renvoie les maillages qui suivent
## l'ouverture (paramètre d'instance « open »), vide si le modèle manque.
static func build(root: Node3D, lid: Node3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if not ResourceLoader.exists(MODEL_PATH):
		return out
	var scene: Node3D = (load(MODEL_PATH) as PackedScene).instantiate()
	scene.name = "Model"
	root.add_child(scene)
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var part := String(mi.name)
		if not PARTS.has(part):
			continue
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, material(part, mi.mesh.surface_get_material(s)))
		if part in NO_SHADOW:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if part.begins_with("lid_"):
			# Même place, mais rattaché au pivot du couvercle.
			var t := lid.transform.affine_inverse() * scene.transform * mi.transform
			mi.get_parent().remove_child(mi)
			lid.add_child(mi)
			mi.transform = t
		elif part == "glow" or part == "inner":
			out.append(mi)
	return out


## Matière partagée par toutes les boîtes (l'ouverture passe par le paramètre
## d'instance « open ») : couleur, rugosité et métal du .glb.
static func material(part: String, src: Material = null) -> ShaderMaterial:
	if _materials.has(part):
		return _materials[part]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("part", PARTS.get(part, 0))
	var base := src as BaseMaterial3D
	if base:
		m.set_shader_parameter("albedo", base.albedo_color)
		m.set_shader_parameter("roughness_base", base.roughness)
		m.set_shader_parameter("metallic_base", base.metallic)
	m.set_shader_parameter("glow_color", MysteryBox.GLOW_COLOR)
	m.set_shader_parameter("noise_lattice", NoiseLattice.tex2d())
	_materials[part] = m
	return m


## Colonne de lumière (cylindre ouvert, additif, bords et sommet fondus).
static func build_beam() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var bm := CylinderMesh.new()
	bm.top_radius = MysteryBox.BEAM_RADIUS * 1.25
	bm.bottom_radius = MysteryBox.BEAM_RADIUS
	bm.height = MysteryBox.BEAM_HEIGHT
	bm.radial_segments = 16
	bm.rings = 1
	bm.cap_top = false
	bm.cap_bottom = false
	beam.mesh = bm
	if _beam_mat == null:
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = BEAM_SHADER
		_beam_mat.set_shader_parameter("color", MysteryBox.BEAM_COLOR)
		_beam_mat.set_shader_parameter("intensity", MysteryBox.BEAM_INTENSITY)
		_beam_mat.set_shader_parameter("height", MysteryBox.BEAM_HEIGHT)
		_beam_mat.set_shader_parameter("noise_lattice", NoiseLattice.tex2d())
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0, MysteryBox.BEAM_BOTTOM + MysteryBox.BEAM_HEIGHT * 0.5, 0)
	return beam


## Halo doré qui monte du coffre ouvert (même shader, plus court, plus
## large, visible de près) ; paramètre d'instance « fade » = ouverture.
static func build_haze() -> MeshInstance3D:
	var haze := MeshInstance3D.new()
	haze.name = "Haze"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.5
	bm.bottom_radius = 0.4
	bm.height = MysteryBox.HAZE_HEIGHT
	bm.radial_segments = 16
	bm.rings = 1
	bm.cap_top = false
	bm.cap_bottom = false
	haze.mesh = bm
	if _haze_mat == null:
		_haze_mat = ShaderMaterial.new()
		_haze_mat.shader = BEAM_SHADER
		_haze_mat.set_shader_parameter("color", MysteryBox.GLOW_COLOR)
		_haze_mat.set_shader_parameter("intensity", MysteryBox.HAZE_INTENSITY)
		_haze_mat.set_shader_parameter("height", MysteryBox.HAZE_HEIGHT)
		_haze_mat.set_shader_parameter("near_fade", 1.0)
		_haze_mat.set_shader_parameter("far_boost", 1.0)
		_haze_mat.set_shader_parameter("noise_lattice", NoiseLattice.tex2d())
	haze.material_override = _haze_mat
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Ellipse à la forme de l'ouverture (1,75 x 0,8 m), pied dans le coffre.
	haze.scale = Vector3(2.0, 1.0, 0.95)
	haze.position = Vector3(0, 0.55 + MysteryBox.HAZE_HEIGHT * 0.5, 0)
	haze.set_instance_shader_parameter("fade", 0.0)
	haze.visible = false
	return haze
