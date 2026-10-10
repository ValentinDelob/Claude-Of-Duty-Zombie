class_name BoxModel
extends RefCounted
## Apparence de la caisse au hasard (ancienne boîte mystère) : caisse de
## matériel CUBIQUE (cubes de 5 cm, GAME_CONCEPT.md § 4.19) peinte olive,
## cerclée d'acier, dé peint sur le couvercle, modélisée sous Blender
## (tools/blender/voxel_props/objets.py « boite » ->
## assets/models/props/voxel/objets/boite.glb ; pièces coffre, couvercle,
## intérieur, fond) ; colonne de lumière douce en pavé
## (assets/shaders/box_beam.gdshader). Partagé par la caisse du jeu et
## l'aperçu de l'éditeur (même MysteryBox). La collision reste celle de
## MysteryBox.

const OBJ := "boite"
const MODEL_PATH := VoxelBuild.OBJ_DIR + OBJ + ".glb"
const GLOW_SHADER := preload("res://assets/shaders/voxel_glow.gdshader")
const BEAM_SHADER := preload("res://assets/shaders/box_beam.gdshader")
## Lueur de chaque pièce qui s'allume à l'ouverture (paramètre « open »).
const GLOW_ENERGY := {"fond": 2.4, "interieur": 0.12}

static var _materials := {}
static var _beam_mat: ShaderMaterial
static var _haze_mat: ShaderMaterial


## Construit le modèle sous `root` (nœud « Model ») ; le couvercle va sous
## `lid` (pivot de la charnière). Renvoie les maillages qui suivent
## l'ouverture (paramètre d'instance « open »), vide si le modèle manque.
static func build(root: Node3D, lid: Node3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var parts := VoxelBuild.parts(OBJ)
	if parts.is_empty():
		return out
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	for part: String in parts:
		var mi: MeshInstance3D = parts[part]
		if part == "couvercle":
			# Même place, mais rattaché au pivot du couvercle.
			VoxelBuild.attach(lid, mi, lid.position)
			continue
		model.add_child(mi)
		if GLOW_ENERGY.has(part):
			mi.material_override = material(part)
			out.append(mi)
	return out


## Matière d'une pièce qui s'allume (partagée par toutes les caisses ;
## l'ouverture passe par le paramètre d'instance « open »).
static func material(part: String) -> ShaderMaterial:
	if _materials.has(part):
		return _materials[part]
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("glow_color", MysteryBox.GLOW_COLOR)
	m.set_shader_parameter("glow_energy", float(GLOW_ENERGY.get(part, 1.0)))
	_materials[part] = m
	return m


## Colonne de lumière : pavé ouvert de 2 × BEAM_RADIUS de côté (additif, bords
## et sommet fondus), sur la grille de 5 cm.
static func build_beam() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var bm := BoxMesh.new()
	bm.size = Vector3(MysteryBox.BEAM_RADIUS * 2.0, MysteryBox.BEAM_HEIGHT, MysteryBox.BEAM_RADIUS * 2.0)
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


## Halo doré qui monte du coffre ouvert (même shader, plus court, à la forme
## de l'ouverture, visible de près) ; paramètre d'instance « fade » = ouverture.
static func build_haze() -> MeshInstance3D:
	var haze := MeshInstance3D.new()
	haze.name = "Haze"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, MysteryBox.HAZE_HEIGHT, 0.7)
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
	# Pied dans le coffre (fond à 0,15 m), sur la grille de 5 cm.
	haze.position = Vector3(0, 0.55 + MysteryBox.HAZE_HEIGHT * 0.5, 0)
	haze.set_instance_shader_parameter("fade", 0.0)
	haze.visible = false
	return haze
