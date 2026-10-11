class_name NurseModel
extends RefCounted
## L'Infirmière hurlante CUBIQUE (GAME_CONCEPT.md § 4.19 : cubes de 2,5 cm),
## modélisée dans Blender (tools/blender/nurse/nurse_voxel.py) et chargée par
## ZombieGlb comme le Brancardier : un mesh skinné partagé, un draw call,
## couleur par face de cube, yeux et gorge émissifs (lueur rose), dissolution
## cube par cube (shaders des zombies cubiques). Ossature du jeu
## (RigBuilder.BONES), le modèle regarde vers +Z ; seringue sur l'os
## `forearm_r`. Animation : NurseAnim ; zones de touche mesurées sur le
## modèle (hit_shapes).

const MODEL_PATH := "res://assets/models/nurse/nurse_voxel.glb"
const MODEL_CUBE := 0.025
## Lueur des yeux et des cordes vocales : rose maladif (elle se distingue
## des zombies aux yeux jaunes ; la gorge, point faible, se voit de loin).
const EYE_EMISSION := Color(1.0, 0.42, 0.5)
const EYE_ENERGY := 7.0

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
	return mat


static func material() -> ShaderMaterial:
	if _material == null:
		_material = _mat(false)
	return _material


static func dissolve_material() -> ShaderMaterial:
	if _dissolve == null:
		_dissolve = _mat(true)
	return _dissolve


## Dissolution (0 : intacte, 1 : disparue).
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
		push_error("NurseModel : %s introuvable" % MODEL_PATH)
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
##   body : [centre, rayon, hauteur] d'une capsule debout (du bas de la jupe
##          à la base du cou) ;
##   head : [centre dans le repère de l'os head, rayon] (crâne et mâchoire,
##          sans la coiffe) ;
##   throat : [centre dans le repère de l'os neck, rayon] (gorge déchirée :
##          compte comme la tête, point faible) ;
##   height : sommet du crâne (m).
static func hit_shapes() -> Dictionary:
	if not _shapes.is_empty():
		return _shapes
	var bb := bone_bounds()
	if bb.is_empty():
		_shapes = {"body": [Vector3(0, 1.05, 0.0), 0.22, 0.95], "head": [Vector3(0, 0.12, 0.02), 0.14],
			"throat": [Vector3(0, 0.03, 0.06), 0.07], "height": 1.8}
		return _shapes
	var waist: AABB = bb.spine
	var bottom: float = (bb.thigh_l as AABB).end.y - 0.4
	var top: float = (bb.neck as AABB).position.y
	var r := (waist.size.x + waist.size.z) * 0.25 + MODEL_CUBE
	var h := maxf(top - bottom, r * 2.0)
	var centre := Vector3(0.0, (bottom + top) * 0.5, waist.get_center().z)
	var rest := RigBuilder._rest_globals(model().overrides)
	var head: AABB = bb.head.merge(bb.get("jaw", bb.head))
	# Sans la coiffe : le crâne s'arrête au sommet des cheveux (z 73 cubes).
	head.size.y = minf(head.size.y, 73 * MODEL_CUBE - head.position.y)
	var head_origin: Vector3 = (rest.head as Transform3D).origin
	var hc := head.get_center() - head_origin
	var hr := maxf(head.size.x, maxf(head.size.y, head.size.z)) * 0.5
	var neck: AABB = bb.neck
	var neck_origin: Vector3 = (rest.neck as Transform3D).origin
	var tc := Vector3(0.0, neck.get_center().y - neck_origin.y, neck.end.z - 0.04 - neck_origin.z)
	_shapes = {"body": [centre, r, h], "head": [hc, hr * 0.85], "throat": [tc, 0.075], "height": head.end.y}
	return _shapes
