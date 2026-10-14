class_name HellhoundModel
extends RefCounted
## Chien errant contaminé CUBIQUE (GAME_CONCEPT.md § 4.19 : cubes de 2,5 cm),
## modélisé dans Blender (tools/blender/dogs/dog_voxel.py) et chargé par
## ZombieGlb : un mesh skinné partagé, un draw call, couleur par face de cube,
## yeux émissifs, dissolution cube par cube (mêmes shaders que les zombies
## cubiques, matériaux propres : lueur ambre des yeux). Ossature du jeu
## (RigBuilder.BONES) replacée en quadrupède ; le modèle regarde vers +Z.
##
##   hips = bassin (arrière) > spine > chest (avant) > neck > head > jaw
##   arm_* / forearm_* = pattes avant ; thigh_* / shin_* = pattes arrière
##
## Animation : procédurale (DogAnim), hitbox et zone de tête mesurées sur le
## modèle (hit_shapes).

const MODEL_PATH := "res://assets/models/dogs/dog_voxel.glb"
## Côté d'un cube (m) : dissolution cube par cube.
const MODEL_CUBE := 0.025
## Lueur des yeux (ambre de l'infection, plus chaude que celle des zombies).
const EYE_EMISSION := Color(1.0, 0.62, 0.14)
const EYE_ENERGY := 7.0
## Teintes de variante (multiplicateurs, linéaire) : [pelage rgb, peau pelée].
## Légères : une meute de bâtards, pas des clones ; la variante 0 garde la
## palette du modèle.
const TINTS := [
	[Color(1.0, 1.0, 1.0), 1.0],
	[Color(0.78, 0.76, 0.74), 0.95],
	[Color(1.08, 0.94, 0.8), 1.0],
	[Color(0.9, 0.92, 0.96), 1.04],
	[Color(1.12, 1.06, 0.96), 0.92],
	[Color(0.7, 0.62, 0.55), 1.0],
]

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


## Matériau des chiens vivants (sans `discard` : pré-passe et ombres simples).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = _mat(false)
	return _material


## Variante « dissolution » (corps qui disparaît cube par cube).
static func dissolve_material() -> ShaderMaterial:
	if _dissolve == null:
		_dissolve = _mat(true)
	return _dissolve


## Dissolution (0 : intact, 1 : disparu) du maillage d'un chien.
static func set_dissolve(mi: MeshInstance3D, k: float) -> void:
	var want := dissolve_material() if k > 0.0 else material()
	if mi.material_override != want:
		mi.material_override = want
	mi.set_instance_shader_parameter("dissolve", k)


## Modèle chargé ({mesh, overrides}) ; {} si le .glb manque.
static func model() -> Dictionary:
	return ZombieGlb.load_model(MODEL_PATH)


static func build(variant: int) -> Skeleton3D:
	var m := model()
	if m.is_empty():
		push_error("HellhoundModel : %s introuvable" % MODEL_PATH)
		return RigBuilder.instantiate(ArrayMesh.new(), material())
	if _skin == null:
		var tmp := RigBuilder.build_skeleton(m.overrides)
		_skin = tmp.create_skin_from_rest_transforms()
		tmp.free()
		hit_shapes()
	var skel := RigBuilder.instantiate(m.mesh, material(), m.overrides, _skin)
	var mi := skel.get_node("Mesh") as MeshInstance3D
	# Hors des décalques de sang (comme les zombies).
	mi.layers = ZombieModel.RENDER_LAYERS
	var tint: Array = TINTS[posmod(variant, TINTS.size())]
	var c: Color = tint[0]
	mi.set_instance_shader_parameter("look_tint", Color(c.r, c.g, c.b, tint[1]))
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


## Zones de touche mesurées sur le modèle (repère du chien, au repos) :
##   body : [centre, rayon, longueur] d'une capsule couchée le long du dos
##          (bassin, échine, poitrail et cou ; les pattes fines ne comptent
##          pas : elles ne seraient qu'un « coup au corps » de plus) ;
##   head : [centre dans le repère de l'os head, rayon] d'une sphère (crâne
##          et museau, mâchoire comprise).
static func hit_shapes() -> Dictionary:
	if not _shapes.is_empty():
		return _shapes
	var bb := bone_bounds()
	if bb.is_empty():
		return {"body": [Vector3(0, 0.55, 0.0), 0.2, 1.0], "head": [Vector3(0, 0.0, 0.12), 0.15]}
	var trunk: AABB = bb.hips.merge(bb.spine).merge(bb.chest)
	# Rayon : demi-hauteur du tronc (le dos et le poitrail sont touchés),
	# borné par la demi-largeur + un cube (flancs).
	var r := minf(trunk.size.y * 0.5, trunk.size.x * 0.5 + MODEL_CUBE * 2.0)
	var centre := trunk.get_center()
	var length := trunk.size.z
	var head: AABB = bb.head.merge(bb.get("jaw", bb.head))
	var rest := RigBuilder._rest_globals(model().overrides)
	var head_origin: Vector3 = (rest.head as Transform3D).origin
	var hc := head.get_center() - head_origin
	var hr := maxf(head.size.x, maxf(head.size.y, head.size.z)) * 0.5
	_shapes = {"body": [centre, r, length], "head": [hc, hr * 0.85]}
	return _shapes
