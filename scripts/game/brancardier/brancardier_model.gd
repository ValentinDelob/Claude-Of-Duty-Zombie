class_name BrancardierModel
extends RefCounted
## Le Brancardier CUBIQUE (GAME_CONCEPT.md § 4.19 : cubes de 2,5 cm),
## modélisé dans Blender (tools/blender/brancardier/brancardier_voxel.py) et
## chargé par ZombieGlb comme le chien : un mesh skinné partagé, un draw
## call, couleur par face de cube, yeux émissifs, dissolution cube par cube
## (shaders des zombies cubiques). Ossature du jeu (RigBuilder.BONES), le
## modèle regarde vers +Z ; le brancard sanglé dans le dos est sur l'os
## `chest`. Animation : BrancardierAnim ; zones de touche mesurées sur le
## modèle (hit_shapes).

const MODEL_PATH := "res://assets/models/brancardier/brancardier_voxel.glb"
const MODEL_CUBE := 0.025
## Lueur des yeux (jaune des zombies du jeu, plus intense : mini-boss).
const EYE_EMISSION := Color(1.0, 0.82, 0.25)
const EYE_ENERGY := 9.0

static var _material: ShaderMaterial
static var _dissolve: ShaderMaterial
static var _skin: Skin
static var _bounds := {}
static var _shapes := {}


static func _mat(dissolve: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/zombie_voxel_dissolve.gdshader") if dissolve else preload("res://assets/shaders/zombie_voxel.gdshader")
	mat.set_shader_parameter("emission_color", EYE_EMISSION)
	mat.set_shader_parameter("emission_energy", EYE_ENERGY)
	mat.set_shader_parameter("voxel_cell", MODEL_CUBE)
	IllustratedStyle.bind(mat, IllustratedStyle.Kind.CHAR)
	return mat


static func material() -> ShaderMaterial:
	if _material == null:
		_material = _mat(false)
	return _material


static func dissolve_material() -> ShaderMaterial:
	if _dissolve == null:
		_dissolve = _mat(true)
	return _dissolve


## Dissolution (0 : intact, 1 : disparu).
static func set_dissolve(mi: MeshInstance3D, k: float) -> void:
	var want := dissolve_material() if k > 0.0 else material()
	if mi.material_override != want:
		mi.material_override = want
	mi.set_instance_shader_parameter("dissolve", k)


## Modèle chargé ({mesh, overrides}) ; {} si le .glb manque.
static func model() -> Dictionary:
	return ZombieGlb.load_model(MODEL_PATH)


static func build(_variant := 0) -> Skeleton3D:
	var m := model()
	if m.is_empty():
		push_error("BrancardierModel : %s introuvable" % MODEL_PATH)
		return RigBuilder.instantiate(ArrayMesh.new(), material())
	if _skin == null:
		var tmp := RigBuilder.build_skeleton(m.overrides)
		_skin = tmp.create_skin_from_rest_transforms()
		tmp.free()
		hit_shapes()
	var skel := RigBuilder.instantiate(m.mesh, material(), m.overrides, _skin)
	var mi := skel.get_node("Mesh") as MeshInstance3D
	mi.layers = ZombieModel.RENDER_LAYERS
	mi.set_instance_shader_parameter("look_tint", Color(1, 1, 1, 1))
	return skel


## Boîte englobante au repos (repère du modèle) des sommets de chaque os.
static func bone_bounds() -> Dictionary:
	if not _bounds.is_empty():
		return _bounds
	var m := model()
	if m.is_empty():
		return {}
	var a := (m.mesh as ArrayMesh).surface_get_arrays(0)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	for v in pos.size():
		var b: String = RigBuilder.BONES[bones[v * 4]][0]
		if _bounds.has(b):
			_bounds[b] = (_bounds[b] as AABB).expand(pos[v])
		else:
			_bounds[b] = AABB(pos[v], Vector3.ZERO)
	return _bounds


## Zones de touche mesurées sur le modèle (au repos) :
##   body : [centre, rayon, hauteur] d'une capsule debout (bassin, ventre et
##          poitrine ; largeur et profondeur du VENTRE : le brancard du dos,
##          sur l'os chest, n'élargit pas la cible) ;
##   head : [centre dans le repère de l'os head, rayon] (crâne et mâchoire) ;
##   height : sommet de la tête (m).
static func hit_shapes() -> Dictionary:
	if not _shapes.is_empty():
		return _shapes
	var bb := bone_bounds()
	if bb.is_empty():
		_shapes = {"body": [Vector3(0, 1.25, 0.0), 0.36, 1.1], "head": [Vector3(0, 0.15, 0.08), 0.18], "height": 2.25}
		return _shapes
	var belly: AABB = bb.spine
	var bottom: float = (bb.hips as AABB).position.y
	var top: float = (bb.neck as AABB).position.y
	# Tronc : du bas du bassin à la base du cou (le brancard du dos, sur l'os
	# chest, dépasse au-dessus : il ne compte pas).
	var r := (belly.size.x + belly.size.z) * 0.25 + MODEL_CUBE
	var h := maxf(top - bottom - 0.1, r * 2.0)
	var centre := Vector3(0.0, (bottom + top) * 0.5, belly.get_center().z)
	var head: AABB = bb.head.merge(bb.get("jaw", bb.head))
	var rest := RigBuilder._rest_globals(model().overrides)
	var head_origin: Vector3 = (rest.head as Transform3D).origin
	var hc := head.get_center() - head_origin
	var hr := maxf(head.size.x, maxf(head.size.y, head.size.z)) * 0.5
	_shapes = {"body": [centre, r, h], "head": [hc, hr * 0.9], "height": head.end.y}
	return _shapes
